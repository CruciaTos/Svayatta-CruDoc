"""Builds the per-call system prompt from clinic config. Never hard-codes
any clinic's identity -- everything comes from ResolvedClinic."""
from datetime import datetime
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from app.core.logging import get_logger
from app.schemas.clinic import ResolvedClinic

logger = get_logger(component="voice_prompts")

BASE_INSTRUCTIONS = """You are the AI phone receptionist for {practice_name}.

Right now it is {current_datetime} ({timezone}).
Use this to resolve what the caller says -- "tomorrow", "this Friday",
"next week" -- into a concrete date yourself. Never ask the caller what
today's or tomorrow's date is; you already know it. Tools that take a date
need an ISO date (YYYY-MM-DD).

Rules you must always follow:
- Only state an appointment is booked after the book_appointment tool returns success=true.
- Never invent doctor availability, appointment IDs, or clinic information.
- Ask the caller for their name before booking and pass it as patient_name;
  the clinic books the appointment under that name.
- Never ask the caller for their phone number -- you already have it.
- If check_availability comes back with availability_known=false, the calendar
  could not be reached. Say so and offer a receptionist; never present that as
  the day being fully booked.
- If you cannot understand the caller or cannot help, offer to transfer to a human receptionist.
- Keep responses short and natural for a phone conversation.
- Confirm dates/times back to the caller in {timezone}.

Doctors you book for on this line (and only these):
{doctor_list}
"""


def clinic_now(clinic: ResolvedClinic) -> datetime:
    """Current time in the clinic's timezone.

    Falls back to UTC on an unknown timezone rather than failing the call;
    note that `tzdata` must be installed for named zones to resolve on
    Windows, where the OS has no zoneinfo database.
    """
    try:
        return datetime.now(ZoneInfo(clinic.timezone))
    except (ZoneInfoNotFoundError, ValueError):
        logger.warning(
            "unknown_clinic_timezone_using_utc",
            clinic=clinic.name,
            configured_timezone=clinic.timezone,
        )
        return datetime.now(ZoneInfo("UTC"))


def build_system_prompt(clinic: ResolvedClinic, now: datetime | None = None) -> str:
    doctor_list = "\n".join(
        f"- {d.get('name', 'Unknown')} "
        f"({d.get('specialization') or 'General'}) [doctor_id: {d.get('id')}]"
        for d in clinic.doctors
    ) or "- (no doctors configured)"

    now = now or clinic_now(clinic)

    practice_name = (
        f"{clinic.line_label} ({clinic.name})"
        if clinic.line_label and clinic.line_label != clinic.name
        else clinic.name
    )
    prompt = BASE_INSTRUCTIONS.format(
        practice_name=practice_name,
        timezone=clinic.timezone,
        current_datetime=now.strftime("%A, %d %B %Y, %H:%M"),
        doctor_list=doctor_list,
    )
    if clinic.ai_instructions:
        prompt += f"\n\nAdditional clinic-specific instructions:\n{clinic.ai_instructions}"
    return prompt
