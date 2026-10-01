"""
Regression tests for the voice-provider wiring.

These cover the failures that made a real call produce no audio at all.
Every one of them was invisible to the rest of the suite because the
pipeline is only assembled inside a live WebSocket handler: wrong provider
kwargs were silently swallowed by `**kwargs`, and a wrong tool-handler
signature only fails when Gemini actually calls a tool.
"""
import inspect
import uuid

import pytest

from app.voice.tools import TOOL_DECLARATIONS, TOOL_NAMES, ToolExecutor
from app.voice.voices import (
    DEFAULT_SARVAM_SPEAKER,
    RETIRED_V2_SPEAKERS,
    SARVAM_BULBUL_V3_SPEAKERS,
    resolve_language,
    resolve_speaker,
)


def _resolved_clinic(**overrides):
    from app.schemas.clinic import ResolvedClinic

    base = dict(
        clinic_id=uuid.uuid4(),
        name="Test Clinic",
        timezone="Asia/Kolkata",
        greeting="Hello",
        ai_instructions=None,
        voice_id=None,
        supported_languages=["en-IN"],
        appointment_provider="crudoc",
        appointment_provider_config={},
        doctors=[],
        receptionist_numbers=[],
    )
    base.update(overrides)
    return ResolvedClinic(**base)


class TestSpeakerResolution:
    """An unknown speaker makes Sarvam 400 the request, producing a call
    with zero audio -- so nothing unvalidated may reach the API."""

    def test_unset_voice_id_falls_back_to_valid_speaker(self):
        assert resolve_speaker(None) == DEFAULT_SARVAM_SPEAKER
        assert DEFAULT_SARVAM_SPEAKER in SARVAM_BULBUL_V3_SPEAKERS

    def test_literal_default_is_not_passed_through(self):
        # "default" is not a Sarvam speaker; passing it through was the
        # original cause of silent calls.
        assert resolve_speaker("default") in SARVAM_BULBUL_V3_SPEAKERS

    @pytest.mark.parametrize("retired", sorted(RETIRED_V2_SPEAKERS))
    def test_retired_v2_speakers_are_replaced(self, retired):
        # bulbul:v3 rejects every v2 speaker name.
        assert resolve_speaker(retired) in SARVAM_BULBUL_V3_SPEAKERS

    def test_valid_speaker_is_preserved_and_normalized(self):
        assert resolve_speaker("neha") == "neha"
        assert resolve_speaker("  Priya  ") == "priya"

    def test_every_known_speaker_resolves_to_itself(self):
        for speaker in SARVAM_BULBUL_V3_SPEAKERS:
            assert resolve_speaker(speaker) == speaker


class TestLanguageResolution:
    def test_first_configured_language_wins(self):
        assert resolve_language(["hi-IN", "en-IN"]) == "hi-IN"

    def test_empty_and_blank_fall_back(self):
        assert resolve_language(None) == "en-IN"
        assert resolve_language([]) == "en-IN"
        assert resolve_language(["  "]) == "en-IN"


class TestToolDeclarations:
    def test_declarations_are_a_tools_schema(self):
        from pipecat.adapters.schemas.tools_schema import ToolsSchema

        # A raw list of dicts is not converted by pipecat's provider adapters.
        assert isinstance(TOOL_DECLARATIONS, ToolsSchema)

    def test_converts_to_gemini_function_declarations(self):
        from pipecat.adapters.services.gemini_adapter import GeminiLLMAdapter

        converted = GeminiLLMAdapter().to_provider_tools_format(TOOL_DECLARATIONS)
        declared = {f["name"] for f in converted[0]["function_declarations"]}
        assert declared == set(TOOL_NAMES)

    def test_every_declared_tool_has_a_handler(self):
        for name in TOOL_NAMES:
            assert hasattr(ToolExecutor, f"_handle_{name}"), f"no handler for {name}"


class TestToolHandlerContract:
    """Pipecat >=0.0.59 calls handlers with one FunctionCallParams and reads
    the result from `params.result_callback`. A handler with more than one
    parameter is routed down the legacy 6-positional-arg path instead, and a
    returned value is discarded -- leaving the LLM waiting forever."""

    def test_handler_takes_a_single_param_so_pipecat_uses_the_modern_path(self):
        executor = ToolExecutor(db=None, session=None)
        # This mirrors pipecat's own check in LLMService.register_function.
        signature = inspect.signature(executor.handle_function_call)
        assert len(signature.parameters) == 1

    @pytest.mark.asyncio
    async def test_result_is_delivered_via_result_callback(self):
        clinic = _resolved_clinic(doctors=[{"name": "Dr. A", "specialization": "Dentist"}])
        from app.voice.call_session import CallSession

        session = CallSession(
            call_id=uuid.uuid4(), clinic=clinic, twilio_call_sid=None, caller_phone="local-browser"
        )
        executor = ToolExecutor(db=None, session=session)

        delivered = []

        class FakeParams:
            function_name = "list_doctors"
            arguments = {}

            @staticmethod
            async def result_callback(result):
                delivered.append(result)

        await executor.handle_function_call(FakeParams())
        assert delivered == [{"doctors": clinic.doctors}]

    @pytest.mark.asyncio
    async def test_unknown_tool_still_answers_the_llm(self):
        session_clinic = _resolved_clinic()
        from app.voice.call_session import CallSession

        session = CallSession(
            call_id=uuid.uuid4(),
            clinic=session_clinic,
            twilio_call_sid=None,
            caller_phone="local-browser",
        )
        executor = ToolExecutor(db=None, session=session)
        delivered = []

        class FakeParams:
            function_name = "no_such_tool"
            arguments = {}

            @staticmethod
            async def result_callback(result):
                delivered.append(result)

        await executor.handle_function_call(FakeParams())
        # The LLM must get *something* back, otherwise the call hangs.
        assert len(delivered) == 1 and "error" in delivered[0]


class TestCallRecordSignature:
    """The local voice route passed `caller_phone=`, but the service takes
    `caller_number=` -- so every browser test session silently failed to
    record a call."""

    def test_service_takes_caller_number(self):
        from app.services import call_service

        params = inspect.signature(call_service.create_call_record).parameters
        assert "caller_number" in params
        assert "caller_phone" not in params

    def test_every_create_call_record_call_site_uses_accepted_kwargs(self):
        """Checks the actual call expressions, not the whole file -- the route
        legitimately uses `caller_phone=` for the CallSession dataclass."""
        import ast
        import pathlib

        from app.services import call_service

        accepted = set(inspect.signature(call_service.create_call_record).parameters)
        call_sites = 0

        for path in pathlib.Path("app").rglob("*.py"):
            tree = ast.parse(path.read_text(encoding="utf-8"))
            for node in ast.walk(tree):
                if not isinstance(node, ast.Call):
                    continue
                func = node.func
                name = func.attr if isinstance(func, ast.Attribute) else getattr(func, "id", None)
                if name != "create_call_record":
                    continue
                call_sites += 1
                for keyword in node.keywords:
                    assert keyword.arg in accepted, (
                        f"{path}:{node.lineno} passes {keyword.arg}= which "
                        f"create_call_record does not accept"
                    )

        assert call_sites >= 2, "expected the Twilio and local-voice call sites"


class TestSessionTeardown:
    """Pipecat keeps a PipelineTask running after its WebSocket closes unless
    something cancels it. Without the transport's on_client_disconnected
    handler, `runner.run()` never returns: the pipeline, its Sarvam sockets and
    the call's DB record all leak for the process's lifetime."""

    @pytest.mark.parametrize(
        "module_name", ["app.voice.pipeline", "app.voice.local_pipeline"]
    )
    def test_pipeline_cancels_task_when_client_disconnects(self, module_name):
        import importlib

        source = inspect.getsource(importlib.import_module(module_name))
        assert 'event_handler("on_client_disconnected")' in source
        assert 'event_handler("on_session_timeout")' in source
        # Each handler must actually end the task, not just log.
        for event in ("on_client_disconnected", "on_session_timeout"):
            after = source.split(f'event_handler("{event}")', 1)[1]
            body = after.split("@", 1)[0]
            assert "task.cancel()" in body, f"{event} does not cancel the task"

    @pytest.mark.parametrize(
        "module_name", ["app.voice.pipeline", "app.voice.local_pipeline"]
    )
    def test_call_record_is_closed_with_its_own_session(self, module_name):
        """Teardown usually runs while the handler task is being cancelled, so
        an await on the call's own DB session never commits."""
        import importlib

        source = inspect.getsource(importlib.import_module(module_name))
        assert "finalize_call_record_shielded" in source
        assert "close_call_record(db" not in source

    @pytest.mark.asyncio
    async def test_finalizer_completes_despite_caller_cancellation(self, monkeypatch):
        """The write must survive cancellation of the task that started it.

        Uses a stand-in for the DB write because the test database is
        in-memory SQLite, where a second connection gets its own empty
        database -- the finalizer deliberately opens its own session.
        """
        import asyncio

        from app.services import call_service

        finished = asyncio.Event()

        async def fake_finalize(call_id, outcome, status="completed"):
            await asyncio.sleep(0.05)  # a commit that outlives the cancellation
            finished.set()

        monkeypatch.setattr(call_service, "finalize_call_record", fake_finalize)

        async def caller():
            await call_service.finalize_call_record_shielded(uuid.uuid4(), outcome="completed")

        task = asyncio.create_task(caller())
        await asyncio.sleep(0)  # let the shielded inner task start
        task.cancel()

        with pytest.raises(asyncio.CancelledError):
            await task

        # Cancelling the caller must not abort the write.
        await asyncio.wait_for(finished.wait(), timeout=2)

    @pytest.mark.asyncio
    async def test_finalizer_swallows_db_errors(self, monkeypatch):
        """Teardown runs in a `finally`; it must never raise over the real error."""
        from app.services import call_service

        class Boom:
            async def __aenter__(self):
                raise RuntimeError("database gone")

            async def __aexit__(self, *exc):
                return False

        monkeypatch.setattr(call_service, "db_session", lambda: Boom())
        # Must not raise.
        await call_service.finalize_call_record(uuid.uuid4(), outcome="completed")
