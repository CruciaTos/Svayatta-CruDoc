import * as admin from "firebase-admin";
import {
  busyIntervalsFrom, busyQuery, DEFAULT_TZ_OFFSET_MINUTES, instantFromClinicLocal,
  loadBusyIntervals, normaliseTime,
} from "../appointments";
import {
  CallContext, callerIndexFor, clinicKey, db, decryptField, DEFAULT_INCLUDED_CALLS,
  Doctor, doctorById, encryptField, phoneForBooking, phoneIndexOf, pickDoctor,
  readableKey, recordAction, str, VoiceError,
} from "./context";
import {
  addDays, daysBetween, freeSlots, hoursText, localDateOf, localTimeOf,
  MAX_DAYS_AHEAD, monthKeyOf, rangesOn, resolveDate, spokenDate, spokenTime,
  spread, weekdayName, fitsHours,
} from "./schedule";

/**
 * The `voiceApi` routes the Sarvam agent calls as tools. See
 * docs/ai_receptionist_final_plan.md §4.4 for the contract.
 *
 * Every reply carries ready-made sentences (`say`) in plain English; the
 * agent's instructions tell it to say them in the caller's language. The
 * model asks, these routes decide: hours, clashes, ownership and quota are
 * all checked here, never left to the prompt.
 */

type Reply = Record<string, unknown>;

const TIMESTAMP = admin.firestore.Timestamp;
const MAX_ALTERNATIVES = 3;
const MAX_OFFERED = 6;
const NEXT_FREE_SEARCH_DAYS = 14;

const SAY_PAUSED =
  "Sorry, the clinic's phone assistant is not available right now. " +
  "Please call again during clinic hours or send the clinic a WhatsApp message.";
const SAY_OVER_QUOTA =
  "Sorry, the clinic's phone assistant can't take more calls this month. " +
  "Please call again during clinic hours or send the clinic a WhatsApp message.";
const SAY_NOT_FOUND = "I couldn't find that appointment under your number.";

function dayBounds(date: string): {start: Date; end: Date} {
  const start = instantFromClinicLocal(date, "00:00", DEFAULT_TZ_OFFSET_MINUTES);
  const end = instantFromClinicLocal(addDays(date, 1), "00:00", DEFAULT_TZ_OFFSET_MINUTES);
  return {start, end};
}

async function slotsOn(ctx: CallContext, doctor: Doctor, date: string): Promise<string[]> {
  if (!rangesOn(doctor.schedule, date).length) return [];
  const {start, end} = dayBounds(date);
  const busy = await loadBusyIntervals(ctx.clinicId, doctor.id, start, end);
  return freeSlots(doctor.schedule, date, busy, ctx.now.getTime());
}

function requireDate(ctx: CallContext, raw: unknown): string {
  const date = resolveDate(raw, ctx.now);
  if (!date) {
    throw new VoiceError("invalid_date", "Which date would you like?");
  }
  const ahead = daysBetween(localDateOf(ctx.now), date);
  if (ahead < 0) {
    throw new VoiceError("in_past", "That date has already passed. Which day would you like?");
  }
  if (ahead > MAX_DAYS_AHEAD) {
    throw new VoiceError(
      "too_far",
      "I can only book up to two months ahead. Which day in the next two months suits you?",
    );
  }
  return date;
}

function requireTime(raw: string): string {
  const t = raw ? normaliseTime(raw) : "";
  if (!/^\d{2}:\d{2}$/.test(t)) {
    throw new VoiceError("invalid_time", "What time would you like?");
  }
  return t;
}

/** Why a time can't be booked, as a sentence, or null when it can. */
function hoursProblem(doctor: Doctor, date: string, start: Date, minutes: number): VoiceError | null {
  if (doctor.schedule.daysOff.includes(date)) {
    return new VoiceError("day_off", `${doctor.name} is away on ${spokenDate(date)}.`);
  }
  if (!rangesOn(doctor.schedule, date).length) {
    return new VoiceError("closed", `${doctor.name} doesn't see patients on ${weekdayName(date)}s.`);
  }
  if (!fitsHours(doctor.schedule, date, start, minutes)) {
    return new VoiceError(
      "outside_hours",
      `That time is outside ${doctor.name}'s hours. ${hoursText(doctor.schedule)}`,
    );
  }
  return null;
}

/** The free times closest to the one asked for, for a "that's taken" reply. */
async function nearestAlternatives(
  ctx: CallContext, doctor: Doctor, date: string, wanted: string,
): Promise<string[]> {
  const slots = await slotsOn(ctx, doctor, date);
  const minutes = (t: string) => Number(t.slice(0, 2)) * 60 + Number(t.slice(3));
  return slots
    .sort((a, b) => Math.abs(minutes(a) - minutes(wanted)) - Math.abs(minutes(b) - minutes(wanted)))
    .slice(0, MAX_ALTERNATIVES)
    .sort();
}

function lockId(doctorId: string, start: Date): string {
  return `${doctorId}_${start.getTime()}`;
}

interface PatientMatch {
  id: string;
  firstName: string;
  lastName: string;
}

async function patientsByIndex(
  ctx: CallContext, index: string, dek: Buffer | null,
): Promise<PatientMatch[]> {
  const snap = await db().collection("patients")
    .where("doctorId", "==", ctx.clinicId)
    .where("phoneIndex", "==", index)
    .limit(10)
    .get();
  return snap.docs
    .filter((d) => d.data().isDeleted !== true)
    .map((d) => ({
      id: d.id,
      firstName: decryptField(d.data().firstName, dek) || "",
      lastName: decryptField(d.data().lastName, dek) || "",
    }));
}

interface Upcoming {
  appointment_id: string;
  doctor: string;
  doctor_id: string;
  date: string;
  weekday: string;
  time: string;
  spoken: string;
}

async function upcomingFor(ctx: CallContext, patientIds: string[]): Promise<Upcoming[]> {
  if (!patientIds.length) return [];
  const snap = await db().collection("appointments")
    .where("doctorId", "==", ctx.clinicId)
    .where("patientId", "in", patientIds.slice(0, 10))
    .where("scheduledStart", ">=", TIMESTAMP.fromDate(ctx.now))
    .orderBy("scheduledStart")
    .limit(10)
    .get();

  const out: Upcoming[] = [];
  for (const doc of snap.docs) {
    const a = doc.data();
    if (a.isDeleted === true || (a.status || "scheduled") !== "scheduled") continue;
    const start = (a.scheduledStart as admin.firestore.Timestamp).toDate();
    const doctor = await doctorById(ctx, a.attendingDoctorUid || ctx.clinicId);
    const date = localDateOf(start);
    const time = localTimeOf(start);
    out.push({
      appointment_id: doc.id,
      doctor: doctor.name,
      doctor_id: doctor.id,
      date,
      weekday: weekdayName(date),
      time,
      spoken: `${spokenDate(date)} at ${spokenTime(time)} with ${doctor.name}`,
    });
    if (out.length === 5) break;
  }
  return out;
}

function upcomingText(list: Upcoming[]): string {
  if (!list.length) return "none";
  return list.map((u) => `${u.spoken} (appointment_id ${u.appointment_id})`).join("; ");
}

async function openCallback(ctx: CallContext, index: string | null) {
  if (!index) return null;
  const snap = await db().collection("voice_callbacks")
    .where("doctorId", "==", ctx.clinicId)
    .where("callerIndex", "==", index)
    .where("status", "==", "open")
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0];
}

// ================================================================= session

export async function session(ctx: CallContext): Promise<Reply> {
  const today = localDateOf(ctx.now);
  const base: Reply = {
    clinic_name: ctx.clinicName,
    today,
    weekday: weekdayName(today),
    now_local: localTimeOf(ctx.now),
    doctors: ctx.doctors.map((d) => ({id: d.id, name: d.name})),
    doctor_list: ctx.doctors.map((d) => `${d.name} (doctor_id ${d.id})`).join("; "),
    hours_text: ctx.doctors.length === 1 ?
      hoursText(ctx.doctors[0].schedule) :
      ctx.doctors.map((d) => `${d.name}: ${hoursText(d.schedule)}`).join(" "),
  };

  const callRef = db().collection("voice_calls").doc(ctx.callId);
  const logCall = async (mode: string, extra: Record<string, unknown> = {}) => {
    await callRef.set({
      doctorId: ctx.clinicId,
      lineId: ctx.line.id,
      interactionId: ctx.interactionId,
      mode,
      startedAt: admin.firestore.FieldValue.serverTimestamp(),
      ...extra,
    }, {merge: true});
  };

  const anyDoctorOn = ctx.doctors.some((d) => d.enabled);
  if (!ctx.moduleEnabled || ctx.line.status === "paused" || !anyDoctorOn) {
    await logCall("paused");
    return {...base, mode: "paused", say: SAY_PAUSED};
  }

  if (ctx.callerIsDoctor && ctx.line.status === "pending_test") {
    await db().collection("voice_lines").doc(ctx.line.id).update({
      status: "active",
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await logCall("verify");
    return {
      ...base,
      mode: "verify",
      say: `This is the CruDoc assistant for ${ctx.clinicName}. Your number is now verified. ` +
        "You can turn on call forwarding now. Goodbye.",
    };
  }

  const usage = await db().collection("voice_usage")
    .doc(`${ctx.clinicId}_${monthKeyOf(ctx.now)}`).get();
  const u = usage.data() || {};
  const allowed = (typeof u.includedCalls === "number" ? u.includedCalls :
    ctx.line.includedCalls ?? DEFAULT_INCLUDED_CALLS) +
    (typeof u.extraCalls === "number" ? u.extraCalls : 0);
  if ((u.calls || 0) >= allowed) {
    await logCall("over_quota");
    return {...base, mode: "over_quota", say: SAY_OVER_QUOTA};
  }

  // Who is calling.
  const dek = await readableKey(ctx);
  const index = ctx.callerPhone && dek ? phoneIndexOf(ctx.callerPhone, dek) : null;
  const patients = index ? await patientsByIndex(ctx, index, dek) : [];
  const firstNames = [...new Set(patients.map((p) => p.firstName.split(/\s+/)[0]).filter(Boolean))];
  // A family often shares one phone. Greet by name only when it's one person.
  const callerFirstName = firstNames.length === 1 ? firstNames[0] : "";
  const upcoming = await upcomingFor(ctx, patients.map((p) => p.id));
  const pending = await openCallback(ctx, index);

  const sealedCaller = ctx.callerPhone ?
    encryptField(ctx.callerPhone, await clinicKey(ctx)) :
    null;
  await logCall("patient", {
    callerPhone: sealedCaller,
    callerIndex: index,
  });

  const greetingName = callerFirstName ? ` ${callerFirstName} ji` : "";
  return {
    ...base,
    ok: true,
    mode: "patient",
    caller_known: patients.length > 0,
    caller_first_name: callerFirstName,
    family_names: firstNames.length > 1 ? firstNames.join(", ") : "",
    ask_phone: ctx.askPhone,
    upcoming,
    upcoming_text: upcomingText(upcoming),
    has_open_message: !!pending,
    say: `Namaste${greetingName}, ${ctx.clinicName}. How can I help you?`,
  };
}

// =================================================================== slots

export async function slots(ctx: CallContext): Promise<Reply> {
  const doctor = pickDoctor(ctx, str(ctx.body, "doctor_id"));
  const date = requireDate(ctx, ctx.body.date);
  const found = await slotsOn(ctx, doctor, date);
  const reply: Reply = {
    doctor: doctor.name,
    doctor_id: doctor.id,
    date,
    weekday: weekdayName(date),
    spoken_date: spokenDate(date),
  };

  if (found.length) {
    const offered = spread(found, MAX_OFFERED);
    return {
      ...reply,
      slots: offered,
      slots_text: offered.map(spokenTime).join(", "),
    };
  }

  // Nothing that day: find the next day that has something.
  let next: {date: string; slots: string[]} | null = null;
  for (let i = 1; i <= NEXT_FREE_SEARCH_DAYS && !next; i++) {
    const d = addDays(date, i);
    if (daysBetween(localDateOf(ctx.now), d) > MAX_DAYS_AHEAD) break;
    const s = await slotsOn(ctx, doctor, d);
    if (s.length) next = {date: d, slots: s};
  }

  const why = !rangesOn(doctor.schedule, date).length ?
    `${doctor.name} doesn't see patients on ${spokenDate(date)}.` :
    `${doctor.name} has no free time left on ${spokenDate(date)}.`;
  const offeredNext = next ? spread(next.slots, MAX_ALTERNATIVES) : [];
  return {
    ...reply,
    slots: [],
    slots_text: "",
    next_free_date: next?.date ?? "",
    next_free_spoken: next ? spokenDate(next.date) : "",
    next_free_slots: offeredNext,
    say_if_empty: next ?
      `${why} The next free day is ${spokenDate(next.date)}, for example at ` +
      `${offeredNext.map(spokenTime).join(", ")}.` :
      `${why} There is nothing free in the next two weeks. Shall I take a message for the clinic?`,
  };
}

// ==================================================================== book

export async function book(ctx: CallContext): Promise<Reply> {
  const doctor = pickDoctor(ctx, str(ctx.body, "doctor_id"));
  const patientName = str(ctx.body, "patient_name").replace(/\s+/g, " ");
  if (!patientName) {
    throw new VoiceError("name_required", "May I have the patient's name, please?");
  }
  const date = requireDate(ctx, ctx.body.date);
  const time = requireTime(str(ctx.body, "time"));
  const start = instantFromClinicLocal(date, time, DEFAULT_TZ_OFFSET_MINUTES);
  const minutes = doctor.schedule.slotMinutes;
  const end = new Date(start.getTime() + minutes * 60_000);

  if (start.getTime() < ctx.now.getTime() + 15 * 60_000) {
    throw new VoiceError("in_past", "That time is too soon or has passed. Which later time suits you?");
  }
  const problem = hoursProblem(doctor, date, start, minutes);
  if (problem) throw problem;

  const phone = phoneForBooking(ctx);
  const dek = await clinicKey(ctx);
  const index = phoneIndexOf(phone, dek);
  const reason = str(ctx.body, "reason").slice(0, 200);

  const appointmentId = `ai_${ctx.callId}_${start.getTime()}`.slice(0, 400);
  const appointmentRef = db().collection("appointments").doc(appointmentId);
  const lockRef = db().collection("slot_locks").doc(lockId(doctor.id, start));
  const [first, ...rest] = patientName.split(" ");

  let outcome: "booked" | "already_booked";
  try {
    outcome = await db().runTransaction(async (tx) => {
      const existing = await tx.get(appointmentRef);
      if (existing.exists && existing.data()?.status !== "cancelled") {
        // A retried request: the first one already booked it.
        return "already_booked" as const;
      }

      const lock = await tx.get(lockRef);
      const holderId = lock.exists ? lock.data()?.appointmentId : null;
      if (holderId && holderId !== appointmentId) {
        const holder = await tx.get(db().collection("appointments").doc(holderId));
        const h = holder.data();
        const stillThere = holder.exists && h?.isDeleted !== true &&
          (h?.status || "scheduled") === "scheduled" &&
          (h?.scheduledStart as admin.firestore.Timestamp)?.toMillis?.() === start.getTime();
        if (stillThere) throw new VoiceError("slot_taken", "");
      }

      const busy = await tx.get(busyQuery(ctx.clinicId, start, end));
      const clash = busyIntervalsFrom(busy.docs, ctx.clinicId, doctor.id)
        .find((b) => b.id !== appointmentId && b.start < end.getTime() && start.getTime() < b.end);
      if (clash) throw new VoiceError("slot_taken", "");

      // The same phone is often shared by a family: reuse a record only when
      // the first name matches, otherwise this is a new patient.
      const candidates = index ?
        await tx.get(db().collection("patients")
          .where("doctorId", "==", ctx.clinicId)
          .where("phoneIndex", "==", index)
          .limit(10)) :
        null;
      const match = candidates?.docs.find((d) =>
        d.data().isDeleted !== true &&
        (decryptField(d.data().firstName, dek) || "").trim().split(/\s+/)[0].toLowerCase() ===
          first.toLowerCase());

      const now = TIMESTAMP.now();
      let patientId: string;
      if (match) {
        patientId = match.id;
      } else {
        const patientRef = db().collection("patients").doc();
        patientId = patientRef.id;
        // Same shape as the app's Patient.toMap(), with the app's encryption.
        tx.set(patientRef, {
          doctorId: ctx.clinicId,
          firstName: encryptField(first, dek),
          lastName: encryptField(rest.join(" "), dek),
          phone: encryptField(phone.slice(2), dek),
          phoneIndex: index,
          email: "",
          gender: "",
          diagnosis: "[]",
          notes: "",
          packageBalance: 0,
          isArchived: false,
          source: "ai_receptionist",
          createdAt: now,
          updatedAt: now,
        });
      }

      tx.set(appointmentRef, {
        doctorId: ctx.clinicId,
        attendingDoctorUid: doctor.id,
        createdByUid: "",
        patientId,
        scheduledStart: TIMESTAMP.fromDate(start),
        durationMinutes: minutes,
        address: "",
        latitude: null,
        longitude: null,
        mapsLink: null,
        visitType: "clinic",
        status: "scheduled",
        isPaid: false,
        amountCharged: null,
        isDeleted: false,
        invoiceId: null,
        packageId: null,
        treatmentType: reason || null,
        therapistNotes: null,
        reminderStatus: null,
        calendarEventId: null,
        source: "ai_receptionist",
        voiceInteractionId: ctx.interactionId,
        createdAt: now,
        updatedAt: now,
      });
      tx.set(lockRef, {
        appointmentId,
        doctorId: doctor.id,
        start: TIMESTAMP.fromDate(start),
        createdAt: now,
      });
      return "booked" as const;
    });
  } catch (err) {
    if (err instanceof VoiceError && err.code === "slot_taken") {
      const alternatives = await nearestAlternatives(ctx, doctor, date, time);
      throw new VoiceError(
        "slot_taken",
        alternatives.length ?
          `Sorry, ${spokenTime(time)} was just taken. Free times near it are ` +
          `${alternatives.map(spokenTime).join(", ")}.` :
          `Sorry, ${spokenTime(time)} was just taken and nothing else is free that day.`,
        {alternatives},
      );
    }
    throw err;
  }

  if (outcome === "booked") {
    await recordAction(ctx, {type: "booked", appointmentId});
  }
  return {
    appointment_id: appointmentId,
    doctor: doctor.name,
    date,
    weekday: weekdayName(date),
    time,
    say: `Booked: ${doctor.name}, ${spokenDate(date)} at ${spokenTime(time)}.`,
  };
}

// ======================================================== my appointments

export async function myAppointments(ctx: CallContext): Promise<Reply> {
  const dek = await readableKey(ctx);
  const index = await callerIndexFor(ctx);
  if (!index) {
    if (ctx.askPhone) throw new VoiceError("phone_required", "Could you please tell me your 10-digit mobile number?");
    return {appointments: [], appointments_text: "none", say: "I don't see any upcoming appointments under your number."};
  }
  const patients = await patientsByIndex(ctx, index, dek);
  const list = await upcomingFor(ctx, patients.map((p) => p.id));
  return {
    appointments: list,
    appointments_text: upcomingText(list),
    say: list.length ?
      `You have ${list.length === 1 ? "one appointment" : `${list.length} appointments`}: ` +
      list.map((u) => u.spoken).join("; ") + "." :
      "I don't see any upcoming appointments under your number.",
  };
}

// ======================================================= cancel / reschedule

async function ownedAppointment(ctx: CallContext) {
  const id = str(ctx.body, "appointment_id");
  if (!id) throw new VoiceError("appointment_required", "Which appointment do you mean?");

  const ref = db().collection("appointments").doc(id);
  const snap = await ref.get();
  const a = snap.data();
  if (!snap.exists || !a || a.doctorId !== ctx.clinicId || a.isDeleted === true) {
    throw new VoiceError("not_found", SAY_NOT_FOUND);
  }

  const index = await callerIndexFor(ctx);
  if (!index) {
    throw new VoiceError("phone_required", "Could you please tell me your 10-digit mobile number?");
  }
  const patient = a.patientId ?
    await db().collection("patients").doc(String(a.patientId)).get() :
    null;
  if (!patient?.exists || patient.data()?.phoneIndex !== index) {
    // Same reply as a missing appointment: a caller learns nothing about
    // appointments that aren't theirs.
    throw new VoiceError("not_found", SAY_NOT_FOUND);
  }

  const start = (a.scheduledStart as admin.firestore.Timestamp).toDate();
  if ((a.status || "scheduled") === "scheduled" && start.getTime() < ctx.now.getTime()) {
    throw new VoiceError("in_past", "That appointment has already passed.");
  }
  const doctor = await doctorById(ctx, a.attendingDoctorUid || ctx.clinicId);
  return {ref, data: a, start, doctor};
}

export async function cancel(ctx: CallContext): Promise<Reply> {
  const {ref, data, start, doctor} = await ownedAppointment(ctx);
  const when = `${spokenDate(localDateOf(start))} at ${spokenTime(localTimeOf(start))}`;
  if (data.status === "cancelled") {
    return {appointment_id: ref.id, say: `Your appointment on ${when} is already cancelled.`};
  }

  const reason = str(ctx.body, "reason").slice(0, 200);
  const lockRef = db().collection("slot_locks").doc(lockId(doctor.id, start));
  await db().runTransaction(async (tx) => {
    const lock = await tx.get(lockRef);
    tx.update(ref, {
      status: "cancelled",
      isDeleted: true,
      therapistNotes: reason ?
        `Cancelled by AI receptionist: ${reason}` :
        (data.therapistNotes ?? "Cancelled by AI receptionist"),
      updatedAt: TIMESTAMP.now(),
    });
    if (lock.exists && lock.data()?.appointmentId === ref.id) tx.delete(lockRef);
  });

  await recordAction(ctx, {type: "cancelled", appointmentId: ref.id});
  return {
    appointment_id: ref.id,
    say: `Your appointment with ${doctor.name} on ${when} is cancelled.`,
  };
}

export async function reschedule(ctx: CallContext): Promise<Reply> {
  const {ref, data, start: oldStart, doctor} = await ownedAppointment(ctx);
  if (data.status !== "scheduled" && data.status !== undefined) {
    throw new VoiceError("not_movable", "That appointment can't be moved. Shall I book a new one?");
  }
  const date = requireDate(ctx, ctx.body.date);
  const time = requireTime(str(ctx.body, "time"));
  const start = instantFromClinicLocal(date, time, DEFAULT_TZ_OFFSET_MINUTES);
  const minutes = typeof data.durationMinutes === "number" && data.durationMinutes > 0 ?
    data.durationMinutes : doctor.schedule.slotMinutes;
  const end = new Date(start.getTime() + minutes * 60_000);

  if (start.getTime() === oldStart.getTime()) {
    return {appointment_id: ref.id, say: "Your appointment is already at that time."};
  }
  if (start.getTime() < ctx.now.getTime() + 15 * 60_000) {
    throw new VoiceError("in_past", "That time is too soon or has passed. Which later time suits you?");
  }
  const problem = hoursProblem(doctor, date, start, minutes);
  if (problem) throw problem;

  const oldLockRef = db().collection("slot_locks").doc(lockId(doctor.id, oldStart));
  const newLockRef = db().collection("slot_locks").doc(lockId(doctor.id, start));
  try {
    await db().runTransaction(async (tx) => {
      const [oldLock, newLock, busy] = await Promise.all([
        tx.get(oldLockRef),
        tx.get(newLockRef),
        tx.get(busyQuery(ctx.clinicId, start, end)),
      ]);
      const holderId = newLock.exists ? newLock.data()?.appointmentId : null;
      if (holderId && holderId !== ref.id) {
        const holder = await tx.get(db().collection("appointments").doc(holderId));
        const h = holder.data();
        if (holder.exists && h?.isDeleted !== true && (h?.status || "scheduled") === "scheduled" &&
          (h?.scheduledStart as admin.firestore.Timestamp)?.toMillis?.() === start.getTime()) {
          throw new VoiceError("slot_taken", "");
        }
      }
      const clash = busyIntervalsFrom(busy.docs, ctx.clinicId, doctor.id)
        .find((b) => b.id !== ref.id && b.start < end.getTime() && start.getTime() < b.end);
      if (clash) throw new VoiceError("slot_taken", "");

      tx.update(ref, {
        scheduledStart: TIMESTAMP.fromDate(start),
        updatedAt: TIMESTAMP.now(),
        rescheduledBy: "ai_receptionist",
      });
      if (oldLock.exists && oldLock.data()?.appointmentId === ref.id) tx.delete(oldLockRef);
      tx.set(newLockRef, {
        appointmentId: ref.id,
        doctorId: doctor.id,
        start: TIMESTAMP.fromDate(start),
        createdAt: TIMESTAMP.now(),
      });
    });
  } catch (err) {
    if (err instanceof VoiceError && err.code === "slot_taken") {
      const alternatives = await nearestAlternatives(ctx, doctor, date, time);
      throw new VoiceError(
        "slot_taken",
        alternatives.length ?
          `Sorry, ${spokenTime(time)} is taken. Free times near it are ${alternatives.map(spokenTime).join(", ")}.` :
          `Sorry, ${spokenTime(time)} is taken and nothing else is free that day.`,
        {alternatives},
      );
    }
    throw err;
  }

  await recordAction(ctx, {type: "rescheduled", appointmentId: ref.id});
  return {
    appointment_id: ref.id,
    doctor: doctor.name,
    date,
    weekday: weekdayName(date),
    time,
    say: `Done. Your appointment with ${doctor.name} is now on ${spokenDate(date)} at ${spokenTime(time)}.`,
  };
}

// ================================================================ callback

export async function callback(ctx: CallContext): Promise<Reply> {
  const name = str(ctx.body, "name").slice(0, 100);
  const note = (str(ctx.body, "note") || "Wants a call back").slice(0, 500);
  const phone = phoneForBooking(ctx);
  const dek = await clinicKey(ctx);
  const index = phoneIndexOf(phone, dek);
  const doctor = ctx.doctors[0];
  const say = `I've passed your message to ${doctor?.name || "the doctor"}. ` +
    "The clinic will call you back during clinic hours.";

  const existing = await openCallback(ctx, index);
  if (existing) {
    const before = decryptField(existing.data().note, dek) || "";
    await existing.ref.update({
      note: encryptField(`${before}\n${note}`.trim().slice(-2000), dek),
      messageCount: admin.firestore.FieldValue.increment(1),
      lastInteractionId: ctx.interactionId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    await recordAction(ctx, {type: "callback", callbackId: existing.id, merged: true});
    return {callback_id: existing.id, merged: true, say};
  }

  const ref = await db().collection("voice_callbacks").add({
    doctorId: ctx.clinicId,
    attendingDoctorUid: doctor?.id ?? ctx.clinicId,
    lineId: ctx.line.id,
    name: encryptField(name, dek),
    note: encryptField(note, dek),
    callerPhone: encryptField(phone.slice(2), dek),
    callerIndex: index,
    status: "open",
    messageCount: 1,
    interactionId: ctx.interactionId,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  await recordAction(ctx, {type: "callback", callbackId: ref.id});
  return {callback_id: ref.id, merged: false, say};
}
