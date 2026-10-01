import pytest

from app.schemas.clinic import ResolvedClinic
from app.services import transfer_service


@pytest.mark.asyncio
async def test_transfer_raises_when_clinic_has_no_receptionist():
    clinic = ResolvedClinic(
        clinic_id=__import__("uuid").uuid4(),
        name="Clinic A",
        timezone="Asia/Kolkata",
        greeting="Hi",
        ai_instructions=None,
        voice_id=None,
        supported_languages=["en-IN"],
        appointment_provider="crudoc",
        appointment_provider_config={},
        doctors=[],
        receptionist_numbers=[],
    )
    with pytest.raises(transfer_service.TransferFailedError):
        await transfer_service.transfer_call("CAxxxx", clinic, reason="test")
