import * as admin from "firebase-admin";
import {getDb} from "./db";
import {getConfig, WhatsAppNotConfiguredError} from "./config";
import {
  CLINIC_TIME_ZONE, firstNameOf, formatDate, formatTime, fullNameOf,
  istDayRange, normalisePhone,
} from "./format";
import {claimReminder, logSkipped, markFailed, markSent} from "./logs";
import {filterOptedOut} from "./optouts";
import {MetaSendError, sendTemplateMessage} from "./send";
import {APPOINTMENT_REMINDER} from "./templates";

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

interface DoctorProfile {
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
function assessDoctor(
  doctorId: string,
  data: admin.firestore.DocumentData | undefined,
): DoctorProfile {
  const base: DoctorProfile = {
    doctorId,
    doctorName: "",
    clinicName: "",
    clinicPhone: null,
    eligible: false,
  };

  if (!data) return {...base, reason: "no_doctor_profile"};

  const doctorName =
    (data.displayName || data.name || data.fullName || "").toString().trim();
  const clinicName =
    (data.clinicName || data.practiceName || "").toString().trim();
  const clinicPhone = normalisePhone(
    data.clinicPhone || data.phone || data.contactNumber,
  );

  const profile: DoctorProfile = {
    ...base,
    doctorName: doctorName || "your doctor",
    clinicName,
    clinicPhone,
  };

  // The switch is opt-out: absent means on.
  if (data.whatsappRemindersEnabled === false) {
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

  // The reminder tells the patient to ring the clinic to reschedule, so a
  // reminder without a number to ring is worse than none.
  if (!clinicPhone) {
    return {...profile, reason: "no_clinic_phone"};
  }
  if (!clinicName) {
    return {...profile, reason: "no_clinic_name"};
  }

  return {...profile, eligible: true};
}

async function findTomorrowsVisits(now: Date): Promise<Candidate[]> {
  const db = getDb();
  const {start, end} = istDayRange(now, 1);
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
  const summary: SweepSummary = {
    considered: 0, sent: 0, failed: 0, skipped: {},
  };
  const skip = (reason: string) => {
    summary.skipped[reason] = (summary.skipped[reason] || 0) + 1;
  };

  // Fail the whole run loudly rather than per message: an unset token is an
  // operational problem, not something to record against 200 patients.
  let config;
  try {
    config = getConfig();
  } catch (err) {
    if (err instanceof WhatsAppNotConfiguredError) {
      console.error(`[WhatsApp] sweep aborted: ${err.message}`);
      return summary;
    }
    throw err;
  }

  const candidates = await findTomorrowsVisits(now);
  summary.considered = candidates.length;
  if (!candidates.length) return summary;

  const doctors = await loadAll(
    "users", candidates.map((c) => c.doctorId),
  );
  const patients = await loadAll(
    "patients",
    candidates.map((c) => c.patientId).filter((p): p is string => !!p),
  );

  const profiles = new Map<string, DoctorProfile>();
  for (const [id, data] of doctors) {
    profiles.set(id, assessDoctor(id, data));
  }

  // Resolve every recipient before checking opt-outs, so that check is one
  // batched read rather than one per appointment.
  interface Resolved {
    candidate: Candidate;
    profile: DoctorProfile;
    phone: string;
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

    const nameSource = patient ?? {fullName: candidate.inlineName || ""};
    const firstName = firstNameOf(nameSource);
    const fullName = fullNameOf(nameSource);

    const phone = normalisePhone(
      (patient?.phone as string) || candidate.inlinePhone,
    );

    if (!phone) {
      skip("invalid_or_missing_phone");
      await logSkipped({
        appointmentId: candidate.appointmentId,
        doctorId: candidate.doctorId,
        patientId: candidate.patientId,
        recipientName: fullName || null,
        reason: "invalid_or_missing_phone",
      });
      continue;
    }

    if (!firstName) {
      skip("no_patient_name");
      await logSkipped({
        appointmentId: candidate.appointmentId,
        doctorId: candidate.doctorId,
        patientId: candidate.patientId,
        recipientPhone: phone,
        reason: "no_patient_name",
      });
      continue;
    }

    resolved.push({candidate, profile, phone, firstName, fullName});
  }

  const optedOut = await filterOptedOut(resolved.map((r) => r.phone));

  for (const r of resolved) {
    if (optedOut.has(r.phone)) {
      skip("opted_out");
      await logSkipped({
        appointmentId: r.candidate.appointmentId,
        doctorId: r.candidate.doctorId,
        patientId: r.candidate.patientId,
        recipientPhone: r.phone,
        recipientName: r.fullName,
        reason: "opted_out",
      });
      continue;
    }

    const claimed = await claimReminder({
      appointmentId: r.candidate.appointmentId,
      doctorId: r.candidate.doctorId,
      patientId: r.candidate.patientId,
      recipientPhone: r.phone,
      recipientName: r.fullName,
      clinicName: r.profile.clinicName,
      scheduledStart: r.candidate.scheduledStart,
    });

    if (!claimed) {
      skip("already_handled");
      continue;
    }

    try {
      const {messageId} = await sendTemplateMessage({
        to: r.phone,
        spec: APPOINTMENT_REMINDER,
        config,
        params: {
          patientFirstName: r.firstName,
          clinicName: r.profile.clinicName,
          doctorName: r.profile.doctorName,
          date: formatDate(r.candidate.scheduledStart, CLINIC_TIME_ZONE),
          time: formatTime(r.candidate.scheduledStart, CLINIC_TIME_ZONE),
          clinicPhone: r.profile.clinicPhone || "",
        },
      });

      await markSent(r.candidate.appointmentId, messageId);
      summary.sent++;
    } catch (err) {
      const meta = err instanceof MetaSendError ? err : null;
      const reason = (err as Error)?.message || "send_failed";

      // Only the status is written, never a success. A failed send that read
      // as sent was what made the old delivery badges untrustworthy.
      await markFailed(r.candidate.appointmentId, reason, meta?.code);
      summary.failed++;

      console.error(
        `[WhatsApp] reminder failed for ${r.candidate.appointmentId}` +
        `${meta ? ` (code ${meta.code})` : ""}: ${reason}`,
      );
    }
  }

  console.log(
    `[WhatsApp] sweep: considered ${summary.considered}, sent ${summary.sent}, ` +
    `failed ${summary.failed}, skipped ${JSON.stringify(summary.skipped)}`,
  );

  return summary;
}
