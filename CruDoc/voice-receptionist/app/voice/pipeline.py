"""
Per-call Pipecat pipeline construction.

INTEGRATION BOUNDARY: this module wires Pipecat's FastAPIWebsocketTransport
(Twilio serializer), Sarvam STT/TTS services, and the Gemini LLM service
together. Pipecat's exact class names/constructor signatures move between
releases -- verify against the installed `pipecat-ai` version's current
docs before relying on this in production; the shape below (transport ->
STT -> context aggregator -> LLM w/ tools -> TTS -> transport, run per
call as an independent Pipeline/PipelineTask/PipelineRunner) reflects
Pipecat's standard per-call pattern, not a guess at unrelated APIs.

Each call to `run_call_pipeline` builds a brand-new Pipeline, PipelineTask
and set of services -- nothing here is module-level/shared state, which is
what gives every simultaneous caller full isolation (spec section 3).
"""
import asyncio
import uuid

from fastapi import WebSocket
from pipecat.audio.vad.silero import SileroVADAnalyzer
from pipecat.frames.frames import TranscriptionFrame, TTSSpeakFrame
from pipecat.pipeline.pipeline import Pipeline
from pipecat.pipeline.runner import PipelineRunner
from pipecat.pipeline.task import PipelineParams, PipelineTask
from pipecat.processors.aggregators.llm_context import LLMContext
from pipecat.processors.aggregators.llm_response_universal import LLMContextAggregatorPair
from pipecat.processors.frame_processor import FrameDirection, FrameProcessor
from pipecat.serializers.twilio import TwilioFrameSerializer
from pipecat.transports.websocket.fastapi import (
    FastAPIWebsocketParams,
    FastAPIWebsocketTransport,
)

from app.core.config import get_settings
from app.core.logging import get_logger
from app.db.postgres import db_session
from app.services import call_service, transfer_service
from app.voice.call_session import CallSession, CallStatus
from app.voice.prompts import build_system_prompt
from app.voice.tools import TOOL_DECLARATIONS, ToolExecutor
from app.voice.voices import resolve_language, resolve_speaker

logger = get_logger(component="voice_pipeline")

# Brief pause before the greeting so the output transport is streaming by
# the time the first TTS audio arrives.
GREETING_DELAY_SECS = 0.6


class HardFallbackMonitor(FrameProcessor):
    """
    Independent of Gemini: counts consecutive empty/unintelligible STT
    results on the CallSession and forces a transfer once the configured
    threshold is hit, regardless of what the LLM decides to do. This is
    what makes the fallback in spec section 11 not depend on the model.
    """

    def __init__(self, session: CallSession, threshold: int, allow_transfer: bool = True):
        super().__init__()
        self._session = session
        self._threshold = threshold
        self._allow_transfer = allow_transfer
        self._triggered = False

    async def process_frame(self, frame, direction: FrameDirection):
        await super().process_frame(frame, direction)

        if isinstance(frame, TranscriptionFrame):
            self._session.register_stt_result(frame.text)
            if self._session.consecutive_stt_failures >= self._threshold and not self._triggered:
                self._triggered = True
                logger.warning(
                    "hard_fallback_triggered",
                    call_id=str(self._session.call_id),
                    clinic_id=str(self._session.clinic.clinic_id),
                )
                if not self._allow_transfer:
                    logger.info("local_voice_fallback_transfer_disabled", call_id=str(self._session.call_id))
                    await self.push_frame(frame, direction)
                    return
                try:
                    await transfer_service.transfer_call(
                        self._session.twilio_call_sid,
                        self._session.clinic,
                        reason="repeated_stt_failure",
                    )
                    self._session.status = CallStatus.TRANSFERRED
                except transfer_service.TransferFailedError as exc:
                    logger.error("hard_fallback_transfer_failed", error=str(exc))

        await self.push_frame(frame, direction)


def build_voice_services(session: CallSession):
    """Construct this call's Sarvam STT, Sarvam TTS and Gemini services.

    Shared by the Twilio and local-browser pipelines so the provider
    argument shapes only have to be right in one place. Note that Sarvam's
    services take `language` inside their `InputParams`, not as a top-level
    kwarg -- a top-level `language=` is swallowed by `**kwargs` and silently
    ignored, leaving the call on the wrong language.
    """
    settings = get_settings()
    from pipecat.services.google.llm import GoogleLLMService
    from pipecat.services.sarvam.stt import SarvamSTTService
    from pipecat.services.sarvam.tts import SarvamTTSService

    language = resolve_language(session.clinic.supported_languages)
    speaker = resolve_speaker(session.clinic.voice_id, clinic_name=session.clinic.name)

    stt = SarvamSTTService(
        api_key=settings.sarvam_api_key,
        params=SarvamSTTService.InputParams(language=language),
    )
    tts = SarvamTTSService(
        api_key=settings.sarvam_api_key,
        model=settings.sarvam_tts_model,
        voice_id=speaker,
        params=SarvamTTSService.InputParams(language=language),
    )
    llm = GoogleLLMService(
        api_key=settings.google_api_key,
        model=settings.gemini_model,
        system_instruction=build_system_prompt(session.clinic),
    )
    return stt, tts, llm


def build_llm_context(llm, tool_executor: ToolExecutor):
    """Register this call's tools and build its context aggregator pair.

    The tool handler must take a single FunctionCallParams and return its
    result through `params.result_callback` -- see
    ToolExecutor.handle_function_call.
    """
    llm.register_function(None, tool_executor.handle_function_call)  # catch-all; dispatch routes by name

    context = LLMContext(messages=[], tools=TOOL_DECLARATIONS)
    return context, LLMContextAggregatorPair(context)


async def queue_greeting(task: PipelineTask, session: CallSession) -> None:
    """Speak the clinic greeting once the pipeline is ready.

    Without this the caller hears silence until they speak first, because
    nothing upstream has produced a turn for the LLM to answer yet.
    """
    greeting = (session.clinic.greeting or "").strip()
    if not greeting:
        return
    await asyncio.sleep(GREETING_DELAY_SECS)  # let the output transport come up
    try:
        await task.queue_frames([TTSSpeakFrame(text=greeting)])
    except Exception as exc:  # noqa: BLE001 -- a failed greeting must not kill the call
        logger.warning("greeting_dispatch_error", call_id=str(session.call_id), error=str(exc))


async def run_call_pipeline(websocket: WebSocket, session: CallSession, stream_sid: str) -> None:
    settings = get_settings()

    # account_sid/auth_token let the serializer hang up the Twilio leg when the
    # pipeline ends; without them the caller stays connected to dead air.
    serializer = TwilioFrameSerializer(
        stream_sid=stream_sid,
        call_sid=session.twilio_call_sid,
        account_sid=settings.twilio_account_sid,
        auth_token=settings.twilio_auth_token,
    )

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
        tool_executor = ToolExecutor(db=db, session=session)
        context, aggregators = build_llm_context(llm, tool_executor)
        fallback_monitor = HardFallbackMonitor(session, settings.stt_failure_threshold)

        pipeline = Pipeline(
            [
                transport.input(),
                stt,
                fallback_monitor,
                aggregators.user(),
                llm,
                tts,
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
            logger.info("call_client_disconnected", call_id=str(session.call_id))
            await task.cancel()

        @transport.event_handler("on_session_timeout")
        async def on_session_timeout(_transport, _client) -> None:
            logger.warning("call_session_timeout", call_id=str(session.call_id))
            await task.cancel()

        @task.event_handler("on_pipeline_error")
        async def on_pipeline_error(_task, frame) -> None:
            """ErrorFrames go upstream to the task, not through the pipeline, so
            a provider failure is otherwise only visible as caller silence."""
            logger.error(
                "call_pipeline_provider_error",
                call_id=str(session.call_id),
                clinic_id=str(session.clinic.clinic_id),
                fatal=bool(getattr(frame, "fatal", False)),
                error=str(getattr(frame, "error", frame)),
            )

        logger.info(
            "call_pipeline_started",
            call_id=str(session.call_id),
            clinic_id=str(session.clinic.clinic_id),
            caller=session.caller_phone,
        )

        greeting_task = asyncio.create_task(queue_greeting(task, session))

        try:
            await runner.run(task)
        finally:
            greeting_task.cancel()
            if session.status == CallStatus.TRANSFERRED:
                outcome = "transferred"
            elif session.appointments_booked:
                outcome = "booked"
            else:
                outcome = "no_action"
            # Logged before the DB write, which re-raises if this task is
            # already being cancelled.
            logger.info(
                "call_pipeline_ended",
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
