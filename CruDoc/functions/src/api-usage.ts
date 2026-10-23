import * as admin from "firebase-admin";
import {FieldValue} from "firebase-admin/firestore";

/**
 * Server-side twin of the clinic app's ApiUsage
 * (lib/core/services/api_usage_service.dart): counters for paid outside
 * services at `users/{uid}/api_usage/{yyyy-MM-dd}` (India's date), which
 * Super Admin adds up. Counters only, never message text or numbers.
 * Recording never fails the send it describes.
 */
export type ApiService = "gemini" | "sarvam" | "whatsapp" | "places" | "maps";

/** yyyy-MM-dd in India, where the clinics are. */
export function istDay(at: Date = new Date()): string {
  return new Date(at.getTime() + 330 * 60 * 1000).toISOString().slice(0, 10);
}

export async function recordApiUsage(
  uid: string,
  service: ApiService,
  feature: string,
  opts: {error?: boolean; count?: number} = {},
): Promise<void> {
  if (!uid) return;
  const count = opts.count ?? 1;
  const day = istDay();
  try {
    await admin.firestore()
      .collection("users").doc(uid)
      .collection("api_usage").doc(day)
      .set({
        date: day,
        clinicId: uid,
        updatedAt: FieldValue.serverTimestamp(),
        [service]: {
          calls: FieldValue.increment(count),
          ...(opts.error ? {errors: FieldValue.increment(1)} : {}),
          features: {[feature]: FieldValue.increment(count)},
        },
      }, {merge: true});
  } catch (err) {
    console.warn(`[ApiUsage] not saved for ${service}/${feature}:`, err);
  }
}
