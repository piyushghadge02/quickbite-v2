"""Event envelope construction and validation (assignment §9).

Every event carries: event_id (immutable), schema_version, event_type,
order_id, order_version, occurred_at, correlation_id, causation_id, data.
AMQP message_id == event_id; JSON content type; persistent delivery mode.
Retry attempts are delivery metadata (AMQP headers), never a new identity.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ..errors import AppError
from ..security import new_id

SCHEMA_VERSION = 1

# Required event types (assignment §9).
ORDER_CREATED = "order.created"
ORDER_PAID = "order.paid"
ORDER_PAYMENT_FAILED = "order.payment.failed"
ORDER_CONFIRMED = "order.confirmed"
ORDER_DRIVER_ASSIGNED = "order.driver.assigned"
ORDER_FAILED = "order.failed"

KNOWN_EVENT_TYPES = frozenset(
    {
        ORDER_CREATED,
        ORDER_PAID,
        ORDER_PAYMENT_FAILED,
        ORDER_CONFIRMED,
        ORDER_DRIVER_ASSIGNED,
        ORDER_FAILED,
    }
)

REQUIRED_FIELDS = (
    "event_id",
    "schema_version",
    "event_type",
    "order_id",
    "order_version",
    "occurred_at",
    "correlation_id",
    "causation_id",
    "data",
)


def utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def build_event(
    *,
    event_type: str,
    order_id: str,
    order_version: int,
    data: dict[str, Any] | None = None,
    correlation_id: str | None = None,
    causation_id: str | None = None,
    event_id: str | None = None,
) -> dict[str, Any]:
    return {
        "event_id": event_id or new_id("evt"),
        "schema_version": SCHEMA_VERSION,
        "event_type": event_type,
        "order_id": order_id,
        "order_version": order_version,
        "occurred_at": utcnow_iso(),
        "correlation_id": correlation_id or new_id("corr"),
        "causation_id": causation_id,
        "data": data or {},
    }


def child_event(
    parent: dict[str, Any],
    *,
    event_type: str,
    order_version: int,
    data: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """A child event keeps correlation_id and sets causation_id to the parent."""
    return build_event(
        event_type=event_type,
        order_id=parent["order_id"],
        order_version=order_version,
        data=data,
        correlation_id=parent.get("correlation_id"),
        causation_id=parent.get("event_id"),
    )


class EnvelopeError(AppError):
    def __init__(self, message: str, details: Any = None):
        super().__init__(422, "INVALID_EVENT_ENVELOPE", message, details)


def validate_envelope(raw: Any) -> dict[str, Any]:
    """Validate a decoded JSON body; returns the envelope dict or raises."""
    if not isinstance(raw, dict):
        raise EnvelopeError("Event body must be a JSON object.")
    missing = [f for f in REQUIRED_FIELDS if f not in raw]
    if missing:
        raise EnvelopeError("Event envelope missing required fields.", {"missing": missing})
    if raw["schema_version"] != SCHEMA_VERSION:
        raise EnvelopeError(
            "Unsupported event schema version.",
            {"schema_version": raw["schema_version"], "supported": SCHEMA_VERSION},
        )
    if not isinstance(raw["data"], dict):
        raise EnvelopeError("Event data must be an object.")
    # Unknown event types with a valid schema are NOT malformed: a worker may
    # intentionally ignore (and acknowledge) a valid future event type.
    return raw
