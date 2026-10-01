"""
Structured logging configuration.

Every log line that touches a call should be bound with call_id / clinic_id
so a single call's full trace can be reconstructed ("why did this call
fail?"). Never log secrets (API keys, auth tokens, Twilio signatures).
"""
import logging
import sys

import structlog

_SENSITIVE_KEYS = {
    "authorization",
    "auth_token",
    "api_key",
    "sarvam_api_key",
    "google_api_key",
    "twilio_auth_token",
    "voice_bot_api_key",
    "x-twilio-signature",
}


def _redact_sensitive(_logger, _method_name, event_dict):
    for key in list(event_dict.keys()):
        if key.lower() in _SENSITIVE_KEYS:
            event_dict[key] = "***REDACTED***"
    return event_dict


def configure_logging(log_level: str = "INFO") -> None:
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, log_level.upper(), logging.INFO),
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            _redact_sensitive,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            getattr(logging, log_level.upper(), logging.INFO)
        ),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


def get_logger(**bind):
    return structlog.get_logger().bind(**bind)
