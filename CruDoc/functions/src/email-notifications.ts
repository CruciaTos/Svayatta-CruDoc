import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import * as admin from 'firebase-admin';
import * as nodemailer from 'nodemailer';
import * as crypto from 'crypto';
function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

/**
 * Firestore trigger: Fires automatically whenever a new appointment document
 * is created in the top-level `appointments` collection.
 *
 * Fetches patient details to retrieve the patient's email address, renders a
 * responsive HTML confirmation template, and emails it to the patient.
 */
export const sendAppointmentEmailNotification = onDocumentCreated(
  {
    document: 'appointments/{appointmentId}',
    region: 'asia-south1',
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) {
      console.log('No data associated with event');
      return;
    }

    const appointment = snapshot.data();
    const appointmentId = snapshot.id;

    const {
      patientId,
      doctorId,
      scheduledStart,
      visitType,
      treatmentType,
      address,
    } = appointment;

    if (!patientId || !doctorId) {
      console.log(
        `Appointment ${appointmentId} missing patientId or doctorId. Skipping email notification.`,
      );
      return;
    }

    try {
      const db = getDb();
      // 0. Unwrap Doctor's Encryption Key (DEK) to decrypt FieldCipher fields
      const doctorDek = await getDoctorDek(doctorId);

      // 1. Fetch & Decrypt Patient details
      const patientDoc = await db.collection('patients').doc(patientId).get();
      if (!patientDoc.exists) {
        console.log(`Patient ${patientId} not found for appointment ${appointmentId}.`);
        return;
      }

      const patientData = patientDoc.data() || {};
      const rawEmail = patientData.email as string | undefined;
      const rawFirstName = patientData.firstName as string | undefined;
      const rawLastName = patientData.lastName as string | undefined;
      const rawFullName = patientData.fullName as string | undefined;

      const patientEmail = decryptField(rawEmail, doctorDek).trim();
      const firstName = decryptField(rawFirstName, doctorDek).trim();
      const lastName = decryptField(rawLastName, doctorDek).trim();
      const fullName = decryptField(rawFullName, doctorDek).trim();

      const patientName =
        fullName ||
        `${firstName} ${lastName}`.trim() ||
        'Valued Patient';

      if (!patientEmail || !patientEmail.includes('@')) {
        console.log(
          `Patient ${patientName} (${patientId}) has no valid email address configured. Skipping email notification.`,
        );
        return;
      }

      // 2. Fetch Doctor details
      let doctorName = 'Your Doctor';
      let doctorSpecialization = 'Medical Specialist';
      const doctorDoc = await db.collection('users').doc(doctorId).get();
      if (doctorDoc.exists) {
        const docData = doctorDoc.data() || {};
        doctorName =
          (docData.displayName as string) ||
          (docData.name as string) ||
          `Dr. ${docData.lastName || 'Doctor'}`;
        if (docData.specialization) {
          doctorSpecialization = docData.specialization as string;
        }
      }

      // 3. Format Date & Time
      let formattedDate = 'Scheduled Date';
      let formattedTime = 'Scheduled Time';

      if (scheduledStart) {
        let dateObj: Date;
        if (typeof scheduledStart.toDate === 'function') {
          dateObj = scheduledStart.toDate();
        } else if (scheduledStart instanceof Date) {
          dateObj = scheduledStart;
        } else {
          dateObj = new Date(scheduledStart);
        }

        if (!isNaN(dateObj.getTime())) {
          formattedDate = dateObj.toLocaleDateString('en-US', {
            weekday: 'long',
            year: 'numeric',
            month: 'long',
            day: 'numeric',
          });
          formattedTime = dateObj.toLocaleTimeString('en-US', {
            hour: '2-digit',
            minute: '2-digit',
            hour12: true,
          });
        }
      }

      // 4. Generate HTML Email Template
      const isHomeVisit = visitType === 'home';
      const visitTypeName = isHomeVisit ? 'Home Visitation' : 'In-Clinic Consultation';
      const visitAddress = address || (isHomeVisit ? 'Your registered address' : 'Clinic Premises');
      const reasonText = treatmentType || 'General Consultation';

      const htmlContent = renderAppointmentEmailHtml({
        patientName,
        doctorName,
        doctorSpecialization,
        formattedDate,
        formattedTime,
        visitTypeName,
        visitAddress,
        reasonText,
      });

      // 5. Send Email via Gmail SMTP or Resend API
      const gmailUser = process.env.GMAIL_USER;
      const gmailPass = process.env.GMAIL_APP_PASSWORD;

      if (gmailUser && gmailPass) {
        const transporter = nodemailer.createTransport({
          service: 'gmail',
          auth: {
            user: gmailUser,
            pass: gmailPass.replace(/\s+/g, ''),
          },
        });

        const info = await transporter.sendMail({
          from: `"CruDoc Practice" <${gmailUser}>`,
          to: patientEmail,
          subject: `📅 Appointment Confirmation — ${doctorName} | CruDoc`,
          html: htmlContent,
        });

        console.log(
          `Successfully sent Gmail confirmation email to ${patientEmail} for appointment ${appointmentId}. MessageId: ${info.messageId}`,
        );
        return;
      }

      const apiKey = process.env.RESEND_API_KEY;
      if (!apiKey) {
        console.log(
          `[MOCK EMAIL LOG] No GMAIL or RESEND credentials set. Email ready for ${patientName} (${patientEmail}):\n` +
          `Date: ${formattedDate} at ${formattedTime}\nDoctor: ${doctorName}\nLocation: ${visitAddress}`,
        );
        return;
      }

      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: 'CruDoc Practice <onboarding@resend.dev>',
          to: [patientEmail],
          subject: `📅 Appointment Confirmation — ${doctorName} | CruDoc`,
          html: htmlContent,
        }),
      });

      const result = await response.json();

      if (!response.ok) {
        console.error(
          `Resend API error for appointment ${appointmentId}:`,
          JSON.stringify(result),
        );
        return;
      }

      console.log(
        `Successfully sent appointment confirmation email to ${patientEmail} for appointment ${appointmentId}. Resend ID: ${result?.id || 'sent'}`,
      );
    } catch (error) {
      console.error(
        `Failed to send appointment confirmation email for appointment ${appointmentId}:`,
        error,
      );
    }
  },
);

/**
 * Renders a modern, mobile-responsive HTML email template.
 */
function renderAppointmentEmailHtml(params: {
  patientName: string;
  doctorName: string;
  doctorSpecialization: string;
  formattedDate: string;
  formattedTime: string;
  visitTypeName: string;
  visitAddress: string;
  reasonText: string;
}): string {
  const {
    patientName,
    doctorName,
    doctorSpecialization,
    formattedDate,
    formattedTime,
    visitTypeName,
    visitAddress,
    reasonText,
  } = params;

  return `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Appointment Confirmation</title>
  <style>
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif;
      background-color: #f4f6f8;
      margin: 0;
      padding: 0;
      color: #333333;
    }
    .container {
      max-width: 600px;
      margin: 30px auto;
      background: #ffffff;
      border-radius: 12px;
      overflow: hidden;
      box-shadow: 0 4px 15px rgba(0, 0, 0, 0.05);
    }
    .header {
      background: linear-gradient(135deg, #1E88E5 0%, #1565C0 100%);
      color: #ffffff;
      padding: 30px 24px;
      text-align: center;
    }
    .header h1 {
      margin: 0;
      font-size: 24px;
      font-weight: 700;
      letter-spacing: -0.5px;
    }
    .header p {
      margin: 6px 0 0 0;
      font-size: 14px;
      opacity: 0.9;
    }
    .content {
      padding: 30px 24px;
    }
    .greeting {
      font-size: 18px;
      font-weight: 600;
      color: #111827;
      margin-bottom: 12px;
    }
    .subtext {
      font-size: 15px;
      color: #4b5563;
      line-height: 1.5;
      margin-bottom: 24px;
    }
    .card {
      background-color: #f8fafc;
      border: 1px solid #e2e8f0;
      border-radius: 10px;
      padding: 20px;
      margin-bottom: 24px;
    }
    .detail-row {
      display: flex;
      padding: 10px 0;
      border-bottom: 1px solid #edf2f7;
    }
    .detail-row:last-child {
      border-bottom: none;
    }
    .detail-label {
      width: 120px;
      font-weight: 600;
      color: #64748b;
      font-size: 14px;
    }
    .detail-value {
      flex: 1;
      font-weight: 500;
      color: #0f172a;
      font-size: 14px;
    }
    .badge {
      display: inline-block;
      padding: 4px 10px;
      border-radius: 20px;
      font-size: 12px;
      font-weight: 600;
      background-color: #e0f2fe;
      color: #0369a1;
    }
    .notice {
      background-color: #fffbeb;
      border-left: 4px solid #f59e0b;
      padding: 14px 16px;
      border-radius: 4px;
      font-size: 13px;
      color: #92400e;
      line-height: 1.4;
      margin-bottom: 24px;
    }
    .footer {
      background-color: #f8fafc;
      padding: 20px 24px;
      text-align: center;
      font-size: 12px;
      color: #94a3b8;
      border-top: 1px solid #e2e8f0;
    }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>CruDoc Healthcare</h1>
      <p>Appointment Confirmation</p>
    </div>

    <div class="content">
      <div class="greeting">Hello ${escapeHtml(patientName)},</div>
      <div class="subtext">
        Your appointment has been successfully scheduled. Below are your consultation details:
      </div>

      <div class="card">
        <div class="detail-row">
          <div class="detail-label">Doctor</div>
          <div class="detail-value">
            <strong>${escapeHtml(doctorName)}</strong><br>
            <span style="font-size: 12px; color: #64748b;">${escapeHtml(doctorSpecialization)}</span>
          </div>
        </div>

        <div class="detail-row">
          <div class="detail-label">Date</div>
          <div class="detail-value">${escapeHtml(formattedDate)}</div>
        </div>

        <div class="detail-row">
          <div class="detail-label">Time</div>
          <div class="detail-value">${escapeHtml(formattedTime)}</div>
        </div>

        <div class="detail-row">
          <div class="detail-label">Type</div>
          <div class="detail-value">
            <span class="badge">${escapeHtml(visitTypeName)}</span>
          </div>
        </div>

        <div class="detail-row">
          <div class="detail-label">Reason</div>
          <div class="detail-value">${escapeHtml(reasonText)}</div>
        </div>

        <div class="detail-row">
          <div class="detail-label">Location</div>
          <div class="detail-value">${escapeHtml(visitAddress)}</div>
        </div>
      </div>

      <div class="notice">
        📌 <strong>Important Note:</strong> Please arrive 10 minutes prior to your scheduled time. If you need to cancel or reschedule, kindly contact the clinic as early as possible.
      </div>
    </div>

    <div class="footer">
      This is an automated notification from CruDoc Practice Management System.<br>
      © ${new Date().getFullYear()} CruDoc. All rights reserved.
    </div>
  </div>
</body>
</html>
  `;
}

function escapeHtml(text: string): string {
  return text
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

const APP_PEPPER = '7TKgLHp1WG3Mh2yywTCgZWDXJ7rLcwZ161LiZ9ct8SE=';

function deriveKek(doctorId: string): Buffer {
  return crypto.createHash('sha256').update(`${doctorId}::${APP_PEPPER}`).digest();
}

async function getDoctorDek(doctorId: string): Promise<Buffer | null> {
  try {
    const keyDoc = await getDb().collection('doctor_keys').doc(doctorId).get();
    if (!keyDoc.exists) return null;
    const wrappedKey = keyDoc.data()?.wrappedKey as string | undefined;
    if (!wrappedKey || !wrappedKey.includes('.')) return null;

    const parts = wrappedKey.split('.');
    const iv = Buffer.from(parts[0], 'base64');
    const ciphertext = Buffer.from(parts[1], 'base64');

    const authTag = ciphertext.subarray(ciphertext.length - 16);
    const encryptedData = ciphertext.subarray(0, ciphertext.length - 16);

    const kek = deriveKek(doctorId);
    const decipher = crypto.createDecipheriv('aes-256-gcm', kek, iv);
    decipher.setAuthTag(authTag);

    return Buffer.concat([decipher.update(encryptedData), decipher.final()]);
  } catch (e) {
    console.error(`Failed to unwrap DEK for doctor ${doctorId}:`, e);
    return null;
  }
}

function decryptField(value: string | undefined, dek: Buffer | null): string {
  if (!value || !value.startsWith('enc:v1:')) return value || '';
  if (!dek) return value;

  try {
    const body = value.substring('enc:v1:'.length);
    const parts = body.split('.');
    const iv = Buffer.from(parts[0], 'base64');
    const ciphertext = Buffer.from(parts[1], 'base64');

    const authTag = ciphertext.subarray(ciphertext.length - 16);
    const encryptedData = ciphertext.subarray(0, ciphertext.length - 16);

    const decipher = crypto.createDecipheriv('aes-256-gcm', dek, iv);
    decipher.setAuthTag(authTag);

    return Buffer.concat([decipher.update(encryptedData), decipher.final()]).toString('utf8');
  } catch (e) {
    console.error('Failed to decrypt field:', e);
    return value;
  }
}

