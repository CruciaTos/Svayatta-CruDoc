"""
Security helpers: Twilio request validation and internal API-key checks.
"""
import hmac

from fastapi import Header, HTTPException, Request, status
from twilio.request_validator import RequestValidator

from app.core.config import get_settings


async def verify_twilio_signature(request: Request) -> None:
    """
    Validate that an inbound webhook actually came from Twilio.

    Twilio signs each request with HMAC-SHA1 over the full URL + sorted
    POST params, using the account auth token. Reject anything that
    doesn't match rather than trusting caller-supplied data.
    """
    settings = get_settings()
    validator = RequestValidator(settings.twilio_auth_token)

    signature = request.headers.get("X-Twilio-Signature", "")
    form = await request.form()
    params = {k: v for k, v in form.multi_items()}

    # Behind ngrok/a load balancer, request.url is the internal http://host
    # URL, but Twilio signed the public one it was configured with.
    url = str(request.url)
    if settings.public_base_url:
        url = settings.public_base_url.rstrip("/") + request.url.path
        if request.url.query:
            url += "?" + request.url.query
    if not validator.validate(url, params, signature):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid Twilio signature",
        )


async def verify_internal_api_key(x_api_key: str = Header(default="")) -> None:
    """Guards internal/admin endpoints (clinic management, etc.).

    Compared with `hmac.compare_digest` rather than `!=` so the check
    takes the same time whichever byte first differs. A plain comparison
    returns early on the first mismatch, which leaks the shared secret a
    byte at a time to anyone who can measure response latency across
    enough requests -- these endpoints provision tenants, so that is worth
    closing. This matches the timing-safe check the CruDoc Cloud Functions
    use on the same class of credential.
    """
    settings = get_settings()
    expected = settings.voice_bot_api_key
    if not expected or not hmac.compare_digest(x_api_key, expected):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Unauthorized")
