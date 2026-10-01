import uuid
from datetime import datetime

from pydantic import BaseModel


class AvailabilityRequest(BaseModel):
    clinic_id: uuid.UUID
    doctor_id: uuid.UUID
    date: str  # ISO date, clinic-local


class SlotOut(BaseModel):
    start: datetime
    end: datetime


class BookingRequest(BaseModel):
    clinic_id: uuid.UUID
    doctor_id: uuid.UUID
    caller_number: str
    # The name the appointment is booked under. Required because the
    # appointment provider books for a named patient -- CruDoc rejects a
    # booking without one, and a phone number alone gives the clinic no way
    # to recognise who is arriving.
    patient_name: str
    slot_start: datetime
    slot_end: datetime
    call_id: uuid.UUID | None = None
    # Why the patient is coming in, if they said. Named to distinguish it
    # from BookingResult.reason, which is why a booking *failed*.
    visit_reason: str | None = None


class BookingResult(BaseModel):
    success: bool
    appointment_id: uuid.UUID | None = None
    external_appointment_id: str | None = None
    reason: str | None = None
    alternative_slots: list[SlotOut] = []
