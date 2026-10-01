"""
Application-level configuration.

Only application/service secrets live here (env vars). Tenant-specific
business data (clinic names, doctors, receptionist numbers, etc.) lives in
the configured database and is loaded per-call via ClinicService. See
app/services/clinic_service.py.
"""
from functools import lru_cache
from uuid import UUID

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_env: str = "development"
    log_level: str = "INFO"

    database_url: str = "sqlite+aiosqlite:///./voice_receptionist.db"
    redis_url: str = ""

    sarvam_api_key: str = ""
    google_api_key: str = ""
    gemini_model: str = "gemini-3.5-flash"
    sarvam_tts_model: str = "bulbul:v3"

    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    public_base_url: str = ""

    voice_bot_api_key: str = ""
    local_voice_test_clinic_id: UUID | None = None
    # Browser voice tests have no Twilio call leg, so phone transfers are always
    # off; set this true to also exercise real appointment-provider bookings.
    local_voice_test_allow_booking: bool = False

    stt_failure_threshold: int = 2

    # Connection pool sizing -- production defaults, override via env if needed.
    db_pool_size: int = 10
    db_max_overflow: int = 20


@lru_cache
def get_settings() -> Settings:
    return Settings()
