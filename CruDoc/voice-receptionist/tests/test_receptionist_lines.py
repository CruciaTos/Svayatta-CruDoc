"""Dedicated per-doctor / per-group receptionist lines and the premium gate."""
import httpx
import pytest

from app.core.config import get_settings
from app.main import app
from app.services.clinic_service import (
    ClinicNotFoundError,
    ReceptionistNotEnabledError,
    resolve_by_clinic_id,
    resolve_by_twilio_number,
)
from app.voice.prompts import build_system_prompt

KEY = "test-admin-key"
AMIT = {"external_provider_id": "uid-amit", "name": "Dr. Amit", "specialization": "Dentist"}
RIYA = {"external_provider_id": "uid-riya", "name": "Dr. Riya", "specialization": "Orthodontist"}
NEHA = {"external_provider_id": "uid-neha", "name": "Dr. Neha"}


@pytest.fixture
def api(monkeypatch, db_session):
    monkeypatch.setenv("VOICE_BOT_API_KEY", KEY)
    get_settings.cache_clear()
    client = httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app), base_url="http://t", headers={"x-api-key": KEY}
    )
    yield client
    get_settings.cache_clear()


def body(doctors, enabled=True, **extra):
    return {
        "clinic": {"external_id": "clinic-1", "name": "Smile Clinic", "ai_receptionist_enabled": enabled},
        "doctors": doctors,
        **extra,
    }


async def test_each_doctor_gets_own_line_seeing_only_their_calendar(api, db_session):
    await api.put("/api/admin/receptionist-lines/+14155550001", json=body([AMIT], label="Dr. Amit"))
    await api.put("/api/admin/receptionist-lines/+14155550002", json=body([RIYA, NEHA], label="Ortho team"))

    solo = await resolve_by_twilio_number(db_session, "+14155550001")
    group = await resolve_by_twilio_number(db_session, "+14155550002")

    assert [d["name"] for d in solo.doctors] == ["Dr. Amit"]
    assert sorted(d["name"] for d in group.doctors) == ["Dr. Neha", "Dr. Riya"]
    assert solo.clinic_id == group.clinic_id
    assert solo.line_id != group.line_id
    assert "Dr. Riya" not in build_system_prompt(solo)
    assert "Dr. Amit (Smile Clinic)" in build_system_prompt(solo)


async def test_line_with_no_doctors_is_clinic_wide(api, db_session):
    await api.put("/api/admin/receptionist-lines/+14155550001", json=body([AMIT, RIYA]))
    await api.put("/api/admin/receptionist-lines/+14155550003", json=body([]))
    wide = await resolve_by_twilio_number(db_session, "+14155550003")
    assert len(wide.doctors) == 2


async def test_premium_gate_blocks_calls_but_not_browser_test(api, db_session):
    await api.put("/api/admin/receptionist-lines/+14155550001", json=body([AMIT], enabled=False))
    with pytest.raises(ReceptionistNotEnabledError):
        await resolve_by_twilio_number(db_session, "+14155550001")
    assert issubclass(ReceptionistNotEnabledError, ClinicNotFoundError)

    r = await api.put("/api/admin/clinics/clinic-1/entitlement", json={"enabled": True})
    assert r.json()["ai_receptionist_enabled"] is True
    resolved = await resolve_by_twilio_number(db_session, "+14155550001")

    await api.put("/api/admin/clinics/clinic-1/entitlement", json={"enabled": False})
    with pytest.raises(ReceptionistNotEnabledError):
        await resolve_by_twilio_number(db_session, "+14155550001")
    # dev-only browser sandbox is not premium-gated
    await resolve_by_clinic_id(db_session, resolved.clinic_id)


async def test_line_overrides_and_fallback_humans(api, db_session):
    await api.put(
        "/api/admin/receptionist-lines/+14155550001",
        json=body(
            [AMIT],
            config={"greeting": "Dr. Amit's office, how can I help?", "voice_id": ""},
            receptionist_numbers=["+919800000001", "+919800000002"],
        ),
    )
    r = await resolve_by_twilio_number(db_session, "+14155550001")
    assert r.greeting == "Dr. Amit's office, how can I help?"
    assert r.receptionist_numbers == ["+919800000001", "+919800000002"]


async def test_upsert_is_idempotent_and_updates_doctors(api, db_session):
    for _ in range(2):
        r = await api.put("/api/admin/receptionist-lines/+14155550001", json=body([AMIT, RIYA]))
        assert r.status_code == 200
    r = await api.put("/api/admin/receptionist-lines/+14155550001", json=body([RIYA]))
    assert [d["name"] for d in r.json()["doctors"]] == ["Dr. Riya"]
    listed = (await api.get("/api/admin/receptionist-lines?clinic_external_id=clinic-1")).json()
    assert len(listed["lines"]) == 1


async def test_number_cannot_move_between_clinics(api):
    await api.put("/api/admin/receptionist-lines/+14155550001", json=body([AMIT]))
    other = body([AMIT])
    other["clinic"]["external_id"] = "clinic-2"
    assert (await api.put("/api/admin/receptionist-lines/+14155550001", json=other)).status_code == 409


async def test_deactivated_line_stops_resolving(api, db_session):
    await api.put("/api/admin/receptionist-lines/+14155550001", json=body([AMIT]))
    assert (await api.delete("/api/admin/receptionist-lines/+14155550001")).json()["active"] is False
    with pytest.raises(ClinicNotFoundError):
        await resolve_by_twilio_number(db_session, "+14155550001")


async def test_admin_api_requires_key_and_valid_number(api):
    anon = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://t")
    assert (await anon.get("/api/admin/receptionist-lines")).status_code == 401
    assert (await api.put("/api/admin/receptionist-lines/12345", json=body([AMIT]))).status_code == 422


# ------------------------------------------------------------ observability


async def _seed_call(db_session, number, outcome, *, booked_for=None, minutes=3):
    from datetime import datetime, timedelta, timezone

    from sqlalchemy import select

    from app.models.appointment import Appointment
    from app.models.call import Call
    from app.models.doctor import Doctor
    from app.models.phone_number import PhoneNumber

    line = (
        await db_session.execute(select(PhoneNumber).where(PhoneNumber.twilio_number == number))
    ).scalar_one()
    start = datetime.now(timezone.utc) - timedelta(hours=1)
    call = Call(
        clinic_id=line.clinic_id,
        phone_number_id=line.id,
        twilio_call_sid=f"CA{outcome}{minutes}",
        caller_number="+919999999999",
        status="completed",
        outcome=outcome,
        start_time=start,
        end_time=start + timedelta(minutes=minutes),
    )
    db_session.add(call)
    await db_session.flush()
    if booked_for:
        doctor = (
            await db_session.execute(select(Doctor).where(Doctor.external_provider_id == booked_for))
        ).scalar_one()
        db_session.add(
            Appointment(
                clinic_id=line.clinic_id,
                doctor_id=doctor.id,
                call_id=call.id,
                caller_number="+919999999999",
                patient_name="Asha",
                slot_start=start + timedelta(days=1),
                slot_end=start + timedelta(days=1, minutes=30),
                external_appointment_id="crudoc-1",
            )
        )
    await db_session.commit()


async def test_calls_and_bookings_are_visible_per_line(api, db_session):
    await api.put("/api/admin/receptionist-lines/+14155550001", json=body([AMIT]))
    await api.put("/api/admin/receptionist-lines/+14155550002", json=body([RIYA]))
    await _seed_call(db_session, "+14155550001", "booked", booked_for="uid-amit")
    await _seed_call(db_session, "+14155550001", "transferred", minutes=1)
    await _seed_call(db_session, "+14155550002", "no_action")

    r = (await api.get("/api/admin/calls?twilio_number=%2B14155550001")).json()
    assert r["summary"]["total"] == 2
    assert r["summary"]["by_outcome"] == {"booked": 1, "transferred": 1}
    booked = next(c for c in r["calls"] if c["outcome"] == "booked")
    assert booked["duration_seconds"] == 180
    assert booked["appointments"][0]["patient_name"] == "Asha"
    assert booked["appointments"][0]["doctor_name"] == "Dr. Amit"

    everything = (await api.get("/api/admin/calls?clinic_external_id=clinic-1")).json()
    assert everything["summary"]["total"] == 3

    appts = (await api.get("/api/admin/appointments?clinic_external_id=clinic-1")).json()
    assert [a["doctor_name"] for a in appts["appointments"]] == ["Dr. Amit"]
    assert appts["appointments"][0]["twilio_number"] == "+14155550001"


async def test_status_reports_without_calling_providers(api):
    r = (await api.get("/api/admin/status")).json()
    assert r["service"]["status"] in {"ok", "degraded"}
    assert r["providers"] is None
    assert "twilio_configured" in r


async def test_successful_booking_marks_the_call_booked():
    import uuid

    from app.schemas.appointment import BookingResult
    from app.schemas.clinic import ResolvedClinic
    from app.services import appointment_service
    from app.voice.call_session import CallSession
    from app.voice.tools import ToolExecutor

    session = CallSession(
        call_id=uuid.uuid4(),
        clinic=ResolvedClinic(
            clinic_id=uuid.uuid4(), name="C", timezone="Asia/Kolkata", greeting="Hi",
            ai_instructions=None, voice_id=None, supported_languages=["en-IN"],
            appointment_provider="crudoc", appointment_provider_config={}, doctors=[],
            receptionist_numbers=[],
        ),
        twilio_call_sid="CA1",
        caller_phone="+919999999999",
    )

    async def fake_book(**kwargs):
        return BookingResult(success=True, external_appointment_id="x")

    original = appointment_service.book_appointment
    appointment_service.book_appointment = fake_book
    try:
        await ToolExecutor(db=None, session=session).dispatch(
            "book_appointment",
            {
                "doctor_id": str(uuid.uuid4()),
                "patient_name": "Asha",
                "slot_start": "2026-10-02T10:00:00+05:30",
                "slot_end": "2026-10-02T10:30:00+05:30",
            },
        )
    finally:
        appointment_service.book_appointment = original
    assert session.appointments_booked == 1
