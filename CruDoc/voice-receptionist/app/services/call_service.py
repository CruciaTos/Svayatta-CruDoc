"""Persists call records for observability/reporting. Live per-call state
lives in voice.call_session.CallSession -- this is the durable summary
written at key transitions (start, end)."""
import asyncio
import uuid
from datetime import datetime, timezone

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.db.postgres import db_session
from app.models.call import Call

logger = get_logger(component="call_service")


async def create_call_record(
    db: AsyncSession,
    clinic_id: uuid.UUID,
    twilio_call_sid: str,
    caller_number: str,
    line_id: uuid.UUID | None = None,
) -> Call:
    call = Call(
        clinic_id=clinic_id,
        phone_number_id=line_id,
        twilio_call_sid=twilio_call_sid,
        caller_number=caller_number,
        status="in_progress",
        start_time=datetime.now(timezone.utc),
    )
    db.add(call)
    await db.commit()
    await db.refresh(call)
    return call


async def close_call_record(db: AsyncSession, call_id: uuid.UUID, outcome: str, status: str = "completed") -> None:
    call = await db.get(Call, call_id)
    if call is None:
        return
    call.status = status
    call.outcome = outcome
    call.end_time = datetime.now(timezone.utc)
    await db.commit()


async def finalize_call_record(
    call_id: uuid.UUID, outcome: str, status: str = "completed"
) -> None:
    """Close a call record using a fresh DB session.

    Call teardown usually runs while the request task is being cancelled --
    a caller hanging up cancels the WebSocket handler -- and an `await` in a
    cancelled task raises immediately, so a commit on the call's original
    session never lands and the record is stranded in "in_progress". This
    opens its own session so it can be run detached from that task.
    """
    try:
        async with db_session() as db:
            await close_call_record(db, call_id, outcome=outcome, status=status)
    except Exception as exc:  # noqa: BLE001 -- teardown must not raise
        logger.error("call_record_finalize_failed", call_id=str(call_id), error=str(exc))


async def finalize_call_record_shielded(
    call_id: uuid.UUID, outcome: str, status: str = "completed"
) -> None:
    """Finalize a call record even if the surrounding task is cancelled.

    The write runs in its own task so cancellation of the caller cannot
    abort it mid-commit; we still wait for it when we are able to.
    """
    closer = asyncio.create_task(finalize_call_record(call_id, outcome, status))
    try:
        await asyncio.shield(closer)
    except asyncio.CancelledError:
        # We are being torn down; leave `closer` running so the record still
        # gets closed, and let the cancellation continue to propagate.
        raise
