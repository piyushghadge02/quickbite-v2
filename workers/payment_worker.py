"""Payment worker: order.created -> PENDING→PAID or →PAYMENT_FAILED.

Deterministic simulation modes (PAYMENT_SIM_MODE, dev/test/demo only —
never selectable through checkout fields):
  succeed                 always succeed
  fail-twice-then-succeed transient failure on attempts 1-2, succeed on 3+
  always-fail             transient failure until attempts exhausted, then
                          PAYMENT_FAILED + order.payment.failed + quarantine
  crash-after-checkpoint  os._exit at PAYMENT_CRASH_POINT
                          (before-tx | after-commit | before-ack)
  random                  exploration only: ~30% transient failure
"""
from __future__ import annotations

import asyncio
import logging
import os
import random
import sys
import time
from datetime import datetime, timezone

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from sqlalchemy import select  # noqa: E402

from backend.app.config import settings  # noqa: E402
from backend.app.domain import state_machine  # noqa: E402
from backend.app.messaging.envelope import (  # noqa: E402
    ORDER_CREATED,
    ORDER_PAID,
    ORDER_PAYMENT_FAILED,
    child_event,
)
from backend.app.models import Order, OutboxEvent, SimulatedPayment  # noqa: E402
from workers.base import OK, PERMANENT, TRANSIENT, HandleResult, Worker  # noqa: E402

log = logging.getLogger("quickbite.worker.payment")


class PaymentWorker(Worker):
    consumer_name = "payment"
    queue_name = settings.payment_queue

    def handle(self, session, envelope: dict, attempt: int) -> HandleResult:
        if envelope["event_type"] != ORDER_CREATED:
            return HandleResult(OK, note="ignoring non-payment event")
        mode = settings.payment_sim_mode
        if settings.sim_payment_delay_s > 0:
            time.sleep(settings.sim_payment_delay_s)

        order = session.execute(
            select(Order).where(Order.id == envelope["order_id"]).with_for_update()
        ).scalar_one_or_none()
        if order is None:
            return HandleResult(PERMANENT, failure_code="ORDER_NOT_FOUND",
                                note="order row missing")
        if order.status != state_machine.PENDING:
            # Stale/duplicate delivery after state moved on: no-op.
            return HandleResult(OK, note=f"order already {order.status}")

        if mode == "crash-after-checkpoint" and settings.payment_crash_point == "before-tx":
            log.warning("CRASH-INJECT before-tx order=%s", order.id)
            os._exit(1)

        if mode == "fail-twice-then-succeed" and attempt < 3:
            return HandleResult(TRANSIENT, failure_code="SIMULATED_TRANSIENT",
                                note=f"simulated transient failure attempt={attempt}")
        if mode == "always-fail":
            return HandleResult(TRANSIENT, failure_code="SIMULATED_DECLINE",
                                note="simulated permanent decline via retries")
        if mode == "random" and random.random() < 0.3:
            return HandleResult(TRANSIENT, failure_code="SIMULATED_RANDOM",
                                note="random exploration failure")

        # --- success path: single transaction -------------------------------
        history = state_machine.apply_transition(order, state_machine.PAID,
                                                 note="Payment simulated OK.")
        session.add(history)
        session.add(SimulatedPayment(order_id=order.id, status="SUCCEEDED", attempts=attempt))
        child = child_event(envelope, event_type=ORDER_PAID, order_version=order.version,
                            data={"payment_status": "SUCCEEDED"})
        session.add(OutboxEvent(
            event_id=child["event_id"], exchange=settings.exchange_name,
            routing_key=ORDER_PAID, payload=child, state="pending",
            available_at=datetime.now(timezone.utc),
        ))
        session.flush()

        if mode == "crash-after-checkpoint" and settings.payment_crash_point in (
            "after-commit", "before-ack"):
            # Commit, then die before ack: the payment row + outbox row are
            # durable. Redelivery re-runs handle(), sees order already PAID,
            # and becomes a safe no-op via the state check above.
            session.commit()
            log.warning("CRASH-INJECT after-commit order=%s event=%s",
                        order.id, envelope["event_id"])
            os._exit(1)
        return HandleResult(OK, note="payment succeeded")

    def terminal_transition(self, session, order: Order, failure_code: str) -> None:
        if order.status == state_machine.PENDING:
            session.add(state_machine.apply_transition(
                order, state_machine.PAYMENT_FAILED, note="Payment failed permanently.",
                failure_code=failure_code))
            session.add(SimulatedPayment(order_id=order.id, status="FAILED",
                                         failure_code=failure_code))

    def terminal_event_for(self, session, envelope: dict, failure_code: str) -> dict | None:
        return child_event(
            envelope, event_type=ORDER_PAYMENT_FAILED,
            order_version=envelope.get("order_version", 1),
            data={"failure_code": failure_code,
                  "message": "Payment could not be completed."},
        )


async def main() -> None:
    await PaymentWorker().run()


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s %(levelname)s %(name)s %(message)s")
    asyncio.run(main())
