import * as admin from "firebase-admin";
import * as crypto from "crypto";
import {defineSecret} from "firebase-functions/params";
import {callDocId, db, DEFAULT_INCLUDED_CALLS, indianNumberDigits, loadLine} from "./context";
import {callCost, monthKeyOf} from "./schedule";

/**
 * Sarvam's post-call webhook for inbound deployments
 * (https://docs.sarvam.ai/conversations/api/deployments/webhooks/webhook-payload).
 *
 * Records the call's duration and cost and adds it to the clinic's monthly
 * usage, which the quota in `session` reads. Keyed on Sarvam's
 * `interaction_id`, in one transaction, so a redelivered webhook (Sarvam
 * retries, and deliveries can be re-sent by hand) is counted once.
 *
 * Sarvam's webhook config has a URL and metadata but no auth header, so the
 * secret travels as `?token=` on the URL and is compared in constant time.
 * CruDoc keeps no transcript: it stays in Sarvam's call logs.
 */

export const sarvamWebhookSecret = defineSecret("SARVAM_WEBHOOK_SECRET");

export function webhookTokenMatches(provided: unknown): boolean {
  let expected = "";
  try {
    expected = sarvamWebhookSecret.value().trim();
  } catch (_) {
    expected = (process.env.SARVAM_WEBHOOK_SECRET || "").trim();
  }
  if (!expected || typeof provided !== "string" || !provided) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** The call's outcome, from what the AI did during it (most important first). */
export function outcomeOf(mode: unknown, actions: unknown): string {
  const types = Array.isArray(actions) ?
    actions.map((a) => (a && typeof a === "object" ? (a as {type?: unknown}).type : null)) :
    [];
  for (const t of ["booked", "rescheduled", "cancelled", "callback"]) {
    if (types.includes(t)) return t;
  }
  if (typeof mode === "string" && mode !== "patient") return mode;
  return mode === "patient" ? "info" : "unknown";
}

export async function callEnded(body: Record<string, unknown>): Promise<Record<string, unknown>> {
  const interactionId = typeof body.interaction_id === "string" ? body.interaction_id : "";
  if (!interactionId) return {ok: false, code: "no_interaction_id"};

  const seconds = typeof body.duration === "number" ? body.duration : Number(body.duration) || 0;
  const startedAt = typeof body.start_datetime === "string" ? new Date(body.start_datetime) : new Date();
  const month = monthKeyOf(isNaN(startedAt.getTime()) ? new Date() : startedAt);

  const callRef = db().collection("voice_calls").doc(callDocId(interactionId));
  const lineId = indianNumberDigits(body.agent_phone_number);

  // The dialled number identifies the clinic; the call document, written by
  // `session`, is the fallback.
  const line = lineId ? await loadLine(lineId) : null;
  const cost = callCost(seconds);

  return db().runTransaction(async (tx) => {
    const call = await tx.get(callRef);
    const c = call.data() || {};
    if (c.endedAt) return {ok: true, duplicate: true};

    const clinicId: string = line?.clinicId || (typeof c.doctorId === "string" ? c.doctorId : "");
    const usageRef = clinicId ?
      db().collection("voice_usage").doc(`${clinicId}_${month}`) :
      null;
    // Every read before any write, as Firestore transactions require.
    const usage = usageRef ? await tx.get(usageRef) : null;
    const outcome = outcomeOf(c.mode, c.actions);

    tx.set(callRef, {
      doctorId: clinicId || null,
      lineId: lineId ?? c.lineId ?? null,
      interactionId,
      durationSec: Math.round(seconds),
      ...cost,
      outcome,
      sarvamAgentId: typeof body.app_id === "string" ? body.app_id : null,
      sarvamDeploymentId: typeof body.deployment_id === "string" ? body.deployment_id : null,
      callStartedAt: isNaN(startedAt.getTime()) ? null : admin.firestore.Timestamp.fromDate(startedAt),
      endedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    if (!usageRef) {
      console.warn(`voiceApi call-ended: no clinic for ${interactionId} (line ${lineId})`);
      return {ok: true, counted: false};
    }

    const u = usage?.data() || {};
    const inc = admin.firestore.FieldValue.increment;
    tx.set(usageRef, {
      doctorId: clinicId,
      month,
      calls: inc(1),
      seconds: inc(Math.round(seconds)),
      agentMinutes: inc(cost.agentMinutes),
      pulses: inc(cost.pulses),
      costPaise: inc(cost.costPaise),
      includedCalls: typeof u.includedCalls === "number" ?
        u.includedCalls :
        line?.includedCalls ?? DEFAULT_INCLUDED_CALLS,
      extraCalls: typeof u.extraCalls === "number" ? u.extraCalls : 0,
      outcomes: {[outcome]: inc(1)},
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {ok: true, counted: true};
  });
}
