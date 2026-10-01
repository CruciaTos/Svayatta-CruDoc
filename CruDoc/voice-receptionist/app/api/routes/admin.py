"""
Super Admin provisioning API for dedicated AI receptionist lines.

The premium AI receptionist is sold per doctor / doctor group: each gets its
own phone number and its own receptionist. These endpoints are idempotent
(`PUT` upserts) so the CruDoc Super Admin backend can re-sync without
tracking what already exists, and they identify everything by CruDoc's own
IDs (`clinic.external_id`, the doctors' Firebase UIDs) rather than this
service's internal UUIDs.

Called only by the `manageReceptionistLines` Cloud Function, which checks
the caller is a Super Admin and holds the `x-api-key`; that key must never
ship in a client app.
"""
import re
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.routes.health import health
from app.core.config import get_settings
from app.core.security import verify_internal_api_key
from app.db.postgres import get_db
from app.models.appointment import Appointment
from app.models.call import Call
from app.models.clinic import Clinic
from app.models.doctor import Doctor
from app.models.phone_number import PhoneNumber
from app.models.receptionist import Receptionist
from app.services.clinic_service import LINE_OVERRIDE_KEYS

router = APIRouter(
    prefix="/api/admin", tags=["admin"], dependencies=[Depends(verify_internal_api_key)]
)

E164 = re.compile(r"^\+[1-9]\d{6,14}$")


def _e164(number: str) -> str:
    if not E164.match(number):
        raise HTTPException(status_code=422, detail="Phone number must be E.164, e.g. +14155550123")
    return number


class ClinicUpsert(BaseModel):
    external_id: str = Field(min_length=1, max_length=128)
    name: str
    timezone: str = "Asia/Kolkata"
    ai_receptionist_enabled: bool = False
    # appointment_provider / appointment_provider_config etc. Replaces the
    # clinic's config when provided; omitted -> left untouched.
    config: dict[str, Any] | None = None


class DoctorRef(BaseModel):
    external_provider_id: str = Field(min_length=1, max_length=255)  # Firebase UID
    name: str
    specialization: str | None = None


class LineUpsert(BaseModel):
    clinic: ClinicUpsert
    label: str | None = None
    active: bool = True
    # Empty -> clinic-wide line. One entry -> that doctor's own number.
    doctors: list[DoctorRef] = []
    # Humans this line falls back to, best first. Clinic-wide receptionists
    # are still appended after these.
    receptionist_numbers: list[str] = []
    # Subset of greeting / voice_id / ai_instructions / supported_languages.
    config: dict[str, Any] = {}


class Entitlement(BaseModel):
    enabled: bool


async def _line_out(db: AsyncSession, line: PhoneNumber) -> dict:
    clinic = await db.get(Clinic, line.clinic_id)
    humans = (
        await db.execute(
            select(Receptionist)
            .where(Receptionist.phone_number_id == line.id, Receptionist.active.is_(True))
            .order_by(Receptionist.priority)
        )
    ).scalars().all()
    return {
        "twilio_number": line.twilio_number,
        "line_id": str(line.id),
        "label": line.label,
        "active": line.active,
        "clinic": {
            "external_id": clinic.external_id,
            "name": clinic.name,
            "ai_receptionist_enabled": clinic.ai_receptionist_enabled,
        },
        "doctors": [
            {
                "external_provider_id": d.external_provider_id,
                "name": d.name,
                "specialization": d.specialization,
            }
            for d in line.doctors
        ],
        "receptionist_numbers": [h.phone_number for h in humans],
        "config": line.config or {},
    }


@router.put("/receptionist-lines/{twilio_number}")
async def upsert_line(
    twilio_number: str,
    payload: LineUpsert,
    db: AsyncSession = Depends(get_db),
) -> dict:
    number = _e164(twilio_number)
    humans = [_e164(n) for n in payload.receptionist_numbers]
    unknown = set(payload.config) - set(LINE_OVERRIDE_KEYS)
    if unknown:
        raise HTTPException(status_code=422, detail=f"Unsupported line config keys: {sorted(unknown)}")

    spec = payload.clinic
    clinic = (
        await db.execute(select(Clinic).where(Clinic.external_id == spec.external_id))
    ).scalar_one_or_none()
    if clinic is None:
        clinic = Clinic(external_id=spec.external_id, name=spec.name, config=spec.config or {})
        db.add(clinic)
    clinic.name = spec.name
    clinic.timezone = spec.timezone
    clinic.ai_receptionist_enabled = spec.ai_receptionist_enabled
    if spec.config is not None:
        clinic.config = spec.config
    await db.flush()

    line = (
        await db.execute(select(PhoneNumber).where(PhoneNumber.twilio_number == number))
    ).scalar_one_or_none()
    if line is not None and line.clinic_id != clinic.id:
        # Never silently move a number between tenants.
        raise HTTPException(status_code=409, detail="Number is already assigned to another clinic")
    if line is None:
        line = PhoneNumber(clinic_id=clinic.id, twilio_number=number)
        db.add(line)
    line.label = payload.label
    line.active = payload.active
    line.config = payload.config

    # Upsert this line's doctors by their CruDoc UID within the clinic.
    existing = {
        d.external_provider_id: d
        for d in (
            await db.execute(select(Doctor).where(Doctor.clinic_id == clinic.id))
        ).scalars()
    }
    assigned: list[Doctor] = []
    for ref in payload.doctors:
        doctor = existing.get(ref.external_provider_id)
        if doctor is None:
            doctor = Doctor(
                clinic_id=clinic.id, external_provider_id=ref.external_provider_id, name=ref.name
            )
            db.add(doctor)
        doctor.name = ref.name
        doctor.specialization = ref.specialization
        doctor.active = True
        assigned.append(doctor)
    await db.flush()
    # Assigning to a persistent object's unloaded collection would lazy-load
    # its old value, which async sessions cannot do implicitly.
    await db.refresh(line, attribute_names=["doctors"])
    line.doctors = assigned
    await db.flush()

    await db.execute(delete(Receptionist).where(Receptionist.phone_number_id == line.id))
    for priority, human in enumerate(humans):
        db.add(
            Receptionist(
                clinic_id=clinic.id, phone_number_id=line.id, phone_number=human, priority=priority
            )
        )
    await db.commit()
    await db.refresh(line)
    return await _line_out(db, line)


@router.get("/receptionist-lines")
async def list_lines(clinic_external_id: str | None = None, db: AsyncSession = Depends(get_db)) -> dict:
    stmt = select(PhoneNumber).join(Clinic, Clinic.id == PhoneNumber.clinic_id)
    if clinic_external_id:
        stmt = stmt.where(Clinic.external_id == clinic_external_id)
    lines = (await db.execute(stmt.order_by(PhoneNumber.twilio_number))).scalars().all()
    return {"lines": [await _line_out(db, line) for line in lines]}


@router.delete("/receptionist-lines/{twilio_number}")
async def deactivate_line(twilio_number: str, db: AsyncSession = Depends(get_db)) -> dict:
    """Stops answering the number. The row is kept so call history stays linked."""
    line = (
        await db.execute(select(PhoneNumber).where(PhoneNumber.twilio_number == _e164(twilio_number)))
    ).scalar_one_or_none()
    if line is None:
        raise HTTPException(status_code=404, detail="Line not found")
    line.active = False
    await db.commit()
    return await _line_out(db, line)


@router.put("/clinics/{external_id}/entitlement")
async def set_entitlement(external_id: str, payload: Entitlement, db: AsyncSession = Depends(get_db)) -> dict:
    """The premium switch. Off -> every line of this clinic stops answering
    (callers hear the 'not configured' message); nothing is deleted."""
    clinic = (
        await db.execute(select(Clinic).where(Clinic.external_id == external_id))
    ).scalar_one_or_none()
    if clinic is None:
        raise HTTPException(status_code=404, detail="Clinic not provisioned yet")
    clinic.ai_receptionist_enabled = payload.enabled
    await db.commit()
    return {"external_id": external_id, "ai_receptionist_enabled": clinic.ai_receptionist_enabled}


# ---------------------------------------------------------------- observability


@router.get("/status")
async def service_status(deep: bool = False, db: AsyncSession = Depends(get_db)) -> dict:
    """Is the voice service able to take calls?

    `deep=true` also makes one real Sarvam TTS and one Gemini request (the
    same checks as /voice-test/preflight), so it costs a little and takes a
    few seconds -- the console only asks for it on demand.
    """
    settings = get_settings()
    result: dict[str, Any] = {
        "service": await health(db),
        "twilio_configured": bool(settings.twilio_account_sid and settings.twilio_auth_token),
        "public_base_url": settings.public_base_url or None,
        "gemini_model": settings.gemini_model,
        "providers": None,
    }
    if deep:
        from app.voice.preflight import run_preflight

        report = await run_preflight(None)
        # The clinic check only makes sense for the browser sandbox.
        result["providers"] = {k: v for k, v in report["checks"].items() if k != "clinic"}
    return result


def _since(days: int) -> datetime:
    return datetime.now(timezone.utc) - timedelta(days=days)


def _utc(value: datetime) -> datetime:
    # SQLite drops the offset; values are always stored as UTC.
    return value.replace(tzinfo=timezone.utc) if value.tzinfo is None else value


def _iso(value: datetime | None) -> str | None:
    return _utc(value).isoformat() if value is not None else None


@router.get("/calls")
async def list_calls(
    clinic_external_id: str | None = None,
    twilio_number: str | None = None,
    days: int = Query(7, ge=1, le=90),
    limit: int = Query(50, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Recent calls, newest first, with what the AI booked on each, plus an
    outcome breakdown over the whole window (not just the returned page)."""
    stmt = (
        select(Call, Clinic, PhoneNumber)
        .join(Clinic, Clinic.id == Call.clinic_id)
        .outerjoin(PhoneNumber, PhoneNumber.id == Call.phone_number_id)
        .where(Call.start_time >= _since(days))
    )
    if clinic_external_id:
        stmt = stmt.where(Clinic.external_id == clinic_external_id)
    if twilio_number:
        stmt = stmt.where(PhoneNumber.twilio_number == twilio_number)

    rows = (await db.execute(stmt.order_by(Call.start_time.desc()))).all()

    summary: dict[str, int] = {}
    for call, _, _ in rows:
        key = call.outcome or call.status
        summary[key] = summary.get(key, 0) + 1

    page = rows[:limit]
    call_ids = [call.id for call, _, _ in page]
    booked: dict = {}
    if call_ids:
        appts = (
            await db.execute(
                select(Appointment, Doctor)
                .join(Doctor, Doctor.id == Appointment.doctor_id)
                .where(Appointment.call_id.in_(call_ids))
            )
        ).all()
        for appt, doctor in appts:
            booked.setdefault(appt.call_id, []).append(
                {
                    "patient_name": appt.patient_name,
                    "doctor_name": doctor.name,
                    "slot_start": _iso(appt.slot_start),
                    "status": appt.status,
                }
            )

    calls = []
    for call, clinic, line in page:
        end = call.end_time
        duration = (
            int((_utc(end) - _utc(call.start_time)).total_seconds()) if end is not None else None
        )
        calls.append(
            {
                "id": str(call.id),
                "clinic_external_id": clinic.external_id,
                "clinic_name": clinic.name,
                "twilio_number": line.twilio_number if line else None,
                "line_label": line.label if line else None,
                "caller_number": call.caller_number,
                "status": call.status,
                "outcome": call.outcome,
                "start_time": _iso(call.start_time),
                "end_time": _iso(end),
                "duration_seconds": duration,
                "appointments": booked.get(call.id, []),
            }
        )
    return {"calls": calls, "summary": {"total": len(rows), "by_outcome": summary, "days": days}}


@router.get("/appointments")
async def list_ai_appointments(
    clinic_external_id: str | None = None,
    days: int = Query(30, ge=1, le=365),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Appointments the AI receptionist booked, newest first. CruDoc stays the
    source of truth for each booking; this is the receptionist's own log."""
    stmt = (
        select(Appointment, Doctor, Clinic, PhoneNumber)
        .join(Doctor, Doctor.id == Appointment.doctor_id)
        .join(Clinic, Clinic.id == Appointment.clinic_id)
        .outerjoin(Call, Call.id == Appointment.call_id)
        .outerjoin(PhoneNumber, PhoneNumber.id == Call.phone_number_id)
        .where(Appointment.created_at >= _since(days))
    )
    if clinic_external_id:
        stmt = stmt.where(Clinic.external_id == clinic_external_id)
    rows = (
        await db.execute(stmt.order_by(Appointment.created_at.desc()).limit(limit))
    ).all()
    return {
        "appointments": [
            {
                "id": str(appt.id),
                "external_appointment_id": appt.external_appointment_id,
                "clinic_external_id": clinic.external_id,
                "clinic_name": clinic.name,
                "twilio_number": line.twilio_number if line else None,
                "doctor_name": doctor.name,
                "doctor_id": doctor.external_provider_id,
                "patient_name": appt.patient_name,
                "caller_number": appt.caller_number,
                "slot_start": _iso(appt.slot_start),
                "slot_end": _iso(appt.slot_end),
                "status": appt.status,
                "booked_at": _iso(appt.created_at),
            }
            for appt, doctor, clinic, line in rows
        ]
    }
