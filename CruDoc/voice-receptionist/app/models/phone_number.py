import uuid

from sqlalchemy import JSON, Boolean, Column, ForeignKey, String, Table
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, uuid_pk

# Which doctors a line's AI receptionist represents. An empty set means the
# line is clinic-wide (every active doctor of the clinic).
phone_number_doctors = Table(
    "phone_number_doctors",
    Base.metadata,
    Column(
        "phone_number_id",
        UUID(as_uuid=True),
        ForeignKey("phone_numbers.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "doctor_id",
        UUID(as_uuid=True),
        ForeignKey("doctors.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)


class PhoneNumber(Base, TimestampMixin):
    """A receptionist *line*: one Twilio number -> one AI receptionist.

    The number resolves an inbound call to a tenant (clinic) and to the
    doctor(s) this receptionist speaks for -- a single doctor's own number,
    or a group of doctors sharing a clinic line. See
    ClinicService.resolve_by_twilio_number.
    """

    __tablename__ = "phone_numbers"

    id: Mapped[uuid.UUID] = uuid_pk()
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    twilio_number: Mapped[str] = mapped_column(String(32), nullable=False, unique=True, index=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    # Name this receptionist introduces itself as, e.g. "Dr. Rahul's clinic".
    label: Mapped[str | None] = mapped_column(String(255))
    # Per-line overrides of the clinic's config (greeting, voice_id,
    # ai_instructions, supported_languages). Unset keys fall back to the clinic.
    config: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)

    clinic = relationship("Clinic", back_populates="phone_numbers")
    doctors = relationship("Doctor", secondary=phone_number_doctors, lazy="selectin")
