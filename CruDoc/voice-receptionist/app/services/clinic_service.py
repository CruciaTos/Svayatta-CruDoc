"""
Tenant resolution and clinic configuration assembly.

resolve_by_twilio_number() is the single entry point that turns an inbound
Twilio number into a fully-loaded ResolvedClinic. This is called exactly
once per call, at call start, and the result is handed to that call's
CallSession -- it is never re-fetched or shared across calls.
"""
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.phone_number import PhoneNumber
from app.models.receptionist import Receptionist
from app.schemas.clinic import ResolvedClinic


class ClinicNotFoundError(Exception):
    pass


class ReceptionistNotEnabledError(ClinicNotFoundError):
    """The clinic exists but has not been given the premium AI receptionist.

    A subclass so callers that only care "can this call be served?" handle
    it like an unmapped number.
    """


# Line-level keys that override the clinic's own config when set.
LINE_OVERRIDE_KEYS = ("greeting", "voice_id", "ai_instructions", "supported_languages")


async def resolve_by_twilio_number(db: AsyncSession, twilio_number: str) -> ResolvedClinic:
    stmt = (
        select(PhoneNumber)
        .where(PhoneNumber.twilio_number == twilio_number, PhoneNumber.active.is_(True))
    )
    phone_row = (await db.execute(stmt)).scalar_one_or_none()
    if phone_row is None:
        raise ClinicNotFoundError(f"No active clinic mapped to {twilio_number}")

    return await _assemble(db, phone_row.clinic_id, phone_row)


async def resolve_by_line_id(db: AsyncSession, line_id: uuid.UUID) -> ResolvedClinic:
    """Resolve a live call's receptionist line by its id (carried in the
    Media Streams URL, which /twilio/voice built from the dialed number)."""
    phone_row = await db.get(PhoneNumber, line_id)
    if phone_row is None or not phone_row.active:
        raise ClinicNotFoundError(f"Receptionist line {line_id} not found or inactive")
    return await _assemble(db, phone_row.clinic_id, phone_row)


async def resolve_by_clinic_id(db: AsyncSession, clinic_id: uuid.UUID) -> ResolvedClinic:
    """Clinic-wide view (every active doctor). Used by the dev-only browser
    voice test, which has no phone line and is not premium-gated."""
    return await _assemble(db, clinic_id, None)


async def _assemble(
    db: AsyncSession, clinic_id: uuid.UUID, line: PhoneNumber | None
) -> ResolvedClinic:
    clinic = await db.get(Clinic, clinic_id)
    if clinic is None or clinic.status != "active":
        raise ClinicNotFoundError(f"Clinic {clinic_id} not found or inactive")
    if line is not None and not clinic.ai_receptionist_enabled:
        raise ReceptionistNotEnabledError(f"AI receptionist is not enabled for clinic {clinic_id}")

    doctors = (
        await db.execute(
            select(Doctor).where(Doctor.clinic_id == clinic.id, Doctor.active.is_(True))
        )
    ).scalars().all()
    if line is not None and line.doctors:
        # A dedicated line represents only its own doctor(s). Everything the
        # model can see or book is derived from this list, so this is what
        # keeps one doctor's receptionist from touching another's calendar.
        allowed = {d.id for d in line.doctors}
        doctors = [d for d in doctors if d.id in allowed]

    receptionist_stmt = select(Receptionist).where(
        Receptionist.clinic_id == clinic.id, Receptionist.active.is_(True)
    )
    receptionists = (await db.execute(receptionist_stmt)).scalars().all()
    line_id = line.id if line is not None else None
    # This line's own humans first, then the clinic-wide ones.
    receptionists = sorted(
        receptionists,
        key=lambda r: (r.phone_number_id != line_id, r.priority),
    )
    receptionists = [r for r in receptionists if r.phone_number_id in (None, line_id)]

    cfg = dict(clinic.config or {})
    label = line.label if line is not None else None
    if line is not None:
        cfg.update({k: v for k, v in (line.config or {}).items() if k in LINE_OVERRIDE_KEYS and v})

    return ResolvedClinic(
        clinic_id=clinic.id,
        name=clinic.name,
        timezone=clinic.timezone,
        greeting=cfg.get("greeting", f"Thank you for calling {label or clinic.name}. How can I help?"),
        ai_instructions=cfg.get("ai_instructions"),
        voice_id=cfg.get("voice_id"),
        supported_languages=cfg.get("supported_languages", ["en-IN"]),
        appointment_provider=cfg.get("appointment_provider", "crudoc"),
        appointment_provider_config=cfg.get("appointment_provider_config", {}),
        doctors=[
            {
                "id": str(d.id),
                "name": d.name,
                "specialization": d.specialization,
                "external_provider_id": d.external_provider_id,
            }
            for d in doctors
        ],
        receptionist_numbers=[r.phone_number for r in receptionists],
        line_id=line_id,
        line_label=label,
    )
