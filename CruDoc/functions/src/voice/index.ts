import {onRequest} from "firebase-functions/v2/https";
import {voiceBotApiKeySecret} from "../appointments";
import {patientKekPepperSecret} from "../crypto/patientCipher";
import {callEnded, sarvamWebhookSecret, webhookTokenMatches} from "./callEnded";
import {apiKeyMatches, CallContext, loadContext, VoiceError} from "./context";
import {
  book, callback, cancel, myAppointments, reschedule, session, slots,
} from "./routes";

/**
 * The booking API for the AI receptionist (Sarvam Voice Agents tools).
 *
 *   POST /voiceApi/<route>   header X-Api-Key, JSON body
 *
 * One function rather than one per route: each Cloud Function is its own
 * server that sleeps when idle, and waking one mid-call is a second or more
 * of silence on the phone. One function means one server to keep warm.
 *
 * Business refusals ("that slot is taken") come back as HTTP 200 with
 * `{ok: false, code, say}` so the agent reads `say` to the caller. Only a
 * crash is a 5xx, which the agent's "if it fails" text covers.
 *
 * docs/ai_receptionist_final_plan.md §4.4 has the contract.
 */

type Route = (ctx: CallContext) => Promise<Record<string, unknown>>;

const ROUTES: Record<string, Route> = {
  session,
  slots,
  book,
  my_appointments: myAppointments,
  cancel,
  reschedule,
  callback,
};

/** "/my-appointments/" -> "my_appointments" */
export function routeName(path: string): string {
  const last = path.replace(/^\/+|\/+$/g, "").split("/").pop() ?? "";
  return last.replace(/-/g, "_").toLowerCase();
}

export const voiceApi = onRequest(
  {
    region: "asia-south1",
    // Sarvam calls this from outside Google Cloud, so the Cloud Run service
    // must allow unauthenticated calls; the API key and the webhook token are
    // the gate. That is set once on the service (Cloud Run → voiceapi →
    // Security → Allow public access), not here: `invoker: "public"` made
    // every deploy try to set it again, and the deploying account may not
    // hold the IAM role to, which failed the deploy.
    maxInstances: 20,
    timeoutSeconds: 30,
    memory: "512MiB",
    secrets: [voiceBotApiKeySecret, patientKekPepperSecret, sarvamWebhookSecret],
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).json({ok: false, code: "method_not_allowed"});
      return;
    }
    const name = routeName(req.path || "");
    const body = (req.body && typeof req.body === "object" ? req.body : {}) as Record<string, unknown>;

    if (name === "call_ended") {
      if (!webhookTokenMatches(req.query.token)) {
        res.status(401).json({ok: false, code: "unauthorized"});
        return;
      }
      try {
        res.status(200).json(await callEnded(body));
      } catch (err) {
        console.error("voiceApi call-ended failed:", (err as Error).message);
        // A 5xx makes Sarvam's delivery record "failed", so it can be retried.
        res.status(500).json({ok: false, code: "server_error"});
      }
      return;
    }

    // The key normally comes as the X-Api-Key header. Sarvam's tool editor
    // sent that header empty, or sent a secret's id instead of its value, so
    // the body may carry it as `api_key` instead. The editor can also add the
    // header twice (Auth plus Headers), which Node joins as "key, key"; each
    // copy is checked.
    const bodyKey = typeof body.api_key === "string" ? body.api_key : "";
    delete body.api_key;
    const provided = String(req.get("x-api-key") || bodyKey || "");
    if (!provided.split(",").some((part) => apiKeyMatches(part.trim()))) {
      // The shape of what arrived, never the value: enough to tell a missing,
      // doubled or truncated key from a wrong one.
      console.warn(
        `voiceApi ${name} unauthorized: x-api-key ${provided ? `length ${provided.length}` : "missing"}` +
        `${provided.includes(",") ? ", sent more than once" : ""}` +
        `${provided !== provided.trim() ? ", has surrounding whitespace" : ""}` +
        `; headers: ${Object.keys(req.headers).filter((h) => /key|auth/i.test(h)).join(" ") || "none"}`,
      );
      res.status(401).json({ok: false, code: "unauthorized"});
      return;
    }

    const route = ROUTES[name];
    if (!route) {
      res.status(404).json({ok: false, code: "unknown_route"});
      return;
    }

    const started = Date.now();
    try {
      const ctx = await loadContext(body);
      const reply = await route(ctx);
      res.status(200).json({ok: true, ...reply});
      console.log(`voiceApi ${name} ok in ${Date.now() - started} ms (line ${ctx.line.id})`);
    } catch (err) {
      if (err instanceof VoiceError) {
        res.status(200).json({ok: false, code: err.code, say: err.say, ...err.extra});
        console.log(`voiceApi ${name} refused ${err.code} in ${Date.now() - started} ms`);
        return;
      }
      console.error(`voiceApi ${name} failed:`, err);
      res.status(500).json({
        ok: false,
        code: "server_error",
        say: "Sorry, I can't reach the clinic diary right now. May I take a message for the clinic?",
      });
    }
  },
);
