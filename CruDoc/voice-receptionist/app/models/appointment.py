import uuid

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, uuid_pk


class Appointment(Base, TimestampMixin):
    """
    Local record of a booking made through this service. This is NOT a
    full duplicate of the external provider's appointment database -- it
    exists to (a) give us a fast local availability/lock reference and
    (b) let us correlate calls -> bookings for observability.

    The UNIQUE constraint on (doctor_id, slot_start) is the actual
    database-level guarantee against double-booking: even if two requests
    somehow both pass the Redis lock (e.g. lock expiry race), the second
    INSERT will fail with an IntegrityError and the service layer treats
    that as "slot no longer available" rather than trusting a prior read.
    """

    __tablename__ = "appointments"
    __table_args__ = (
        UniqueConstraint("doctor_id", "slot_start", name="uq_doctor_slot"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    doctor_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("doctors.id", ondelete="CASCADE"), nullable=False, index=True
    )
    call_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("calls.id", ondelete="SET NULL")
    )
    caller_number: Mapped[str] = mapped_column(String(32), nullable=False)
    # Name the appointment was booked under. The provider is the source of
    # truth for it; this copy is what makes a call record legible on its own
    # ("who was this booked for?") without a round trip to CruDoc.
    # Nullable so rows written before the interface carried a name still load.
    patient_name: Mapped[str | None] = mapped_column(String(255))
    slot_start: Mapped["DateTime"] = mapped_column(DateTime(timezone=True), nullable=False, index=True)
    slot_end: Mapped["DateTime"] = mapped_column(DateTime(timezone=True), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="confirmed")
    # ID returned by the external provider (CruDoc, etc). Source of truth
    # for the booking itself remains the provider; this is a reference.
    external_appointment_id: Mapped[str | None] = mapped_column(String(255))
