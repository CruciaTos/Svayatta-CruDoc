"""Twilio webhook + Media Streams handshake, with the pipeline stubbed out."""
import pytest
from fastapi.testclient import TestClient

from app.api.routes import twilio as twilio_route
from app.core.security import verify_twilio_signature
from app.db.postgres import AsyncSessionLocal, engine
from app.main import app
from app.models.base import Base
from app.models.clinic import Clinic
from app.models.phone_number import PhoneNumber


@pytest.fixture
def client_and_clinic():
    import asyncio

    async def setup():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)
        async with AsyncSessionLocal() as db:
            clinic = Clinic(name="Test Clinic", timezone="Asia/Kolkata", config={}, ai_receptionist_enabled=True)
            db.add(clinic)
            await db.flush()
            line = PhoneNumber(clinic_id=clinic.id, twilio_number="+15550001111", active=True)
            db.add(line)
            await db.commit()
            return line.id

    clinic_id = asyncio.run(setup())
    app.dependency_overrides[verify_twilio_signature] = lambda: None
    yield TestClient(app), clinic_id
    app.dependency_overrides.clear()

    async def teardown():
        async with engine.begin() as conn:
            await conn.run_sync(Base.metadata.drop_all)

    asyncio.run(teardown())


def test_voice_webhook_forwards_numbers_in_stream_params(client_and_clinic, monkeypatch):
    client, line_id = client_and_clinic
    monkeypatch.setattr(
        "app.core.config.Settings.public_base_url", "https://x.ngrok.app", raising=False
    )
    from app.core.config import get_settings

    get_settings.cache_clear()
    monkeypatch.setenv("PUBLIC_BASE_URL", "https://x.ngrok.app")
    get_settings.cache_clear()
    r = client.post("/twilio/voice", data={"To": "+15550001111", "From": "+919999999999", "CallSid": "CA1"})
    assert r.status_code == 200
    assert f"wss://x.ngrok.app/twilio/media-stream/{line_id}" in r.text
    assert 'name="from" value="+919999999999"' in r.text
    get_settings.cache_clear()


def test_media_stream_skips_connected_event_and_uses_url_line(client_and_clinic, monkeypatch):
    client, line_id = client_and_clinic
    import threading

    seen = {}
    done = threading.Event()

    async def fake_pipeline(websocket, session, stream_sid):
        seen["stream_sid"] = stream_sid
        seen["clinic"] = session.clinic.clinic_id
        seen["caller"] = session.caller_phone
        seen["call_sid"] = session.twilio_call_sid
        done.set()

    # The TestClient runs the app on its own loop, which an in-memory aiosqlite
    # connection created on another loop cannot be used from -- stub the DB.
    import contextlib
    import types
    import uuid as _uuid

    from app.schemas.clinic import ResolvedClinic

    resolved = ResolvedClinic(
        clinic_id=_uuid.uuid4(), name="Test Clinic", timezone="Asia/Kolkata", greeting="Hi",
        ai_instructions=None, voice_id=None, supported_languages=["en-IN"],
        appointment_provider="crudoc", appointment_provider_config={}, doctors=[],
        receptionist_numbers=[],
    )

    async def fake_resolve(db, lid):
        assert lid == line_id
        return resolved

    async def fake_create(db, cid, sid, caller, line_id=None):
        return types.SimpleNamespace(id=_uuid.uuid4())

    @contextlib.asynccontextmanager
    async def fake_db():
        yield None

    monkeypatch.setattr(twilio_route.clinic_service, "resolve_by_line_id", fake_resolve)
    monkeypatch.setattr(twilio_route.call_service, "create_call_record", fake_create)
    monkeypatch.setattr(twilio_route, "db_session", fake_db)
    monkeypatch.setattr(twilio_route, "run_call_pipeline", fake_pipeline)
    with client.websocket_connect(f"/twilio/media-stream/{line_id}") as ws:
        ws.send_json({"event": "connected", "protocol": "Call", "version": "1.0.0"})
        ws.send_json(
            {
                "event": "start",
                "start": {
                    "streamSid": "MZ1",
                    "callSid": "CA1",
                    "customParameters": {"from": "+919999999999", "to": "+15550001111"},
                },
            }
        )
        # Leaving the block earlier would disconnect and cancel the handler.
        assert done.wait(timeout=10)
    assert seen == {
        "stream_sid": "MZ1",
        "clinic": resolved.clinic_id,
        "caller": "+919999999999",
        "call_sid": "CA1",
    }
