from datetime import date

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.security import verify_internal_api_key
from app.db.postgres import get_db
from app.providers.base import AppointmentProviderError
from app.schemas.appointment import AvailabilityRequest, BookingRequest, BookingResult, SlotOut
from app.services import clinic_service
from app.services.appointment_service import book_appointment, check_availability

router = APIRouter(prefix="/api/appointments", tags=["appointments"], dependencies=[Depends(verify_internal_api_key)])


@router.post("/availability", response_model=list[SlotOut])
async def availability(payload: AvailabilityRequest, db: AsyncSession = Depends(get_db)):
    clinic = await _resolved_clinic(db, payload.clinic_id)
    try:
        return await check_availability(
            clinic, str(payload.doctor_id), date.fromisoformat(payload.date)
        )
    except AppointmentProviderError as exc:
        # An unreachable provider is upstream's failure, not a bad request,
        # and it must not be flattened into an empty list -- "no slots" and
        # "we could not find out" mean opposite things to whoever is asking.
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)
        ) from exc


@router.post("/book", response_model=BookingResult)
async def book(payload: BookingRequest, db: AsyncSession = Depends(get_db)):
    clinic = await _resolved_clinic(db, payload.clinic_id)
    return await book_appointment(
        db=db,
        clinic=clinic,
        doctor_id=str(payload.doctor_id),
        caller_number=payload.caller_number,
        patient_name=payload.patient_name,
        slot_start=payload.slot_start,
        slot_end=payload.slot_end,
        call_id=payload.call_id,
        reason=payload.visit_reason,
    )


async def _resolved_clinic(db: AsyncSession, clinic_id):
    # Convenience path for direct API testing (not through Twilio). Reuses
    # the same resolver the voice layer uses, keyed by clinic_id lookup
    # rather than by phone number.
    from sqlalchemy import select
    from app.models.phone_number import PhoneNumber

    row = (
        await db.execute(select(PhoneNumber).where(PhoneNumber.clinic_id == clinic_id))
    ).scalars().first()
    if row is None:
        raise ValueError("Clinic has no mapped phone number; cannot resolve config")
    return await clinic_service.resolve_by_twilio_number(db, row.twilio_number)
