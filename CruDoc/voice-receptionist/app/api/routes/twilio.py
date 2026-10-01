"""
Twilio webhook entry points -- where a call turns into an isolated
CallSession + Pipecat pipeline (spec sections 3 and 5).
"""
import uuid
from xml.sax.saxutils import quoteattr

from fastapi import APIRouter, Depends, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import Response
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.core.security import verify_twilio_signature
from app.db.postgres import db_session, get_db
from app.services import call_service, clinic_service
from app.services.clinic_service import ClinicNotFoundError
from app.voice.call_session import CallSession
from app.voice.pipeline import run_call_pipeline

router = APIRouter(prefix="/twilio", tags=["twilio"])
logger = get_logger(component="twilio_webhook")


@router.post("/voice", dependencies=[Depends(verify_twilio_signature)])
async def incoming_call(request: Request, db: AsyncSession = Depends(get_db)) -> Response:
    """
    Twilio's Voice webhook for an inbound call. Resolves the tenant from
    the dialed (`To`) number and returns TwiML that opens a Media Stream
    WebSocket back to this service, carrying the resolved clinic_id so the
    WebSocket handler doesn't have to re-resolve it mid-call.
    """
    form = await request.form()
    to_number = form.get("To", "")
    call_sid = form.get("CallSid", "")

    try:
        clinic = await clinic_service.resolve_by_twilio_number(db, to_number)
    except ClinicNotFoundError as exc:
        logger.error(
            "unmapped_twilio_number",
            to_number=to_number,
            call_sid=call_sid,
            premium_not_enabled=isinstance(exc, clinic_service.ReceptionistNotEnabledError),
        )
        twiml = (
            '<?xml version="1.0" encoding="UTF-8"?>'
            "<Response><Say>Sorry, this number is not currently configured. Goodbye.</Say>"
            "<Hangup/></Response>"
        )
        return Response(content=twiml, media_type="application/xml")

    from app.core.config import get_settings

    ws_url = get_settings().public_base_url.replace("https://", "wss://").replace("http://", "ws://")
    stream_url = f"{ws_url}/twilio/media-stream/{clinic.line_id}"

    # Twilio's `start` event carries no caller/callee numbers, only
    # customParameters, so they are forwarded here.
    twiml = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        f"<Response><Connect><Stream url={quoteattr(stream_url)}>"
        f"<Parameter name=\"callSid\" value={quoteattr(call_sid)}/>"
        f"<Parameter name=\"from\" value={quoteattr(form.get('From', ''))}/>"
        f"<Parameter name=\"to\" value={quoteattr(to_number)}/>"
        "</Stream></Connect></Response>"
    )
    return Response(content=twiml, media_type="application/xml")


@router.websocket("/media-stream/{line_id}")
async def media_stream(websocket: WebSocket, line_id: uuid.UUID) -> None:
    """
    One WebSocket connection = one call = one CallSession = one Pipecat
    pipeline, run as its own asyncio task. Nothing here is shared across
    connections -- that's the entire concurrency/isolation model.
    """
    await websocket.accept()

    # Twilio sends a "connected" event first, then "start" (streamSid + custom
    # parameters), then media frames. Skip ahead to "start".
    start = {}
    try:
        for _ in range(5):
            message = await websocket.receive_json()
            if message.get("event") == "start":
                start = message.get("start", {})
                break
    except WebSocketDisconnect:
        return
    if not start:
        logger.error("media_stream_no_start_event", line_id=str(line_id))
        await websocket.close()
        return

    stream_sid = start.get("streamSid", "")
    custom_params = start.get("customParameters", {})
    call_sid = start.get("callSid") or custom_params.get("callSid", "")
    caller_number = custom_params.get("from") or "unknown"

    async with db_session() as db:
        try:
            # The line (and so the tenant and its doctors) was already
            # resolved from the dialed number in /twilio/voice and is carried
            # in the URL.
            resolved_clinic = await clinic_service.resolve_by_line_id(db, line_id)
        except ClinicNotFoundError:
            logger.error("media_stream_clinic_resolution_failed", line_id=str(line_id))
            await websocket.close()
            return

        call_record = await call_service.create_call_record(
            db, resolved_clinic.clinic_id, call_sid, caller_number, line_id=resolved_clinic.line_id
        )

        session = CallSession(
            call_id=uuid.uuid4(),
            clinic=resolved_clinic,
            twilio_call_sid=call_sid,
            caller_phone=caller_number,
            db_call_record_id=call_record.id,
        )

    try:
        await run_call_pipeline(websocket, session, stream_sid)
    except WebSocketDisconnect:
        logger.info("call_websocket_disconnected", call_id=str(session.call_id))
    except Exception as exc:  # noqa: BLE001 -- one call's failure must not affect others
        logger.error("call_pipeline_crashed", call_id=str(session.call_id), error=str(exc))
