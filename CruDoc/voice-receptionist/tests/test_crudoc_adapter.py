"""
Wire-contract tests for the CruDoc adapter.

These exist because the adapter previously targeted an invented REST shape
-- bearer auth, /providers/{id}/appointments, slot_start/slot_end keys --
while CruDoc's actual Cloud Function wants an X-Api-Key header, a flat
/createAppointment path and patient_name/phone/doctor_id. Nothing failed at
import time or in a type check; every call would simply have 401'd and then
400'd against the real backend.

So the assertions here are deliberately about the bytes on the wire: header
name, path, payload keys and status-code handling, checked against a mock
transport. They are the layer that would have caught the original mismatch.

Kept in sync with CruDoc/functions/src/appointments.ts.
"""
import json
from datetime import date, datetime, timezone

import httpx
import pytest

from app.providers.base import AppointmentProviderError
from app.providers.crudoc_adapter import CruDocAdapter

BASE_URL = "https://asia-south1-svayatta-crudoc-dev.cloudfunctions.net"
API_KEY = "test-shared-secret"


def _adapter(handler, **kwargs) -> CruDocAdapter:
    """A real adapter with only its transport swapped for a mock.

    The client is built by __init__ exactly as in production, so the
    headers and base_url under test are the genuine ones; replacing the
    transport intercepts the fully-built request on its way out.
    """
    adapter = CruDocAdapter(base_url=BASE_URL, api_key=API_KEY, **kwargs)
    # _mounts is populated from HTTP(S)_PROXY in the environment and is
    # consulted before _transport, so it has to be cleared or the request
    # goes to a real proxy instead of the mock.
    adapter._client._mounts = {}
    adapter._client._transport = httpx.MockTransport(handler)
    return adapter


def _json_response(status: int, body: dict) -> httpx.Response:
    return httpx.Response(status, json=body)


class TestAuthAndRouting:
    @pytest.mark.asyncio
    async def test_uses_x_api_key_header_not_bearer_token(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["headers"] = request.headers
            return _json_response(201, {"success": True, "appointment_id": "a1"})

        await _adapter(handler).book(
            "doc-uid", datetime(2026, 10, 3, 10, 30), datetime(2026, 10, 3, 11, 0),
            "+919876543210", "Asha Rao",
        )

        assert seen["headers"]["x-api-key"] == API_KEY
        # A bearer token is what the endpoint does NOT accept -- it would 401.
        assert "authorization" not in seen["headers"]

    @pytest.mark.asyncio
    async def test_book_posts_to_flat_create_appointment_path(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["url"] = str(request.url)
            seen["method"] = request.method
            return _json_response(201, {"success": True, "appointment_id": "a1"})

        await _adapter(handler).book(
            "doc-uid", datetime(2026, 10, 3, 10, 30), datetime(2026, 10, 3, 11, 0),
            "+919876543210", "Asha Rao",
        )

        assert seen["method"] == "POST"
        assert seen["url"] == f"{BASE_URL}/createAppointment"

    def test_base_url_pointing_at_a_function_is_trimmed(self):
        """The old bot's CRUDOC_APPOINTMENTS_API was the create URL itself.

        Left alone it would produce .../createAppointment/getAvailability.
        """
        adapter = CruDocAdapter(
            base_url=f"{BASE_URL}/createAppointment", api_key=API_KEY
        )
        assert str(adapter._client.base_url).rstrip("/") == BASE_URL

    def test_trailing_slash_is_normalised(self):
        adapter = CruDocAdapter(base_url=f"{BASE_URL}/", api_key=API_KEY)
        assert str(adapter._client.base_url).rstrip("/") == BASE_URL


class TestBookingPayload:
    @pytest.mark.asyncio
    async def test_sends_the_field_names_crudoc_validates(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["payload"] = json.loads(request.content)
            return _json_response(201, {"success": True, "appointment_id": "a1"})

        await _adapter(handler).book(
            "doctor-firebase-uid",
            datetime(2026, 10, 3, 10, 30),
            datetime(2026, 10, 3, 11, 0),
            "+919876543210",
            "Asha Rao",
            "Toothache",
        )

        payload = seen["payload"]
        # These five are the ones createAppointment 400s without.
        assert payload["patient_name"] == "Asha Rao"
        assert payload["phone"] == "+919876543210"
        assert payload["doctor_id"] == "doctor-firebase-uid"
        assert payload["scheduled_start"]
        assert payload["source"] == "ai_receptionist"
        assert payload["reason"] == "Toothache"
        # 10:30 -> 11:00 is half an hour.
        assert payload["duration_minutes"] == 30
        # The invented keys must be gone.
        assert "slot_start" not in payload
        assert "patient_phone" not in payload

    @pytest.mark.asyncio
    async def test_naive_slot_is_qualified_with_the_clinic_offset(self):
        """A wall-clock time sent unqualified is how a booking lands hours off.

        CruDoc parses scheduled_start with `new Date(...)`, and the Flutter
        app renders the stored Timestamp in device-local time -- so 10:30
        with no offset became 16:00 IST.
        """
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["payload"] = json.loads(request.content)
            return _json_response(201, {"success": True, "appointment_id": "a1"})

        await _adapter(handler, timezone="Asia/Kolkata").book(
            "doc-uid",
            datetime(2026, 10, 3, 10, 30),  # naive, as the LLM tends to emit
            datetime(2026, 10, 3, 11, 0),
            "+919876543210",
            "Asha Rao",
        )

        assert seen["payload"]["scheduled_start"] == "2026-10-03T10:30:00+05:30"

    @pytest.mark.asyncio
    async def test_already_aware_slot_is_left_alone(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["payload"] = json.loads(request.content)
            return _json_response(201, {"success": True, "appointment_id": "a1"})

        await _adapter(handler, timezone="Asia/Kolkata").book(
            "doc-uid",
            datetime(2026, 10, 3, 5, 0, tzinfo=timezone.utc),
            datetime(2026, 10, 3, 5, 30, tzinfo=timezone.utc),
            "+919876543210",
            "Asha Rao",
        )

        assert seen["payload"]["scheduled_start"] == "2026-10-03T05:00:00+00:00"

    @pytest.mark.asyncio
    async def test_duration_follows_the_slot_length(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["payload"] = json.loads(request.content)
            return _json_response(201, {"success": True, "appointment_id": "a1"})

        await _adapter(handler).book(
            "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 11, 15),
            "+919876543210", "Asha Rao",
        )
        assert seen["payload"]["duration_minutes"] == 75

    @pytest.mark.asyncio
    async def test_reason_is_omitted_when_absent(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["payload"] = json.loads(request.content)
            return _json_response(201, {"success": True, "appointment_id": "a1"})

        await _adapter(handler).book(
            "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
            "+919876543210", "Asha Rao",
        )
        assert "reason" not in seen["payload"]


class TestBookingResponses:
    @pytest.mark.asyncio
    async def test_returns_appointment_id_on_201(self):
        def handler(request):
            return _json_response(
                201, {"success": True, "appointment_id": "appt-123", "patient_id": "p-9"}
            )

        result = await _adapter(handler).book(
            "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
            "+919876543210", "Asha Rao",
        )
        assert result == "appt-123"

    @pytest.mark.asyncio
    async def test_409_is_reported_as_slot_taken(self):
        def handler(request):
            return _json_response(
                409, {"success": False, "error": "Slot no longer available"}
            )

        with pytest.raises(AppointmentProviderError, match="no longer available"):
            await _adapter(handler).book(
                "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
                "+919876543210", "Asha Rao",
            )

    @pytest.mark.asyncio
    async def test_surfaces_the_servers_own_error_message(self):
        def handler(request):
            return _json_response(400, {"success": False, "error": "phone is required"})

        with pytest.raises(AppointmentProviderError, match="phone is required"):
            await _adapter(handler).book(
                "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
                "", "Asha Rao",
            )

    @pytest.mark.asyncio
    async def test_unauthorized_key_is_an_error_not_a_silent_success(self):
        def handler(request):
            return _json_response(401, {"success": False, "error": "Unauthorized"})

        with pytest.raises(AppointmentProviderError, match="Unauthorized"):
            await _adapter(handler).book(
                "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
                "+919876543210", "Asha Rao",
            )

    @pytest.mark.asyncio
    async def test_201_without_success_flag_is_rejected(self):
        """A 2xx is not proof of a booking; the body carries the verdict."""
        def handler(request):
            return _json_response(201, {"success": False, "error": "write failed"})

        with pytest.raises(AppointmentProviderError, match="write failed"):
            await _adapter(handler).book(
                "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
                "+919876543210", "Asha Rao",
            )

    @pytest.mark.asyncio
    async def test_missing_appointment_id_is_rejected(self):
        def handler(request):
            return _json_response(201, {"success": True})

        with pytest.raises(AppointmentProviderError):
            await _adapter(handler).book(
                "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
                "+919876543210", "Asha Rao",
            )

    @pytest.mark.asyncio
    async def test_transport_failure_becomes_a_provider_error(self):
        def handler(request):
            raise httpx.ConnectError("connection refused")

        with pytest.raises(AppointmentProviderError, match="Could not reach CruDoc"):
            await _adapter(handler).book(
                "doc-uid", datetime(2026, 10, 3, 10, 0), datetime(2026, 10, 3, 10, 30),
                "+919876543210", "Asha Rao",
            )


class TestAvailability:
    @pytest.mark.asyncio
    async def test_queries_the_availability_function_with_the_clinic_grid(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["url"] = request.url
            seen["method"] = request.method
            return _json_response(200, {"success": True, "slots": []})

        adapter = _adapter(
            handler, timezone="Asia/Kolkata",
            open_time="10:00", close_time="17:00", slot_minutes=20,
        )
        await adapter.get_availability("doc-uid", date(2026, 10, 3))

        assert seen["method"] == "GET"
        assert seen["url"].path == "/getAvailability"
        params = seen["url"].params
        assert params["doctor_id"] == "doc-uid"
        assert params["date"] == "2026-10-03"
        assert params["open_time"] == "10:00"
        assert params["close_time"] == "17:00"
        assert params["slot_minutes"] == "20"
        # +05:30 in minutes -- lets the function build the right day boundaries.
        assert params["tz_offset_minutes"] == "330"

    @pytest.mark.asyncio
    async def test_parses_utc_slots_into_aware_datetimes(self):
        def handler(request):
            return _json_response(200, {
                "success": True,
                "slots": [
                    {"start": "2026-10-03T04:30:00.000Z", "end": "2026-10-03T05:00:00.000Z"},
                    {"start": "2026-10-03T05:00:00.000Z", "end": "2026-10-03T05:30:00.000Z"},
                ],
            })

        slots = await _adapter(handler).get_availability("doc-uid", date(2026, 10, 3))

        assert len(slots) == 2
        assert slots[0].start == datetime(2026, 10, 3, 4, 30, tzinfo=timezone.utc)
        assert slots[0].end == datetime(2026, 10, 3, 5, 0, tzinfo=timezone.utc)

    @pytest.mark.asyncio
    async def test_an_unparseable_slot_is_skipped_not_fatal(self):
        def handler(request):
            return _json_response(200, {
                "success": True,
                "slots": [
                    {"start": "not-a-date", "end": "also-not"},
                    {"start": "2026-10-03T05:00:00Z", "end": "2026-10-03T05:30:00Z"},
                ],
            })

        slots = await _adapter(handler).get_availability("doc-uid", date(2026, 10, 3))
        assert len(slots) == 1

    @pytest.mark.asyncio
    async def test_failure_raises_rather_than_looking_fully_booked(self):
        """An empty list would tell the caller the day is full.

        The service layer relies on this raising so the bot can say the
        calendar is unreachable instead of inventing a full day.
        """
        def handler(request):
            return _json_response(500, {"success": False, "error": "Firestore timeout"})

        with pytest.raises(AppointmentProviderError, match="Firestore timeout"):
            await _adapter(handler).get_availability("doc-uid", date(2026, 10, 3))

    @pytest.mark.asyncio
    async def test_unknown_doctor_raises(self):
        def handler(request):
            return _json_response(404, {"success": False, "error": "Doctor not found"})

        with pytest.raises(AppointmentProviderError, match="Doctor not found"):
            await _adapter(handler).get_availability("nope", date(2026, 10, 3))


class TestCancelAndReschedule:
    @pytest.mark.asyncio
    async def test_cancel_posts_the_appointment_id(self):
        seen = {}

        def handler(request: httpx.Request) -> httpx.Response:
            seen["url"] = str(request.url)
            seen["method"] = request.method
            seen["payload"] = json.loads(request.content)
            return _json_response(200, {"success": True, "appointment_id": "appt-1"})

        assert await _adapter(handler).cancel("appt-1") is True
        assert seen["method"] == "POST"
        assert seen["url"] == f"{BASE_URL}/cancelAppointment"
        assert seen["payload"]["appointment_id"] == "appt-1"

    @pytest.mark.asyncio
    async def test_cancel_failure_raises_so_an_orphan_is_visible(self):
        def handler(request):
            return _json_response(404, {"success": False, "error": "Appointment not found"})

        with pytest.raises(AppointmentProviderError, match="Appointment not found"):
            await _adapter(handler).cancel("missing")

    @pytest.mark.asyncio
    async def test_reschedule_is_explicitly_unsupported(self):
        """CruDoc has no reschedule endpoint, so this must not no-op."""
        def handler(request):  # pragma: no cover -- must never be called
            raise AssertionError("reschedule should not issue a request")

        with pytest.raises(AppointmentProviderError, match="does not support rescheduling"):
            await _adapter(handler).reschedule(
                "appt-1", datetime(2026, 10, 4, 10, 0), datetime(2026, 10, 4, 10, 30)
            )


class TestFactoryWiring:
    def setup_method(self):
        from app.providers.factory import reset_provider_cache
        reset_provider_cache()

    def test_adapter_is_reused_for_the_same_config(self):
        """Each adapter owns a connection pool; one per tool call leaked them."""
        from app.providers.factory import get_provider

        config = {"base_url": BASE_URL, "api_key": API_KEY}
        first = get_provider("crudoc", config, timezone="Asia/Kolkata")
        second = get_provider("crudoc", config, timezone="Asia/Kolkata")
        assert first is second

    def test_rotated_credential_builds_a_new_adapter(self):
        from app.providers.factory import get_provider

        first = get_provider("crudoc", {"base_url": BASE_URL, "api_key": "old"})
        second = get_provider("crudoc", {"base_url": BASE_URL, "api_key": "new"})
        assert first is not second

    def test_clinic_timezone_reaches_the_adapter(self):
        from app.providers.factory import get_provider

        adapter = get_provider(
            "crudoc", {"base_url": BASE_URL, "api_key": API_KEY}, timezone="Asia/Kolkata"
        )
        assert adapter._offset_minutes_on(date(2026, 10, 3)) == 330

    def test_clinic_can_override_the_slot_grid(self):
        from app.providers.factory import get_provider

        adapter = get_provider("crudoc", {
            "base_url": BASE_URL, "api_key": API_KEY,
            "open_time": "08:00", "close_time": "20:00", "slot_minutes": 15,
        })
        assert adapter._open_time == "08:00"
        assert adapter._close_time == "20:00"
        assert adapter._slot_minutes == 15

    def test_non_integer_slot_minutes_is_a_config_error(self):
        from app.providers.factory import ProviderNotConfiguredError, get_provider

        with pytest.raises(ProviderNotConfiguredError, match="slot_minutes"):
            get_provider("crudoc", {
                "base_url": BASE_URL, "api_key": API_KEY, "slot_minutes": "half an hour",
            })

    def test_unknown_timezone_falls_back_to_utc(self):
        adapter = CruDocAdapter(
            base_url=BASE_URL, api_key=API_KEY, timezone="Mars/Olympus_Mons"
        )
        assert adapter._offset_minutes_on(date(2026, 10, 3)) == 0
