import * as admin from "firebase-admin";

/**
 * A clinic's reminder settings and message wording.
 *
 * Stored on the owner's `users/{uid}` document, next to the existing
 * `whatsappRemindersEnabled` switch the app already writes:
 *
 *   whatsappRemindersEnabled  appointment reminders on/off (absent = on)
 *   recallsEnabled            automatic recalls on/off (absent = off)
 *   reminderChannelOrder      ["whatsapp", "email"] in the clinic's order
 *   reminderTemplates         { reminder: {emailSubject, emailBody},
 *                               recall:   {emailSubject, emailBody} }
 *
 * WhatsApp wording is not editable: Meta approves a template once, so the
 * clinic only ever uses CruDoc's approved names.
 */

export type ReminderKind = "reminder" | "recall";
export type Channel = "whatsapp" | "email";

export interface EmailTemplate {
  subject: string;
  body: string;
}

export interface ReminderSettings {
  remindersEnabled: boolean;
  recallsEnabled: boolean;
  channelOrder: Channel[];
  email: Record<ReminderKind, EmailTemplate>;
}

export interface TemplateVars {
  patient: string;
  date: string;
  time: string;
  clinic: string;
  doctor: string;
  /** Recall only: the reason on the recall, e.g. "check-up and cleaning". */
  reason?: string;
}

export const DEFAULT_EMAIL_TEMPLATES: Record<ReminderKind, EmailTemplate> = {
  reminder: {
    subject: "Appointment reminder from {clinic}",
    body:
      "Hi {patient},\n\n" +
      "This is a reminder of your appointment with {doctor} at {clinic} " +
      "on {date} at {time}.\n\n" +
      "If you need to reschedule, please call the clinic.\n\n" +
      "See you soon,\n{clinic}",
  },
  recall: {
    subject: "Time for your next visit to {clinic}",
    body:
      "Hi {patient},\n\n" +
      "It is time to book your next visit with {doctor} at {clinic}. " +
      "Your recall is due on {date}.\n\n" +
      "Please call the clinic to pick a time that suits you.\n\n" +
      "Thank you,\n{clinic}",
  },
};

export const EMAIL_FOOTER =
  "You're receiving this because you're a patient of {clinic}. " +
  "To stop these reminders, reply to this email or let the clinic know.";

const MAX_SUBJECT = 200;
const MAX_BODY = 3000;

function cleanText(value: unknown, max: number, fallback: string): string {
  if (typeof value !== "string") return fallback;
  const trimmed = value.trim();
  return trimmed ? trimmed.slice(0, max) : fallback;
}

/** Reads settings off the owner's profile, falling back to the defaults. */
export function readSettings(
  data: admin.firestore.DocumentData | undefined,
): ReminderSettings {
  const d = data || {};

  const rawOrder = Array.isArray(d.reminderChannelOrder) ?
    d.reminderChannelOrder.map((c: unknown) => String(c)) :
    [];
  const order: Channel[] = [];
  for (const c of rawOrder) {
    if ((c === "whatsapp" || c === "email") && !order.includes(c)) {
      order.push(c);
    }
  }
  for (const c of ["whatsapp", "email"] as Channel[]) {
    if (!order.includes(c)) order.push(c);
  }

  const stored = (d.reminderTemplates && typeof d.reminderTemplates === "object") ?
    d.reminderTemplates as Record<string, Record<string, unknown>> :
    {};
  const email = {} as Record<ReminderKind, EmailTemplate>;
  for (const kind of ["reminder", "recall"] as ReminderKind[]) {
    const def = DEFAULT_EMAIL_TEMPLATES[kind];
    const mine = stored[kind] || {};
    email[kind] = {
      subject: cleanText(mine.emailSubject, MAX_SUBJECT, def.subject),
      body: cleanText(mine.emailBody, MAX_BODY, def.body),
    };
  }

  return {
    remindersEnabled: d.whatsappRemindersEnabled !== false,
    recallsEnabled: d.recallsEnabled === true,
    channelOrder: order,
    email,
  };
}

/** Replaces {patient}, {date}, {time}, {clinic}, {doctor} and {reason}. */
export function fill(template: string, vars: TemplateVars): string {
  return template.replace(
    /\{(patient|date|time|clinic|doctor|reason)\}/g,
    (_, key: keyof TemplateVars) => (vars[key] ?? "").toString(),
  );
}

/** The email as sent: the clinic's wording plus the fixed footer. */
export function renderEmail(
  template: EmailTemplate,
  vars: TemplateVars,
): EmailTemplate {
  return {
    subject: fill(template.subject, vars),
    body: `${fill(template.body, vars)}\n\n--\n${fill(EMAIL_FOOTER, vars)}`,
  };
}
