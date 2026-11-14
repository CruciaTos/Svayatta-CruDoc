import * as admin from "firebase-admin";
import {getDb} from "./db";
import {getConfig, WhatsAppConfig} from "./config";
import {
  CLINIC_TIME_ZONE, firstNameOf, formatDate, formatTime, fullNameOf,
  istDateKey, istDayRange, normalisePhone,
} from "./format";
import {claimReminder, logSkipped, markFailed, markSent} from "./logs";
import {filterOptedOut} from "./optouts";
import {MetaSendError, sendTemplateMessage} from "./send";
import {APPOINTMENT_REMINDER} from "./templates";
import {decryptField, PatientKeyring} from "../crypto/patientCipher";
import {decryptProfileField} from "../crypto/profileCipher";
import {
  buildClinicContext, ClinicContext, deliver, logSkip,
} from "../reminders/deliver";
import {renderEmail} from "../reminders/settings";
import {recordApiUsage} from "../api-usage";

/**
 * The evening sweep that sends tomorrow's reminders.
 *
 * Runs once at 18:00 IST rather than continuously. The previous design polled
 * every minute for appointments starting in the next ten minutes, which gave
 * the patient no useful warning and ran 1,440 times a day to do it.
 *
 * Nothing here is driven by the doctor. Reminders are on unless a clinic turns
 * them off, which is the whole point: the doctor presses no buttons.
 */

/** The module a clinic must hold for its patients to get reminders. */
const MESSAGING_MODULE = "omnichannel_messaging";

const VISIT_COLLECTIONS = ["appointments", "visitations"] as const;

export interface SweepSummary {
  considered: number;
  sent: number;
  failed: number;
  skipped: Record<string, number>;
}

interface Candidate {
  appointmentId: string;
  doctorId: string;
  patientId: string | null;
  scheduledStart: Date;
  /** Name and phone carried on the visit, used when no patient record exists. */
  inlineName: string | null;
  inlinePhone: string | null;
}

export interface DoctorProfile {
  doctorId: string;
  doctorName: string;
  clinicName: string;
  clinicPhone: string | null;
  eligible: boolean;
  reason?: string;
}

/**
 * Whether a clinic's patients may be messaged.
 *
 * Fails closed. A missing profile, an expired subscription or a missing module
 * all mean no, because sending is spending someone's money and messaging
 * someone who did not agree to it.
 */
export function assessDoctor(
  doctorId: string,
  data: admin.firestore.DocumentData | undefined,
  /** Recalls have their own switch, so they skip the reminders one. */
  requireRemindersOn = true,
): DoctorProfile {
  const base: DoctorProfile = {
    doctorId,
    doctorName: "",
    clinicName: "",
    clinicPhone: null,
    eligible: false,
  };

  if (!data) return {...base, reason: "no_doctor_profile"};

  // Super Admin stores these encrypted (super-admin.ts encryptDoctorValue).
  // Read raw, the reminder greeted patients with ciphertext.
  const plain = (...values: unknown[]) =>
    values.map((v) => decryptProfileField(v, doctorId)).find((v) => v) || "";
  const doctorName = plain(data.displayName, data.name, data.fullName);
  const clinicName = plain(data.clinicName, data.practiceName);
  const clinicPhone = normalisePhone(
    plain(data.clinicPhone, data.phone, data.contactNumber),
  );

  const profile: DoctorProfile = {
    ...base,
    doctorName: doctorName || "your doctor",
    clinicName,
    clinicPhone,
  };

  // The switch is opt-out: absent means on.
  if (requireRemindersOn && data.whatsappRemindersEnabled === false) {
    return {...profile, reason: "reminders_switched_off"};
  }

  const modules: string[] = Array.isArray(data.enabledModules) ?
    data.enabledModules.map((m: unknown) => String(m).toLowerCase()) :
    [];
  if (!modules.includes(MESSAGING_MODULE)) {
    return {...profile, reason: "module_not_enabled"};
  }

  const expiresRaw = data.expiresDate;
  const expiresAt = expiresRaw?.toDate?.() ??
    (typeof expiresRaw === "string" ? new Date(expiresRaw) : null);
  const expired =
    data.status === "expired" ||
    (expiresAt instanceof Date &&
      !isNaN(expiresAt.getTime()) &&
      expiresAt.getTime() < Date.now());
  if (expired) {
    return {...profile, reason: "subscription_expired"};
  }

  // A clinic phone is only needed for WhatsApp (the template tells the
  // patient to ring it); the channel layer checks that itself, email does not.
  if (!clinicName) {
    return {...profile, reason: "no_clinic_name"};
  }

  return {...profile, eligible: true};
}

/**
 * Scheduled visits on one clinic-local day, optionally only those starting at
 * or after `notBefore`.
 */
async function findVisits(
  now: Date,
  dayOffset: number,
  notBefore?: Date,
): Promise<Candidate[]> {
  const db = getDb();
  const day = istDayRange(now, dayOffset);
  const start = notBefore && notBefore > day.start ? notBefore : day.start;
  const end = day.end;
  const out: Candidate[] = [];

  for (const collection of VISIT_COLLECTIONS) {
    const snap = await db
      .collection(collection)
      .where("status", "==", "scheduled")
      .where("scheduledStart", ">=", admin.firestore.Timestamp.fromDate(start))
      .where("scheduledStart", "<", admin.firestore.Timestamp.fromDate(end))
      .get();

    for (const doc of snap.docs) {
      const data = doc.data();
      if (data.isDeleted === true) continue;

      const startsAt = (data.scheduledStart as admin.firestore.Timestamp)
        ?.toDate?.();
      if (!startsAt) continue;

      out.push({
        appointmentId: doc.id,
        doctorId: (data.doctorId || "").toString(),
        patientId: data.patientId ? String(data.patientId) : null,
        scheduledStart: startsAt,
        inlineName: data.patientName ? String(data.patientName) : null,
        inlinePhone: (data.phone || data.patientPhone) ?
          String(data.phone || data.patientPhone) :
          null,
      });
    }
  }

  return out;
}

/** Reads many documents in as few round trips as Firestore allows. */
async function loadAll(
  collection: string,
  ids: string[],
): Promise<Map<string, admin.firestore.DocumentData | undefined>> {
  const db = getDb();
  const unique = [...new Set(ids)].filter(Boolean);
  const out = new Map<string, admin.firestore.DocumentData | undefined>();

  for (let i = 0; i < unique.length; i += 300) {
    const refs = unique
      .slice(i, i + 300)
      .map((id) => db.collection(collection).doc(id));
    const snaps = await db.getAll(...refs);
    for (const s of snaps) out.set(s.id, s.exists ? s.data() : undefined);
  }

  return out;
}

/**
 * Sends tomorrow's reminders.
 *
 * @param now overridable so tests can pick a date without waiting for 18:00.
 */
export async function sendDayBeforeReminders(
  now: Date = new Date(),
): Promise<SweepSummary> {
  return sendReminders(await findVisits(now, 1), "day_before");
}

/** The earliest same-day appointment the morning catch-up reminds about. */
const CATCH_UP_FIRST_HOUR_IST = 10;

/**
 * The 08:00 catch-up: today's appointments from 10:00 onwards that the evening
 * sweep could not see because they were booked after it ran.
 *
 * Anything the evening sweep already sent is skipped by the per-appointment
 * claim, so a patient never gets the same reminder twice.
 */
export async function sendMorningCatchUpReminders(
  now: Date = new Date(),
): Promise<SweepSummary> {
  const today = istDayRange(now, 0);
  const notBefore = new Date(
    today.start.getTime() + CATCH_UP_FIRST_HOUR_IST * 60 * 60 * 1000,
  );
  return sendReminders(await findVisits(now, 0, notBefore), "morning_catch_up");
}

async function sendReminders(
  candidates: Candidate[],
  label: string,
): Promise<SweepSummary> {
  const summary: SweepSummary = {
    considered: 0, sent: 0, failed: 0, skipped: {},
  };
  const skip = (reason: string) => {
    summary.skipped[reason] = (summary.skipped[reason] || 0) + 1;
  };

  summary.considered = candidates.length;
  if (!candidates.length) return summary;

  // The shared CruDoc number, as reminders have always been sent. Without it
  // WhatsApp falls back to the outbox (a clinic's own number) or to email.
  let sharedConfig: WhatsAppConfig | null = null;
  try {
    sharedConfig = getConfig();
  } catch (_) {
    console.error("[reminders] shared WhatsApp number is not configured");
  }

  const doctors = await loadAll(
    "users", candidates.map((c) => c.doctorId),
  );
  const patients = await loadAll(
    "patients",
    candidates.map((c) => c.patientId).filter((p): p is string => !!p),
  );

  const keyring = new PatientKeyring(getDb());

  const profiles = new Map<string, DoctorProfile>();
  for (const [id, data] of doctors) {
    profiles.set(id, assessDoctor(id, data));
  }

  // Resolve every recipient before checking opt-outs, so that check is one
  // batched read rather than one per appointment.
  interface Resolved {
    candidate: Candidate;
    profile: DoctorProfile;
    phone: string | null;
    email: string | null;
    optOutFlag: boolean;
    firstName: string;
    fullName: string;
  }
  const resolved: Resolved[] = [];

  for (const candidate of candidates) {
    const profile = profiles.get(candidate.doctorId);

    if (!profile || !profile.eligible) {
      skip(profile?.reason || "no_doctor_profile");
      continue;
    }

    const patient = candidate.patientId ?
      patients.get(candidate.patientId) :
      undefined;

    // Patient fields are encrypted with the clinic's key. Reading them as
    // they are put ciphertext in the greeting and, worse, turned the
    // encrypted phone into a random foreign number.
    let dek: Buffer | null = null;
    try {
      dek = await keyring.dekFor(
        String(patient?.doctorId || candidate.doctorId),
      );
    } catch (err) {
      console.error(
        `[reminders] cannot unwrap the key for ${candidate.doctorId}: ` +
        `${(err as Error).message}`,
      );
    }
    const plain = (value: unknown) => decryptField(value, dek) ?? "";

    const nameSource = patient ?
      {
        firstName: plain(patient.firstName),
        lastName: plain(patient.lastName),
        fullName: plain(patient.fullName),
      } :
      {fullName: plain(candidate.inlineName)};
    const firstName = firstNameOf(nameSource);
    const fullName = fullNameOf(nameSource);

    if (!firstName) {
      skip("no_patient_name");
      await logSkipped({
        appointmentId: candidate.appointmentId,
        doctorId: candidate.doctorId,
        patientId: candidate.patientId,
        recipientPhone:
          normalisePhone(plain(patient?.phone) || plain(candidate.inlinePhone)),
        reason: "no_patient_name",
      });
      await logSkip(
        candidate.doctorId, "reminder", candidate.appointmentId,
        istDateKey(candidate.scheduledStart), candidate.patientId,
        "no_patient_name",
      );
      continue;
    }

    resolved.push({
      candidate,
      profile,
      phone: normalisePhone(
        plain(patient?.phone) || plain(candidate.inlinePhone),
      ),
      email: plain(patient?.email).trim().toLowerCase() || null,
      optOutFlag: patient?.remindersOptOut === true,
      firstName,
      fullName,
    });
  }

  const optedOut = await filterOptedOut(
    resolved.map((r) => r.phone).filter((p): p is string => !!p),
  );

  const contexts = new Map<string, ClinicContext>();

  for (const r of resolved) {
    const clinicId = r.candidate.doctorId;
    let ctx = contexts.get(clinicId);
    if (!ctx) {
      ctx = await buildClinicContext(
        clinicId, doctors.get(clinicId), r.profile.clinicPhone,
      );
      contexts.set(clinicId, ctx);
    }

    const start = r.candidate.scheduledStart;
    const date = formatDate(start, CLINIC_TIME_ZONE);
    const time = formatTime(start, CLINIC_TIME_ZONE);
    const vars = {
      patient: r.firstName,
      date,
      time,
      clinic: r.profile.clinicName,
      doctor: r.profile.doctorName,
    };

    const waParams = {
      patientFirstName: r.firstName,
      clinicName: r.profile.clinicName,
      doctorName: r.profile.doctorName,
      date,
      time,
      clinicPhone: r.profile.clinicPhone || "",
    };
    const phone = r.phone;
    const shared = sharedConfig;
    // The original send, unchanged: shared number, claim, log, usage.
    const direct = phone && shared ?
      async (): Promise<"sent" | "already"> => {
        const claimed = await claimReminder({
          appointmentId: r.candidate.appointmentId,
          doctorId: r.candidate.doctorId,
          patientId: r.candidate.patientId,
          recipientPhone: phone,
          recipientName: r.fullName,
          clinicName: r.profile.clinicName,
          scheduledStart: r.candidate.scheduledStart,
        });
        if (!claimed) return "already";
        try {
          const {messageId} = await sendTemplateMessage({
            to: phone,
            spec: APPOINTMENT_REMINDER,
            config: shared,
            params: waParams,
          });
          await markSent(r.candidate.appointmentId, messageId);
          await recordApiUsage(r.candidate.doctorId, "whatsapp", "reminder");
          return "sent";
        } catch (err) {
          const meta = err instanceof MetaSendError ? err : null;
          await markFailed(
            r.candidate.appointmentId,
            (err as Error)?.message || "send_failed",
            meta?.code,
          );
          await recordApiUsage(
            r.candidate.doctorId, "whatsapp", "reminder", {error: true},
          );
          throw err;
        }
      } :
      undefined;

    try {
      const result = await deliver(
        ctx,
        {
          patientId: r.candidate.patientId,
          phone: r.phone,
          email: r.email,
          optedOut: r.optOutFlag || (!!r.phone && optedOut.has(r.phone)),
        },
        "reminder",
        {
          refId: r.candidate.appointmentId,
          dayKey: istDateKey(start),
          whatsapp: {
            templateKey: APPOINTMENT_REMINDER.key,
            params: waParams,
            direct,
          },
          email: renderEmail(ctx.settings.email.reminder, vars),
        },
      );

      if (result.status === "sent" || result.status === "queued") {
        summary.sent++;
      } else if (result.status === "failed") {
        summary.failed++;
      } else {
        skip(result.reason || result.status);
        // The feed has always shown skipped reminders; keep it doing so.
        if (result.reason === "opted_out" ||
            (result.reason === "no_channel" && !r.phone)) {
          await logSkipped({
            appointmentId: r.candidate.appointmentId,
            doctorId: r.candidate.doctorId,
            patientId: r.candidate.patientId,
            recipientPhone: r.phone,
            recipientName: r.fullName,
            reason: result.reason === "opted_out" ?
              "opted_out" : "invalid_or_missing_phone",
          });
        }
      }
    } catch (err) {
      summary.failed++;
      console.error(
        `[reminders] reminder failed for ${r.candidate.appointmentId}: ` +
        `${(err as Error)?.message}`,
      );
    }
  }

  console.log(
    `[reminders] ${label} sweep: considered ${summary.considered}, sent ${summary.sent}, ` +
    `failed ${summary.failed}, skipped ${JSON.stringify(summary.skipped)}`,
  );

  return summary;
}
