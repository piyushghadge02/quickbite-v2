"""Checkout idempotency: replay, conflict, concurrency (assignment §7)."""
from __future__ import annotations

import concurrent.futures
import uuid

from sqlalchemy import func, select

from backend.app.models import IdempotencyRecord, Order, OutboxEvent
from .conftest import checkout_payload, place_order


def test_same_key_same_payload_replays(client, cust1_headers, db):
    key = str(uuid.uuid4())
    r1, _ = place_order(client, cust1_headers, key=key)
    r2, _ = place_order(client, cust1_headers, key=key)
    assert r1.status_code == 202 and r2.status_code == 202
    assert r1.json()["order_id"] == r2.json()["order_id"]
    assert r1.headers["Location"] == r2.headers["Location"]
    assert db.execute(select(func.count()).select_from(Order)).scalar() == 1
    assert db.execute(select(func.count()).select_from(OutboxEvent)).scalar() == 1


def test_same_key_different_payload_conflicts(client, cust1_headers, db):
    key = str(uuid.uuid4())
    r1, _ = place_order(client, cust1_headers, key=key)
    assert r1.status_code == 202
    payload = checkout_payload(items=[{"menu_item_id": "t_lassi", "quantity": 5}])
    r2 = client.post("/api/v1/orders", json=payload,
                     headers={**cust1_headers, "Idempotency-Key": key})
    assert r2.status_code == 409, r2.text
    assert r2.json()["code"] == "IDEMPOTENCY_CONFLICT"
    assert db.execute(select(func.count()).select_from(Order)).scalar() == 1


def test_key_scoped_to_customer(client, cust1_headers, cust2_headers, db):
    key = "shared-key-across-customers"
    r1, _ = place_order(client, cust1_headers, key=key)
    r2, _ = place_order(client, cust2_headers, key=key)
    assert r1.status_code == 202 and r2.status_code == 202
    assert r1.json()["order_id"] != r2.json()["order_id"]
    assert db.execute(select(func.count()).select_from(Order)).scalar() == 2


def test_missing_idempotency_key_422(client, cust1_headers):
    r = client.post("/api/v1/orders", json=checkout_payload(), headers=cust1_headers)
    assert r.status_code == 422
    assert r.json()["code"] == "MISSING_IDEMPOTENCY_KEY"


def test_concurrent_identical_requests_create_one_order(client, cust1_headers, db):
    key = str(uuid.uuid4())
    payload = checkout_payload()

    def attempt(_i):
        from fastapi.testclient import TestClient
        from backend.app.main import create_app
        c = TestClient(create_app(), raise_server_exceptions=False)
        return c.post("/api/v1/orders", json=payload,
                      headers={**cust1_headers, "Idempotency-Key": key})

    with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
        results = list(pool.map(attempt, range(10)))
    assert all(r.status_code == 202 for r in results), [r.status_code for r in results]
    order_ids = {r.json()["order_id"] for r in results}
    assert len(order_ids) == 1
    assert db.execute(select(func.count()).select_from(Order)).scalar() == 1
    assert db.execute(select(func.count()).select_from(IdempotencyRecord)).scalar() == 1
