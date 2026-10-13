"""Auth + RBAC: login, token expiry, ownership, admin gating."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

import jwt as pyjwt

from backend.app.config import settings
from .conftest import place_order


def test_login_ok_and_me(client):
    r = client.post("/api/v1/auth/login",
                    json={"email": "cust1@t.test", "password": "cust123"})
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["token_type"] == "bearer"
    assert body["role"] == "customer"
    assert body["user"]["email"] == "cust1@t.test"
    assert body["expires_at"]
    me = client.get("/api/v1/me", headers={"Authorization": f"Bearer {body['access_token']}"})
    assert me.status_code == 200
    assert me.json()["id"] == "t_cust1"


def test_login_bad_credentials(client):
    r = client.post("/api/v1/auth/login",
                    json={"email": "cust1@t.test", "password": "wrong"})
    assert r.status_code == 401
    assert r.json()["code"] == "INVALID_CREDENTIALS"


def test_expired_token_rejected(client):
    payload = {"sub": "t_cust1", "role": "customer",
               "iat": datetime.now(timezone.utc) - timedelta(hours=2),
               "exp": datetime.now(timezone.utc) - timedelta(hours=1)}
    token = pyjwt.encode(payload, settings.jwt_secret, algorithm=settings.jwt_algorithm)
    r = client.get("/api/v1/me", headers={"Authorization": f"Bearer {token}"})
    assert r.status_code == 401
    assert r.json()["code"] == "TOKEN_EXPIRED"


def test_customer_cannot_see_other_customer_order(client, cust1_headers, cust2_headers):
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    r = client.get(f"/api/v1/orders/{order_id}", headers=cust2_headers)
    assert r.status_code == 404  # not 403: no existence leak
    assert r.json()["code"] == "ORDER_NOT_FOUND"


def test_customer_cannot_use_admin_routes(client, cust1_headers):
    for url in ("/api/v1/admin/orders", "/api/v1/admin/summary"):
        r = client.get(url, headers=cust1_headers)
        assert r.status_code == 403, url
        assert r.json()["code"] == "FORBIDDEN"


def test_admin_can_view_any_order_and_summary(client, admin_headers, cust1_headers):
    resp, _ = place_order(client, cust1_headers)
    order_id = resp.json()["order_id"]
    r = client.get(f"/api/v1/orders/{order_id}", headers=admin_headers)
    assert r.status_code == 200
    s = client.get("/api/v1/admin/summary", headers=admin_headers)
    assert s.status_code == 200
    body = s.json()
    assert body["orders_by_status"].get("PENDING") == 1
    assert body["outbox_pending"] >= 1
    assert set(body) == {"orders_by_status", "outbox_pending", "outbox_scheduled",
                         "retries_scheduled", "quarantine_total"}
