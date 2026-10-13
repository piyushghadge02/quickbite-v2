"""Worker integration tests on REAL PostgreSQL + REAL RabbitMQ.

Covers: happy path, duplicate delivery, fail-twice-then-succeed, always-fail
terminal + quarantine, restaurant terminal failure, notification isolation,
malformed quarantine, and worker kill recovery (subprocess SIGKILL).
"""
from __future__ import annotations

import asyncio
import json
import os
import subprocess
import sys
import time

import aio_pika
import pytest
from sqlalchemy import func, select

from backend.app.config import settings
from backend.app.database import SessionLocal
from backend.app.domain import state_machine
from backend.app.messaging.envelope import (
    ORDER_CREATED,
    build_event,
    child_event,
)
from backend.app.messaging.outbox import claim_due, publish_confirmed, settle
from backend.app.messaging.topology import amqp_message, declare_topology
from backend.app.models import (
    DriverAssignment,
    Notification,
    Order,
    OrderStatusHistory,
    OutboxEvent,
    ProcessedEvent,
    QuarantineRecord,
    RetryJob,
    SimulatedPayment,
)
from workers.delivery_worker import DeliveryWorker
from workers.notification_worker import NotificationWorker
from workers.payment_worker import PaymentWorker
from workers.retry_scheduler import promote_due
from workers.restaurant_worker import RestaurantWorker
from .conftest import place_order

TERMINAL = ("DRIVER_ASSIGNED", "PAYMENT_FAILED", "FAILED")
FAST_DELAYS = (0.2, 0.5, 1.0)


@pytest.fixture()
def fast_retries(monkeypatch):
    monkeypatch.setattr(settings, "retry_delays_s", FAST_DELAYS)
    monkeypatch.setattr(settings, "max_attempts", 1 + len(FAST_DELAYS))
    monkeypatch.setattr(settings, "retry_scheduler_interval_s", 0.1)
    monkeypatch.setattr(settings, "outbox_poll_interval_s", 0.1)


async def drain_outbox_async():
    conn = await aio_pika.connect_robust(settings.amqp_url)
    async with conn:
        channel = await conn.channel(publisher_confirms=True)
        await declare_topology(channel)
        while True:
            session = SessionLocal()
            try:
                rows = claim_due(session, 50)
                ids = [r.id for r in rows]
            finally:
                session.close()
            if not ids:
                break
            for rid in ids:
                s2 = SessionLocal()
                try:
                    row = s2.get(OutboxEvent, rid)
                    ok, err = await publish_confirmed(channel, row)
                    settle(s2, row, ok, err)
                finally:
                    s2.close()


def order_status(order_id: str) -> str | None:
    s = SessionLocal()
    try:
        o = s.get(Order, order_id)
        return o.status if o else None
    finally:
        s.close()


async def drive(order_id: str, timeout: float = 40.0, workers=None):
    """Run dispatcher + scheduler + workers until the order is terminal."""
    workers = workers or [PaymentWorker(), RestaurantWorker(), DeliveryWorker(),
                          NotificationWorker()]
    conn = await aio_pika.connect_robust(settings.amqp_url)
    async with conn:
        channel = await conn.channel(publisher_confirms=True)
        await declare_topology(channel)
        tasks = [asyncio.create_task(w._consume_loop()) for w in workers]
        # Give consumers a moment to attach before dispatching.
        await asyncio.sleep(1.0)
        try:
            start = time.monotonic()
            while time.monotonic() - start < timeout:
                await asyncio.to_thread(promote_due)
                # inline drain using the open channel
                session = SessionLocal()
                try:
                    rows = claim_due(session, 50)
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
                if order_status(order_id) in TERMINAL:
                    # Terminal state reached, but the terminal event's outbox
                    # row was committed in the same transaction: do a final
                    # drain + grace period so trailing notifications land.
                    for _ in range(6):
                        await asyncio.to_thread(promote_due)
                        session = SessionLocal()
                        try:
                            rows = claim_due(session, 50)
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
                        await asyncio.sleep(0.5)
                    break
                await asyncio.sleep(0.3)
        finally:
            for w in workers:
                w._shutdown.set()
            await asyncio.gather(*tasks, return_exceptions=True)
    return order_status(order_id)


def count(model, **kw):
    s = SessionLocal()
    try:
        q = select(func.count()).select_from(model)
        for k, v in kw.items():
            q = q.where(getattr(model, k) == v)
        return s.execute(q).scalar()
    finally:
        s.close()


def test_happy_path_end_to_end(client, cust1_headers, db, rmq, fast_retries):
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    final = asyncio.run(drive(order_id))
    assert final == "DRIVER_ASSIGNED", f"final={final}"
    s = SessionLocal()
    try:
        order = s.get(Order, order_id)
        assert order.version == 4
        assert order.driver_id is not None
        hist = s.execute(
            select(OrderStatusHistory).where(OrderStatusHistory.order_id == order_id)
            .order_by(OrderStatusHistory.version)).scalars().all()
        assert [h.to_status for h in hist] == ["PENDING", "PAID", "CONFIRMED", "DRIVER_ASSIGNED"]
        assert [h.version for h in hist] == [1, 2, 3, 4]
    finally:
        s.close()
    assert count(SimulatedPayment, order_id=order_id) == 1
    assert count(DriverAssignment, order_id=order_id) == 1
    assert count(Notification, order_id=order_id) == 4  # created/paid/confirmed/driver_assigned
    # 1 payment + 1 restaurant + 1 delivery + 4 notification processed events.
    assert count(ProcessedEvent, order_id=order_id) == 7


def test_duplicate_delivery_single_effect(client, cust1_headers, db, rmq, fast_retries):
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    asyncio.run(drain_outbox_async())  # order.created -> payment.queue, marked sent
    # Redeliver the SAME event (same event_id) to payment.queue manually.
    s = SessionLocal()
    try:
        row = s.execute(select(OutboxEvent).where(OutboxEvent.routing_key == ORDER_CREATED)).scalar_one()
        payload = dict(row.payload)
    finally:
        s.close()

    async def _republish():
        conn = await aio_pika.connect_robust(settings.amqp_url)
        async with conn:
            ch = await conn.channel()
            exchange = await ch.get_exchange(settings.exchange_name, ensure=False)
            await exchange.publish(amqp_message(payload), routing_key=ORDER_CREATED)
    asyncio.run(_republish())
    asyncio.run(drive(order_id, workers=[PaymentWorker()], timeout=15))
    # Payment ran twice (original + redelivery) but committed effects once.
    assert count(SimulatedPayment, order_id=order_id) == 1
    assert count(ProcessedEvent, consumer_name="payment", order_id=order_id) == 1


def test_fail_twice_then_succeed(client, cust1_headers, db, rmq, fast_retries, monkeypatch):
    monkeypatch.setattr(settings, "payment_sim_mode", "fail-twice-then-succeed")
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    started = time.monotonic()
    final = asyncio.run(drive(order_id, timeout=60))
    assert final == "DRIVER_ASSIGNED", final
    # Retries were scheduled (attempts 2 and 3) with delays between them.
    jobs = SessionLocal()
    try:
        rows = jobs.execute(select(RetryJob).where(RetryJob.consumer_name == "payment")).scalars().all()
    finally:
        jobs.close()
    assert len(rows) == 2
    attempts = sorted(r.attempt for r in rows)
    assert attempts == [2, 3]
    gap = (rows[1].run_at - rows[0].run_at).total_seconds()
    assert gap >= 0.4, f"retry delay not honored: {gap}"
    # Exactly one payment committed despite three handling attempts.
    assert count(SimulatedPayment, order_id=order_id) == 1


def test_always_fail_payment_terminal_and_quarantine(client, cust1_headers, db, rmq,
                                                     fast_retries, monkeypatch):
    monkeypatch.setattr(settings, "payment_sim_mode", "always-fail")
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    final = asyncio.run(drive(order_id, timeout=60))
    assert final == "PAYMENT_FAILED", final
    s = SessionLocal()
    try:
        order = s.get(Order, order_id)
        assert order.failure_code == "SIMULATED_DECLINE"
        assert order.version == 2  # PENDING -> PAYMENT_FAILED only
    finally:
        s.close()
    # Quarantined exactly once (logically).
    assert count(QuarantineRecord, consumer_name="payment", order_id=order_id) == 1
    # order.payment.failed was emitted and notified.
    assert count(Notification, order_id=order_id, event_type="order.payment.failed") == 1
    # No payment row committed.
    assert count(SimulatedPayment, order_id=order_id) == 1  # FAILED payment record
    s2 = SessionLocal()
    try:
        pay = s2.execute(select(SimulatedPayment).where(SimulatedPayment.order_id == order_id)).scalar_one()
        assert pay.status == "FAILED"
    finally:
        s2.close()


def test_restaurant_always_fail_terminal(client, cust1_headers, db, rmq,
                                         fast_retries, monkeypatch):
    monkeypatch.setattr(settings, "restaurant_fail_mode", "always-fail")
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    final = asyncio.run(drive(order_id, timeout=60))
    assert final == "FAILED", final
    s = SessionLocal()
    try:
        order = s.get(Order, order_id)
        assert order.failure_code == "RESTAURANT_REJECTED"
    finally:
        s.close()
    assert count(Notification, order_id=order_id, event_type="order.failed") == 1


def test_notification_isolation(client, cust1_headers, db, rmq, fast_retries, monkeypatch):
    monkeypatch.setattr(settings, "notification_fail_mode", "always-fail")
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    final = asyncio.run(drive(order_id, timeout=60))
    # Order pipeline completes DESPITE the notification outage.
    assert final == "DRIVER_ASSIGNED", final
    # No notifications persisted.
    assert count(Notification, order_id=order_id) == 0

    # Keep driving ONLY notification redelivery until its retries exhaust
    # into quarantine (the order is already terminal, so drive() returned).
    async def _drain_notifications(timeout: float = 30.0):
        w = NotificationWorker()
        conn = await aio_pika.connect_robust(settings.amqp_url)
        async with conn:
            channel = await conn.channel(publisher_confirms=True)
            await declare_topology(channel)
            task = asyncio.create_task(w._consume_loop())
            await asyncio.sleep(1.0)
            try:
                start = time.monotonic()
                while time.monotonic() - start < timeout:
                    await asyncio.to_thread(promote_due)
                    session = SessionLocal()
                    try:
                        rows = claim_due(session, 50)
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
                    if count(QuarantineRecord, consumer_name="notification",
                             order_id=order_id) >= 1:
                        break
                    await asyncio.sleep(0.3)
            finally:
                w._shutdown.set()
                await task
    asyncio.run(_drain_notifications())
    # Failures quarantined without touching order status.
    assert count(QuarantineRecord, consumer_name="notification", order_id=order_id) >= 1
    assert order_status(order_id) == "DRIVER_ASSIGNED"


def test_malformed_event_quarantined_no_retry(client, cust1_headers, db, rmq):
    async def _publish_garbage():
        conn = await aio_pika.connect_robust(settings.amqp_url)
        async with conn:
            ch = await conn.channel()
            await declare_topology(ch)
            exchange = await ch.get_exchange(settings.exchange_name, ensure=False)
            await exchange.publish(
                aio_pika.Message(b"this is not json",
                                 content_type="application/json",
                                 delivery_mode=aio_pika.DeliveryMode.PERSISTENT),
                routing_key=ORDER_CREATED,
            )
    async def _run_worker_briefly():
        w = PaymentWorker()
        task = asyncio.create_task(w._consume_loop())
        await asyncio.sleep(4)
        w._shutdown.set()
        await task
    asyncio.run(_publish_garbage())
    asyncio.run(_run_worker_briefly())
    assert count(QuarantineRecord, consumer_name="payment") == 1
    s = SessionLocal()
    try:
        rec = s.execute(select(QuarantineRecord)).scalar_one()
        assert rec.failure_code == "MALFORMED_ENVELOPE"
        assert count(RetryJob) == 0  # never retried
    finally:
        s.close()


def test_worker_kill_recovery_no_double_effects(client, cust1_headers, db, rmq):
    """Kill -9 the payment worker after commit but before ack; restart cleanly."""
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    asyncio.run(drain_outbox_async())  # order.created -> payment.queue

    env = dict(os.environ)
    env["PAYMENT_SIM_MODE"] = "crash-after-checkpoint"
    env["PAYMENT_CRASH_POINT"] = "after-commit"
    env["PYTHONPATH"] = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    proc = subprocess.Popen(
        [sys.executable, "workers/payment_worker.py"],
        cwd=os.path.abspath(os.path.join(os.path.dirname(__file__), "..")),
        env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        proc.wait(timeout=30)  # worker os._exit(1)s after committing
    finally:
        if proc.poll() is None:
            proc.kill()
    assert proc.returncode == 1  # died at the injected checkpoint
    # The payment WAS committed before the crash.
    s = SessionLocal()
    try:
        assert s.get(Order, order_id).status == "PAID"
        assert count(SimulatedPayment, order_id=order_id) == 1
    finally:
        s.close()
    # Restart a healthy worker: redelivery must be a safe no-op.
    asyncio.run(drive(order_id, workers=[PaymentWorker()], timeout=15))
    assert count(SimulatedPayment, order_id=order_id) == 1
    s2 = SessionLocal()
    try:
        assert s2.get(Order, order_id).status == "PAID"
        assert s2.get(Order, order_id).version == 2
    finally:
        s2.close()
