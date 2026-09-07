import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

export const geminiApiKeySecret = defineSecret("GEMINI_API_KEY");

function getGeminiApiKey(): string {
  try {
    const val = geminiApiKeySecret.value();
    if (val && val.trim().length > 0) return val.trim();
  } catch (_) {
    // Falls back to process.env in local/emulator environments
  }
  const envVal = process.env.GEMINI_API_KEY || "";
  return envVal.trim();
}

const GEMINI_MODEL = "gemini-2.0-flash";
const GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models";

const ASSISTANT_SYSTEM_PROMPT = `
You are **CruDoc AI Assistant**, an intelligent, highly knowledgeable, and versatile clinical & practice companion for doctors, healthcare practitioners, and clinic administrators using the CruDoc application.

## Your Mission:
You must answer ANY question asked regarding the CruDoc application, clinical workflows, patient management, medical science, pharmacology, or app navigation with complete accuracy, clarity, and helpfulness.

## CruDoc Knowledge Base:
- Tab 0: Dashboard (Revenue Snapshot, Privacy Eye toggle, Live Stats Grid, Quick Actions, Today's Visits, Low Stock Banner)
- Tab 1: Patient Records (Add Patient, Search & Filter, Patient Details, Quick Contact WhatsApp/Phone)
- Tab 2: Inventory & Pharmacy (Add Medicine, Stock Tracking, Adjust Stock, Expiry Alerts)
- Tab 3: Revenue & Billing (Create Invoice, Payment Statuses, PDF Export & WhatsApp Sharing)
- Tab 4: Appointments & Visits (Schedule Visit, In-Clinic vs Home Visit, Google Places address, Automated WhatsApp Reminders)
- Tab 5: Patient Campaigns (Email & WhatsApp broadcast outreach)
- AI Voice Scribe: Ambient consultation recording & structured clinical note extraction
- Center AI Assistant: Voice dictation, clinical inquiry & application companion

## Tone & Formatting Guidelines:
- Answer warmly, accurately, and professionally.
- Always provide structured, easy-to-follow steps using Markdown: headers (###), bullet points (•), and bold text.
- If asked about clinical topics, provide accurate medical knowledge with appropriate clinical reminders.
`;

/**
 * Doctor-authenticated assistant consultation callable function.
 * Authenticates the doctor and routes queries through Gemini with server-side API key.
 */
export const chatWithAssistant = onCall(
  {
    region: "asia-south1",
    maxInstances: 10,
    secrets: [geminiApiKeySecret],
  },
  async (request) => {
    // 1. Multi-tenant authentication check
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Authentication required to access CruDoc AI Assistant."
      );
    }

    const {message, history, enabledModules} = request.data || {};
    if (!message || typeof message !== "string" || message.trim().length === 0) {
      throw new HttpsError("invalid-argument", "Message cannot be empty.");
    }

    const apiKey = getGeminiApiKey();
    if (!apiKey) {
      console.error("[chatWithAssistant] GEMINI_API_KEY not configured in Secret Manager or env");
      throw new HttpsError("failed-precondition", "AI Assistant service is currently not configured.");
    }

    // Build active prompt with locked module instructions if applicable
    let activePrompt = ASSISTANT_SYSTEM_PROMPT;
    if (Array.isArray(enabledModules)) {
      activePrompt += `\n\n## DOCTOR CONFIGURED MODULES: ${enabledModules.join(", ")}`;
    }

    const contents: any[] = [];
    if (Array.isArray(history)) {
      for (const item of history.slice(-10)) {
        if (item && item.role && item.parts) {
          contents.push({
            role: item.role === "user" ? "user" : "model",
            parts: item.parts,
          });
        }
      }
    }

    contents.push({
      role: "user",
      parts: [{text: message.trim()}],
    });

    const url = `${GEMINI_BASE_URL}/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          system_instruction: {
            parts: [{text: activePrompt}],
          },
          contents,
          generationConfig: {
            temperature: 0.7,
            topP: 0.95,
            topK: 40,
            maxOutputTokens: 1024,
          },
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error(`[chatWithAssistant] Gemini API returned ${response.status}:`, errorText);
        throw new HttpsError("internal", "AI Assistant service encountered an error.");
      }

      const data: any = await response.json();
      const candidate = data.candidates?.[0];
      const replyText = candidate?.content?.parts?.[0]?.text || "";

      return {reply: replyText.trim()};
    } catch (err: any) {
      if (err instanceof HttpsError) throw err;
      console.error("[chatWithAssistant] Network error:", err);
      throw new HttpsError("internal", "Failed to communicate with AI Assistant.");
    }
  }
);

/**
 * Doctor-authenticated audio transcription callable function.
 * Transcribes audio recordings using Gemini multimodal capability.
 */
export const transcribeVoiceAudio = onCall(
  {
    region: "asia-south1",
    maxInstances: 10,
    secrets: [geminiApiKeySecret],
  },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Authentication required to transcribe audio."
      );
    }

    const {audioBase64, mimeType = "audio/mp4"} = request.data || {};
    if (!audioBase64 || typeof audioBase64 !== "string") {
      throw new HttpsError("invalid-argument", "audioBase64 is required.");
    }

    const apiKey = getGeminiApiKey();
    if (!apiKey) {
      console.error("[transcribeVoiceAudio] GEMINI_API_KEY not configured");
      throw new HttpsError("failed-precondition", "Transcription service is currently unconfigured.");
    }

    const prompt =
      "Transcribe the spoken audio query verbatim. " +
      "The speaker is a doctor asking a question or giving a command. " +
      "Return ONLY the direct transcribed text. " +
      "Do NOT include formatting tags, quotes, explanations, or timestamps.";

    const url = `${GEMINI_BASE_URL}/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          contents: [
            {
              role: "user",
              parts: [
                {text: prompt},
                {
                  inline_data: {
                    mime_type: mimeType,
                    data: audioBase64,
                  },
                },
              ],
            },
          ],
          generationConfig: {
            temperature: 0.1,
            maxOutputTokens: 256,
          },
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error(`[transcribeVoiceAudio] Gemini error ${response.status}:`, errorText);
        throw new HttpsError("internal", "Failed to transcribe audio.");
      }

      const data: any = await response.json();
      const text = data.candidates?.[0]?.content?.parts?.[0]?.text || "";
      return {text: text.trim().replace(/^["']|["']$/g, "")};
    } catch (err: any) {
      if (err instanceof HttpsError) throw err;
      console.error("[transcribeVoiceAudio] Error:", err);
      throw new HttpsError("internal", "Audio transcription failed.");
    }
  }
);

/**
 * Doctor-authenticated Homeopathy Case Sheet extraction callable function.
 */
export const extractHomeopathyCaseSheet = onCall(
  {
    region: "asia-south1",
    maxInstances: 10,
    secrets: [geminiApiKeySecret],
  },
  async (request) => {
    if (!request.auth || !request.auth.uid) {
      throw new HttpsError(
        "unauthenticated",
        "Authentication required to extract homeopathy case sheet."
      );
    }

    const {transcript} = request.data || {};
    if (!transcript || typeof transcript !== "string" || transcript.trim().length === 0) {
      throw new HttpsError("invalid-argument", "transcript is required.");
    }

    const apiKey = getGeminiApiKey();
    if (!apiKey) {
      console.error("[extractHomeopathyCaseSheet] GEMINI_API_KEY not configured");
      throw new HttpsError("failed-precondition", "AI Scribe service is currently unconfigured.");
    }

    const systemPrompt = `
You are an expert Homeopathic Clinical Scribe assistant.
Analyze a doctor's spoken case notes or patient consultation transcript, and extract the clinical details into structured JSON matching a Homeopathy Case Sheet.
CRITICAL: Return ONLY valid raw JSON with NO markdown formatting, NO backticks, and NO extra explanations.
`;

    const url = `${GEMINI_BASE_URL}/${GEMINI_MODEL}:generateContent?key=${apiKey}`;

    try {
      const response = await fetch(url, {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          system_instruction: {
            parts: [{text: systemPrompt}],
          },
          contents: [
            {
              role: "user",
              parts: [{text: transcript}],
            },
          ],
          generationConfig: {
            temperature: 0.2,
            maxOutputTokens: 2048,
          },
        }),
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error(`[extractHomeopathyCaseSheet] Gemini error ${response.status}:`, errorText);
        throw new HttpsError("internal", "Failed to extract case sheet.");
      }

      const data: any = await response.json();
      const rawText = data.candidates?.[0]?.content?.parts?.[0]?.text || "";
      const cleaned = rawText.replace(/```json/g, "").replace(/```/g, "").trim();

      try {
        const parsed = JSON.parse(cleaned);
        return {caseSheet: parsed};
      } catch (_) {
        return {rawResponse: cleaned};
      }
    } catch (err: any) {
      if (err instanceof HttpsError) throw err;
      console.error("[extractHomeopathyCaseSheet] Error:", err);
      throw new HttpsError("internal", "Failed to process case sheet extraction.");
    }
  }
);
