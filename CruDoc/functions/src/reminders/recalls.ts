import * as admin from "firebase-admin";
import {getDb} from "../whatsapp/db";
import {
  CLINIC_TIME_ZONE, firstNameOf, formatDate, istDateKey, istDayRange,
  normalisePhone,
} from "../whatsapp/format";
import {filterOptedOut} from "../whatsapp/optouts";
import {RECALL_REMINDER} from "../whatsapp/templates";
import {assessDoctor, SweepSummary} from "../whatsapp/reminders";
import {decryptField, PatientKeyring} from "../crypto/patientCipher";
import {buildClinicContext, deliver, logSkip} from "./deliver";
import {renderEmail} from "./settings";

/**
 * The daily recall sweep (10:00 IST).
 *
 * A recall is a `dental_records` row of kind "recall": the clinic (or its
 * recall rules, via "Add recall" in the app) set a patient to come back on a
 * date. This sweep messages the patient on that date, for recalls still in the
 * "pending" state. Recall *rules* only suggest recalls inside the app, from the
 * on-device procedure log (procedure_log_entries is not synced), so the server
 * acts on the recalls those rules produced rather than re-deriving them.
 *
 * Window: due today, or up to 14 days ago. Older ones are left for the clinic;
 * a recall months late reads as an error, not a reminder.
 *
 * Not already recalled in that cycle: the log document id is
 * recall_<recordId>_<due date>, so each recall goes out once. At most 200 per
 * clinic per day, oldest due first.
 *
 * The recall rows are never edited from here: their data is encrypted with the
 * clinic's key and the app owns it. Sent status lives in the reminder log.
 */

const DAILY_LIMIT_PER_CLINIC = 200;
const OVERDUE_GRACE_DAYS = 14;

interface RecallRow {
  id: string;
  doctorId: string;
  patientId: string;
  due: Date;
  reason: string;
}

export async function sendDueRecalls(
  now: Date = new Date(),
): Promise<SweepSummary> {
  const summary: SweepSummary = {
    considered: 0, sent: 0, failed: 0, skipped: {},
  };
  const skip = (reason: string) => {
    summary.skipped[reason] = (summary.skipped[reason] || 0) + 1;
  };
  const db = getDb();

  const today = istDayRange(now, 0);
  const earliest = new Date(
    today.start.getTime() - OVERDUE_GRACE_DAYS * 24 * 60 * 60 * 1000,
  );

  // Two equality filters need no composite index; the date window is applied
  // in memory. Add (kind, isDeleted, recordedAt) if recall volume grows.
  const snap = await db.collection("dental_records")
    .where("kind", "==", "recall")
    .where("isDeleted", "==", false)
    .get();

  const byClinic = new Map<string, admin.firestore.QueryDocumentSnapshot[]>();
  for (const doc of snap.docs) {
    const data = doc.data();
    const due = (data.recordedAt as admin.firestore.Timestamp)?.toDate?.();
    if (!due || due < earliest || due >= today.end) continue;
    const clinicId = String(data.doctorId || "");
    if (!clinicId) continue;
    const list = byClinic.get(clinicId) ?? [];
    list.push(doc);
    byClinic.set(clinicId, list);
  }

  const keyring = new PatientKeyring(db);

  for (const [clinicId, docs] of byClinic) {
    const userSnap = await db.collection("users").doc(clinicId).get();
    const userData = userSnap.exists ? userSnap.data() : undefined;
    const profile = assessDoctor(clinicId, userData, false);
    if (!profile.eligible) {
      summary.considered += docs.length;
      skip(profile.reason || "not_eligible");
      continue;
    }

    const ctx = await buildClinicContext(clinicId, userData, profile.clinicPhone);
    if (!ctx.settings.recallsEnabled) continue;

    let dek: Buffer | null = null;
    try {
      dek = await keyring.dekFor(clinicId);
    } catch (err) {
      console.error(
        `[recalls] cannot unwrap the key for ${clinicId}: ${(err as Error).message}`,
      );
    }

    // Only recalls still "pending"; anything the clinic marked sent, booked or
    // cancelled by hand is theirs to manage.
    const rows: RecallRow[] = [];
    for (const doc of docs) {
      const raw = decryptField(doc.data().data, dek);
      let payload: Record<string, unknown> = {};
      try {
        const parsed = JSON.parse(raw || "{}");
        if (parsed && typeof parsed === "object") payload = parsed;
      } catch (_) {
        // Unreadable: treated as no status, so skipped below.
      }
      const status = String(payload.status || "");
      if (status && status !== "pending") continue;
      if (!raw) {
        summary.considered++;
        skip("unreadable_record");
        continue;
      }
      const data = doc.data();
      rows.push({
        id: doc.id,
        doctorId: clinicId,
        patientId: String(data.patientId || ""),
        due: (data.recordedAt as admin.firestore.Timestamp).toDate(),
        reason: String(payload.reason || "").toLowerCase(),
      });
    }

    rows.sort((a, b) => a.due.getTime() - b.due.getTime());
    const todays = rows.slice(0, DAILY_LIMIT_PER_CLINIC);
    if (rows.length > todays.length) {
      skip("over_daily_limit");
    }
    summary.considered += todays.length;
    if (!todays.length) continue;

    const patientSnaps = await db.getAll(
      ...[...new Set(todays.map((r) => r.patientId))]
        .filter(Boolean)
        .map((id) => db.collection("patients").doc(id)),
    );
    const patients = new Map(
      patientSnaps.map((s) => [s.id, s.exists ? s.data() : undefined]),
    );

    interface Ready {
      row: RecallRow;
      firstName: string;
      phone: string | null;
      email: string | null;
      optOutFlag: boolean;
    }
    const ready: Ready[] = [];
    for (const row of todays) {
      const patient = patients.get(row.patientId);
      const plain = (v: unknown) => decryptField(v, dek) ?? "";
      const firstName = patient ? firstNameOf({
        firstName: plain(patient.firstName),
        lastName: plain(patient.lastName),
        fullName: plain(patient.fullName),
      }) : "";
      if (!patient || !firstName) {
        skip("no_patient_name");
        await logSkip(
          clinicId, "recall", row.id, istDateKey(row.due), row.patientId || null,
          "no_patient_name",
        );
        continue;
      }
      ready.push({
        row,
        firstName,
        phone: normalisePhone(plain(patient.phone)),
        email: plain(patient.email).trim().toLowerCase() || null,
        optOutFlag: patient.remindersOptOut === true,
      });
    }

    const optedOut = await filterOptedOut(
      ready.map((r) => r.phone).filter((p): p is string => !!p),
    );

    for (const r of ready) {
      const date = formatDate(r.row.due, CLINIC_TIME_ZONE);
      const vars = {
        patient: r.firstName,
        date,
        time: "",
        clinic: profile.clinicName,
        doctor: profile.doctorName,
        reason: r.row.reason,
      };
      try {
        const result = await deliver(
          ctx,
          {
            patientId: r.row.patientId,
            phone: r.phone,
            email: r.email,
            optedOut: r.optOutFlag || (!!r.phone && optedOut.has(r.phone)),
          },
          "recall",
          {
            refId: r.row.id,
            dayKey: istDateKey(r.row.due),
            whatsapp: {
              templateKey: RECALL_REMINDER.key,
              params: {
                patientFirstName: r.firstName,
                clinicName: profile.clinicName,
                doctorName: profile.doctorName,
                date,
                clinicPhone: profile.clinicPhone || "",
              },
            },
            email: renderEmail(ctx.settings.email.recall, vars),
          },
        );
        if (result.status === "sent" || result.status === "queued") {
          summary.sent++;
        } else if (result.status === "failed") {
          summary.failed++;
        } else {
          skip(result.reason || result.status);
        }
      } catch (err) {
        summary.failed++;
        console.error(
          `[recalls] failed for ${r.row.id}: ${(err as Error)?.message}`,
        );
      }
    }
  }

  console.log(
    `[recalls] sweep: considered ${summary.considered}, sent ${summary.sent}, ` +
    `failed ${summary.failed}, skipped ${JSON.stringify(summary.skipped)}`,
  );
  return summary;
}
