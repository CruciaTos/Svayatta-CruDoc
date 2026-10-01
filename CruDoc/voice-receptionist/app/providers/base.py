"""
Appointment provider adapter interface.

The AI/voice layer and AppointmentService only ever talk to this
interface -- never to CruDoc, Google Calendar, etc. directly. This is what
lets a clinic switch providers, or lets us support a new provider, without
touching the voice pipeline or the LLM tool definitions.
"""
from abc import ABC, abstractmethod
from datetime import date, datetime

from app.schemas.appointment import SlotOut


class AppointmentProviderError(Exception):
    """Raised on any provider failure (timeout, 5xx, malformed response).
    Callers must catch this and degrade gracefully -- never assume a
    booking succeeded because no exception surfaced elsewhere."""


class AppointmentProvider(ABC):
    @abstractmethod
    async def get_availability(
        self, doctor_external_id: str, on_date: date
    ) -> list[SlotOut]:
        """Return real open slots from the provider. Never fabricated."""

    @abstractmethod
    async def book(
        self,
        doctor_external_id: str,
        slot_start: datetime,
        slot_end: datetime,
        caller_number: str,
        patient_name: str,
        reason: str | None = None,
    ) -> str:
        """Attempt to book. Returns the provider's appointment ID on
        success. Raises AppointmentProviderError on failure or if the
        provider reports the slot as no longer available.

        `patient_name` is required because a practice management system
        books an appointment *for a named patient* -- CruDoc rejects a
        booking without one, and a phone number alone gives the clinic no
        way to recognise who is arriving.

        Implementations must treat a naive `slot_start`/`slot_end` as
        clinic-local time and qualify it before sending, rather than
        letting the provider guess a zone.
        """

    @abstractmethod
    async def cancel(self, external_appointment_id: str) -> bool:
        ...

    @abstractmethod
    async def reschedule(
        self, external_appointment_id: str, new_start: datetime, new_end: datetime
    ) -> bool:
        ...
