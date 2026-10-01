"""
Provider credential/config preflight.

A broken key or a retired provider model does not surface until a call is
already in progress, where it appears only as a caller hearing silence.
These checks make each dependency fail loudly, by name, before testing.

Each check returns a dict with:
  ok:      bool        -- the dependency is usable right now
  detail:  str         -- human-readable status
  fix:     str | None  -- what to change when ok is False
"""
import asyncio
import json

import aiohttp

from app.core.config import get_settings
from app.core.logging import get_logger
from app.providers.factory import KNOWN_PROVIDERS, missing_config_keys
from app.voice.voices import DEFAULT_SARVAM_SPEAKER, resolve_speaker

logger = get_logger(component="voice_preflight")

TIMEOUT = aiohttp.ClientTimeout(total=20)

SARVAM_TTS_URL = "https://api.sarvam.ai/text-to-speech"
GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"


def _result(ok: bool, detail: str, fix: str | None = None) -> dict:
    return {"ok": ok, "detail": detail, "fix": fix}


async def check_sarvam_tts(session: aiohttp.ClientSession, speaker: str | None = None) -> dict:
    """Synthesize one word to prove key, model and speaker all work together."""
    settings = get_settings()
    if not settings.sarvam_api_key:
        return _result(False, "SARVAM_API_KEY is not set", "Add SARVAM_API_KEY to .env")

    speaker = speaker or DEFAULT_SARVAM_SPEAKER
    payload = {
        "text": "Hi",
        "target_language_code": "en-IN",
        "speaker": speaker,
        "model": settings.sarvam_tts_model,
    }
    try:
        async with session.post(
            SARVAM_TTS_URL,
            json=payload,
            headers={"api-subscription-key": settings.sarvam_api_key},
        ) as response:
            body = await response.text()
            if response.status == 200 and (json.loads(body).get("audios") or []):
                return _result(
                    True, f"synthesized with model={settings.sarvam_tts_model} speaker={speaker}"
                )
            message = body[:300]
            fix = "Check SARVAM_API_KEY."
            if "deprecated" in message:
                fix = f"SARVAM_TTS_MODEL={settings.sarvam_tts_model} is retired; set the model Sarvam names in this error."
            elif "not recognized" in message or "not compatible" in message:
                fix = "Set the clinic's config.voice_id to one of the speakers named in this error, or clear it to use the default."
            elif response.status in (401, 403):
                fix = "SARVAM_API_KEY is invalid or lacks TTS access."
            return _result(False, f"HTTP {response.status}: {message}", fix)
    except asyncio.TimeoutError:
        return _result(False, "timed out contacting Sarvam", "Check network access to api.sarvam.ai")
    except Exception as exc:  # noqa: BLE001 -- a diagnostic must never raise
        return _result(False, f"{type(exc).__name__}: {exc}", "Check network access to api.sarvam.ai")


async def check_gemini(session: aiohttp.ClientSession) -> dict:
    """Generate one token with the configured model.

    A `listModels` call is not enough: models the key may not actually use are
    still listed, and then 404 at generation time ("no longer available to new
    users"). This calls the same endpoint the pipeline does.
    """
    settings = get_settings()
    if not settings.google_api_key:
        return _result(False, "GOOGLE_API_KEY is not set", "Add GOOGLE_API_KEY to .env")

    model = settings.gemini_model
    url = f"{GEMINI_BASE_URL}/{model}:generateContent"
    payload = {
        "contents": [{"parts": [{"text": "hi"}]}],
        "generationConfig": {"maxOutputTokens": 8},
    }
    try:
        async with session.post(
            url, json=payload, headers={"x-goog-api-key": settings.google_api_key}
        ) as response:
            body = await response.text()
            if response.status == 200:
                return _result(True, f"{model} generated a response")

            fix = f"Check GOOGLE_API_KEY and GEMINI_MODEL ({model})."
            if "API_KEY_SERVICE_BLOCKED" in body:
                fix = (
                    "This key is restricted and does not allow "
                    "generativelanguage.googleapis.com. In Google Cloud Console > "
                    "Credentials > this key > API restrictions, allow 'Generative "
                    "Language API' (and enable that API for the project), or create a "
                    "fresh key at https://aistudio.google.com/apikey"
                )
            elif "API_KEY_INVALID" in body:
                fix = "The key is not valid; create one at https://aistudio.google.com/apikey"
            elif "SERVICE_DISABLED" in body:
                fix = "Enable the Generative Language API for this key's Google Cloud project."
            elif response.status == 404:
                available = await _available_models(session)
                suggestion = f" Models this key can list: {', '.join(available[:8])}" if available else ""
                fix = f"GEMINI_MODEL={model} is not available to this key.{suggestion}"
            elif response.status == 429:
                fix = f"Quota exhausted for {model}; wait, or use a different model/key."
            elif response.status == 503:
                fix = (
                    f"{model} is temporarily overloaded, not misconfigured. Retry, or set "
                    "GEMINI_MODEL to another flash model (gemini-3.5-flash is reliable)."
                )
            return _result(False, f"HTTP {response.status}: {body[:300]}", fix)
    except asyncio.TimeoutError:
        return _result(False, "timed out contacting Gemini", "Check network access to googleapis.com")
    except Exception as exc:  # noqa: BLE001
        return _result(False, f"{type(exc).__name__}: {exc}", "Check network access to googleapis.com")


async def _available_models(session: aiohttp.ClientSession) -> list[str]:
    """Flash-family model names this key can list, for a 404's fix message."""
    settings = get_settings()
    try:
        async with session.get(
            GEMINI_BASE_URL, headers={"x-goog-api-key": settings.google_api_key}
        ) as response:
            if response.status != 200:
                return []
            models = json.loads(await response.text()).get("models", [])
    except Exception:  # noqa: BLE001 -- best-effort hint only
        return []

    return [
        m["name"].split("/")[-1]
        for m in models
        if "generateContent" in m.get("supportedGenerationMethods", [])
        and "flash" in m.get("name", "")
    ]


def check_appointment_provider(clinic) -> dict:
    """Whether this clinic can actually book.

    Reported as a warning, not a blocker: a clinic with no provider can still
    answer, answer questions and transfer -- it just cannot complete a booking.
    """
    provider = clinic.appointment_provider
    if provider not in KNOWN_PROVIDERS:
        return _result(
            False,
            f"unknown appointment provider '{provider}'",
            f"Set config.appointment_provider to one of: {', '.join(KNOWN_PROVIDERS)}",
        )

    missing = missing_config_keys(provider, clinic.appointment_provider_config)
    if missing:
        return _result(
            False,
            f"{provider} is not configured (missing: {', '.join(missing)})",
            "Booking will fail and the bot will offer a transfer instead. Set these in "
            "the clinic's config.appointment_provider_config.",
        )
    return _result(True, f"{provider} configured")


async def run_preflight(clinic=None) -> dict:
    """Check every external dependency a voice call needs.

    `clinic` is an optional ResolvedClinic; when given, the TTS check uses
    that clinic's resolved speaker so a bad config.voice_id is caught too.
    """
    speaker = (
        resolve_speaker(clinic.voice_id, clinic_name=clinic.name) if clinic is not None else None
    )

    async with aiohttp.ClientSession(timeout=TIMEOUT) as session:
        sarvam, gemini = await asyncio.gather(
            check_sarvam_tts(session, speaker), check_gemini(session)
        )

    checks = {"sarvam_tts": sarvam, "gemini": gemini}
    warnings: dict[str, dict] = {}

    if clinic is not None:
        checks["clinic"] = _result(True, f"{clinic.name} ({len(clinic.doctors)} doctors)")
        # Booking config is a warning: the call still works without it.
        warnings["appointment_provider"] = check_appointment_provider(clinic)
        if not clinic.receptionist_numbers:
            warnings["transfer"] = _result(
                False,
                "no receptionist numbers configured",
                "Transfers will fail. Add one via POST /api/clinics/{id}/receptionists.",
            )
    else:
        checks["clinic"] = _result(
            False,
            "no active clinic resolved",
            "Create a clinic via POST /api/clinics, or set LOCAL_VOICE_TEST_CLINIC_ID",
        )

    ready = all(check["ok"] for check in checks.values())
    blockers = [name for name, check in checks.items() if not check["ok"]]
    warned = [name for name, check in warnings.items() if not check["ok"]]
    if not ready:
        logger.warning("voice_preflight_failed", blockers=blockers)
    if warned:
        logger.warning("voice_preflight_warnings", warnings=warned)

    return {
        "ready": ready,
        "blockers": blockers,
        "checks": checks,
        "warnings": warnings,
        "degraded": warned,
        "speaker": speaker,
    }
