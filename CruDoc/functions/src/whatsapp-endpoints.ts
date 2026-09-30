import * as functions from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {defineSecret} from "firebase-functions/params";
import {
  getDb,
  getWhatsAppWebhookVerifyToken,
  getWhatsAppWebhookAppSecret,
  normalizePhoneNumber,
  sendWhatsAppMetaMessage,
  dispatchAppointmentWhatsApp,
  checkAndDispatchUpcomingReminders,
} from "./whatsapp";

/**
 * WhatsApp endpoints. Not exported from index.ts until WhatsApp is set up:
 * declaring these secrets makes every deploy of this codebase require them.
 * To enable, set the three secrets (firebase functions:secrets:set ...) and
 * add `export * from "./whatsapp-endpoints";` to index.ts.
 */
export const whatsappAccessTokenSecret = defineSecret("WHATSAPP_ACCESS_TOKEN");
export const whatsappWebhookVerifyTokenSecret = defineSecret("WHATSAPP_WEBHOOK_VERIFY_TOKEN");
export const whatsappWebhookAppSecretSecret = defineSecret("WHATSAPP_WEBHOOK_APP_SECRET");

export const sendWhatsAppAppointmentConfirmation = functions.onRequest(
  {
    region: "asia-south1",
    maxInstances: 10,
    cors: true,
    secrets: [whatsappAccessTokenSecret],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({success: false, error: "Method not allowed"});
      return;
    }

    try {
      const {appointmentId, doctorId, patientId, phone, patientName, scheduledStart, visitType} = req.body;

      if (!appointmentId || !doctorId || !patientId) {
        res.status(400).json({success: false, error: "appointmentId, doctorId, and patientId are required"});
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
        visitType: visitType || "clinic",
        source: "manual_or_client_trigger",
      });

      res.status(200).json(result);
    } catch (err: any) {
      console.error("[WhatsApp Endpoint Error]", err);
      res.status(500).json({success: false, error: err?.message || "Internal server error"});
    }
  }
);

// ============================================================
// 6. AUTOMATED 10-MINUTE PRE-APPOINTMENT REMINDER ENGINE
// ============================================================

/**
 * Cloud Scheduler cron trigger running every 1 minute to automatically
 * detect and send pre-appointment WhatsApp reminders 10 minutes before the visit.
 */
export const scheduledAppointmentReminders = functions.onRequest(
  {
    region: "asia-south1",
    maxInstances: 5,
    cors: true,
  },
  async (req, res) => {
    try {
      console.log("[WhatsApp Reminders] Automated 10-minute reminder job triggered.");
      const result = await checkAndDispatchUpcomingReminders();
      res.status(200).json({
        success: true,
        message: `Processed ${result.processedCount} appointments, sent ${result.sentCount} reminders.`,
        ...result,
      });
    } catch (err: any) {
      console.error("[WhatsApp Reminders Error]", err);
      res.status(500).json({success: false, error: err?.message || "Internal error"});
    }
  }
);

// ============================================================
// 7. SECURE META WEBHOOK (SIGNATURE VERIFICATION & STATUS UPDATES)
// ============================================================

export const whatsappWebhook = functions.onRequest(
  {
    region: "asia-south1",
    maxInstances: 10,
    cors: true,
    secrets: [whatsappWebhookVerifyTokenSecret, whatsappWebhookAppSecretSecret],
  },
  async (req, res) => {
    // ---- GET: Webhook Verification Challenge ----
    if (req.method === "GET") {
      const mode = req.query["hub.mode"];
      const token = req.query["hub.verify_token"];
      const challenge = req.query["hub.challenge"];

      const expectedVerifyToken = getWhatsAppWebhookVerifyToken();

      if (mode === "subscribe" && typeof token === "string" && expectedVerifyToken) {
        const tokenBuf = Buffer.from(token);
        const expectedBuf = Buffer.from(expectedVerifyToken);
        if (
          tokenBuf.length === expectedBuf.length &&
          crypto.timingSafeEqual(tokenBuf, expectedBuf)
        ) {
          console.log("[WhatsApp Webhook] Verification challenge passed successfully.");
          res.status(200).send(challenge);
          return;
        }
      }

      console.warn("[WhatsApp Webhook] Verification token mismatch.");
      res.status(403).send("Forbidden");
      return;
    }

    // ---- POST: Status Callback Events ----
    if (req.method === "POST") {
      const appSecret = getWhatsAppWebhookAppSecret();

      // Validate HMAC SHA-256 signature if app secret is configured
      if (appSecret) {
        const signatureHeader = req.headers["x-hub-signature-256"] as string | undefined;
        if (!signatureHeader || !signatureHeader.startsWith("sha256=")) {
          console.warn("[WhatsApp Webhook] Missing or invalid signature header");
          res.status(401).send("Unauthorized: Signature missing");
          return;
        }

        const signature = signatureHeader.substring(7);
        const rawBody = (req as any).rawBody || JSON.stringify(req.body);
        const expectedSignature = crypto
          .createHmac("sha256", appSecret)
          .update(rawBody)
          .digest("hex");

        const sigBuf = Buffer.from(signature);
        const expBuf = Buffer.from(expectedSignature);

        if (sigBuf.length !== expBuf.length || !crypto.timingSafeEqual(sigBuf, expBuf)) {
          console.warn("[WhatsApp Webhook] HMAC SHA-256 signature mismatch");
          res.status(401).send("Unauthorized: Signature mismatch");
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
                      .collection("whatsapp_notification_logs")
                      .where("whatsappMessageId", "==", messageId)
                      .limit(1)
                      .get();

                    if (!querySnap.empty) {
                      const doc = querySnap.docs[0];
                      const updateData: Record<string, any> = {
                        status,
                        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
                      };

                      if (status === "delivered") {
                        updateData.deliveredAt = admin.firestore.Timestamp.fromDate(timestamp);
                      } else if (status === "read") {
                        updateData.readAt = admin.firestore.Timestamp.fromDate(timestamp);
                      } else if (status === "failed") {
                        const errorDetail = statusObj.errors?.[0];
                        updateData.failureReason = errorDetail ? `${errorDetail.code}: ${errorDetail.title}` : "delivery_failed";
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
      res.status(200).json({success: true});
      return;
    }

    res.status(405).json({success: false, error: "Method not allowed"});
  }
);

/**
 * Authenticated doctor callable to dispatch WhatsApp campaign messages securely.
 * Verifies doctorId == request.auth.uid to enforce strict multi-tenant isolation.
 */
export const sendWhatsAppCampaignMessage = functions.onCall(
  {
    region: "asia-south1",
    maxInstances: 10,
    secrets: [whatsappAccessTokenSecret],
  },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new functions.HttpsError("unauthenticated", "Authentication required.");
    }

    const {campaignId, doctorId, patientId, patientName, phone, clinicName, doctorName} = request.data || {};

    if (!doctorId || request.auth.uid !== doctorId) {
      throw new functions.HttpsError("permission-denied", "Cross-doctor action is strictly forbidden.");
    }

    const normalized = normalizePhoneNumber(phone);
    if (!normalized) {
      return {success: false, error: "Invalid recipient phone number"};
    }

    const result = await sendWhatsAppMetaMessage({
      toPhone: normalized,
      data: {
        patientName: patientName || "Valued Patient",
        doctorName: doctorName || "Doctor",
        clinicName: clinicName || "CruDoc Practice",
        appointmentDate: new Date().toLocaleDateString(),
        appointmentTime: new Date().toLocaleTimeString(),
        consultationType: "In-Clinic",
      },
      templateName: "appointment_confirmation",
      appointmentId: `${campaignId || "campaign"}_${Date.now()}`,
      doctorId,
      patientId: patientId || "campaign_patient",
    });

    return result;
  }
);
