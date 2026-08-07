#
# CruDoc AI Voice Receptionist — Pipecat Pipeline
#
# Answers incoming phone calls via Twilio, converses using Sarvam AI
# (STT/TTS) and Google Gemini (LLM), and either books an appointment
# into CruDoc or transfers the call to a human receptionist.
#
# Run locally:
#   uv run bot.py -t twilio -x your-ngrok-domain.ngrok.io
#

import asyncio
import os
import sys

if sys.stdout and hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import aiohttp
from dotenv import load_dotenv
from loguru import logger
from twilio.rest import Client as TwilioClient

from pipecat.adapters.schemas.function_schema import FunctionSchema
from pipecat.adapters.schemas.tools_schema import ToolsSchema
from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.frames.frames import (
    Frame,
    LLMFullResponseEndFrame,
    TranscriptionFrame,
)
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor
from pipecat.services.google.llm import GoogleLLMService
from pipecat.services.llm_service import FunctionCallParams
from pipecat.services.sarvam.stt import SarvamSTTService
from pipecat.services.sarvam.tts import SarvamTTSService
from pipecat.transports.base_transport import BaseTransport
from pipecat.transports.websocket.fastapi import (
    FastAPIWebsocketParams,
    FastAPIWebsocketTransport,
)
from pipecat.serializers.twilio import TwilioFrameSerializer
from pipecat.transcriptions.language import Language
from pipecat.runner.types import RunnerArguments, WebSocketRunnerArguments
from pipecat.runner.utils import parse_telephony_websocket

load_dotenv(override=True)

# ── Twilio client (for live call transfer) ──────────────────────────
twilio_client = TwilioClient(
    os.getenv("TWILIO_ACCOUNT_SID"),
    os.getenv("TWILIO_AUTH_TOKEN"),
)
RECEPTIONIST_NUMBER = os.getenv("RECEPTIONIST_NUMBER", "")
CRUDOC_APPOINTMENTS_API = os.getenv("CRUDOC_APPOINTMENTS_API", "")
CRUDOC_DOCTOR_ID = os.getenv("CRUDOC_DOCTOR_ID", "")
VOICE_BOT_API_KEY = os.getenv("VOICE_BOT_API_KEY", "")

# ── LLM system prompt ──────────────────────────────────────────────
SYSTEM_PROMPT = (
    "You are the friendly phone receptionist for CruDoc, a medical practice. "
    "Your job is to greet the caller warmly, find out why they are calling, "
    "and help them book an appointment if that is what they need.\n\n"
    "RULES:\n"
    "1. Start by greeting: 'Hello, thank you for calling CruDoc! How can I help you today?'\n"
    "2. If the caller wants to book an appointment, collect:\n"
    "   - Their full name\n"
    "   - Their preferred date\n"
    "   - Their preferred time\n"
    "   - (Optional) the reason for their visit\n"
    "3. Once you have name, date, and time, confirm the details with the caller, "
    "then call the book_appointment function.\n"
    "4. After booking, tell the caller their appointment is confirmed and wish them well.\n"
    "5. NEVER ask the caller for their phone number — you already have it.\n"
    "6. If you cannot understand the caller after asking them to repeat twice, "
    "call transfer_to_receptionist with reason 'Could not understand caller'.\n"
    "7. If the caller explicitly asks to speak to a person, a human, or a real receptionist, "
    "call transfer_to_receptionist immediately.\n"
    "8. Keep your responses concise and natural — this is a phone call, not a text chat.\n"
    "9. For dates, interpret relative references like 'tomorrow', 'next Monday', etc. "
    "relative to the current date. Format the date as YYYY-MM-DD when calling the tool.\n"
    "10. For times, accept natural language like '10 in the morning' or '2:30 PM' "
    "and format as HH:MM (24-hour) when calling the tool.\n"
)

# ── Tool definitions ────────────────────────────────────────────────
TOOLS = ToolsSchema(
    standard_tools=[
        FunctionSchema(
            name="book_appointment",
            description=(
                "Book an appointment once you have the caller's name, "
                "preferred date, and preferred time. The caller's phone "
                "number is provided automatically — never ask for it."
            ),
            properties={
                "name": {
                    "type": "string",
                    "description": "The caller's full name",
                },
                "date": {
                    "type": "string",
                    "description": "Appointment date in YYYY-MM-DD format",
                },
                "time": {
                    "type": "string",
                    "description": "Appointment time in HH:MM 24-hour format",
                },
                "reason": {
                    "type": "string",
                    "description": "Optional reason for the visit",
                },
            },
            required=["name", "date", "time"],
        ),
        FunctionSchema(
            name="transfer_to_receptionist",
            description=(
                "Transfer the call to a human receptionist. Use this when "
                "you cannot understand the caller after repeated attempts, "
                "or when the caller explicitly asks for a person."
            ),
            properties={
                "reason": {
                    "type": "string",
                    "description": "Why the call is being transferred",
                },
            },
            required=["reason"],
        ),
    ]
)


# ── Hard-fallback processor ────────────────────────────────────────
# Monitors STT output for consecutive empty / low-confidence results.
# When the count hits the threshold, it bypasses the LLM and triggers
# a direct Twilio call transfer — the LLM can be flaky, so we never
# rely on it alone for this safety net.

class STTFallbackMonitor(FrameProcessor):
    """Watches TranscriptionFrames for consecutive empty/low-confidence
    results and triggers an automatic call transfer when the threshold
    is reached."""

    EMPTY_THRESHOLD = 2  # consecutive empty results before transfer

    def __init__(self, call_sid: str, **kwargs):
        super().__init__(**kwargs)
        self._call_sid = call_sid
        self._consecutive_empty = 0
        self._transferred = False

    async def process_frame(self, frame: Frame, direction: FrameDirection):
        await super().process_frame(frame, direction)

        if isinstance(frame, TranscriptionFrame) and not self._transferred:
            text = (frame.text or "").strip()
            if len(text) == 0:
                self._consecutive_empty += 1
                logger.warning(
                    f"STT empty result #{self._consecutive_empty} "
                    f"(threshold: {self.EMPTY_THRESHOLD})"
                )
                if self._consecutive_empty >= self.EMPTY_THRESHOLD:
                    logger.warning(
                        "Hard fallback triggered — transferring call "
                        "to receptionist due to consecutive empty STT"
                    )
                    self._transferred = True
                    await self._force_transfer()
            else:
                # Reset counter on any non-empty transcription
                self._consecutive_empty = 0

        # Always pass the frame through regardless
        await self.push_frame(frame, direction)

    async def _force_transfer(self):
        """Redirect the live Twilio call to the receptionist number."""
        if not RECEPTIONIST_NUMBER:
            logger.error(
                "RECEPTIONIST_NUMBER not configured — cannot transfer"
            )
            return
        try:
            twilio_client.calls(self._call_sid).update(
                twiml=(
                    f'<Response><Say>I\'m having trouble understanding. '
                    f'Let me connect you with our receptionist.</Say>'
                    f'<Dial>{RECEPTIONIST_NUMBER}</Dial></Response>'
                )
            )
            logger.info(f"Hard-fallback transfer initiated for call {self._call_sid}")
        except Exception as e:
            logger.error(f"Failed to transfer call: {e}")


# ── Tool handler functions ──────────────────────────────────────────

def make_book_appointment(caller_number: str):
    """Factory: creates the book_appointment handler closed over the
    caller's phone number (from Twilio, never asked verbally)."""

    async def book_appointment(params: FunctionCallParams):
        name = params.arguments.get("name", "")
        date = params.arguments.get("date", "")
        time = params.arguments.get("time", "")
        reason = params.arguments.get("reason", "")

        logger.info(
            f"Booking appointment: name={name}, date={date}, "
            f"time={time}, reason={reason}, phone={caller_number}"
        )

        try:
            async with aiohttp.ClientSession() as session:
                headers = {
                    "Content-Type": "application/json",
                    "X-Api-Key": VOICE_BOT_API_KEY,
                }
                payload = {
                    "patient_name": name,
                    "phone": caller_number,
                    "date": date,
                    "time": time,
                    "reason": reason,
                    "source": "ai_receptionist",
                    "doctor_id": CRUDOC_DOCTOR_ID,
                }
                async with session.post(
                    CRUDOC_APPOINTMENTS_API,
                    json=payload,
                    headers=headers,
                ) as resp:
                    body = await resp.json()
                    if resp.status == 201 and body.get("success"):
                        logger.info(
                            f"Appointment created: {body.get('appointment_id')}"
                        )
                        await params.result_callback(
                            {"status": "booked", "appointment_id": body.get("appointment_id")}
                        )
                    else:
                        error = body.get("error", "Unknown error")
                        logger.error(f"Appointment API error: {error}")
                        await params.result_callback(
                            {"status": "error", "message": error}
                        )
        except Exception as e:
            logger.error(f"Failed to call appointments API: {e}")
            await params.result_callback(
                {"status": "error", "message": str(e)}
            )

    return book_appointment


def make_transfer_to_receptionist(call_sid: str):
    """Factory: creates the transfer handler closed over the Twilio
    call SID."""

    async def transfer_to_receptionist(params: FunctionCallParams):
        reason = params.arguments.get("reason", "Caller requested transfer")
        logger.info(f"Transferring call {call_sid}: {reason}")

        if not RECEPTIONIST_NUMBER:
            logger.error("RECEPTIONIST_NUMBER not configured")
            await params.result_callback(
                {"status": "error", "message": "Receptionist number not configured"}
            )
            return

        try:
            twilio_client.calls(call_sid).update(
                twiml=(
                    f'<Response><Say>Let me connect you with our receptionist. '
                    f'Please hold.</Say>'
                    f'<Dial>{RECEPTIONIST_NUMBER}</Dial></Response>'
                )
            )
            await params.result_callback({"status": "transferring"})
        except Exception as e:
            logger.error(f"Transfer failed: {e}")
            await params.result_callback(
                {"status": "error", "message": str(e)}
            )

    return transfer_to_receptionist


# ── Main bot entry point ────────────────────────────────────────────

async def bot(args: RunnerArguments):
    """Entry point called by the Pipecat development runner.

    For telephony transports the runner passes a WebSocketRunnerArguments
    containing the raw WebSocket connection from Twilio.
    """
    if not isinstance(args, WebSocketRunnerArguments):
        logger.error("Expected WebSocketRunnerArguments (telephony transport)")
        return

    # Parse the Twilio WebSocket to extract call metadata
    transport_type, call_data = await parse_telephony_websocket(args.websocket)
    logger.info(f"Transport: {transport_type}, Call data: {call_data}")

    call_sid = getattr(call_data, "call_id", "") or ""
    caller_number = getattr(call_data, "caller_number", "") or getattr(call_data, "from_number", "") or ""
    logger.info(f"Call SID: {call_sid}, Caller: {caller_number}")

    # ── Transport ───────────────────────────────────────────────
    transport = FastAPIWebsocketTransport(
        websocket=args.websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_out_enabled=True,
            add_wav_header=False,
            vad_enabled=True,
            vad_analyzer=SileroVADAnalyzer(),
            serializer=TwilioFrameSerializer(),
        ),
    )

    # ── AI Services ─────────────────────────────────────────────
    stt = SarvamSTTService(
        api_key=os.getenv("SARVAM_API_KEY", ""),
    )

    tts = SarvamTTSService(
        api_key=os.getenv("SARVAM_API_KEY", ""),
        params=SarvamTTSService.InputParams(
            language=Language.EN_IN,
        ),
    )

    llm = GoogleLLMService(
        api_key=os.getenv("GOOGLE_API_KEY", ""),
        model="gemini-2.5-flash",
    )

    # ── Register tool handlers ──────────────────────────────────
    llm.register_function(
        "book_appointment",
        make_book_appointment(caller_number),
    )
    llm.register_function(
        "transfer_to_receptionist",
        make_transfer_to_receptionist(call_sid),
    )

    # ── LLM Context ─────────────────────────────────────────────
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]
    context = LLMContext(messages=messages, tools=TOOLS)
    context_aggregator = llm.create_context_aggregator(context)

    # ── Hard-fallback STT monitor ───────────────────────────────
    stt_monitor = STTFallbackMonitor(call_sid=call_sid)

    # ── Pipeline ────────────────────────────────────────────────
    # The monitor sits between STT and the context aggregator so it
    # can count empty transcriptions before they reach the LLM.
    pipeline = Pipeline(
        [
            transport.input(),
            stt,
            stt_monitor,
            context_aggregator.user(),
            llm,
            tts,
            transport.output(),
            context_aggregator.assistant(),
        ]
    )

    task = PipelineTask(
        pipeline,
        params=PipelineParams(allow_interruptions=True),
    )

    # Kick off the conversation — the bot speaks first
    @transport.event_handler("on_client_connected")
    async def on_client_connected(transport, client):
        logger.info("Client connected — sending initial greeting")
        # Push an initial LLM run so the bot greets the caller
        await task.queue_frames(
            [context_aggregator.user().get_context_frame()]
        )

    runner = PipelineRunner()
    await runner.run(task)


# ── Dev-runner entry point ──────────────────────────────────────────

if __name__ == "__main__":
    from pipecat.runner.run import main
    main()
