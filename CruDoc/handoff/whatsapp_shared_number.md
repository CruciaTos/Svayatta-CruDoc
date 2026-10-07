# WhatsApp reminders from one shared CruDoc number

Last updated: 2026-10-05

## 1. Decision

CruDoc sends appointment reminders to patients from **one WhatsApp number owned by CruDoc**, on
behalf of every clinic. The message names the clinic and doctor.

This replaces the per-clinic Tech Provider plan (`whatsapp-meta-status.md`) for launch. That plan
needs Meta Business Verification, Tech Provider registration and App Review for Advanced Access
before any clinic can connect — weeks of lead time, plus 10–15 minutes of Facebook/Meta setup per
doctor. The shared number needs none of that, because CruDoc only ever touches its own WhatsApp
account.

**Goal: the doctor presses no buttons.** Reminders are on by default. There is only an off switch.

### Defaults assumed (change here if decided otherwise)

| Decision | Default |
|---|---|
| Which clinics get reminders | Clinics with the `omnichannel_messaging` module (₹1999/mo) |
| Which messages | One day-before reminder per appointment. No booking confirmation. |
| When it sends | 18:00 IST the evening before the appointment |
| Who pays Meta | CruDoc, absorbed into the module price |
| Marketing / campaigns on this number | **Not allowed** — reminders only |

---

## 2. How it works

```
18:00 IST  Cloud Scheduler ─▶ sendDayBeforeReminders (function)
                                │
                                ├─ find tomorrow's scheduled appointments
                                ├─ skip: clinic switched off / no module / patient opted out / bad phone
                                └─ send template ─▶ Meta Cloud API ─▶ patient's WhatsApp
                                                                         │
whatsappWebhook ◀─ delivered / read / failed / patient reply ◀───────────┘
   ├─ status   → update whatsapp_notification_logs
   ├─ "STOP"   → add phone to whatsapp_optouts, confirm once
   └─ anything else → auto-reply "this number only sends reminders, call {clinic} on {phone}"
```

### What each person sees

- **Doctor:** nothing. Settings has one switch, "WhatsApp appointment reminders", on by default.
- **Reception:** books appointments exactly as today. The patient form shows a line of text
  (not a checkbox): *"Appointment reminders will be sent on WhatsApp. Reply STOP to opt out."*
- **Patient:** one message the evening before, from the CruDoc number:

  > Hi Rahul, this is a reminder of your appointment at **Smile Dental Clinic** with
  > **Dr. Mehta** on **Tue, 6 Oct** at **11:00 AM**. To reschedule, please call the clinic on
  > **98XXXXXXXX**. Reply STOP to stop these reminders.

- **CruDoc:** one-time Meta setup (section 3), the Meta bill, and watching the number's quality
  rating (section 7).

---

## 3. Meta setup — one time, done by CruDoc

No App Review, no Tech Provider registration, no Embedded Signup. CruDoc's app only needs
Standard Access, because the WhatsApp account belongs to CruDoc's own business.

| # | Step | Where | Done |
|---|---|---|---|
| 1 | Meta Business Portfolio for Svayatta / CruDoc | business.facebook.com | ☐ |
| 2 | App with the WhatsApp product added | developers.facebook.com | ☐ |
| 3 | WhatsApp Business Account (WABA) under the portfolio | WhatsApp Manager | ☐ |
| 4 | A **new SIM / number** not registered on any WhatsApp app, added and OTP-verified | WhatsApp Manager → Phone numbers | ☐ |
| 5 | Display name `CruDoc` (must match the business owning the WABA) — wait for approval | same | ☐ |
| 6 | Payment method on the WABA | WhatsApp Manager → Payment settings | ☐ |
| 7 | System User (admin) in the portfolio, assigned the app and the WABA with full control; generate a **permanent** token with `whatsapp_business_messaging` + `whatsapp_business_management` | Business Settings → Users → System users | ☐ |
| 8 | Template `appointment_reminder_v1` submitted (section 4) and **Approved** | WhatsApp Manager → Message templates | ☐ |
| 9 | Webhook: callback URL + verify token, subscribed to `messages` | App → WhatsApp → Configuration | ☐ |
| 10 | Start **Business Verification** (not blocking — lifts sending limits later) | Security Center | ☐ |

Do not use the temporary 24-hour token from the API Setup page — it expires and every send fails
the next day. Use the System User token from step 7.

Record here once done:

| Value | |
|---|---|
| Business ID | |
| App ID | |
| WABA ID | |
| Phone number ID | |
| Display name status | |
| Business Verification status | |

### Secrets and config

```bash
firebase functions:secrets:set WHATSAPP_ACCESS_TOKEN        # System User token from step 7
firebase functions:secrets:set WHATSAPP_WEBHOOK_VERIFY_TOKEN
firebase functions:secrets:set WHATSAPP_WEBHOOK_APP_SECRET  # App → Settings → Basic → App secret
```

`functions/.env` (not secret):

```
WHATSAPP_MODE=live
WHATSAPP_PHONE_NUMBER_ID=<from step 4>
WHATSAPP_TEMPLATE_NAME=appointment_reminder_v1
```

`functions/.env.example` currently has `WHATSAPP_PHONE_NUMBER_ID=1260194177180019` committed —
confirm it is CruDoc's own number or replace it.

---

## 4. Template

Category **Utility**, language **English (en)**. Hindi / Marathi versions later, as separate
templates.

Name: `appointment_reminder_v1`

```
Hi {{1}}, this is a reminder of your appointment at {{2}} with {{3}} on {{4}} at {{5}}.
To reschedule, please call the clinic on {{6}}.
Reply STOP to stop these reminders.
```

| Param | Value | Sample for Meta review |
|---|---|---|
| {{1}} | patient first name | Rahul |
| {{2}} | clinic name | Smile Dental Clinic |
| {{3}} | doctor name | Dr. Mehta |
| {{4}} | date, `EEE, d MMM`, IST | Tue, 6 Oct |
| {{5}} | time, `h:mm a`, IST | 11:00 AM |
| {{6}} | clinic phone (`clinicPhone` on the doctor profile) | 98XXXXXXXX |

Rules that keep it Utility (Meta re-categorises promotional-sounding templates as Marketing,
which costs more and needs separate opt-in):

- No offers, discounts, "visit us again", or links to anything but the clinic.
- **No medical information** — no diagnosis, treatment, procedure or medicine names. A reminder
  saying "your root canal" would disclose health data to anyone who sees the phone.

The current code sends 6 params in a different order (patient, doctor, clinic, date, time,
consultation type) to a template named `appointment_confirmation`. Update the payload to match
this table.

---

## 5. Code changes

### Must fix before going live (bugs in the current code)

| # | Problem | Where | Fix |
|---|---|---|---|
| 1 | **Anyone on the internet can send messages from CruDoc's number.** `sendWhatsAppAppointmentConfirmation` is a public `onRequest` with no auth; it takes any phone and doctorId from the request body. | `functions/src/whatsapp-endpoints.ts:25` | Delete it (no booking confirmation in this plan), or turn it into `onCall` that checks `request.auth.uid == doctorId` and that the appointment belongs to that doctor. Remove the raw URL call in `lib/features/messaging/data/repo/whatsapp_repository.dart:385`. |
| 2 | **Reminder trigger is also public** and is set up for a 10-minute window, run every minute. | `whatsapp-endpoints.ts:75`, `whatsapp.ts:401` | Replace with `onSchedule({schedule: "0 18 * * *", timeZone: "Asia/Kolkata"})` that selects tomorrow's appointments (IST day boundaries). |
| 3 | **Times are formatted in UTC.** `toLocaleDateString/TimeString` without `timeZone` runs in the function's UTC clock, so an 11:00 AM IST appointment says 5:30 AM. | `whatsapp.ts` dispatch step 5 | Pass `timeZone: "Asia/Kolkata"`, locale `en-IN`. |
| 4 | `reminderSent: true` is written even when the send failed, so failures are never retried. | `whatsapp.ts` reminder loop | Write `reminderStatus` from the result; retry `failed` once on the next run; never retry `skipped`. |
| 5 | Campaign callable sends the appointment template with today's date as a fake appointment. | `whatsapp-endpoints.ts:231` | Disable on the shared number. Campaigns are marketing and need the clinic's own number later. |
| 6 | Endpoints are not exported. | `functions/src/index.ts:16` | Export the reminder job and webhook only. |
| 7 | Graph API version hard-coded `v20.0`. | `whatsapp.ts:132` | Read `WHATSAPP_GRAPH_VERSION` (default `v23.0`). |

### New behaviour

**Eligibility** — send only when all are true:

1. The appointment's `status == "scheduled"` and it starts tomorrow (IST).
2. The doctor has the `omnichannel_messaging` module.
3. The doctor's `whatsappRemindersEnabled != false` (missing = on).
4. The patient phone normalises to a valid Indian mobile.
5. The phone is not in `whatsapp_optouts`.

Log every skip with its reason in `whatsapp_notification_logs`, as the code already does for bad
phones.

**Webhook — inbound messages** (`value.messages`, currently ignored):

- Text equal to `STOP`, `UNSUBSCRIBE`, `CANCEL` or `BAND` (case-insensitive, trimmed) →
  write `whatsapp_optouts/{e164Phone}` with `{optedOutAt, source: "reply"}`; send one free-form
  confirmation ("You won't get reminders from CruDoc any more. Reply START to turn them back on.").
  `START` deletes the opt-out.
- Anything else → one free-form auto-reply per 24 h per phone: "This number only sends
  appointment reminders. Please call {clinic} on {clinicPhone}." Find the clinic from the most
  recent `whatsapp_notification_logs` entry for that phone.

Free-form replies are allowed and free inside the 24-hour window the patient's message opens.

Opt-out is **global**, not per clinic: a reply carries no clinic context, and a patient who says
STOP to this number means it.

**Flutter:**

- Settings: one switch "WhatsApp appointment reminders", bound to `whatsappRemindersEnabled`,
  default on. Show it only to doctors with the module.
- Patient add/edit form: the static notice line from section 2, under the phone field. No
  checkbox.
- Optional, later: a small "Reminder sent / delivered / failed" chip on the appointment, read
  from `whatsapp_notification_logs`.

**Firestore rules:** `whatsapp_optouts` and `whatsapp_notification_logs` are written only by
functions. Doctors may read logs where `doctorId == request.auth.uid`.

---

## 6. Consent (India)

Meta requires opt-in before a business messages someone; DPDP requires consent that is informed
and given by a clear action, and pre-ticked boxes are unlikely to count.

What this plan relies on:

1. The patient gives their phone number to the clinic for appointments, and the form tells them,
   in the same place, that reminders come on WhatsApp.
2. Every message says how to stop, and STOP works instantly.
3. CruDoc's privacy policy states CruDoc sends appointment reminders on the clinic's behalf as
   its processor, from the CruDoc WhatsApp number.
4. No health information in messages.

**Have someone with legal knowledge confirm points 1 and 3 before scaling beyond pilot clinics.**

---

## 7. Limits, cost and risk

**Sending limit.** A new, unverified business starts with a low cap on business-initiated
messages to unique users per rolling 24 h (about 250 at the time of writing — check Meta's current
figure). That is roughly 10 busy clinics. Business Verification plus good quality ratings raise
it. Start verification on day one.

**Cost.** Meta's India utility rate has been around ₹0.11–0.15 per delivered template — re-check
the current rate card. A clinic with 20 appointments a day × 26 days ≈ 520 messages ≈ **₹60–80 a
month**, well inside the ₹1999 module.

**Shared quality rating — the main risk.** Every clinic shares one number. If patients block or
report it, Meta lowers the quality rating and can cap or pause the number **for all clinics at
once**. Mitigations:

- Reminders only, one per appointment, never marketing.
- STOP honoured instantly.
- Watch the quality rating in WhatsApp Manager weekly; alert on Medium.
- Keep a second verified number ready as a fallback.

---

## 8. Upgrade path (later, optional)

When a clinic wants messages from its own name and number, or wants campaigns, onboard it through
a WhatsApp BSP partner program or the full Tech Provider plan in `whatsapp-meta-status.md`. The
sender becomes per-clinic; templates and eligibility logic carry over. Offer it as a paid upgrade
done on a call with the clinic, so the default stays zero-effort.

---

## 9. Done when

- [ ] Section 3 steps 1–9 done; template `appointment_reminder_v1` Approved
- [ ] Section 5 bugs 1–7 fixed
- [ ] Eligibility, STOP/START and auto-reply implemented
- [ ] Settings switch and patient-form notice shipped
- [ ] Test: a real appointment tomorrow on a pilot clinic gets the reminder at 18:00 IST with the
      correct IST time; STOP from that phone blocks the next one
- [ ] Webhook shows green; delivered/read statuses land in `whatsapp_notification_logs`
- [ ] Business Verification submitted
- [ ] Privacy policy updated; consent wording reviewed
