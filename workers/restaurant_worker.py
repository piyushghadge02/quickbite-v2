"""Restaurant worker: order.paid -> PAID→CONFIRMED or →FAILED.

RESTAURANT_FAIL_MODE=always-fail simulates a permanent business decline
(restaurant rejects the order): skips retries, transitions PAID→FAILED and
emits order.failed.
"""
from __future__ import annotations

import asyncio
import logging
import os
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import select  # noqa: E402

from backend.app.config import settings  # noqa: E402
from backend.app.domain import state_machine  # noqa: E402
from backend.app.messaging.envelope import ORDER_CONFIRMED, ORDER_FAILED, ORDER_PAID, child_event  # noqa: E402
from backend.app.models import Order, OutboxEvent  # noqa: E402
from workers.base import OK, PERMANENT, HandleResult, Worker  # noqa: E402

log = logging.getLogger("quickbite.worker.restaurant")


class RestaurantWorker(Worker):
    consumer_name = "restaurant"
    queue_name = settings.restaurant_queue

    def handle(self, session, envelope: dict, attempt: int) -> HandleResult:
        if envelope["event_type"] != ORDER_PAID:
            return HandleResult(OK, note="ignoring non-restaurant event")
        if settings.sim_restaurant_delay_s > 0:
            time.sleep(settings.sim_restaurant_delay_s)

        order = session.execute(
            select(Order).where(Order.id == envelope["order_id"]).with_for_update()
        ).scalar_one_or_none()
        if order is None:
            return HandleResult(PERMANENT, failure_code="ORDER_NOT_FOUND")
        if order.status != state_machine.PAID:
            return HandleResult(OK, note=f"order already {order.status}")

        if settings.restaurant_fail_mode == "always-fail":
            return HandleResult(PERMANENT, failure_code="RESTAURANT_REJECTED",
                                note="simulated permanent restaurant decline")

        history = state_machine.apply_transition(order, state_machine.CONFIRMED,
                                                 note="Restaurant accepted the order.")
        session.add(history)
        child = child_event(envelope, event_type=ORDER_CONFIRMED, order_version=order.version,
                            data={"restaurant_id": order.restaurant_id})
        session.add(OutboxEvent(
            event_id=child["event_id"], exchange=settings.exchange_name,
            routing_key=ORDER_CONFIRMED, payload=child, state="pending",
            available_at=datetime.now(timezone.utc),
        ))
        return HandleResult(OK, note="restaurant confirmed")

    def terminal_transition(self, session, order: Order, failure_code: str) -> None:
        if order.status == state_machine.PAID:
            session.add(state_machine.apply_transition(
                order, state_machine.FAILED, note="Restaurant could not fulfil the order.",
                failure_code=failure_code))

    def terminal_event_for(self, session, envelope: dict, failure_code: str) -> dict | None:
        return child_event(
            envelope, event_type=ORDER_FAILED,
            order_version=envelope.get("order_version", 1),
            data={"stage": "restaurant", "failure_code": failure_code,
                  "message": "The restaurant could not accept your order."},
        )


async def main() -> None:
    await RestaurantWorker().run()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    asyncio.run(main())
