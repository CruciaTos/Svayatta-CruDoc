"""
Appointment business logic. This is the ONLY place that talks to
providers.base.AppointmentProvider adapters or acquires booking locks --
Gemini tool handlers call into this, never into a provider directly.

Concurrency/race-condition strategy (see spec section 8):
  1. Redis lock on (clinic, doctor, slot) narrows the race window and
     avoids two concurrent calls both hitting the provider for the same
     slot.
  2. The provider call itself is the real availability check -- we never
     trust a cached/previous read as proof a slot is free. CruDoc enforces
     this server-side by answering 409 for an occupied slot, which matters
     because it can see appointments the doctor booked inside the app and
     this service's own tables cannot.
  3. The local `appointments` table has a UNIQUE (doctor_id, slot_start)
     constraint as the last-resort guarantee: if the provider is a system
     that doesn't itself enforce atomicity, the local INSERT still fails
     safely on a true collision.
  4. Any failure at any stage returns success=False with alternative
     slots pulled from a fresh availability call -- never a fabricated
     confirmation.
"""
import uuid
from datetime import date, datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.db.redis import slot_lock
from app.models.appointment import Appointment
from app.providers.base import AppointmentProviderError
from app.providers.factory import get_provider
from app.schemas.appointment import BookingResult, SlotOut
from app.schemas.clinic import ResolvedClinic

logger = get_logger(component="appointment_service")


def _doctor_in(clinic: ResolvedClinic, doctor_id: str) -> dict | None:
    """The clinic's record for this doctor, or None.

    Looked up against the immutable ResolvedClinic for the call, which is
    what stops a tool call from reaching another tenant's doctor.
    """
    return next((d for d in clinic.doctors if d["id"] == doctor_id), None)


async def check_availability(
    clinic: ResolvedClinic, doctor_id: str, on_date: date
) -> list[SlotOut]:
    """Real open slots for this doctor.

    Raises AppointmentProviderError if the provider cannot be reached or
    rejects the request. That distinction matters to the caller: an empty
    list means "this day is full", while a failure means "we don't know" --
    and telling a caller the day is full when the calendar is simply
    unreachable is a fabricated answer.
    """
    doctor = _doctor_in(clinic, doctor_id)
    if doctor is None or not doctor.get("external_provider_id"):
        return []

    provider = get_provider(
        clinic.appointment_provider,
        clinic.appointment_provider_config,
        timezone=clinic.timezone,
    )
    return await provider.get_availability(doctor["external_provider_id"], on_date)


async def _alternatives(
    clinic: ResolvedClinic, doctor_id: str, on_date: date
) -> list[SlotOut]:
    """Best-effort alternative slots for a failed booking.

    Swallows provider errors deliberately: we are already on a failure
    path and the caller deserves the booking error itself, not a second
    error raised while trying to be helpful about it.
    """
    try:
        return await check_availability(clinic, doctor_id, on_date)
    except AppointmentProviderError as exc:
        logger.warning(
            "alternatives_lookup_failed",
            clinic_id=str(clinic.clinic_id),
            doctor_id=doctor_id,
            error=str(exc),
        )
        return []


async def book_appointment(
    db: AsyncSession,
    clinic: ResolvedClinic,
    doctor_id: str,
    caller_number: str,
    patient_name: str,
    slot_start: datetime,
    slot_end: datetime,
    call_id: uuid.UUID | None,
    reason: str | None = None,
) -> BookingResult:
    doctor = _doctor_in(clinic, doctor_id)
    if doctor is None or not doctor.get("external_provider_id"):
        return BookingResult(success=False, reason="Doctor not found or not configured")

    if not (patient_name or "").strip():
        # The provider books for a named patient; an unnamed booking gives
        # the clinic no way to know who is arriving.
        return BookingResult(success=False, reason="The caller's name is required to book")

    provider = get_provider(
        clinic.appointment_provider,
        clinic.appointment_provider_config,
        timezone=clinic.timezone,
    )
    lock_key_slot = slot_start.isoformat()

    async with slot_lock(str(clinic.clinic_id), doctor_id, lock_key_slot) as acquired:
        if not acquired:
            alt = await _alternatives(clinic, doctor_id, slot_start.date())
            return BookingResult(
                success=False,
                reason="Someone is currently booking this slot",
                alternative_slots=alt,
            )

        try:
            external_id = await provider.book(
                doctor["external_provider_id"],
                slot_start,
                slot_end,
                caller_number,
                patient_name.strip(),
                reason,
            )
        except AppointmentProviderError as exc:
            logger.warning(
                "booking_rejected_by_provider",
                clinic_id=str(clinic.clinic_id),
                doctor_id=doctor_id,
                error=str(exc),
            )
            alt = await _alternatives(clinic, doctor_id, slot_start.date())
            return BookingResult(success=False, reason=str(exc), alternative_slots=alt)

        appointment = Appointment(
            clinic_id=clinic.clinic_id,
            doctor_id=uuid.UUID(doctor_id),
            call_id=call_id,
            caller_number=caller_number,
            patient_name=patient_name.strip(),
            slot_start=slot_start,
            slot_end=slot_end,
            status="confirmed",
            external_appointment_id=external_id,
        )
        db.add(appointment)
        try:
            await db.commit()
        except IntegrityError:
            # Local uniqueness constraint tripped -- another booking for
            # this exact slot committed first. Roll back and cancel the
            # just-made provider booking so we don't leave an orphaned
            # double-booking on the doctor's calendar.
            await db.rollback()
            logger.error(
                "local_double_booking_detected",
                clinic_id=str(clinic.clinic_id),
                doctor_id=doctor_id,
                slot_start=lock_key_slot,
            )
            try:
                await provider.cancel(external_id)
            except AppointmentProviderError:
                logger.error(
                    "failed_to_unwind_provider_booking",
                    external_appointment_id=external_id,
                )
            alt = await _alternatives(clinic, doctor_id, slot_start.date())
            return BookingResult(
                success=False, reason="Slot was just booked by someone else", alternative_slots=alt
            )

        await db.refresh(appointment)
        return BookingResult(
            success=True,
            appointment_id=appointment.id,
            external_appointment_id=external_id,
        )
