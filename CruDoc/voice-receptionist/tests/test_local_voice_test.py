import uuid
import pytest
from httpx import AsyncClient, ASGITransport
from starlette.websockets import WebSocketDisconnect

from app.core.config import Settings
from app.main import app
from app.models.clinic import Clinic
from app.voice.call_session import CallSession, CallStatus
from app.voice.local_audio_serializer import LocalPcmSerializer
from app.voice.pipeline import HardFallbackMonitor
from pipecat.frames.frames import InputAudioRawFrame, TranscriptionFrame


@pytest.mark.asyncio
async def test_local_serializer_audio_frames():
    """Verify LocalPcmSerializer validates frame lengths and audio properties."""
    serializer = LocalPcmSerializer()

    # Valid 16000Hz mono PCM16 chunk (e.g. 320 bytes = 160 samples = 10ms)
    pcm_data = b"\x00\x00" * 160
    frame = await serializer.deserialize(pcm_data)
    assert isinstance(frame, InputAudioRawFrame)
    assert frame.sample_rate == 16000
    assert frame.num_channels == 1
    assert frame.audio == pcm_data

    # Odd number of bytes should be rejected
    with pytest.raises(ValueError, match="even number of bytes"):
        await serializer.deserialize(b"\x00\x00\x01")

    # Exceeding maximum frame size should be rejected
    oversized = b"\x00" * (serializer.max_audio_frame_bytes + 2)
    with pytest.raises(ValueError, match="exceeds the local test size limit"):
        await serializer.deserialize(oversized)


@pytest.mark.asyncio
async def test_local_serializer_control_frames():
    """Verify LocalPcmSerializer correctly parses JSON stop message and serializes events."""
    from pipecat.frames.frames import (
        BotStartedSpeakingFrame,
        BotStoppedSpeakingFrame,
        EndFrame,
        ErrorFrame,
        OutputAudioRawFrame,
        TranscriptionFrame,
        TTSTextFrame,
    )

    serializer = LocalPcmSerializer()

    # Stop command
    end_frame = await serializer.deserialize('{"type": "stop"}')
    assert isinstance(end_frame, EndFrame)

    # Transcription frame serialization
    user_tr = await serializer.serialize(TranscriptionFrame(text="Hello doctor", user_id="user", timestamp="0"))
    assert '"role": "user"' in user_tr
    assert "Hello doctor" in user_tr

    assistant_tr = await serializer.serialize(TTSTextFrame(text="How can I help?", aggregated_by="test"))
    assert '"role": "assistant"' in assistant_tr
    assert "How can I help?" in assistant_tr

    # Speaking status
    assert '"value": true' in await serializer.serialize(BotStartedSpeakingFrame())
    assert '"value": false' in await serializer.serialize(BotStoppedSpeakingFrame())

    # Raw audio serialization
    out_audio = await serializer.serialize(OutputAudioRawFrame(audio=b"\x12\x34", sample_rate=24000, num_channels=1))
    assert out_audio == b"\x12\x34"


@pytest.mark.asyncio
async def test_local_fallback_monitor_no_twilio_transfer():
    """Verify HardFallbackMonitor with allow_transfer=False suppresses Twilio call transfer."""
    clinic = Clinic(
        name="Test Dev Clinic",
        timezone="Asia/Kolkata",
        status="active",
        config={"greeting": "Welcome"},
    )
    from app.schemas.clinic import ResolvedClinic

    resolved = ResolvedClinic(
        clinic_id=uuid.uuid4(),
        name=clinic.name,
        timezone=clinic.timezone,
        greeting="Welcome",
        ai_instructions=None,
        voice_id=None,
        supported_languages=["en-IN"],
        appointment_provider="crudoc",
        appointment_provider_config={},
        doctors=[],
        receptionist_numbers=[],
    )

    session = CallSession(
        call_id=uuid.uuid4(),
        clinic=resolved,
        twilio_call_sid=None,
        caller_phone="local-browser",
    )

    monitor = HardFallbackMonitor(session, threshold=2, allow_transfer=False)

    # Simulate 2 consecutive failed transcriptions
    from pipecat.processors.frame_processor import FrameDirection

    await monitor.process_frame(TranscriptionFrame(text="", user_id="user", timestamp="0"), FrameDirection.DOWNSTREAM)
    assert session.consecutive_stt_failures == 1
    assert session.status == CallStatus.IN_PROGRESS

    await monitor.process_frame(TranscriptionFrame(text="   ", user_id="user", timestamp="0"), FrameDirection.DOWNSTREAM)
    assert session.consecutive_stt_failures == 2
    # Status remains in progress because allow_transfer=False prevents Twilio transfer call
    assert session.status != CallStatus.TRANSFERRED


@pytest.mark.asyncio
async def test_local_voice_info_endpoint(db_session):
    """Verify GET /voice-test/info returns environment status."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/voice-test/info")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "available"
        assert data["app_env"] == "development"


@pytest.mark.asyncio
async def test_local_voice_ui_page_loads():
    """Verify GET /voice-test serves HTML page in development."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/voice-test")
        assert resp.status_code == 200
        assert "Local Sandbox" in resp.text


@pytest.mark.asyncio
async def test_local_voice_rejected_outside_development(monkeypatch):
    """Verify local voice test endpoints are rejected outside development environment."""
    from app.core import config
    test_settings = config.get_settings().model_copy(update={"app_env": "production"})
    monkeypatch.setattr("app.api.routes.local_voice_test.get_settings", lambda: test_settings)

    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        resp = await client.get("/voice-test")
        assert resp.status_code == 403
        assert "only permitted in development" in resp.json()["detail"]

