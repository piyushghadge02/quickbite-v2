# QuickBite v2 — Engineering Report

Every claim below is grounded in the shipped code (file references inline).
Anything not yet measured is marked **PENDING** — never presented as done.

## 1. Retry safety

**Bounded, delayed, never tight loops.** The policy is 1 initial attempt + 3
delayed retries, configured by `RETRY_DELAYS_S` (default `"2,10,30"`,
parsed in `backend/app/config.py`; `max_attempts = 1 + len(retry_delays_s)`).
`Worker._schedule_retry` (`workers/base.py`) computes
`delay = retry_delays_s[next_attempt - 2]` and persists, **in the same rolled-back-then-new
transaction as the failure handling**, a `retry_jobs` row plus a targeted
outbox publication. When `next_attempt > max_attempts` it returns `False`
and the caller quarantines instead — retries cannot run forever.

**Targeted redelivery, not re-fan-out.** The retry publication uses the
default exchange (`exchange=""`) with `routing_key=<failing queue name>`, so
the redelivery goes straight to the failing consumer's queue. The retry
scheduler (`workers/retry_scheduler.py`) flips due rows `scheduled → pending`
and the outbox dispatcher publishes them; the event never re-enters the
`quickbite.orders` topic exchange, so unrelated subscribers never see a retry
(the scheduler's docstring states this invariant explicitly).

**Stable identity across attempts.** `message_id == event_id` on every
publication (`topology.amqp_message`; `outbox.publish_confirmed`); the attempt
counter travels in AMQP headers (`_headers: {"attempt": n}`), never as a new
domain-event identity. `UNIQUE(consumer_name, event_id, attempt)` on
`retry_jobs` prevents double-scheduling a retry. The outbox publication
identity is `UNIQUE(event_id, exchange, routing_key, attempt)` (migration
`a3ad56353a32`): the `event_id` is preserved across redelivery per the
assignment, while the durable attempt counter keeps each retry a distinct
outbox row — without it, scheduling attempt N+1 collides with attempt N's
row and the retry cycle stalls (found during integration testing).
`retry_jobs` and the `IntegrityError` catch in `_handle_transient` make a
racing double-schedule collapse to one.

**No tight nack/requeue loops, ever.** Three distinct paths in `workers/base.py`:
1. *Transient business failure* → roll back, atomically persist the retry
   schedule, then **ack** the original message. The redelivery arrives later
   via the outbox, with a delay.
2. *Terminal outcome / exhaustion* → quarantine + terminal transition + ack.
3. *Business-transaction failure* (could not even schedule a retry) → **do not
   ack**, close the channel, reconnect with backoff. The broker redelivers
   after reconnect — a delayed redelivery, not a spin loop.

**Retry timing evidence:** `scripts/demo_fail_twice_then_succeed.sh`
(`PAYMENT_SIM_MODE=fail-twice-then-succeed`) shows attempts landing ~2 s and
~10 s apart via the admin summary's `retries_scheduled`/`outbox_scheduled`
counters.

## 2. Deduplication

Duplicates are expected (at-least-once delivery, crash-after-publish, manual
redelivery). Each layer collapses them independently:

| Layer | Mechanism | Code |
|---|---|---|
| Consumer dedup | `processed_events` `UNIQUE(consumer_name, event_id)`; `_already_processed` → ack without effects | `workers/base.py`, `models.py` (`uq_processed_consumer_event`) |
| Checkout idempotency | `idempotency_records` `UNIQUE(user_id, idem_key)` + canonical request hash (`sha256` of sorted JSON). Same key+payload → replay stored 202; same key+other payload → `409`; concurrent race → `IntegrityError` → re-read winner → replay | `backend/app/domain/checkout.py` (`uq_idempotency_user_key`) |
| Notifications | `UNIQUE(customer_id, event_id)`; `IntegrityError` → rollback → `OK` ("already persisted") | `workers/notification_worker.py` (`uq_notification_customer_event`) |
| Driver assignment | `driver_assignments.order_id` `UNIQUE`; loser of a race re-reads the winner's assignment | `workers/delivery_worker.py` |
| State guards | Workers no-op when the order already moved past their stage (`order already PAID`, etc.); `state_machine.apply_transition` rejects illegal transitions with `ValueError` | `workers/*_worker.py`, `backend/app/domain/state_machine.py` |
| Outbox publication identity | `UNIQUE(event_id, exchange, routing_key)` — the same logical event may be published to several destinations, but never twice to the same one | `models.py` (`uq_outbox_publication`) |

**Exactly-once is never claimed.** The guarantee is at-least-once delivery
with single committed business effects.

## 3. Outbox recovery

* **Atomic accept.** `POST /api/v1/orders` commits order + items + history +
  idempotency record + outbox event in one PostgreSQL transaction
  (`checkout()`). The broker is never touched in the request path, so a broker
  outage cannot lose an accepted order — `scripts/demo_broker_stop_outbox.sh`
  proves it: 202 while RabbitMQ is stopped, then eventual completion after
  restart.
* **Safe multi-dispatcher claims.** `claim_due` uses
  `SELECT … FOR UPDATE SKIP LOCKED` plus a claim lease
  (`OUTBOX_CLAIM_LEASE_S`, default 300 s); a crashed dispatcher's `inflight`
  rows become claimable after the lease expires (`backend/app/messaging/outbox.py`).
* **Confirms mean routed.** The dispatcher enables publisher confirms and
  publishes with `mandatory=True`; a row is marked `sent` only after a confirm
  arrives with no basic-return. An unroutable message raises and is *not*
  marked sent — a confirm alone is not treated as proof of a binding. Publish
  failures keep the row `pending` with `available_at` pushed out by
  `min(2^attempts, 60)` seconds.
* **Crash after publish, before mark-sent.** This window can duplicate a
  message; the docstring in `outbox.py` calls it out explicitly and relies on
  consumer idempotency (Section 2) instead of pretending it cannot happen.
* **Crash injection for the ack boundary.** `PAYMENT_SIM_MODE=crash-after-checkpoint`
  with `PAYMENT_CRASH_POINT=before-tx | after-commit | before-ack` kills the
  worker via `os._exit(1)` at the chosen point
  (`workers/payment_worker.py`). `scripts/demo_kill_worker_recovery.sh`
  exercises it: after `after-commit`, the committed PAID transition + payment
  row + child outbox event are durable, and the redelivery is a safe no-op
  via the state check — exactly one payment row and one history entry.
* **Readiness honesty.** `/health/ready` reports `database` and `broker`
  separately with bounded timeouts; checkout stays 202-capable during a
  broker outage because the outbox holds the event (documented in
  `backend/app/api/routes/health.py` and `docs/API_CONTRACT.md`).

## 4. Security choices

* **Passwords:** bcrypt via `backend/app/security.py`, with a 72-byte cap
  (`hash_password` rejects longer inputs — bcrypt's silent-truncation
  footgun). Seed passwords are hashed at seed time; no plaintext secrets in
  the repo (only `.env.example` placeholders). Nothing in the codebase logs
  tokens, passwords, or full delivery addresses.
* **Tokens:** PyJWT, HS256, `exp`/`iat` claims, `sub`+`role` required by
  `decode_access_token`; expired → `401 TOKEN_EXPIRED`, invalid →
  `401 INVALID_TOKEN`. `settings.validate()` refuses to boot in
  `QUICKBITE_ENV=prod` with the insecure default `JWT_SECRET`.
* **RBAC + ownership:** `require_customer` / `require_admin` dependencies;
  `get_visible_order` returns `404` for other customers' orders (no existence
  leak) while admins see everything (`backend/app/api/deps.py`).
* **CORS:** explicit origins from `CORS_ORIGINS` (never `*` with
  credentials); required headers (`Authorization`, `Content-Type`,
  `Idempotency-Key`, `X-Request-ID`) permitted; `Location`/`X-Request-ID`
  exposed (`backend/app/main.py`).
* **Failure injection is env-only.** `PAYMENT_SIM_MODE`,
  `*_FAIL_MODE`, `SIM_*_DELAY_S` are read from environment; there is no API
  field or checkout parameter that can select them (stated in the payment
  worker's docstring). They are dev/test/demo tools, not production knobs.
* **Error envelope:** `{code, message, details, request_id}` on all errors
  including Pydantic 422s; unexpected exceptions log server-side with the
  request id and return a generic `500 INTERNAL_ERROR` — no stack traces or
  internals leak (`backend/app/errors.py`).

## 5. Scaling

* **Workers are stateless** apart from PostgreSQL + RabbitMQ, so any worker
  type scales horizontally: `docker compose up -d --scale payment-worker=3`
  (no `container_name`, no worker host ports — see `compose.yaml`). Claims
  (`SKIP LOCKED`), idempotency, and `UNIQUE` constraints make concurrent
  workers safe; the delivery worker's driver-pick race is resolved by
  re-reading the winner (`delivery_worker.py`).
* **Backpressure:** `PREFETCH_COUNT` (default 10) bounds unacked messages per
  worker (`channel.set_qos`); the dispatcher uses prefetch 1.
* **Outbox scales too:** the dispatcher claim protocol is safe for N
  instances (Section 3).
* **Measured scaling: PENDING.** `scripts/load_test.py` reports per-order
  create latency (p50/p95), orders/sec, and drain behavior, and labels runs
  with `--workers 1|3` for the comparison in §17. No numbers are claimed
  here — the coordinator records real results in Phase 9.

## 6. Limitations (honest)

* At-least-once delivery; exactly-once is not claimed and not achievable with
  this design.
* Single RabbitMQ node in compose (no quorum queues / clustering); broker
  loss during the crash window can duplicate or delay — both handled, neither
  hidden.
* No TLS in the compose stack (plain HTTP/AMQP on loopback); terminate TLS at
  a reverse proxy for anything beyond local demo.
* "Notifications" are a persisted in-app feed (`GET …/notifications`), not
  real push/email/SMS (an assignment §19 extension).
* Payment, restaurant acceptance, and driver assignment are **simulated**;
  failure modes are deterministic test hooks, not integrations.
* Retry schedule is fixed (`2,10,30` s) rather than exponential-with-jitter;
  outbox publish failures use `min(2^attempts, 60)` s backoff.
* Idempotency records are retained for the assignment lifetime; a production
  design needs a documented TTL/compaction policy.
* A crashed outbox dispatcher's `inflight` rows wait up to the 300 s claim
  lease before another dispatcher re-claims them.
* `/api/v1/admin/summary` is point-in-time polling; there is no metrics
  pipeline (Prometheus/Grafana is a §19 extension).
* Quarantine has no replay API (a §19 extension: replay must not double-charge
  or regress terminal state).
* iOS target: cannot be built or executed on this Linux VM — must be reported
  separately, never claimed.
