"""Delivery worker: order.confirmed -> CONFIRMED→DRIVER_ASSIGNED or →FAILED.

Assigns a seeded driver deterministically (active driver with the fewest
assignments). driver_assignments has UNIQUE(order_id), so concurrent or
repeated deliveries can never assign two drivers to one order: the loser
re-reads the winner's assignment (IntegrityError -> re-read).

DELIVERY_FAIL_MODE=always-fail simulates a permanent failure:
CONFIRMED→FAILED + order.failed.
"""
from __future__ import annotations

import asyncio
import logging
import os
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import func, select  # noqa: E402
from sqlalchemy.exc import IntegrityError  # noqa: E402

from backend.app.config import settings  # noqa: E402
from backend.app.domain import state_machine  # noqa: E402
from backend.app.messaging.envelope import (  # noqa: E402
    ORDER_CONFIRMED,
    ORDER_DRIVER_ASSIGNED,
    ORDER_FAILED,
    child_event,
)
from backend.app.models import Driver, DriverAssignment, Order, OutboxEvent  # noqa: E402
from workers.base import OK, PERMANENT, HandleResult, Worker  # noqa: E402

log = logging.getLogger("quickbite.worker.delivery")


class DeliveryWorker(Worker):
    consumer_name = "delivery"
    queue_name = settings.delivery_queue

    def _pick_driver(self, session) -> Driver | None:
        counts = (
            select(DriverAssignment.driver_id, func.count().label("n"))
            .group_by(DriverAssignment.driver_id)
            .subquery()
        )
        row = session.execute(
            select(Driver, func.coalesce(counts.c.n, 0).label("n"))
            .outerjoin(counts, counts.c.driver_id == Driver.id)
            .where(Driver.is_active.is_(True))
            .order_by("n", Driver.id)
            .limit(1)
        ).first()
        return row[0] if row else None

    def handle(self, session, envelope: dict, attempt: int) -> HandleResult:
        if envelope["event_type"] != ORDER_CONFIRMED:
            return HandleResult(OK, note="ignoring non-delivery event")
        if settings.sim_delivery_delay_s > 0:
            time.sleep(settings.sim_delivery_delay_s)

        order = session.execute(
            select(Order).where(Order.id == envelope["order_id"]).with_for_update()
        ).scalar_one_or_none()
        if order is None:
            return HandleResult(PERMANENT, failure_code="ORDER_NOT_FOUND")
        if order.status != state_machine.CONFIRMED:
            return HandleResult(OK, note=f"order already {order.status}")

        if settings.delivery_fail_mode == "always-fail":
            return HandleResult(PERMANENT, failure_code="NO_DRIVERS_AVAILABLE",
                                note="simulated permanent delivery failure")

        driver = self._pick_driver(session)
        if driver is None:
            return HandleResult(PERMANENT, failure_code="NO_DRIVERS_AVAILABLE",
                                note="no active drivers seeded")

        history = state_machine.apply_transition(
            order, state_machine.DRIVER_ASSIGNED,
            note=f"Driver {driver.name} assigned.")
        session.add(history)
        order.driver_id = driver.id
        try:
            session.add(DriverAssignment(order_id=order.id, driver_id=driver.id))
            session.flush()
        except IntegrityError:
            # Lost a race with another delivery worker on the same order:
            # roll back and re-check; the winner's commit is now visible.
            session.rollback()
            order = session.execute(
                select(Order).where(Order.id == envelope["order_id"]).with_for_update()
            ).scalar_one()
            existing = session.execute(
                select(DriverAssignment).where(DriverAssignment.order_id == order.id)
            ).scalar_one_or_none()
            if existing is not None and order.status == state_machine.DRIVER_ASSIGNED:
                return HandleResult(OK, note="driver already assigned by racing worker")
            # Genuinely unexpected: leave unacked for redelivery.
            raise
        child = child_event(
            envelope, event_type=ORDER_DRIVER_ASSIGNED, order_version=order.version,
            data={"driver_id": driver.id, "driver_name": driver.name},
        )
        session.add(OutboxEvent(
            event_id=child["event_id"], exchange=settings.exchange_name,
            routing_key=ORDER_DRIVER_ASSIGNED, payload=child, state="pending",
            available_at=datetime.now(timezone.utc),
        ))
        return HandleResult(OK, note=f"driver {driver.id} assigned")

    def terminal_transition(self, session, order: Order, failure_code: str) -> None:
        if order.status == state_machine.CONFIRMED:
            session.add(state_machine.apply_transition(
                order, state_machine.FAILED, note="Delivery could not be arranged.",
                failure_code=failure_code))

    def terminal_event_for(self, session, envelope: dict, failure_code: str) -> dict | None:
        return child_event(
            envelope, event_type=ORDER_FAILED,
            order_version=envelope.get("order_version", 1),
            data={"stage": "delivery", "failure_code": failure_code,
                  "message": "A driver could not be assigned to your order."},
        )


async def main() -> None:
    await DeliveryWorker().run()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    asyncio.run(main())
