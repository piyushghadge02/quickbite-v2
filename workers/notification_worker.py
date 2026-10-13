"""Notification worker: order.# -> persisted customer notifications.

Bound with order.# so it receives two-segment events (order.paid) AND
multi-segment events (order.payment.failed, order.driver.assigned).

Notifications are UNIQUE(customer_id, event_id): redeliveries never create
duplicates. Notification failures NEVER change order status: exhaustion
quarantines the event and preserves the business state
(terminal_transition / terminal_event_for are no-ops).

NOTIFICATION_FAIL_MODE=always-fail simulates a notification outage; the
order pipeline is unaffected and the backlog drains on restart.
"""
from __future__ import annotations

import asyncio
import logging
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import select  # noqa: E402
from sqlalchemy.exc import IntegrityError  # noqa: E402

from backend.app.config import settings  # noqa: E402
from backend.app.messaging.envelope import KNOWN_EVENT_TYPES  # noqa: E402
from backend.app.models import Notification, Order  # noqa: E402
from workers.base import OK, TRANSIENT, HandleResult, Worker  # noqa: E402

log = logging.getLogger("quickbite.worker.notification")

TITLES = {
    "order.created": ("Order received", "Your order {order_id} was accepted and is being processed."),
    "order.paid": ("Payment successful", "Payment for order {order_id} succeeded."),
    "order.payment.failed": (
        "Payment failed",
        "Payment for order {order_id} could not be completed ({reason}). No charge was made.",
    ),
    "order.confirmed": ("Order confirmed", "The restaurant confirmed order {order_id}."),
    "order.driver.assigned": (
        "Driver assigned",
        "Driver {driver} was assigned to order {order_id}.",
    ),
    "order.failed": (
        "Order failed",
        "Order {order_id} could not be completed: {reason}.",
    ),
}


class NotificationWorker(Worker):
    consumer_name = "notification"
    queue_name = settings.notification_queue

    def handle(self, session, envelope: dict, attempt: int) -> HandleResult:
        event_type = envelope["event_type"]
        if event_type not in TITLES:
            # Valid future event type we intentionally ignore (acked, logged).
            log.info("notification ignoring event_type=%s event=%s",
                     event_type, envelope["event_id"])
            return HandleResult(OK, note=f"intentionally ignoring {event_type}")

        if settings.notification_fail_mode == "always-fail":
            return HandleResult(TRANSIENT, failure_code="NOTIFICATION_OUTAGE",
                                note="simulated notification outage")

        order = session.execute(
            select(Order).where(Order.id == envelope["order_id"])
        ).scalar_one_or_none()
        if order is None:
            # No valid order reference: nothing to notify; ack as no-op.
            # (Truly malformed envelopes never reach here — they are
            # quarantined by the base class before handle().)
            return HandleResult(OK, note="order not found; nothing to notify")

        title_tpl, body_tpl = TITLES[event_type]
        data = envelope.get("data") or {}
        reason = data.get("failure_code") or data.get("message") or "see order details"
        body = body_tpl.format(
            order_id=order.id,
            reason=reason,
            driver=data.get("driver_name", "your driver"),
        )
        try:
            session.add(Notification(
                customer_id=order.customer_id,
                event_id=envelope["event_id"],
                event_type=event_type,
                order_id=order.id,
                title=title_tpl,
                body=body,
            ))
            session.flush()
        except IntegrityError:
            # Duplicate delivery: notification already persisted.
            session.rollback()
            return HandleResult(OK, note="notification already persisted")
        return HandleResult(OK, note="notification persisted")

    # terminal_transition / terminal_event_for intentionally inherit the
    # base no-ops: notification quarantine preserves order business status.


async def main() -> None:
    await NotificationWorker().run()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    asyncio.run(main())
