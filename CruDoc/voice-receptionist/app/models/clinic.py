import uuid

from sqlalchemy import JSON, Boolean, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin, uuid_pk


class Clinic(Base, TimestampMixin):
    """
    A tenant. All clinic-scoped queries elsewhere in the app filter by
    clinic_id -- see app/services/clinic_service.py and
    app/core/security.py for how tenant isolation is enforced.
    """

    __tablename__ = "clinics"

    id: Mapped[uuid.UUID] = uuid_pk()
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    timezone: Mapped[str] = mapped_column(String(64), nullable=False, default="Asia/Kolkata")
    address: Mapped[str | None] = mapped_column(String(500))
    contact_email: Mapped[str | None] = mapped_column(String(255))
    contact_phone: Mapped[str | None] = mapped_column(String(32))
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="active")

    # ID of this tenant in the CruDoc app (the owning doctor's/clinic's Firebase
    # UID). Lets the Super Admin provisioning API upsert idempotently.
    external_id: Mapped[str | None] = mapped_column(String(128), unique=True, index=True)

    # Premium entitlement. The AI receptionist is a paid feature: a phone call
    # to one of this clinic's numbers is refused unless Super Admin has
    # switched it on. Does not gate the dev-only browser voice test.
    ai_receptionist_enabled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    # Free-form business config that doesn't warrant its own column:
    # greeting text, supported_languages, voice id, AI instructions,
    # appointment_provider ("crudoc" | "google_calendar" | ...),
    # appointment_provider_config (credentials/IDs for that provider).
    config: Mapped[dict] = mapped_column(JSON, nullable=False, default=dict)

    doctors: Mapped[list["Doctor"]] = relationship(back_populates="clinic")
    phone_numbers: Mapped[list["PhoneNumber"]] = relationship(back_populates="clinic")
    receptionists: Mapped[list["Receptionist"]] = relationship(back_populates="clinic")


from app.models.doctor import Doctor  # noqa: E402
from app.models.phone_number import PhoneNumber  # noqa: E402
from app.models.receptionist import Receptionist  # noqa: E402
