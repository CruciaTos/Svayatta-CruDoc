"""
Tests for the provider preflight checks.

The point of preflight is to turn "the call was silent" into a named cause,
so these assert that each real failure seen from the live providers maps to
an actionable fix message.
"""
import json

import pytest

from app.voice import preflight


class _FakeResponse:
    def __init__(self, status: int, body: str):
        self.status = status
        self._body = body

    async def text(self) -> str:
        return self._body

    async def __aenter__(self):
        return self

    async def __aexit__(self, *exc):
        return False


class _FakeSession:
    """Stands in for aiohttp.ClientSession; post/get return async context managers."""

    def __init__(self, response: _FakeResponse):
        self._response = response
        self.calls = []

    def post(self, url, **kwargs):
        self.calls.append(("POST", url, kwargs))
        return self._response

    def get(self, url, **kwargs):
        self.calls.append(("GET", url, kwargs))
        return self._response


# Bodies copied from real provider responses.
SARVAM_DEPRECATED_MODEL = json.dumps(
    {"error": {"message": "Model 'bulbul:v2' has been deprecated. Please use 'bulbul:v3' instead."}}
)
SARVAM_BAD_SPEAKER = json.dumps(
    {"error": {"message": "Speaker 'zzz' is not recognized. Available speakers for bulbul:v3 are: aditya, ritu"}}
)
GEMINI_BLOCKED = json.dumps(
    {"error": {"code": 403, "status": "PERMISSION_DENIED",
               "details": [{"reason": "API_KEY_SERVICE_BLOCKED"}]}}
)
GEMINI_INVALID = json.dumps({"error": {"code": 400, "details": [{"reason": "API_KEY_INVALID"}]}})
# Real response for a model that `listModels` returns but the key cannot use.
GEMINI_MODEL_GONE = json.dumps(
    {"error": {"code": 404, "message": "This model models/gemini-2.5-flash is no longer available to new users."}}
)
GEMINI_OVERLOADED = json.dumps(
    {"error": {"code": 503, "message": "This model is currently experiencing high demand."}}
)


class TestSarvamCheck:
    @pytest.mark.asyncio
    async def test_success_reports_model_and_speaker(self, monkeypatch):
        session = _FakeSession(_FakeResponse(200, json.dumps({"audios": ["BASE64"]})))
        result = await preflight.check_sarvam_tts(session, "priya")
        assert result["ok"] is True
        assert "priya" in result["detail"]

    @pytest.mark.asyncio
    async def test_empty_audio_is_not_success(self):
        session = _FakeSession(_FakeResponse(200, json.dumps({"audios": []})))
        result = await preflight.check_sarvam_tts(session, "priya")
        assert result["ok"] is False

    @pytest.mark.asyncio
    async def test_deprecated_model_names_the_model_setting(self):
        session = _FakeSession(_FakeResponse(400, SARVAM_DEPRECATED_MODEL))
        result = await preflight.check_sarvam_tts(session, "anushka")
        assert result["ok"] is False
        assert "SARVAM_TTS_MODEL" in result["fix"]

    @pytest.mark.asyncio
    async def test_bad_speaker_points_at_clinic_voice_id(self):
        session = _FakeSession(_FakeResponse(400, SARVAM_BAD_SPEAKER))
        result = await preflight.check_sarvam_tts(session, "zzz")
        assert result["ok"] is False
        assert "voice_id" in result["fix"]

    @pytest.mark.asyncio
    async def test_missing_key_is_reported_without_a_request(self, monkeypatch):
        from app.core import config

        settings = config.get_settings().model_copy(update={"sarvam_api_key": ""})
        monkeypatch.setattr(preflight, "get_settings", lambda: settings)
        session = _FakeSession(_FakeResponse(200, "{}"))
        result = await preflight.check_sarvam_tts(session)
        assert result["ok"] is False
        assert session.calls == [], "should not call the provider without a key"


class TestGeminiCheck:
    @pytest.mark.asyncio
    async def test_success_requires_an_actual_generation(self, monkeypatch):
        from app.core import config

        settings = config.get_settings().model_copy(
            update={"google_api_key": "k", "gemini_model": "gemini-3.5-flash"}
        )
        monkeypatch.setattr(preflight, "get_settings", lambda: settings)
        body = json.dumps({"candidates": [{"content": {"parts": [{"text": "hi"}]}}]})
        session = _FakeSession(_FakeResponse(200, body))
        result = await preflight.check_gemini(session)
        assert result["ok"] is True
        # Must hit generateContent, not just list models: a listed model can
        # still 404 at generation time.
        assert session.calls[0][0] == "POST"
        assert ":generateContent" in session.calls[0][1]

    @pytest.mark.asyncio
    async def test_listed_but_unusable_model_is_flagged(self, monkeypatch):
        """`listModels` returns models the key cannot actually use; only a real
        generate call surfaces that."""
        from app.core import config

        settings = config.get_settings().model_copy(
            update={"google_api_key": "k", "gemini_model": "gemini-2.5-flash"}
        )
        monkeypatch.setattr(preflight, "get_settings", lambda: settings)
        result = await preflight.check_gemini(_FakeSession(_FakeResponse(404, GEMINI_MODEL_GONE)))
        assert result["ok"] is False
        assert "GEMINI_MODEL" in result["fix"]

    @pytest.mark.asyncio
    async def test_overloaded_model_is_reported_as_transient(self, monkeypatch):
        from app.core import config

        settings = config.get_settings().model_copy(update={"google_api_key": "k"})
        monkeypatch.setattr(preflight, "get_settings", lambda: settings)
        result = await preflight.check_gemini(_FakeSession(_FakeResponse(503, GEMINI_OVERLOADED)))
        assert result["ok"] is False
        assert "overloaded" in result["fix"]

    @pytest.mark.asyncio
    async def test_blocked_key_explains_the_restriction(self, monkeypatch):
        from app.core import config

        settings = config.get_settings().model_copy(update={"google_api_key": "k"})
        monkeypatch.setattr(preflight, "get_settings", lambda: settings)
        result = await preflight.check_gemini(_FakeSession(_FakeResponse(403, GEMINI_BLOCKED)))
        assert result["ok"] is False
        # This is the exact failure that made the live test silent.
        assert "API restrictions" in result["fix"] or "Generative Language API" in result["fix"]

    @pytest.mark.asyncio
    async def test_invalid_key_points_at_key_creation(self, monkeypatch):
        from app.core import config

        settings = config.get_settings().model_copy(update={"google_api_key": "k"})
        monkeypatch.setattr(preflight, "get_settings", lambda: settings)
        result = await preflight.check_gemini(_FakeSession(_FakeResponse(400, GEMINI_INVALID)))
        assert result["ok"] is False
        assert "aistudio.google.com" in result["fix"]


class TestPreflightEndpoint:
    @pytest.mark.asyncio
    async def test_endpoint_returns_check_results(self, db_session, monkeypatch):
        from httpx import ASGITransport, AsyncClient

        from app.main import app

        async def fake_preflight(clinic=None):
            return {"ready": True, "blockers": [], "checks": {}, "speaker": "priya"}

        monkeypatch.setattr("app.api.routes.local_voice_test.run_preflight", fake_preflight)

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/voice-test/preflight")
        assert resp.status_code == 200
        assert resp.json()["ready"] is True

    @pytest.mark.asyncio
    async def test_endpoint_blocked_outside_development(self, monkeypatch):
        from httpx import ASGITransport, AsyncClient

        from app.core import config
        from app.main import app

        settings = config.get_settings().model_copy(update={"app_env": "production"})
        monkeypatch.setattr("app.api.routes.local_voice_test.get_settings", lambda: settings)

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            resp = await client.get("/voice-test/preflight")
        assert resp.status_code == 403


class TestAppointmentProviderWarning:
    """A clinic with no provider config can still greet, answer and transfer --
    it just cannot book. That is a warning, not a reason to block testing."""

    def _clinic(self, provider="crudoc", config=None):
        import uuid

        from app.schemas.clinic import ResolvedClinic

        return ResolvedClinic(
            clinic_id=uuid.uuid4(),
            name="C",
            timezone="Asia/Kolkata",
            greeting="hi",
            ai_instructions=None,
            voice_id=None,
            supported_languages=["en-IN"],
            appointment_provider=provider,
            appointment_provider_config=config if config is not None else {},
            doctors=[],
            receptionist_numbers=["+911234567890"],
        )

    def test_missing_config_is_named_not_a_keyerror(self):
        result = preflight.check_appointment_provider(self._clinic())
        assert result["ok"] is False
        assert "base_url" in result["detail"] and "api_key" in result["detail"]

    def test_fully_configured_provider_passes(self):
        clinic = self._clinic(config={"base_url": "https://x", "api_key": "k"})
        assert preflight.check_appointment_provider(clinic)["ok"] is True

    def test_unknown_provider_is_flagged(self):
        result = preflight.check_appointment_provider(self._clinic(provider="nope"))
        assert result["ok"] is False
        assert "appointment_provider" in result["fix"]


class TestProviderFactory:
    def test_missing_config_raises_a_named_error(self):
        from app.providers.factory import ProviderNotConfiguredError, get_provider

        with pytest.raises(ProviderNotConfiguredError) as exc:
            get_provider("crudoc", {})
        # A bare KeyError here would reach the caller as a generic failure.
        assert "base_url" in str(exc.value)

    def test_partial_config_is_rejected(self):
        from app.providers.factory import ProviderNotConfiguredError, get_provider

        with pytest.raises(ProviderNotConfiguredError) as exc:
            get_provider("crudoc", {"base_url": "https://x"})
        assert "api_key" in str(exc.value)

    def test_unknown_provider_rejected(self):
        from app.providers.factory import get_provider

        with pytest.raises(ValueError, match="Unknown appointment provider"):
            get_provider("nope", {})
