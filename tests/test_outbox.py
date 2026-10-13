"""Transactional outbox: atomicity, dispatcher confirms, broker-outage safety."""
from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone

import aio_pika
import pytest
from sqlalchemy import func, select

from backend.app.config import settings
from backend.app.messaging.envelope import ORDER_CREATED, build_event
from backend.app.messaging.outbox import claim_due, publish_confirmed, settle
from backend.app.models import Order, OutboxEvent
from .conftest import place_order


def test_acceptance_commits_order_history_idempotency_outbox_atomically(
    client, cust1_headers, db
):
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    assert db.get(Order, order_id) is not None
    n_outbox = db.execute(
        select(func.count()).select_from(OutboxEvent).where(OutboxEvent.state == "pending")
    ).scalar()
    assert n_outbox == 1
    row = db.execute(select(OutboxEvent)).scalar_one()
    assert row.exchange == settings.exchange_name
    assert row.routing_key == ORDER_CREATED
    assert row.payload["order_id"] == order_id
    assert row.payload["event_id"] == row.event_id


def _drain_once():
    """Claim due outbox rows and publish them over a real channel (test helper)."""
    from backend.app.database import SessionLocal

    async def _run():
        conn = await aio_pika.connect_robust(settings.amqp_url)
        async with conn:
            channel = await conn.channel(publisher_confirms=True)
            session = SessionLocal()
            try:
                rows = claim_due(session, 100)
                ids = [r.id for r in rows]
            finally:
                session.close()
            for rid in ids:
                s2 = SessionLocal()
                try:
                    row = s2.get(OutboxEvent, rid)
                    ok, err = await publish_confirmed(channel, row)
                    settle(s2, row, ok, err)
                finally:
                    s2.close()
    asyncio.run(_run())


def test_dispatcher_publishes_with_confirms_and_marks_sent(db, rmq):
    event = build_event(event_type=ORDER_CREATED, order_id="o1", order_version=1,
                        data={"customer_id": "t_cust1"})
    db.add(OutboxEvent(event_id=event["event_id"], exchange=settings.exchange_name,
                       routing_key=ORDER_CREATED, payload=event, state="pending",
                       available_at=datetime.now(timezone.utc)))
    db.commit()
    _drain_once()
    db.expire_all()
    row = db.execute(select(OutboxEvent)).scalar_one()
    assert row.state == "sent"
    assert row.sent_at is not None

    async def _check():
        # Fresh connection: aio-pika objects are bound to their event loop.
        conn = await aio_pika.connect_robust(settings.amqp_url)
        try:
            ch = await conn.channel()
            queue = await ch.get_queue(settings.payment_queue, ensure=False)
            msg = await asyncio.wait_for(queue.get(fail=False), timeout=10)
            assert msg is not None
            body = json.loads(msg.body.decode())
            assert body["event_id"] == event["event_id"]
            assert msg.message_id == event["event_id"]  # message_id == event_id
            assert msg.content_type == "application/json"
            await msg.ack()
        finally:
            await conn.close()
    asyncio.run(_check())


def test_failed_publish_stays_eligible_for_retry(db):
    event = build_event(event_type=ORDER_CREATED, order_id="o2", order_version=1)
    db.add(OutboxEvent(event_id=event["event_id"], exchange=settings.exchange_name,
                       routing_key=ORDER_CREATED, payload=event, state="pending",
                       available_at=datetime.now(timezone.utc)))
    db.commit()

    async def _bad_publish():
        # Unroutable destination: mandatory publish to a nonexistent exchange
        # must NOT mark the record sent.
        conn = await aio_pika.connect_robust(settings.amqp_url)
        async with conn:
            channel = await conn.channel(publisher_confirms=True)
            row = db.execute(select(OutboxEvent)).scalar_one()
            row.exchange = "no.such.exchange"
            ok, err = await publish_confirmed(channel, row)
            assert ok is False, "unroutable publish must fail"
            settle(db, row, ok, err)
            db.commit()
    asyncio.run(_bad_publish())
    db.expire_all()
    row = db.execute(select(OutboxEvent)).scalar_one()
    assert row.state == "pending"  # still eligible
    assert row.attempts == 1
    assert row.last_error


def test_broker_outage_does_not_invalidate_committed_order(client, cust1_headers, db, monkeypatch):
    # Simulate broker downtime at dispatch time: the committed order stays
    # valid and the outbox row stays pending until the broker recovers.
    resp, _ = place_order(client, cust1_headers)
    assert resp.status_code == 202
    order_id = resp.json()["order_id"]

    async def _failing_drain():
        raise aio_pika.exceptions.AMQPConnectionError("simulated outage")
    with pytest.raises(aio_pika.exceptions.AMQPConnectionError):
        asyncio.run(_failing_drain())
    db.expire_all()
    assert db.get(Order, order_id).status == "PENDING"
    row = db.execute(select(OutboxEvent)).scalar_one()
    assert row.state == "pending"

    # Broker "recovers": drain for real.
    _drain_once()
    db.expire_all()
    assert db.execute(select(OutboxEvent)).scalar_one().state == "sent"
