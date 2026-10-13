# CruDoc AI Receptionist: Own-Server Plan (superseded)

> **Superseded on 11 Oct 2026 by `ai_receptionist_final_plan.md`**, which launches on Sarvam's hosted agent instead. Kept for the own-server design, which is the fallback for AI-first (see the final plan §9).

| | |
|---|---|
| **Date** | 11 October 2026 |
| **Status** | Draft for approval (Soham, Smit) |
| **Replaces** | `docs/ai_receptionist_plan.md` (9 Oct) and Smit's "AI answers first" plan (10 Oct). Both are kept for history only. |
| **Target** | 40 doctors live in `no_answer` mode by 31 Oct 2026 · AI-first beta with 5 clinics in early November |

---

## 1. Summary

**What we are building**

1. **AI receptionist on our own server.** Patients call the doctor's usual number. The AI books, moves or cancels appointments in CruDoc.
2. **Handover to reception** when the AI can't help: the receptionist hears who is calling and presses 1 to accept. If nobody accepts, the AI takes a message and the doctor gets a WhatsApp alert.
3. **WhatsApp reminders** the evening before each appointment, sent automatically.

**Decisions made**

| Topic | Decision |
|---|---|
| Who runs the AI | **Our own server** (Pipecat, the existing `voice-receptionist/`), from day one |
| Phone numbers | **Our own Vobiz account**, 3 shared AI numbers. One per clinic only if carriers hide the forwarding number (test T1) |
| Speech | Sarvam speech-to-text (Saaras) and text-to-speech (Bulbul v3) |
| LLM | Switchable by config. Candidates: **GLM 5.3 Flash** (through Sarvam) and **Gemini 3.6 Flash**. Run every test call on both; the one with fewer mistakes and faster replies becomes the main model, the other the backup |
| Modes per clinic | `no_answer` (default), `ai_first` (needs a separate reception number), `off` |
| Handover | Whisper + press 1 to accept. If nobody accepts: message, doctor alert, callback card |
| Call direction | Incoming only. The AI never calls patients |
| Rules and data | One booking API (`voiceApi`) and Firestore. The AI can ask; only `voiceApi` decides |
| Reminders | WhatsApp from one shared CruDoc number: 18:00 the day before, plus 08:00 catch-up |
| Providers | Every provider sits behind an adapter and is chosen in config (§6) |

**Still to decide**

| # | Question | Recommendation | By |
|---|---|---|---|
| O1 | What clinics pay | `no_answer`: 20 AI calls included. `ai_first`: 100 included. ₹10 per extra call (§7.4) | 22 Oct |
| O2 | 3 shared AI numbers or one per clinic | Shared, if the forwarding number arrives from Jio, Airtel and Vi (test T1) | 17 Oct |
| O3 | Go-live dates | 31 Oct for `no_answer` if Gate 2 passes, otherwise 7 Nov. AI-first after its own pilot (§10) | 17 Oct |
| O4 | Call recordings | Off. Keep transcripts 90 days | 22 Oct |

---

## 2. How it fits together

```
Patient dials the doctor's number
        │  (phone company forwards: when missed, or always)
        ▼
AI number on Vobiz (ours) ──── answer webhook ───▶ Voice server (our Docker image, Mumbai)
                                                    listens: Sarvam speech-to-text
                                                    thinks:  LLM (switchable)
                                                    speaks:  Sarvam text-to-speech
                                                          │ tool calls (HTTPS, X-Api-Key)
                                                          ▼
                                                    voiceApi (Cloud Functions, asia-south1)
                                                          │
                                                          ▼
                                                    Firestore ──▶ CruDoc app (live), WhatsApp alert to doctor

Voice server down? Vobiz fallback URL ──▶ small Cloud Function ──▶ ring reception (ai_first)
                                                                 or short message + callback card (no_answer)
```

- **Voice server = ears and mouth.** It handles audio and the conversation and stores nothing.
- **`voiceApi` = rules and data.** Hours, clashes, ownership and quotas are checked in one place. If the LLM gets something wrong, `voiceApi` refuses it.
- **Firestore = the only record.** Lines, appointments, calls, costs and callbacks live in our database, never only in a provider's dashboard.

This split is what makes switching providers quick (§6).

---

## 3. How each flow works (examples)

### 3.1 Doctor misses the call, AI books (`no_answer`)

Ramesh calls Dr. Sharma on 98220 11111 at 13:40. The doctor is with a patient.

1. The phone rings for about 20 s, then the phone company forwards the call to AI number A.
2. Our server calls `/session`. The forwarding number maps to Sharma Dental Clinic, and Ramesh is a known patient.
3. AI: *"Namaste Ramesh ji, Sharma Dental Clinic. How can I help?"* Ramesh: *"Tomorrow evening, tooth pain."*
4. AI calls `/slots` and gets 17:00, 17:30 and 18:30. Ramesh picks 17:30.
5. AI: *"Dr. Sharma, Saturday 10 October, 5:30 pm. Shall I book?"* Ramesh says yes, and the AI calls `/book`.
6. The appointment appears in CruDoc with an "AI" chip. Cost ≈ ₹3–4.

### 3.2 AI answers first (`ai_first`)

The same as 3.1, but the published number forwards **every** call, so the AI answers straight away and the doctor's phone doesn't ring.

### 3.3 Caller wants a person, reception accepts

Meera calls at 14:10 with a question about a bill. The AI must not handle bills.

1. AI: *"Let me connect you to reception."* It calls `/transfer-check`: reception is open, and the numbers are 98220 22222, then 98220 33333.
2. The receptionist's phone rings. They hear *"Call from Meera Joshi about a bill. Press 1 to accept."* and press 1.
3. Meera is connected and the AI drops off. A handover card appears in the app. Extra cost ≈ ₹3.

If the first number doesn't press 1 within 20 s, the second number rings.

### 3.4 Nobody at reception: AI takes a message, the doctor is alerted

Meera calls at 21:30 when reception is closed, or nobody presses 1 within about 45 s.

1. AI: *"Reception isn't available right now. Tell me your question and I'll pass it to Dr. Sharma."* It takes her name and a one-line question, then reads it back.
2. The AI calls `/callback`. A callback card appears in the app, and the doctor gets a WhatsApp: *"New callback request from Meera Joshi. Open CruDoc to see it."*
3. AI: *"I've passed your message to Dr. Sharma. The clinic will call you back during clinic hours."* It never promises a time.
4. The card stays on the dashboard until someone taps "Done". At 09:00 the doctor gets a reminder listing open callbacks.

### 3.5 Existing patient moves an appointment

Ramesh calls again: *"Can I come on Monday instead?"*

1. `/session` has already returned his upcoming appointment (Saturday 17:30).
2. The AI confirms which appointment and calls `/slots` for Monday. He picks 18:00, the AI reads it back, then calls `/reschedule`.
3. The Saturday slot is freed, and the WhatsApp reminder will go out for Monday.

A caller can only move or cancel their own appointments at this clinic.

### 3.6 Caller rings again before the clinic called back

`/session` shows an open callback for this caller. AI: *"Your message from this morning is already with Dr. Sharma. The clinic will call you back."* It can add to that note, and no duplicate card is created.

### 3.7 Emergency

The caller says *"chest pain"*. AI: *"Please call 108 or go to the nearest hospital now."* In `ai_first`, if reception is open, it offers to connect them. It never books and never offers a callback.

### 3.8 When something is off

| Situation | `no_answer` | `ai_first` |
|---|---|---|
| Clinic over its monthly quota | Short message (*"please call during clinic hours or send a WhatsApp"*), then end | Ring reception straight away |
| AI paused in the app | Same short message. The app shows the off code `##004#` | Ring reception. The app shows the off code `##21#` |
| Voice server down | Fallback: short message, plus a callback card with the caller's number | Fallback: ring reception |
| Someone dials the AI number directly | *"Please call your doctor's number"*, then end | Same |
| Call arrives forwarded from a reception number (loop) | n/a | One fixed sentence, end, and an alert fires |

### 3.9 WhatsApp reminder

At 18:00 the evening before: *"Reminder: Sharma Dental Clinic, tomorrow 5:30 pm with Dr. Sharma. To change it, call 98220 11111."* Anything booked after 18:00 gets an 08:00 reminder instead. STOP and START are handled automatically.

### 3.10 Doctor setup (once, about 5 minutes)

1. In the app: Settings → AI Receptionist. Choose the mode, enter the number patients call, and (for `ai_first`) the reception numbers.
2. Call the AI number once from that number. AI: *"Your number is verified for Sharma Dental Clinic."*
3. Tap "Turn on forwarding". The dialler opens with the code filled in, and the doctor presses call.
4. Test it: call from another phone and don't answer.

---

## 4. Phone setup

| Number | Who uses it | Rule |
|---|---|---|
| Published number (e.g. 98220 11111) | Patients. It's on cards, Google and WhatsApp reminders | Forwards to the AI number |
| AI number (e.g. 080-4567-0001) | Only the phone network | Patients never see it |
| Reception number (`ai_first` only) | Receptionist or doctor | Must differ from the published number, must not forward to the AI, ideally has no voicemail |

| Mode | Who answers | Code to dial on the published phone | Turn off |
|---|---|---|---|
| `no_answer` (default) | Doctor first. AI when busy, unanswered or switched off | `**004*<AI number>#` | `##004#` |
| `ai_first` | AI first, reception on request | `**21*<AI number>#` | `##21#` |
| `off` | Phone rings as before | none | — |

These are the standard GSM codes. Jio uses its own, so confirm on Jio, Airtel and Vi before giving any code to doctors.

**Doctors don't need a business connection.** Any normal mobile number works, prepaid or postpaid, on Jio, Airtel, Vi or BSNL, because call forwarding is a standard feature of every mobile plan. Only CruDoc's AI numbers are business numbers (our Vobiz account, our KYC). Each forwarded call counts as an outgoing call on the doctor's plan, which unlimited plans cover. On prepaid, forwarding stops if the plan lapses.

**Loop rules**

- Never transfer to the published number: it forwards straight back to the AI.
- The server refuses a reception number that equals any published, AI or other clinic's number.
- A call forwarded from a reception number is a loop: one sentence, end, and an alert fires.
- Pausing the AI in the app doesn't undo forwarding at the phone company. The app shows the off code.

---

## 5. What we build

### 5.1 Parts

| Part | Today | Change |
|---|---|---|
| Voice server (`voice-receptionist/`) | Built for Twilio: Pipecat, Sarvam speech, Gemini, one isolated session per call, transfer after 2 failed recognitions, plain transfer without whisper, its own SQLite tables | Add Vobiz. Add whisper + press-1 transfer with return to the AI. Call `voiceApi` instead of its own tables. Config switches for every provider. Deploy in Mumbai |
| `voiceApi` (Cloud Functions) | Only 3 legacy endpoints: `createAppointment`, `getAvailability`, `cancelAppointment` | New: one function with the routes in §5.3 |
| Fallback answer | — | Small Cloud Function that rings reception or plays a short message when the voice server is down |
| Server-side patient decryption | Missing (P0, §5.4) | `functions/src/crypto/patientCipher.ts` |
| Patient lookup by phone | Missing | `phoneIndex` trigger, one-time backfill, and an index |
| WhatsApp reminders | 18:00 sweep built, but it reads encrypted fields (P0) | Fix it, and add the 08:00 catch-up |
| Doctor alerts | — | WhatsApp template `callback_request_v1`, plus a 09:00 reminder of open callbacks |
| App | Module `ai_agentic_calling` and the `ai` permission exist; no screens | Settings, working hours, setup steps, usage, AI chip, callback and handover cards |
| Super Admin | "AI Receptionist" tab → `manageReceptionistLines` → the voice server's own tables | Read and write Firestore `voice_lines` instead |

### 5.2 Data (Firestore, written by functions only)

| Collection | Holds |
|---|---|
| `voice_numbers/{aiNumber}` | The 3 AI numbers, each with its `provider` (e.g. `vobiz`) |
| `voice_lines/{publishedNumber}` | Clinic, doctors, AI number, mode, reception numbers and hours, status |
| `users/{uid}.aiReceptionist` | Working hours, slot length and days off (written by the app) |
| `voice_calls/{callId}` | One per call: outcome, handover result, cost, and which phone, speech and LLM providers handled it |
| `voice_usage/{clinicId}_{YYYYMM}` | Monthly calls, minutes, cost and quota |
| `voice_callbacks/{id}` | Messages for the doctor: name, question, status, when the doctor was alerted |
| `slot_locks/{doctorId}_{start}` | Stops two calls booking the same slot |

Caller numbers are stored encrypted, with an HMAC index (`phoneIndex`) for lookups.

### 5.3 `voiceApi` routes

All routes are `POST` with an `X-Api-Key` header. Times are always clinic-local (`2026-10-10`, `17:30`). Every error includes a ready-made `say` sentence for the AI.

| Route | What it does |
|---|---|
| `/session` | Runs first on every call. Finds the clinic from the forwarding number and returns the clinic name, doctors, today's date, hours, the caller's name and upcoming appointments, any open callback, whether reception is open, and a `mode` |
| `/slots` | Up to 6 free times for a doctor and date, or the next free day |
| `/book` | Books in one transaction with a slot lock. A retried request returns the same booking |
| `/my-appointments`, `/cancel`, `/reschedule` | Act only on the caller's own appointments at this clinic |
| `/transfer-check`, `/transfer-result` | Whether reception is open, which numbers to ring and the whisper line; afterwards, the outcome |
| `/callback` | Saves the message and alerts the doctor |
| `/call-ended` | Records duration, cost and providers, and updates monthly usage exactly once per call |

`/session` modes: `patient` (normal), `verify` (setup test call), `passthrough` (`ai_first` but paused or over quota: ring reception), `over_quota` and `paused` (`no_answer`: short message), `unknown_line`, `loop_guard`.

### 5.4 Fix first (P0): still in the code on 11 Oct

1. **Reminders read encrypted names and phones without decrypting them** (`functions/src/whatsapp/reminders.ts:253-257`). About 26% of encrypted phones look like valid foreign numbers, so reminders would reach strangers abroad. Fix: decrypt on the server, accept Indian mobiles only, and reject `enc:` values.
2. **Patients created by the AI have no name and are stored in plain text.** Fix: write encrypted `firstName`, `lastName` and `phone`, plus `phoneIndex`.
3. **The AI can't recognise existing patients.** Fix: add `phoneIndex` to every patient.
4. **The legacy `cancelAppointment` cancels any ID it's given.** The new routes check ownership. Remove the legacy endpoints after the pilot.

---

## 6. Switching providers quickly

**Rules that keep any switch quick**

1. Only an adapter talks to a provider. All other code uses our own contracts (`voiceApi` and Firestore).
2. The provider and model are chosen in config, not in code.
3. Our data lives in Firestore. Each call records which providers handled it, so cost and quality can be compared after a switch.
4. The voice server is one Docker image that runs on any host.
5. A second, tested option is kept ready for the parts most likely to fail (LLM, speech).

| Part | Start with | Alternatives | How to switch | Time | Doctors affected? |
|---|---|---|---|---|---|
| LLM | GLM 5.3 Flash or Gemini 3.6 Flash (after tests) | Gemini 3.8 Flash, Gemini 3.5 Flash-Lite, Gemma 4, Sarvam-105B, OpenAI, Claude | Change `LLM_PROVIDER` / `LLM_MODEL`, then rerun the test calls | Under an hour, plus the test run | No |
| Speech-to-text | Sarvam Saaras | Google Chirp, or others that handle Marathi | Change `STT_PROVIDER` | ½ day, plus a Hindi/Marathi check | No |
| Text-to-speech | Sarvam Bulbul v3 | Google, Azure, ElevenLabs | Change `TTS_PROVIDER` and the voice list | ½ day, plus a listening check | No |
| Phone company | Vobiz | Plivo, Exotel, Twilio (all supported by Pipecat) | New adapter, and new numbers in `voice_numbers` | 1–3 days, plus doctors updating forwarding | **Yes**: each doctor re-dials one code from the app. Run both companies side by side until every line has moved |
| Whole AI runtime | Our server | A hosted agent (Sarvam, Vapi, Retell) | Point its tools at `voiceApi` and copy the instructions | 1–2 days | Only if the numbers change. Whisper and press-1 may be lost |
| Hosting | GCP Mumbai | Any cloud or VPS | Same Docker image and env vars | ½–1 day | No |
| WhatsApp | Meta Cloud API, direct | A BSP (Gupshup, Interakt, …) | Swap the sender in `functions/src/whatsapp/`, then move the number | 1–2 days, plus Meta moving the number | No |

**The phone company is the only slow switch.** Virtual numbers usually can't be moved between phone companies in India, so doctors have to re-enter forwarding. To keep that painless:

- The app always shows each doctor their current AI number, with a one-tap dialler button.
- Each line stores its own AI number, so lines can move one clinic at a time.
- The existing Twilio adapter stays working as a second, tested path.

**Prove it before launch:** in the pilot, run every test call on two LLMs by changing one setting (scenario 22).

---

## 7. Pricing

All prices are before 18% GST. ₹88 = US$1.

### 7.1 Unit prices

| Item | Price | Source |
|---|---|---|
| Sarvam hosted agent (Business plan) | ₹3.00 per started minute, including speech and LLM | Your Sarvam plan |
| Sarvam-rented number | ₹159/month (₹59 the first month) | Sarvam |
| Vobiz number | ₹500/month + ₹100 setup | Your Vobiz quote. The US list price is $1/month, so ask for India pricing |
| Vobiz incoming call | ₹0.20 per 30 s | The rate Sarvam passes on. Confirm the direct rate |
| Vobiz audio streaming to our server | ≈ ₹0.30/min | Vobiz US list price ($0.0034/min). Confirm for India |
| Vobiz leg to reception | ₹0.40 per 30 s | Sarvam's rate for forwarding to a phone. Confirm |
| Sarvam speech-to-text | ₹30/hour (₹0.50/min), billed per second | Sarvam pricing |
| Sarvam text-to-speech (Bulbul v3) | ₹30 per 10,000 characters | Sarvam pricing |
| GLM 5.3 Flash on Sarvam | ₹13.5 input / ₹2.5 cached / ₹45 output per 1M tokens. Always reasons first, and reasoning is billed as output | Your Sarvam screenshot. Not yet on Sarvam's public price pages, so confirm |
| Gemini 3.6 Flash (same price as 3.8 Flash) | $0.75 / $0.075 / $3.75 per 1M tokens until 31 Dec 2026, then $1.50 / $0.15 / $7.50 | Google pricing |
| Gemini 3.5 Flash-Lite (cheap backup) | $0.30 / $0.03 / $2.50 per 1M tokens | Google pricing |
| Server (e2-medium VM, Mumbai) | ≈ ₹2,600/month each | Third-party estimate (≈ $29) |
| WhatsApp utility message | ≈ ₹0.145 | 9 Oct plan |

### 7.2 Cost per call

| | 45 s call | 90 s call | Average |
|---|---|---|---|
| Sarvam hosted agent + rented number | ₹3.40 | ₹6.60 | ₹5.00 |
| Own server + GLM 5.3 Flash | ₹2.15–2.25 | ₹4.10–4.25 | ₹3.15–3.25 |
| Own server + Gemini 3.6 Flash (2026 price) | ₹2.35–2.80 | ₹4.55–5.45 | ₹3.45–4.15 |
| Own server + Gemini 3.6 Flash (2027 price) | ₹2.70–3.55 | ₹5.20–7.00 | ₹3.95–5.30 |
| Own server + Gemini 3.5 Flash-Lite | ₹2.20–2.35 | ₹4.20–4.55 | ₹3.20–3.45 |

- **What a 90 s call costs on our server:** line ₹0.60, Vobiz streaming ₹0.45, speech-to-text ₹0.75 and text-to-speech ₹2.10 come to ₹3.90 before the LLM. The LLM adds ₹0.20–0.40 with GLM 5.3 Flash, ₹0.65–1.55 with Gemini 3.6 Flash until 31 Dec 2026, and ₹1.30–3.10 after that.
- **Assumptions:**
  - Half the calls last about 45 s and half about 90 s. The AI speaks about 8 characters per second of call.
  - Each LLM request carries about 2,100–2,400 tokens (instructions, tools and the conversation so far), with 5 requests in a 45 s call and 9 in a 90 s call.
  - The lower end of each range assumes 70% of tokens are cached; the upper end assumes none.
  - GLM 5.3 Flash reasons for about 150 tokens per reply at low effort. Gemini's thinking is at its lowest; if it thinks 150 tokens per reply, a 90 s call costs ₹0.45 more (2026) or ₹0.90 more (2027).
- **Handing a call to reception adds about ₹3.00** (a 2-minute bridge plus ringing and the whisper). The AI stops while the two people talk.
- **Text-to-speech is the biggest cost on our server.** Short AI sentences save money and time.

### 7.3 Monthly cost, 40 clinics

Voice only, before GST.

| | Launch: `no_answer`, 20 calls per clinic (800 calls) | AI-first: 250 calls per clinic (10,000 calls, 30% handed to reception) |
|---|---|---|
| Sarvam hosted agent | ≈ ₹4,500 | ≈ ₹57,700 (and it can't do press-1) |
| **Own server + GLM 5.3 Flash** | **≈ ₹6,600** | **≈ ₹47,500** |
| Own server + Gemini 3.6 Flash (2026 price) | ≈ ₹7,100 | ≈ ₹53,500 |
| Own server + Gemini 3.6 Flash (2027 price) | ≈ ₹7,800 | ≈ ₹61,700 |

- **Vobiz streaming inside these:** ≈ ₹270 a month at launch and ≈ ₹3,400 at AI-first scale (about ₹0.30 per minute of AI talk; it stops while a call is handed to reception).
- **Fixed costs included above:**
  - Own server: 3 Vobiz numbers (₹1,500) plus one VM at launch (₹2,600), or two VMs for AI-first (₹5,200).
  - Sarvam: 3 numbers (₹477).
- **The Vobiz number price is the biggest unknown.** At the US list price, the own-server rows drop by about ₹1,200 a month.
- **Both options also pay about ₹2,700 a month** for WhatsApp reminders and Firebase.

**Per clinic per month, including reminders and GST**

| | Launch | AI-first |
|---|---|---|
| Sarvam hosted agent | ≈ ₹210 | ≈ ₹1,780 |
| **Own server + GLM 5.3 Flash** | **≈ ₹275** | **≈ ₹1,480** |
| Own server + Gemini 3.6 Flash (2026 price) | ≈ ₹290 | ≈ ₹1,660 |
| Own server + Gemini 3.6 Flash (2027 price) | ≈ ₹310 | ≈ ₹1,900 |

### 7.4 What clinics should pay (O1)

- Revenue today is ₹500–800 per clinic per month, or ₹20,000–32,000 for 40 clinics.
- **At launch, about ₹120 of the ₹275–310 per clinic is the server and numbers** shared across 40 clinics. That share falls to about ₹20 at 250 clinics.
- **An extra AI call costs us about ₹5 including GST** with GLM 5.3 Flash, or ₹5.50–6.50 with Gemini 3.6 Flash, so ₹10 per extra call leaves a margin.
- **AI-first at 250 calls:** 100 included plus 150 extra × ₹10 brings in ₹2,000–2,300 per clinic, against a cost of about ₹1,480–1,900.

---

## 8. What's better

| Question | Better choice | Why |
|---|---|---|
| Our server or Sarvam's hosted agent? | **Our server** (decided) | It's the only way to get whisper + press-1 today. It also gives a free choice of LLM, speech and phone company, our own fallbacks, and quick switching. With GLM 5.3 Flash it costs ≈ ₹2,200/month more at launch and saves ≈ ₹10,000/month at AI-first scale |
| Which LLM? | **GLM 5.3 Flash or Gemini 3.6 Flash.** Run every test call on both and pick by mistakes first, reply speed second, cost third. The other stays as backup | GLM 5.3 Flash is the cheapest (₹0.20–0.40 a call) but always reasons before replying, which adds delay. Gemini 3.6 Flash costs ₹0.65–1.55 a call and doubles in 2027, after which our server would cost more than Sarvam at AI-first scale. Gemini 3.7 Flash isn't on Google's price list |
| Sarvam-rented or own Vobiz numbers? | **Own Vobiz** | A Sarvam-rented number only works with Sarvam's hosted agent |
| 3 shared AI numbers or one per clinic? | **3 shared**, if test T1 passes | One per clinic costs 40 × the number price every month |
| Where do the booking rules live? | **`voiceApi` + Firestore** | One place for the rules. Any runtime can call it, so changing the runtime doesn't touch booking |
| Hosting | **One small VM in Mumbai** that restarts itself; a second before AI-first | Cheapest option that supports long-lived audio connections. Cloud Run with an always-on instance would cost roughly double (estimate) |
| Rollout | **40 doctors in `no_answer`**, then 5 clinics AI-first | AI-first costs more and turns the AI into a single point of failure |
| Reminder sender | **Shared CruDoc number now**, each clinic's own number later | Already built. Per-clinic numbers need weeks of Meta approvals |

**Bottom line:** we choose our own server for control (press-1, any LLM, our own fallbacks, easy switching), not to save money. It costs a little more at launch and saves money at AI-first scale, but only with a cheap LLM (GLM 5.3 Flash, or Gemini 3.6 Flash at its 2026 price).

---

## 9. Things to note

**Phones and carriers**
- In `ai_first`, the published phone never rings. Use a clinic-only number, not the doctor's personal mobile.
- The reception number must differ from the published number, must not forward to the AI, and ideally has no voicemail. A landline is ideal.
- Jio uses different forwarding codes. Confirm them on Jio, Airtel and Vi before giving them to doctors.
- On a transferred call, the receptionist will probably see the AI number, not the patient's. The whisper says who is calling.
- 3 shared AI numbers only work if the forwarding number reaches Vobiz from all 3 carriers (T1). If it doesn't, we need one AI number per clinic.
- Forwarded calls use the doctor's plan minutes. That's fine on unlimited plans.

**Patients and privacy**
- The AI gives no medical or fee answers, promises no call-back time, and says 108 first in an emergency.
- WhatsApp alerts to doctors carry no health details, only "open CruDoc". Doctors opt in to these alerts with a checkbox in AI Receptionist settings.
- Patient fields stay encrypted. Lookups use `phoneIndex`.
- Recordings are off, and transcripts are kept 90 days (O4).
- The privacy policy must name Vobiz, Sarvam, Google and Meta as processors. Gemini may process data outside India, while Sarvam and Vobiz are Indian. If that becomes a problem, check whether Vertex AI offers the chosen Gemini model in an Indian region.
- Calls are incoming only, and callbacks are made by clinic staff, not the AI. That keeps us clear of TRAI telemarketing rules.
- Use GLM 5.3 Flash through Sarvam, not through Z.ai's own API in China, so patient conversations stay with an Indian provider. Confirm with Sarvam where the model runs.

**Reliability**
- In `ai_first`, an outage hits every call. The fallback answer, a second VM and alerts are required before the AI-first beta.
- Keep the backup LLM configured and tested, so a switch takes minutes.
- Gemini 3.7 Flash isn't on Google's price list (only 3.8 and 3.6 Flash are), and 3.7/3.8 Flash returned "overloaded" errors in our 30 Sep tests. Use 3.6 Flash. The voice server's default, `gemini-3.5-flash` (`voice-receptionist/app/core/config.py`), isn't on the list either, so change it.
- GLM 5.3 Flash always reasons before answering. Set its reasoning effort to `low` (other values fall back to the slowest setting) and measure reply time in the pilot.
- Set Gemini's thinking to the lowest level. Thinking adds delay and is billed as output.
- Sarvam limits simultaneous connections per account. Ask for the limit, and load test before AI-first.

**Cost**
- The AI part of a call is capped at 4 minutes. A call already handed to reception is never cut off.
- Each clinic has a quota, with an in-app banner at 80% and 100%.
- Every month, compare `voice_usage` with the Vobiz, Sarvam and Google bills.

**WhatsApp and code**
- The P0 reminder bug is still in the code (checked 11 Oct). Don't send live WhatsApp reminders before V1–V2.
- Without Meta Business Verification, Meta allows about 250 reminders a day across all clinics, but 40 doctors need 400–600. After verification the limit is 2,000. Start Y3 now.
- Reminders don't depend on the voice work. They can go live once V1–V2 and Meta verification are done.

---

## 10. Tasks and timeline

Owner: **You** = Soham, **C** = Claude. Size: S ≤ ½ day, M ≈ 1 day, L ≈ 2–3 days.

### Week 1 (11–17 Oct): accounts, carrier test, P0, start the backend

| ID | Task | Owner | Size | Done when |
|---|---|---|---|---|
| Y1 | Vobiz account and KYC. 1 test number now, 3 AI numbers after T1 | You | S | Numbers visible in Vobiz |
| T1 | Carrier test: forward calls from Jio, Airtel and Vi to the test number and log exactly what Vobiz sends (caller number, forwarding number); confirm the codes | You + C | S | Results table; O2 decided |
| Y2 | Send the §12 questions to Vobiz and Sarvam | You | S | Written answers |
| Y3 | Meta Business Verification, and the new template `callback_request_v1` | You | S + wait | Verified; template approved |
| Y4 | Secrets: `PATIENT_KEK_PEPPER`, Vobiz auth, Sarvam key, Google key | You | S | Set |
| V1–V4 | P0 fixes: `patientCipher`, reminder fix, `phoneIndex` + backfill, 08:00 catch-up | C | M, S, M, S | Dry run shows real names and no foreign numbers |
| V5–V7 | `voiceApi`: skeleton, `/session`, `/slots`, `/book` | C | M each | Two simultaneous bookings: exactly one wins |
| R1 | Vobiz adapter in the voice server: answer XML, audio stream, hang-up | C | L | The test number is answered by our server |

### Week 2 (18–24 Oct): finish backend and app, pilot on your phone

| ID | Task | Owner | Size | Done when |
|---|---|---|---|---|
| V8 | `/my-appointments`, `/cancel`, `/reschedule` with ownership checks | C | M | Can't touch another caller's appointment |
| V9 | `/callback`, doctor WhatsApp, 09:00 reminder, repeat-caller check | C | M | Card and alert appear |
| V11 | `/call-ended`: cost, providers, usage | C | S | A retried webhook isn't counted twice |
| V12 | Line setup callables: register, update, remove; reception-number checks; loop rules | C | M | A line can't belong to two clinics |
| R2 | Voice server calls `voiceApi`, its own tables are dropped, tool names match the routes | C | M | Booking from a call lands in Firestore |
| R4 | Config switches for LLM, speech-to-text and text-to-speech; GLM 5.3 Flash (Sarvam) and Gemini 3.6 Flash both wired | C | S | Model changed with one setting |
| R5 | Instructions with tone and guardrails (Appendix A); 4-minute AI cap | C | S | Reviewed by you |
| R6 | Deploy: Docker on a Mumbai VM that restarts itself, fallback answer function, health checks | C | M | Stopping the server triggers the fallback |
| A1–A4 | App: settings, working hours, setup steps with the dialler button, usage and banners | C | M, M, S, S | A doctor sets up without help |
| P1 | Pilot on your phone in `no_answer`: scenarios 1–7, 12–19, 21–22 | You + C | M | Gate 1 |

### Week 3 (25–31 Oct): beta and launch in `no_answer`

| ID | Task | Owner | Size | Done when |
|---|---|---|---|---|
| A5 | AI chip, callback cards and dashboard badge | C | S | Visible on web and mobile |
| L1 | Alerts: `voiceApi` errors, voice server down, fallback used, daily cost | C | S | Test alert received |
| L2 | Privacy policy update, 2-minute doctor guide, outage message | You | S | Published |
| B1 | 5-doctor beta in `no_answer`, about 4 days | You + C | — | Gate 2 |
| B2 | 40 doctors live in `no_answer` | You | — | 31 Oct if Gate 2 passes, otherwise 7 Nov |

### Early November: AI-first

| ID | Task | Owner | Size | Done when |
|---|---|---|---|---|
| V10 | `/transfer-check`, `/transfer-result`, handover record | C | M | Handover appears with reason and result |
| R3 | Transfer: whisper + press 1, second number, return to the AI with a summary | C | L | Scenarios 8–11 pass |
| A6 | Mode selector, reception numbers and hours, handover cards | C | M | Handover card shows within seconds |
| R7 | Second VM; load test with 15 calls at once, 5 handed over | C | S | Peak capacity known |
| P2 | Pilot in `ai_first`: scenarios 1–20 | You + C | M | Gate 1 for AI-first |
| B3 | 5 clinics in AI-first for a week | You + C | — | Gate 2 for AI-first |
| L3 | Super Admin tab reads Firestore; remove the 3 legacy endpoints | C | M | Legacy endpoints no longer deployed |

**Timeline risk:** about 20 days of coding are needed before the `no_answer` launch. If week 2 slips, launch moves to 7 Nov. The WhatsApp reminders don't have to wait for it.

---

## 11. Testing

| # | Scenario | Expected |
|---|---|---|
| 1 | New caller books | Appointment in the app with a name; patient fields encrypted; "AI" chip |
| 2 | Existing patient calls | Greeted by first name; no duplicate patient |
| 3 | Slot already taken in the app | Other times offered; never a double booking |
| 4 | Two callers book the same slot at the same moment | One succeeds; the other is offered a new time |
| 5 | Cancel | Cancelled in the app; slot free again |
| 6 | Reschedule | Time moves; the reminder goes out for the new date |
| 7 | Ask for a closed day | AI says closed and offers the next open day |
| 8 | Ask for a person (`ai_first`, reception open) | Whisper, press 1, connected; handover card |
| 9 | Reception rings out or goes to voicemail | Back to the AI within about 45 s; message taken; doctor alerted |
| 10 | Ask for a person outside reception hours | No transfer attempt; message taken |
| 11 | Two reception numbers, the first switched off | The second rings and accepts |
| 12 | "Chest pain, emergency" | 108 first; transfer offered only in `ai_first` with reception open; no booking |
| 13 | Speak Marathi, then Hindi | AI follows the language |
| 14 | Ask about fees or medicine | Not answered; handed over or message taken |
| 15 | Two unclear answers in a row | Handed over, or a callback created |
| 16 | Quota set to 0 | `no_answer`: short message, ends in under a minute. `ai_first`: rings reception |
| 17 | AI paused in the app while forwarding is on | `no_answer`: short message. `ai_first`: rings reception |
| 18 | Voice server stopped | Fallback works: message + callback card, or reception rings |
| 19 | AI number dialled directly | "Please call your doctor's number" |
| 20 | Reception number equal to the published number, or a call forwarded from a reception number | Setup refused; loop sentence and alert |
| 21 | Caller with an open message rings again | Told it's with the doctor; no duplicate card |
| 22 | LLM switched in config (GLM 5.3 Flash ↔ Gemini 3.6 Flash) | Scenarios 1–7 still pass |

**Gates**

- **Gate 1 (pilot on your phone):** all listed scenarios pass; the AI answers within about 1.5 s; tool calls take under 2 s; in `ai_first`, a transfer connects within 25 s; the real cost per call is measured.
- **Gate 2 (beta):** zero wrong bookings; under 5% of calls hit a tool error; no caller is left stranded; the Vobiz, Sarvam and Google bills match `voice_usage` within 10%; doctors and receptionists are happy.
- **Gate 3 (everyone):** Meta verified, load test passed, alerts on, pricing decided.

**When something goes wrong**

| Situation | What to do |
|---|---|
| Voice server down | The fallback answers automatically. The alert fires; restart or roll back |
| LLM errors or slow replies | Switch `LLM_MODEL` to the backup and redeploy (minutes) |
| Sarvam speech down | Switch to the backup speech provider if one is set up; otherwise treat it as "voice server down" |
| Vobiz down | Send doctors the "turn off forwarding" message (`##004#` or `##21#`), and turn it back on later |
| "The AI booked a wrong time" | Check `voice_calls/{id}` and the transcript; fix the rule in `voiceApi` or the instructions |
| Clinic over quota | `no_answer`: short message. `ai_first`: straight to reception. Offer a top-up |

---

## 12. Open questions

| Ask | Question | Needed for |
|---|---|---|
| Vobiz | India prices: number, incoming per minute, outgoing per minute, streaming, billing pulse | §7, O2 |
| Vobiz | Does the answer webhook include the forwarding number (Plivo-style `ForwardedFrom`)? Verify with T1 | O2 |
| Vobiz | Does `<Dial>` support a whisper with press-to-accept and a URL called when the dial ends (Plivo-style `confirmSound`, `confirmKey`, `action`)? | R3 |
| Vobiz | Fallback answer URL: when is it used, and what happens if our audio stream drops mid-call? | R6 |
| Vobiz | Which caller ID does the receptionist see? Simultaneous-call limit? | R3, R7 |
| Sarvam | Simultaneous streaming limits for speech-to-text and text-to-speech. Is GLM 5.3 Flash available to us (model ID, price, reasoning-effort setting, tool calling), and where is it hosted? | R4, R7 |
| Google | Where Gemini API data is processed and how long it's kept | L2 |
| You | Clinic pricing (O1), go-live dates (O3), recordings and retention (O4) | §1 |

---

## Appendix A: AI instructions (tone and guardrails)

Values in `{{ }}` come from `/session`.

```
You are the phone receptionist for {{clinic_name}}. You are an AI; say so if asked.
Today is {{weekday}}, {{today}}. Time now: {{now_local}} (India).
Clinic hours: {{hours_text}}. Reception available now: {{reception_open}}.
Doctors: {{doctor_list}}

How you speak
- Warm, calm and respectful. Call people "<name> ji". Hindi: "aap". Marathi: "tumhi". Never "tu" or "tum".
- Reply in the caller's language (Marathi, Hindi or English).
- One or two short sentences per turn. Ask one question at a time.
- If you didn't catch something, say "Maaf kijiye, phir se bataiye?" Never guess.
- If the caller is upset, apologise once, then help.

What you can do
- Book, move or cancel appointments. Tell clinic hours. Take a message for the doctor.
- Connect the caller to reception, only when reception is available.

Rules
1. Never make up a time. Call slots before offering times, and offer at most 3.
2. If there is more than one doctor, ask which doctor first.
3. Ask for the patient's name if you don't know it. Never ask for their phone number.
4. Before booking, read back doctor, day, date and time. Book only after a clear "yes".
5. To cancel or move: call my_appointments, confirm which one, then act.
6. If a tool returns ok=false, say its `say` sentence in the caller's language and carry on.
7. If the caller asks for the doctor, reception or a person, or the topic is fees, treatment,
   medical advice, reports or a complaint: if reception is available, call transfer_check and
   connect them. Otherwise take a message (name and a one-line question), read it back and call callback.
8. After taking a message say: "I've passed your message to Dr. <name>. The clinic will call you
   back during clinic hours." Never promise a time.
9. Never answer fee, treatment or medical questions yourself, even when reception is unavailable.
10. Emergency (chest pain, heavy bleeding, unconscious, accident, breathing trouble): tell them to
    call 108 or go to the nearest hospital now. If reception is available, offer to connect them.
    Never book and never offer a callback.
11. If you fail to understand the caller twice, or a tool fails twice: connect to reception if
    available, otherwise create a callback so the clinic calls them back.
12. Never share another patient's details or read out phone numbers. Stay on clinic topics and
    politely bring the caller back.
13. Keep the call under 3 minutes. When the task is done, thank them and end the call.
```

---

## Sources

- Sarvam: [API pricing](https://docs.sarvam.ai/api/pricing.md) · [Models (no bring-your-own model in the hosted agent)](https://docs.sarvam.ai/conversations/build/models.md) · [Rent from Sarvam](https://docs.sarvam.ai/conversations/deploy/telephony/rent-from-sarvam.md) · [Bring your own Vobiz](https://docs.sarvam.ai/conversations/deploy/telephony/vobiz.md) · [Call transfer](https://docs.sarvam.ai/conversations/build/tools/call-transfer.md) · [Run-time (key presses "planned")](https://docs.sarvam.ai/conversations/build/run-time.md) · [Migrating chat from Gemini (OpenAI-style API)](https://docs.sarvam.ai/api/migrations/from-gemini/chat-completion)
- Vobiz: [Pricing (US list)](https://vobiz.ai/pricing) · [Audio streams (third-party skill page)](https://www.skills.sh/vobiz-ai/agent-skills/vobiz-audio-streams) · [Vobiz app with fallback answer URL (Dograh guide)](https://docs.dograh.com/integrations/telephony/vobiz)
- Plivo, used as a reference for Vobiz-style XML: [Dial XML: `confirmSound`, `confirmKey`, `action`](https://www.plivo.com/docs/voice/xml/routing)
- Pipecat: [Serializers](https://docs.pipecat.ai/server/services/serializers/introduction) · [Sarvam LLM service](https://docs.pipecat.ai/server/services/llm/sarvam)
- Google: [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) (3.8 and 3.6 Flash, 3.5 Flash-Lite)
- GLM 5.3 Flash reasoning settings (third-party guide): [Qubrid developer guide](https://www.qubrid.com/blog-news/glm-53-flash-api-the-complete-developer-guide)
- Server estimate: [e2-medium in asia-south1](https://cloudprice.net/gcp/regions/asia-south1)
- Code: `voice-receptionist/README.md` (model timings, Twilio flow, Super Admin wiring) · `functions/src/whatsapp/reminders.ts` · `functions/src/appointments.ts`
