import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {defineSecret} from "firebase-functions/params";

import {
  WhatsAppConfig, WhatsAppNotConfiguredError, getConfig, getMode,
} from "./whatsapp/config";
import {normalisePhone} from "./whatsapp/format";
import {filterOptedOut} from "./whatsapp/optouts";
import {MetaSendError, sendTemplateMessage} from "./whatsapp/send";
import {templateFor} from "./whatsapp/templates";
import {
  CAMPAIGN_TEMPLATE_KEY,
  CampaignRecipientInput,
  planCampaign,
} from "./whatsapp/campaigns";
import {
  OutboxRow,
  claim,
  dueRows,
  enqueueWhatsApp,
  markBlocked,
  markFailed,
  markRetryable,
  markSent,
} from "./whatsapp/outbox";
import {
  TenantNotConnectedError,
  TenantReauthRequiredError,
  getTenantConfig,
  getTenantCreds,
  isAuthError,
  markReauthRequired,
} from "./whatsapp/tenants";

/**
 * The per-clinic WhatsApp campaign path: a callable the app invokes to queue a
 * campaign, and the worker that drains the outbox as the clinic's own number.
 *
 * Campaigns ride the existing outbox (kind "campaign"), so retry, idempotency,
 * opt-out handling and the "wait until the clinic connects" behaviour are all
 * inherited rather than re-implemented.
 */

const REGION = "asia-south1";

/**
 * The shared CruDoc number's token, needed only for the fallback send path.
 * The per-clinic path reads each tenant's token from Secret Manager directly.
 */
const accessToken = defineSecret("WHATSAPP_ACCESS_TOKEN");

function graphVersion(): string {
  return (process.env.WHATSAPP_GRAPH_VERSION || "v23.0").trim();
}

/** A send config for one clinic, built from its tenant credentials. */
function tenantSendConfig(creds: {
  token: string;
  phoneNumberId: string;
}): WhatsAppConfig {
  return {
    token: creds.token,
    phoneNumberId: creds.phoneNumberId,
    graphVersion: graphVersion(),
    // Empty, so the send uses the template spec's own registered name.
    templateName: "",
    mode: getMode(),
  };
}

// ---------------------------------------------------------------------------
// Callable: queue a campaign
// ---------------------------------------------------------------------------

interface EnqueueCampaignData {
  campaignId?: unknown;
  message?: unknown;
  clinicName?: unknown;
  clinicPhone?: unknown;
  recipients?: unknown;
}

function asString(v: unknown): string {
  return typeof v === "string" ? v : "";
}

/**
 * Queues a WhatsApp campaign for the authenticated clinic.
 *
 * The client passes the resolved audience (phones and names); the server owns
 * the rules that actually gate a send: the clinic's number must be connected,
 * opted-out patients are dropped, and each patient is messaged at most once per
 * campaign (the dedupe key makes a retried call a no-op).
 */
export const enqueueCampaign = onCall({region: REGION}, async (request) => {
  const doctorId = request.auth?.uid;
  if (!doctorId) {
    throw new HttpsError("unauthenticated", "Sign in to send a campaign.");
  }

  const data = (request.data || {}) as EnqueueCampaignData;
  const campaignId = asString(data.campaignId).trim();
  const message = asString(data.message).trim();
  const clinicName = asString(data.clinicName).trim();
  const clinicPhone = asString(data.clinicPhone).trim();
  const recipients = Array.isArray(data.recipients) ?
    (data.recipients as CampaignRecipientInput[]) :
    [];

  if (!campaignId) {
    throw new HttpsError("invalid-argument", "campaignId is required.");
  }
  if (!message) {
    throw new HttpsError("invalid-argument", "message is required.");
  }
  if (!clinicName || !clinicPhone) {
    throw new HttpsError(
      "invalid-argument",
      "clinicName and clinicPhone are required.",
    );
  }
  if (!recipients.length) {
    throw new HttpsError("invalid-argument", "recipients is empty.");
  }

  // A reauth-required tenant must reconnect before anything queues for it; a
  // clinic with no tenant at all still queues and sends from the shared number.
  const tenant = await getTenantConfig(doctorId);
  if (tenant && tenant.status === "reauth_required") {
    throw new HttpsError(
      "failed-precondition",
      "Reconnect this clinic's WhatsApp number before sending campaigns.",
    );
  }

  const normalised = recipients
    .map((r) => normalisePhone(r.phone))
    .filter((p): p is string => !!p);
  const optedOut = await filterOptedOut(normalised);

  const plan = planCampaign({
    campaignId,
    message,
    clinicName,
    clinicPhone,
    recipients,
    optedOut,
  });

  let queued = 0;
  for (const m of plan.messages) {
    const result = await enqueueWhatsApp({
      doctorId,
      toPhone: m.phone,
      templateKey: CAMPAIGN_TEMPLATE_KEY,
      params: m.params,
      kind: "campaign",
      patientId: m.patientId ?? undefined,
      dedupeKey: m.dedupeKey,
    });
    if (result.created) queued++;
  }

  return {
    queued,
    alreadyQueued: plan.messages.length - queued,
    skipped: plan.skipped,
  };
});

// ---------------------------------------------------------------------------
// Worker: drain the outbox as each clinic
// ---------------------------------------------------------------------------

/** Sends one claimed row, then records its outcome. */
async function processRow(row: OutboxRow): Promise<void> {
  // Prefer the clinic's own connected number; otherwise fall back to the shared
  // CruDoc number (the one reminders already send from). A reauth-required
  // tenant is parked rather than silently sent from the shared number.
  let config: WhatsAppConfig;
  try {
    const creds = await getTenantCreds(row.doctorId);
    config = tenantSendConfig(creds);
  } catch (err) {
    if (err instanceof TenantReauthRequiredError) {
      await markBlocked(row.id, "blocked_tenant", err.message);
      return;
    }
    if (err instanceof TenantNotConnectedError) {
      try {
        config = getConfig();
      } catch (e2) {
        if (e2 instanceof WhatsAppNotConfiguredError) {
          // No per-clinic number and no shared number: wait for one.
          await markBlocked(row.id, "blocked_tenant", e2.message);
          return;
        }
        await markRetryable(
          row.id, (e2 as Error)?.message || "config read failed",
        );
        return;
      }
    } else {
      await markRetryable(
        row.id, (err as Error)?.message || "tenant read failed",
      );
      return;
    }
  }

  let spec;
  try {
    spec = templateFor(row.templateKey);
  } catch {
    await markFailed(row.id, `Unknown template: ${row.templateKey}`);
    return;
  }

  try {
    const {messageId} = await sendTemplateMessage({
      to: row.toPhone,
      spec,
      params: row.params,
      config,
    });
    await markSent(row.id, messageId);
  } catch (err) {
    const meta = err instanceof MetaSendError ? err : null;
    const reason = (err as Error)?.message || "send failed";

    if (meta && isAuthError(meta.code)) {
      // The token is dead; stop retrying against it and prompt reconnection.
      await markReauthRequired(row.doctorId, meta.code);
      await markBlocked(row.id, "blocked_tenant", reason);
      return;
    }
    if (meta?.permanent) {
      await markFailed(row.id, reason, meta.code);
      return;
    }
    await markRetryable(row.id, reason, meta?.code);
  }
}

/** Claims and sends every due row, ignoring those another worker holds. */
async function drain(limit = 100): Promise<void> {
  const rows = await dueRows(limit);
  for (const row of rows) {
    const claimed = await claim(row.id);
    if (claimed) await processRow(claimed);
  }
}

/** The steady sweep: catches retries, blocked rows released, and stalled leases. */
export const drainWhatsAppOutbox = onSchedule(
  {
    schedule: "every 1 minutes",
    region: REGION,
    maxInstances: 1,
    secrets: [accessToken],
  },
  async () => {
    await drain();
  },
);

/** The fast path: send a freshly queued row without waiting for the sweep. */
export const onWhatsAppOutboxQueued = onDocumentCreated(
  {document: "whatsapp_outbox/{id}", region: REGION, secrets: [accessToken]},
  async (event) => {
    const id = event.params.id;
    const claimed = await claim(id);
    if (claimed) await processRow(claimed);
  },
);
