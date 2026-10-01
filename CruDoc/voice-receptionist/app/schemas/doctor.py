import uuid

from pydantic import BaseModel, ConfigDict


class DoctorCreate(BaseModel):
    name: str
    specialization: str | None = None
    external_provider_id: str | None = None


class DoctorOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    clinic_id: uuid.UUID
    name: str
    specialization: str | None
    active: bool
