# AI Receptionist + WhatsApp Reminders — Implementation Plan

| | |
|---|---|
| **Date** | 9 October 2026 |
| **Status** | Draft for approval |
| **Target** | Pilot on one phone by 17 Oct · 5-doctor beta from 22 Oct · 40 doctors live by 31 Oct 2026 |
| **Vendors** | Sarvam (AI voice agent + numbers, Business plan) · Meta WhatsApp Cloud API (direct, no reseller) |
| **Related docs** | `docs/whatsapp_shared_number.md` (reminder design, 5 Oct) · `docs/whatsapp-meta-status.md` (per-clinic WhatsApp, later) |

---

## 0. Summary in plain words

### What we are building

1. **AI receptionist.** When a patient calls the doctor's normal number and the doctor does not pick up, the call is forwarded to an AI. The AI books, moves or cancels the appointment in CruDoc, then says goodbye.
2. **WhatsApp reminders.** The evening before an appointment, the patient automatically gets a WhatsApp reminder. Nobody at the clinic presses a button.

### What the patient experiences

- They only ever need **one number: the doctor's own number**, which they already have saved.
- If the doctor answers, it's a normal call. If not (busy, no answer, phone off), the AI answers: *"Namaste, Sharma Dental Clinic. I'm Dr. Sharma's assistant. How can I help?"*
- The evening before the visit, they get a WhatsApp reminder that says *"to reschedule, call the clinic on 98220 11111"*. That's the doctor's number again, so a missed call there also reaches the AI.

### Decisions already made

| Topic | Decision |
|---|---|
| AI voice vendor | **Sarvam**, Business plan: AI ₹3.00/min, line ₹0.20 per 30 s |
| AI phone numbers | **3 numbers rented from Sarvam**, shared by all clinics (₹59 the first month, then ₹159 each) |
| How calls reach the AI | **Conditional call forwarding** on the doctor's phone (busy / no answer / unreachable) to one of the 3 AI numbers |
| Which clinic a call belongs to | Sarvam passes the **number that forwarded the call**; CruDoc looks it up in a "phone book" |
| Call direction | **Incoming only.** The AI never phones patients. |
| WhatsApp sender at launch | **One shared CruDoc WhatsApp number** (already built, see §3.5). The clinic's own number is phase 2. |
| Reminder timing | 18:00 the evening before, plus a new 08:00 catch-up for late bookings |
| Cost ceiling | ≤ ₹8 per call-minute including everything. Actual: **₹3.40 (₹4.01 with GST)** |
| Pricing to clinics | 20 AI calls a month included; extra calls ₹10 each (to confirm, Q6) |
| Feature switch | Existing module `ai_agentic_calling` (AI receptionist) and `omnichannel_messaging` (reminders) |

> **Correction to the earlier chat.** I said reminders would come from each clinic's own WhatsApp number through "coexistence". The code built on 5 Oct actually sends from **one shared CruDoc number**, which avoids weeks of Meta approvals. This plan keeps the shared number for launch. Moving each clinic to its own number is phase 2 (§11).

### What must happen before launch (critical path)

1. **Fix the reminder bug in §2.1 before WhatsApp goes live.** As written, the reminders would message random foreign numbers.
2. **Meta Business Verification** (you). Until it's verified, Meta allows about 250 reminders a day across all clinics, but 40 doctors will need about 400–600. After verification the limit is 2,000 a day (about 130 clinics), and it rises automatically to 10,000 once you regularly use half of it. Verification is also step 1 of coexistence (§11).
3. **Sarvam simultaneous-call limit** (you). It applies to the whole account, and 3 numbers don't raise it. Get it confirmed or raised before 40 doctors go live.

---

## 1. How it works

### 1.1 Phone call flow

```
Patient dials doctor's number (98220 11111)
        │
        ▼
Doctor's phone rings ── answered ──▶ normal call, AI not involved
        │
        │ busy / no answer in ~20 s / switched off
        ▼
Mobile operator forwards the call to AI number A (080-xxxx-0001)
        │            Sarvam knows: caller = 98901 55555
        │                          forwarded from = 98220 11111
        ▼
Sarvam AI agent ──── HTTPS tool calls (X-Api-Key) ────▶ CruDoc voiceApi (Cloud Functions, asia-south1)
   speaks with the                                        │  1. phone book: 98220 11111 → Dr. Sharma's clinic
   patient                                                │  2. reads/writes Firestore appointments
                                                          ▼
                                              Appointment appears live in the CruDoc app
        │
        ▼ call ends
Sarvam "call ended" webhook ──▶ voiceApi /call-ended ──▶ usage + cost recorded per clinic
```

### 1.2 WhatsApp reminder flow (already built, needs the §2 fixes)

```
18:00 IST daily ─▶ sendDayBeforeWhatsAppReminders
                     ├─ tomorrow's scheduled appointments
                     ├─ skip: module off / switched off / opted out / bad phone
                     └─ template appointment_reminder_v1 ─▶ Meta ─▶ patient
08:00 IST daily ─▶ NEW catch-up: today's appointments booked after last night's sweep

whatsappWebhook ◀─ delivered / read / STOP / START / other replies
```

### 1.3 Example call (Dr. Sharma and Ramesh)

| Time | What happens |
|---|---|
| 13:40 | Ramesh calls 98220 11111. Dr. Sharma is with a patient, so after 20 s the call forwards to AI number A. |
| 13:40 | AI → `POST /voiceApi/session` with the forwarding number and caller → CruDoc returns the clinic name, today's date and doctor list, and says Ramesh is a known patient. |
| 13:40 | AI: *"Namaste Ramesh ji, Sharma Dental Clinic. How can I help?"* Ramesh: *"Tomorrow evening, tooth pain."* |
| 13:41 | AI → `/slots` for 2026-10-10 → returns `17:00, 17:30, 18:30`. AI offers them; Ramesh picks 17:30. |
| 13:41 | AI repeats it back: *"Dr. Sharma, Saturday 10 October, 5:30 pm. Shall I book?"* "Yes." → `/book` → booked. |
| 13:41 | Call ends (70 s). Cost: 2 AI minutes × ₹3 + 3 half-minutes × ₹0.20 = **₹6.60** (₹7.79 with GST). |
| 13:45 | Dr. Sharma sees *"Sat 10 Oct · 5:30 pm · Ramesh Patil · AI"* in CruDoc. |
| 18:00 | Ramesh gets the WhatsApp reminder for tomorrow 5:30 pm. |

### 1.4 What exists today vs what we build

| Part | Status | Where |
|---|---|---|
| Check free slots, book, cancel (for a voice bot) | ✅ built, needs changes | `functions/src/appointments.ts` |
| Double-booking check against in-app bookings | ✅ built | `appointments.ts` `findConflictingAppointment` |
| API-key protection, time-zone-safe times | ✅ built | `appointments.ts` `authorizeVoiceBot`, `instantFromClinicLocal` |
| 18:00 WhatsApp reminder, STOP/START, auto-reply | ✅ built, **has P0 bug** | `functions/src/whatsapp/*`, `whatsapp-endpoints.ts` |
| Reminder on/off switch in app | ✅ built | `lib/features/messaging/data/providers/reminder_settings_providers.dart` |
| Phone book (forwarding number → clinic/doctor) | ❌ build | new |
| One `voiceApi` for Sarvam (session, slots, book, find, cancel, reschedule, callback, call-ended) | ❌ build | new `functions/src/voice/*` |
| Server-side decryption of patient fields | ❌ build | new `functions/src/crypto/patientCipher.ts` |
| Patient lookup by phone (`phoneIndex`) | ❌ build | new trigger + backfill |
| Usage, quota and cost tracking | ❌ build | new |
| Working hours per doctor | ❌ build (no such setting exists yet) | new, in app settings |
| AI Receptionist settings screen + forwarding guide | ❌ build | new `lib/features/ai_receptionist/` |
| 08:00 catch-up reminder | ❌ build | `whatsapp/reminders.ts` |

---

## 2. Fix first (P0): bugs found while writing this plan

These are in code that is already committed. The first is serious and must be fixed before WhatsApp goes live.

### 2.1 Reminders read encrypted patient data, so ~26% would go to random foreign numbers

- The app encrypts patient `firstName`, `lastName` and `phone` before saving them to Firestore (`lib/features/patients/data/repo/patient_repository.dart:44`, format `enc:v1:<iv>.<ciphertext>`).
- The reminder sweep reads them **without decrypting** (`functions/src/whatsapp/reminders.ts:253` and `:256`).
- `normalisePhone` strips the non-digits out of the ciphertext. I simulated 100,000 encrypted phone numbers:
  - **26.3%** become a "valid" 11–15-digit international number starting with 1 (the "1" comes from `v1`).
  - The other ~74% are rejected, so those patients silently get no reminder.
- **Effect if it went live:** about a quarter of reminders would go to random overseas numbers, showing the clinic name, doctor name, appointment date and time, and the ciphertext as the "name". The rest would be skipped.

**Fix:**
1. New `functions/src/crypto/patientCipher.ts` that mirrors `lib/core/services/encryption_key_manager.dart` and `field_cipher.dart`:
   - KEK = SHA-256 of `"{clinicId}::{pepper}"`.
   - DEK = AES-GCM unwrap of `doctor_keys/{clinicId}.wrappedKey`.
   - Fields are AES-256-GCM `enc:v1:` values, decrypted with the DEK.
   - The pepper becomes a Firebase secret `PATIENT_KEK_PEPPER`, set to the same value as the app constant. Don't paste it into the functions source.
2. The reminder sweep decrypts the patient's name and phone with `doctor_keys/{patient.doctorId}` before using them.
3. `normalisePhone` rejects any value containing `enc:` and accepts **Indian mobiles only** (`91` + 10 digits starting 6–9), since we're India-only.
4. A unit test with a known value encrypted by the Dart code, so the two implementations can't drift apart.

### 2.2 AI-created patients have no name in the app

- `findOrCreatePatient` writes `fullName` (`appointments.ts:810`), but the app's `Patient.fromMap` reads `firstName` / `lastName` (`lib/features/patients/data/models/patient.dart:88`).
- Every AI-created patient therefore shows with a blank name.
- These records also hold the name and phone in **plaintext**, unlike every other patient.

**Fix:** write `firstName` / `lastName` / `phone` encrypted with the clinic DEK (using `patientCipher.ts`) and add `phoneIndex` (§2.3).

### 2.3 The AI cannot recognise existing patients

- `findOrCreatePatient` only searches records with `source == "ai_receptionist"` and a plaintext phone (`appointments.ts:789`).
- A long-time patient who calls gets a **duplicate** patient record.

**Fix:**
- Add `phoneIndex` = HMAC-SHA256(DEK, E.164 phone), hex, to every patient.
- A Firestore trigger `onPatientWrittenIndexPhone` computes it on the server whenever a patient is created or their phone changes. It only writes if the value changed, so it can't loop.
- A one-time backfill script fills it in for existing patients.
- **No app release is needed:** the server derives the DEK itself.
- `voiceApi` looks up `patients where doctorId == clinicId and phoneIndex == X`. That needs a composite index `(doctorId, phoneIndex)`.

### 2.4 Cancel accepts any appointment ID

- `cancelAppointment` (`appointments.ts:628`) cancels whatever appointment ID it's given. There's no check that the appointment belongs to the calling clinic or patient.

**Fix:** the new `/cancel` and `/reschedule` only act when both are true:
- the appointment's clinic matches the forwarding line's clinic, and
- the appointment's patient `phoneIndex` matches the caller.

Once Sarvam is live, remove the three legacy endpoints (task V12).

---

## 3. Design

### 3.1 Components

| Component | Role | Notes |
|---|---|---|
| Doctor's mobile | Forwards unanswered calls | Settings on the phone; nothing installed |
| Sarvam AI numbers A, B, C | Receive forwarded calls | Rented in Sarvam, all attached to the **same** agent |
| Sarvam agent | Talks, calls CruDoc tools | Configured in Sarvam's dashboard (Appendix A, B) |
| `voiceApi` (new) | One HTTPS function with routes | `asia-south1`, `X-Api-Key`, one warm service rather than three cold ones |
| Firestore | Phone book, usage, appointments, patients | New collections in §3.2 |
| CruDoc app | Settings, forwarding guide, usage, AI chip, callbacks | New `lib/features/ai_receptionist/` |
| Reminder sweep + webhook | WhatsApp | Exists; fixed in §2.1, extended in §3.5 |

**Why one `voiceApi` function instead of separate ones?**
- Each Cloud Function is its own server that "sleeps" when idle, and waking it adds 1–3 seconds. That silence is noticeable mid-call.
- One function means only one server to keep warm. If the pilot shows delays, set `minInstances: 1` (roughly a few hundred rupees a month; measure first).

### 3.2 Data model (new)

**`voice_numbers/{aiNumberE164}`**: the pool of 3 AI numbers. Super admin edits it.
```json
{ "number": "918045670001", "label": "A", "active": true,
  "lineCount": 14, "sarvamAgentId": "agt_...", "createdAt": "<ts>" }
```

**`voice_lines/{forwardingNumberE164}`**: the phone book. The document ID is the doctor's phone, so one phone can belong to only one clinic.
```json
{ "clinicId": "aB3xK9", "doctorIds": ["aB3xK9"], "aiNumber": "918045670001",
  "status": "pending_test",            // pending_test | active | paused
  "verifiedAt": null, "lastCallAt": null,
  "createdBy": "aB3xK9", "createdAt": "<ts>", "updatedAt": "<ts>" }
```

**`users/{uid}.aiReceptionist`**: per-doctor settings, written by the app.
```json
{ "enabled": true,
  "hours": { "mon": [["10:00","13:00"],["17:00","21:00"]], "tue": [...], "sun": [] },
  "slotMinutes": 30,
  "daysOff": ["2026-10-20"],
  "announceAs": "Dr. Sharma" }
```

**`voice_calls/{interactionId}`**: one document per call, written only by the server.
```json
{ "clinicId": "aB3xK9", "doctorId": "aB3xK9", "line": "919822011111",
  "aiNumber": "918045670001", "callerPhone": "enc:v1:...", "callerIndex": "<hmac>",
  "startedAt": "<ts>", "durationSec": 70, "agentMinutes": 2, "pulses": 3,
  "costPaise": 660, "outcome": "booked",   // booked|rescheduled|cancelled|info|callback|over_quota|unknown_line|failed
  "appointmentId": "Xy12Ab" }
```

**`voice_usage/{clinicId}_{YYYYMM}`**: the monthly counter (IST month), used for quota and billing.
```json
{ "calls": 37, "seconds": 2610, "agentMinutes": 51, "pulses": 96,
  "costPaise": 17220, "includedCalls": 20, "extraCalls": 100, "overQuotaCalls": 0 }
```

**`voice_callbacks/{id}`**: "please ask the doctor to call me back".
```json
{ "clinicId": "aB3xK9", "doctorId": "aB3xK9", "callerPhone": "enc:v1:...",
  "name": "Ramesh", "note": "wants to ask about bill", "status": "open", "createdAt": "<ts>" }
```

**`slot_locks/{doctorId}_{startUtcIso}`**: stops two simultaneous AI calls booking the same slot.
```json
{ "appointmentId": "Xy12Ab", "createdAt": "<ts>" }
```

**Firestore rules:**
- All `voice_*` collections and `slot_locks` are **written by functions only**.
- Clinic members with the AI permission can read their clinic's `voice_calls`, `voice_usage`, `voice_callbacks` and `voice_lines`, and can update `status` on `voice_callbacks`.
- `voice_numbers` is readable by any signed-in user, so the app can show the number to forward to.

### 3.3 `voiceApi` contract (what Sarvam calls)

**Every request:**
- Method `POST`, JSON body.
- Header `X-Api-Key: <VOICE_BOT_API_KEY>` (the existing secret).
- Body always includes `forwarded_from`, `caller` and `interaction_id`, filled from Sarvam's call variables (exact names to confirm, Q1).

**Every response:**
- Success: `{ "ok": true, ... }`
- Failure: `{ "ok": false, "code": "...", "say": "..." }`

`say` is a ready-made sentence the agent can speak, which keeps the AI from improvising around errors.

**All times are clinic-local** (`"17:30"`, `"2026-10-10"`), never UTC. If the model has to convert UTC to IST in the middle of a call, it will eventually get it wrong.

#### `POST /session`: first call, every time
Request:
```json
{ "forwarded_from": "9822011111", "caller": "9890155555", "interaction_id": "int_123" }
```
Response (normal case):
```json
{ "ok": true, "mode": "patient",
  "clinic_name": "Sharma Dental Clinic",
  "doctors": [ { "id": "aB3xK9", "name": "Dr. Sharma" } ],
  "today": "2026-10-09", "weekday": "Friday", "now_local": "13:40",
  "hours_text": "Mon–Sat 10 am–1 pm and 5–9 pm. Closed Sunday.",
  "caller_known": true, "caller_first_name": "Ramesh",
  "upcoming": [ { "appointment_id": "Xy12Ab", "doctor": "Dr. Sharma",
                  "date": "2026-10-10", "time": "17:30" } ],
  "say": "Namaste, Sharma Dental Clinic. I'm Dr. Sharma's assistant. How can I help?" }
```
`mode` tells the agent which script to follow:

| mode | When | Agent does |
|---|---|---|
| `patient` | Line active, under quota | Normal conversation |
| `verify` | No `forwarded_from`, and the caller is a `pending_test` line | Says *"Your number is verified for Sharma Dental Clinic"*, then ends the call. The server marks the line `active`. |
| `over_quota` | The clinic's monthly calls are used up | Says the `say` text (*"…please send a WhatsApp or call again during clinic hours"*), then ends the call |
| `paused` | Line paused, or module switched off | Says `say`, then ends the call |
| `unknown_line` | Forwarding number not in the phone book, or someone dialled the AI number directly | *"Please call your doctor's own number"*, then ends the call |

The agent needs today's date and weekday from `/session`: without them it can't work out what "tomorrow" means.

#### `POST /slots`
Request adds `{ "doctor_id": "aB3xK9", "date": "2026-10-10" }`. `doctor_id` can be left out when the line has one doctor.
```json
{ "ok": true, "date": "2026-10-10", "weekday": "Saturday",
  "slots": ["17:00", "17:30", "18:30"],
  "say_if_empty": "Dr. Sharma has no free time that day. The next free day is Monday." }
```
Rules:
- Use the doctor's `aiReceptionist.hours` for that weekday (falling back to 09:00–18:00 if no hours are set yet), minus `daysOff`, minus busy appointments (`loadBusyIntervals`), minus past times.
- Return at most 6 slots, spread across the day.
- If the day is empty, also give the next day that has free slots.

#### `POST /book`
Request adds:
```json
{ "doctor_id": "aB3xK9", "patient_name": "Ramesh Patil",
  "date": "2026-10-10", "time": "17:30", "reason": "tooth pain" }
```
The server, inside one Firestore transaction:
1. Resolves the line, checks the doctor is on the line, and checks the time is within hours and in the future.
2. Runs the overlap check with `findConflictingAppointment`.
3. Creates `slot_locks/{doctorId}_{startUtcIso}`. If the lock exists and points to an appointment that is still scheduled, it returns `slot_taken`. If that appointment was cancelled or moved, the stale lock is overwritten.
4. Finds the patient by `phoneIndex`, or creates one with encrypted fields (§2.2).
5. Creates the appointment with the same field shape as today, plus `source: "ai_receptionist"`, `voiceInteractionId`, and `treatmentType: reason`.

**Idempotent:** the appointment ID is `ai_<interactionId>_<startMillis>`. If Sarvam retries a request, the second attempt returns the first booking instead of creating another.

Response:
```json
{ "ok": true, "appointment_id": "ai_int_123_1760097600000",
  "doctor": "Dr. Sharma", "date": "2026-10-10", "weekday": "Saturday", "time": "17:30",
  "say": "Booked: Dr. Sharma, Saturday 10 October at 5:30 pm." }
```
Errors (`code`): `slot_taken`, `outside_hours`, `in_past`, `doctor_not_on_line`, `day_off`, `invalid_date`.

#### `POST /my-appointments`
Returns the caller's upcoming appointments at this clinic. It matches the caller's `phoneIndex` and returns at most 5.

#### `POST /cancel`
Request adds `{ "appointment_id": "...", "reason": "..." }`. It works only if the appointment belongs to the caller at this clinic (§2.4). It's a soft cancel, as today, and it releases the slot lock.

#### `POST /reschedule`
Request adds `{ "appointment_id": "...", "date": "...", "time": "..." }`. It's one transaction: the ownership check, the conflict check for the new time (ignoring the appointment itself), moving the lock, and updating `scheduledStart`. **Reminder:** the claim must be keyed by appointment + date, so a moved appointment gets a fresh reminder. Check `claimReminder` in `whatsapp/logs.ts`.

#### `POST /callback`
Request adds `{ "name": "...", "note": "..." }` and creates `voice_callbacks`. The agent offers this instead of transferring the call. **Never transfer to the doctor's phone:** if the doctor doesn't answer, the call forwards straight back to the AI and loops.

#### `POST /call-ended`: Sarvam's post-call webhook
- Sarvam sends `interaction_id`, the caller, the AI number, the forwarding number (to confirm, Q1) and the duration.
- The server calculates:
  - `agentMinutes = ceil(sec / 60)`
  - `pulses = ceil(sec / 30)`
  - `costPaise = agentMinutes × 300 + pulses × 20`
- It writes `voice_calls/{interactionId}` and increments `voice_usage`, both in one transaction keyed on `interaction_id`, so a redelivered webhook can't count a call twice.
- Authentication: a shared secret (header or URL token, depending on what Sarvam supports, Q2).

### 3.4 Quota and cost guards

| Guard | How |
|---|---|
| Monthly call quota | `/session` checks `voice_usage.calls ≥ includedCalls + extraCalls` and returns `over_quota`, so the call ends in under a minute (≈ ₹4) |
| Warn the clinic | App banner at 80% and 100% of quota; super admin sees all clinics |
| Longest call | Set Sarvam's maximum call duration to **4 minutes**. Worst case is 4 × ₹3 + 8 × ₹0.20 = ₹13.60 (₹16 with GST) |
| Runaway spend | GCP budget alert. Compare against the monthly Sarvam invoice (`voice_usage.costPaise` total vs bill) |

### 3.5 WhatsApp reminder changes

1. **Fixes in §2.1** (decrypt; Indian mobiles only).
2. **08:00 catch-up sweep.** Same code path as the 18:00 sweep, but for **today's** appointments that start at 10:00 or later and have no reminder log yet. It catches anything booked after 18:00 the night before.
   - Still at most one message per appointment, thanks to the existing per-appointment claim.
   - No messages at night (quiet hours).
3. **No change to the template.** `{{6}}` is the clinic phone. Guide clinics to forward that same number to the AI, and the reminder then leads patients to the AI too.
4. **Same-number check.** If the clinic phone on the profile is not the forwarding line, the AI settings screen warns: *"Your reminders tell patients to call 98xxxx. Forward that number, or change the clinic phone."*

### 3.6 App changes (Flutter)

New feature folder `lib/features/ai_receptionist/`, gated on the module `ai_agentic_calling` and the clinic permission `ai` (`lib/core/clinic/clinic_access.dart:68`).

**Settings → AI Receptionist** (a section next to the existing WhatsApp reminder switch):
1. **On/off switch**, plus status: *Not set up · Waiting for test call · Active · Paused · Over quota*.
2. **"Number patients call"**: defaults to the clinic phone, editable.
   - Saving calls a new callable, `voiceLineRegister`.
   - It checks permissions, makes sure the number isn't owned by another clinic, assigns the least-busy AI number, and creates the line as `pending_test`.
3. **Doctors on this number** (multi-doctor clinics): pick from the clinic's members.
4. **Working hours:** a weekly editor (two ranges per day), slot length, and days off.
5. **Set-up steps**, shown one at a time:
   - **a.** *"From 98220 11111, call 080-4567-0001 once."* That test call verifies the number.
   - **b.** *"Turn on call forwarding."* Android gets a button that opens the dialler with the code pre-filled (`tel:` with `#` as `%23`); the doctor just presses call. iPhone gets written steps. See Appendix C.
   - **c.** *"Test it: call your number from another phone and don't answer."*
6. **This month:** calls used out of the quota, with a link to the call list.
7. **Pause** (keeps settings and stops answering) and **Remove**.

**Elsewhere:**
- **Appointments:** a small "AI" chip when `source == "ai_receptionist"`.
- **Callbacks:** a list with a count badge on the dashboard, "Call back" (opens the dialler) and "Done". There's no push notification yet, because `firebase_messaging` isn't in the app.
- **Hours:** stored in `users/{uid}.aiReceptionist`, which the doctor's own-profile rule already allows.

### 3.7 Super admin

**v1** (no UI):
- Add the 3 numbers to `voice_numbers` in the Firestore console.
- Set `includedCalls` and `extraCalls` per clinic on `voice_usage`.

**Phase 2** (`CrudocSuper-admin`):
- Number pool page: lines per number, with "move all lines from A to B".
- Usage per clinic, cost this month, and reconciliation against the Sarvam invoice.
- Top-ups.

---

## 4. Tasks

Owner: **You** = Soham, **C** = Claude (coding).
Size: S ≤ ½ day, M ≈ 1 day, L ≈ 2–3 days.
UI tasks A1–A5 can be handed to Antigravity as small prompts if useful.

### Phase 0: accounts and setup (start today, long lead times)

| ID | Task | Owner | Size | Done when |
|---|---|---|---|---|
| S1 | Start **Meta Business Verification** for the shared CruDoc WhatsApp number | You | S + wait (days) | Status "Verified" |
| S2 | Complete the Meta one-time setup in `docs/whatsapp_shared_number.md` §3 (WABA, number, display name, system-user token, template `appointment_reminder_v1`, webhook) | You | M + wait | Template "Approved", webhook green |
| S3 | Sarvam: finish KYC, rent **3 numbers** | You | S | 3 numbers visible in Sarvam |
| S4 | Sarvam: ask Q1–Q3 (forwarding-number variable, concurrency limit, webhook auth, custom headers on tools) | You | S | Written answers |
| S5 | Set Firebase secrets: `PATIENT_KEK_PEPPER` (same value as the app) and `SARVAM_WEBHOOK_SECRET` | You | S | `firebase functions:secrets:set` done |
| S6 | Decide pricing (Q6) and which clinics get reminders (Q7) | You | S | Answers in §8 |

### Phase 1: P0 fixes (blocks WhatsApp going live)

| ID | Task | Owner | Size | Depends on | Done when |
|---|---|---|---|---|---|
| V1 | `functions/src/crypto/patientCipher.ts`: unwrap the DEK, decrypt/encrypt `enc:v1`, `phoneIndex` HMAC. Unit test against a Dart-made value | C | M | S5 | Test decrypts the Dart sample |
| V2 | Reminders: decrypt name and phone; `normalisePhone` rejects `enc:` and accepts Indian mobiles only | C | S | V1 | Dry-run sweep shows real names, zero foreign numbers |
| V3 | Trigger `onPatientWrittenIndexPhone` + one-time backfill script + index `(doctorId, phoneIndex)` | C | M | V1 | Every patient has `phoneIndex` |
| V4 | 08:00 catch-up sweep (§3.5); reminder claim keyed by appointment + date | C | S | V2 | Booking at 20:00 for tomorrow 17:30 gets the 08:00 reminder |

### Phase 2: voice backend

| ID | Task | Owner | Size | Depends on | Done when |
|---|---|---|---|---|---|
| V5 | `functions/src/voice/` skeleton: one `voiceApi` with a router, API-key auth, line resolution, IST helpers (reusing `instantFromClinicLocal`, `computeOpenSlots`, `loadBusyIntervals`) | C | M | – | `/session` answers for a test line |
| V6 | `/session` with all modes, quota check, caller recognition | C | M | V3, V5 | All 5 modes return correctly |
| V7 | `/slots` with working hours, days off, next free day, local times | C | M | V5 | Matches what the app shows as free |
| V8 | `/book` (transaction, slot lock, idempotent ID, encrypted patient) | C | M | V1, V5 | Two simultaneous bookings: exactly one wins |
| V9 | `/my-appointments`, `/cancel`, `/reschedule` with ownership checks | C | M | V8 | Can't cancel another clinic's or caller's appointment |
| V10 | `/callback` + `/call-ended` webhook with usage and cost | C | M | V5, S4 | Redelivered webhook doesn't double-count |
| V11 | Callables `voiceLineRegister` / `voiceLineUpdate` / `voiceLineRemove`, number-pool assignment, rules, indexes | C | M | V5 | A line can't be claimed by two clinics |
| V12 | After the pilot passes: remove the legacy `createAppointment` / `getAvailability` / `cancelAppointment` exports | C | S | Gate 2 | Not deployed |

### Phase 3: Sarvam agent and pilot

| ID | Task | Owner | Size | Depends on | Done when |
|---|---|---|---|---|---|
| P1 | Create the agent in Sarvam: instructions (Appendix A), 7 tools (Appendix B), languages, 4-minute maximum, post-call webhook | You + C | M | V6–V10, S3 | Agent answers test calls |
| P2 | Attach all 3 numbers to the agent | You | S | P1 | Each number answers |
| P3 | Pilot on your own phone: register line, test call, set forwarding, run the 12 scenarios in §5 | You + C | M | P1, V11 | Gate 1 passed |
| P4 | Check forwarding codes on **Jio, Airtel and Vi**, and whether the caller's number survives forwarding | You | S | P3 | Appendix C confirmed for all 3 |

### Phase 4: app

| ID | Task | Owner | Size | Depends on | Done when |
|---|---|---|---|---|---|
| A1 | AI Receptionist settings: switch, number, doctors, status | C | M | V11 | Line registered from the app |
| A2 | Working-hours editor + days off | C | M | – | `/slots` respects them |
| A3 | Set-up steps + Android dialler button + iPhone instructions | C | S | A1, P4 | A doctor can set up without help |
| A4 | Usage card + quota banner | C | S | V10 | Shows correct numbers |
| A5 | "AI" chip on appointments; callbacks list + badge | C | S | V10 | Visible on web and mobile |

### Phase 5: launch hardening

| ID | Task | Owner | Size | Done when |
|---|---|---|---|---|
| L1 | Alerts: `voiceApi` 5xx rate, `/call-ended` failures, reminder sweep "failed" count, GCP budget | C | S | Test alert received |
| L2 | Runbook (§7) checked by you | You | S | Read and agreed |
| L3 | Privacy policy: AI call assistant + WhatsApp reminders by CruDoc as processor; Sarvam and Meta as sub-processors | You | S | Published |
| L4 | Onboarding message/video for doctors (2 minutes: switch on, test call, forwarding) | You | S | Sent to the 40 doctors |

---

## 5. Testing

**Automated** (small, matching the existing `functions/test/*.test.js`):
- Patient decryption against a value made by the Dart code.
- `normalisePhone`: rejects `enc:` values and non-Indian numbers.
- Slot calculation with split hours and days off.
- Line resolution.
- Cost maths (`ceil` per 60 s and per 30 s).

**Pilot scenarios (Gate 1).** Call the doctor's line from another phone and don't answer:

| # | Scenario | Expected |
|---|---|---|
| 1 | New caller books tomorrow evening | Appointment in app with name; patient record encrypted; "AI" chip |
| 2 | Existing patient calls | AI greets them by first name; no duplicate patient |
| 3 | Ask for a slot that's already taken in the app | AI offers other times; never books a clash |
| 4 | Two phones book the same slot at the same moment | One succeeds, the other is offered a new time |
| 5 | Cancel an upcoming appointment | Status cancelled in app; slot free again |
| 6 | Reschedule | Time moves; reminder goes for the new date |
| 7 | Ask for Sunday (closed) | AI says closed, offers next open day |
| 8 | Ask to speak to the doctor | Callback request appears in app; no call transfer |
| 9 | Say "chest pain, emergency" | AI advises 108 / nearest hospital and ends politely; no booking |
| 10 | Speak Marathi, then Hindi | AI follows the language |
| 11 | Set quota to 0, then call | Over-quota message; ends in under 1 minute |
| 12 | Dial the AI number directly from an unknown phone | "Please call your doctor's number"; ends |

**WhatsApp:**
- `WHATSAPP_MODE=dry_run` against real data: check names, phones and skip reasons in `whatsapp_notification_logs`.
- Then live to your own test numbers: STOP and START.

**Gates:**
- **Gate 1 (pilot):** all 12 scenarios pass. Each tool call answers in under 2 seconds. Real cost per call is measured.
- **Gate 2 (5 doctors, about 1 week):**
  - Zero wrong bookings.
  - Under 5% of calls with a tool error.
  - Doctors happy.
  - Sarvam bill matches `voice_usage`.
- **Gate 3 (40 doctors):**
  - Meta verified.
  - Sarvam simultaneous-call limit above expected peak.
  - Alerts on.
  - Runbook agreed.

---

## 6. Timeline (to 31 Oct)

| Week | Dates | You | Claude |
|---|---|---|---|
| 1 | Fri 9 – Thu 15 Oct | S1–S6: Meta verification, Meta setup, Sarvam KYC and 3 numbers, questions to Sarvam | V1–V4 (P0 fixes), V5–V8 |
| 2 | Fri 16 – Thu 22 Oct | P1–P4 pilot on your phone; operator checks | V9–V11, A1–A3 |
| 3 | Fri 23 – Sat 31 Oct | 5-doctor beta (Gate 2), then all 40 (Gate 3); doctor onboarding | A4–A5, L1, fixes from beta, V12 |

**Biggest schedule risks:**
- Meta Business Verification takes too long. Without it, reminders are capped at about 250 a day; start S1 today.
- Sarvam's simultaneous-call limit isn't raised in time.

---

## 7. Runbook (after launch)

| Situation | What to do |
|---|---|
| An AI number stops working | Move its lines to another number (Firestore now; super admin later). The app shows those doctors *"Update forwarding to 080-…-0002"* with the dialler button. |
| Sarvam is down | Tell doctors to switch forwarding off (`##004#`). Calls just ring as before. Turn it back on afterwards. |
| `voiceApi` errors spike | Agent reads the `say` fallback and offers a callback. Check logs; roll back the deploy. |
| A doctor says "AI booked a wrong time" | Open `voice_calls/{interactionId}` and the Sarvam transcript, then fix the prompt or server rule |
| Clinic over quota | Banner in app; offer a top-up; set `extraCalls` |
| WhatsApp quality rating drops to Medium | Pause any non-essential sending; check opt-out volume; review the template wording |
| Monthly | Compare total `voice_usage.costPaise` with Sarvam's invoice, and WhatsApp spend with Meta's |

---

## 8. Costs

### Unit prices

| Item | Price | Notes |
|---|---|---|
| Sarvam AI agent (Business) | ₹3.00 per started minute | billed per 60 s |
| Sarvam line (Vobiz) | ₹0.20 per started 30 s | |
| **Per call-minute, all-in** | **₹3.40 (₹4.01 with GST)** | limit was ₹8 ✅ |
| AI numbers | 3 × ₹159 = ₹477/month | ₹59 each in the first month |
| WhatsApp reminder (Meta, utility) | ≈ ₹0.145 per message | paid by CruDoc on the shared number |
| Firebase (functions, Firestore) | ≤ ₹10 per clinic per month | optional warm instance: a few hundred ₹/month in total |

### Per call

| Call | Cost | With GST |
|---|---|---|
| Under 60 s | ₹3.40 | ₹4.01 |
| 61–90 s | ₹6.60 | ₹7.79 |
| 91–120 s | ₹6.80 | ₹8.02 |
| **Average (assumed)** | **≈ ₹5.10** | **≈ ₹6.00** |
| Worst case (4-minute cap) | ₹13.60 | ₹16.05 |

### Per clinic per month (20 AI calls included, ~400 appointments)

| Item | Cost |
|---|---|
| 20 AI calls × ₹5.10 | ₹102 |
| 400 reminders × ₹0.145 | ₹58 |
| Firebase | ₹10 |
| **Total** | **₹170 (≈ ₹201 with GST)**, 25–40% of a ₹500–800 plan |
| Each extra call | ≈ ₹6 with GST, so sell at ₹10 |

### Your total

| | 40 doctors | 250 clinics |
|---|---|---|
| Clinics × ₹170 | ₹6,800 | ₹42,500 |
| 3 AI numbers | ₹477 | ₹477 |
| **Total with GST** | **≈ ₹8,600/month** | **≈ ₹50,700/month** |
| Revenue at ₹500–800 | ₹20,000–32,000 | ₹1,25,000–2,00,000 |

If clinics were given unlimited AI calls (about 50 each), the 40-doctor bill would be about ₹15,400. That's why there's a quota.

---

## 9. Later (not in this plan)

| Item | Why later |
|---|---|
| Reminders from each clinic's **own** WhatsApp number (Meta coexistence + Embedded Signup) | Needs Tech Provider registration and App Review (weeks). **Full plan in §11.** |
| Hindi / Marathi reminder templates | Separate templates, each approved by Meta |
| Push notifications for callbacks | Needs `firebase_messaging` |
| Outgoing AI calls (reminder calls) | Not wanted. Would bring TRAI telemarketing rules into play. |
| Super admin number-pool and usage pages | Firestore console is enough for 40 doctors |
| Doctor holidays synced from calendar | Manual days-off list first |

---

## 10. Open questions

| # | Question | Ask | Needed by |
|---|---|---|---|
| Q1 | Exact variable name for the **forwarding number** in tool calls, and is it in the post-call webhook? Same for the caller ("User Identifier") and the call ID | Sarvam | V5 |
| Q2 | Can API tools send a custom header (`X-Api-Key`)? How are webhooks authenticated? | Sarvam | V5, V10 |
| Q3 | **Simultaneous-call limit on the Business plan** (it's per account), and can it be raised? | Sarvam | Gate 3 |
| Q4 | Call recordings and transcripts: on or off, how long they're kept, where they're stored | Sarvam | L3 |
| Q5 | Does the caller's number survive forwarding on Jio / Airtel / Vi? | Test (P4) | Gate 1 |
| Q6 | Confirm pricing: 20 calls included, ₹10 per extra call | You | A4 |
| Q7 | Reminders for every clinic or only those with `omnichannel_messaging`? (It's in the default module list today) | You | V2 |

---

## 11. Phase 2: reminders from each clinic's own number (coexistence)

**Goal:** a clinic connects its existing WhatsApp Business number, and reminders come from the doctor's own number instead of CruDoc's. The doctor keeps using the WhatsApp Business app on their phone as before. Clinics that don't connect stay on the shared number.

**Availability:** coexistence works for Indian (+91) numbers. Several sources agree, though most are vendor blogs, so confirm in Meta's docs when building.

### 11.1 One-time setup for CruDoc (about 3–6 weeks, mostly waiting on Meta)

| Step | Who | Time |
|---|---|---|
| C1. Meta Business Verification (same as S1) | You submit, Meta reviews | 2 days – 2 weeks |
| C2. Register as **Tech Provider** | You (self-serve) | 1 day, after C1 |
| C3. Meta app of type **Business**: WhatsApp product, Facebook Login for Business, Embedded Signup configuration with a **System User** token and coexistence enabled | You + Claude | 1 day |
| C4. Build the "Connect WhatsApp" flow, per-clinic sending, fallback and monitoring (§11.3) | Claude | 4–6 days (groundwork exists in `functions/src/whatsapp/tenants.ts`, `outbox.ts`, not exported yet) |
| C5. **App Review** for Advanced Access to `whatsapp_business_messaging`, `whatsapp_business_management`, `business_management`. Needs a screen recording of C4 working. | You submit, Meta reviews | 1–7 days per try, often 2 tries |
| C6. Pilot with 1–2 real clinics | You + Claude | 2–3 days |

```
Week 1–2   C1 verification (waiting)   ║  C4 built against Meta's test number
Week 2–3   C2 + C3                     ║  C4 finished and tested
Week 3–5   C5 App Review (waiting, maybe twice)
Week 5–6   C6 pilot → offered to all clinics
```

If S1 starts now, coexistence can be available around **mid to late November 2026**. It is **not** needed for the 31 Oct launch.

The CruDoc-side checklist (secrets, permissions, service accounts) is in `docs/whatsapp-meta-status.md`.

### 11.2 Each new clinic: about 10–15 minutes, no waiting on Meta

The long setup above happens **once**. After that, each clinic onboards itself inside CruDoc:

| Step | Time |
|---|---|
| 1. Settings → **"Send reminders from your own WhatsApp"** → Connect | – |
| 2. Log in with Facebook (or create an account) | 2–3 min |
| 3. Confirm the business details (Meta creates the clinic's business account) | 2–3 min |
| 4. Enter the WhatsApp Business number and **scan the QR code** with the WhatsApp Business app | 1–2 min |
| 5. Add a payment card to the clinic's WhatsApp account (Meta bills the clinic directly) | 2–3 min |
| 6. Done: the next reminder goes from the clinic's own number | instant |

**A clinic does not need:** its own Business Verification, its own App Review, or its own template approvals. CruDoc creates its templates in the clinic's account during connection.

**Requirements for the clinic:**

| Requirement | If not met |
|---|---|
| Number is on the **WhatsApp Business app** (not regular WhatsApp) | Switch apps (free, chats move over), then wait 7 days |
| Number has used the Business app **for at least 7 days** | Wait, and stay on the shared number meanwhile |
| Latest Business app version (2.24.17 or newer), phone with a camera | Update the app |
| A Facebook account | Create one (5 min) |
| A payment card for Meta | Can't connect without it |

### 11.3 Rules CruDoc must follow

| Rule | What to build |
|---|---|
| **Open the app at least every 14 days**, or sync can break | Watch each clinic's connection (webhook `account_update` + daily health check). If it breaks, **fall back to the shared CruDoc number automatically** and show the doctor: "Open WhatsApp Business to reconnect." |
| **Never lose a reminder** | The reminder sweep sends from the clinic's number when `whatsapp_tenants/{clinicId}.status == "connected"`, otherwise from the shared number |
| **Up to 6 months of chat history can sync** | **Don't import chat history.** CruDoc only needs to send reminders and handle replies; storing old patient chats is a DPDP risk with no benefit. |
| **Broadcast lists in the app become read-only** | Say so on the Connect screen. Offer CruDoc campaigns instead (marketing ≈ ₹1.09 per message, needs patient opt-in). |
| **No green tick; disappearing messages, view-once, live location and group sync are restricted** | Mention it on the Connect screen |
| **Patient replies** | They arrive in the doctor's own WhatsApp Business app. CruDoc still handles STOP/START from the webhook. |
| **Token safety** | Each clinic's System User token is stored in Secret Manager, never in Firestore (as `tenants.ts` already does) |

### 11.4 What changes compared with the shared number

| | Shared CruDoc number (launch) | Clinic's own number (Phase 2) |
|---|---|---|
| Reminders come from | CruDoc's number | The doctor's own number |
| Doctor setup | Nothing | About 10–15 min, once |
| Who pays Meta | CruDoc (~₹58/clinic/month) | The clinic, from its own card |
| Daily sending limit | Shared by all clinics | Separate per clinic (250 at the start, plenty for one clinic) |
| Patient replies | Auto-reply "call the clinic" | Land in the doctor's WhatsApp Business app |
| One clinic's quality problems affect others? | Yes, one shared quality rating | No |

### 11.5 Tasks

| ID | Task | Owner | Size | Depends on | Done when |
|---|---|---|---|---|---|
| W1 | Tech Provider registration + Business-type app + Embedded Signup config (coexistence on) | You + C | S | S1 | `config_id` recorded in `whatsapp-meta-status.md` |
| W2 | Callable to finish signup: exchange the code, save the token to Secret Manager, register the number, subscribe the webhook, create templates in the clinic's account | C | L | W1 | Test clinic connected end to end |
| W3 | Reminder sweep picks the sender per clinic, with fallback to the shared number | C | M | W2 | Disconnected clinic still gets reminders via the shared number |
| W4 | Connection monitoring: `account_update` webhook + daily health check + reconnect banner | C | M | W2 | Breaking a test connection shows the banner within a day |
| W5 | App: "Send reminders from your own WhatsApp" screen with requirements, limitations and status | C | M | W2 | A doctor connects without help |
| W6 | App Review submission with screen recording | You | S + wait | W2, W5 | Advanced Access granted |
| W7 | Pilot with 1–2 clinics, then open to all | You + C | S | W6 | Gate passed |

---

## Appendix A: Sarvam agent instructions (draft)

```
You are the phone assistant for {{clinic_name}}. You are an AI. If asked, say so.
Today is {{weekday}}, {{today}}. The time now is {{now_local}} (India).
Clinic hours: {{hours_text}}

Speak in the caller's language (Marathi, Hindi or English). Short, polite sentences.

At the start of every call, call `session` first and follow its `mode`:
- patient: help the caller.
- verify, over_quota, paused, unknown_line: say the `say` text, then end the call.

You can: book, move or cancel an appointment; tell clinic hours; take a callback request.
You cannot: give medical advice, talk about fees or treatment, or transfer the call.

Rules:
1. Never make up a time. Call `slots` before offering times. Offer at most 3.
2. If there is more than one doctor, ask which doctor first.
3. If you don't know the patient's name, ask for it. Do not ask for their phone number.
   If they are booking for someone else, ask that person's name.
4. Before booking, read back doctor, day, date and time. Book only after a clear "yes".
5. If a tool returns ok=false, say its `say` sentence in the caller's language and carry on.
6. For cancel or move: call `my_appointments`, confirm which one, then act.
7. If the caller wants the doctor: offer a callback (`callback`). Never transfer.
8. If the caller mentions an emergency (chest pain, heavy bleeding, unconscious,
   accident, breathing trouble): tell them to call 108 or go to the nearest
   hospital now, then end the call. Do not book.
9. Keep the call under 3 minutes. When the task is done, thank them and end.
```

## Appendix B: tools to create in Sarvam

All tools: `POST https://<voiceApi URL>/<route>`, header `X-Api-Key`. Fields marked *system* come from Sarvam's call variables, not from the model.

| Tool | Route | Model fills | System fills |
|---|---|---|---|
| `session` | `/session` | – | `forwarded_from`, `caller`, `interaction_id` |
| `slots` | `/slots` | `doctor_id`, `date` (YYYY-MM-DD) | same three |
| `book` | `/book` | `doctor_id`, `patient_name`, `date`, `time` (HH:MM), `reason` | same three |
| `my_appointments` | `/my-appointments` | – | same three |
| `cancel` | `/cancel` | `appointment_id`, `reason` | same three |
| `reschedule` | `/reschedule` | `appointment_id`, `date`, `time` | same three |
| `callback` | `/callback` | `name`, `note` | same three |

Post-call webhook: `POST https://<voiceApi URL>/call-ended` with the Sarvam webhook secret.

## Appendix C: call forwarding for doctors

**Android (most phones):** Phone app → ⋮ → Settings → Calls (or Supplementary services) → Call forwarding → Voice. Set *When busy*, *When unanswered* and *When unreachable* to the AI number shown in CruDoc.

**iPhone:** Settings → Phone → Call Forwarding only offers "always". For *when unanswered*, dial the codes below from the Phone app.

**Standard GSM codes** (Airtel, Vi, BSNL; confirm in P4):

| Purpose | Dial |
|---|---|
| Forward when busy, unanswered or unreachable | `**004*<AI number>#` |
| Unanswered after 20 seconds | `**61*<AI number>**20#` |
| Turn off all conditional forwarding | `##004#` |
| Forward every call (night / holiday) | `**21*<AI number>#` |
| Turn off "every call" | `##21#` |

**Jio** uses its own codes, which we confirm with Jio during the pilot (P4) before giving them to doctors.

## Appendix D: glossary

| Word | Meaning |
|---|---|
| Forwarding | The phone company sends an unanswered call to another number |
| Forwarding number / line | The doctor's number that forwards to the AI; the key of the phone book |
| AI number | One of the 3 Sarvam numbers; patients never see it |
| Tool | A web address the AI calls mid-conversation to read or change CruDoc data |
| Webhook | A message Sarvam or Meta sends to CruDoc when something happens (call ended, message delivered) |
| Template | A WhatsApp message approved by Meta in advance, with blanks filled per patient |
| DEK / KEK | The clinic's data key that encrypts patient fields / the key that protects it |
| `phoneIndex` | A one-way fingerprint of a patient's phone, so CruDoc can find a patient without storing the phone in plain text |
| Quota | AI calls included per clinic per month |
| Simultaneous-call limit | How many calls can be live at once across the whole Sarvam account |
