# Local Voice Testing for the AI Voice Receptionist

## Detailed implementation plan --- no Twilio phone number required

**Project:** AI Voice Receptionist Platform\
**Goal:** Test a real spoken conversation with the receptionist using a
computer microphone and speakers, without buying a Twilio phone number.

------------------------------------------------------------------------

## 1. Goal and expected result

The existing application is a multi-tenant clinic receptionist backend
built with FastAPI, Pipecat, Sarvam speech-to-text (STT), Gemini, and
Sarvam text-to-speech (TTS). Its telephone audio path is designed around
Twilio Media Streams.

The goal is to add a **separate local testing path**. It must reuse the
existing clinic configuration, receptionist prompt, AI tools,
appointment logic, STT, LLM, and TTS where practical, but must not
require a real telephone call.

At the end, a developer should be able to:

1.  Start the existing FastAPI application.
2.  Open a local test page in a browser.
3.  Allow microphone access.
4.  Start a voice session.
5.  Speak a question.
6.  Hear the AI receptionist answer through the computer speakers.
7.  Review logs and confirm that errors are handled safely.

**Important:** `http://127.0.0.1:8000/docs` only confirms that the API
documentation is served. The current OpenAPI specification does not
expose a browser voice-testing endpoint.

------------------------------------------------------------------------

## 2. Current project architecture

The supplied project README describes this intended production path:

``` text
Incoming phone call
       |
     Twilio
       |
 POST /twilio/voice
       |
 Twilio Media Streams WebSocket
       |
 FastAPI WebSocket handler
       |
 Pipecat pipeline
       |
 Sarvam STT -> Gemini (tool calling) -> Sarvam TTS
       |
 Twilio audio output
```

Relevant existing files include:

-   `app/main.py` --- creates the FastAPI app and registers routers.
-   `app/api/routes/twilio.py` --- incoming-call webhook and Twilio
    Media Streams WebSocket handling.
-   `app/voice/pipeline.py` --- builds the per-call Pipecat pipeline.
-   `app/voice/call_session.py` --- per-call state and clinic/call
    context.
-   `app/voice/prompts.py` --- receptionist system prompt.
-   `app/voice/tools.py` --- AI tool declarations and tool execution.
-   `app/api/routes/clinics.py` --- clinic creation and retrieval.
-   `app/api/routes/doctors.py` --- doctor management.
-   `app/api/routes/appointments.py` --- appointment availability and
    booking.
-   `app/api/routes/calls.py` --- call lookup.
-   `app/core/config.py` --- environment-based settings.
-   `requirements.txt` --- pinned dependencies, including
    `pipecat-ai[google,openai,sarvam,silero]==0.0.100`.
-   `README.md` --- local setup and known external-integration caveats.

The existing `app/voice/pipeline.py` constructs a
`TwilioFrameSerializer` and passes it to `FastAPIWebsocketTransport`.
That serializer is intended for Twilio's message/audio protocol. A
browser microphone does not send Twilio's `start`, `media`, and `stop`
events, so a normal browser WebSocket must not be pointed at the
existing Twilio-specific handler.

The project README also explicitly warns that Pipecat service and
transport constructor signatures, tool registration, and Twilio event
payloads need verification against the installed versions and live
provider APIs. The new implementation must be tested against the
project's pinned Pipecat version rather than copying code for a newer
release.

------------------------------------------------------------------------

## 3. Design: add a second transport, preserve the telephone path

Keep the production Twilio route unchanged. Add a separate local-test
route and pipeline/transport implementation.

``` text
                    Shared receptionist logic
             (prompt, tools, clinic, appointments)
                              |
                  +-----------+-----------+
                  |                       |
             Phone path                Local path
                  |                       |
               Twilio                 Browser page
                  |                       |
        Twilio Media Streams          Microphone
                  |                       |
        Twilio serializer             Local audio transport
                  |                       |
                  +------> Pipecat <------+
                              |
                      Sarvam STT
                              |
                           Gemini
                              |
                       Sarvam TTS
                              |
                  +-----------+-----------+
                  |                       |
            Twilio audio             Browser audio
```

### Requirements for the design

-   Do not remove or break `/twilio/voice`.
-   Do not make the browser pretend to be Twilio.
-   Reuse the current prompt, tool executor, and appointment services
    rather than duplicating business rules.
-   Create a fresh session and pipeline for each local test.
-   Do not put call/session state in global mutable variables.
-   Use a fixed, explicitly configured development clinic ID or a safe
    development-only clinic selector.
-   Do not accept arbitrary clinic IDs from unauthenticated users in a
    deployed environment.
-   Keep local testing restricted to localhost unless there is a
    specific, secured reason to expose it.
-   Do not log API keys, raw credentials, or unnecessary patient
    information.

------------------------------------------------------------------------

## 4. Recommended implementation approach

There are two reasonable options. Prefer **Option A** if the pinned
Pipecat version supports a suitable WebSocket transport and serializer
for the intended browser audio format. Use Option B as a fallback if
browser audio transport integration becomes too complicated.

### Option A --- Browser UI with a local WebSocket audio transport

Create a small local web page with Start, Stop, microphone status,
connection status, transcript, and playback controls. Use browser audio
capture and playback, with a WebSocket endpoint dedicated to the local
test.

This offers the simplest user experience once implemented, but audio
encoding, sample rate, framing, and Pipecat transport compatibility must
be handled explicitly.

### Option B --- First validate the pipeline with a controlled audio test

Before building a polished interface, add a development-only test
harness that can send known audio input through the STT/LLM/TTS chain
and verify output. This can help isolate provider credentials and
service integration issues from browser audio problems. It is useful for
debugging but is not, by itself, a live conversational microphone demo.

**Recommended delivery sequence:** first verify the existing provider
pipeline can initialize; then build the local audio transport; then add
the browser UI. Avoid installing unrelated audio packages or upgrading
Pipecat until the existing pinned version and APIs have been checked.

------------------------------------------------------------------------

## 5. Files to add or modify

Suggested file layout:

``` text
voice-receptionist/
├── app/
│   ├── api/
│   │   └── routes/
│   │       ├── twilio.py              # Keep existing production route
│   │       └── local_voice_test.py    # New, development-only route
│   ├── voice/
│   │   ├── pipeline.py                # Existing Twilio-specific pipeline
│   │   ├── local_pipeline.py           # New local transport pipeline, if needed
│   │   ├── call_session.py             # Existing session model; extend carefully if required
│   │   ├── prompts.py                  # Reuse
│   │   └── tools.py                    # Reuse
│   └── main.py                         # Register local test router conditionally
├── local_voice_test/
│   ├── index.html                      # Local browser interface
│   ├── app.js                          # Microphone, WebSocket, playback, UI state
│   └── styles.css                      # Optional styling
└── tests/
    └── test_local_voice_test.py        # New tests for route restrictions/session setup
```

These are suggested names, not existing files. They should be adjusted
to match the actual project's import conventions.

### Keep changes isolated

Do not replace `app/voice/pipeline.py` wholesale. Its current transport
and Twilio serializer are needed for phone calls. If common logic needs
to be shared, extract a small helper that builds the provider services,
prompt, tool executor, and aggregators, while allowing each transport to
be configured separately. Make sure any refactor preserves existing
behavior and per-call isolation.

------------------------------------------------------------------------

## 6. Implementation steps

### Step 1 --- Make a safe working copy

1.  Stop the running server with `Ctrl+C` if needed.
2.  Commit the current working state to Git or copy the project folder
    as a backup.
3.  Check that `.env` is excluded by `.gitignore`.
4.  Never upload `.env` or paste its values into chats/issues.
5.  If credentials in a shared archive were real and the archive was
    distributed beyond this private conversation, rotate the affected
    keys in the provider dashboards.

From PowerShell, in the project folder:

``` powershell
git status
```

If the project is already under Git, commit or back up the working state
before editing.

### Step 2 --- Verify the environment and installed Pipecat version

Activate the existing virtual environment:

``` powershell
.venv\Scripts\Activate.ps1
```

Check the Python and Pipecat versions:

``` powershell
python --version
python -c "import pipecat; print(getattr(pipecat, '__version__', 'version attribute unavailable'))"
python -m pip show pipecat-ai
```

Inspect the transport modules available in the installed version:

``` powershell
python -c "import pipecat.transports.network.fastapi_websocket as m; print([n for n in dir(m) if 'Transport' in n or 'Params' in n])"
python -c "import pipecat.serializers as s; print(dir(s))"
```

The project's requirements pin Pipecat `0.0.100`. Do not upgrade it as a
first troubleshooting step. Confirm which transport and serializer APIs
actually exist in that environment before writing the local pipeline.

### Step 3 --- Verify required environment variables

Check the variable names in `.env.example` and `app/core/config.py`. For
the provider pipeline, the code references Sarvam and Google/Gemini API
keys. The existing Twilio path additionally needs the appropriate Twilio
configuration.

For a local voice test:

-   Sarvam credentials are needed if live Sarvam STT/TTS is used.
-   Google/Gemini credentials are needed if live Gemini responses are
    used.
-   A Twilio phone number and Twilio call SID should not be required for
    the local browser path.
-   Database configuration must support the existing app's local SQLite
    setup, unless the developer has intentionally configured another
    database.

Never put actual secrets in source files or frontend JavaScript. The
browser must never receive provider API keys.

### Step 4 --- Verify the current backend

Start the app using the project's existing instructions:

``` powershell
uvicorn app.main:app --reload
```

Open:

-   `http://127.0.0.1:8000/health`
-   `http://127.0.0.1:8000/docs`

Use the `GET /health` endpoint's Try it out / Execute controls. A
successful HTTP response confirms that the API is reachable; it does not
confirm that the external STT, LLM, TTS, or audio pipeline works.

Review terminal logs for startup errors before continuing.

### Step 5 --- Create or identify a development clinic

The OpenAPI document includes:

-   `POST /api/clinics`
-   `GET /api/clinics/{clinic_id}`
-   `POST /api/clinics/{clinic_id}/doctors`
-   `GET /api/clinics/{clinic_id}/doctors`
-   `POST /api/appointments/availability`
-   `POST /api/appointments/book`

Create a clinic only if a suitable development clinic does not already
exist. Management endpoints support an optional `x-api-key` header
according to the OpenAPI schema and application configuration.

Example development clinic request body:

``` json
{
  "name": "Local Demo Clinic",
  "timezone": "Asia/Kolkata",
  "config": {
    "greeting": "Thank you for calling Local Demo Clinic. How can I help you today?",
    "supported_languages": ["en-IN"],
    "appointment_provider": "crudoc",
    "appointment_provider_config": {}
  }
}
```

Use the returned clinic UUID for the local test configuration. Avoid
creating duplicate clinics on every run.

Add a development doctor if needed:

``` json
{
  "name": "Dr. Rahul",
  "specialization": "General Physician"
}
```

The actual appointment booking integration may require valid provider
configuration and an external doctor ID. Do not assume booking will
succeed until that integration has been verified.

### Step 6 --- Add a development-only local test route

Add a separate router, for example `app/api/routes/local_voice_test.py`,
with a WebSocket endpoint such as `/voice-test/ws`.

The route should:

1.  Reject connections when the app is not in a development/test
    environment.
2.  Accept a WebSocket connection using the correct FastAPI/Starlette
    lifecycle.
3.  Validate the configured development clinic exists.
4.  Create a fresh local `CallSession` with a generated local call ID
    and a clear marker such as `local-browser`.
5.  Avoid requiring a Twilio call SID or inbound telephone number.
6.  Start a dedicated local pipeline/transport.
7.  Close and clean up the pipeline, session, database resources, and
    WebSocket on disconnect or error.
8.  Log session start/end and safe diagnostic details.

Do not use the production `/twilio/media-stream/{clinic_id}` endpoint
for the browser. The production handler expects Twilio Media Streams
events and payloads, which a normal browser microphone does not
generate.

If `CallSession` currently assumes a real Twilio call SID, adjust the
model or introduce a local session adapter in a way that keeps
production phone-call validation intact. Do not invent a fake Twilio SID
and pass it into code that can trigger actual call-transfer APIs.

### Step 7 --- Build a transport-compatible local pipeline

The current `app/voice/pipeline.py` constructs:

-   `TwilioFrameSerializer`
-   `FastAPIWebsocketTransport`
-   `SarvamSTTService`
-   `GoogleLLMService`
-   `SarvamTTSService`
-   `HardFallbackMonitor`
-   LLM context aggregators
-   `ToolExecutor`
-   `Pipeline`, `PipelineTask`, and `PipelineRunner`

The local pipeline should preserve the provider/service logic and tool
execution but use an audio transport and serialization format that
matches the browser client.

Before implementing, verify the installed Pipecat `0.0.100` API for:

-   WebSocket transport class and parameters
-   Available serializer classes and supported audio formats
-   Input/output audio sample rate and frame formats
-   Pipeline startup and shutdown behavior
-   Service initialization signatures
-   Tool/function registration API
-   How initial assistant greetings are emitted
-   How user interruptions and VAD are handled

Do not assume a raw PCM WebSocket will automatically work with the
existing `TwilioFrameSerializer`. It will not: the serializer and
message format must match the chosen client protocol.

Reuse `build_system_prompt(session.clinic)`, the existing tool
declarations/dispatch, and appointment services where possible. Each
local conversation must get its own prompt/context, pipeline task, and
call session. Avoid sharing message history between sessions.

### Step 8 --- Decide the browser audio protocol

Document a simple protocol before writing frontend and backend code. For
example:

-   Client-to-server messages carry audio frames in a documented binary
    format.
-   Server-to-client messages carry audio frames in a documented output
    format.
-   Optional text events carry transcript updates, assistant text,
    errors, and connection state.
-   The server validates frame sizes, audio format, and message types.
-   The browser and server agree on sample rate, channel count, PCM
    encoding, and chunk duration.

Do not send JSON-encoded audio data unless there is a specific reason;
base64 can increase payload size. Binary WebSocket frames are often more
efficient, but only use them if the chosen transport supports them
cleanly.

The browser's Web Audio API may expose audio at a sample rate different
from the provider's required sample rate. Resampling and channel
conversion may be required. Do not merely relabel the sample rate
without actually resampling the audio.

### Step 9 --- Create the browser UI

Add `local_voice_test/index.html`, `app.js`, and optionally
`styles.css`.

The UI should include:

-   A Start conversation button
-   A Stop conversation button
-   Microphone permission and activity status
-   WebSocket connection status
-   A transcript display for recognized user speech
-   A display of the assistant's response text, if available
-   Audio playback for assistant speech
-   An error/status area
-   A clear indication that this is a local development test, not a real
    phone call

Browser requirements:

1.  Request microphone access only after the user clicks Start.
2.  Connect to the local WebSocket endpoint.
3.  Capture audio using the agreed audio format and sample rate.
4.  Send audio frames with suitable chunking and backpressure handling.
5.  Receive assistant audio and play it in the correct order.
6.  Stop microphone tracks, audio processing nodes, WebSocket, and
    playback when Stop is clicked or the page is closed.
7.  Handle permissions denied, server disconnects, empty audio, and
    provider failures.
8.  Avoid placing provider credentials in JavaScript.

Serve the page through the FastAPI app or a simple local development
server. If the frontend is served from a separate origin, configure
local CORS/WebSocket access deliberately. Browser microphone access
generally works on `localhost`/`127.0.0.1` in a secure local context; do
not expose the page publicly for this test.

### Step 10 --- Add a safe local greeting

The existing call pipeline creates a system prompt and conversation
aggregators, but the implementation must explicitly verify how the first
greeting is triggered in the pinned Pipecat version.

The local session should start with the configured clinic greeting, for
example:

> Thank you for calling Local Demo Clinic. How can I help you today?

Do not assume setting the system prompt automatically causes the model
to speak first. Use the supported initial-message mechanism for the
installed Pipecat version, and test that the greeting is generated once
per session.

### Step 11 --- Test in small stages

Do not test every feature at once.

**Test A: backend health** - Start FastAPI. - Confirm `/health` returns
a success response. - Confirm the local test route is registered only in
development mode.

**Test B: browser connection** - Open the local test page. - Grant
microphone access. - Confirm WebSocket connection status becomes
connected. - Click Stop and confirm all browser audio resources are
released.

**Test C: audio capture** - Speak a short sentence. - Confirm audio
reaches the server. - Confirm the server receives valid frames at the
expected sample rate and format. - Confirm there are no continuously
growing queues or blocked event loops.

**Test D: speech recognition** - Verify Sarvam returns a non-empty
transcription. - Test a quiet sentence and a normal speaking volume. -
Verify empty/unintelligible speech does not create an infinite retry
loop.

**Test E: LLM response** - Verify Gemini receives the transcript and
produces a response. - Confirm clinic-specific prompt instructions are
applied. - Confirm there is no cross-session conversation history.

**Test F: speech generation** - Verify Sarvam TTS generates audio. -
Confirm the browser can decode/play the response. - Confirm audio chunks
are ordered and do not overlap unexpectedly.

**Test G: complete conversation** Try: - "Hello, what can you help me
with?" - "I want to book an appointment." - "What times are
available?" - "Can you repeat that?" - A short Hindi sentence, only
after Hindi is explicitly configured and tested.

**Test H: tools and booking** - Test appointment availability using a
valid clinic and doctor. - Only test actual booking against a
development/test appointment provider. - Confirm booking result and
database state. - Confirm an invalid or unavailable slot is handled
safely. - Avoid creating real patient appointments during testing.

**Test I: resilience** - Deny microphone permission. - Disconnect the
browser during a response. - Simulate missing/invalid provider
credentials. - Send silence and unintelligible audio. - Restart the
server during a session. - Confirm cleanup and error messages are clear.

### Step 12 --- Add automated tests

Add tests for:

-   Local voice-test route is disabled outside development/test mode.
-   Missing/invalid development clinic is rejected.
-   Each connection creates a separate session and conversation context.
-   Disconnect triggers cleanup.
-   No local test path calls Twilio transfer or outbound telephone APIs.
-   Invalid audio messages are rejected.
-   Existing Twilio routes still register and existing tests continue to
    pass.

Run the existing test suite:

``` powershell
pytest
```

The README states that the existing tests cover tenant isolation, clinic
resolution, booking race handling, and transfer fallback, but do not
fully integration-test the live Pipecat pipeline. Keep that limitation
in mind.

------------------------------------------------------------------------

## 7. Security and operational constraints

This is a development-only test, not a production voice service.

-   Bind the service to localhost for local testing.
-   Do not expose an unauthenticated local test endpoint to the public
    internet.
-   Do not accept arbitrary clinic IDs without authorization.
-   Do not let local tests trigger real phone transfers.
-   Do not use production patient records or real patient details in
    test conversations.
-   Avoid storing raw microphone recordings unless explicitly needed and
    consented to.
-   Keep provider keys on the server.
-   Rotate credentials if they have been exposed outside a trusted
    environment.
-   Do not commit `.env`; commit `.env.example` with placeholder values
    only.
-   Add limits for message size, audio duration, concurrent local
    sessions, and session lifetime.

------------------------------------------------------------------------

## 8. Cost expectations

No Twilio phone number is needed for this local test. However, **"no
phone number" does not mean "all usage is free."**

-   Sarvam STT/TTS may incur charges or require a funded account.
-   Gemini usage may incur charges or be subject to account quotas.
-   Local CPU usage is expected for browser capture and audio handling.
-   A local test can be run with a limited number of short conversations
    to control provider usage.

Check current provider pricing and quotas before doing extended testing.

------------------------------------------------------------------------

## 9. Acceptance criteria

The local voice test is complete when all of the following are true:

-   [ ] Existing `/health` and `/docs` still work.
-   [ ] Existing Twilio webhook and Media Streams routes are unchanged
    and existing tests pass.
-   [ ] A development-only browser test page loads locally.
-   [ ] The browser can request and release microphone access.
-   [ ] Audio travels from browser to backend using the documented
    protocol.
-   [ ] Sarvam STT transcribes a spoken sentence.
-   [ ] Gemini generates a response using the correct clinic prompt.
-   [ ] Sarvam TTS generates a spoken reply.
-   [ ] The browser plays the reply intelligibly.
-   [ ] Multiple local sessions do not share conversation state.
-   [ ] Local sessions cannot initiate real Twilio calls or transfers.
-   [ ] Provider errors and browser disconnects clean up resources.
-   [ ] Appointment tools are tested only with a safe development
    provider.
-   [ ] No provider credentials are exposed to the browser or committed
    to Git.

------------------------------------------------------------------------

## 10. Troubleshooting guide

  -----------------------------------------------------------------------
  Symptom                             What to check
  ----------------------------------- -----------------------------------
  `/health` works but voice test does Confirm the new WebSocket route is
  not connect                         registered and the frontend uses
                                      the correct
                                      `ws://127.0.0.1:8000/...` URL.

  Browser microphone permission fails Use localhost, click Start before
                                      requesting the microphone, and
                                      check browser permissions.

  Connection opens but STT receives   Check binary frame handling, sample
  no text                             rate, encoding, VAD, and Sarvam
                                      credentials.

  STT works but there is no AI        Check Gemini credentials, service
  response                            initialization, context
                                      aggregation, and provider logs.

  AI text exists but no sound plays   Check TTS output format, audio
                                      framing, sample rate, browser
                                      playback initialization, and audio
                                      queue handling.

  Audio is too fast, slow, or         Check whether the client and server
  distorted                           agree on sample rate, channels, PCM
                                      encoding, and actual resampling.

  Greeting never plays                Verify the initial-message
                                      mechanism supported by the
                                      installed Pipecat version.

  Appointment lookup fails            Check clinic/doctor IDs, provider
                                      configuration, external doctor ID,
                                      and appointment provider adapter.

  Local test tries to transfer a call Fix the local session/transfer
                                      boundary; do not use fake Twilio
                                      IDs with production transfer code.

  Changes break phone calls           Restore the previous
                                      Twilio-specific pipeline and keep
                                      the local transport separate.
  -----------------------------------------------------------------------

------------------------------------------------------------------------

## 11. Recommended development order

Implement in this order:

1.  Back up the current project.
2.  Verify Python and pinned Pipecat version.
3.  Verify local health endpoint and existing tests.
4.  Confirm a development clinic and doctor exist.
5.  Verify provider initialization with a minimal integration test.
6.  Implement the development-only local WebSocket route.
7.  Implement the local pipeline using a transport/serializer supported
    by the installed Pipecat version.
8.  Implement browser audio capture and playback.
9.  Test STT, LLM, and TTS independently.
10. Test a complete conversation.
11. Test appointment tools with safe test data.
12. Run all existing tests and regression-test the Twilio path.
13. Only after local testing works, buy/configure a Twilio number and
    test actual inbound calls.

------------------------------------------------------------------------

## 12. What must be verified before writing version-specific code

The supplied README itself warns that the Pipecat service and transport
signatures must be checked against the installed package. Before writing
exact implementation code, collect:

``` powershell
python --version
python -m pip show pipecat-ai
python -c "import pipecat.transports.network.fastapi_websocket as m; print([n for n in dir(m) if 'Transport' in n or 'Params' in n])"
python -c "import pipecat.serializers as s; print(dir(s))"
```

Also inspect the installed package's documentation/source for the
available browser-compatible or generic WebSocket transport, supported
serializer formats, and audio frame sample-rate requirements. Do not
blindly copy examples for a newer Pipecat release.

The exact implementation should be written only after these facts are
confirmed. This prevents an incompatible serializer, audio protocol, or
transport API from breaking the current phone implementation.

------------------------------------------------------------------------

## Final outcome

The intended result is a **local browser-based voice demo** that
exercises the same receptionist behavior without a purchased telephone
number. It should reuse clinic configuration, prompt construction,
provider services, and appointment logic, while keeping the
Twilio-specific audio transport isolated.

The existing API being healthy is a useful starting point, but it does
not by itself prove the live voice pipeline works. Validate the provider
integrations, transport format, browser audio, and session lifecycle
separately before treating the local test as complete.
