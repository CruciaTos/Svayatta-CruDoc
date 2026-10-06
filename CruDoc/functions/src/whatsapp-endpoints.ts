import {onRequest} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {defineSecret} from "firebase-functions/params";
import {sendDayBeforeReminders} from "./whatsapp/reminders";
import {
  processWebhook, verifySignature, verifySubscription,
} from "./whatsapp/webhook";

/**
 * WhatsApp appointment reminders, sent from one CruDoc number on behalf of
 * every clinic. See docs/whatsapp_shared_number.md.
 *
 * Two functions, deliberately. Three earlier ones were removed rather than
 * fixed:
 *
 *   sendWhatsAppAppointmentConfirmation  a public onRequest with no auth that
 *     took a phone number and a doctorId straight from the request body, so
 *     anyone who found the URL could send messages from CruDoc's number to
 *     anyone. There is also no booking confirmation in this plan.
 *
 *   scheduledAppointmentReminders  also public, and an onRequest with no
 *     scheduler job defined anywhere, so it never ran. Replaced by the
 *     onSchedule below, which provisions its own Cloud Scheduler job.
 *
 *   sendWhatsAppCampaignMessage  marketing on a number shared by every clinic
 *     risks the quality rating for all of them at once. Campaigns wait for
 *     per-clinic numbers.
 */

const accessToken = defineSecret("WHATSAPP_ACCESS_TOKEN");
const webhookVerifyToken = defineSecret("WHATSAPP_WEBHOOK_VERIFY_TOKEN");
const webhookAppSecret = defineSecret("WHATSAPP_WEBHOOK_APP_SECRET");

/**
 * Sends tomorrow's reminders, every evening at 18:00 IST.
 *
 * `maxInstances: 1` with no retries because a second overlapping run would
 * race the first for the same appointments. The per-appointment claim would
 * catch it, but not racing in the first place is cheaper than relying on that.
 */
export const sendDayBeforeWhatsAppReminders = onSchedule(
  {
    schedule: "0 18 * * *",
    timeZone: "Asia/Kolkata",
    region: "asia-south1",
    maxInstances: 1,
    timeoutSeconds: 540,
    memory: "512MiB",
    retryCount: 0,
    secrets: [accessToken],
  },
  async () => {
    await sendDayBeforeReminders();
  },
);

/**
 * Meta's callbacks: delivery receipts, and patient replies.
 *
 * No CORS: this is a server-to-server callback, and CORS headers on it would
 * only ever help a browser that has no business calling it.
 */
export const whatsappWebhook = onRequest(
  {
    region: "asia-south1",
    maxInstances: 10,
    secrets: [accessToken, webhookVerifyToken, webhookAppSecret],
  },
  async (req, res) => {
    if (req.method === "GET") {
      const challenge = verifySubscription(
        req.query as Record<string, unknown>,
      );
      if (challenge === null) {
        res.status(403).send("Forbidden");
        return;
      }
      res.status(200).send(challenge);
      return;
    }

    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }

    const check = verifySignature(
      (req as unknown as {rawBody?: Buffer}).rawBody,
      req.headers["x-hub-signature-256"] as string | undefined,
    );

    if (!check.ok) {
      console.error(`[WhatsApp Webhook] rejected: ${check.reason}`);
      res
        .status(check.reason === "app_secret_unset" ? 500 : 401)
        .send("Unauthorized");
      return;
    }

    // Acknowledge first, then work. Meta retries anything it does not see a
    // 200 for within seconds, and disables a callback that keeps failing.
    res.status(200).send("EVENT_RECEIVED");

    try {
      await processWebhook(req.body);
    } catch (err) {
      console.error("[WhatsApp Webhook] processing failed", err);
    }
  },
);
