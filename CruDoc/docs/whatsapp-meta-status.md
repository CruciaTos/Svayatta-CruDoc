# WhatsApp / Meta setup status

The single source of truth for what exists on Meta's side. Every phase of the WhatsApp build
depends on this, so keep it current — if something here is stale, someone will waste a day.

**Why this matters:** Business Verification and App Review take days to weeks. Nothing
clinic-facing can ship until they clear, so start them before writing code.

Last updated: _(date)_ · Updated by: _(name)_

---

## 1. Audit — fill this in first

Takes about 30 minutes. Every row needs an answer before Phase 3 (onboarding) can be tested
against a real clinic.

### Meta Business Portfolio — business.facebook.com

| Item | Where to look | Value |
|---|---|---|
| Business Portfolio exists | Business Settings → Business Info | ☐ yes ☐ no |
| Legal business name | same | |
| Business ID | same | |
| **Business Verification status** | Security Center | ☐ Verified ☐ Pending ☐ Not started ☐ Failed |
| If failed, the reason | same | |
| WhatsApp Business Platform Terms accepted | Business Settings → Requests / Terms | ☐ yes ☐ no |

### Meta app — developers.facebook.com

| Item | Where to look | Value |
|---|---|---|
| App exists | App Dashboard | ☐ yes ☐ no |
| App ID | Settings → Basic | |
| **App type** | Settings → Basic | ☐ Business ☐ other → **blocker, see note** |
| App mode | top bar | ☐ Development ☐ Live |
| App secret set as a Firebase secret | — | ☐ yes ☐ no |
| WhatsApp product added | Products | ☐ yes ☐ no |
| Facebook Login for Business added | Products | ☐ yes ☐ no |
| Privacy Policy URL | Settings → Basic | |
| Terms of Service URL | Settings → Basic | |
| Data Deletion URL | Settings → Basic | |
| App icon 1024×1024 | Settings → Basic | ☐ yes ☐ no |
| Data Use Checkup | App Dashboard | ☐ complete ☐ due |

> **App type is not changeable.** If the existing app is not type Business, a new app has to be
> created and everything below re-done against it. Check this first — discovering it late is
> expensive.

### Permissions — App Review → Permissions and Features

All three need **Advanced Access**. Standard Access only works for people with a role on the app,
so a real clinic cannot connect until these are Advanced.

| Permission | Needed for | Current level |
|---|---|---|
| `whatsapp_business_messaging` | sending messages, uploading media | ☐ Standard ☐ Advanced |
| `whatsapp_business_management` | creating templates, registering numbers, subscribing webhooks | ☐ Standard ☐ Advanced |
| `business_management` | reading the clinic's business assets during onboarding | ☐ Standard ☐ Advanced |

### Test WABA — WhatsApp → API Setup

Available from day one, no verification needed. Phases 1, 2, 4 and 8 are all testable on this.

| Item | Value |
|---|---|
| Test WABA ID | |
| Test phone number ID | _(the repo has `1260194177180019` committed in `functions/.env.example` — confirm it belongs to an app you control, or replace it)_ |
| Test recipient numbers added | _(up to 5, each verified by WhatsApp OTP)_ |

### Embedded Signup configuration

| Item | Where | Value |
|---|---|---|
| Configuration ID (`config_id`) | Facebook Login for Business → Configurations | |
| Permissions on the config | same | ☐ all three above |
| Asset type | same | ☐ `whatsapp_business_account` at `MANAGE` |
| **Token type** | same | ☐ **System User** ☐ User → **wrong, see note** |
| Allowed Domains for the JS SDK | FB Login → Settings | |

> **Token type must be System User.** A User token expires in 60 days and every clinic would silently
> stop sending two months after connecting. A System User token has no expiry timer.

### Webhook — WhatsApp → Configuration

| Item | Value |
|---|---|
| Callback URL | `https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net/whatsappWebhook` |
| Verify token matches the `WHATSAPP_WEBHOOK_VERIFY_TOKEN` secret | ☐ yes |
| Status | ☐ green ☐ failing |
| Subscribed fields | ☐ `messages` ☐ `message_template_status_update` ☐ `message_template_quality_update` ☐ `account_update` ☐ `phone_number_quality_update` |

---

## 2. Long-lead items — start these today

Ordered by lead time. The first two run for days or weeks, so kick them off before any code lands.

### Business Verification

Business Settings → Business Info → Start Verification.

Needs: legal business name **exactly** as it appears on the document, registered address, phone,
website, and a verification document. For an Indian entity: Certificate of Incorporation, GST
certificate, Udyam registration, or a utility bill in the legal name.

The usual cause of rejection is a mismatch — the name typed into Meta differing from the document,
or the website domain's registration not matching the business. A rejection costs another full
cycle, so get the document set right the first time.

### Tech Provider registration

Needs verified business + accepted Platform Terms.

CruDoc is a **Tech Provider**, not a Solution Partner. Tech Provider is self-serve: clinics onboard
themselves through Embedded Signup and **each clinic's message charges go to their own WABA payment
method**. Solution Partner requires a Meta-approved partnership and gives you a credit line to
resell messaging — months of business development, and not needed here.

### App Review for Advanced Access

1–7 business days per submission, and often more than one submission.

**Sequencing trap:** the submission needs a screencast of the working Embedded Signup flow. That
means the Phase 3 onboarding page and functions have to exist and work before you can submit. Build
onboarding early, not last.

---

## 3. Credentials — three different things

Conflating these is the usual source of confusion.

| Credential | Scope | Lives in | Used for |
|---|---|---|---|
| App secret | CruDoc's app | Secret Manager, one value | webhook signature check, Embedded Signup code exchange |
| App access token (`{app-id}\|{app-secret}`) | CruDoc's app | derived at call time, never stored | resumable upload for template header examples |
| **Business integration system user token** | **one per clinic** | Secret Manager, one secret per doctorId | every send, template and register call for that clinic |

The per-clinic token has no expiry timer, but it **is revocable** — the clinic removing the app, an
admin password reset, or a Meta security action all invalidate it. That is what the
`reauth_required` state and the daily health sweep are for.

### Firebase secrets

Set with `firebase functions:secrets:set NAME` (never in `.env`, never committed):

| Secret | Set? |
|---|---|
| `WHATSAPP_APP_SECRET` | ☐ |
| `WHATSAPP_WEBHOOK_VERIFY_TOKEN` | ☐ |

Plain config in `functions/.env` (not secret, but not in source either):

| Var | Value |
|---|---|
| `WHATSAPP_APP_ID` | |
| `WHATSAPP_ES_CONFIG_ID` | |
| `WHATSAPP_GRAPH_VERSION` | `v23.0` |

> `WHATSAPP_ACCESS_TOKEN` and `WHATSAPP_PHONE_NUMBER_ID` are **removed** by this work. They were the
> single-shared-number model. Credentials are per-clinic now.

### Service accounts

| Grant | To | Why |
|---|---|---|
| `roles/secretmanager.secretAccessor` | default runtime SA | read per-clinic tokens when sending |
| `secretmanager.secrets.create` + `secretmanager.versions.add` | onboarding function SA only | write a token when a clinic connects |

Keep these separate — the sending path should not be able to create secrets.

---

## 4. Billing

Each clinic pays Meta directly from their own WABA payment method; CruDoc never handles it.

India utility rate is roughly **₹0.11–0.15 per message** — re-check Meta's current rate card rather
than trusting this number. A confirmation plus a reminder is two paid messages per appointment, and
automating every touchpoint multiplies that.

Meta's free tier covers 1,000 service conversations per month, and utility templates sent inside an
open 24-hour customer-service window are free.

**Open question:** does the ₹1999/mo `omnichannel_messaging` module absorb this cost or exclude it?
Clinics need to be told before they connect a payment method.

---

## 5. Done when

- [ ] Business Verification = Verified
- [ ] App is type Business and in Live mode
- [ ] All three permissions at Advanced Access
- [ ] `config_id` exists with System User token type
- [ ] Webhook shows green in the dashboard
- [ ] This document records the App ID, config_id and test WABA ids
