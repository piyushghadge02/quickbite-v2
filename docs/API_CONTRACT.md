# QuickBite v2 — API Contract

Versioned REST API served by the FastAPI `api` service. Base path: `/api/v1`.
Interactive docs: `GET /docs` and `GET /openapi.json` on the API service
(default `http://127.0.0.1:8000`). The machine-readable contract is exported
to [`docs/openapi.json`](openapi.json); regenerate it with:

```bash
QUICKBITE_ENV=dev .venv/bin/python -c "
import json, sys; sys.path.insert(0, '.')
from backend.app.main import app
json.dump(app.openapi(), open('docs/openapi.json', 'w'), indent=2)"
```

## Conventions

| Topic | Contract |
|---|---|
| Money | Integer **minor units** (INR paise). `total_amount_minor: 2900` = INR 29.00. `currency: "INR"`. Client prices are never trusted: checkout totals are computed server-side from menu snapshots. |
| Pagination | Every list returns `{items, page, page_size, total}`. `page >= 1`, `1 <= page_size <= 100` (`MAX_PAGE_SIZE = 100` in `backend/app/api/deps.py`). |
| Timestamps | UTC ISO-8601 with timezone info. |
| Error envelope | `{code, message, details, request_id}` on every error, including Pydantic validation failures (`backend/app/errors.py`). `X-Request-ID` is echoed on every response (client-supplied or generated). |
| Auth | `Authorization: <redacted>` JWT (PyJWT, HS256, configurable expiry, default 60 min). Roles: `customer`, `admin`. `401` unauthenticated, `403` wrong role, `404` unknown order **or another customer's order** (no existence leak). |
| Idempotency | `POST /api/v1/orders` requires an `Idempotency-Key` header (missing → `422 MISSING_IDEMPOTENCY_KEY`). Key is scoped to the authenticated customer (`UNIQUE(user_id, idem_key)`). Same key + same payload → replay of the stored 202 response and `Location`, no new order. Same key + different payload → `409 IDEMPOTENCY_CONFLICT`. Concurrent identical submissions → exactly one order (unique-constraint race → re-read → replay). |
| CORS | Explicit origins only (never `*` with credentials); allowed headers include `Authorization`, `Content-Type`, `Idempotency-Key`, `X-Request-ID`; `Location` and `X-Request-ID` are exposed. |

## Endpoints

### Auth

| Method & path | Auth | Description |
|---|---|---|
| `POST /api/v1/auth/login` | none | Body `{email, password}` → `200 {access_token, token_type: "bearer", expires_at, role, user{id,email,name,role}}`. Bad credentials → `401 INVALID_CREDENTIALS`. |
| `GET /api/v1/me` | bearer | `200 {id, email, name, role, created_at}`. Expired token → `401 TOKEN_EXPIRED`; bad token → `401 INVALID_TOKEN`. |

### Catalog

| Method & path | Auth | Description |
|---|---|---|
| `GET /api/v1/restaurants?page=&page_size=` | bearer | `200` page of `{id, name, address, is_active}`. |
| `GET /api/v1/restaurants/{restaurant_id}/menu?page=&page_size=` | bearer | `200` page of `{id, restaurant_id, name, price_minor, currency, is_available}`. Unknown restaurant → `404 RESTAURANT_NOT_FOUND`. |

### Orders

`POST /api/v1/orders` — customer only. Requires `Idempotency-Key`.

Request:

```json
{
  "restaurant_id": "rest_spice",
  "delivery_address": "12 Lake Road, Bengaluru",
  "items": [
    {"menu_item_id": "item_biryani", "quantity": 2},
    {"menu_item_id": "item_lassi", "quantity": 1}
  ]
}
```

Validation: address ≥ 8 chars; 1–20 distinct items; quantity 1–20; no duplicate
`menu_item_id`; all items must belong to the restaurant and be available.
Server computes `total_minor` from menu prices (e.g. 2×1250 + 400 = 2900).

Response `202 Accepted`, header `Location: /api/v1/orders/{order_id}`:

```json
{
  "order_id": "order_9f2c…",
  "status": "PENDING",
  "currency": "INR",
  "total_amount_minor": 2900,
  "version": 1,
  "message": "Order accepted for asynchronous processing."
}
```

The acceptance transaction commits atomically: order + order items +
initial history row + idempotency record + outbox event
(`backend/app/domain/checkout.py`). If it cannot commit, the API returns an
error, never a 202. An accepted `PENDING` order may be waiting for messaging
recovery — this is by design (see readiness below).

| Method & path | Auth | Description |
|---|---|---|
| `GET /api/v1/orders?status=&page=&page_size=` | customer | `200` page of `{id, restaurant_id, currency, total_minor, status, version, created_at, updated_at}` for the caller's own orders. |
| `GET /api/v1/orders/{order_id}` | owner-or-admin | `200` full order: `{id, customer_id, restaurant_id, delivery_address, currency, total_minor, status, version, failure_code, driver_id, driver_name, created_at, updated_at, items[]}`. Items: `{menu_item_id, item_name, quantity, unit_price_minor}` (server-priced snapshot). |
| `GET /api/v1/orders/{order_id}/history` | owner-or-admin | `200` list of `{from_status, to_status, version, note, created_at}` — the full state-machine audit trail. |
| `GET /api/v1/orders/{order_id}/notifications` | owner-or-admin | `200` page of `{id, event_id, event_type, order_id, title, body, created_at}` — persisted notification feed. |

### Admin

| Method & path | Auth | Description |
|---|---|---|
| `GET /api/v1/admin/orders?status=&page=&page_size=` | admin | `200` page of orders across all customers (same shape as customer list). Customer token → `403 FORBIDDEN`. |
| `GET /api/v1/admin/summary` | admin | `200 {orders_by_status, outbox_pending, outbox_scheduled, retries_scheduled, quarantine_total}` — the pipeline observability endpoint used by the load test and demos. |

### Health

| Method & path | Auth | Description |
|---|---|---|
| `GET /health/live` | none | `200 {status: "ok"}` — process liveness only. |
| `GET /health/ready` | none | `200 {status: "ready", details: {database, broker, elapsed_s}}` when PostgreSQL and RabbitMQ both answer within bounded timeouts (`READY_DB_TIMEOUT_S` / `READY_AMQP_TIMEOUT_S`); otherwise `503 {status: "not_ready", details}`. Readiness distinguishes "API can accept work" (DB ok) from "pipeline fully draining" (broker ok): checkout stays available during a broker outage because the outbox holds the event. |

## Status codes used

`200` reads, `202` checkout accepted, `401` unauthenticated (`UNAUTHENTICATED`,
`TOKEN_EXPIRED`, `INVALID_TOKEN`, `INVALID_CREDENTIALS`), `403` wrong role
(`FORBIDDEN`), `404` unknown / not-visible resource (`ORDER_NOT_FOUND`,
`RESTAURANT_NOT_FOUND`), `409` idempotency conflict (`IDEMPOTENCY_CONFLICT`),
`422` invalid input (`MISSING_IDEMPOTENCY_KEY`, `INVALID_ADDRESS`,
`EMPTY_CART`, `TOO_MANY_ITEMS`, `INVALID_ITEM`, `DUPLICATE_ITEM`,
`MIXED_RESTAURANT`, `ITEM_UNAVAILABLE`, `INVALID_TOTAL`, `INVALID_PAGE`,
`INVALID_PAGE_SIZE`, `VALIDATION_ERROR`), `500` unexpected (`INTERNAL_ERROR`,
logged server-side with the request id).

## Event schema (for consumers)

Every domain event published to RabbitMQ carries
`{event_id, schema_version, event_type, order_id, order_version, occurred_at,
correlation_id, causation_id, data}` (`backend/app/messaging/envelope.py`).
`event_id` is the stable identity across retries (also the AMQP
`message_id`); the retry attempt counter travels in AMQP headers, never as a
new identity. Event types: `order.created`, `order.paid`,
`order.payment.failed`, `order.confirmed`, `order.driver.assigned`,
`order.failed`.

## Order state machine

`PENDING → PAID → CONFIRMED → DRIVER_ASSIGNED` (success, terminal) ·
`PENDING → PAYMENT_FAILED` (terminal) · `PAID → FAILED`, `CONFIRMED → FAILED`
(terminal). No backward transitions; terminal states are final; transient
failures keep the last successful state; notification failures never change
order status (`backend/app/domain/state_machine.py`).
