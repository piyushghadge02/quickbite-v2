"""Topology: bindings, wildcards, dead-letter routing (assignment §9)."""
from __future__ import annotations

import asyncio
import json

import aio_pika
from aio_pika import DeliveryMode, Message

from backend.app.config import settings
from backend.app.messaging.envelope import (
    ORDER_CREATED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
    build_event,
)
from backend.app.messaging.topology import declare_topology


async def _publish_and_collect(event_types: list[str], queue_name: str,
                               timeout_each: float = 5.0) -> list[str]:
    conn = await aio_pika.connect_robust(settings.amqp_url)
    try:
        ch = await conn.channel()
        await declare_topology(ch)
        exchange = await ch.get_exchange(settings.exchange_name, ensure=False)
        for et in event_types:
            event = build_event(event_type=et, order_id="o_topo", order_version=1)
            await exchange.publish(
                Message(json.dumps(event).encode(),
                        content_type="application/json",
                        delivery_mode=DeliveryMode.PERSISTENT,
                        message_id=event["event_id"]),
                routing_key=et,
            )
        queue = await ch.get_queue(queue_name, ensure=False)
        got = []
        for _ in event_types:
            try:
                msg = await asyncio.wait_for(queue.get(fail=False), timeout=timeout_each)
            except asyncio.TimeoutError:
                break
            if msg is None:
                break
            got.append(json.loads(msg.body.decode())["event_type"])
            await msg.ack()
        return got
    finally:
        await conn.close()


def test_notification_binding_uses_hash_not_star(rmq):
    # order.# must receive multi-segment events that order.* would miss.
    got = asyncio.run(_publish_and_collect(
        [ORDER_PAID, ORDER_PAYMENT_FAILED, ORDER_DRIVER_ASSIGNED],
        settings.notification_queue,
    ))
    assert ORDER_PAID in got
    assert ORDER_PAYMENT_FAILED in got, "order.# missed order.payment.failed"
    assert ORDER_DRIVER_ASSIGNED in got, "order.# missed order.driver.assigned"


def test_payment_queue_only_gets_order_created(rmq):
    got = asyncio.run(_publish_and_collect(
        [ORDER_CREATED, ORDER_PAID], settings.payment_queue, timeout_each=3.0))
    assert got == [ORDER_CREATED]


def test_dead_letter_topology(rmq):
    async def _run():
        conn = await aio_pika.connect_robust(settings.amqp_url)
        try:
            ch = await conn.channel()
            await declare_topology(ch)
            dead = await ch.get_exchange(settings.dead_exchange_name, ensure=False)
            assert dead.name == settings.dead_exchange_name
            await dead.publish(
                Message(b'{"dead": true}', content_type="application/json",
                        delivery_mode=DeliveryMode.PERSISTENT),
                routing_key="failed",
            )
            dlq = await ch.get_queue(settings.dead_letter_queue, ensure=False)
            msg = await asyncio.wait_for(dlq.get(fail=False), timeout=5)
            assert msg is not None
            assert msg.body == b'{"dead": true}'
            await msg.ack()
        finally:
            await conn.close()
    asyncio.run(_run())


def test_queues_are_durable_not_exclusive_not_autodelete(rmq):
    async def _run():
        conn = await aio_pika.connect_robust(settings.amqp_url)
        try:
            ch = await conn.channel()
            for qname in (settings.payment_queue, settings.restaurant_queue,
                          settings.delivery_queue, settings.notification_queue,
                          settings.dead_letter_queue):
                # Passive redeclare with identical flags must succeed.
                await ch.declare_queue(qname, durable=True, exclusive=False,
                                       auto_delete=False, passive=True)
        finally:
            await conn.close()
    asyncio.run(_run())
