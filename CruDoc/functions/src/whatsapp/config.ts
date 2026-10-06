/**
 * Credentials for the shared CruDoc WhatsApp number.
 *
 * One number, owned by CruDoc, messaging on behalf of every clinic. The token
 * is a System User token set with `firebase functions:secrets:set`; the
 * temporary one from the API Setup page expires after 24 hours and every send
 * fails the next day.
 */

export type WhatsAppMode = "live" | "dry_run";

export interface WhatsAppConfig {
  token: string;
  phoneNumberId: string;
  graphVersion: string;
  templateName: string;
  mode: WhatsAppMode;
}

/**
 * Thrown when the number is not set up.
 *
 * This is deliberately an error rather than a quiet fallback. The previous
 * implementation treated missing credentials as a cue to simulate a successful
 * send, so an unconfigured deployment reported every message as delivered and
 * the status badges in the app were green for messages that never existed.
 */
export class WhatsAppNotConfiguredError extends Error {
  constructor(what: string) {
    super(`WhatsApp is not configured: ${what}`);
    this.name = "WhatsAppNotConfiguredError";
  }
}

function env(name: string): string {
  return (process.env[name] || "").trim();
}

export function getMode(): WhatsAppMode {
  return env("WHATSAPP_MODE") === "dry_run" ? "dry_run" : "live";
}

/**
 * Reads and checks the configuration.
 *
 * `dry_run` still requires nothing but is reported honestly by the caller: a
 * dry run is logged as skipped, never as sent.
 */
export function getConfig(): WhatsAppConfig {
  const mode = getMode();
  const token = env("WHATSAPP_ACCESS_TOKEN");
  const phoneNumberId = env("WHATSAPP_PHONE_NUMBER_ID");

  if (mode === "live") {
    if (!token) throw new WhatsAppNotConfiguredError("WHATSAPP_ACCESS_TOKEN is unset");
    if (!phoneNumberId) {
      throw new WhatsAppNotConfiguredError("WHATSAPP_PHONE_NUMBER_ID is unset");
    }
  }

  return {
    token,
    phoneNumberId,
    // Pinned in config rather than in source so a Graph deprecation is a
    // redeploy, not a code change.
    graphVersion: env("WHATSAPP_GRAPH_VERSION") || "v23.0",
    templateName: env("WHATSAPP_TEMPLATE_NAME") || "appointment_reminder_v1",
    mode,
  };
}

export function getWebhookVerifyToken(): string {
  return env("WHATSAPP_WEBHOOK_VERIFY_TOKEN");
}

export function getWebhookAppSecret(): string {
  return env("WHATSAPP_WEBHOOK_APP_SECRET");
}
