import {
  computeOpenSlots, DEFAULT_SLOT_MINUTES, DEFAULT_TZ_OFFSET_MINUTES,
  instantFromClinicLocal, normaliseTime,
} from "../appointments";

/**
 * Clinic-local dates, working hours and slots for the AI receptionist.
 *
 * Pure: no Firestore. Everything the voice agent sees is clinic-local
 * ("2026-10-10", "17:30"), never UTC, because a model converting zones in
 * the middle of a call will eventually get it wrong. India has no daylight
 * saving, so a fixed +05:30 is exact.
 */

const OFFSET_MS = DEFAULT_TZ_OFFSET_MINUTES * 60_000;
const DAY_MS = 24 * 60 * 60 * 1000;

export const WEEKDAY_KEYS = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"] as const;
export type WeekdayKey = typeof WEEKDAY_KEYS[number];
const WEEKDAY_NAMES = [
  "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
];
const WEEKDAY_SHORT = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June", "July", "August",
  "September", "October", "November", "December",
];

export type Hours = Record<WeekdayKey, Array<[string, string]>>;

export interface DoctorSchedule {
  hours: Hours;
  slotMinutes: number;
  /** Clinic-local dates (YYYY-MM-DD) the doctor is away. */
  daysOff: string[];
  /** True when the doctor hasn't set hours and the default is in use. */
  defaulted: boolean;
}

/** Used until the doctor sets their own hours in the app. */
export const DEFAULT_HOURS: Hours = {
  sun: [],
  mon: [["09:00", "18:00"]],
  tue: [["09:00", "18:00"]],
  wed: [["09:00", "18:00"]],
  thu: [["09:00", "18:00"]],
  fri: [["09:00", "18:00"]],
  sat: [["09:00", "18:00"]],
};

/** How far ahead the AI may book. */
export const MAX_DAYS_AHEAD = 60;

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

function validTime(raw: unknown): string | null {
  if (typeof raw !== "string") return null;
  const t = normaliseTime(raw);
  const m = t.match(/^(\d{2}):(\d{2})$/);
  if (!m || Number(m[1]) > 23 || Number(m[2]) > 59) return null;
  return t;
}

/**
 * Reads `users/{uid}.aiReceptionist`, falling back field by field. A
 * malformed day is treated as closed rather than as open all day.
 */
export function scheduleFrom(raw: unknown): DoctorSchedule {
  const src = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  const hoursRaw = src.hours && typeof src.hours === "object" ?
    src.hours as Record<string, unknown> :
    null;

  let hours: Hours = DEFAULT_HOURS;
  if (hoursRaw) {
    hours = {} as Hours;
    for (const key of WEEKDAY_KEYS) {
      const day = Array.isArray(hoursRaw[key]) ? hoursRaw[key] as unknown[] : [];
      hours[key] = [];
      for (const range of day) {
        const pair = Array.isArray(range) ? range :
          (range && typeof range === "object" ?
            [(range as Record<string, unknown>).open, (range as Record<string, unknown>).close] :
            []);
        const open = validTime(pair[0]);
        const close = validTime(pair[1]);
        if (open && close && open < close) hours[key].push([open, close]);
      }
      hours[key].sort((a, b) => a[0].localeCompare(b[0]));
    }
  }

  const slot = typeof src.slotMinutes === "number" && Number.isInteger(src.slotMinutes) &&
    src.slotMinutes >= 5 && src.slotMinutes <= 240 ?
    src.slotMinutes :
    DEFAULT_SLOT_MINUTES;

  const daysOff = Array.isArray(src.daysOff) ?
    src.daysOff.filter((d): d is string => typeof d === "string" && DATE_RE.test(d)) :
    [];

  return {hours, slotMinutes: slot, daysOff, defaulted: !hoursRaw};
}

// ------------------------------------------------------------------ dates

/** "2026-10-10" in the clinic's zone. */
export function localDateOf(instant: Date): string {
  return new Date(instant.getTime() + OFFSET_MS).toISOString().slice(0, 10);
}

/** "17:30" in the clinic's zone. */
export function localTimeOf(instant: Date): string {
  return new Date(instant.getTime() + OFFSET_MS).toISOString().slice(11, 16);
}

/** "202610", the clinic-local month, for usage counters. */
export function monthKeyOf(instant: Date): string {
  return localDateOf(instant).slice(0, 7).replace("-", "");
}

function dateParts(date: string): [number, number, number] {
  const [y, m, d] = date.split("-").map(Number);
  return [y, m, d];
}

export function weekdayIndex(date: string): number {
  const [y, m, d] = dateParts(date);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

export function weekdayName(date: string): string {
  return WEEKDAY_NAMES[weekdayIndex(date)];
}

export function addDays(date: string, days: number): string {
  const [y, m, d] = dateParts(date);
  return new Date(Date.UTC(y, m - 1, d) + days * DAY_MS).toISOString().slice(0, 10);
}

/**
 * The date the model asked for, as YYYY-MM-DD, or null. Accepts the words
 * "today" and "tomorrow" as well, since a model under time pressure will
 * sometimes send those instead of computing the date.
 */
export function resolveDate(raw: unknown, now: Date): string | null {
  if (typeof raw !== "string") return null;
  const v = raw.trim().toLowerCase();
  const today = localDateOf(now);
  if (v === "today" || v === "aaj") return today;
  if (v === "tomorrow" || v === "kal") return addDays(today, 1);
  if (v === "day after tomorrow" || v === "parso") return addDays(today, 2);
  if (!DATE_RE.test(v)) return null;
  const [y, m, d] = dateParts(v);
  const check = new Date(Date.UTC(y, m - 1, d));
  if (check.getUTCMonth() !== m - 1 || check.getUTCDate() !== d) return null;
  return v;
}

/** Days between two clinic-local dates (b - a). */
export function daysBetween(a: string, b: string): number {
  const [ay, am, ad] = dateParts(a);
  const [by, bm, bd] = dateParts(b);
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / DAY_MS);
}

// ------------------------------------------------------------------ hours

/** The doctor's working ranges on a date, as instants. Empty when closed. */
export function rangesOn(schedule: DoctorSchedule, date: string): Array<[Date, Date]> {
  if (schedule.daysOff.includes(date)) return [];
  const key = WEEKDAY_KEYS[weekdayIndex(date)];
  return schedule.hours[key].map(([open, close]) => [
    instantFromClinicLocal(date, open, DEFAULT_TZ_OFFSET_MINUTES),
    instantFromClinicLocal(date, close, DEFAULT_TZ_OFFSET_MINUTES),
  ]);
}

/** Whether [start, start + minutes) lies inside one working range. */
export function fitsHours(
  schedule: DoctorSchedule,
  date: string,
  start: Date,
  minutes: number,
): boolean {
  const end = start.getTime() + minutes * 60_000;
  return rangesOn(schedule, date).some(
    ([open, close]) => start.getTime() >= open.getTime() && end <= close.getTime(),
  );
}

/**
 * Free start times on a date, clinic-local, in order: the slot grid of each
 * working range minus busy intervals and anything that has already started
 * (or starts within `leadMinutes`, so nobody is booked for a time they can't
 * reach).
 */
export function freeSlots(
  schedule: DoctorSchedule,
  date: string,
  busy: Array<{start: number; end: number}>,
  nowMillis: number,
  leadMinutes = 30,
): string[] {
  const out: string[] = [];
  for (const [open, close] of rangesOn(schedule, date)) {
    for (const slot of computeOpenSlots(
      open, close, schedule.slotMinutes, busy, nowMillis + leadMinutes * 60_000,
    )) {
      out.push(localTimeOf(new Date(slot.start)));
    }
  }
  return out;
}

/** At most `max` items, spread across the list rather than the first few. */
export function spread<T>(items: T[], max: number): T[] {
  if (items.length <= max) return items;
  const out: T[] = [];
  const step = (items.length - 1) / (max - 1);
  for (let i = 0; i < max; i++) out.push(items[Math.round(i * step)]);
  return out;
}

/** "5:30 pm" */
export function spokenTime(hhmm: string): string {
  const [h, m] = hhmm.split(":").map(Number);
  const h12 = h % 12 === 0 ? 12 : h % 12;
  return `${h12}:${String(m).padStart(2, "0")} ${h < 12 ? "am" : "pm"}`;
}

/** "Saturday 10 October" */
export function spokenDate(date: string): string {
  const [, m, d] = dateParts(date);
  return `${weekdayName(date)} ${d} ${MONTH_NAMES[m - 1]}`;
}

function rangeText(ranges: Array<[string, string]>): string {
  if (!ranges.length) return "closed";
  return ranges.map(([o, c]) => `${spokenTime(o)} to ${spokenTime(c)}`).join(" and ");
}

/**
 * "Mon to Sat 9:00 am to 6:00 pm. Sun closed." Consecutive days with the
 * same hours are grouped, so a normal week reads as one sentence.
 */
export function hoursText(schedule: DoctorSchedule): string {
  const order: WeekdayKey[] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"];
  const parts: string[] = [];
  let i = 0;
  while (i < order.length) {
    const text = rangeText(schedule.hours[order[i]]);
    let j = i;
    while (j + 1 < order.length && rangeText(schedule.hours[order[j + 1]]) === text) j++;
    const first = WEEKDAY_SHORT[WEEKDAY_KEYS.indexOf(order[i])];
    const last = WEEKDAY_SHORT[WEEKDAY_KEYS.indexOf(order[j])];
    parts.push(`${i === j ? first : `${first} to ${last}`} ${text}`);
    i = j + 1;
  }
  return parts.join(". ") + ".";
}

// ------------------------------------------------------------------ cost

/** Sarvam Business plan: ₹3.00 per started minute of agent time. */
export const AGENT_PAISE_PER_MINUTE = 300;
/** Line: ₹0.20 per started 30-second pulse. */
export const LINE_PAISE_PER_PULSE = 20;

export function callCost(seconds: number): {
  agentMinutes: number; pulses: number; costPaise: number;
} {
  const s = Number.isFinite(seconds) && seconds > 0 ? seconds : 0;
  const agentMinutes = Math.ceil(s / 60);
  const pulses = Math.ceil(s / 30);
  return {
    agentMinutes,
    pulses,
    costPaise: agentMinutes * AGENT_PAISE_PER_MINUTE + pulses * LINE_PAISE_PER_PULSE,
  };
}
