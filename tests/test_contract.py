"""API contract tests: validation, server-side totals, pagination, envelopes."""
from __future__ import annotations

from sqlalchemy import func, select

from backend.app.models import IdempotencyRecord, Order, OutboxEvent
from .conftest import checkout_payload, place_order


def test_checkout_example_totals(client, cust1_headers, db):
    # Worked example from the assignment: 2x1250 + 1x400 = 2900 minor units.
    resp, key = place_order(client, cust1_headers)
    assert resp.status_code == 202, resp.text
    body = resp.json()
    assert body["status"] == "PENDING"
    assert body["currency"] == "INR"
    assert body["total_amount_minor"] == 2900
    assert body["version"] == 1
    assert body["message"] == "Order accepted for asynchronous processing."
    assert resp.headers["Location"] == f"/api/v1/orders/{body['order_id']}"
    order = db.get(Order, body["order_id"])
    assert order.total_minor == 2900
    assert order.version == 1


def test_checkout_rejects_mixed_restaurant_no_partial_commit(client, cust1_headers, db):
    payload = checkout_payload(items=[
        {"menu_item_id": "t_biryani", "quantity": 1},
        {"menu_item_id": "t_other_item", "quantity": 1},  # belongs to t_rest2
    ])
    r = client.post("/api/v1/orders", json=payload,
                    headers={**cust1_headers, "Idempotency-Key": "k-mixed"})
    assert r.status_code == 422, r.text
    assert db.execute(select(func.count()).select_from(Order)).scalar() == 0
    assert db.execute(select(func.count()).select_from(OutboxEvent)).scalar() == 0
    assert db.execute(select(func.count()).select_from(IdempotencyRecord)).scalar() == 0


def test_checkout_rejects_unavailable_item(client, cust1_headers, db):
    payload = checkout_payload(items=[{"menu_item_id": "t_stale", "quantity": 1}])
    r = client.post("/api/v1/orders", json=payload,
                    headers={**cust1_headers, "Idempotency-Key": "k-stale"})
    assert r.status_code == 422
    assert r.json()["code"] == "ITEM_UNAVAILABLE"


def test_checkout_rejects_bad_quantities(client, cust1_headers):
    for items in [[{"menu_item_id": "t_biryani", "quantity": 0}],
                  [{"menu_item_id": "t_biryani", "quantity": 21}],
                  []]:
        r = client.post("/api/v1/orders", json=checkout_payload(items=items),
                        headers={**cust1_headers, "Idempotency-Key": "k-q"})
        assert r.status_code == 422, (items, r.text)


def test_checkout_rejects_too_many_distinct_items(client, cust1_headers):
    items = [{"menu_item_id": f"item_{i}", "quantity": 1} for i in range(21)]
    r = client.post("/api/v1/orders", json=checkout_payload(items=items),
                    headers={**cust1_headers, "Idempotency-Key": "k-21"})
    assert r.status_code == 422


def test_checkout_totals_come_from_server_menu(client, cust1_headers, db):
    # Even if the client tries to smuggle price fields, totals are server-side.
    payload = checkout_payload()
    payload["items"][0]["unit_price_minor"] = 1  # ignored unknown field
    payload["total_amount_minor"] = 1            # ignored unknown field
    r = client.post("/api/v1/orders", json=payload,
                    headers={**cust1_headers, "Idempotency-Key": "k-srv"})
    assert r.status_code == 202, r.text
    assert r.json()["total_amount_minor"] == 2900


def test_pagination_envelope_and_max_page_size(client, cust1_headers):
    r = client.get("/api/v1/restaurants?page=1&page_size=2", headers=cust1_headers)
    assert r.status_code == 200
    body = r.json()
    assert set(body) == {"items", "page", "page_size", "total"}
    assert body["page"] == 1 and body["page_size"] == 2 and body["total"] == 2
    r = client.get("/api/v1/restaurants?page_size=101", headers=cust1_headers)
    assert r.status_code == 422
    assert r.json()["code"] == "INVALID_PAGE_SIZE"


def test_error_envelope_shape(client, cust1_headers):
    r = client.get("/api/v1/orders/order_nope", headers=cust1_headers)
    assert r.status_code == 404
    body = r.json()
    assert set(body) == {"code", "message", "details", "request_id"}
    assert body["code"] == "ORDER_NOT_FOUND"
    assert body["request_id"]


def test_validation_error_uses_envelope(client, cust1_headers):
    r = client.post("/api/v1/orders", json={"bogus": True}, headers=cust1_headers)
    assert r.status_code == 422
    body = r.json()
    assert body["code"] in ("VALIDATION_ERROR", "MISSING_IDEMPOTENCY_KEY")
    assert "request_id" in body


def test_unauthenticated_rejected(client):
    r = client.get("/api/v1/restaurants")
    assert r.status_code == 401
    assert r.json()["code"] == "UNAUTHENTICATED"


def test_health_live(client):
    r = client.get("/health/live")
    assert r.status_code == 200
    assert r.json()["status"] == "ok"


def test_health_ready_with_real_deps(client):
    r = client.get("/health/ready")
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["status"] == "ready"
    assert body["details"]["database"]["ok"] is True
    assert body["details"]["broker"]["ok"] is True


def test_timestamps_are_tz_aware_utc(client, cust1_headers):
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    r = client.get(f"/api/v1/orders/{order_id}", headers=cust1_headers)
    ts = r.json()["created_at"]
    assert ts.endswith("+00:00") or ts.endswith("Z"), ts
