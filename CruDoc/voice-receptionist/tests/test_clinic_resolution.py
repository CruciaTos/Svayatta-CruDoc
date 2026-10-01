import pytest

from app.models.clinic import Clinic
from app.models.phone_number import PhoneNumber
from app.services.clinic_service import ClinicNotFoundError, resolve_by_twilio_number


@pytest.mark.asyncio
async def test_unmapped_number_raises_not_found(db_session):
    with pytest.raises(ClinicNotFoundError):
        await resolve_by_twilio_number(db_session, "+910000000000")


@pytest.mark.asyncio
async def test_inactive_phone_number_is_not_resolved(db_session):
    clinic = Clinic(name="Clinic A", config={})
    db_session.add(clinic)
    await db_session.flush()
    db_session.add(PhoneNumber(clinic_id=clinic.id, twilio_number="+913333333333", active=False))
    await db_session.commit()

    with pytest.raises(ClinicNotFoundError):
        await resolve_by_twilio_number(db_session, "+913333333333")
