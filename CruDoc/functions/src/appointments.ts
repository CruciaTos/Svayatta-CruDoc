import * as functions from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
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
 * Flow:
 * 1. Validate required fields (patient_name, phone, date, time, doctor_id).
 * 2. Look up an existing patient by phone number under the doctor's
 *    patients collection. If not found, create a minimal patient record.
 * 3. Write a document to the top-level `appointments` Firestore
 *    collection, matching the exact shape the Flutter app's
 *    `Visit.fromMap()` expects so it appears in real-time streams
 *    without any app-side changes.
 * 4. Return the new appointment and patient IDs.
 */
export const createAppointment = functions.onRequest(
  {
    region: 'asia-south1',
    maxInstances: 10,
    cors: true,
  },
  async (req, res) => {
    // ---- Method check ----
    if (req.method !== 'POST') {
      res.status(405).json({success: false, error: 'Method not allowed'});
      return;
    }

    // ---- API-key auth ----
    const expectedKey = process.env.VOICE_BOT_API_KEY;
    if (!expectedKey) {
      console.error('VOICE_BOT_API_KEY not configured in Cloud Functions env');
      res.status(500).json({success: false, error: 'Server misconfiguration'});
      return;
    }

    const providedKey =
      req.headers['x-api-key'] as string | undefined;
    if (!providedKey || providedKey !== expectedKey) {
      res.status(401).json({success: false, error: 'Unauthorized'});
      return;
    }

    // ---- Parse & validate body ----
    const {
      patient_name,
      phone,
      date,
      time,
      reason,
      source,
      doctor_id,
    } = req.body;

    if (!patient_name || typeof patient_name !== 'string') {
      res.status(400).json({success: false, error: 'patient_name is required'});
      return;
    }
    if (!phone || typeof phone !== 'string') {
      res.status(400).json({success: false, error: 'phone is required'});
      return;
    }
    if (!date || typeof date !== 'string') {
      res.status(400).json({success: false, error: 'date is required (ISO format, e.g. 2026-08-15)'});
      return;
    }
    if (!time || typeof time !== 'string') {
      res.status(400).json({success: false, error: 'time is required (e.g. 10:30)'});
      return;
    }
    if (!doctor_id || typeof doctor_id !== 'string') {
      res.status(400).json({success: false, error: 'doctor_id is required'});
      return;
    }

    // ---- Parse date + time into a Firestore Timestamp ----
    // Expected formats: date = "2026-08-15", time = "10:30" or "10:30 AM"
    let scheduledStart: Date;
    try {
      // Normalise 12-hour time ("2:30 PM") to 24-hour if needed
      const normalised = normaliseTime(time);
      scheduledStart = new Date(`${date}T${normalised}:00`);
      if (isNaN(scheduledStart.getTime())) {
        throw new Error('Invalid date');
      }
    } catch {
      res.status(400).json({
        success: false,
        error: `Could not parse date "${date}" + time "${time}". Use ISO date (2026-08-15) and 24h or 12h time (14:30 or 2:30 PM).`,
      });
      return;
    }

    try {
      // ---- Verify doctor exists ----
      const doctorDoc = await getDb().collection('users').doc(doctor_id).get();
      if (!doctorDoc.exists) {
        res.status(404).json({success: false, error: 'Doctor not found'});
        return;
      }

      // ---- Find or create patient ----
      const patientId = await findOrCreatePatient(
        doctor_id,
        patient_name.trim(),
        phone.trim(),
      );

      // ---- Create appointment ----
      const now = admin.firestore.Timestamp.now();
      const appointmentData: Record<string, unknown> = {
        doctorId: doctor_id,
        patientId: patientId,
        scheduledStart: admin.firestore.Timestamp.fromDate(scheduledStart),
        durationMinutes: 30,
        address: '',
        latitude: null,
        longitude: null,
        mapsLink: null,
        visitType: 'clinic',
        status: 'scheduled',
        isPaid: false,
        amountCharged: null,
        isDeleted: false,
        invoiceId: null,
        packageId: null,
        treatmentType: reason || null,
        therapistNotes: null,
        reminderStatus: null,
        calendarEventId: null,
        source: source || 'ai_receptionist',
        createdAt: now,
        updatedAt: now,
      };

      const appointmentRef = await getDb()
        .collection('appointments')
        .add(appointmentData);

      console.log(
        `AI receptionist created appointment ${appointmentRef.id} ` +
        `for patient ${patientId} under doctor ${doctor_id}`,
      );

      res.status(201).json({
        success: true,
        appointment_id: appointmentRef.id,
        patient_id: patientId,
      });
    } catch (error) {
      const message =
        error instanceof Error ? error.message : 'Unknown error';
      console.error('createAppointment failed:', message);
      res.status(500).json({success: false, error: message});
    }
  },
);

// ============================================================
// HELPERS
// ============================================================

/**
 * Looks up a patient by phone number in the doctor's top-level
 * `appointments`-style patients collection. If not found, creates a
 * minimal patient record.
 *
 * The Flutter app stores patients either in a subcollection
 * (`users/{doctorId}/patients`) or a top-level `patients` collection
 * filtered by `doctorId` — this uses the top-level approach to match
 * the `_watchWebVisits` pattern in `visits_repo.dart`.
 */
async function findOrCreatePatient(
  doctorId: string,
  name: string,
  phone: string,
): Promise<string> {
  // Try to find an existing patient by phone for this doctor.
  // Phone numbers are stored encrypted in production, but the AI
  // receptionist creates its own records with a plaintext `phone`
  // field so it can look them up. These records are tagged with
  // `source: "ai_receptionist"` so they're distinguishable.
  const existing = await getDb()
    .collection('patients')
    .where('doctorId', '==', doctorId)
    .where('phone', '==', phone)
    .where('source', '==', 'ai_receptionist')
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
    source: 'ai_receptionist',
    createdAt: now,
    updatedAt: now,
  };

  const patientRef = await getDb().collection('patients').add(patientData);
  console.log(
    `AI receptionist created patient ${patientRef.id} (${name}, ${phone})`,
  );
  return patientRef.id;
}

/**
 * Normalises a time string like "2:30 PM" or "14:30" into "HH:MM"
 * 24-hour format for Date parsing.
 */
function normaliseTime(raw: string): string {
  const trimmed = raw.trim().toUpperCase();

  // Already 24-hour? e.g. "14:30"
  const match24 = trimmed.match(/^(\d{1,2}):(\d{2})$/);
  if (match24) {
    return `${match24[1].padStart(2, '0')}:${match24[2]}`;
  }

  // 12-hour? e.g. "2:30 PM" or "2:30PM"
  const match12 = trimmed.match(/^(\d{1,2}):(\d{2})\s*(AM|PM)$/);
  if (match12) {
    let hours = parseInt(match12[1], 10);
    const minutes = match12[2];
    const period = match12[3];

    if (period === 'PM' && hours !== 12) hours += 12;
    if (period === 'AM' && hours === 12) hours = 0;

    return `${hours.toString().padStart(2, '0')}:${minutes}`;
  }

  // Fallback — return as-is and let the caller's Date parse handle it
  return trimmed;
}
