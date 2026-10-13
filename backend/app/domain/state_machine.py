"""Order state machine (assignment §6).

PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED   (DRIVER_ASSIGNED terminal: success)
PENDING -> PAYMENT_FAILED                          (terminal)
PAID -> FAILED                                     (terminal)
CONFIRMED -> FAILED                                (terminal)

Rules: no backward transitions; terminal states are final; transient
failures keep the last successful state; notification failures never
change order status.
"""
from __future__ import annotations

from ..models import Order, OrderStatusHistory

PENDING = "PENDING"
PAID = "PAID"
CONFIRMED = "CONFIRMED"
DRIVER_ASSIGNED = "DRIVER_ASSIGNED"
PAYMENT_FAILED = "PAYMENT_FAILED"
FAILED = "FAILED"

TERMINAL_STATES = frozenset({DRIVER_ASSIGNED, PAYMENT_FAILED, FAILED})

ALLOWED: dict[str, frozenset[str]] = {
    PENDING: frozenset({PAID, PAYMENT_FAILED}),
    PAID: frozenset({CONFIRMED, FAILED}),
    CONFIRMED: frozenset({DRIVER_ASSIGNED, FAILED}),
    DRIVER_ASSIGNED: frozenset(),
    PAYMENT_FAILED: frozenset(),
    FAILED: frozenset(),
}

ALL_STATES = frozenset(ALLOWED)


def can_transition(from_status: str, to_status: str) -> bool:
    return to_status in ALLOWED.get(from_status, frozenset())


def apply_transition(
    order: Order,
    to_status: str,
    *,
    note: str | None = None,
    failure_code: str | None = None,
) -> OrderStatusHistory:
    """Apply one allowed transition: bump version, set status, append history.

    Must be called with the order row locked (SELECT ... FOR UPDATE) inside
    the caller's transaction. Raises ValueError on illegal transitions.
    """
    if to_status not in ALL_STATES:
        raise ValueError(f"unknown status {to_status!r}")
    if not can_transition(order.status, to_status):
        raise ValueError(f"illegal transition {order.status} -> {to_status}")
    from_status = order.status
    order.status = to_status
    order.version += 1
    if failure_code is not None:
        order.failure_code = failure_code
    history = OrderStatusHistory(
        order_id=order.id,
        from_status=from_status,
        to_status=to_status,
        version=order.version,
        note=note,
    )
    return history
