"""
Gemini tool definitions + handlers.

Tools perform real backend operations only -- no tool handler ever
fabricates availability, a confirmation, or an appointment ID. Every
handler is bound to the CallSession it was created for, so it can only
ever act on that call's clinic_id / selected doctor, never another
tenant's or another caller's.
"""
import json
import uuid
from datetime import date, datetime

from pipecat.adapters.schemas.function_schema import FunctionSchema
from pipecat.adapters.schemas.tools_schema import ToolsSchema
from pipecat.services.llm_service import FunctionCallParams
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import get_logger
from app.providers.base import AppointmentProviderError
from app.services import appointment_service, transfer_service
from app.services.transfer_service import TransferFailedError
from app.voice.call_session import CallSession

logger = get_logger(component="voice_tools")

TOOL_SCHEMAS = [
    FunctionSchema(
        name="list_doctors",
        description="List doctors available at this clinic, with specialization.",
        properties={},
        required=[],
    ),
    FunctionSchema(
        name="check_availability",
        description=(
            "Check real open appointment slots for a doctor on a given date. "
            "Never assume availability without calling this."
        ),
        properties={
            "doctor_id": {"type": "string", "description": "Doctor id from list_doctors."},
            "date": {"type": "string", "description": "ISO date, e.g. 2026-10-03"},
        },
        required=["doctor_id", "date"],
    ),
    FunctionSchema(
        name="book_appointment",
        description=(
            "Book an appointment. Only tell the caller it's confirmed after this "
            "tool returns success=true."
        ),
        properties={
            "doctor_id": {"type": "string", "description": "Doctor id from list_doctors."},
            "patient_name": {
                "type": "string",
                "description": (
                    "The caller's full name, as they gave it. Required -- the "
                    "clinic books the appointment under this name."
                ),
            },
            "slot_start": {"type": "string", "description": "ISO 8601 datetime"},
            "slot_end": {"type": "string", "description": "ISO 8601 datetime"},
            "reason": {
                "type": "string",
                "description": "Optional reason for the visit, if the caller gave one.",
            },
        },
        required=["doctor_id", "patient_name", "slot_start", "slot_end"],
    ),
    FunctionSchema(
        name="transfer_to_receptionist",
        description="Transfer the caller to a human receptionist at this clinic.",
        properties={
            "reason": {"type": "string", "description": "Why the transfer is needed."},
        },
        required=["reason"],
    ),
]

# Pipecat converts this to each provider's native tool format via its LLM
# adapter (Gemini's function_declarations here), so the declarations above
# stay provider-agnostic.
TOOL_DECLARATIONS = ToolsSchema(standard_tools=TOOL_SCHEMAS)

TOOL_NAMES = tuple(schema.name for schema in TOOL_SCHEMAS)


class ToolExecutor:
    """One instance per CallSession -- holds the DB session and the
    session's clinic context so handlers can't drift to another tenant."""

    def __init__(
        self, db: AsyncSession, session: CallSession, allow_external_actions: bool = True
    ):
        self._db = db
        self._session = session
        self._allow_external_actions = allow_external_actions

    async def handle_function_call(self, params: FunctionCallParams) -> None:
        """Pipecat tool-call entrypoint.

        Pipecat (>=0.0.59) invokes handlers with a single FunctionCallParams
        and takes the result via `params.result_callback` -- returning a dict
        here would be discarded and the LLM would wait forever for its tool
        result.
        """
        result = await self.dispatch(params.function_name, params.arguments or {})
        await params.result_callback(result)

    async def dispatch(self, tool_name: str, args: dict) -> dict:
        handler = getattr(self, f"_handle_{tool_name}", None)
        if handler is None:
            logger.warning("unknown_tool_call", tool=tool_name, clinic_id=str(self._session.clinic.clinic_id))
            return {"error": f"Unknown tool: {tool_name}"}
        try:
            return await handler(args)
        except Exception as exc:  # noqa: BLE001 -- tool boundary must never crash the call
            logger.error(
                "tool_execution_failed",
                tool=tool_name,
                clinic_id=str(self._session.clinic.clinic_id),
                call_id=str(self._session.call_id),
                error=str(exc),
            )
            return {"error": "This action could not be completed right now."}

    async def _handle_list_doctors(self, args: dict) -> dict:
        return {"doctors": self._session.clinic.doctors}

    async def _handle_check_availability(self, args: dict) -> dict:
        if not self._allow_external_actions:
            return {"slots": [], "error": "Appointment-provider access is disabled in local voice tests."}
        doctor_id = args["doctor_id"]
        on_date = date.fromisoformat(args["date"])
        try:
            slots = await appointment_service.check_availability(
                self._session.clinic, doctor_id, on_date
            )
        except AppointmentProviderError as exc:
            # "Unreachable" and "fully booked" both look like zero slots to
            # the model, so they are reported differently: telling a caller
            # the day is full when we never found out is a fabricated answer.
            logger.warning(
                "availability_unknown",
                clinic_id=str(self._session.clinic.clinic_id),
                doctor_id=doctor_id,
                error=str(exc),
            )
            return {
                "availability_known": False,
                "slots": [],
                "error": (
                    "The clinic calendar could not be reached, so availability is "
                    "unknown. Do not tell the caller the day is full -- offer to "
                    "transfer them to a receptionist instead."
                ),
            }
        self._session.select_doctor(doctor_id)
        return {
            "availability_known": True,
            "slots": [
                {"start": s.start.isoformat(), "end": s.end.isoformat()} for s in slots
            ],
        }

    async def _handle_book_appointment(self, args: dict) -> dict:
        if not self._allow_external_actions:
            return {"success": False, "reason": "Booking is disabled in local voice tests."}
        result = await appointment_service.book_appointment(
            db=self._db,
            clinic=self._session.clinic,
            doctor_id=args["doctor_id"],
            caller_number=self._session.caller_phone,
            patient_name=args.get("patient_name", ""),
            slot_start=datetime.fromisoformat(args["slot_start"]),
            slot_end=datetime.fromisoformat(args["slot_end"]),
            call_id=self._session.call_id,
            reason=args.get("reason"),
        )
        if result.success:
            self._session.appointments_booked += 1
        return json.loads(result.model_dump_json())

    async def _handle_transfer_to_receptionist(self, args: dict) -> dict:
        if not self._allow_external_actions:
            return {"success": False, "error": "Phone transfers are disabled in local voice tests."}
        try:
            number = await transfer_service.transfer_call(
                self._session.twilio_call_sid, self._session.clinic, reason=args.get("reason", "requested")
            )
            self._session.status = self._session.status.__class__.TRANSFERRED
            return {"success": True, "transferred_to": number}
        except TransferFailedError as exc:
            return {"success": False, "error": str(exc)}
