#!/usr/bin/env python3
"""Demo: duplicate / concurrent checkout with the same Idempotency-Key.

Part 1: POST twice with the same key + same payload -> both 202, same
        order_id (second is a replay; no new order).
Part 2: POST twice with the same key + DIFFERENT payload -> 409
        IDEMPOTENCY_CONFLICT.
Part 3: N concurrent identical POSTs (same key) -> exactly one order_id
        across all responses (UNIQUE(user_id, idem_key) + IntegrityError
        re-read in domain/checkout.py).

Usage: .venv/bin/python scripts/demo_idempotent_checkout.py [--concurrency 10]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from concurrent.futures import ThreadPoolExecutor

API = os.environ.get("QB_API", "http://127.0.0.1:8000")


def call(method: str, path: str, token: str | None = None,
         body: dict | None = None, headers: dict | None = None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Content-Type": "application/json", **(headers or {})},
    )
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            return resp.status, json.loads(resp.read().decode())
    except urllib.error.HTTPError as e:  # noqa: F821
        return e.code, json.loads(e.read().decode())


def login(email: str, password: str) -> str:
    status, data = call("POST", "/api/v1/auth/login",
                        body={"email": email, "password": password})
    assert status == 200, data
    return data["access_token"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--concurrency", type=int, default=10)
    args = ap.parse_args()

    token = login("aarav@quickbite.test", "customer123")
    _, rests = call("GET", "/api/v1/restaurants", token)
    rest_id = rests["items"][0]["id"]
    _, menu = call("GET", f"/api/v1/restaurants/{rest_id}/menu", token)
    item_id = next(m["id"] for m in menu["items"] if m["is_available"])
    payload = {"restaurant_id": rest_id,
               "delivery_address": "77 Demo Street, Bengaluru",
               "items": [{"menu_item_id": item_id, "quantity": 1}]}

    print("=== part 1: same key, same payload -> replay ===")
    key = str(uuid.uuid4())
    s1, r1 = call("POST", "/api/v1/orders", token, payload,
                  {"Idempotency-Key": key})
    s2, r2 = call("POST", "/api/v1/orders", token, payload,
                  {"Idempotency-Key": key})
    print(f"first:  {s1} order_id={r1['order_id']}")
    print(f"second: {s2} order_id={r2['order_id']}")
    assert s1 == s2 == 202 and r1["order_id"] == r2["order_id"], "replay failed"
    print("OK: identical order_id, no duplicate order created")

    print("=== part 2: same key, different payload -> 409 ===")
    other = dict(payload, delivery_address="999 Other Street, Bengaluru")
    s3, r3 = call("POST", "/api/v1/orders", token, other,
                  {"Idempotency-Key": key})
    print(f"status={s3} code={r3.get('code')}")
    assert s3 == 409 and r3["code"] == "IDEMPOTENCY_CONFLICT", "expected 409"
    print("OK: conflicting reuse rejected")

    print(f"=== part 3: {args.concurrency} concurrent identical POSTs, one key ===")
    race_key = str(uuid.uuid4())

    def one(_):
        return call("POST", "/api/v1/orders", token, payload,
                    {"Idempotency-Key": race_key})

    with ThreadPoolExecutor(max_workers=args.concurrency) as ex:
        results = list(ex.map(one, range(args.concurrency)))
    statuses = {s for s, _ in results}
    order_ids = {r["order_id"] for _, r in results}
    print(f"statuses={sorted(statuses)} distinct_order_ids={len(order_ids)}")
    assert statuses == {202}, f"unexpected statuses: {statuses}"
    assert len(order_ids) == 1, f"duplicate orders created: {order_ids}"
    print(f"OK: exactly one order ({next(iter(order_ids))}) from "
          f"{args.concurrency} concurrent requests")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
