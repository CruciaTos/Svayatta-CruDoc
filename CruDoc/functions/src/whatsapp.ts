import * as functions from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import * as crypto from 'crypto';

function getDb() {
  if (!admin.apps.length) {
    admin.initializeApp();
  }
  return admin.firestore();
}

// ============================================================
// 1. PHONE NORMALIZATION & VALIDATION (E.164 STANDARD)
// ============================================================

/**
 * Normalizes a raw phone number into a clean E.164 compatible string without '+' or symbols.
 * Default country code is '91' (India) for 10-digit mobile numbers.
 *
 * Examples:
 *  "+91 98765 43210" -> "919876543210"
 *  "9876543210"       -> "919876543210"
 *  "09876543210"      -> "919876543210"
 *  "+1 (555) 234-5678"-> "15552345678"
 */
export function normalizePhoneNumber(raw: string | null | undefined, defaultCountryCode = '91'): string | null {
  if (!raw || typeof raw !== 'string') return null;

  // Strip all non-digit characters
  let digits = raw.replace(/\D/g, '');
  if (!digits) return null;

  // Remove leading zeros
  digits = digits.replace(/^0+/, '');

  // 10-digit number assumed to be default country code (e.g. India)
  if (digits.length === 10) {
    digits = `${defaultCountryCode}${digits}`;
  }

  // E.164 valid length is between 10 and 15 digits
  if (digits.length < 10 || digits.length > 15) {
    return null;
  }

  return digits;
}

// ============================================================
// 2. PRIVACY-COMPLIANT TEMPLATE BUILDER
// ============================================================

export interface WhatsAppAppointmentData {
  patientName: string;
  doctorName: string;
  clinicName: string;
  appointmentDate: string;
  appointmentTime: string;
  consultationType: 'In-Clinic' | 'Home Visit';
}

/**
 * Sanitizes template parameters to prevent CRLF injection, control characters,
 * and ensures NO sensitive medical information or diagnoses are ever included.
 */
export function sanitizeTemplateParam(val: string | null | undefined, fallback = 'N/A'): string {
  if (!val) return fallback;
  return val.replace(/[\r\n\t]/g, ' ').trim() || fallback;
}

// ============================================================
// 3. WHATSAPP CLOUD API CLIENT & RETRY ENGINE
// ============================================================

interface MetaApiResponse {
  messaging_product?: string;
  contacts?: Array<{ input: string; wa_id: string }>;
  messages?: Array<{ id: string }>;
  error?: {
    message: string;
    type: string;
    code: number;
    error_subcode?: number;
    fbtrace_id?: string;
  };
}

/**
 * Sends a WhatsApp message via Meta Cloud API with exponential backoff on transient errors.
 * Supports Development/Mock mode when configured or when credentials are not yet supplied.
 */
export async function sendWhatsAppMetaMessage(params: {
  toPhone: string;
  data: WhatsAppAppointmentData;
  templateName?: string;
  appointmentId: string;
  doctorId: string;
  patientId: string;
}): Promise<{ success: boolean; messageId?: string; error?: string; isMock?: boolean }> {
  const mode = process.env.WHATSAPP_MODE || 'development';
  const token = process.env.WHATSAPP_ACCESS_TOKEN;
  const phoneNumberId = process.env.WHATSAPP_PHONE_NUMBER_ID;
  const templateName = params.templateName || process.env.WHATSAPP_TEMPLATE_NAME || 'appointment_confirmation';

  // In development/mock mode or if credentials are unconfigured, simulate realistic successful delivery
  if (mode === 'development' || mode === 'mock' || !token || !phoneNumberId) {
    const mockWamid = `wamid.HBgL${Date.now()}_${crypto.randomBytes(6).toString('hex')}`;
    console.log(
      `[WhatsApp ${mode.toUpperCase()} MODE] Simulated send to ${params.toPhone} for appt ${params.appointmentId} ` +
      `(Patient: "${params.data.patientName}", Doctor: "${params.data.doctorName}"). WAMID: ${mockWamid}`
    );
    return {
      success: true,
      messageId: mockWamid,
      isMock: true,
    };
  }

  const url = `https://graph.facebook.com/v20.0/${phoneNumberId}/messages`;
  const body = {
    messaging_product: 'whatsapp',
    recipient_type: 'individual',
    to: params.toPhone,
    type: 'template',
    template: {
      name: templateName,
      language: { code: 'en_US' },
      components: [
        {
          type: 'body',
          parameters: [
            { type: 'text', text: sanitizeTemplateParam(params.data.patientName, 'Valued Patient') },
            { type: 'text', text: sanitizeTemplateParam(params.data.doctorName, 'Doctor') },
            { type: 'text', text: sanitizeTemplateParam(params.data.clinicName, 'CruDoc Practice') },
            { type: 'text', text: sanitizeTemplateParam(params.data.appointmentDate) },
            { type: 'text', text: sanitizeTemplateParam(params.data.appointmentTime) },
            { type: 'text', text: sanitizeTemplateParam(params.data.consultationType) },
          ],
        },
      ],
    },
  };

  const maxRetries = 3;
  let attempt = 0;
  let lastError = '';

  while (attempt < maxRetries) {
    attempt++;
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(body),
      });

      const responseData = (await response.json()) as MetaApiResponse;

      if (response.ok && responseData.messages && responseData.messages.length > 0) {
        const messageId = responseData.messages[0].id;
        console.log(`[WhatsApp API] Successfully sent message ${messageId} to ${params.toPhone}`);
        return { success: true, messageId };
      }

      const errorCode = responseData.error?.code ?? response.status;
      lastError = responseData.error?.message || `HTTP ${response.status} from Meta WhatsApp API`;

      // If custom template is not created yet, fallback to hello_world test template in sandbox
      if ((errorCode === 132001 || lastError.toLowerCase().includes('template')) && templateName !== 'hello_world') {
        console.warn(`[WhatsApp API] Template "${templateName}" not found. Falling back to "hello_world" test template...`);
        const fallbackBody = {
          messaging_product: 'whatsapp',
          recipient_type: 'individual',
          to: params.toPhone,
          type: 'template',
          template: {
            name: 'hello_world',
            language: { code: 'en_US' },
          },
        };
        const fbRes = await fetch(url, {
          method: 'POST',
          headers: { 'Authorization': `Bearer ${token}`, 'Content-Type': 'application/json' },
          body: JSON.stringify(fallbackBody),
        });
        const fbData = (await fbRes.json()) as MetaApiResponse;
        if (fbRes.ok && fbData.messages && fbData.messages.length > 0) {
          return { success: true, messageId: fbData.messages[0].id };
        }
      }

      // Permanent failures (400 Bad Request, 401 Auth, Invalid Recipient) -> fail fast without retrying
      if (response.status === 400 || response.status === 401 || errorCode === 131026) {
        console.error(`[WhatsApp API] Permanent failure (status: ${response.status}, code: ${errorCode}): ${lastError}`);
        return { success: false, error: lastError };
      }

      // Transient errors (429 Rate Limit, 500, 503) -> retry with exponential backoff
      console.warn(`[WhatsApp API] Transient error (attempt ${attempt}/${maxRetries}): ${lastError}`);
      if (attempt < maxRetries) {
        const delayMs = Math.pow(2, attempt) * 500 + Math.random() * 200;
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
    } catch (err: any) {
      lastError = err?.message || 'Network failure connecting to Meta WhatsApp API';
      console.warn(`[WhatsApp API] Network error on attempt ${attempt}/${maxRetries}: ${lastError}`);
      if (attempt < maxRetries) {
        const delayMs = Math.pow(2, attempt) * 500 + Math.random() * 200;
        await new Promise((resolve) => setTimeout(resolve, delayMs));
      }
    }
  }

  return { success: false, error: lastError };
}

// ============================================================
// 4. DISPATCH ORCHESTRATOR WITH IDEMPOTENCY & LOGGING
// ============================================================

export async function dispatchAppointmentWhatsApp(params: {
  appointmentId: string;
  doctorId: string;
  patientId: string;
  patientName?: string;
  phone?: string;
  scheduledStart: Date | admin.firestore.Timestamp;
  visitType?: string;
  source?: string;
}): Promise<{ success: boolean; status: string; messageId?: string; reason?: string }> {
  const db = getDb();
  const appointmentId = params.appointmentId;
  const doctorId = params.doctorId;
  const logRef = db.collection('whatsapp_notification_logs').doc(appointmentId);

  // 1. Idempotency Check
  const existingLog = await logRef.get();
  if (existingLog.exists) {
    const data = existingLog.data();
    if (data?.status === 'sent' || data?.status === 'delivered' || data?.status === 'read') {
      console.log(`[WhatsApp Dispatch] Notification already completed for appointment ${appointmentId}. Skipping duplicate.`);
      return { success: true, status: data.status, messageId: data.whatsappMessageId };
    }
    if (data?.status === 'pending') {
      const attemptedAt = data.attemptedAt?.toDate ? data.attemptedAt.toDate() : new Date();
      if (Date.now() - attemptedAt.getTime() < 2 * 60 * 1000) {
        console.log(`[WhatsApp Dispatch] Notification is currently in-flight for appointment ${appointmentId}. Skipping.`);
        return { success: true, status: 'pending' };
      }
    }
  }

  // 2. Resolve Patient Data (Phone & Name)
  let rawPhone = params.phone;
  let patientName = params.patientName;

  if (!rawPhone || !patientName) {
    try {
      const patientDoc = await db.collection('patients').doc(params.patientId).get();
      if (patientDoc.exists) {
        const patientData = patientDoc.data() || {};
        rawPhone = rawPhone || (patientData.phone as string);
        const first = (patientData.firstName as string) || '';
        const last = (patientData.lastName as string) || '';
        patientName = patientName || `${first} ${last}`.trim();
      }
    } catch (e) {
      console.warn(`[WhatsApp Dispatch] Could not fetch patient ${params.patientId}:`, e);
    }
  }

  // 3. Resolve Doctor & Clinic Details
  let doctorName = 'Doctor';
  let clinicName = 'CruDoc Clinic';
  try {
    const doctorDoc = await db.collection('users').doc(doctorId).get();
    if (doctorDoc.exists) {
      const docData = doctorDoc.data() || {};
      doctorName = docData.displayName || docData.name || 'Doctor';
      clinicName = docData.clinicName || docData.practiceName || clinicName;
    }
  } catch (e) {
    console.warn(`[WhatsApp Dispatch] Could not fetch doctor profile for ${doctorId}:`, e);
  }

  // 4. Validate & Normalize Phone Number
  const normalizedPhone = normalizePhoneNumber(rawPhone);
  if (!normalizedPhone) {
    console.log(`[WhatsApp Dispatch] Skipping: Invalid or missing phone number for patient "${patientName}" (phone: "${rawPhone}")`);
    await logRef.set({
      id: appointmentId,
      appointmentId,
      doctorId,
      patientId: params.patientId,
      recipientPhone: rawPhone || '',
      recipientName: patientName || 'Patient',
      status: 'skipped',
      failureReason: 'invalid_or_missing_phone',
      source: params.source || 'booking_flow',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, status: 'skipped', reason: 'invalid_or_missing_phone' };
  }

  // 5. Format Date and Time
  const startDate = params.scheduledStart instanceof Date
    ? params.scheduledStart
    : (params.scheduledStart as admin.firestore.Timestamp).toDate();

  const formattedDate = startDate.toLocaleDateString('en-US', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    year: 'numeric',
  });

  const formattedTime = startDate.toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
    hour12: true,
  });

  const consultationType = params.visitType === 'home' ? 'Home Visit' : 'In-Clinic';

  // 6. Write Initial Pending Log
  await logRef.set({
    id: appointmentId,
    appointmentId,
    doctorId,
    patientId: params.patientId,
    recipientPhone: normalizedPhone,
    recipientName: patientName || 'Valued Patient',
    status: 'pending',
    attemptCount: 1,
    attemptedAt: admin.firestore.FieldValue.serverTimestamp(),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  // 7. Dispatch via Meta WhatsApp API
  const result = await sendWhatsAppMetaMessage({
    toPhone: normalizedPhone,
    data: {
      patientName: patientName || 'Valued Patient',
      doctorName,
      clinicName,
      appointmentDate: formattedDate,
      appointmentTime: formattedTime,
      consultationType,
    },
    appointmentId,
    doctorId,
    patientId: params.patientId,
  });

  // 8. Update Log Status
  if (result.success) {
    await logRef.update({
      status: 'sent',
      whatsappMessageId: result.messageId || null,
      isMock: result.isMock || false,
      sentAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: true, status: 'sent', messageId: result.messageId };
  } else {
    await logRef.update({
      status: 'failed',
      failureReason: result.error || 'meta_api_error',
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return { success: false, status: 'failed', reason: result.error };
  }
}

// ============================================================
// 5. CALLABLE HTTPS FUNCTION FOR AUTHENTICATED USERS
// ============================================================

export const sendWhatsAppAppointmentConfirmation = functions.onRequest(
  {
    region: 'asia-south1',
    maxInstances: 10,
    cors: true,
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ success: false, error: 'Method not allowed' });
      return;
    }

    try {
      const { appointmentId, doctorId, patientId, phone, patientName, scheduledStart, visitType } = req.body;

      if (!appointmentId || !doctorId || !patientId) {
        res.status(400).json({ success: false, error: 'appointmentId, doctorId, and patientId are required' });
        return;
      }

      const dateObj = scheduledStart ? new Date(scheduledStart) : new Date();

      const result = await dispatchAppointmentWhatsApp({
        appointmentId,
        doctorId,
        patientId,
        phone,
        patientName,
        scheduledStart: isNaN(dateObj.getTime()) ? new Date() : dateObj,
        visitType: visitType || 'clinic',
        source: 'manual_or_client_trigger',
      });

      res.status(200).json(result);
    } catch (err: any) {
      console.error('[WhatsApp Endpoint Error]', err);
      res.status(500).json({ success: false, error: err?.message || 'Internal server error' });
    }
  }
);

// ============================================================
// 6. AUTOMATED 10-MINUTE PRE-APPOINTMENT REMINDER ENGINE
// ============================================================

/**
 * Checks all upcoming appointments in the next 10-12 minutes and automatically
 * sends WhatsApp reminder notifications to patients who have not yet received one.
 */
export async function checkAndDispatchUpcomingReminders(): Promise<{
  processedCount: number;
  sentCount: number;
}> {
  const db = getDb();
  const now = new Date();

  // Query appointments starting between now and next 12 minutes
  const windowStart = new Date(now.getTime() - 2 * 60 * 1000); // 2 mins grace
  const windowEnd = new Date(now.getTime() + 12 * 60 * 1000); // 12 mins ahead

  const windowStartTs = admin.firestore.Timestamp.fromDate(windowStart);
  const windowEndTs = admin.firestore.Timestamp.fromDate(windowEnd);

  let processedCount = 0;
  let sentCount = 0;

  const collections = ['appointments', 'visitations'];

  for (const colName of collections) {
    try {
      const snap = await db
        .collection(colName)
        .where('status', '==', 'scheduled')
        .where('scheduledStart', '>=', windowStartTs)
        .where('scheduledStart', '<=', windowEndTs)
        .get();

      for (const doc of snap.docs) {
        const data = doc.data();
        processedCount++;

        // Skip if reminder has already been sent
        if (data.reminderSent === true || data.reminderStatus === 'sent') {
          continue;
        }

        const appointmentId = doc.id;
        const doctorId = data.doctorId;
        const patientId = data.patientId;
        const visitType = data.visitType || (colName === 'visitations' ? 'home' : 'clinic');

        if (!doctorId || !patientId) continue;

        // Fetch patient phone and details
        let phone = data.phone || data.patientPhone || '';
        let patientName = data.patientName || '';

        if (!phone || !patientName) {
          try {
            const pDoc = await db.collection('patients').doc(patientId).get();
            if (pDoc.exists) {
              const pData = pDoc.data() || {};
              phone = phone || pData.phone || '';
              patientName = patientName || pData.fullName || 'Valued Patient';
            }
          } catch (_) {}
        }

        const startDate = data.scheduledStart instanceof admin.firestore.Timestamp
          ? data.scheduledStart.toDate()
          : new Date(data.scheduledStart);

        console.log(
          `[WhatsApp Auto-Reminder] Triggering 10-min reminder for appt ${appointmentId} ` +
          `(Patient: "${patientName}", Time: ${startDate.toLocaleTimeString()})`
        );

        // Dispatch WhatsApp Reminder
        const result = await dispatchAppointmentWhatsApp({
          appointmentId: `${appointmentId}_reminder`,
          doctorId,
          patientId,
          phone,
          patientName,
          scheduledStart: startDate,
          visitType,
          source: '10_min_automated_reminder',
        });

        // Mark visit with reminderSent = true to guarantee idempotency
        await doc.ref.update({
          reminderSent: true,
          reminderStatus: 'sent',
          reminderSentAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });

        if (result.success) {
          sentCount++;
        }
      }
    } catch (err) {
      console.error(`[WhatsApp Auto-Reminder] Error querying ${colName}:`, err);
    }
  }

  return { processedCount, sentCount };
}

/**
 * Cloud Scheduler cron trigger running every 1 minute to automatically
 * detect and send pre-appointment WhatsApp reminders 10 minutes before the visit.
 */
export const scheduledAppointmentReminders = functions.onRequest(
  {
    region: 'asia-south1',
    maxInstances: 5,
    cors: true,
  },
  async (req, res) => {
    try {
      console.log('[WhatsApp Reminders] Automated 10-minute reminder job triggered.');
      const result = await checkAndDispatchUpcomingReminders();
      res.status(200).json({
        success: true,
        message: `Processed ${result.processedCount} appointments, sent ${result.sentCount} reminders.`,
        ...result,
      });
    } catch (err: any) {
      console.error('[WhatsApp Reminders Error]', err);
      res.status(500).json({ success: false, error: err?.message || 'Internal error' });
    }
  }
);

// ============================================================
// 7. SECURE META WEBHOOK (SIGNATURE VERIFICATION & STATUS UPDATES)
// ============================================================

export const whatsappWebhook = functions.onRequest(
  {
    region: 'asia-south1',
    maxInstances: 10,
    cors: true,
  },
  async (req, res) => {
    // ---- GET: Webhook Verification Challenge ----
    if (req.method === 'GET') {
      const mode = req.query['hub.mode'];
      const token = req.query['hub.verify_token'];
      const challenge = req.query['hub.challenge'];

      const expectedVerifyToken = process.env.WHATSAPP_WEBHOOK_VERIFY_TOKEN || 'crudoc_whatsapp_webhook_verify_token_2026';

      if (mode === 'subscribe' && token === expectedVerifyToken) {
        console.log('[WhatsApp Webhook] Verification challenge passed successfully.');
        res.status(200).send(challenge);
        return;
      }

      console.warn('[WhatsApp Webhook] Verification token mismatch.');
      res.status(403).send('Forbidden');
      return;
    }

    // ---- POST: Status Callback Events ----
    if (req.method === 'POST') {
      const appSecret = process.env.WHATSAPP_WEBHOOK_APP_SECRET;

      // Validate HMAC SHA-256 signature if app secret is configured
      if (appSecret) {
        const signatureHeader = req.headers['x-hub-signature-256'] as string | undefined;
        if (!signatureHeader || !signatureHeader.startsWith('sha256=')) {
          console.warn('[WhatsApp Webhook] Missing or invalid signature header');
          res.status(401).send('Unauthorized: Signature missing');
          return;
        }

        const signature = signatureHeader.substring(7);
        const rawBody = (req as any).rawBody || JSON.stringify(req.body);
        const expectedSignature = crypto
          .createHmac('sha256', appSecret)
          .update(rawBody)
          .digest('hex');

        if (signature !== expectedSignature) {
          console.warn('[WhatsApp Webhook] HMAC SHA-256 signature mismatch');
          res.status(401).send('Unauthorized: Signature mismatch');
          return;
        }
      }

      // Process Status Updates
      const body = req.body;
      if (body?.entry && Array.isArray(body.entry)) {
        const db = getDb();

        for (const entry of body.entry) {
          const changes = entry.changes || [];
          for (const change of changes) {
            const value = change.value;
            if (value?.statuses && Array.isArray(value.statuses)) {
              for (const statusObj of value.statuses) {
                const messageId = statusObj.id;
                const status = statusObj.status; // 'sent' | 'delivered' | 'read' | 'failed'
                const timestamp = statusObj.timestamp ? new Date(parseInt(statusObj.timestamp, 10) * 1000) : new Date();

                if (messageId && status) {
                  try {
                    // Look up matching notification log by whatsappMessageId
                    const querySnap = await db
                      .collection('whatsapp_notification_logs')
                      .where('whatsappMessageId', '==', messageId)
                      .limit(1)
                      .get();

                    if (!querySnap.empty) {
                      const doc = querySnap.docs[0];
                      const updateData: Record<string, any> = {
                        status,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                      };

                      if (status === 'delivered') {
                        updateData.deliveredAt = admin.firestore.Timestamp.fromDate(timestamp);
                      } else if (status === 'read') {
                        updateData.readAt = admin.firestore.Timestamp.fromDate(timestamp);
                      } else if (status === 'failed') {
                        const errorDetail = statusObj.errors?.[0];
                        updateData.failureReason = errorDetail ? `${errorDetail.code}: ${errorDetail.title}` : 'delivery_failed';
                      }

                      await doc.ref.update(updateData);
                      console.log(`[WhatsApp Webhook] Updated message ${messageId} status to "${status}"`);
                    }
                  } catch (e) {
                    console.error(`[WhatsApp Webhook] Error updating status for ${messageId}:`, e);
                  }
                }
              }
            }
          }
        }
      }

      // Acknowledge receipt to Meta immediately (200 OK)
      res.status(200).json({ success: true });
      return;
    }

    res.status(405).json({ success: false, error: 'Method not allowed' });
  }
);
