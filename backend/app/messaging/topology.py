"""RabbitMQ topology declaration (assignment §9).

Durable topic exchange ``quickbite.orders`` with:
  payment.queue      <- order.created
  restaurant.queue   <- order.paid
  delivery.queue     <- order.confirmed
  notification.queue <- order.#        (HASH, not star: order.* would miss
                                       order.payment.failed and order.driver.assigned)

Durable direct exchange ``quickbite.dead`` with:
  orders.dead-letter.queue  <- routing key "failed"

All queues are durable, non-exclusive, non-auto-delete and are declared
before any event is dispatched, so stopping a consumer never removes its queue.
"""
from __future__ import annotations

import logging

from aio_pika import ExchangeType, Message, DeliveryMode
from aio_pika.abc import AbstractChannel

from ..config import settings

log = logging.getLogger("quickbite.topology")

BINDINGS: tuple[tuple[str, str], ...] = (
    (settings.payment_queue, "order.created"),
    (settings.restaurant_queue, "order.paid"),
    (settings.delivery_queue, "order.confirmed"),
    # NOTE: order.# (multi-segment wildcard) is required; order.* would miss
    # order.payment.failed and order.driver.assigned.
    (settings.notification_queue, "order.#"),
)


async def declare_topology(channel: AbstractChannel) -> None:
    """Idempotent declaration of the full topology."""
    exchange = await channel.declare_exchange(
        settings.exchange_name, ExchangeType.TOPIC, durable=True
    )
    for queue_name, routing_key in BINDINGS:
        queue = await channel.declare_queue(queue_name, durable=True, exclusive=False,
                                            auto_delete=False)
        await queue.bind(exchange, routing_key=routing_key)
        log.info("bound queue=%s key=%s", queue_name, routing_key)

    dead = await channel.declare_exchange(
        settings.dead_exchange_name, ExchangeType.DIRECT, durable=True
    )
    dlq = await channel.declare_queue(
        settings.dead_letter_queue, durable=True, exclusive=False, auto_delete=False
    )
    await dlq.bind(dead, routing_key="failed")
    log.info("bound dead-letter queue=%s key=failed", settings.dead_letter_queue)


def amqp_message(event: dict, *, attempt: int = 1) -> Message:
    """Serialize an envelope to a persistent AMQP message.

    message_id == event_id (stable across retries); the attempt counter is
    delivery metadata in headers, not a new domain-event identity.
    """
    import json

    return Message(
        json.dumps(event).encode("utf-8"),
        content_type="application/json",
        delivery_mode=DeliveryMode.PERSISTENT,
        message_id=event["event_id"],
        headers={"attempt": attempt, "schema_version": event.get("schema_version", 1)},
    )
