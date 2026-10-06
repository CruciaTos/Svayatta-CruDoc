/**
 * The message templates CruDoc sends.
 *
 * Meta requires every business-initiated message to use a template approved in
 * advance. Free text only reaches a patient inside the 24-hour window their own
 * reply opens, which is not how a reminder is triggered.
 *
 * Launch sends one template from one shared CruDoc number, so there is exactly
 * one entry here. Per-clinic numbers and the wider catalogue are the upgrade
 * path (see docs/whatsapp-meta-status.md); this file is where they would
 * return, which is why it is still a registry rather than a single constant.
 *
 * Writing bodies that pass review:
 *  - A body may not start or end with a variable, and two variables may not sit
 *    next to each other.
 *  - Variables are numbered from 1, in the order they appear.
 *  - A body that is mostly one big variable gets rejected.
 *  - UTILITY is for messages about something the patient already did. Anything
 *    that reads promotional gets re-categorised as MARKETING, which costs more
 *    and needs its own opt-in.
 */

export type TemplateCategory = "UTILITY" | "MARKETING";

export interface TemplateSpec {
  /** Stable internal key. Never sent to Meta. */
  key: string;
  /** The name registered in WhatsApp Manager. */
  name: string;
  category: TemplateCategory;
  /** Language code. Must match how the template was created. */
  language: string;
  /** Named parameters, in the positional order the body expects. */
  paramOrder: string[];
  /** Body text as submitted to Meta, with {{n}} placeholders. */
  body: string;
  /** Sample values Meta shows reviewers. */
  example: Record<string, string>;
}

/**
 * The day-before appointment reminder.
 *
 * Deliberately carries no medical information. A reminder naming a procedure
 * would disclose health data to anyone who glances at the patient's phone, and
 * would also read as something other than a utility message to Meta.
 */
export const APPOINTMENT_REMINDER: TemplateSpec = {
  key: "appointment_reminder",
  name: "appointment_reminder_v1",
  category: "UTILITY",
  language: "en",
  paramOrder: [
    "patientFirstName",
    "clinicName",
    "doctorName",
    "date",
    "time",
    "clinicPhone",
  ],
  body:
    "Hi {{1}}, this is a reminder of your appointment at {{2}} with {{3}} on " +
    "{{4}} at {{5}}. To reschedule, please call the clinic on {{6}}. " +
    "Reply STOP to stop these reminders.",
  example: {
    patientFirstName: "Rahul",
    clinicName: "Smile Dental Clinic",
    doctorName: "Dr. Mehta",
    date: "Tue, 6 Oct",
    time: "11:00 AM",
    clinicPhone: "9812345678",
  },
};

export const TEMPLATES: Record<string, TemplateSpec> = {
  [APPOINTMENT_REMINDER.key]: APPOINTMENT_REMINDER,
};

export const TEMPLATE_KEYS = Object.keys(TEMPLATES);

export function templateFor(key: string): TemplateSpec {
  const t = TEMPLATES[key];
  if (!t) throw new Error(`Unknown WhatsApp template: ${key}`);
  return t;
}

/** Strips what Meta rejects: newlines, tabs, and long runs of spaces. */
export function sanitiseParam(value: string | null | undefined): string {
  if (!value) return "";
  return value.replace(/[\r\n\t]+/g, " ").replace(/ {4,}/g, "   ").trim();
}

/**
 * Turns named parameters into the positional array Meta expects.
 *
 * Parameters stay named everywhere else and only become positional here. The
 * old code passed six positional strings straight from the call site, so the
 * clinic name and the doctor name could be — and were — the wrong way round
 * without anything failing: the patient simply received a plausible message
 * with the wrong words in it.
 *
 * A missing value throws rather than sending a blank, because Meta accepts an
 * empty parameter and the patient gets "your appointment at  with ".
 */
export function toPositionalParams(
  spec: TemplateSpec,
  params: Record<string, string>,
): string[] {
  const missing: string[] = [];
  const ordered = spec.paramOrder.map((name) => {
    const value = sanitiseParam(params[name]);
    if (!value) missing.push(name);
    return value;
  });

  if (missing.length) {
    throw new Error(`Template ${spec.key} is missing: ${missing.join(", ")}`);
  }
  return ordered;
}

/** The `components` array for a send. */
export function buildMessageComponents(
  spec: TemplateSpec,
  params: Record<string, string>,
): Array<Record<string, unknown>> {
  return [{
    type: "body",
    parameters: toPositionalParams(spec, params).map((text) => ({
      type: "text",
      text,
    })),
  }];
}

/**
 * The payload for creating this template in WhatsApp Manager.
 *
 * The template is registered by hand once (see whatsapp_shared_number.md
 * section 3), so this is not called in production. It exists so the body and
 * the examples that were submitted live beside the code that sends them, and
 * so the tests can check the body against Meta's formatting rules.
 */
export function buildCreationPayload(
  spec: TemplateSpec,
): Record<string, unknown> {
  const components: Array<Record<string, unknown>> = [{
    type: "BODY",
    text: spec.body,
    example: {
      body_text: [spec.paramOrder.map((n) => spec.example[n] || n)],
    },
  }];

  if (spec.category === "MARKETING") {
    components.push({
      type: "BUTTONS",
      buttons: [{type: "QUICK_REPLY", text: "Stop promotions"}],
    });
  }

  return {
    name: spec.name,
    language: spec.language,
    category: spec.category,
    components,
  };
}
