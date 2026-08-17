# 📱 CruDoc — WhatsApp Appointment Notification System Guide

This document outlines how to use, configure, and maintain the automated **WhatsApp Appointment Notification System** in CruDoc.

---

## Table of Contents
1. [Overview & Features](#1-overview--features)
2. [How to Use (Doctor & Receptionist Workflow)](#2-how-to-use-doctor--receptionist-workflow)
3. [Environment Configuration (.env)](#3-environment-configuration-env)
4. [Meta Developer & WhatsApp Business Setup](#4-meta-developer--whatsapp-business-setup)
5. [Registering the Official Appointment Template](#5-registering-the-official-appointment-template)
6. [Switching to a Production Clinic Phone Number](#6-switching-to-a-production-clinic-phone-number)
7. [Privacy & Security Guardrails](#7-privacy--security-guardrails)
8. [Troubleshooting & FAQs](#8-troubleshooting--faqs)

---

## 1. Overview & Features

CruDoc integrates an enterprise-grade, privacy-compliant WhatsApp notification engine:
- **⚡ 100% Automated Background Dispatch**: Whenever an appointment is booked via Flutter Desktop/Web/Mobile or the AI Voice Receptionist phone bot, Meta's WhatsApp Cloud API dispatches the notification instantly.
- **💬 1-Click WhatsApp Companion**: Every appointment card features a **"Chat / Resend via WhatsApp"** button for manual direct messaging and resends without API limits.
- **📊 Real-Time Delivery Tracking**: Appointment cards display live delivery badges (`Sent`, `Delivered`, `Read`, `Failed`, `Skipped`).
- **🔒 Zero Medical Leakage**: Only operational details (Doctor, Clinic, Date, Time, Consultation Type) are sent. Diagnoses, clinical notes, and prescriptions are strictly stripped.
- **🛡️ Idempotent Execution**: Duplicate bookings or rapid double-clicks never send duplicate WhatsApp messages.

---

## 2. How to Use (Doctor & Receptionist Workflow)

### Booking an Appointment
1. Open CruDoc and navigate to **Appointments $\to$ Schedule Session** (or book via **Patient Records**).
2. Select a patient:
   - If the patient has a valid mobile number (e.g. `+91 98765 43210`), CruDoc displays a green badge: **`💬 WhatsApp Auto-Notify`**.
   - If no phone is on profile, it cleanly displays **`No WhatsApp mobile`**.
3. Choose Date, Time, Duration, and Consultation Type (In-Clinic or Home Visit).
4. Tap **Confirm & Schedule**.
5. The appointment is saved immediately, and the WhatsApp notification is triggered automatically in the background.

### Viewing Status & 1-Click Resend
1. Click any scheduled appointment on the calendar or patient list.
2. In the details sheet, look at the **WhatsApp Notification Section**:
   - **`🟢 WhatsApp: Delivered` / `Sent`**: Confirms Meta successfully delivered the message.
   - **`🔵 WhatsApp: Read`**: Patient opened and read the message (blue ticks).
   - **`⚪ WhatsApp: Skipped`**: Patient has no valid phone number.
3. Click the green **`Chat / Resend via WhatsApp`** button to open WhatsApp on your computer or phone with the patient's pre-filled, personalized confirmation message.

---

## 3. Environment Configuration (`.env`)

Backend Cloud Functions and the app read credentials from `CruDoc/functions/.env`:

```env
# Mode options: 'production' | 'sandbox' | 'development'
WHATSAPP_MODE=production

# Meta WhatsApp Cloud API Access Token
WHATSAPP_ACCESS_TOKEN=EAAPCogiyZB7ABSL1...

# Meta Phone Number ID (from WhatsApp API Setup or Production Phone Numbers)
WHATSAPP_PHONE_NUMBER_ID=1260194177180019

# Optional: Webhook verification token for delivery receipts
WHATSAPP_WEBHOOK_VERIFY_TOKEN=crudoc_whatsapp_verify_token_2026

# Optional: Custom approved Meta template name (defaults to 'appointment_confirmation')
WHATSAPP_TEMPLATE_NAME=appointment_confirmation
```

---

## 4. Meta Developer & WhatsApp Business Setup

### For Developers / Testers (Sandbox Mode)
1. Log in to [developers.facebook.com](https://developers.facebook.com) $\to$ **My Apps** $\to$ **`Svayatta CruDoc`**.
2. Navigate to **WhatsApp $\to$ API Setup**:
   - Copy the **Temporary Access Token** and **Phone number ID**.
   - Under **Step 2 (Send and receive messages)**, click **Manage phone number list** to add tester phone numbers. Meta will send a 6-digit WhatsApp OTP to whitelist the number.

---

## 5. Registering the Official Appointment Template

To customize the message text sent by Meta Cloud API:

1. Go to [WhatsApp Manager $\to$ Message Templates](https://business.facebook.com/wa/manage/message-templates).
2. Click **Create Template**:
   - **Category**: `Utility`
   - **Name**: `appointment_confirmation`
   - **Language**: `English (US)`
3. Under **Body**, paste:
   ```text
   Hello {{1}}, your appointment with {{2}} at {{3}} has been confirmed for {{4}} at {{5}} ({{6}}). Please arrive 10 minutes early. Thank you!
   ```
4. Under **Variable samples**, enter sample values:
   - `{{1}}`: `Rahul Sharma`
   - `{{2}}`: `Dr. Sarah Jenkins`
   - `{{3}}`: `CruDoc Clinic`
   - `{{4}}`: `20 Aug 2026`
   - `{{5}}`: `10:30 AM`
   - `{{6}}`: `In-Clinic Consultation`
5. Click **Submit for review** *(Meta automatically approves utility templates within 1–2 minutes)*.

---

## 6. Switching to a Production Clinic Phone Number

When deploying to a live clinic with their official SIM card / landline:

1. In [developers.facebook.com](https://developers.facebook.com), open the app and go to **WhatsApp $\to$ API Setup $\to$ Step 2: Production setup**.
2. Click **Add Phone Number**:
   - Enter the clinic's official Display Name (e.g. *Svayatta Healthcare*).
   - Enter the clinic's phone number.
   - Choose **SMS** or **Voice call** to receive the 6-digit verification code.
3. Once verified, copy the new **Production Phone Number ID**.
4. In **Meta Business Suite $\to$ System Users**, generate a **Permanent Access Token** with `whatsapp_business_messaging` permission.
5. Update `WHATSAPP_PHONE_NUMBER_ID` and `WHATSAPP_ACCESS_TOKEN` in `CruDoc/functions/.env` and deploy via `firebase deploy --only functions`.

---

## 7. Privacy & Security Guardrails

CruDoc strictly implements healthcare privacy standards:
1. **Medical Data Stripping**: Diagnoses, clinical notes, therapy records, and medication names are explicitly excluded from WhatsApp payloads.
2. **E.164 Normalization**: Automatically strips non-numeric characters, spaces, dashes, leading zeros, and prepends `+91` (India) or international codes.
3. **Multi-Tenant Scoping**: All SQLite and Firestore log queries are strictly scoped to the logged-in `doctorId`.
4. **Input Sanitization**: Control characters, carriage returns (`\r\n`), and template injection attacks are filtered prior to transmission.

---

## 8. Troubleshooting & FAQs

### Q: Why did the test message say `hello_world` instead of appointment details?
> **Answer**: Meta Sandbox enables `hello_world` by default until your custom `appointment_confirmation` template is submitted and approved in WhatsApp Manager (Step 5). The 1-click **"Chat / Resend via WhatsApp"** button always contains the full appointment text.

### Q: Why did the test message come from a `+1 555` number?
> **Answer**: In developer sandbox mode, Meta provides a free test number so you don't need a real SIM card. Once you add your clinic's number in Production Setup (Step 6), messages will come directly from your verified clinic number.

### Q: Does WhatsApp messaging cost money during development?
> **Answer**: **No.** Testing via Developer Sandbox or the 1-click WhatsApp button is **$0.00 (100% Free)**.
