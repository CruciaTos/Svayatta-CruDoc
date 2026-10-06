/**
 * Dates, times and names as they appear in a reminder.
 *
 * Cloud Functions containers run on UTC. The old code formatted with
 * `toLocaleDateString("en-US", ...)` and no `timeZone`, so an 11:00 AM IST
 * appointment was announced to the patient as 5:30 AM. Everything here takes
 * the clinic's zone explicitly.
 */

/** India has no daylight saving, so a fixed offset is safe. */
const IST_OFFSET_MINUTES = 330;

export const CLINIC_TIME_ZONE = "Asia/Kolkata";
export const CLINIC_LOCALE = "en-IN";

/** "Tue, 6 Oct" in the clinic's zone. */
export function formatDate(
  when: Date,
  timeZone: string = CLINIC_TIME_ZONE,
): string {
  return new Intl.DateTimeFormat(CLINIC_LOCALE, {
    timeZone,
    weekday: "short",
    day: "numeric",
    month: "short",
  }).format(when);
}

/**
 * "11:00 AM" in the clinic's zone.
 *
 * ICU renders the meridiem lower case in some versions and as "a.m." in
 * others, so it is normalised rather than left to the runtime.
 */
export function formatTime(
  when: Date,
  timeZone: string = CLINIC_TIME_ZONE,
): string {
  const raw = new Intl.DateTimeFormat(CLINIC_LOCALE, {
    timeZone,
    hour: "numeric",
    minute: "2-digit",
    hour12: true,
  }).format(when);

  // ICU separates the time and the meridiem with a narrow no-break space,
  // which \s matches, so collapsing whitespace first makes the rest simple.
  return raw
    .replace(/\ba\.?\s?m\.?/i, "AM")
    .replace(/\bp\.?\s?m\.?/i, "PM")
    .replace(/\s+/g, " ")
    .trim();
}

/**
 * The span of a day in the clinic's zone, as absolute instants.
 *
 * Used to pick "tomorrow's" appointments. Comparing against a UTC day would
 * take in the wrong 5.5 hours at each end, so an 8:00 PM appointment would be
 * reminded about on the wrong evening.
 */
export function istDayRange(
  from: Date,
  addDays = 0,
): {start: Date; end: Date} {
  const shifted = new Date(from.getTime() + IST_OFFSET_MINUTES * 60_000);
  const startMs =
    Date.UTC(
      shifted.getUTCFullYear(),
      shifted.getUTCMonth(),
      shifted.getUTCDate() + addDays,
    ) - IST_OFFSET_MINUTES * 60_000;

  return {
    start: new Date(startMs),
    end: new Date(startMs + 24 * 60 * 60 * 1000),
  };
}

/**
 * The patient's first name.
 *
 * The reminder greets by first name only: it is friendlier, and it keeps the
 * message from identifying someone in full on a screen another person may see.
 */
export function firstNameOf(patient: {
  firstName?: string;
  lastName?: string;
  fullName?: string;
}): string {
  const direct = (patient.firstName || "").trim();
  if (direct) return direct.split(/\s+/)[0];

  const full = (patient.fullName || "").trim();
  if (full) return full.split(/\s+/)[0];

  return "";
}

/**
 * The patient's full name, however the record happens to store it.
 *
 * One path used firstName + lastName and another used fullName, so whichever
 * record shape was not expected produced a blank name in the message.
 */
export function fullNameOf(patient: {
  firstName?: string;
  lastName?: string;
  fullName?: string;
}): string {
  const full = (patient.fullName || "").trim();
  if (full) return full;

  const joined = [patient.firstName, patient.lastName]
    .map((p) => (p || "").trim())
    .filter(Boolean)
    .join(" ");

  return joined;
}

/**
 * Normalises a phone number to digits only, with a country code and no "+",
 * which is the form both wa.me and the Cloud API take.
 *
 * Returns null when the number cannot be a mobile, so the caller logs a skip
 * rather than sending into the void.
 */
export function normalisePhone(
  raw: string | null | undefined,
  defaultCountryCode = "91",
): string | null {
  if (!raw || typeof raw !== "string") return null;

  let digits = raw.replace(/\D/g, "");
  if (!digits) return null;

  digits = digits.replace(/^0+/, "");

  if (digits.length === 10) {
    digits = `${defaultCountryCode}${digits}`;
  }

  if (digits.length < 10 || digits.length > 15) return null;

  // An Indian mobile is 10 digits starting 6-9. Landlines and short codes
  // cannot receive WhatsApp, so they are refused here rather than failing at
  // Meta with an unhelpful error.
  if (digits.startsWith("91")) {
    const local = digits.slice(2);
    if (local.length !== 10 || !/^[6-9]/.test(local)) return null;
  }

  return digits;
}
