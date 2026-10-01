import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {defineSecret} from "firebase-functions/params";
import {dispatchAppointmentWhatsApp} from "./whatsapp";

export const voiceBotApiKeySecret = defineSecret("VOICE_BOT_API_KEY");

// ============================================================
// CLINIC-LOCAL DEFAULTS
// ============================================================

/**
 * Fallbacks used only when the caller does not supply these.
 *
 * The AI voice platform is multi-tenant and owns each clinic's real
 * timezone and business hours (its `Clinic.config`), so it passes them on
 * every request. These defaults exist for callers that don't -- e.g. a
 * manual curl, or the legacy single-tenant bot.
 */
const DEFAULT_TZ_OFFSET_MINUTES = 330; // Asia/Kolkata (+05:30)
const DEFAULT_SLOT_MINUTES = 30;
const DEFAULT_OPEN_TIME = "09:00";
const DEFAULT_CLOSE_TIME = "18:00";

/** Widest appointment we look back for when detecting slot overlap. */
const MAX_APPOINTMENT_MINUTES = 240;

/** Statuses that still occupy a slot on the doctor's calendar. */
const BLOCKING_STATUSES = new Set(["scheduled", "completed"]);

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

function getExpectedVoiceBotKey(): string {
  try {
    const val = voiceBotApiKeySecret.value();
    if (val && val.trim().length > 0) return val.trim();
  } catch (_) {
    // Falls back to process.env in local/emulator environments
  }
  return (process.env.VOICE_BOT_API_KEY || "").trim();
}

// ============================================================
// SHARED REQUEST HELPERS
// ============================================================

/**
 * The slice of the response object this module's helpers need.
 *
 * Declared structurally rather than as `express.Response`, so the
 * functions package needs no `@types/express` dependency of its own and
 * this keeps compiling across firebase-functions major versions (v4 does
 * not re-export a `Response` type from the https namespace).
 */
interface JsonCapableResponse {
  status(code: number): JsonCapableResponse;
  json(body: unknown): unknown;
}

/**
 * Shared `X-Api-Key` gate for every voice-bot endpoint.
 *
 * Returns true when the request is authorised. Otherwise it has already
 * written the error response and the caller must return immediately.
 *
 * Uses a timing-safe comparison so the key cannot be recovered by
 * measuring response times against a guessed prefix.
 */
function authorizeVoiceBot(
  req: functions.Request,
  res: JsonCapableResponse,
): boolean {
  const expectedKey = getExpectedVoiceBotKey();
  if (!expectedKey) {
    console.error(
      "VOICE_BOT_API_KEY not configured in Cloud Functions Secret Manager or env",
    );
    res.status(500).json({success: false, error: "Server misconfiguration"});
    return false;
  }

  const providedKey = req.headers["x-api-key"] as string | undefined;
  if (!providedKey || typeof providedKey !== "string") {
    res.status(401).json({success: false, error: "Unauthorized"});
    return false;
  }

  const providedBuf = Buffer.from(providedKey);
  const expectedBuf = Buffer.from(expectedKey);

  if (
    providedBuf.length !== expectedBuf.length ||
    !crypto.timingSafeEqual(providedBuf, expectedBuf)
  ) {
    res.status(401).json({success: false, error: "Unauthorized"});
    return false;
  }

  return true;
}

/** Reads a string param from either a POST body or a GET query string. */
function readParam(
  src: Record<string, unknown> | undefined,
  key: string,
): string | undefined {
  const value = src?.[key];
  if (typeof value === "string" && value.trim().length > 0) return value.trim();
  if (typeof value === "number") return String(value);
  if (Array.isArray(value)) {
    const first = value[0];
    if (typeof first === "string" && first.trim().length > 0) return first.trim();
  }
  return undefined;
}

/** Reads an integer param, falling back when absent or unparseable. */
function readIntParam(
  src: Record<string, unknown> | undefined,
  key: string,
  fallback: number,
): number {
  const raw = readParam(src, key);
  if (raw === undefined) return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

/**
 * Normalises a time string like "2:30 PM" or "14:30" into "HH:MM"
 * 24-hour format.
 */
function normaliseTime(raw: string): string {
  const trimmed = raw.trim().toUpperCase();

  // Already 24-hour? e.g. "14:30"
  const match24 = trimmed.match(/^(\d{1,2}):(\d{2})$/);
  if (match24) {
    return `${match24[1].padStart(2, "0")}:${match24[2]}`;
  }

  // 12-hour? e.g. "2:30 PM" or "2:30PM"
  const match12 = trimmed.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/);
  if (match12) {
    let hours = parseInt(match12[1], 10);
    const minutes = match12[2];
    const period = match12[3];

    if (period === "PM" && hours !== 12) hours += 12;
    if (period === "AM" && hours === 12) hours = 0;

    return `${hours.toString().padStart(2, "0")}:${minutes}`;
  }

  // Fallback -- return as-is and let the caller's parse handle it
  return trimmed;
}

/**
 * Builds the absolute instant for a clinic-local wall-clock date + time.
 *
 * This must NOT go through `new Date("2026-10-03T10:30:00")`. A date-time
 * string with no offset is interpreted in the *runtime's* zone, which is
 * UTC on Cloud Functions -- so a caller asking for 10:30 got an instant
 * that the Flutter app (which renders `Timestamp.toDate()` in device-local
 * time) displayed as 16:00 IST. Every AI-booked appointment was silently
 * shifted by the clinic's UTC offset. We therefore construct the instant
 * from an explicit offset instead of relying on the ambient zone.
 */
function instantFromClinicLocal(
  date: string,
  time: string,
  tzOffsetMinutes: number,
): Date {
  const dateMatch = date.trim().match(/^(\d{4})-(\d{2})-(\d{2})$/);
  if (!dateMatch) {
    throw new Error(`Invalid date "${date}" -- expected YYYY-MM-DD`);
  }

  const timeMatch = normaliseTime(time).match(/^(\d{2}):(\d{2})$/);
  if (!timeMatch) {
    throw new Error(`Invalid time "${time}" -- expected HH:MM or h:MM AM/PM`);
  }

  const [, year, month, day] = dateMatch;
  const [, hours, minutes] = timeMatch;

  const utcMillis =
    Date.UTC(
      Number(year),
      Number(month) - 1,
      Number(day),
      Number(hours),
      Number(minutes),
    ) - tzOffsetMinutes * 60_000;

  const instant = new Date(utcMillis);
  if (Number.isNaN(instant.getTime())) {
    throw new Error(`Could not build an instant from "${date}" + "${time}"`);
  }
  return instant;
}

/**
 * Resolves the appointment start instant from a request body.
 *
 * Prefers `scheduled_start` (a full ISO 8601 string *with* offset, which is
 * unambiguous) and falls back to the legacy `date` + `time` pair
 * interpreted in the clinic's zone.
 */
function resolveScheduledStart(
  body: Record<string, unknown>,
  tzOffsetMinutes: number,
): Date {
  const iso = readParam(body, "scheduled_start");
  if (iso) {
    const parsed = new Date(iso);
    if (Number.isNaN(parsed.getTime())) {
      throw new Error(
        `Invalid scheduled_start "${iso}" -- expected ISO 8601 with offset`,
      );
    }
    return parsed;
  }

  const date = readParam(body, "date");
  const time = readParam(body, "time");
  if (!date || !time) {
    throw new Error(
      "Provide either scheduled_start (ISO 8601 with offset) or both date and time",
    );
  }
  return instantFromClinicLocal(date, time, tzOffsetMinutes);
}

/**
 * The open slots on a grid across [dayOpen, dayClose), given the intervals
 * already taken.
 *
 * A slot is offered only when it fits entirely inside business hours,
 * overlaps nothing busy, and has not already started -- offering a caller
 * a time that has passed is worse than offering nothing.
 *
 * Kept pure (and exported via `__internal`) because this arithmetic is the
 * part most likely to be quietly wrong, and it should be testable without
 * standing up Firestore.
 */
function computeOpenSlots(
  dayOpen: Date,
  dayClose: Date,
  slotMinutes: number,
  busy: Array<{start: number; end: number}>,
  nowMillis: number,
): Array<{start: string; end: string}> {
  const slots: Array<{start: string; end: string}> = [];
  const stepMillis = slotMinutes * 60_000;
  const closeMillis = dayClose.getTime();

  for (
    let slotStart = dayOpen.getTime();
    slotStart + stepMillis <= closeMillis;
    slotStart += stepMillis
  ) {
    const slotEnd = slotStart + stepMillis;
    if (slotStart <= nowMillis) continue;
    if (busy.some((b) => b.start < slotEnd && slotStart < b.end)) continue;

    slots.push({
      start: new Date(slotStart).toISOString(),
      end: new Date(slotEnd).toISOString(),
    });
  }
  return slots;
}

// ============================================================
// APPOINTMENT CREATION ENDPOINT (for AI Voice Receptionist)
// ============================================================

/**
 * REST endpoint for the AI voice receptionist to create appointments.
 *
 * Authenticates via a shared API key (`X-Api-Key` header) rather than
 * Firebase Auth, since the caller is a backend service, not a
 * browser/mobile client.
 *
 * Accepts either:
 *   - `scheduled_start`: ISO 8601 with offset (preferred, unambiguous), or
 *   - `date` + `time`:   clinic-local wall clock, resolved with
 *                        `tz_offset_minutes` (default +330 / IST).
 *
 * Flow:
 * 1. Validate required fields (patient_name, phone, start, doctor_id).
 * 2. Look up an existing patient by phone number for this doctor. If not
 *    found, create a minimal patient record.
 * 3. Write a document to the top-level `appointments` Firestore
 *    collection, matching the exact shape the Flutter app's
 *    `Visit.fromMap()` expects so it appears in real-time streams
 *    without any app-side changes.
 * 4. Return the new appointment and patient IDs.
 */
export const createAppointment = functions.onRequest(
  {
    region: "asia-south1",
    maxInstances: 10,
    cors: true,
    secrets: [voiceBotApiKeySecret],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({success: false, error: "Method not allowed"});
      return;
    }

    if (!authorizeVoiceBot(req, res)) return;

    const body = (req.body || {}) as Record<string, unknown>;

    const patientName = readParam(body, "patient_name");
    const phone = readParam(body, "phone");
    const doctorId = readParam(body, "doctor_id");
    const reason = readParam(body, "reason");
    const source = readParam(body, "source") || "ai_receptionist";
    const tzOffsetMinutes = readIntParam(
      body,
      "tz_offset_minutes",
      DEFAULT_TZ_OFFSET_MINUTES,
    );
    const durationMinutes = readIntParam(
      body,
      "duration_minutes",
      DEFAULT_SLOT_MINUTES,
    );

    if (!patientName) {
      res.status(400).json({success: false, error: "patient_name is required"});
      return;
    }
    if (!phone) {
      res.status(400).json({success: false, error: "phone is required"});
      return;
    }
    if (!doctorId) {
      res.status(400).json({success: false, error: "doctor_id is required"});
      return;
    }
    if (durationMinutes <= 0) {
      res
        .status(400)
        .json({success: false, error: "duration_minutes must be positive"});
      return;
    }

    let scheduledStart: Date;
    try {
      scheduledStart = resolveScheduledStart(body, tzOffsetMinutes);
    } catch (error) {
      res.status(400).json({
        success: false,
        error: error instanceof Error ? error.message : "Invalid date/time",
      });
      return;
    }

    try {
      // ---- Verify doctor exists ----
      const doctorDoc = await getDb().collection("users").doc(doctorId).get();
      if (!doctorDoc.exists) {
        res.status(404).json({success: false, error: "Doctor not found"});
        return;
      }

      // ---- Reject a slot that is already taken ----
      // The voice platform documents the provider call as the real
      // availability check -- its local UNIQUE(doctor_id, slot_start) is
      // only a last-resort guard, and it cannot see appointments the
      // doctor booked inside the app. Without this check two concurrent
      // callers both get a confirmation for the same slot.
      const scheduledEnd = new Date(
        scheduledStart.getTime() + durationMinutes * 60_000,
      );
      const conflictId = await findConflictingAppointment(
        doctorId,
        scheduledStart,
        scheduledEnd,
      );
      if (conflictId) {
        console.warn(
          `Rejected AI booking for doctor ${doctorId} at ` +
          `${scheduledStart.toISOString()} -- conflicts with ${conflictId}`,
        );
        res.status(409).json({
          success: false,
          error: "Slot no longer available",
          conflict_appointment_id: conflictId,
        });
        return;
      }

      // ---- Find or create patient ----
      const patientId = await findOrCreatePatient(
        doctorId,
        patientName,
        phone,
      );

      // ---- Create appointment ----
      const now = admin.firestore.Timestamp.now();
      const appointmentData: Record<string, unknown> = {
        doctorId: doctorId,
        patientId: patientId,
        scheduledStart: admin.firestore.Timestamp.fromDate(scheduledStart),
        durationMinutes: durationMinutes,
        address: "",
        latitude: null,
        longitude: null,
        mapsLink: null,
        visitType: "clinic",
        status: "scheduled",
        isPaid: false,
        amountCharged: null,
        isDeleted: false,
        invoiceId: null,
        packageId: null,
        treatmentType: reason || null,
        therapistNotes: null,
        reminderStatus: null,
        calendarEventId: null,
        source: source,
        createdAt: now,
        updatedAt: now,
      };

      const appointmentRef = await getDb()
        .collection("appointments")
        .add(appointmentData);

      console.log(
        `AI receptionist created appointment ${appointmentRef.id} ` +
        `for patient ${patientId} under doctor ${doctorId} ` +
        `at ${scheduledStart.toISOString()}`,
      );

      // Asynchronously trigger WhatsApp confirmation without blocking appointment response
      dispatchAppointmentWhatsApp({
        appointmentId: appointmentRef.id,
        doctorId: doctorId,
        patientId: patientId,
        patientName: patientName,
        phone: phone,
        scheduledStart,
        visitType: "clinic",
        source: source,
      }).catch((err) => {
        console.error(`[WhatsApp] Failed to dispatch for appointment ${appointmentRef.id}:`, err);
      });

      res.status(201).json({
        success: true,
        appointment_id: appointmentRef.id,
        patient_id: patientId,
        scheduled_start: scheduledStart.toISOString(),
        duration_minutes: durationMinutes,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : "Unknown error";
      console.error("createAppointment failed:", message);
      res.status(500).json({success: false, error: message});
    }
  },
);

// ============================================================
// AVAILABILITY ENDPOINT (for AI Voice Receptionist)
// ============================================================

/**
 * Returns the doctor's genuinely open slots for one clinic-local day.
 *
 * The voice bot must never invent availability, so this is the single
 * source of truth it reads: a slot grid across the clinic's business
 * hours, minus every appointment already on that doctor's calendar --
 * including ones the doctor booked inside the app, which is exactly what
 * a local-database-only view would miss.
 *
 * Accepts GET (query string) or POST (JSON body):
 *   doctor_id          required -- Firebase UID, matches `users/{uid}`
 *   date               required -- YYYY-MM-DD, clinic-local
 *   open_time          optional -- HH:MM, default 09:00
 *   close_time         optional -- HH:MM, default 18:00
 *   slot_minutes       optional -- default 30
 *   tz_offset_minutes  optional -- default +330 (IST)
 *
 * Responds `{success: true, slots: [{start, end}]}` with instants as UTC
 * ISO 8601 strings, so the caller never has to guess a zone.
 */
export const getAvailability = functions.onRequest(
  {
    region: "asia-south1",
    maxInstances: 10,
    cors: true,
    secrets: [voiceBotApiKeySecret],
  },
  async (req, res) => {
    if (req.method !== "GET" && req.method !== "POST") {
      res.status(405).json({success: false, error: "Method not allowed"});
      return;
    }

    if (!authorizeVoiceBot(req, res)) return;

    const src = (req.method === "GET" ?
      req.query :
      req.body || {}) as Record<string, unknown>;

    const doctorId = readParam(src, "doctor_id");
    const date = readParam(src, "date");

    if (!doctorId) {
      res.status(400).json({success: false, error: "doctor_id is required"});
      return;
    }
    if (!date) {
      res.status(400).json({
        success: false,
        error: "date is required (ISO format, e.g. 2026-10-03)",
      });
      return;
    }

    const tzOffsetMinutes = readIntParam(
      src,
      "tz_offset_minutes",
      DEFAULT_TZ_OFFSET_MINUTES,
    );
    const slotMinutes = readIntParam(src, "slot_minutes", DEFAULT_SLOT_MINUTES);
    const openTime = readParam(src, "open_time") || DEFAULT_OPEN_TIME;
    const closeTime = readParam(src, "close_time") || DEFAULT_CLOSE_TIME;

    if (slotMinutes <= 0) {
      res
        .status(400)
        .json({success: false, error: "slot_minutes must be positive"});
      return;
    }

    let dayOpen: Date;
    let dayClose: Date;
    try {
      dayOpen = instantFromClinicLocal(date, openTime, tzOffsetMinutes);
      dayClose = instantFromClinicLocal(date, closeTime, tzOffsetMinutes);
    } catch (error) {
      res.status(400).json({
        success: false,
        error: error instanceof Error ? error.message : "Invalid date/time",
      });
      return;
    }

    if (dayClose.getTime() <= dayOpen.getTime()) {
      res.status(400).json({
        success: false,
        error: `close_time (${closeTime}) must be after open_time (${openTime})`,
      });
      return;
    }

    try {
      const doctorDoc = await getDb().collection("users").doc(doctorId).get();
      if (!doctorDoc.exists) {
        res.status(404).json({success: false, error: "Doctor not found"});
        return;
      }

      const busy = await loadBusyIntervals(doctorId, dayOpen, dayClose);

      const slots = computeOpenSlots(
        dayOpen,
        dayClose,
        slotMinutes,
        busy,
        Date.now(),
      );

      res.status(200).json({
        success: true,
        doctor_id: doctorId,
        date: date,
        slot_minutes: slotMinutes,
        slots: slots,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      console.error("getAvailability failed:", message);
      res.status(500).json({success: false, error: message});
    }
  },
);

// ============================================================
// CANCELLATION ENDPOINT (for AI Voice Receptionist)
// ============================================================

/**
 * Cancels an appointment the voice bot created.
 *
 * This is a soft delete -- `status: 'cancelled'` plus `isDeleted: true`,
 * matching what the Flutter app writes -- so the slot frees up and the
 * record stays auditable rather than vanishing.
 *
 * The voice platform calls this to unwind a booking when its own
 * double-booking guard rejects the local write *after* the provider
 * booking already succeeded. Without it, that race leaves an orphaned
 * appointment on the doctor's calendar that nobody is expecting.
 *
 * Idempotent: cancelling an already-cancelled appointment succeeds.
 */
export const cancelAppointment = functions.onRequest(
  {
    region: "asia-south1",
    maxInstances: 10,
    cors: true,
    secrets: [voiceBotApiKeySecret],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({success: false, error: "Method not allowed"});
      return;
    }

    if (!authorizeVoiceBot(req, res)) return;

    const body = (req.body || {}) as Record<string, unknown>;
    const appointmentId = readParam(body, "appointment_id");
    const reason = readParam(body, "reason");

    if (!appointmentId) {
      res
        .status(400)
        .json({success: false, error: "appointment_id is required"});
      return;
    }

    try {
      const docRef = getDb().collection("appointments").doc(appointmentId);
      const snapshot = await docRef.get();

      if (!snapshot.exists) {
        res.status(404).json({success: false, error: "Appointment not found"});
        return;
      }

      const existing = snapshot.data() || {};
      const alreadyCancelled = existing.status === "cancelled";

      if (!alreadyCancelled) {
        await docRef.update({
          status: "cancelled",
          isDeleted: true,
          therapistNotes: reason ?
            `Cancelled by AI receptionist: ${reason}` :
            (existing.therapistNotes ?? null),
          updatedAt: admin.firestore.Timestamp.now(),
        });
        console.log(
          `AI receptionist cancelled appointment ${appointmentId}` +
          (reason ? ` (${reason})` : ""),
        );
      }

      res.status(200).json({
        success: true,
        appointment_id: appointmentId,
        already_cancelled: alreadyCancelled,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown error";
      console.error("cancelAppointment failed:", message);
      res.status(500).json({success: false, error: message});
    }
  },
);

// ============================================================
// HELPERS
// ============================================================

/**
 * Loads the intervals on a doctor's calendar that actually occupy time,
 * over [from, until).
 *
 * Only `doctorId` and `scheduledStart` are in the Firestore query so one
 * composite index covers it; `isDeleted` and `status` are filtered here
 * rather than adding index permutations. The lookback widens the window by
 * MAX_APPOINTMENT_MINUTES so an appointment starting before `from` that
 * runs into it is still seen.
 */
async function loadBusyIntervals(
  doctorId: string,
  from: Date,
  until: Date,
): Promise<Array<{id: string; start: number; end: number}>> {
  const queryFrom = new Date(
    from.getTime() - MAX_APPOINTMENT_MINUTES * 60_000,
  );

  const snapshot = await getDb()
    .collection("appointments")
    .where("doctorId", "==", doctorId)
    .where("scheduledStart", ">=", admin.firestore.Timestamp.fromDate(queryFrom))
    .where("scheduledStart", "<", admin.firestore.Timestamp.fromDate(until))
    .get();

  const busy: Array<{id: string; start: number; end: number}> = [];
  for (const doc of snapshot.docs) {
    const data = doc.data();
    if (data.isDeleted === true) continue;

    const status = typeof data.status === "string" ? data.status : "scheduled";
    if (!BLOCKING_STATUSES.has(status)) continue;

    const startTs = data.scheduledStart as admin.firestore.Timestamp | undefined;
    if (!startTs || typeof startTs.toDate !== "function") continue;

    const start = startTs.toDate().getTime();
    const duration =
      typeof data.durationMinutes === "number" && data.durationMinutes > 0 ?
        data.durationMinutes :
        DEFAULT_SLOT_MINUTES;
    busy.push({id: doc.id, start, end: start + duration * 60_000});
  }
  return busy;
}

/**
 * Returns the id of an appointment overlapping [start, end) for this
 * doctor, or null when the slot is free.
 */
async function findConflictingAppointment(
  doctorId: string,
  start: Date,
  end: Date,
): Promise<string | null> {
  const busy = await loadBusyIntervals(doctorId, start, end);
  const startMillis = start.getTime();
  const endMillis = end.getTime();
  const clash = busy.find((b) => b.start < endMillis && startMillis < b.end);
  return clash ? clash.id : null;
}

/**
 * Looks up a patient by phone number for this doctor. If not found,
 * creates a minimal patient record.
 *
 * Phone numbers are stored encrypted in production, but the AI
 * receptionist creates its own records with a plaintext `phone` field so
 * it can look them up. These records are tagged with
 * `source: "ai_receptionist"` so they're distinguishable.
 */
async function findOrCreatePatient(
  doctorId: string,
  name: string,
  phone: string,
): Promise<string> {
  const existing = await getDb()
    .collection("patients")
    .where("doctorId", "==", doctorId)
    .where("phone", "==", phone)
    .where("source", "==", "ai_receptionist")
    .limit(1)
    .get();

  if (!existing.empty) {
    return existing.docs[0].id;
  }

  // Create a minimal patient record
  const now = admin.firestore.Timestamp.now();
  const patientData: Record<string, unknown> = {
    doctorId: doctorId,
    fullName: name,
    phone: phone,
    gender: null,
    dob: null,
    email: null,
    address: null,
    diagnosis: null,
    isArchived: false,
    isDeleted: false,
    source: "ai_receptionist",
    createdAt: now,
    updatedAt: now,
  };

  const patientRef = await getDb().collection("patients").add(patientData);
  console.log(
    `AI receptionist created patient ${patientRef.id} (${name}, ${phone})`,
  );
  return patientRef.id;
}

// ============================================================
// TEST SEAM
// ============================================================

/**
 * Pure helpers exposed for unit tests (see functions/test/).
 *
 * Not a Cloud Function: `firebase deploy` only picks up exports built by
 * the functions SDK, so this object is inert at deploy time.
 */
export const __internal = {
  normaliseTime,
  instantFromClinicLocal,
  computeOpenSlots,
};
