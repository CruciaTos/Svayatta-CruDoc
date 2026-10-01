"""
Sarvam voice/model/language resolution.

Sarvam rejects the whole TTS request with a 400 -- killing every bit of
audio on the call -- if either the model or the speaker is not one it
currently serves, so an unset or stale `clinic.config.voice_id` must never
reach the API. Two live failures this guards against:

- `bulbul:v2` (pipecat 0.0.100's built-in default) is deprecated
  server-side; Sarvam now requires `bulbul:v3`.
- v3 rejects every v2 speaker name, so speaker and model must move together.

Resolution happens here, once, rather than at each call site.
"""
from app.core.logging import get_logger

logger = get_logger(component="voice_config")

# Sarvam's current TTS model. Pipecat's own default (bulbul:v2) is
# deprecated server-side and returns 400 for every request.
DEFAULT_SARVAM_TTS_MODEL = "bulbul:v3"

# Speakers accepted by bulbul:v3. Sarvam returns this exact list in its 400
# body when it rejects an unknown speaker.
SARVAM_BULBUL_V3_SPEAKERS = frozenset(
    {
        "aditya", "ritu", "ashutosh", "priya", "neha", "rahul", "pooja",
        "rohan", "simran", "kavya", "amit", "dev", "ishita", "shreya",
        "ratan", "varun", "manan", "sumit", "roopa", "kabir", "aayan",
        "shubh", "advait", "anand", "tanya", "tarun", "sunny", "mani",
        "gokul", "vijay", "shruti", "suhani", "mohit", "kavitha", "rehan",
        "soham", "rupali",
    }
)

# Retired bulbul:v2 speakers. Called out separately so a clinic still
# configured with one gets a log line naming the reason, not just
# "unknown speaker".
RETIRED_V2_SPEAKERS = frozenset(
    {"anushka", "abhilash", "manisha", "vidya", "arya", "karun", "hitesh"}
)

DEFAULT_SARVAM_SPEAKER = "priya"
DEFAULT_SARVAM_LANGUAGE = "en-IN"


def resolve_speaker(voice_id: str | None, *, clinic_name: str = "") -> str:
    """Map a clinic's configured voice_id to a speaker Sarvam will accept.

    Falls back to DEFAULT_SARVAM_SPEAKER rather than passing an unknown name
    through, because an unknown speaker means zero audio on the call.
    """
    if voice_id:
        candidate = voice_id.strip().lower()
        if candidate in SARVAM_BULBUL_V3_SPEAKERS:
            return candidate
        logger.warning(
            "retired_sarvam_speaker_falling_back"
            if candidate in RETIRED_V2_SPEAKERS
            else "unknown_sarvam_speaker_falling_back",
            configured_voice_id=voice_id,
            clinic=clinic_name,
            model=DEFAULT_SARVAM_TTS_MODEL,
            using=DEFAULT_SARVAM_SPEAKER,
        )
    return DEFAULT_SARVAM_SPEAKER


def resolve_language(supported_languages: list[str] | None) -> str:
    """First configured language, or Sarvam's Indian-English default."""
    if supported_languages:
        first = supported_languages[0]
        if first and first.strip():
            return first.strip()
    return DEFAULT_SARVAM_LANGUAGE
