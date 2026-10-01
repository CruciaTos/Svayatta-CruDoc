"""
CruDoc appointment provider adapter.

The wire contract here is confirmed against CruDoc's own Cloud Functions
source (`CruDoc/functions/src/appointments.ts`) rather than assumed:

    POST {base_url}/createAppointment
    GET  {base_url}/getAvailability
    POST {base_url}/cancelAppointment

All three authenticate with the clinic's shared secret in an `X-Api-Key`
header -- *not* a bearer token -- and all answer with a JSON body carrying
`success: bool`. Status codes that carry meaning:

    401  bad or missing key
    404  unknown doctor (create/availability) or appointment (cancel)
    409  the requested slot is already taken
    400  a field this adapter sent was rejected

Two things worth knowing about this integration:

- Times. CruDoc stores `scheduledStart` as a Firestore Timestamp and the
  Flutter app renders it in device-local time, so an ambiguous wall-clock
  string lands at the wrong hour. This adapter therefore always sends
  `scheduled_start` as an ISO 8601 string *with* a UTC offset, and
  localises a naive datetime to the clinic's timezone before doing so
  rather than letting either end guess.
- Business hours. CruDoc has no working-hours model of its own, so the
  open/close/slot-length grid that availability is computed from lives in
  this clinic's `appointment_provider_config` and is sent per request.

Reschedule is deliberately unimplemented: CruDoc exposes no such
endpoint, so it raises instead of silently reporting success.
"""
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

import httpx
from tenacity import retry, retry_if_exception_type, stop_after_attempt, wait_exponential

from app.core.logging import get_logger
from app.providers.base import AppointmentProvider, AppointmentProviderError
from app.schemas.appointment import SlotOut

logger = get_logger(component="crudoc_adapter")

# Cloud Functions cold-start can take a few seconds, but a caller is on the
# phone waiting, so the read timeout is a deliberate compromise rather than
# something generous.
_TIMEOUT = httpx.Timeout(connect=5.0, read=10.0, write=5.0, pool=5.0)

_DEFAULT_OPEN_TIME = "09:00"
_DEFAULT_CLOSE_TIME = "18:00"
_DEFAULT_SLOT_MINUTES = 30
_SOURCE = "ai_receptionist"

# CruDoc's function URLs are flat -- one function per path segment off the
# region host, not a nested REST hierarchy.
_CREATE_PATH = "/createAppointment"
_AVAILABILITY_PATH = "/getAvailability"
_CANCEL_PATH = "/cancelAppointment"

# A base_url copied from the old single-tenant bot's CRUDOC_APPOINTMENTS_API
# points at the create function itself. Accept that and trim it, rather than
# issuing every request against ".../createAppointment/getAvailability".
_TRIMMABLE_SUFFIXES = (_CREATE_PATH, _AVAILABILITY_PATH, _CANCEL_PATH)


class CruDocAdapter(AppointmentProvider):
    def __init__(
        self,
        base_url: str,
        api_key: str,
        timezone: str = "Asia/Kolkata",
        open_time: str = _DEFAULT_OPEN_TIME,
        close_time: str = _DEFAULT_CLOSE_TIME,
        slot_minutes: int = _DEFAULT_SLOT_MINUTES,
    ):
        self._base_url = self._normalise_base_url(base_url)
        self._timezone_name = timezone
        self._tz = self._resolve_timezone(timezone)
        self._open_time = open_time
        self._close_time = close_time
        self._slot_minutes = slot_minutes
        self._client = httpx.AsyncClient(
            base_url=self._base_url,
            headers={
                "X-Api-Key": api_key,
                "Content-Type": "application/json",
            },
            timeout=_TIMEOUT,
        )

    # ---------------------------------------------------------------
    # Setup helpers
    # ---------------------------------------------------------------

    @staticmethod
    def _normalise_base_url(base_url: str) -> str:
        trimmed = (base_url or "").strip().rstrip("/")
        for suffix in _TRIMMABLE_SUFFIXES:
            if trimmed.endswith(suffix):
                logger.info(
                    "crudoc_base_url_trimmed",
                    reason="base_url pointed at a specific function, not the region host",
                    removed=suffix,
                )
                return trimmed[: -len(suffix)].rstrip("/")
        return trimmed

    @staticmethod
    def _resolve_timezone(name: str) -> ZoneInfo:
        """Clinic timezone, falling back to UTC rather than failing a call.

        Named zones need the `tzdata` package on Windows, where the OS
        ships no zoneinfo database -- it is pinned in requirements.txt for
        exactly this reason.
        """
        try:
            return ZoneInfo(name)
        except (ZoneInfoNotFoundError, ValueError):
            logger.warning("crudoc_unknown_timezone_using_utc", configured_timezone=name)
            return ZoneInfo("UTC")

    def _offset_minutes_on(self, on_date: date) -> int:
        """The clinic's UTC offset on a given day, in minutes.

        Derived from local noon so a DST transition at midnight can't make
        the answer ambiguous.
        """
        local_noon = datetime(on_date.year, on_date.month, on_date.day, 12, tzinfo=self._tz)
        offset = local_noon.utcoffset()
        return int(offset.total_seconds() // 60) if offset else 0

    def _as_aware(self, moment: datetime) -> datetime:
        """Attach the clinic's timezone to a naive datetime.

        The LLM can emit a slot time without an offset, and sending that
        on unqualified is how an appointment silently lands hours away
        from what the caller agreed to.
        """
        if moment.tzinfo is None:
            return moment.replace(tzinfo=self._tz)
        return moment

    @staticmethod
    def _describe_error(resp: httpx.Response) -> str:
        """The server's own message when it sent one, else the status."""
        try:
            body = resp.json()
        except ValueError:
            return f"CruDoc returned HTTP {resp.status_code}"
        if isinstance(body, dict) and body.get("error"):
            return str(body["error"])
        return f"CruDoc returned HTTP {resp.status_code}"

    # ---------------------------------------------------------------
    # AppointmentProvider
    # ---------------------------------------------------------------

    @retry(
        retry=retry_if_exception_type(httpx.TransportError),
        stop=stop_after_attempt(2),
        wait=wait_exponential(multiplier=0.3, max=2),
        reraise=True,
    )
    async def get_availability(self, doctor_external_id: str, on_date: date) -> list[SlotOut]:
        try:
            resp = await self._client.get(
                _AVAILABILITY_PATH,
                params={
                    "doctor_id": doctor_external_id,
                    "date": on_date.isoformat(),
                    "open_time": self._open_time,
                    "close_time": self._close_time,
                    "slot_minutes": self._slot_minutes,
                    "tz_offset_minutes": self._offset_minutes_on(on_date),
                },
            )
        except httpx.TransportError as exc:
            logger.error(
                "crudoc_availability_failed",
                doctor_id=doctor_external_id,
                error=str(exc),
            )
            raise AppointmentProviderError(
                "Could not reach CruDoc to check availability"
            ) from exc

        if resp.status_code != 200:
            detail = self._describe_error(resp)
            logger.error(
                "crudoc_availability_rejected",
                doctor_id=doctor_external_id,
                status=resp.status_code,
                error=detail,
            )
            raise AppointmentProviderError(detail)

        body = resp.json()
        if not body.get("success"):
            detail = str(body.get("error") or "CruDoc reported an availability failure")
            logger.error("crudoc_availability_unsuccessful", error=detail)
            raise AppointmentProviderError(detail)

        slots: list[SlotOut] = []
        for raw in body.get("slots", []):
            try:
                slots.append(
                    SlotOut(
                        start=datetime.fromisoformat(raw["start"].replace("Z", "+00:00")),
                        end=datetime.fromisoformat(raw["end"].replace("Z", "+00:00")),
                    )
                )
            except (KeyError, AttributeError, ValueError):
                logger.warning("crudoc_slot_unparseable", slot=raw)
        return slots

    async def book(
        self,
        doctor_external_id: str,
        slot_start: datetime,
        slot_end: datetime,
        caller_number: str,
        patient_name: str,
        reason: str | None = None,
    ) -> str:
        start = self._as_aware(slot_start)
        end = self._as_aware(slot_end)
        duration_minutes = max(1, int((end - start) / timedelta(minutes=1)))

        payload = {
            "patient_name": patient_name,
            "phone": caller_number,
            "doctor_id": doctor_external_id,
            # Sent with an explicit offset so neither side has to guess a
            # zone; CruDoc prefers this over the legacy date + time pair.
            "scheduled_start": start.isoformat(),
            "duration_minutes": duration_minutes,
            "source": _SOURCE,
        }
        if reason:
            payload["reason"] = reason

        try:
            resp = await self._client.post(_CREATE_PATH, json=payload)
        except httpx.TransportError as exc:
            logger.error(
                "crudoc_booking_unreachable",
                doctor_id=doctor_external_id,
                error=str(exc),
            )
            raise AppointmentProviderError("Could not reach CruDoc to book") from exc

        if resp.status_code == 409:
            # CruDoc found something already on that doctor's calendar --
            # including an appointment booked inside the app, which this
            # service's own tables cannot see.
            raise AppointmentProviderError("Slot no longer available")

        if resp.status_code != 201:
            detail = self._describe_error(resp)
            logger.error(
                "crudoc_booking_rejected",
                doctor_id=doctor_external_id,
                status=resp.status_code,
                error=detail,
            )
            raise AppointmentProviderError(detail)

        body = resp.json()
        appointment_id = body.get("appointment_id")
        if not body.get("success") or not appointment_id:
            detail = str(body.get("error") or "CruDoc did not return an appointment id")
            logger.error("crudoc_booking_unsuccessful", error=detail)
            raise AppointmentProviderError(detail)

        logger.info(
            "crudoc_booking_created",
            doctor_id=doctor_external_id,
            appointment_id=appointment_id,
            scheduled_start=start.isoformat(),
        )
        return str(appointment_id)

    async def cancel(self, external_appointment_id: str) -> bool:
        try:
            resp = await self._client.post(
                _CANCEL_PATH,
                json={
                    "appointment_id": external_appointment_id,
                    "reason": "Released by AI receptionist",
                },
            )
        except httpx.TransportError as exc:
            logger.error(
                "crudoc_cancel_unreachable",
                appointment_id=external_appointment_id,
                error=str(exc),
            )
            raise AppointmentProviderError("Could not reach CruDoc to cancel") from exc

        if resp.status_code != 200:
            detail = self._describe_error(resp)
            logger.error(
                "crudoc_cancel_rejected",
                appointment_id=external_appointment_id,
                status=resp.status_code,
                error=detail,
            )
            raise AppointmentProviderError(detail)

        body = resp.json()
        if not body.get("success"):
            detail = str(body.get("error") or "CruDoc reported a cancel failure")
            raise AppointmentProviderError(detail)

        logger.info("crudoc_booking_cancelled", appointment_id=external_appointment_id)
        return True

    async def reschedule(
        self, external_appointment_id: str, new_start: datetime, new_end: datetime
    ) -> bool:
        """Unsupported: CruDoc has no reschedule endpoint.

        Raising keeps a caller from treating a silent no-op as a moved
        appointment. Reschedule is currently cancel-then-book at the
        service layer.
        """
        raise AppointmentProviderError(
            "CruDoc does not support rescheduling; cancel and re-book instead"
        )

    async def aclose(self) -> None:
        """Release the HTTP connection pool."""
        await self._client.aclose()
