import {getConfig, WhatsAppConfig} from "./config";
import {buildMessageComponents, TemplateSpec} from "./templates";

/**
 * The Meta Cloud API client.
 *
 * Every path either returns a real message id from Meta or throws. There is no
 * simulated success and no substitute template: a message that did not go has
 * to be visible as one, because the whole point of the delivery log is that a
 * doctor can trust it.
 */

interface MetaResponse {
  messages?: Array<{id: string}>;
  error?: {
    message: string;
    type?: string;
    code: number;
    error_subcode?: number;
    error_data?: {details?: string};
    fbtrace_id?: string;
  };
}

export class MetaSendError extends Error {
  constructor(
    message: string,
    readonly code: number,
    readonly permanent: boolean,
    readonly detail?: string,
  ) {
    super(message);
    this.name = "MetaSendError";
  }
}

const MAX_ATTEMPTS = 3;

/**
 * Errors no retry can fix.
 *
 *   131026  the number cannot receive WhatsApp
 *   131047  re-engagement needed (outside any session, no template)
 *   132000  parameter count does not match the template
 *   132001  the template does not exist in this account
 *   132005  the template was paused or disabled
 *   190     the token is expired or revoked
 *   131049  Meta declined to deliver for quality reasons
 */
const PERMANENT_CODES = new Set([
  131026, 131047, 132000, 132001, 132005, 132007, 132012, 190, 131049, 368,
]);

function isPermanent(code: number, status: number): boolean {
  if (PERMANENT_CODES.has(code)) return true;
  // 4xx other than rate limiting is a request we built wrong; sending it again
  // unchanged will fail the same way.
  return status >= 400 && status < 500 && status !== 429;
}

/** Meta's own id for a sent message, used to match delivery receipts. */
export interface SendResult {
  messageId: string;
}

/**
 * Sends one template message.
 *
 * @throws MetaSendError when Meta refuses or stays unreachable.
 */
export async function sendTemplateMessage(params: {
  to: string;
  spec: TemplateSpec;
  params: Record<string, string>;
  config?: WhatsAppConfig;
}): Promise<SendResult> {
  const config = params.config ?? getConfig();

  // Throws before any network call when a parameter is missing, so a
  // half-filled reminder is never sent.
  const components = buildMessageComponents(params.spec, params.params);

  if (config.mode === "dry_run") {
    throw new MetaSendError(
      "dry_run mode: nothing was sent",
      0,
      true,
      "WHATSAPP_MODE=dry_run",
    );
  }

  const url =
    `https://graph.facebook.com/${config.graphVersion}` +
    `/${config.phoneNumberId}/messages`;

  const body = {
    messaging_product: "whatsapp",
    recipient_type: "individual",
    to: params.to,
    type: "template",
    template: {
      name: config.templateName || params.spec.name,
      language: {code: params.spec.language},
      components,
    },
  };

  let lastError: MetaSendError | null = null;

  for (let attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${config.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
      });

      const data = (await response.json()) as MetaResponse;

      if (response.ok && data.messages?.length) {
        return {messageId: data.messages[0].id};
      }

      const code = data.error?.code ?? response.status;
      const message =
        data.error?.message || `HTTP ${response.status} from the WhatsApp API`;
      const permanent = isPermanent(code, response.status);

      lastError = new MetaSendError(
        message,
        code,
        permanent,
        data.error?.error_data?.details,
      );

      if (permanent) throw lastError;
    } catch (err) {
      if (err instanceof MetaSendError) {
        if (err.permanent) throw err;
        lastError = err;
      } else {
        lastError = new MetaSendError(
          (err as Error)?.message || "Could not reach the WhatsApp API",
          0,
          false,
        );
      }
    }

    if (attempt < MAX_ATTEMPTS) {
      const delay = Math.pow(2, attempt) * 500 + Math.random() * 200;
      await new Promise((r) => setTimeout(r, delay));
    }
  }

  throw lastError ??
    new MetaSendError("The WhatsApp API could not be reached", 0, false);
}

/**
 * Sends a plain text message.
 *
 * Only legal inside the 24 hours a patient's own message opens, so this is for
 * replying to STOP and to anything else a patient writes — never for starting
 * a conversation.
 */
export async function sendSessionText(params: {
  to: string;
  text: string;
  config?: WhatsAppConfig;
}): Promise<SendResult> {
  const config = params.config ?? getConfig();

  if (config.mode === "dry_run") {
    throw new MetaSendError("dry_run mode: nothing was sent", 0, true);
  }

  const url =
    `https://graph.facebook.com/${config.graphVersion}` +
    `/${config.phoneNumberId}/messages`;

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${config.token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: params.to,
      type: "text",
      text: {preview_url: false, body: params.text},
    }),
  });

  const data = (await response.json()) as MetaResponse;
  if (response.ok && data.messages?.length) {
    return {messageId: data.messages[0].id};
  }

  const code = data.error?.code ?? response.status;
  throw new MetaSendError(
    data.error?.message || `HTTP ${response.status} from the WhatsApp API`,
    code,
    isPermanent(code, response.status),
  );
}
