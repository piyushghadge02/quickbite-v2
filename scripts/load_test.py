#!/usr/bin/env python3
"""QuickBite v2 load test: place N orders, measure checkout latency.

What it does:
  1. Logs in as the seed customer (aarav@quickbite.test).
  2. Fetches one restaurant + one available menu item.
  3. Places --orders orders (default 100) with --concurrency in flight,
     each with a fresh Idempotency-Key. Requires PAYMENT_SIM_MODE=succeed
     on the payment worker(s) so the pipeline drains.
  4. Reports per-order create latency (p50/p95), total time, orders/sec.
  5. Polls GET /api/v1/admin/summary (seed admin) until the pipeline
     drains (outbox_pending == 0 and no PENDING/PAID/CONFIRMED orders left)
     or --drain-timeout-s elapses.

What it does NOT measure: end-to-end pipeline latency per order (that is a
separate concern; see --drain-wait). Create latency measures the API accept
path only: validation + one PostgreSQL transaction (order + items +
history + idempotency + outbox row).

Scaling comparison: run once with 1 payment worker, then:
    docker compose up -d --scale payment-worker=3
and re-run with --workers 3. The flag only labels the report; scaling is
done by you via compose.

Usage:
    .venv/bin/python scripts/load_test.py [--orders 100] [--concurrency 10]
        [--base-url http://127.0.0.1:8000] [--workers 1|3]
"""
from __future__ import annotations

import argparse
import asyncio
import os
import platform
import statistics
import sys
import time
import uuid

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import httpx  # noqa: E402  (pinned in requirements.txt)

CUSTOMER_EMAIL = "aarav@quickbite.test"
CUSTOMER_PASSWORD = "customer123"
ADMIN_EMAIL = "admin@quickbite.test"
ADMIN_PASSWORD = "admin123"
TERMINAL_STATES = {"DRIVER_ASSIGNED", "PAYMENT_FAILED", "FAILED"}


def percentile(data: list[float], q: float) -> float:
    if not data:
        return 0.0
    s = sorted(data)
    k = (len(s) - 1) * (q / 100)
    f = int(k)
    c = min(f + 1, len(s) - 1)
    return s[f] + (s[c] - s[f]) * (k - f)


async def login(client: httpx.AsyncClient, email: str, password: str) -> str:
    r = await client.post("/api/v1/auth/login",
                          json={"email": email, "password": password})
    r.raise_for_status()
    return r.json()["access_token"]


async def pick_menu_item(client: httpx.AsyncClient, token: str) -> tuple[str, str]:
    headers = {"Authorization": f"Bearer {token}"}
    r = await client.get("/api/v1/restaurants", headers=headers)
    r.raise_for_status()
    restaurants = r.json()["items"]
    if not restaurants:
        raise SystemExit("no restaurants seeded — run scripts/seed.py first")
    rest_id = restaurants[0]["id"]
    r = await client.get(f"/api/v1/restaurants/{rest_id}/menu", headers=headers)
    r.raise_for_status()
    items = [m for m in r.json()["items"] if m["is_available"]]
    if not items:
        raise SystemExit("no available menu items — run scripts/seed.py first")
    return rest_id, items[0]["id"]


async def place_one(client: httpx.AsyncClient, token: str, rest_id: str,
                    item_id: str, sem: asyncio.Semaphore) -> tuple[float, str]:
    async with sem:
        headers = {"Authorization": f"Bearer {token}",
                   "Idempotency-Key": str(uuid.uuid4())}
        body = {"restaurant_id": rest_id,
                "delivery_address": "221 Load Test Avenue, Bengaluru",
                "items": [{"menu_item_id": item_id, "quantity": 1}]}
        t0 = time.perf_counter()
        r = await client.post("/api/v1/orders", json=body, headers=headers)
        dt = (time.perf_counter() - t0) * 1000
        r.raise_for_status()
        return dt, r.json()["order_id"]


async def drain_wait(client: httpx.AsyncClient, admin_token: str,
                     timeout_s: float) -> dict:
    """Poll admin summary until the pipeline drains or timeout."""
    headers = {"Authorization": f"Bearer {admin_token}"}
    deadline = time.monotonic() + timeout_s
    last: dict = {}
    while time.monotonic() < deadline:
        r = await client.get("/api/v1/admin/summary", headers=headers)
        r.raise_for_status()
        last = r.json()
        pending_states = sum(
            n for s, n in last["orders_by_status"].items() if s not in TERMINAL_STATES
        )
        if last["outbox_pending"] == 0 and pending_states == 0:
            return last
        await asyncio.sleep(2.0)
    return last


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--orders", type=int, default=100)
    ap.add_argument("--concurrency", type=int, default=10)
    ap.add_argument("--base-url", default="http://127.0.0.1:8000")
    ap.add_argument("--workers", type=int, choices=(1, 3), default=1,
                    help="label only: how many payment workers YOU scaled to")
    ap.add_argument("--drain-timeout-s", type=float, default=180.0)
    ap.add_argument("--no-drain-wait", action="store_true")
    args = ap.parse_args()

    limits = httpx.Limits(max_connections=args.concurrency * 2)
    async with httpx.AsyncClient(base_url=args.base_url, timeout=30.0,
                                 limits=limits) as client:
        token = await login(client, CUSTOMER_EMAIL, CUSTOMER_PASSWORD)
        admin_token = await login(client, ADMIN_EMAIL, ADMIN_PASSWORD)
        rest_id, item_id = await pick_menu_item(client, token)

        sem = asyncio.Semaphore(args.concurrency)
        t0 = time.perf_counter()
        results = await asyncio.gather(*[
            place_one(client, token, rest_id, item_id, sem)
            for _ in range(args.orders)
        ])
        total_s = time.perf_counter() - t0

        lat = [d for d, _ in results]
        print("=" * 64)
        print("QuickBite v2 load test — checkout accept path")
        print("=" * 64)
        print(f"machine        : {platform.platform()} / {platform.machine()} / "
              f"cpus={os.cpu_count()} / python={platform.python_version()}")
        print(f"orders         : {args.orders}")
        print(f"concurrency    : {args.concurrency}")
        print(f"payment workers: {args.workers} (label — scale via "
              "`docker compose up -d --scale payment-worker=N`)")
        print(f"base URL       : {args.base_url}")
        print("-" * 64)
        print(f"total time     : {total_s:.2f} s")
        print(f"throughput     : {args.orders / total_s:.1f} orders/s")
        print(f"create latency : p50={percentile(lat, 50):.1f} ms  "
              f"p95={percentile(lat, 95):.1f} ms  "
              f"max={max(lat):.1f} ms")
        print("-" * 64)
        print("NOTE: create latency = API accept path only (validation + one")
        print("PostgreSQL tx). End-to-end pipeline time is tracked via drain wait.")

        if args.no_drain_wait:
            return 0
        print("waiting for pipeline drain ...")
        summary = await drain_wait(client, admin_token, args.drain_timeout_s)
        by_status = summary.get("orders_by_status", {})
        drained = (summary.get("outbox_pending", -1) == 0
                   and all(s in TERMINAL_STATES for s in by_status))
        print(f"drained        : {drained}")
        print(f"orders_by_status: {by_status}")
        print(f"outbox_pending : {summary.get('outbox_pending')}")
        print(f"outbox_scheduled: {summary.get('outbox_scheduled')}")
        print(f"retries_sched  : {summary.get('retries_scheduled')}")
        print(f"quarantine     : {summary.get('quarantine_total')}")
        if not drained:
            print("WARNING: pipeline did not fully drain within the timeout.")
            print("Check PAYMENT_SIM_MODE=succeed and that all workers are running.")
            return 2
        return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
