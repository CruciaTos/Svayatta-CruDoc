# CruDoc AI Voice Receptionist

A standalone Python service that answers incoming phone calls and either books appointments into CruDoc or transfers the caller to a human receptionist.

**Tech stack**: [Pipecat](https://pipecat.ai) · [Twilio](https://twilio.com) · [Sarvam AI](https://sarvam.ai) (STT/TTS) · [Google Gemini](https://ai.google.dev) (LLM)

---

## How It Works

```
Caller → Twilio → WebSocket → Pipecat Pipeline → Caller
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼              ▼
              Sarvam STT    Gemini LLM    Sarvam TTS
                              │    │
                    ┌─────────┘    └──────────┐
                    ▼                          ▼
           book_appointment          transfer_to_receptionist
           (→ CruDoc API)           (→ Twilio redirect)
```

1. Caller dials the Twilio number.
2. Twilio opens a Media Stream WebSocket to this service.
3. Audio flows through: **Sarvam STT** → **Gemini LLM** → **Sarvam TTS** → back to the caller.
4. The LLM has two tools:
   - `book_appointment` — collects name, date, time, then POSTs to CruDoc's Cloud Function to create the appointment.
   - `transfer_to_receptionist` — redirects the live Twilio call to a configured phone number.
5. **Hard fallback**: If STT returns 2 consecutive empty/unintelligible results, the call is transferred automatically — independent of the LLM.

---

## Prerequisites

- **Python 3.11+** (with [`uv`](https://docs.astral.sh/uv/) recommended, or plain `pip`)
- **Twilio account** with a phone number
- **Sarvam AI API key** ([sarvam.ai](https://sarvam.ai))
- **Google AI API key** ([ai.google.dev](https://ai.google.dev))
- **ngrok** (for local development) — [ngrok.com](https://ngrok.com)

---

## 1. Buy & Configure a Twilio Phone Number

1. Sign up / log in at [console.twilio.com](https://console.twilio.com).
2. Go to **Phone Numbers → Buy a Number**. Pick one with Voice capability.
3. Note your **Account SID** and **Auth Token** from the dashboard.
4. **Don't configure the webhook yet** — you'll do that after starting the bot (step 4 below).

---

## 2. Set Up Environment Variables

```bash
cd voice-receptionist
cp .env.example .env
```

Fill in every value in `.env`:

| Variable | Where to get it |
|---|---|
| `SARVAM_API_KEY` | [Sarvam AI dashboard](https://sarvam.ai) |
| `GOOGLE_API_KEY` | [Google AI Studio](https://ai.google.dev) |
| `TWILIO_ACCOUNT_SID` | Twilio Console dashboard |
| `TWILIO_AUTH_TOKEN` | Twilio Console dashboard |
| `TWILIO_NUMBER` | The number you bought (E.164: `+14155551234`) |
| `RECEPTIONIST_NUMBER` | The human receptionist's phone (E.164) |
| `CRUDOC_APPOINTMENTS_API` | Your deployed Cloud Function URL (see below) |
| `CRUDOC_DOCTOR_ID` | The Firebase UID of the doctor to book under |
| `VOICE_BOT_API_KEY` | A shared secret — must match the Cloud Function's `VOICE_BOT_API_KEY` |

---

## 3. Deploy the Appointment Cloud Function

The bot calls a Firebase Cloud Function to create appointments. Deploy it first:

```bash
cd ../functions

# Set the API key the bot will use to authenticate
firebase functions:config:set voice.bot_api_key="your-secret-key-here"

# Or, for v2 functions using environment variables:
# Set VOICE_BOT_API_KEY in your Cloud Functions environment

npm run build
firebase deploy --only functions
```

Note the deployed URL — it will look like:
```
https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net/createAppointment
```

Set this as `CRUDOC_APPOINTMENTS_API` in your `.env`.

---

## 4. Run Locally (Development)

### Option A: Using `uv` (recommended)

```bash
cd voice-receptionist

# Install dependencies
uv pip install -r requirements.txt

# Start ngrok in a separate terminal
ngrok http 7860

# Start the bot (replace with your ngrok domain)
uv run bot.py -t twilio -x abc123.ngrok.io
```

### Option B: Using `pip`

```bash
cd voice-receptionist

# Create and activate a virtual environment
python -m venv .venv
.venv\Scripts\activate        # Windows
# source .venv/bin/activate   # macOS/Linux

# Install dependencies
pip install -r requirements.txt

# Start ngrok in a separate terminal
ngrok http 7860

# Start the bot
python bot.py -t twilio -x abc123.ngrok.io
```

### Configure the Twilio Webhook

Once the bot and ngrok are running:

1. Go to your Twilio phone number's configuration page.
2. Under **Voice → A call comes in**, set:
   - **Webhook**: `https://abc123.ngrok.io` (your ngrok HTTPS URL)
   - **HTTP Method**: `POST`
3. Save.

Now call your Twilio number — the bot should answer and greet you!

---

## 5. Test It

### Happy path (appointment booking)
1. Call your Twilio number.
2. The bot greets you.
3. Say "I'd like to book an appointment".
4. Give your name, preferred date, and time when asked.
5. ✅ The appointment should appear immediately in the CruDoc app.

### Transfer path
1. Call your Twilio number.
2. Say something unintelligible, or say "Can I speak to a real person?"
3. ✅ The call should be transferred to `RECEPTIONIST_NUMBER`.

### Hard fallback
1. Call your Twilio number.
2. Stay completely silent (or hold the phone far away).
3. ✅ After ~2 empty STT results, the bot says "Let me connect you" and transfers.

---

## 6. Deployment (Production)

> **Important**: This service holds a persistent WebSocket per call — it **cannot** run on classic serverless (Lambda, Cloud Run with default settings). It needs an always-on process.

### Option A: Pipecat Cloud

Pipecat offers managed hosting for voice bots. See [docs.pipecat.ai](https://docs.pipecat.ai) for deployment instructions.

### Option B: Always-On VM / Container

1. **Provision** a small VM (e.g. GCP `e2-small`, AWS `t3.small`) or a container service with persistent connections (e.g. GCP Cloud Run with `--no-cpu-throttling`, AWS Fargate, Fly.io).

2. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

3. **Set environment variables** (via the cloud provider's secrets manager or `.env`).

4. **Run the bot**:
   ```bash
   python bot.py -t twilio
   ```
   Use a process manager like `supervisord` or `systemd` to keep it running.

5. **Point Twilio** at your VM's public URL instead of ngrok.

6. **TLS**: Ensure HTTPS is terminated (via a load balancer or reverse proxy like Caddy/nginx).

### Resource requirements
- **CPU**: Minimal — the heavy lifting (STT/LLM/TTS) happens on external APIs.
- **Memory**: ~256 MB base + ~50 MB per concurrent call.
- **Network**: Stable, low-latency connection for real-time audio streaming.

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Bot doesn't answer | Check ngrok is running and Twilio webhook URL is correct |
| "Unauthorized" in bot logs | `VOICE_BOT_API_KEY` doesn't match between bot and Cloud Function |
| Appointment doesn't appear in app | Check `CRUDOC_DOCTOR_ID` matches the logged-in doctor's UID |
| Import errors on startup | Pipecat version mismatch — check [docs.pipecat.ai](https://docs.pipecat.ai) for current import paths |
| Transfer doesn't work | Verify `RECEPTIONIST_NUMBER` is a valid E.164 phone number |
