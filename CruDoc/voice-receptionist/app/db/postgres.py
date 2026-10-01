"""
Async SQLAlchemy engine/session management. Local development defaults to
a persistent SQLite file; deployments can use PostgreSQL via DATABASE_URL.
"""
from contextlib import asynccontextmanager
from typing import AsyncIterator

from sqlalchemy import event
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import get_settings

_settings = get_settings()

if _settings.database_url.startswith("sqlite+"):
    engine = create_async_engine(_settings.database_url, pool_pre_ping=True)

    @event.listens_for(engine.sync_engine, "connect")
    def _enable_sqlite_foreign_keys(connection, _record) -> None:
        cursor = connection.cursor()
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()
else:
    engine = create_async_engine(
        _settings.database_url,
        pool_size=_settings.db_pool_size,
        max_overflow=_settings.db_max_overflow,
        pool_pre_ping=True,
    )

AsyncSessionLocal = async_sessionmaker(
    bind=engine, expire_on_commit=False, autoflush=False
)


async def get_db() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency: one session per request."""
    async with AsyncSessionLocal() as session:
        yield session


@asynccontextmanager
async def db_session() -> AsyncIterator[AsyncSession]:
    """Context manager for use outside the FastAPI DI system (voice layer)."""
    async with AsyncSessionLocal() as session:
        yield session
