"""
CallSession: the unit of isolation for a single phone call.

One instance is created per inbound call and holds every piece of
call-specific state (see spec section 3). It is never stored in a global
variable and never shared between calls -- it lives for exactly the
lifetime of one WebSocket connection from Twilio, owned by that
connection's asyncio task. Concurrency comes from many independent
CallSession + Pipecat Pipeline instances running as separate asyncio
tasks under one (or many, horizontally-scaled) FastAPI worker process --
never from OS threads per call and never from a single shared
conversation object.
"""
import uuid
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum

from app.schemas.clinic import ResolvedClinic


class CallStatus(str, Enum):
    IN_PROGRESS = "in_progress"
    TRANSFERRED = "transferred"
    COMPLETED = "completed"
    FAILED = "failed"


@dataclass
class CallSession:
    call_id: uuid.UUID
    clinic: ResolvedClinic  # loaded once at call start; never re-fetched or mutated
    twilio_call_sid: str | None
    caller_phone: str

    status: CallStatus = CallStatus.IN_PROGRESS
    selected_doctor_id: str | None = None

    # Appointment-in-progress scratch state (not yet committed).
    pending_slot_start: datetime | None = None
    pending_slot_end: datetime | None = None

    # Consecutive empty/unintelligible STT results -- drives the hard
    # fallback in voice/pipeline.py, independent of what Gemini decides.
    consecutive_stt_failures: int = 0

    # Successful book_appointment calls; drives the call record's outcome.
    appointments_booked: int = 0

    db_call_record_id: uuid.UUID | None = None

    started_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))

    def register_stt_result(self, transcript: str | None) -> None:
        if transcript and transcript.strip():
            self.consecutive_stt_failures = 0
        else:
            self.consecutive_stt_failures += 1

    def select_doctor(self, doctor_id: str) -> None:
        self.selected_doctor_id = doctor_id
