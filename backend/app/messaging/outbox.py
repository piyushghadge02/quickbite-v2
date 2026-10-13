"""Transactional outbox dispatcher (separate process).

Claims due outbox records with SELECT ... FOR UPDATE SKIP LOCKED plus a
claim lease, so multiple dispatcher instances never publish the same row.
Publishes with publisher confirms + mandatory routing and marks a record
sent ONLY after a confirm arrives with no basic-return (an unroutable
message is NOT marked sent — a confirm alone does not prove a binding
existed). Failures leave the record eligible for a delayed retry.

A crash after publication but before mark-sent can duplicate a message;
downstream consumers are idempotent, so duplicates are safe. Exactly-once
delivery is never claimed — at-least-once with single committed effects.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timedelta, timezone

import aio_pika
from aio_pika import DeliveryMode, Message
from sqlalchemy import select, text
from sqlalchemy.orm import Session

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../../..")))

from backend.app.config import settings  # noqa: E402
from backend.app.database import SessionLocal  # noqa: E402
from backend.app.messaging.topology import declare_topology  # noqa: E402
from backend.app.models import OutboxEvent  # noqa: E402

log = logging.getLogger("quickbite.outbox")
WORKER_ID = f"outbox-{os.getpid()}"
_shutdown = asyncio.Event()


def _handle_signal(*_args):
    _shutdown.set()


def claim_due(session: Session, limit: int) -> list[OutboxEvent]:
    """Claim up to `limit` due rows using a lease safe for N dispatchers."""
    now = datetime.now(timezone.utc)
    lease_cutoff = now - timedelta(seconds=settings.outbox_claim_lease_s)
    rows = session.execute(
        select(OutboxEvent)
        .where(
            OutboxEvent.state.in_(("pending", "inflight")),
            OutboxEvent.available_at <= now,
        )
        .where(
            (OutboxEvent.state == "pending")
            | (OutboxEvent.claimed_at.is_(None))
            | (OutboxEvent.claimed_at < lease_cutoff)
        )
        .order_by(OutboxEvent.available_at.asc(), OutboxEvent.id.asc())
        .limit(limit)
        .with_for_update(skip_locked=True)
    ).scalars().all()
    for row in rows:
        row.state = "inflight"
        row.claimed_at = now
        row.claimed_by = WORKER_ID
    session.commit()
    return rows


async def publish_confirmed(channel, event: OutboxEvent) -> tuple[bool, str | None]:
    """Publish with publisher confirms + mandatory routing.

    Returns (ok, error). ok=True only when the broker acknowledges the
    publish AND the message was routed (an unroutable message raises
    DeliveryError — a confirm alone does not prove a binding existed).
    """
    try:
        body = json.dumps(event.payload).encode("utf-8")
        headers = dict((event.payload.get("_headers") or {}))
        headers.pop("_headers", None)
        msg = Message(
            body,
            content_type="application/json",
            delivery_mode=DeliveryMode.PERSISTENT,
            message_id=event.event_id,
            headers=headers,
        )
        # The default exchange ("") routes directly to a queue by name;
        # named exchanges route via bindings. Both support confirms.
        if event.exchange:
            exchange = await channel.get_exchange(event.exchange, ensure=False)
        else:
            exchange = channel.default_exchange
        await exchange.publish(msg, routing_key=event.routing_key,
                               mandatory=True, timeout=10)
        return True, None
    except Exception as exc:  # noqa: BLE001
        return False, f"{type(exc).__name__}: {exc}"


def settle(session: Session, event: OutboxEvent, ok: bool, error: str | None) -> None:
    if ok:
        event.state = "sent"
        event.sent_at = datetime.now(timezone.utc)
        event.last_error = None
    else:
        event.state = "pending"  # stays eligible
        event.attempts += 1
        backoff = min(2 ** min(event.attempts, 6), 60)
        event.available_at = datetime.now(timezone.utc) + timedelta(seconds=backoff)
        event.last_error = (error or "unknown")[:2000]
        event.claimed_at = None
        event.claimed_by = None
    session.commit()


async def run() -> None:
    settings.validate()
    for sig in (signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, _handle_signal)
    log.info("outbox dispatcher starting id=%s", WORKER_ID)
    backoff = 1.0
    while not _shutdown.is_set():
        try:
            connection = await aio_pika.connect_robust(settings.amqp_url)
            async with connection:
                channel = await connection.channel(publisher_confirms=True)
                await channel.set_qos(prefetch_count=1)
                await declare_topology(channel)
                backoff = 1.0
                while not _shutdown.is_set():
                    session = SessionLocal()
                    try:
                        rows = claim_due(session, settings.outbox_batch_size)
                    finally:
                        session.close()
                    if not rows:
                        await asyncio.sleep(settings.outbox_poll_interval_s)
                        continue
                    for row in rows:
                        if _shutdown.is_set():
                            break
                        ok, error = await publish_confirmed(channel, row)
                        s2 = SessionLocal()
                        try:
                            fresh = s2.get(OutboxEvent, row.id)
                            settle(s2, fresh, ok, error)
                        finally:
                            s2.close()
                        log.info(
                            "outbox id=%s event=%s -> %s/%s ok=%s",
                            row.id, row.event_id, row.exchange or "(default)",
                            row.routing_key, ok,
                        )
        except Exception as exc:  # noqa: BLE001
            log.warning("dispatcher connection lost: %s; retry in %.1fs", exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30.0)
    log.info("outbox dispatcher stopped")


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    asyncio.run(run())
