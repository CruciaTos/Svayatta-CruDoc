"""
Development-only router for local browser-based voice testing.

Exposes:
- GET /voice-test: Serves the browser testing UI.
- GET /voice-test/info: Returns active clinic and environment status.
- GET /voice-test/preflight: Verifies provider credentials before testing.
- WebSocket /voice-test/ws: Receives PCM16 microphone audio, runs the Pipecat
  Sarvam/Gemini pipeline, and sends back PCM16 synthesized voice audio.

Guarded by app_env == "development" -- rejected in staging/production.
"""
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import get_settings
from app.core.logging import get_logger
from app.db.postgres import db_session, get_db
from app.models.clinic import Clinic
from app.services import call_service, clinic_service
from app.voice.call_session import CallSession
from app.voice.local_pipeline import run_local_pipeline
from app.voice.preflight import run_preflight

logger = get_logger(component="local_voice_test_route")

router = APIRouter(prefix="/voice-test", tags=["Local Voice Testing"])

HTML_FILE_PATH = Path(__file__).resolve().parent.parent.parent.parent / "local_voice_test" / "index.html"


def ensure_development_mode() -> None:
    settings = get_settings()
    if settings.app_env != "development":
        raise HTTPException(status_code=403, detail="Local voice testing is only permitted in development mode.")


async def resolve_active_clinic(db: AsyncSession):
    """The clinic a local test runs against: the configured one, else the
    first active clinic in the database."""
    settings = get_settings()

    if settings.local_voice_test_clinic_id:
        try:
            return await clinic_service.resolve_by_clinic_id(db, settings.local_voice_test_clinic_id)
        except clinic_service.ClinicNotFoundError:
            logger.warning(
                "configured_local_clinic_not_found",
                clinic_id=str(settings.local_voice_test_clinic_id),
            )

    first_clinic = (
        await db.execute(select(Clinic).where(Clinic.status == "active").limit(1))
    ).scalar_one_or_none()
    if first_clinic:
        return await clinic_service.resolve_by_clinic_id(db, first_clinic.id)
    return None


@router.get("", response_class=HTMLResponse)
async def get_test_page() -> FileResponse:
    """Serve the local browser testing interface."""
    ensure_development_mode()
    if not HTML_FILE_PATH.exists():
        raise HTTPException(status_code=404, detail="Test UI files not found.")
    return FileResponse(HTML_FILE_PATH)


@router.get("/info")
async def get_test_info(db: AsyncSession = Depends(get_db)):
    """Return local voice testing diagnostic info and active development clinic."""
    ensure_development_mode()
    settings = get_settings()

    active_clinic = None
    try:
        active_clinic = await resolve_active_clinic(db)
    except Exception:
        pass

    return {
        "status": "available",
        "app_env": settings.app_env,
        "configured_clinic_id": str(settings.local_voice_test_clinic_id) if settings.local_voice_test_clinic_id else None,
        "active_clinic": {
            "id": str(active_clinic.clinic_id),
            "name": active_clinic.name,
            "greeting": active_clinic.greeting,
            "languages": active_clinic.supported_languages,
        } if active_clinic else None,
    }


@router.get("/preflight")
async def get_preflight(db: AsyncSession = Depends(get_db)):
    """Verify Sarvam, Gemini and clinic config before starting a test call.

    A provider failure otherwise shows up only as silence mid-call, so check
    this first when a test session produces no audio.
    """
    ensure_development_mode()
    clinic = None
    try:
        clinic = await resolve_active_clinic(db)
    except Exception as exc:  # noqa: BLE001 -- report, don't fail the diagnostic
        logger.warning("preflight_clinic_resolution_failed", error=str(exc))
    return await run_preflight(clinic)


@router.websocket("/ws")
async def websocket_local_voice(websocket: WebSocket) -> None:
    """WebSocket endpoint connecting browser microphone & speaker to Pipecat."""
    settings = get_settings()
    if settings.app_env != "development":
        logger.warning("local_voice_ws_rejected_non_dev_env", env=settings.app_env)
        await websocket.close(code=1008, reason="Only permitted in development mode")
        return

    await websocket.accept()

    async with db_session() as db:
        # 1. Resolve test clinic
        resolved_clinic = await resolve_active_clinic(db)

        if resolved_clinic is None:
            logger.error("no_active_clinic_available_for_local_test")
            await websocket.send_json(
                {
                    "type": "error",
                    "message": "No active clinic found in database. Create a clinic first before testing.",
                }
            )
            await websocket.close(code=1008, reason="No active clinic found")
            return

        # 2. Build local CallSession
        call_id = uuid.uuid4()
        session = CallSession(
            call_id=call_id,
            clinic=resolved_clinic,
            twilio_call_sid=None,
            caller_phone="local-browser",
        )

        try:
            call_record = await call_service.create_call_record(
                db,
                clinic_id=resolved_clinic.clinic_id,
                twilio_call_sid=f"local-{call_id}",
                caller_number="local-browser",
            )
            session.db_call_record_id = call_record.id
        except Exception as exc:
            logger.warning("call_record_creation_skipped", error=str(exc))

    logger.info(
        "local_voice_session_connected",
        call_id=str(session.call_id),
        clinic_name=resolved_clinic.name,
    )

    try:
        await run_local_pipeline(websocket, session)
    except WebSocketDisconnect:
        logger.info("local_voice_session_disconnected", call_id=str(session.call_id))
    except Exception as exc:
        logger.error("local_voice_session_error", call_id=str(session.call_id), error=str(exc))
        try:
            await websocket.send_json({"type": "error", "message": f"Session error: {str(exc)}"})
        except Exception:
            pass
    finally:
        logger.info("local_voice_session_cleaned_up", call_id=str(session.call_id))
