# CruDoc AI Receptionist: Final Plan

| | |
|---|---|
| **Date** | 11 October 2026 (revision 2) |
| **Status** | Approved direction; building |
| **Replaces** | The own-server draft of the same day (`ai_receptionist_own_server_plan.md`), the 9 Oct plan (`ai_receptionist_plan.md`) and Smit's 10 Oct "AI answers first" plan. All kept for history. |
| **Target** | Pilot on Smit's number from 13 Oct · 5-doctor beta from 24 Oct · 40 doctors live in `no_answer` mode by 31 Oct 2026 |

---

## 1. Summary

**What we are building**

1. **AI receptionist.** When a doctor misses a call, the phone company forwards it to that clinic's AI number. The AI books, moves or cancels the appointment in CruDoc, or takes a message for the doctor.
2. **WhatsApp reminders** the evening before each appointment, sent automatically from one shared CruDoc number.

**What changed from the own-server draft, and why**

The draft ran the AI on our own server (Pipecat) with our own Vobiz account. We checked the live prices and docs on 11 Oct (§10) and changed course:

| Finding | Effect |
|---|---|
| A Sarvam-rented number works only with Sarvam's hosted agent | We already own one (+91 80 6426 1740). Use it. |
| Sarvam's hosted agent picks its own LLM; you cannot bring GLM, Gemini or any other model | "Sarvam + GLM-5" is not one product. The hosted agent is the one-vendor option. |
| GLM-5.3 on Sarvam's API costs ₹126 in / ₹390 out per 1M tokens, and its reasoning is billed as output | On our own server it makes a call cost about the same as the hosted agent, and it is slow. The ₹13.5/₹45 "GLM 5.3 Flash" price in the draft is not on Sarvam's price page. |
| Vobiz India prices are not published | The draft's main cost advantage was unproven. |
| Hosted agent: one bill, no server, no audio-streaming fee, all models in India, sub-second replies claimed | Fastest and lowest-risk way to 31 Oct. |
| Hosted agent cannot do "press 1 to accept" on a transfer, and tools don't receive the forwarding number | Launch `no_answer` only (no handover needed). One AI number per clinic. AI-first is decided in November (§9). |

**Decisions**

| Topic | Decision |
|---|---|
| Who runs the AI | **Sarvam Voice Agents (hosted)** for `no_answer`. Our own server is the fallback for AI-first only (§9). |
| AI numbers | **One Sarvam-rented number per clinic**, ₹159/month (₹59 the first month). |
| Telling clinics apart | Each clinic's agent carries a fixed `line_id` variable (its AI number). One agent per clinic, made from a template (§4.3). |
| Rules and data | One booking API, `voiceApi` (Cloud Functions, asia-south1), and Firestore. The AI can ask; only `voiceApi` decides. |
| "I want to speak to someone" | The AI takes a message (name + one-line question). A callback card appears in the app. No call transfer at launch. |
| Call direction | Incoming only. The AI never calls patients. |
| Reminders | WhatsApp from one shared CruDoc number at 18:00 the day before, plus an 08:00 catch-up. |
| Switching later | `voiceApi` knows nothing about Sarvam except the webhook parser, so a move to our own server is 1–2 days of server work, not a rewrite. |

**Still to decide**

| # | Question | Recommendation | By |
|---|---|---|---|
| O1 | What clinics pay | 20 AI calls included; ₹10 per extra call. The ₹159 number is the biggest fixed cost per clinic (§7) | 22 Oct |
| O2 | AI-first (AI answers every call, reception on request) | Decide in November: Sarvam if it has added key presses / whisper by then, otherwise our own server for those clinics only (§9) | 7 Nov |
| O3 | Call recordings | Off in Sarvam. Transcripts stay in Sarvam's call logs; CruDoc stores outcomes only | 22 Oct |

---

## 2. How it fits together

```
Patient dials the doctor's usual number (98220 11111)
        │  doctor answers → normal call, AI not involved
        │  busy / no answer ~20 s / switched off → phone company forwards
        ▼
Clinic's AI number (Sarvam-rented, e.g. 080 6426 1740)
        ▼
Sarvam hosted agent  (this clinic's copy; line_id = 918064261740)
   listens, thinks, speaks (Sarvam's own models, in India)
        │  API tools: POST, X-Api-Key, body = {line_id, caller, interaction_id, ...}
        ▼
voiceApi  (Cloud Functions, asia-south1)  ── rules: hours, clashes, ownership, quota
        ▼
Firestore  ──▶  CruDoc app (live): appointment with "AI" chip, callback card
        ▲
        └── Sarvam post-call webhook ──▶ voiceApi /call-ended (duration, cost, usage)
```

- **Sarvam = ears, mouth and conversation.** It stores the transcript in its own call logs.
- **`voiceApi` = rules and data.** If the AI gets something wrong, `voiceApi` refuses it and returns a sentence for the AI to say.
- **Firestore = the record.** Lines, appointments, calls, costs and callbacks.

---

## 3. How each flow works

### 3.1 Doctor misses the call, AI books

Ramesh calls Dr. Sharma on 98220 11111 at 13:40. The doctor is with a patient.

1. After ~20 s the phone company forwards the call to the clinic's AI number.
2. The agent calls `session`. `voiceApi` finds the clinic from `line_id` and Ramesh from his number: he's a known patient with no upcoming visit.
3. AI: *"Namaste Ramesh ji, Sharma Dental Clinic. How can I help?"* Ramesh: *"Tomorrow evening, tooth pain."*
4. AI calls `slots` for tomorrow and gets 17:00, 17:30, 18:30. Ramesh picks 17:30.
5. AI reads it back (*"Dr. Sharma, Saturday 10 October, 5:30 pm. Shall I book?"*), Ramesh says yes, AI calls `book`.
6. The appointment appears in CruDoc with an "AI" chip. Call cost ≈ ₹3.40–6.60.

### 3.2 Caller wants a person, or asks about fees or treatment

The AI says the doctor isn't available, takes the caller's name and a one-line question, reads it back and calls `callback`. A callback card appears in the app with the caller's number. The AI says *"I've passed your message to Dr. Sharma. The clinic will call you back during clinic hours."* It never promises a time.

If the same caller already has an open callback, the AI says it's already with the doctor and adds to that note instead of creating a second card.

### 3.3 Existing patient moves or cancels

`session` returns the caller's upcoming appointments. The AI confirms which one, calls `slots` for the new day, reads the new time back and calls `reschedule` (or `cancel`). A caller can only touch their own appointments at this clinic. The WhatsApp reminder follows the new date.

### 3.4 Emergency

*"Chest pain"*, heavy bleeding, unconscious, accident, breathing trouble: *"Please call 108 or go to the nearest hospital now."* No booking, no callback.

### 3.5 When something is off

| Situation | What the caller hears |
|---|---|
| Clinic over its monthly quota | *"Please call again during clinic hours or send a WhatsApp."* Call ends within a minute. |
| AI paused in the app | Same short message. The app shows the off code so the doctor can stop forwarding. |
| Someone dials the AI number directly (not forwarded, not the doctor) | Normal conversation. Harmless: they can only book at this clinic. |
| `voiceApi` errors | The agent's tool "if it fails" text: *"Sorry, I can't reach the clinic diary right now. I'll take a message."* and it takes a callback note in the transcript. |

### 3.6 Doctor setup (once, about 5 minutes)

1. CruDoc staff assign the clinic an AI number and agent (§4.3). Later: self-serve in the app.
2. The doctor calls the AI number once from their own number. AI: *"Your number is verified for Sharma Dental Clinic."* The line becomes active.
3. In the app (later) or by our guide: turn on conditional forwarding (§5).
4. Test: call from another phone and don't answer.

---

## 4. What we build

### 4.1 Parts

| Part | Today | Change |
|---|---|---|
| `voiceApi` (Cloud Functions) | 3 legacy endpoints (`createAppointment`, `getAvailability`, `cancelAppointment`) | New single function with the routes in §4.4 |
| Server-side patient encryption | Missing (P0) | `functions/src/crypto/patientCipher.ts`, mirroring the app's `FieldCipher` |
| Patient lookup by phone | Missing | `phoneIndex` on every patient: trigger + one-time backfill + index |
| WhatsApp reminders | 18:00 sweep reads encrypted fields (P0) | Decrypt, Indian mobiles only, 08:00 catch-up, re-send after a reschedule |
| Sarvam agent | One rented number | Agent template (instructions, tools, webhook), one copy per clinic |
| App | Module `ai_agentic_calling` and the `ai` permission exist; no screens | Working hours, AI chip, callback cards, usage, setup steps with the forwarding dialler button |
| Super Admin | "AI Receptionist" tab talks to the old voice server | Reads and writes Firestore `voice_lines` (after launch) |
| `voice-receptionist/` (Pipecat) | Built for Twilio | Frozen. Kept for the AI-first fallback (§9). |

### 4.2 Data (Firestore, written by functions only)

| Collection | Holds |
|---|---|
| `voice_lines/{lineId}` | `lineId` = the AI number as digits (`918064261740`). Clinic, doctors on the line, the doctor's published number, status (`pending_test` / `active` / `paused`), Sarvam agent id |
| `users/{uid}.aiReceptionist` | Working hours, slot length, days off (written by the app) |
| `voice_calls/{callId}` | One per call: what the AI did (booked / moved / cancelled / message), duration, cost |
| `voice_usage/{clinicId}_{YYYYMM}` | Monthly calls, seconds, cost and quota |
| `voice_callbacks/{id}` | Messages for the doctor: name, question, caller (encrypted), status |
| `slot_locks/{doctorId}_{startMillis}` | Stops two calls booking the same slot |

Caller numbers are stored encrypted with the clinic's key, plus an HMAC index (`phoneIndex` / `callerIndex`) for lookups.

### 4.3 One agent per clinic

During a call, Sarvam's tools receive only the caller's number, the call id, the transcript and the call length. The number that was dialled reaches us only in the post-call webhook. So each clinic gets its own copy of the agent with one input variable, `line_id`, set to that clinic's AI number (not sent to the LLM). Every tool sends it.

- **Pilot:** duplicate the agent in the dashboard and change `line_id`.
- **40 clinics:** create the copies with Sarvam's agent API from one template, and push instruction changes to all copies with the same script.
- **If Sarvam exposes the dialled number as a variable** (asked, §11), we collapse to one shared agent and nothing in `voiceApi` changes: it already accepts the dialled number as `line_id`.

### 4.4 `voiceApi` routes

`POST https://asia-south1-<project>.cloudfunctions.net/voiceApi/<route>`, header `X-Api-Key`. Every body carries `line_id`, `caller` (Sarvam "User Identifier") and `interaction_id`. Times are clinic-local (`2026-10-10`, `17:30`). Success is `{ok: true, ...}`; failure is `{ok: false, code, say}` where `say` is a ready sentence.

| Route | What it does |
|---|---|
| `session` | First call every time. Returns `mode`, clinic name, doctors, today's date / weekday / time, hours, the caller's first name and upcoming appointments, and whether they have an open message |
| `slots` | Up to 6 free times for a doctor and date, spread across the day, or the next day with free times |
| `book` | Books in one transaction with a slot lock. Finds the patient by `phoneIndex` or creates one with encrypted fields. A retried request returns the same booking |
| `my_appointments` | The caller's upcoming appointments at this clinic |
| `cancel`, `reschedule` | Only the caller's own appointments at this clinic |
| `callback` | Saves a message for the doctor; merges into an open one from the same caller |
| `call-ended` | Sarvam's post-call webhook (URL token, not the API key). Records duration and cost, updates monthly usage exactly once per call |

`session` modes: `patient` (normal), `verify` (the doctor's test call from their own number), `over_quota`, `paused`, `unknown_line`.

### 4.5 Fix first (P0)

1. **Reminders read encrypted names and phones without decrypting them** (`functions/src/whatsapp/reminders.ts`). About 26% of encrypted phones look like valid foreign numbers, so reminders would reach strangers abroad. Fix: decrypt on the server, accept Indian mobiles only, reject `enc:` values.
2. **Patients created by the legacy AI endpoint have no name and are stored in plain text.** The new `book` writes encrypted `firstName`, `lastName`, `phone` and `phoneIndex`.
3. **The AI can't recognise existing patients.** `phoneIndex` on every patient.
4. **The legacy `cancelAppointment` cancels any id it's given.** The new routes check ownership. Remove the legacy endpoints after the pilot.

---

## 5. Forwarding the doctor's number

Conditional forwarding only acts on calls the doctor doesn't take. Answering, outgoing calls and WhatsApp work as before.

**Always dial the AI number with `+91` or a leading `0`.** Sarvam's numbers are 080 landline numbers; without the prefix the network says the number doesn't exist.

| Phone / carrier | How |
|---|---|
| Any Android, any carrier (easiest) | Phone → ⋮ → Settings → Calls (or Supplementary services) → Call forwarding → Voice. Set *When busy*, *When unanswered*, *When unreachable* to `+918064261740`. Leave *Always forward* off. On dual SIM, set it on the SIM patients call. |
| Airtel / Vi / BSNL by code | `**004*+918064261740#` (busy + unanswered + unreachable) or `**61*+918064261740**20#` (unanswered after 20 s). Off: `##004#` |
| Jio | Use the phone settings above or the MyJio app. Published `*403/*405/*409` codes disagree between sources, and Jio has disabled the forward-all code. Off: `*413` |
| iPhone | Settings → Phone → Call Forwarding is "always" only, so don't use it. Use the codes above (Airtel/Vi), or ask Jio to set no-answer forwarding. |

**Things to tell doctors:** declining a call sends it to the AI; the AI replaces carrier voicemail; forwarded calls use plan minutes (unlimited plans cover them); forwarding stops if a prepaid plan lapses; turn it off before roaming abroad; WhatsApp calls are never forwarded. Pausing the AI in CruDoc does not undo forwarding at the phone company.

**Never transfer a caller back to the doctor's number.** If the doctor doesn't answer, it forwards straight back to the AI and loops.

**Test F1 (pilot, day 1):** forward from Jio, Airtel and Vi and check what Sarvam's call log shows as the User Identifier. If it's the *patient's* number, recognition works. If it's the *doctor's* number, `voiceApi` sees `caller == published number` and tells the AI to ask the caller for their mobile number instead.

---

## 6. Sarvam agent setup

Instructions are in Appendix A. Tools are in Appendix B. Settings:

| Setting | Value |
|---|---|
| Languages | Marathi, Hindi, English, auto-switch |
| Voice | Bulbul v3, a warm female voice (pick after listening) |
| Max call length | 4 minutes |
| Inbound deployment schedule | 00:00–23:59, all days (the default 09:00–18:00 would leave evening calls unanswered) |
| Input variable | `line_id`, default = this clinic's AI number as digits; "send to LLM" off |
| Post-call webhook | `https://.../voiceApi/call-ended?token=<SARVAM_WEBHOOK_SECRET>` |
| Recording | Off |

### 6.1 Pilot setup, step by step (Smit's number)

All commands from `CruDoc/`, project `svayatta-crudoc-dev`.

1. **Secrets** (`VOICE_BOT_API_KEY` already exists):
   ```
   firebase functions:secrets:set PATIENT_KEK_PEPPER      # the app's _appPepper, from lib/core/services/encryption_key_manager.dart
   firebase functions:secrets:set SARVAM_WEBHOOK_SECRET   # any long random string
   ```
2. **Deploy** rules, indexes and the new or changed functions:
   ```
   firebase deploy --only firestore:rules,firestore:indexes,functions:voiceApi,functions:onPatientWrittenIndexPhone,functions:sendDayBeforeWhatsAppReminders,functions:sendMorningCatchUpWhatsAppReminders
   ```
   Check: `curl -X POST https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net/voiceApi/session` must answer `{"ok":false,"code":"unauthorized"}` (our code), not Google's 403 page.
3. **Backfill `phoneIndex`** (from `functions/`, after `gcloud auth application-default login`): `node scripts/backfill-phone-index.js --project svayatta-crudoc-dev`, check the counts, then again with `--write`.
4. **Module:** in Super Admin, give the test clinic `ai_agentic_calling`.
5. **Line:** `node scripts/voice-line.js --project svayatta-crudoc-dev --ai-number +918064261740 --clinic <clinic owner uid> --published <the doctor's own number>`
6. **Sarvam:** build the agent from Appendices A and B, set `line_id` = `918064261740`, attach the number in an Inbound deployment open 24×7, and set the post-call webhook.
7. **Verify:** call +91 80 6426 1740 from the published number. The AI says the number is verified.
8. **Forwarding (§5)**, then test F1 and the §11 scenarios.

---

## 7. Costs

All before 18% GST.

### 7.1 Unit prices

| Item | Price | Source |
|---|---|---|
| Sarvam hosted agent | ₹3.00 per started minute (speech, LLM, voice included) | Your Sarvam Business plan |
| Line (Vobiz via Sarvam) | ₹0.20 per started 30 s | Your Sarvam plan |
| Sarvam-rented number | ₹159/month (₹59 the first month) | Sarvam |
| WhatsApp utility message | ≈ ₹0.145 | 9 Oct plan |

### 7.2 Per call and per month

| Call | Cost |
|---|---|
| Up to 60 s | ₹3.40 |
| 61–90 s | ₹6.60 |
| 91–120 s | ₹6.80 |
| Average (half 45 s, half 90 s) | ≈ ₹5.00 |
| Worst case (4-minute cap) | ₹13.60 |

| 40 clinics, 20 calls each (800 calls) | Per month |
|---|---|
| Calls | ≈ ₹4,000 |
| 40 numbers × ₹159 | ₹6,360 |
| Reminders + Firebase | ≈ ₹2,700 |
| **Total** | **≈ ₹13,100 (≈ ₹15,450 with GST), ≈ ₹386 per clinic** |

- The number is the largest fixed cost per clinic. Offer the AI receptionist only to clinics that switch it on.
- An extra call costs us ≈ ₹6 with GST, so ₹10 per extra call leaves a margin.
- For comparison, our own server would have been ≈ ₹5,500–8,600 a month at this size *if* Vobiz India prices match the US list and 3 shared numbers worked. Neither is confirmed.

---

## 8. Things to note

- **Testing credits.** The hosted agent draws from the same Sarvam wallet as everything else. Each test minute costs ₹3.40.
- **Data.** Sarvam hosts every model in India. CruDoc stores no transcripts; callers' numbers are encrypted. The privacy policy must name Sarvam (and Vobiz through Sarvam) and Meta as processors.
- **Quota.** 20 calls per clinic per month by default (`voice_usage.includedCalls`), with a banner at 80% and 100% (app, later).
- **Simultaneous calls.** Sarvam claims platform scale beyond 20,000 calls; our account's own limit is unknown (§11).
- **P0 first.** Don't send live WhatsApp reminders before the P0 fix (§4.5) is deployed and Meta Business Verification is done (about 250 messages a day before it, 2,000 after).

---

## 9. AI-first (November decision)

AI-first means the published number forwards **every** call to the AI and reception is rung on request. It needs a handover where the receptionist hears who is calling and presses 1 to accept. Sarvam's run-time lists key presses as planned; plain transfer to a number exists today.

| If, in early November… | Then |
|---|---|
| Sarvam supports key presses / whisper on transfer | Stay on Sarvam. Add `transfer_check` to `voiceApi`. |
| It doesn't | Run our own server (Pipecat + Vobiz + Sarvam speech + Sarvam-105B Chat or DeepSeek V4.1 Flash) for AI-first clinics only. Design in `ai_receptionist_own_server_plan.md`. Not GLM-5.3. |

---

## 10. Tasks and timeline

Owner: **S** = Smit / Soham, **C** = Claude.

### Week 1 (11–17 Oct): backend and pilot

| ID | Task | Owner | Done when | Status (11 Oct) |
|---|---|---|---|---|
| V1 | `patientCipher.ts` + test against a value encrypted by the Dart app | C | Test decrypts the Dart sample | Built. Node and Dart each decrypt the other's values |
| V2 | Reminders: decrypt, Indian mobiles only; re-send after reschedule; 08:00 catch-up | C | Dry run shows real names and no foreign numbers | Built; dry run after deploy |
| V3 | `phoneIndex` trigger + backfill script + index | C | Every patient has `phoneIndex` | Built; backfill after deploy |
| V5 | `voiceApi`: `session`, `slots`, `book`, `my_appointments`, `cancel`, `reschedule`, `callback`, `call-ended`; rules; indexes | C | Unit tests pass; two bookings for one slot, one wins | Built; 26 tests on an in-memory Firestore. Rules tests written, need the emulator (Java 21) |
| V6 | Line setup script (create `voice_lines` doc) | C | Smit's line registered | Built (`functions/scripts/voice-line.js`) |
| S1 | Secrets: `PATIENT_KEK_PEPPER` (same value as the app), `SARVAM_WEBHOOK_SECRET`; deploy (§6.1) | S | Deployed | |
| S2 | Build the agent from Appendix A/B in Sarvam; Inbound deployment 24×7 | S + C | Test call books into CruDoc |
| P1 | Pilot on Smit's number: F1 + scenarios 1–12 | S + C | Gate 1 |

### Week 2 (18–24 Oct): app

| ID | Task | Owner | Done when |
|---|---|---|---|
| A1 | AI Receptionist settings: status, working hours, slot length, days off | C | `slots` follows them |
| A2 | Setup steps with the Android forwarding dialler button and iPhone / Jio notes | C | A doctor sets up without help |
| A3 | "AI" chip on appointments; callback cards + dashboard badge; usage and quota banner | C | Visible on web and mobile |
| A4 | Agent-copy script for many clinics (Sarvam API) | C | 5 agents created from the template |
| S3 | Ask Sarvam the §11 questions | S | Written answers |

### Week 3 (25–31 Oct): beta and launch

| ID | Task | Owner | Done when |
|---|---|---|---|
| B1 | 5-doctor beta, about 4 days | S + C | Gate 2 |
| L1 | Alerts: `voiceApi` errors, `call-ended` failures, daily cost | C | Test alert received |
| L2 | Privacy policy; 2-minute doctor guide | S | Published |
| B2 | 40 doctors live | S | 31 Oct if Gate 2 passes, otherwise 7 Nov |
| L3 | Remove the 3 legacy endpoints; Super Admin tab reads `voice_lines` | C | Not deployed |

---

## 11. Testing

| # | Scenario | Expected |
|---|---|---|
| 1 | New caller books | Appointment in the app with a name; patient fields encrypted; "AI" chip |
| 2 | Existing patient calls | Greeted by first name; no duplicate patient |
| 3 | Slot already taken in the app | Other times offered; never a double booking |
| 4 | Two callers book the same slot at once | One succeeds; the other is offered a new time |
| 5 | Cancel | Cancelled in the app; slot free again |
| 6 | Reschedule | Time moves; the reminder goes out for the new date |
| 7 | Ask for a closed day | AI says closed and offers the next open day |
| 8 | Ask for the doctor, fees or medicine | Message taken; callback card; no medical or fee answer |
| 9 | Caller with an open message rings again | Told it's with the doctor; no duplicate card |
| 10 | "Chest pain" | 108 first; no booking, no callback |
| 11 | Marathi, then Hindi | AI follows the language |
| 12 | Quota set to 0; line paused | Short message, ends in under a minute |

**Gate 1 (pilot):** all pass; tool calls under 2 s; real cost per call measured.
**Gate 2 (beta):** zero wrong bookings; under 5% of calls with a tool error; Sarvam bill matches `voice_usage` within 10%; doctors happy.

**Questions for Sarvam (§4.3, §8)**

1. Can a tool or the on-start hook read the **dialled number** during the call?
2. Our account's **simultaneous-call limit**, and how to raise it.
3. Can the API tool's `api_key` auth send a custom header name (`X-Api-Key`)? (Static headers work if not.)
4. Agent API: create and update agents from a template (for 40 copies).
5. Transfer with key-press accept / whisper: on the roadmap, and when?

---

## Appendix A: Agent instructions

Values in `{{ }}` are agent variables filled by the **on-start hook** (`session`, below) through "Save reply into variables". In Sarvam's editor, insert them with `@`. The greeting is just `{{say}}`.

```
You are the phone receptionist for {{clinic_name}}. You are an AI; say so if asked.
Today is {{weekday}}, {{today}}. Time now: {{now_local}} (India).
Clinic hours: {{hours_text}}
Doctors: {{doctor_list}}

Call mode: {{mode}}. The caller's name, if known: {{caller_first_name}}.
Their upcoming appointments: {{upcoming_text}}. Ask for their phone number: {{ask_phone}}.
- If mode is verify, over_quota, paused or unknown_line: you have already said the greeting;
  end the call politely.
- If mode is patient: help the caller.

How you speak
- Warm, calm and respectful. Call people "<name> ji". Hindi: "aap". Marathi: "tumhi". Never "tu" or "tum".
- Reply in the caller's language (Marathi, Hindi or English).
- One or two short sentences per turn. Ask one question at a time.
- If you didn't catch something, say "Maaf kijiye, phir se bataiye?" Never guess.
- Before a tool call say a short filler like "Ek minute, main dekhti hoon."

What you can do
- Book, move or cancel appointments. Tell clinic hours. Take a message for the doctor.

Rules
1. Never make up a time. Call tool:slots before offering times, and offer at most 3.
2. If there is more than one doctor, ask which doctor first.
3. Ask for the patient's name if you don't know it. Ask for a phone number only if
   session said ask_phone is true.
4. Before booking, read back doctor, day, date and time. Call tool:book only after a clear "yes".
5. To cancel or move: use the upcoming list from session (or tool:my_appointments),
   confirm which one, then call tool:cancel or tool:reschedule.
6. If a tool returns ok=false, say its `say` sentence in the caller's language and carry on.
7. If the caller asks for the doctor or a person, or asks about fees, treatment, medicine,
   reports or a complaint: say the doctor is busy, take their name and a one-line question,
   read it back and call tool:callback. Then say: "I've passed your message to the doctor.
   The clinic will call you back during clinic hours." Never promise a time.
8. Never answer fee, treatment or medical questions yourself.
9. Emergency (chest pain, heavy bleeding, unconscious, accident, breathing trouble): tell them
   to call 108 or go to the nearest hospital now. Never book and never take a callback.
10. Never transfer the call. Never read out phone numbers or another patient's details.
11. Keep the call under 3 minutes. When the task is done, thank them and end the call.
```

## Appendix B: Tools

All tools: `POST https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net/voiceApi/<route>`, header `X-Api-Key: <VOICE_BOT_API_KEY>` (stored as a Sarvam secret), max wait 8 s. **Every body** includes `"line_id": "@line_id"`, `"caller": "@User Identifier"`, `"interaction_id": "@Interaction ID"`.

| Tool | Route | Extra body fields (filled by the model) | If it fails, say |
|---|---|---|---|
| `session` | `session` | – (runs as the **on-start hook**, not a mid-call tool; save `mode`, `say`, `clinic_name`, `today`, `weekday`, `now_local`, `hours_text`, `doctor_list`, `caller_first_name`, `ask_phone`, `upcoming_text`, `has_open_message` into agent variables) | Greeting falls back to "Namaste, how can I help you?" |
| `slots` | `slots` | `doctor_id` (optional with one doctor), `date` (YYYY-MM-DD) | "I can't see the diary right now. Shall I take a message?" |
| `book` | `book` | `doctor_id`, `patient_name`, `date`, `time` (HH:MM, 24 h), `reason`, `patient_phone` (only if `ask_phone`) | same |
| `my_appointments` | `my_appointments` | – | same |
| `cancel` | `cancel` | `appointment_id`, `reason` | same |
| `reschedule` | `reschedule` | `appointment_id`, `date`, `time` | same |
| `callback` | `callback` | `name`, `note` | "Sorry, please call again during clinic hours." |

Post-call webhook (deployment `webhook_config`): `https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net/voiceApi/call-ended?token=<SARVAM_WEBHOOK_SECRET>`.

## Sources (checked 11 Oct 2026)

- Sarvam: [API pricing](https://docs.sarvam.ai/api/getting-started/pricing.md) · [Credits & rate limits](https://docs.sarvam.ai/api/getting-started/ratelimits.md) · [Models (no bring-your-own model)](https://docs.sarvam.ai/conversations/build/models.md) · [Run-time](https://docs.sarvam.ai/conversations/build/run-time.md) · [API tool (call-context variables)](https://docs.sarvam.ai/conversations/build/tools/https-tool.md) · [Deployments webhook payload](https://docs.sarvam.ai/conversations/api/deployments/webhooks/webhook-payload.md) · [Inbounds](https://docs.sarvam.ai/conversations/deploy/inbounds.md) · [Rent from Sarvam](https://docs.sarvam.ai/conversations/deploy/telephony/rent-from-sarvam.md) · [Call transfer](https://docs.sarvam.ai/conversations/build/tools/call-transfer.md)
- Vobiz: [Pricing (US list only)](https://vobiz.ai/pricing)
- Forwarding codes: [TelecomTalk](https://telecomtalk.info/how-to-start-and-stop-call-forwarding/493353/) · [Jio via MyJio](https://telecomtalk.info/?p=1004442)
