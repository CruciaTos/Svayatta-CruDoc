from pathlib import Path
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.api.routes import admin, appointments, calls, clinics, doctors, health, phone_numbers, twilio
from app.core.config import get_settings
from app.core.logging import configure_logging, get_logger
from app.db.postgres import engine
from app.models.base import Base

settings = get_settings()
configure_logging(settings.log_level)
logger = get_logger(component="startup")

app = FastAPI(title="AI Voice Receptionist Platform", version="0.1.0")

app.include_router(health.router)
app.include_router(admin.router)
app.include_router(clinics.router)
app.include_router(doctors.router)
app.include_router(phone_numbers.router)
app.include_router(appointments.router)
app.include_router(calls.router)
app.include_router(twilio.router)

if settings.app_env == "development":
    from app.api.routes import local_voice_test

    static_dir = Path(__file__).resolve().parent.parent / "local_voice_test"
    if static_dir.exists():
        app.mount("/voice-test/static", StaticFiles(directory=str(static_dir)), name="local_voice_test_static")
    app.include_router(local_voice_test.router)



@app.on_event("startup")
async def on_startup() -> None:
    if engine.url.get_backend_name() == "sqlite":
        async with engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
    logger.info("service_starting", env=settings.app_env)
