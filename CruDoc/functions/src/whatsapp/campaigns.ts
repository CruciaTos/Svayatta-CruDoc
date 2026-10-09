import {normalisePhone} from "./format";
import {CLINIC_CAMPAIGN} from "./templates";

/**
 * Turning a campaign into outbox rows.
 *
 * A WhatsApp campaign is business-initiated outreach, so every message uses the
 * approved {@link CLINIC_CAMPAIGN} MARKETING template — never free text. The
 * doctor's composed note is carried as one template variable.
 *
 * The planning is a pure function so the rules that decide who is messaged —
 * valid mobile, has a name, has not opted out, not a duplicate within the one
 * send — are testable without Firestore or Meta.
 */

export const CAMPAIGN_TEMPLATE_KEY = CLINIC_CAMPAIGN.key;

export interface CampaignRecipientInput {
  patientId?: string | null;
  /** Raw phone as stored on the patient; normalised here. */
  phone?: string | null;
  firstName?: string | null;
}

export interface PlannedCampaignMessage {
  patientId: string | null;
  /** Normalised E.164-digits phone. */
  phone: string;
  params: Record<string, string>;
  /** Idempotency key: one message per patient (or phone) per campaign. */
  dedupeKey: string;
}

export type CampaignSkipReason =
  | "invalid_or_missing_phone"
  | "no_patient_name"
  | "opted_out"
  | "duplicate";

export interface CampaignPlan {
  messages: PlannedCampaignMessage[];
  skipped: Record<CampaignSkipReason, number>;
}

export interface PlanCampaignParams {
  campaignId: string;
  /** The doctor's composed note; becomes the {{3}} template variable. */
  message: string;
  clinicName: string;
  clinicPhone: string;
  recipients: CampaignRecipientInput[];
  /** Normalised phones that have opted out (see {@link filterOptedOut}). */
  optedOut: Set<string>;
}

function emptySkips(): Record<CampaignSkipReason, number> {
  return {
    invalid_or_missing_phone: 0,
    no_patient_name: 0,
    opted_out: 0,
    duplicate: 0,
  };
}

/**
 * Decides who gets a message and with what parameters. Does not send or touch
 * Firestore.
 */
export function planCampaign(params: PlanCampaignParams): CampaignPlan {
  const skipped = emptySkips();
  const messages: PlannedCampaignMessage[] = [];
  const seen = new Set<string>();

  const message = params.message.trim();
  const clinicName = params.clinicName.trim();
  const clinicPhone = params.clinicPhone.trim();

  for (const r of params.recipients) {
    const phone = normalisePhone(r.phone);
    if (!phone) {
      skipped.invalid_or_missing_phone++;
      continue;
    }

    const firstName = (r.firstName || "").trim();
    if (!firstName) {
      skipped.no_patient_name++;
      continue;
    }

    if (params.optedOut.has(phone)) {
      skipped.opted_out++;
      continue;
    }

    if (seen.has(phone)) {
      skipped.duplicate++;
      continue;
    }
    seen.add(phone);

    const patientId = r.patientId ? String(r.patientId) : null;
    messages.push({
      patientId,
      phone,
      params: {
        patientFirstName: firstName,
        clinicName,
        message,
        clinicPhone,
      },
      dedupeKey: `camp_${params.campaignId}_${patientId ?? phone}`,
    });
  }

  return {messages, skipped};
}
