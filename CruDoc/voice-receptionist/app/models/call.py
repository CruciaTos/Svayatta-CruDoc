import uuid

from sqlalchemy import DateTime, ForeignKey, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin, uuid_pk


class Call(Base, TimestampMixin):
    """Persistent record of a call, written on call end (and updated as it
    progresses) for observability/reporting. The LIVE per-call state during
    the call lives in voice.call_session.CallSession, not here."""

    __tablename__ = "calls"

    id: Mapped[uuid.UUID] = uuid_pk()
    clinic_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("clinics.id", ondelete="CASCADE"), nullable=False, index=True
    )
    # The receptionist line that was dialed; null for browser test calls.
    phone_number_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("phone_numbers.id", ondelete="SET NULL"), index=True
    )
    twilio_call_sid: Mapped[str] = mapped_column(String(64), nullable=False, unique=True, index=True)
    caller_number: Mapped[str] = mapped_column(String(32), nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="in_progress")
    # e.g. "booked", "transferred", "abandoned", "no_action", "failed"
    outcome: Mapped[str | None] = mapped_column(String(64))
    start_time: Mapped["DateTime"] = mapped_column(DateTime(timezone=True), nullable=False)
    end_time: Mapped["DateTime | None"] = mapped_column(DateTime(timezone=True))
