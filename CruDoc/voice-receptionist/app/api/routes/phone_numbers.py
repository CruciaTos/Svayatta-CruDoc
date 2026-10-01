import uuid

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import verify_internal_api_key
from app.db.postgres import get_db
from app.models.phone_number import PhoneNumber

router = APIRouter(
    prefix="/api/clinics/{clinic_id}/phone-numbers",
    tags=["phone-numbers"],
    dependencies=[Depends(verify_internal_api_key)],
)


class PhoneNumberCreate(BaseModel):
    twilio_number: str


@router.post("", status_code=201)
async def map_phone_number(clinic_id: uuid.UUID, payload: PhoneNumberCreate, db: AsyncSession = Depends(get_db)):
    row = PhoneNumber(clinic_id=clinic_id, twilio_number=payload.twilio_number, active=True)
    db.add(row)
    await db.commit()
    await db.refresh(row)
    return {"id": str(row.id), "twilio_number": row.twilio_number}
