"""
Local browser testing Pipecat pipeline construction.

Wires FastAPIWebsocketTransport with LocalPcmSerializer (PCM16 16kHz In / 24kHz Out),
Sarvam STT, Google Gemini LLM, Sarvam TTS, and local CallSession isolation.
Safe for development use without requiring a Twilio phone number or outbound telephony.

Service construction is shared with the Twilio pipeline (app/voice/pipeline.py)
so provider argument shapes only have to be correct in one place.
"""
import asyncio

from fastapi import WebSocket
from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.frames.frames import TranscriptionFrame, TTSTextFrame
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.transports.websocket.fastapi import (
    FastAPIWebsocketParams,
    FastAPIWebsocketTransport,
)

from app.core.config import get_settings
from app.core.logging import get_logger
from app.db.postgres import db_session
from app.services import call_service
from app.voice.call_session import CallSession, CallStatus
from app.voice.local_audio_serializer import LocalPcmSerializer
from app.voice.pipeline import (
    HardFallbackMonitor,
    build_llm_context,
    build_voice_services,
    queue_greeting,
)
from app.voice.tools import ToolExecutor

logger = get_logger(component="local_voice_pipeline")


class TranscriptRelay(FrameProcessor):
    """Send transcript text to the browser.

    The WebSocket output transport only serializes audio frames, so
    TranscriptionFrame/TTSTextFrame never reach the serializer -- without
    this relay the test UI shows audio but no conversation text.
    """

    def __init__(self, websocket: WebSocket):
        super().__init__()
        self._websocket = websocket

    async def process_frame(self, frame, direction: FrameDirection):
        await super().process_frame(frame, direction)

        role = None
        if isinstance(frame, TranscriptionFrame):
            role = "user"
        elif isinstance(frame, TTSTextFrame):
            role = "assistant"

        if role and (frame.text or "").strip():
            try:
                await self._websocket.send_json(
                    {"type": "transcript", "role": role, "text": frame.text}
                )
            except Exception:  # noqa: BLE001 -- never break the call over the UI
                pass

        await self.push_frame(frame, direction)


async def run_local_pipeline(websocket: WebSocket, session: CallSession) -> None:
    """Build and run an isolated Pipecat pipeline for a browser-based local voice session."""
    settings = get_settings()

    serializer = LocalPcmSerializer()

    transport = FastAPIWebsocketTransport(
        websocket=websocket,
        params=FastAPIWebsocketParams(
            audio_in_enabled=True,
            audio_out_enabled=True,
            add_wav_header=False,
            vad_analyzer=SileroVADAnalyzer(),
            serializer=serializer,
        ),
    )

    stt, tts, llm = build_voice_services(session)

    async with db_session() as db:
        # No Twilio call leg exists for a browser session, so phone transfers can
        # never work here; real provider bookings are opt-in via env.
        tool_executor = ToolExecutor(
            db=db, session=session, allow_external_actions=settings.local_voice_test_allow_booking
        )
        context, aggregators = build_llm_context(llm, tool_executor)
        # allow_transfer=False ensures local browser test sessions never attempt Twilio phone transfers
        fallback_monitor = HardFallbackMonitor(session, settings.stt_failure_threshold, allow_transfer=False)

        transcripts = TranscriptRelay(websocket)

        pipeline = Pipeline(
            [
                transport.input(),
                stt,
                transcripts,
                fallback_monitor,
                aggregators.user(),
                llm,
                tts,
                TranscriptRelay(websocket),
                transport.output(),
                aggregators.assistant(),
            ]
        )

        task = PipelineTask(pipeline, params=PipelineParams(allow_interruptions=True))
        runner = PipelineRunner()


        @transport.event_handler("on_client_disconnected")
        async def on_client_disconnected(_transport, _client) -> None:
            """End the pipeline when the caller goes away.

            Without this the PipelineTask keeps running after the socket
            closes: `runner.run()` never returns, the session's teardown never
            executes, and its call record is stranded in "in_progress".
            """
            logger.info("local_voice_client_disconnected", call_id=str(session.call_id))
            await task.cancel()

        @transport.event_handler("on_session_timeout")
        async def on_session_timeout(_transport, _client) -> None:
            logger.warning("local_voice_session_timeout", call_id=str(session.call_id))
            await task.cancel()

        @task.event_handler("on_pipeline_error")
        async def on_pipeline_error(_task, frame) -> None:
            """Surface provider errors in the browser.

            ErrorFrames travel upstream to the task, so they never pass through
            the output serializer -- without this a failed STT/LLM/TTS call is
            invisible to the tester and looks like an unexplained silence.
            """
            detail = str(getattr(frame, "error", frame))
            logger.error(
                "local_pipeline_provider_error",
                call_id=str(session.call_id),
                fatal=bool(getattr(frame, "fatal", False)),
                error=detail,
            )
            try:
                await websocket.send_json(
                    {
                        "type": "error",
                        "message": detail,
                        "fatal": bool(getattr(frame, "fatal", False)),
                    }
                )
            except Exception:  # noqa: BLE001 -- the socket may already be gone
                pass

        logger.info(
            "local_pipeline_started",
            call_id=str(session.call_id),
            clinic_id=str(session.clinic.clinic_id),
            caller=session.caller_phone,
        )

        # Notify browser of the connected clinic name
        try:
            await websocket.send_json({"type": "clinic", "name": session.clinic.name})
        except Exception:
            pass

        greeting_task = asyncio.create_task(queue_greeting(task, session))

        try:
            await runner.run(task)
        finally:
            greeting_task.cancel()
            outcome = "transferred" if session.status == CallStatus.TRANSFERRED else "completed"
            # Logged before the DB write, which re-raises if this task is
            # already being cancelled.
            logger.info(
                "local_pipeline_ended",
                call_id=str(session.call_id),
                clinic_id=str(session.clinic.clinic_id),
                outcome=outcome,
            )
            if session.db_call_record_id:
                # Teardown often runs under cancellation (the caller hung up),
                # so this must not rely on the call's own DB session.
                await call_service.finalize_call_record_shielded(
                    session.db_call_record_id, outcome=outcome
                )
