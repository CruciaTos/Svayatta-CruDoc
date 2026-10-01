import pytest

from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.phone_number import PhoneNumber
from app.services.clinic_service import resolve_by_twilio_number


@pytest.mark.asyncio
async def test_resolving_one_number_never_returns_another_clinics_doctors(db_session):
    clinic_a = Clinic(name="Clinic A", config={}, ai_receptionist_enabled=True)
    clinic_b = Clinic(name="Clinic B", config={}, ai_receptionist_enabled=True)
    db_session.add_all([clinic_a, clinic_b])
    await db_session.flush()

    db_session.add_all(
        [
            Doctor(clinic_id=clinic_a.id, name="Dr. A1", active=True),
            Doctor(clinic_id=clinic_b.id, name="Dr. B1", active=True),
            PhoneNumber(clinic_id=clinic_a.id, twilio_number="+911111111111", active=True),
            PhoneNumber(clinic_id=clinic_b.id, twilio_number="+912222222222", active=True),
        ]
    )
    await db_session.commit()

    resolved = await resolve_by_twilio_number(db_session, "+911111111111")

    assert resolved.clinic_id == clinic_a.id
    assert [d["name"] for d in resolved.doctors] == ["Dr. A1"]
