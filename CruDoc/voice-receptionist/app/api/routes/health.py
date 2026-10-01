from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.postgres import get_db
from app.db.redis import get_redis

router = APIRouter(tags=["health"])


@router.get("/health")
async def health(db: AsyncSession = Depends(get_db)) -> dict:
    checks = {"database": "unknown", "redis": "unknown"}
    try:
        await db.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception as exc:  # noqa: BLE001
        checks["database"] = f"error: {exc}"

    redis = get_redis()
    if redis is None:
        checks["redis"] = "local-only"
    else:
        try:
            await redis.ping()
            checks["redis"] = "ok"
        except Exception as exc:  # noqa: BLE001
            checks["redis"] = f"error: {exc}"

    status = "ok" if checks["database"] == "ok" and checks["redis"] in {"ok", "local-only"} else "degraded"
    return {"status": status, "checks": checks}
