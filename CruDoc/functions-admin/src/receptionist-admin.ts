import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret, defineString} from "firebase-functions/params";
import * as admin from "firebase-admin";

/**
 * Super Admin control plane for the premium AI phone receptionist.
 *
 * Each doctor (or group of doctors sharing a clinic) can be given their own
 * phone number answered by a dedicated AI receptionist. The voice service
 * (../voice-receptionist) owns the lines; this callable is the only path the
 * Super Admin app takes to it, so the service's admin key stays server-side.
 *
 * Premium gate: a line can only be created for doctors whose account has the
 * `ai_agentic_calling` module enabled, and deactivating that module (or
 * calling `setEntitlement`) stops every line of the clinic from answering.
 */

export const voiceServiceAdminKey = defineSecret("VOICE_SERVICE_ADMIN_KEY");
// The same Secret Manager secret the main codebase's voice-bot endpoints check
// (functions/src/appointments.ts); declared here because this codebase is
// deployed separately and cannot import from that one.
export const voiceBotApiKeySecret = defineSecret("VOICE_BOT_API_KEY");
// e.g. https://voice.example.com  (no trailing slash)
const voiceServiceUrl = defineString("VOICE_SERVICE_URL");

export const AI_RECEPTIONIST_MODULE = "ai_agentic_calling";

type Json = Record<string, unknown>;

function db() {
  return admin.firestore();
}

function adminKey(): string {
  try {
    const val = voiceServiceAdminKey.value();
    if (val && val.trim().length > 0) return val.trim();
  } catch (_) {
    // local/emulator: fall back to env
  }
  return (process.env.VOICE_SERVICE_ADMIN_KEY || "").trim();
}

function baseUrl(): string {
  let url = "";
  try {
    url = voiceServiceUrl.value();
  } catch (_) {
    // local/emulator
  }
  return (url || process.env.VOICE_SERVICE_URL || "").replace(/\/+$/, "");
}

async function callVoiceService(
  method: "GET" | "PUT" | "DELETE",
  path: string,
  body?: Json,
): Promise<Json> {
  const url = baseUrl();
  const key = adminKey();
  if (!url || !key) {
    throw new HttpsError(
      "failed-precondition",
      "Voice service is not configured (VOICE_SERVICE_URL / VOICE_SERVICE_ADMIN_KEY).",
    );
  }
  const response = await fetch(`${url}${path}`, {
    method,
    headers: {"x-api-key": key, "content-type": "application/json"},
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let parsed: Json = {};
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch (_) {
    parsed = {raw: text.slice(0, 300)};
  }
  if (!response.ok) {
    const detail = typeof parsed.detail === "string" ? parsed.detail : `HTTP ${response.status}`;
    const code = response.status === 404 ? "not-found" :
      response.status === 409 ? "already-exists" :
        response.status === 422 ? "invalid-argument" : "internal";
    throw new HttpsError(code, `Voice service: ${detail}`);
  }
  return parsed;
}

function str(value: unknown, field: string, required = true): string {
  if (typeof value === "string" && value.trim()) return value.trim();
  if (required) throw new HttpsError("invalid-argument", `${field} is required`);
  return "";
}

function strList(value: unknown, field: string): string[] {
  if (value === undefined || value === null) return [];
  if (!Array.isArray(value) || value.some((v) => typeof v !== "string")) {
    throw new HttpsError("invalid-argument", `${field} must be a list of strings`);
  }
  return value as string[];
}

/** A bounded positive integer from the client, or the default. */
function int(value: unknown, fallback: number, max: number): number {
  const n = typeof value === "number" ? Math.floor(value) : NaN;
  return Number.isFinite(n) && n >= 1 ? Math.min(n, max) : fallback;
}

function queryString(params: Record<string, string | number | undefined>): string {
  const parts = Object.entries(params)
    .filter(([, v]) => v !== undefined && v !== "")
    .map(([k, v]) => `${k}=${encodeURIComponent(String(v))}`);
  return parts.length ? `?${parts.join("&")}` : "";
}

function functionsBaseUrl(): string {
  const project = process.env.GCLOUD_PROJECT || process.env.GCP_PROJECT || "";
  return `https://asia-south1-${project}.cloudfunctions.net`;
}

async function audit(
  request: {auth?: {token: Json} | undefined},
  actionType: string,
  details: Json,
): Promise<void> {
  try {
    await db().collection("audit_logs").add({
      adminEmail: request.auth?.token.email || "unknown",
      adminName: request.auth?.token.name || "Admin",
      actionType,
      details,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      status: "success",
    });
  } catch (error) {
    console.error("Failed to write audit log:", error);
  }
}

/**
 * actions:
 *  - upsertLine:      {twilioNumber, doctorIds[], clinicId?, label?, receptionistNumbers?,
 *                      greeting?, voiceId?, aiInstructions?, active?}
 *  - listLines:       {clinicId?}
 *  - deactivateLine:  {twilioNumber}
 *  - setEntitlement:  {clinicId, enabled}
 *  - getStatus:       {deep?}  -- deep makes one real Sarvam + Gemini call
 *  - listCalls:       {clinicId?, twilioNumber?, days?, limit?}
 *  - listAppointments:{clinicId?, days?, limit?}  -- bookings made by the AI
 */
export const manageReceptionistLines = onCall(
  {
    region: "asia-south1",
    maxInstances: 5,
    secrets: [voiceServiceAdminKey, voiceBotApiKeySecret],
  },
  async (request) => {
    if (!request.auth || request.auth.token.role !== "superAdmin") {
      throw new HttpsError("permission-denied", "Only Super Admin can manage receptionist lines");
    }
    const data = (request.data || {}) as Json;
    const action = str(data.action, "action");

    switch (action) {
    case "getStatus":
      return callVoiceService(
        "GET", `/api/admin/status${data.deep === true ? "?deep=true" : ""}`);

    case "listCalls":
      return callVoiceService("GET", `/api/admin/calls${queryString({
        clinic_external_id: str(data.clinicId, "clinicId", false),
        twilio_number: str(data.twilioNumber, "twilioNumber", false),
        days: int(data.days, 7, 90),
        limit: int(data.limit, 50, 200),
      })}`);

    case "listAppointments":
      return callVoiceService("GET", `/api/admin/appointments${queryString({
        clinic_external_id: str(data.clinicId, "clinicId", false),
        days: int(data.days, 30, 365),
        limit: int(data.limit, 100, 500),
      })}`);

    case "listLines": {
      const clinicId = str(data.clinicId, "clinicId", false);
      const query = clinicId ? `?clinic_external_id=${encodeURIComponent(clinicId)}` : "";
      return callVoiceService("GET", `/api/admin/receptionist-lines${query}`);
    }

    case "deactivateLine": {
      const twilioNumber = str(data.twilioNumber, "twilioNumber");
      const result = await callVoiceService(
        "DELETE", `/api/admin/receptionist-lines/${encodeURIComponent(twilioNumber)}`);
      await audit(request, "deactivatedReceptionistLine", {twilioNumber});
      return result;
    }

    case "setEntitlement": {
      const clinicId = str(data.clinicId, "clinicId");
      const enabled = data.enabled === true;
      const result = await callVoiceService(
        "PUT", `/api/admin/clinics/${encodeURIComponent(clinicId)}/entitlement`, {enabled});
      await audit(request, "setReceptionistEntitlement", {clinicId, enabled});
      return result;
    }

    case "upsertLine": {
      const twilioNumber = str(data.twilioNumber, "twilioNumber");
      const doctorIds = strList(data.doctorIds, "doctorIds");
      if (doctorIds.length === 0) {
        throw new HttpsError("invalid-argument", "Pick at least one doctor for this line");
      }

      // Doctor details come from our own records, never from the client.
      const doctors: Json[] = [];
      let timezone = "";
      let clinicName = "";
      for (const uid of doctorIds) {
        const snap = await db().collection("users").doc(uid).get();
        if (!snap.exists) throw new HttpsError("not-found", `Doctor ${uid} not found`);
        const user = snap.data() as Json;
        const modules = Array.isArray(user.enabledModules) ? user.enabledModules : [];
        if (!modules.includes(AI_RECEPTIONIST_MODULE)) {
          throw new HttpsError(
            "failed-precondition",
            `${user.name || uid} does not have the AI receptionist (premium) enabled`,
          );
        }
        doctors.push({
          external_provider_id: uid,
          name: String(user.name || uid),
          specialization: user.specialization ? String(user.specialization) : null,
        });
        timezone = timezone || String(user.timeZone || "");
        clinicName = clinicName || String(user.clinicName || "");
      }

      // A group line needs an explicit clinic id; a single doctor is their own.
      const clinicId = str(data.clinicId, "clinicId", false) || (doctorIds.length === 1 ? doctorIds[0] : "");
      if (!clinicId) {
        throw new HttpsError("invalid-argument", "clinicId is required for a multi-doctor line");
      }

      const line: Json = {
        clinic: {
          external_id: clinicId,
          name: clinicName || String(doctors[0].name),
          timezone: timezone || "Asia/Kolkata",
          ai_receptionist_enabled: true,
          // How the voice service books into CruDoc for this clinic.
          config: {
            appointment_provider: "crudoc",
            appointment_provider_config: {
              base_url: functionsBaseUrl(),
              api_key: voiceBotApiKeySecret.value().trim(),
            },
          },
        },
        label: str(data.label, "label", false) || null,
        active: data.active !== false,
        doctors,
        receptionist_numbers: strList(data.receptionistNumbers, "receptionistNumbers"),
        config: {
          ...(str(data.greeting, "greeting", false) ? {greeting: str(data.greeting, "greeting")} : {}),
          ...(str(data.voiceId, "voiceId", false) ? {voice_id: str(data.voiceId, "voiceId")} : {}),
          ...(str(data.aiInstructions, "aiInstructions", false) ?
            {ai_instructions: str(data.aiInstructions, "aiInstructions")} : {}),
        },
      };
      const result = await callVoiceService(
        "PUT", `/api/admin/receptionist-lines/${encodeURIComponent(twilioNumber)}`, line);
      await audit(request, "upsertedReceptionistLine", {twilioNumber, clinicId, doctorIds});
      return result;
    }

    default:
      throw new HttpsError("invalid-argument", `Unknown action: ${action}`);
    }
  },
);
