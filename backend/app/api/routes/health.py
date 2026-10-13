"""Health probes.

/health/live  — process liveness only (no dependency checks).
/health/ready — bounded dependency checks (PostgreSQL, RabbitMQ) with
configured timeouts; 503 when a required dependency is unavailable.

An accepted PENDING order may legitimately wait for messaging recovery;
readiness distinguishes "API can accept work" (DB ok) from "pipeline fully
draining" (broker ok). Both are required for ready=200.
"""
from __future__ import annotations

import asyncio
import logging
import time

import aio_pika
from fastapi import APIRouter
from fastapi.responses import JSONResponse
from sqlalchemy import text

from ...config import settings
from ...database import SessionLocal

log = logging.getLogger("quickbite.health")

router = APIRouter()


@router.get("/health/live")
def live():
    return {"status": "ok"}


def _db_check() -> tuple[bool, str]:
    try:
        session = SessionLocal()
        try:
            session.execute(text("SELECT 1"))
            return True, "ok"
        finally:
            session.close()
    except Exception as exc:  # noqa: BLE001
        return False, f"{type(exc).__name__}: {exc}"


async def _amqp_check() -> tuple[bool, str]:
    try:
        conn = await asyncio.wait_for(
            aio_pika.connect_robust(settings.amqp_url), timeout=settings.ready_amqp_timeout_s
        )
        await conn.close()
        return True, "ok"
    except Exception as exc:  # noqa: BLE001
        return False, f"{type(exc).__name__}: {exc}"


@router.get("/health/ready")
async def ready():
    started = time.monotonic()
    db_ok, db_detail = await asyncio.to_thread(_db_check)
    amqp_ok, amqp_detail = await _amqp_check()
    details = {
        "database": {"ok": db_ok, "detail": db_detail},
        "broker": {"ok": amqp_ok, "detail": amqp_detail},
        "elapsed_s": round(time.monotonic() - started, 3),
    }
    if db_ok and amqp_ok:
        return {"status": "ready", "details": details}
    return JSONResponse(
        status_code=503, content={"status": "not_ready", "details": details}
    )
