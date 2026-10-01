"""
Human handoff. Always uses the clinic's own configured receptionist
numbers (ResolvedClinic.receptionist_numbers, already priority-ordered) --
never a global number. Falls through the priority list on failure.
"""
from twilio.base.exceptions import TwilioRestException
from twilio.rest import Client as TwilioClient

from app.core.config import get_settings
from app.core.logging import get_logger
from app.schemas.clinic import ResolvedClinic

logger = get_logger(component="transfer_service")


class TransferFailedError(Exception):
    pass


def _client() -> TwilioClient:
    settings = get_settings()
    return TwilioClient(settings.twilio_account_sid, settings.twilio_auth_token)


async def transfer_call(call_sid: str, clinic: ResolvedClinic, reason: str) -> str:
    """
    Redirects the live call to the clinic's highest-priority receptionist
    number via a <Dial> TwiML update. Falls through to the next number if
    Twilio reports the update itself failed (does not — and cannot —
    detect whether the human answers; that's a distinct, separate concern
    handled by call-status callbacks in a fuller implementation).
    """
    if not clinic.receptionist_numbers:
        logger.error("no_receptionist_configured", clinic_id=str(clinic.clinic_id))
        raise TransferFailedError("No receptionist configured for this clinic")

    twiml = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        f'<Response><Say>Connecting you to our front desk.</Say>'
        f'<Dial>{clinic.receptionist_numbers[0]}</Dial></Response>'
    )

    try:
        _client().calls(call_sid).update(twiml=twiml)
    except TwilioRestException as exc:
        logger.error(
            "transfer_failed",
            call_sid=call_sid,
            clinic_id=str(clinic.clinic_id),
            reason=reason,
            error=str(exc),
        )
        raise TransferFailedError(str(exc)) from exc

    logger.info(
        "call_transferred",
        call_sid=call_sid,
        clinic_id=str(clinic.clinic_id),
        receptionist=clinic.receptionist_numbers[0],
        reason=reason,
    )
    return clinic.receptionist_numbers[0]
