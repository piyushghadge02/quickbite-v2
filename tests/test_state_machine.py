"""State machine unit tests (assignment §6)."""
from __future__ import annotations

import pytest

from backend.app.domain import state_machine
from backend.app.models import Order


def _order(status):
    return Order(id="o", customer_id="c", restaurant_id="r", delivery_address="addr",
                 currency="INR", total_minor=100, status=status, version=1)


def test_happy_path_transitions():
    o = _order("PENDING")
    for nxt in ("PAID", "CONFIRMED", "DRIVER_ASSIGNED"):
        h = state_machine.apply_transition(o, nxt)
        assert o.status == nxt
        assert h.version == o.version
    assert o.version == 4


def test_terminal_transitions():
    o = _order("PENDING")
    state_machine.apply_transition(o, "PAYMENT_FAILED", failure_code="DECLINED")
    assert o.failure_code == "DECLINED"
    with pytest.raises(ValueError):
        state_machine.apply_transition(o, "PAID")


def test_failed_from_paid_and_confirmed():
    for start in ("PAID", "CONFIRMED"):
        o = _order(start)
        state_machine.apply_transition(o, "FAILED")
        assert o.status == "FAILED"


def test_no_backward_or_skip_transitions():
    o = _order("CONFIRMED")
    for bad in ("PENDING", "PAID", "PAYMENT_FAILED", "BOGUS"):
        with pytest.raises(ValueError):
            state_machine.apply_transition(o, bad)


def test_terminal_states_are_final():
    for s in ("DRIVER_ASSIGNED", "PAYMENT_FAILED", "FAILED"):
        assert state_machine.can_transition(s, "PAID") is False
        assert s in state_machine.TERMINAL_STATES
