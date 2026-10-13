# QuickBite v2.0 — Implementation Plan

Source of truth: `QuickBite - Revised Full-Stack Assignment.pdf` v2.0 (12 Oct 2026), 21 sections.
Reference (READ-ONLY, never modify): `~/workspace/quickbite-build/quickbite-order-system/` (v1: FastAPI + SQLite + aio-pika + 4 workers, 25 tests, docs, docker-compose.yml).

## 1. Repository audit of v1 (`quickbite-order-system/`)

**Real entry points / capabilities:**
- `app/main.py` (178 lines): FastAPI app, endpoints `POST /orders` (201), `GET /orders/{id}`, `GET /health`; direct `rabbitmq.publish()` inside the request handler (no outbox).
- `app/models.py` (61): SQLAlchemy models — `Order`, `Notification`, `ProcessedEvent` only. No users, restaurants, menu_items, order_items, order_status_history, payments, driver_assignments, outbox_events, retry_jobs, quarantine_records.
- `app/config.py`: SQLite DB (`sqlite:///./quickbite.db`, WAL), `quickbite.orders` topic exchange, `quickbite.dlx` direct exchange (NOTE: v2 requires dead exchange name `quickbite.dead` and queue `orders.dead-letter.queue` bound with key `failed` — v1 differs).
- `app/events.py` (39): event envelope — needs to be checked for `event_id/schema_version/correlation_id/causation_id`; likely incomplete.
- `app/rabbitmq.py` (93): topology declaration + publisher; workers in `workers/base.py` (207) + 4 concrete workers (payment w/ PAYMENT_FAIL_MODE, restaurant, delivery, notification with dedup via unique constraint).
- Tests (3 files, 25 tests): API, topology, workers — all against SQLite + (probably) mocked or local broker.
- Docs: ARCHITECTURE.md, DEMO.md, REPORT.md, API_EXAMPLES.md, architecture.png (regenerate for v2).
- `docker-compose.yml` + `Dockerfile`, `.env.example`, `requirements.txt` (unpinned).
- No git repository.

**Requirement gaps (PDF v2.0 vs v1):**
1. **No Flutter frontend at all** — and therefore no cream/orange theme, no screens, no idempotency-key persistence, no polling. The prompt's "preserve cream/orange theme" has nothing to preserve; the theme must be created from scratch (documented in TRACEABILITY).
2. No authentication (no users, no JWT, no RBAC), no `/api/v1` prefix, no pagination envelope, no error envelope `{code,message,details,request_id}`.
3. No PostgreSQL / Alembic; SQLite is the authoritative store (v2 requires PG).
4. No transactional outbox; API publishes to broker inline in the request path (loses events on broker outage; API latency tied to broker).
5. No idempotency-key handling on checkout; no canonical request hash.
6. Event envelope lacks `schema_version/correlation_id/causation_id` (verify); dead exchange named `quickbite.dlx` instead of `quickbite.dead`.
7. No bounded retries (retries are immediate requeue via aio-pika? verify), no retry_jobs table, no retry scheduler, no targeted redelivery via default exchange, no quarantine_records, no `orders.dead-letter.queue` bound to `quickbite.dead` with key `failed`.
8. No state machine enforcement (version/compare-and-set), no order_status_history, no failure_code, no terminal-state semantics.
9. Notification binding in v1 — check whether `order.*` or `order.#` (PDF §20 correction: must be `order.#`).
10. No health/readiness semantics (`/health/live`, `/health/ready` with bounded dependency checks + 503).
11. No seeded users/restaurants/menus/drivers; no scripts/seed.py; no load test; no failure demo scripts.
12. Unpinned dependencies, no lockfile; compose file is v1's `docker-compose.yml` (v2 expects `compose.yaml` with pinned tags, healthchecks, no fixed container_name).

**Reusable from v1 (adapt, do not copy blindly):**
- aio-pika publisher confirms pattern; worker base loop skeleton (manual acks, prefetch, reconnect backoff); payment failure-mode idea (extend to 4 deterministic modes + crash-after-checkpoint); notification dedup via DB unique constraint; domain event type names.

## 2. Phased build plan (single execution)

- **Phase 0 — Environment (parallel with coding):** apt postgres-16 + rabbitmq-server (running); initdb in `~/workspace/quickbite-build/pgdata` as non-root user on 127.0.0.1:5432, role+db `quickbite`; RabbitMQ data under `~/workspace/quickbite-build/rabbitmq-data`, management plugin, ports 5672/15672; `.venv` + pinned deps + requirements.txt/lock; Flutter SDK download (~1h, background).
- **Phase 1 — This document** (audit + plan). Done after writing.
- **Phase 2 — Backend foundation + PostgreSQL:** `backend/app/{config,database,security,models,schemas,domain,api,messaging}`, Alembic env + initial migration (all 14 tables), `scripts/seed.py` (fictional users incl. admin, restaurants, menus, drivers; bcrypt hashes), error envelope middleware, request-id, CORS.
- **Phase 3 — Versioned REST API:** all `/api/v1` routes + `/health/*`; server-side totals; idempotency endpoint semantics; pagination; JWT auth + RBAC; OpenAPI export → `docs/openapi.json` + `docs/API_CONTRACT.md`.
- **Phase 4 — Checkout idempotency + transactional outbox:** `Idempotency-Key` required; canonical hash UNIQUE(user,key,hash); 409 on conflict; replay; outbox_events table; single-tx accept; outbox dispatcher (SKIP LOCKED, confirms + mandatory, mark-sent only on confirm w/o return).
- **Phase 5 — Topology + reliable workers:** declare durable topic exchange + 4 queues/bindings (`order.#` for notifications), `quickbite.dead` direct + `orders.dead-letter.queue` (key `failed`); envelope validation; `(consumer_name,event_id)` dedup; state/version guarded transitions; terminal events; failure injection via config only.
- **Phase 6 — Bounded retries + quarantine + scheduler:** retry_jobs + retry scheduler; targeted redelivery via default exchange to failing queue; attempt counter; quarantine_records + publish to `quickbite.dead`; worker-kill recovery semantics (no ack on tx failure).
- **Phase 7 — Flutter app** (`frontend/`): all §5 screens, cream/orange theme, Riverpod, ApiClient, typed models, shared_preferences idempotency persistence, flutter_secure_storage behind platform adapter, LayoutBuilder phone/desktop, a11y, widget tests + integration_test; `flutter analyze` + `flutter test` + `flutter build web`.
- **Phase 8 — Docker/compose + scripts:** `compose.yaml` (pinned tags, healthchecks, named volumes, no fixed names/ports), Dockerfiles, nginx SPA web host, `scripts/load_test.py`, failure/demo scripts.
- **Phase 9 — Tests + acceptance:** pytest suite on real PG + real RabbitMQ (contract, auth/RBAC, idempotency incl. concurrency, outbox atomicity, state machine, dedup, retries, quarantine, notification isolation); §14 acceptance checklist as far as VM allows (worker-kill recovery, broker-stop outbox recovery, notification backlog drain, 1-vs-3 payment workers); real numbers only.
- **Phase 10 — Docs + traceability:** README, API_CONTRACT (+openapi.json), ARCHITECTURE.md + generated PNG, ENGINEERING_REPORT, DEMO, TRACEABILITY (every PDF requirement → PASS/PARTIAL/FAIL/BLOCKED with evidence).

**Delegation:** backend+workers+migrations+tests stay with coordinator; Flutter app and docs/scripts/compose go to child agents with self-contained briefs.

## 3. Non-negotiable invariants
- Never fabricate test results; BLOCKED items carry exact remaining action.
- No secrets in repo; only `.env.example` placeholders; fictional seed data.
- No git init/commit/push. Do not modify `quickbite-order-system/`.
- iOS: impossible here (no macOS) — label PENDING, never claim.
- Worker kill tests, broker-stop tests: run live on the VM; record real outcomes.
