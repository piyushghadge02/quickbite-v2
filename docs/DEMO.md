# QuickBite v2 — Demo Script

Reproduces **every sequence in assignment §17** from a clean checkout.
Backend/API demos run against the compose stack (or the host-local VM
setup); Flutter UI steps are marked — the Flutter track owns those screens.

**Prerequisites** (see [README.md](README.md) for full setup):

```bash
export TMPDIR=~/workspace/quickbite-build/piptmp   # host /tmp is a tiny tmpfs
cp .env.example .env                                # edit secrets
docker compose build
docker compose up -d postgres rabbitmq
docker compose exec api alembic -c migrations/alembic.ini upgrade head
docker compose exec api python scripts/seed.py
docker compose up -d
```

Test accounts (fictional seed data): `admin@quickbite.test` / `admin123`,
`aarav@quickbite.test` / `customer123`, `diya@quickbite.test` / `customer123`.
RabbitMQ management: http://localhost:15672.

## 1. Start the stack, sign in, browse the menu (§17-1)

```bash
docker compose ps                       # all services "healthy"/"running"
curl -s http://127.0.0.1:8000/health/ready
```

*Flutter (frontend track):* open the web build at http://localhost:8080,
sign in as `aarav@quickbite.test` / `customer123`, browse the seeded
restaurants and menus (Spice Symphony, Dragon Wok, Crust & Co.).

## 2. Place an order: 202, transitions, notifications, history (§17-2)

```bash
source scripts/demo_lib.sh
CTOK=$(qb_login aarav@quickbite.test customer123)
read -r REST ITEM <<< "$(qb_menu_item "$CTOK")"
time OID=$(qb_post_order "$CTOK" "$REST" "$ITEM")   # expect 202 in milliseconds
echo "order=$OID"
watch -n 2 "qb_order_status $CTOK $OID"              # PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED
qb_order_history "$CTOK" "$OID"                     # full audit trail
qb_notifications "$CTOK" "$OID"                    # persisted notification feed
```

Show: the `202` returns in milliseconds (the broker is never in the request
path); the order then walks the state machine; each transition emits a
notification visible in the feed.

## 3. Idempotent checkout (§17-3)

```bash
.venv/bin/python scripts/demo_idempotent_checkout.py --concurrency 10
```

Expected output: same key + same payload → both `202`, identical `order_id`
(replay, no new order); same key + different payload → `409
IDEMPOTENCY_CONFLICT`; 10 concurrent identical POSTs → exactly one
`order_id`. Ground truth: `UNIQUE(user_id, idem_key)` + canonical request
hash in `backend/app/domain/checkout.py`.

## 4. Notification outage: backlog, unaffected orders, drain (§17-4)

```bash
bash scripts/demo_notification_backlog.sh
```

Stops `notification-worker`, places 3 orders, shows `notification.queue`
depth > 0 in the management UI while every order still reaches
`DRIVER_ASSIGNED` (notification failures never change order status), then
restarts the worker and shows the queue draining to 0 with all notifications
persisted.

## 5. Payment retries and exhaustion (§17-5)

```bash
bash scripts/demo_fail_twice_then_succeed.sh
```

`PAYMENT_SIM_MODE=fail-twice-then-succeed`: attempts 1–2 fail transiently,
attempt 3 succeeds. Watch `GET /api/v1/admin/summary` —
`retries_scheduled`/`outbox_scheduled` rise and fall at the ~2 s / ~10 s
retry marks; the order ends `DRIVER_ASSIGNED`.

```bash
bash scripts/demo_always_fail.sh
```

`PAYMENT_SIM_MODE=always-fail`: 1 attempt + 3 retries exhaust → order goes
`PENDING → PAYMENT_FAILED` (terminal), `order.payment.failed` is emitted,
`quarantine_total` in the admin summary increments, and a message lands in
`orders.dead-letter.queue` (check http://localhost:15672 → Queues).

*Flutter:* the order detail screen shows the terminal failure state with the
`failure_code`; history shows the transition trail.

## 6. Kill a worker at the transaction/ack boundary (§17-6)

```bash
bash scripts/demo_kill_worker_recovery.sh [before-tx|after-commit|before-ack]
```

`PAYMENT_SIM_MODE=crash-after-checkpoint` kills the payment worker with
`os._exit(1)` at the chosen point (default `after-commit`: commit durable,
die before ack). Compose (`restart: unless-stopped`) brings the worker back;
the redelivered message is a safe no-op because the order is already `PAID`
and `processed_events` dedupes. Verify uniqueness: the order history shows
exactly one `PENDING → PAID` entry, and the order completes to
`DRIVER_ASSIGNED` with a single driver assignment.

## 7. Broker outage: outbox holds the order (§17-7)

```bash
bash scripts/demo_broker_stop_outbox.sh
```

Stops `rabbitmq` while postgres + api stay up: `POST /orders` still returns
`202` (acceptance is a pure PostgreSQL transaction; `/health/ready` reports
`not_ready` with `broker` failing but the API keeps accepting). The outbox
row sits `pending`. Restart the broker → the dispatcher publishes → the
order flows to `DRIVER_ASSIGNED`. No event is lost.

## 8. One vs three payment workers (§17-8)

```bash
# baseline: 1 payment worker
.venv/bin/python scripts/load_test.py --orders 100 --concurrency 10 --workers 1 | tee /tmp/load_w1.txt

# scale up
docker compose up -d --scale payment-worker=3
docker compose ps payment-worker   # 3 running
.venv/bin/python scripts/load_test.py --orders 100 --concurrency 10 --workers 3 | tee /tmp/load_w3.txt

# scale back down
docker compose up -d --scale payment-worker=1
diff /tmp/load_w1.txt /tmp/load_w3.txt
```

Report the measured create-latency p50/p95, orders/sec, and drain behavior
from both runs. Requires `PAYMENT_SIM_MODE=succeed` so the pipeline drains.
(Numbers are recorded by the coordinator in Phase 9 — no figures are claimed
here.)

## 9. Customer flow on web, Android, iOS (§17-9)

*Flutter track.* Web: http://localhost:8080. Android: emulator with
`--dart-define=API_BASE_URL=http://10.0.2.2:8000` (emulator loopback to the
host). iOS simulator: `http://localhost:8000`. Show the common flow
(sign in → browse → checkout → track → notifications) on each, including a
narrow phone layout and a safe network retry (failed request → retry button,
no duplicate order thanks to the persisted `Idempotency-Key`).

> iOS execution cannot be done on this Linux VM (no macOS toolchain) — the
> Flutter track reports it separately as PENDING, never as done.

## 10. Admin overview and RBAC denial (§17-10)

```bash
source scripts/demo_lib.sh
ATOK=$(qb_login admin@quickbite.test admin123)
CTOK=$(qb_login aarav@quickbite.test customer123)

# cross-customer overview (place orders as both customers first, or use existing)
curl -s "$QB_API/api/v1/admin/orders?status=DRIVER_ASSIGNED" \
  -H "Authorization: Bearer $ATOK" | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print('total', d['total'])"
curl -s "$QB_API/api/v1/admin/summary" -H "Authorization: Bearer $ATOK"

# the same endpoints as a customer -> 403
curl -s -o /dev/null -w "%{http_code}\n" "$QB_API/api/v1/admin/summary" \
  -H "Authorization: Bearer $CTOK"     # expect 403
curl -s "$QB_API/api/v1/admin/summary" -H "Authorization: Bearer $CTOK" \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['code'])"  # FORBIDDEN
```

*Flutter:* sign in as admin to see the cross-customer order list; sign in as
a customer and confirm admin screens/routes are unreachable.

## Quick reference: all demo entry points

| Demo | Command |
|---|---|
| Idempotent checkout (replay / 409 / concurrent race) | `.venv/bin/python scripts/demo_idempotent_checkout.py` |
| Fail-twice-then-succeed | `bash scripts/demo_fail_twice_then_succeed.sh` |
| Always-fail → quarantine | `bash scripts/demo_always_fail.sh` |
| Worker kill at tx/ack boundary | `bash scripts/demo_kill_worker_recovery.sh [point]` |
| Broker-stop outbox recovery | `bash scripts/demo_broker_stop_outbox.sh` |
| Notification backlog drain | `bash scripts/demo_notification_backlog.sh` |
| Load test (1 vs 3 workers) | `.venv/bin/python scripts/load_test.py --workers 1\|3` |

Each script prints the exact commands it runs as it goes, so the demo can be
narrated live or followed step-by-step from the terminal output.
