# AI Voice Receptionist Platform

Multi-tenant AI phone receptionist for clinics. Twilio → Pipecat →
Sarvam STT → Gemini (tool calling) → Sarvam TTS → Twilio, with each call
isolated in its own `CallSession` + Pipecat pipeline (see
`app/voice/call_session.py` and `app/voice/pipeline.py`).

Appointments are written into CruDoc through its Cloud Functions; see
[CruDoc integration](#crudoc-integration) for the wire contract and setup.

## Architecture

```
app/
├── api/routes/    FastAPI routes (thin -- delegate to services/)
├── voice/         Per-call isolation: CallSession, Pipecat pipeline, tools, prompts
├── services/       Business logic: clinic resolution, appointments, transfer, calls
├── providers/      Appointment provider adapters (CruDoc today; pluggable)
├── models/         SQLAlchemy models (clinics, doctors, phone_numbers, receptionists, calls, appointments)
├── schemas/        Pydantic request/response + internal DTOs
├── db/             Local SQLite by default; PostgreSQL and Redis are optional
└── core/           Config, structured logging, security (Twilio signature + internal API key)
```

### Concurrency & tenant isolation

- Every inbound call gets exactly one `CallSession` (dataclass holding
  call_id, clinic config, selected doctor, appointment-in-progress state,
  STT-failure counter) and one Pipecat `Pipeline`/`PipelineTask`, built
  fresh inside the WebSocket handler for that call
  (`app/api/routes/twilio.py::media_stream`). Nothing is stored in module-
  level/global state, so N simultaneous callers get N fully independent
  pipelines under normal `asyncio` concurrency — no thread-per-call, no
  shared conversation object.
- A call is bound to a tenant once, at call start, via
  `ClinicService.resolve_by_twilio_number` (Twilio `To` number → clinic →
  doctors/receptionists/appointment-provider config). That `ResolvedClinic`
  is immutable for the life of the call.
- Provider *adapters*, by contrast, are deliberately shared. Each owns an
  `httpx.AsyncClient` connection pool, and the call sites build one per
  tool call (once for availability, again for booking), so
  `providers/factory.py` caches them against the exact config they were
  built from. Without that cache every call leaked a pool for the life of
  the process. A rotated credential produces a different cache key and
  therefore a fresh adapter.

### Appointment race conditions

Four layers (`app/services/appointment_service.py`):
1. A Redis lock on `(clinic, doctor, slot)` narrows the race window in deployments; local mode uses an in-process lock.
2. The provider call itself is the real availability source — never a
   cached read. CruDoc enforces this server-side and answers `409` for an
   occupied slot, which matters because it can see appointments the doctor
   booked inside the app and this service's tables cannot.
3. A DB `UNIQUE(doctor_id, slot_start)` constraint on `appointments` is
   the final guarantee; on collision the just-made provider booking is
   unwound (`provider.cancel`) and the caller is offered fresh
   alternatives.
4. Alternatives come from a *fresh* availability call, and a failure to
   fetch them never masks the original booking error.

### Hard STT fallback

`app/voice/pipeline.py::HardFallbackMonitor` counts consecutive
empty/unintelligible `TranscriptionFrame`s on the `CallSession` and forces
a transfer once `STT_FAILURE_THRESHOLD` (env, default 2) is hit —
independent of whether Gemini ever calls `transfer_to_receptionist`.

### Availability is "unknown", not "empty"

`check_availability` raises `AppointmentProviderError` when the provider
cannot be reached, rather than returning `[]`. Those two states look
identical to the model but mean opposite things to a caller, and telling
someone the day is fully booked when the calendar was simply unreachable
is a fabricated answer. The tool handler surfaces the difference as
`availability_known: false`, and the prompt instructs the model to offer a
transfer in that case.

## CruDoc integration

The adapter (`app/providers/crudoc_adapter.py`) talks to three Cloud
Functions in `../functions/src/appointments.ts`. All three authenticate
with a shared secret in an **`X-Api-Key`** header — not a bearer token —
and all answer a JSON body carrying `success: bool`.

| Endpoint | Method | Purpose |
| --- | --- | --- |
| `/createAppointment` | POST | Book. `201` + `{success, appointment_id, patient_id}`, or `409` when the slot is taken. |
| `/getAvailability` | GET | Open slots for one doctor-day. `200` + `{success, slots: [{start, end}]}` as UTC ISO 8601. |
| `/cancelAppointment` | POST | Soft-cancel (`status: 'cancelled'`, `isDeleted: true`). Idempotent. |

`createAppointment` requires `patient_name`, `phone`, `doctor_id` and a
start time, and rejects anything else with `400`. `doctor_id` is the
doctor's Firebase UID in the `users` collection, which is what a
`Doctor.external_provider_id` holds here.

Two things about this integration are easy to get wrong and fail quietly:

- **Times.** CruDoc stores `scheduledStart` as a Firestore Timestamp and
  the Flutter app renders it with `Timestamp.toDate()`, i.e. in
  device-local time. A wall-clock string sent without an offset is parsed
  in the *runtime's* zone, which is UTC on Cloud Functions — so a 10:30
  booking previously landed at 16:00 IST in the app, a silent 5.5-hour
  shift on every AI booking. The adapter therefore always sends
  `scheduled_start` as ISO 8601 *with* an offset, localising a naive
  datetime to the clinic's timezone first; the function also accepts the
  legacy `date` + `time` pair with an explicit `tz_offset_minutes`.
  `functions/test/appointments.test.js` pins this.
- **Business hours.** CruDoc has no working-hours model, so the
  open/close/slot-length grid lives in this clinic's
  `appointment_provider_config` and is sent on each availability request.

`reschedule` raises: CruDoc exposes no such endpoint, and a silent no-op
would read as a moved appointment. Reschedule is cancel-then-book.

### Provider config keys

In the clinic's `config.appointment_provider_config`:

| Key | Required | Default | Notes |
| --- | --- | --- | --- |
| `base_url` | yes | — | The region host, e.g. `https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net`. A URL that points at `/createAppointment` itself is trimmed rather than producing `.../createAppointment/getAvailability`. |
| `api_key` | yes | — | Must match the `VOICE_BOT_API_KEY` secret on the Cloud Functions side. |
| `open_time` | no | `09:00` | Clinic-local. |
| `close_time` | no | `18:00` | Clinic-local. |
| `slot_minutes` | no | `30` | Must be an integer. |

### Deploying the Cloud Functions

```bash
cd ../functions
firebase functions:secrets:set VOICE_BOT_API_KEY   # same value as api_key above
npm run build
firebase deploy --only functions:createAppointment,functions:getAvailability,functions:cancelAppointment
```

`getAvailability` and the conflict check in `createAppointment` query
`appointments` by `doctorId` + `scheduledStart`, which needs the composite
index in `firestore.indexes.json`:

```bash
firebase deploy --only firestore:indexes
```

## Integration boundaries

Verified against the installed `pipecat-ai` 0.0.100 and live Sarvam/Gemini
endpoints on 2026-09-30 (see `tests/test_voice_wiring.py`):

- `app/voice/pipeline.py` — class names, constructor signatures, context
  aggregators and tool registration all check out against 0.0.100. Two
  details that are easy to get wrong and fail *silently*:
  - Sarvam's STT/TTS services take `language` inside their `InputParams`,
    **not** as a top-level kwarg. A top-level `language=` is swallowed by
    `**kwargs` and ignored, leaving the call in the wrong language.
  - Tool handlers must take a single `FunctionCallParams` and return their
    result through `params.result_callback`. A handler with more than one
    parameter is routed down Pipecat's legacy 6-positional-arg path, and a
    returned value is discarded — the model then waits forever for its tool
    result.
- `app/voice/pipeline.py` — session lifecycle. Two things Pipecat does *not*
  do for you, both of which leak a call:
  - A `PipelineTask` keeps running after its WebSocket closes. The transport's
    `on_client_disconnected` (and `on_session_timeout`) handler must cancel
    the task, or `runner.run()` never returns and the pipeline plus its Sarvam
    sockets stay alive for the life of the process.
  - `ErrorFrame`s travel *upstream* to the task, not downstream through the
    pipeline, so they never reach the output serializer. Provider failures are
    only visible via an `on_pipeline_error` handler.
- `app/services/call_service.py` — call teardown normally runs while the
  handler task is being cancelled (the caller hung up), and an `await` in a
  cancelled task raises immediately. Closing a call record therefore uses
  `finalize_call_record_shielded`, which writes on its own session in a
  shielded task; a commit on the call's own session is silently lost and
  strands the record in `in_progress`.
- `app/core/config.py` — Gemini model choice. `listModels` returns models a
  key cannot actually use: `gemini-2.5-flash` is listed but 404s with "no
  longer available to new users", and `gemini-3.8`/`3.7-flash` (and therefore
  `gemini-flash-latest`) were returning 503 under load. `gemini-3.5-flash` was
  measured reliable (3/3) at ~1.4s per turn with tool calling;
  `gemini-3.5-flash-lite` is ~0.8s if latency matters more than reasoning.
  Preflight therefore performs a real `generateContent` call rather than
  trusting the model listing.
- `app/voice/prompts.py` — the model is told the current date/time in the
  clinic's timezone. Without it the bot cannot resolve "tomorrow" and asks the
  caller what tomorrow's date is. Named timezones need the `tzdata` package on
  Windows, where the OS ships no zoneinfo database.
- `app/voice/voices.py` — Sarvam's `bulbul:v2` is deprecated server-side and
  400s every request; `bulbul:v3` is current and rejects all v2 speaker
  names. An unknown speaker produces a call with **zero audio**, so
  `clinic.config.voice_id` is validated against the v3 speaker list and
  falls back rather than being passed through.
- `app/providers/crudoc_adapter.py` — endpoint paths, the `X-Api-Key` auth
  scheme, payload keys and status-code meanings are confirmed against
  CruDoc's own Cloud Functions source, and pinned by
  `tests/test_crudoc_adapter.py`. Those tests assert the bytes on the wire
  rather than the adapter's internals, because an earlier version of this
  adapter targeted an invented REST shape (bearer auth,
  `/providers/{id}/appointments`, `slot_start`/`patient_phone` keys) that
  type-checked and imported cleanly while failing every real request.

Still unverified, because there is no live account to check against:

- `app/api/routes/twilio.py` — the exact shape of Twilio's Media Streams
  `start` event payload (caller number field name, custom parameters).
- The CruDoc functions have been unit-tested and type-checked but not yet
  exercised against a deployed Firebase project.

## Troubleshooting a silent test call

Start here — it checks every external dependency and names the fix:

```bash
curl localhost:8000/voice-test/preflight
```

The browser UI runs the same check when you press Start and refuses to
begin if a provider is not usable, so a bad key shows up as a named error
instead of a call where nothing happens. Results are split into `blockers`
(the call cannot work) and `warnings` (it works but degraded -- e.g. no
appointment provider configured, so the bot can only transfer). Provider errors that occur
mid-call are also pushed to the browser (Pipecat routes `ErrorFrame`s
upstream to the task, so the pipeline registers an `on_pipeline_error`
handler to forward them).

Common causes:

| Symptom | Cause | Fix |
| --- | --- | --- |
| No audio at all, `Speaker '...' is not recognized` | `config.voice_id` is unset or a retired `bulbul:v2` name | Leave it null, or set one of the `bulbul:v3` speakers in `app/voice/voices.py` |
| No audio at all, `Model 'bulbul:v2' has been deprecated` | Pipecat's built-in default TTS model | `SARVAM_TTS_MODEL=bulbul:v3` (already the default here) |
| Greeting plays, then nothing after you speak | Gemini rejected the request | Check `GOOGLE_API_KEY`; see below |
| `403 API_KEY_SERVICE_BLOCKED` from Gemini | The key is restricted and does not allow `generativelanguage.googleapis.com` | In Google Cloud Console → Credentials → the key → API restrictions, allow "Generative Language API" and enable that API for the project; or create a fresh key at <https://aistudio.google.com/apikey> |
| Bot never responds, no error | STT returned empty text repeatedly | `HardFallbackMonitor` transfers after `STT_FAILURE_THRESHOLD`; check mic input level |
| Call records stuck in `in_progress` | Pipeline teardown did not run | Check for a `*_client_disconnected` log line; the transport handler must cancel the task |
| Gemini `404 ... no longer available to new users` | The model is listed but not usable by this key | Set `GEMINI_MODEL` to one preflight suggests (e.g. `gemini-3.5-flash`) |
| Gemini `503 high demand` | The model is overloaded, not misconfigured | Retry, or switch `GEMINI_MODEL` to another flash model |
| Bot asks "what is tomorrow's date?" | The prompt has no current date | Ensure `tzdata` is installed so the clinic timezone resolves |
| Bot always offers a transfer instead of booking | Clinic has no `appointment_provider_config` | Preflight reports this under `warnings`; set `base_url`/`api_key` |
| Booking fails with `Unauthorized` | `api_key` does not match the Cloud Functions `VOICE_BOT_API_KEY` secret | Re-set the secret and redeploy the functions |
| Booking fails with `patient_name is required` | The model called `book_appointment` without a name | It is a required tool arg and the prompt tells the model to ask; check the prompt was not overridden by `ai_instructions` |
| Appointment appears at the wrong time in the app | A caller or config is sending an unqualified wall-clock time | The adapter sends an explicit offset; check the clinic's `timezone` is a valid IANA name and `tzdata` is installed |
| Availability always empty | `getAvailability` is not deployed, or its composite index is missing | Deploy the function and `firebase deploy --only firestore:indexes` |
| `The clinic calendar could not be reached` | `getAvailability` returned non-200 | Check the function logs; the adapter surfaces the server's own error |

## Local development

```powershell
Copy-Item .env.example .env   # add API keys only when testing live calls
py -3.11 -m venv .venv
.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
uvicorn app.main:app --reload

# expose to Twilio:
ngrok http 8000
# set PUBLIC_BASE_URL to the ngrok URL, set the clinic's Twilio number's
# Voice webhook to <PUBLIC_BASE_URL>/twilio/voice
```

Browser-based testing without a phone number: start the server and open
<http://localhost:8000/voice-test>. That sandbox is development-only and
never transfers calls; set `LOCAL_VOICE_TEST_ALLOW_BOOKING=true` to also let
it make real appointment-provider bookings.

The API creates a local `voice_receptionist.db` SQLite file and its tables
on startup. No PostgreSQL or Redis server is required for a single-process
local test. Docker Compose persists its SQLite file in `data/`.

## Going live on a phone number

The browser sandbox (`/voice-test`) stays available for testing; the phone
path runs alongside it.

1. **Buy/verify a Twilio number** (Console -> Phone Numbers). For Indian
   (+91) numbers Twilio requires a regulatory bundle; a US number works
   immediately for testing.
2. **Make the service publicly reachable over HTTPS/WSS.** Locally:
   `ngrok http 8000`. For production, deploy the Docker image behind a
   TLS host (Cloud Run, Fly, a VM + Caddy). Media Streams needs WebSocket
   support and a single long-lived connection per call.
3. **Set `.env`:** `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN` (used both to
   validate webhooks and to hang up/transfer calls) and `PUBLIC_BASE_URL`
   (exactly the public URL, no trailing slash -- Twilio's signature is
   computed over it). Set `APP_ENV=production` on the live deployment to
   turn the browser sandbox off there.
4. **Map the number to a clinic** in E.164, exactly as Twilio shows it:
   `POST /api/clinics/{clinic_id}/phone-numbers {"twilio_number": "+1..."}`.
   Add at least one receptionist number for transfers.
5. **Point Twilio at the webhook:** the number's *A call comes in* ->
   Webhook, `POST`, `<PUBLIC_BASE_URL>/twilio/voice`.
6. Call the number. Watch for `call_pipeline_started` in the logs; an
   unmapped number plays "not currently configured" and hangs up.

## Dedicated receptionists per doctor (premium)

Each doctor -- or a group of doctors sharing a clinic -- can have their own
phone number answered by a dedicated AI receptionist. A *line*
(`phone_numbers` row) binds one number to a clinic and to the doctor(s) it
speaks for:

| Line | Receptionist can see / book | Introduces itself as |
| --- | --- | --- |
| 1 doctor | only that doctor | the line `label`, e.g. "Dr. Amit (Smile Clinic)" |
| several doctors | only that group | the line `label` |
| no doctors | every active doctor of the clinic | the clinic name |

What the model can list or book is derived from the line's doctors
(`clinic_service._assemble` -> `appointment_service._doctor_in`), so one
doctor's receptionist cannot touch another doctor's calendar. A line can
override `greeting`, `voice_id`, `ai_instructions` and
`supported_languages`, and has its own fallback human numbers (tried before
the clinic-wide ones).

**Premium gate.** `clinics.ai_receptionist_enabled` must be true for a
number to answer; otherwise the caller hears the "not configured" message
and the log line `unmapped_twilio_number` carries `premium_not_enabled=true`.
The dev-only browser sandbox is not gated.

**Super Admin wiring.** The Super Admin app never calls this service
directly. Flow:

```
Super Admin app (ReceptionistLineService)
  -> Cloud Function manageReceptionistLines   (checks role == superAdmin, audit-logs)
  -> voice service PUT /api/admin/receptionist-lines/{+E164}   (x-api-key)
```

The function validates that every doctor has the `ai_agentic_calling`
module, takes their names from Firestore, and injects the clinic's
CruDoc booking credentials. Endpoints (all idempotent, keyed by CruDoc IDs):

| Endpoint | Purpose |
| --- | --- |
| `PUT /api/admin/receptionist-lines/{number}` | Upsert clinic + line + doctors + fallback humans |
| `GET /api/admin/receptionist-lines?clinic_external_id=` | List lines |
| `DELETE /api/admin/receptionist-lines/{number}` | Deactivate (history kept) |
| `PUT /api/admin/clinics/{external_id}/entitlement` | Premium on/off for a whole clinic |
| `GET /api/admin/status?deep=` | Service health and Twilio config; `deep=true` also makes one real Sarvam and Gemini call |
| `GET /api/admin/calls?clinic_external_id=&twilio_number=&days=&limit=` | Recent calls with outcome, duration and what was booked, plus an outcome breakdown |
| `GET /api/admin/appointments?clinic_external_id=&days=&limit=` | Appointments the AI booked |

A call's outcome is `booked` when the AI made at least one booking,
`transferred` when it handed off, and `no_action` otherwise.

The function lives in `../functions-admin` (the `admin` codebase, next to
`claimSuperAdmin`) because Super Admin is its own app now. Its UI is the
"AI Receptionist" tab in the CrudocSuper-admin repo
(`lib/screens/dashboard/receptionist_lines_screen.dart`). Setup:

```bash
cd ..
firebase functions:secrets:set VOICE_SERVICE_ADMIN_KEY   # = this service's VOICE_BOT_API_KEY
# VOICE_SERVICE_URL (plain param) = the public https URL of this service
firebase deploy --only functions:admin
```

Existing databases: new columns (`clinics.external_id`,
`clinics.ai_receptionist_enabled`, `phone_numbers.label/config`,
`receptionists.phone_number_id`, `calls.phone_number_id`) and the `phone_number_doctors` table are
not created on an existing SQLite/Postgres file (no Alembic migrations yet).
Delete the local dev DB, or add the columns by hand.

## Provisioning a clinic

```bash
curl -X POST localhost:8000/api/clinics -H "x-api-key: $VOICE_BOT_API_KEY" \
  -d '{
        "name": "ABC Dental Clinic",
        "timezone": "Asia/Kolkata",
        "ai_receptionist_enabled": true,
        "config": {
          "appointment_provider": "crudoc",
          "appointment_provider_config": {
            "base_url": "https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net",
            "api_key": "<same as the VOICE_BOT_API_KEY secret>",
            "open_time": "09:00",
            "close_time": "18:00",
            "slot_minutes": 30
          }
        }
      }'

# external_provider_id is the doctor's Firebase UID in CruDoc's `users` collection
curl -X POST localhost:8000/api/clinics/{clinic_id}/doctors -H "x-api-key: $VOICE_BOT_API_KEY" \
  -d '{"name": "Dr. Rahul", "specialization": "Dentist", "external_provider_id": "crudoc-doctor-uid"}'

curl -X POST localhost:8000/api/clinics/{clinic_id}/phone-numbers -H "x-api-key: $VOICE_BOT_API_KEY" \
  -d '{"twilio_number": "+91XXXXXXXX01"}'
```

The clinic's `timezone` is what the adapter uses to qualify a slot time, so
set it correctly even though it defaults to `Asia/Kolkata`.

## Tests

```bash
pytest                      # this service
cd ../functions && npm run build && node test/appointments.test.js
```

Tests use an in-memory SQLite database by default, so they do not touch the
local application data file. Set `DATABASE_URL` explicitly to use PostgreSQL.

Covers tenant isolation, clinic resolution edge cases, DB-level
double-booking rejection, transfer fallback behavior (spec section 25's
business-critical list), and the CruDoc wire contract
(`tests/test_crudoc_adapter.py` — header name, paths, payload keys,
201/409/400/401 handling and timezone qualification, against a mock
transport). The Cloud Functions' time and slot arithmetic is covered by
`functions/test/appointments.test.js`.

Pipecat pipeline wiring itself is not unit tested here — it needs an
integration/staging test against real Twilio + Sarvam + Gemini, which is
out of scope for a local test suite. Neither suite talks to a deployed
Firebase project.

## Not yet built (see spec build order, phases 11-13)

- Auth/admin dashboard beyond the internal `x-api-key` guard on management
  endpoints.
- Alembic migration files (models are final; run
  `alembic revision --autogenerate` once a DB is reachable).
- Cancellation/reschedule *tools* for the caller. The provider methods and
  schemas exist and `cancel` is wired to CruDoc, but there are no tool
  declarations exposing them to the model yet; they follow the same pattern
  as `book_appointment` in `app/voice/tools.py`. Reschedule needs to be
  cancel-then-book, since CruDoc has no reschedule endpoint.
