"""
NOTE: these tests assume a PostgreSQL + Redis test instance reachable via
DATABASE_URL / REDIS_URL (e.g. via docker-compose up postgres redis).
They are written against the service layer directly, not through HTTP,
to keep them focused on business-critical behavior (spec section 25).
"""
import os
import uuid

import pytest
import pytest_asyncio

# Keep routine tests isolated from the app's persistent local database.
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")

from app.db.postgres import AsyncSessionLocal, engine
from app.models.base import Base
from app.models import appointment, call, clinic, doctor, phone_number, receptionist


@pytest_asyncio.fixture
async def db_session():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with AsyncSessionLocal() as session:
        yield session
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


@pytest.fixture
def new_id():
    return uuid.uuid4
