"""
Verifies the last-resort guarantee: even if the Redis lock is bypassed
entirely, the DB-level UNIQUE(doctor_id, slot_start) constraint prevents
two committed bookings for the same slot.
"""
import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy.exc import IntegrityError

from app.models.appointment import Appointment
from app.models.clinic import Clinic
from app.models.doctor import Doctor


@pytest.mark.asyncio
async def test_duplicate_slot_booking_is_rejected_at_db_level(db_session):
    clinic = Clinic(name="Test Clinic", config={})
    db_session.add(clinic)
    await db_session.flush()
    doctor = Doctor(clinic_id=clinic.id, name="Test Doctor")
    db_session.add(doctor)
    await db_session.flush()

    clinic_id = clinic.id
    doctor_id = doctor.id
    slot_start = datetime.now(timezone.utc).replace(microsecond=0)
    slot_end = slot_start + timedelta(minutes=30)

    db_session.add(
        Appointment(
            clinic_id=clinic_id,
            doctor_id=doctor_id,
            caller_number="+911234567890",
            slot_start=slot_start,
            slot_end=slot_end,
            status="confirmed",
        )
    )
    await db_session.commit()

    db_session.add(
        Appointment(
            clinic_id=clinic_id,
            doctor_id=doctor_id,
            caller_number="+919876543210",
            slot_start=slot_start,
            slot_end=slot_end,
            status="confirmed",
        )
    )
    with pytest.raises(IntegrityError):
        await db_session.commit()
