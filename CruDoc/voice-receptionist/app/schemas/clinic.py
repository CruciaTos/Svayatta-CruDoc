import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class ClinicConfig(BaseModel):
    """Structure of Clinic.config. Kept permissive (extra allowed) since
    new business config fields will be added over time without migrations."""
    model_config = ConfigDict(extra="allow")

    greeting: str = "Thank you for calling. How can I help you today?"
    supported_languages: list[str] = ["en-IN"]
    voice_id: str | None = None
    ai_instructions: str | None = None
    appointment_provider: str = "crudoc"
    appointment_provider_config: dict = {}


class ClinicCreate(BaseModel):
    name: str
    timezone: str = "Asia/Kolkata"
    address: str | None = None
    contact_email: str | None = None
    contact_phone: str | None = None
    config: ClinicConfig = ClinicConfig()
    # Premium switch; phone calls are refused while false.
    ai_receptionist_enabled: bool = False


class ClinicOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    timezone: str
    status: str
    ai_receptionist_enabled: bool
    config: dict
    created_at: datetime


class ResolvedClinic(BaseModel):
    """Everything the voice layer needs for one call, assembled once at
    call start and never mutated by other calls."""
    model_config = ConfigDict(from_attributes=True)

    clinic_id: uuid.UUID
    name: str
    timezone: str
    greeting: str
    ai_instructions: str | None
    voice_id: str | None
    supported_languages: list[str]
    appointment_provider: str
    appointment_provider_config: dict
    doctors: list[dict]
    receptionist_numbers: list[str]
    # Set when the call came in on a dedicated receptionist line.
    line_id: uuid.UUID | None = None
    line_label: str | None = None
