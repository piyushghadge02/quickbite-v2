"""Retry scheduler (separate process).

Makes due retry_jobs eligible for publication by flipping their targeted
outbox records from ``scheduled`` to ``pending``. The outbox dispatcher
then publishes them — targeted at the failing consumer's queue via the
default exchange (routing key = queue name), never back through the
domain exchange (which would re-fan-out to unrelated subscribers).
"""
from __future__ import annotations

import asyncio
import logging
import os
import signal
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from sqlalchemy import select  # noqa: E402

from backend.app.config import settings  # noqa: E402
from backend.app.database import SessionLocal  # noqa: E402
from backend.app.models import OutboxEvent, RetryJob  # noqa: E402

log = logging.getLogger("quickbite.retry-scheduler")
_shutdown = asyncio.Event()


def _handle_signal(*_args):
    _shutdown.set()


def promote_due() -> int:
    """Flip due scheduled outbox rows (created for retries) to pending."""
    now = datetime.now(timezone.utc)
    session = SessionLocal()
    try:
        due_jobs = session.execute(
            select(RetryJob).where(
                RetryJob.state == "scheduled", RetryJob.run_at <= now
            )
        ).scalars().all()
        promoted = 0
        for job in due_jobs:
            row = session.execute(
                select(OutboxEvent).where(
                    OutboxEvent.event_id == job.event_id,
                    OutboxEvent.exchange == "",
                    OutboxEvent.routing_key == job.queue_name,
                    OutboxEvent.attempt == job.attempt,
                    OutboxEvent.state == "scheduled",
                )
            ).scalar_one_or_none()
            if row is not None:
                row.state = "pending"
                row.available_at = now
                promoted += 1
            job.state = "done"
        session.commit()
        return promoted
    finally:
        session.close()


async def run() -> None:
    settings.validate()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, _handle_signal)
    log.info("retry scheduler starting")
    while not _shutdown.is_set():
        try:
            n = await asyncio.to_thread(promote_due)
            if n:
                log.info("promoted %d due retries", n)
        except Exception as exc:  # noqa: BLE001
            log.warning("retry scheduler error: %s", exc)
        await asyncio.sleep(settings.retry_scheduler_interval_s)
    log.info("retry scheduler stopped")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    asyncio.run(run())
