"""Checkout service: validation, server-side totals, idempotency, outbox.

POST /api/v1/orders acceptance commits, in ONE PostgreSQL transaction:
  1. the order + order_items (server-priced snapshots)
  2. the initial order_status_history row (PENDING, version 1)
  3. the idempotency record (key scoped to customer + canonical request hash)
  4. the outbox event (order.created -> quickbite.orders)

Idempotency semantics (§7):
  * same key + same payload  -> replay stored 202 response + Location, no new order
  * same key + different payload -> 409
  * concurrent identical requests -> exactly one order (UNIQUE(user_id, idem_key);
    IntegrityError is mapped to a re-read, which then replays)
"""
from __future__ import annotations

import hashlib
import json
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from ..config import settings
from ..errors import AppError
from ..messaging.envelope import ORDER_CREATED, build_event
from ..models import (
    IdempotencyRecord,
    MenuItem,
    Order,
    OrderItem,
    OrderStatusHistory,
    OutboxEvent,
    Restaurant,
)
from ..security import new_id

MAX_DISTINCT_ITEMS = 20
MAX_QUANTITY = 20
CURRENCY = "INR"
ACCEPT_MESSAGE = "Order accepted for asynchronous processing."


def canonical_hash(payload: dict) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _canonical_request(restaurant_id: str, delivery_address: str, items: list[dict]) -> dict:
    return {
        "restaurant_id": restaurant_id,
        "delivery_address": delivery_address.strip(),
        "items": sorted(
            ({"menu_item_id": i["menu_item_id"], "quantity": i["quantity"]} for i in items),
            key=lambda d: d["menu_item_id"],
        ),
    }


def _conflict(details=None) -> AppError:
    return AppError(
        409,
        "IDEMPOTENCY_CONFLICT",
        "Idempotency-Key was already used with a different request payload.",
        details,
    )


def _replay_response(record: IdempotencyRecord) -> tuple[dict, str]:
    body = dict(record.response)
    location = f"/api/v1/orders/{record.order_id}"
    return body, location


def checkout(
    session: Session,
    *,
    customer_id: str,
    idem_key: str,
    restaurant_id: str,
    delivery_address: str,
    items: list[dict],
    correlation_id: str | None = None,
) -> tuple[dict, str, bool]:
    """Returns (response_body, location, created_new). Raises AppError."""
    if not idem_key:
        raise AppError(
            422, "MISSING_IDEMPOTENCY_KEY", "Idempotency-Key header is required.",
            {"header": "Idempotency-Key"},
        )

    # --- validate ---------------------------------------------------------
    if not delivery_address or len(delivery_address.strip()) < 8:
        raise AppError(422, "INVALID_ADDRESS",
                       "delivery_address must be at least 8 characters.",
                       {"field": "delivery_address"})
    if not items:
        raise AppError(422, "EMPTY_CART", "At least one item is required.",
                       {"field": "items"})
    if len(items) > MAX_DISTINCT_ITEMS:
        raise AppError(422, "TOO_MANY_ITEMS",
                       f"At most {MAX_DISTINCT_ITEMS} distinct items per order.",
                       {"field": "items", "max": MAX_DISTINCT_ITEMS})
    seen: set[str] = set()
    for it in items:
        mid = it.get("menu_item_id")
        qty = it.get("quantity")
        if not mid or not isinstance(qty, int) or not (1 <= qty <= MAX_QUANTITY):
            raise AppError(422, "INVALID_ITEM",
                           f"Each item needs a menu_item_id and quantity 1..{MAX_QUANTITY}.",
                           {"item": it})
        if mid in seen:
            raise AppError(422, "DUPLICATE_ITEM",
                           "Duplicate menu_item_id in request.", {"menu_item_id": mid})
        seen.add(mid)

    restaurant = session.get(Restaurant, restaurant_id)
    if restaurant is None or not restaurant.is_active:
        raise AppError(404, "RESTAURANT_NOT_FOUND",
                       "Restaurant not found or inactive.",
                       {"restaurant_id": restaurant_id})

    menu_rows = session.execute(
        select(MenuItem).where(MenuItem.id.in_(seen))
    ).scalars().all()
    menu_by_id = {m.id: m for m in menu_rows}
    for mid in seen:
        m = menu_by_id.get(mid)
        if m is None or m.restaurant_id != restaurant_id:
            raise AppError(422, "MIXED_RESTAURANT",
                           "All items must belong to the requested restaurant.",
                           {"menu_item_id": mid})
        if not m.is_available:
            raise AppError(422, "ITEM_UNAVAILABLE",
                           "Menu item is currently unavailable.",
                           {"menu_item_id": mid})

    # --- server-side totals (never trust client prices/totals) -------------
    total_minor = sum(menu_by_id[it["menu_item_id"]].price_minor * it["quantity"]
                      for it in items)
    if total_minor <= 0:
        raise AppError(422, "INVALID_TOTAL", "Order total must be positive.", None)

    request_hash = canonical_hash(
        _canonical_request(restaurant_id, delivery_address, items))

    # --- idempotency fast path ---------------------------------------------
    existing = session.execute(
        select(IdempotencyRecord).where(
            IdempotencyRecord.user_id == customer_id,
            IdempotencyRecord.idem_key == idem_key,
        )
    ).scalar_one_or_none()
    if existing is not None:
        if existing.request_hash != request_hash:
            raise _conflict({"order_id": existing.order_id})
        body, location = _replay_response(existing)
        return body, location, False

    # --- atomic accept ------------------------------------------------------
    order_id = new_id("order")
    now = datetime.now(timezone.utc)
    order = Order(
        id=order_id,
        customer_id=customer_id,
        restaurant_id=restaurant_id,
        delivery_address=delivery_address.strip(),
        currency=CURRENCY,
        total_minor=total_minor,
        status="PENDING",
        version=1,
    )
    session.add(order)
    session.flush()
    for it in items:
        m = menu_by_id[it["menu_item_id"]]
        session.add(OrderItem(
            order_id=order_id,
            menu_item_id=m.id,
            item_name=m.name,
            quantity=it["quantity"],
            unit_price_minor=m.price_minor,
        ))
    session.add(OrderStatusHistory(
        order_id=order_id, from_status=None, to_status="PENDING", version=1,
        note="Order accepted.",
    ))
    body = {
        "order_id": order_id,
        "status": "PENDING",
        "currency": CURRENCY,
        "total_amount_minor": total_minor,
        "version": 1,
        "message": ACCEPT_MESSAGE,
    }
    record = IdempotencyRecord(
        user_id=customer_id, idem_key=idem_key, request_hash=request_hash,
        order_id=order_id, response=body,
    )
    session.add(record)
    event = build_event(
        event_type=ORDER_CREATED, order_id=order_id, order_version=1,
        data={"customer_id": customer_id, "restaurant_id": restaurant_id,
              "total_minor": total_minor, "currency": CURRENCY},
        correlation_id=correlation_id,
    )
    session.add(OutboxEvent(
        event_id=event["event_id"],
        exchange=settings.exchange_name,
        routing_key=ORDER_CREATED,
        payload=event,
        state="pending",
        available_at=now,
    ))
    try:
        session.commit()
    except IntegrityError:
        # Lost a concurrent race on (user_id, idem_key): re-read and replay.
        session.rollback()
        winner = session.execute(
            select(IdempotencyRecord).where(
                IdempotencyRecord.user_id == customer_id,
                IdempotencyRecord.idem_key == idem_key,
            )
        ).scalar_one_or_none()
        if winner is not None:
            if winner.request_hash != request_hash:
                raise _conflict({"order_id": winner.order_id})
            body, location = _replay_response(winner)
            return body, location, False
        raise
    return body, f"/api/v1/orders/{order_id}", True
