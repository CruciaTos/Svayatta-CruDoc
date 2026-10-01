import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import verify_internal_api_key
from app.db.postgres import get_db
from app.models.call import Call

router = APIRouter(prefix="/api/calls", tags=["calls"], dependencies=[Depends(verify_internal_api_key)])


@router.get("/{call_id}")
async def get_call(call_id: uuid.UUID, db: AsyncSession = Depends(get_db)):
    call = await db.get(Call, call_id)
    if call is None:
        raise HTTPException(status_code=404, detail="Call not found")
    return {
        "id": str(call.id),
        "clinic_id": str(call.clinic_id),
        "caller_number": call.caller_number,
        "status": call.status,
        "outcome": call.outcome,
        "start_time": call.start_time.isoformat(),
        "end_time": call.end_time.isoformat() if call.end_time else None,
    }
