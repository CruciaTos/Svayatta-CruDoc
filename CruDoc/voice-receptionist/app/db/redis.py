"""
Redis client + appointment locks. When REDIS_URL is unset, local
single-process development uses asyncio locks instead.
"""
import asyncio
from contextlib import asynccontextmanager
from typing import AsyncIterator
from uuid import uuid4

from redis.asyncio import Redis, from_url

from app.core.config import get_settings

_settings = get_settings()
_redis: Redis | None = (
    from_url(_settings.redis_url, decode_responses=True) if _settings.redis_url else None
)
_local_locks: dict[str, asyncio.Lock] = {}


def get_redis() -> Redis | None:
    return _redis


@asynccontextmanager
async def slot_lock(
    clinic_id: str, doctor_id: str, slot_start_iso: str, timeout_seconds: int = 10
) -> AsyncIterator[bool]:
    """
    Distributed lock around a single (doctor, slot) so two concurrent
    callers requesting the same slot can't both pass the availability
    check before either has committed a booking. This is a belt-and-braces
    guard in addition to the DB-level uniqueness constraint in
    appointments (see app/models/appointment.py) -- the DB constraint is
    the real source of truth; the lock just avoids wasted provider calls.
    """
    key = f"lock:slot:{clinic_id}:{doctor_id}:{slot_start_iso}"
    if _redis is None:
        lock = _local_locks.setdefault(key, asyncio.Lock())
        try:
            await asyncio.wait_for(lock.acquire(), timeout=timeout_seconds)
            acquired = True
        except asyncio.TimeoutError:
            acquired = False
        try:
            yield acquired
        finally:
            if acquired:
                lock.release()
        return

    token = str(uuid4())
    acquired = await _redis.set(key, token, nx=True, ex=timeout_seconds)
    try:
        yield bool(acquired)
    finally:
        if acquired:
            # Only release if we still own it (avoid clobbering a lock
            # acquired by someone else after ours expired).
            current = await _redis.get(key)
            if current == token:
                await _redis.delete(key)
