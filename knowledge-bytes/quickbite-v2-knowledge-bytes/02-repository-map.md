# Byte 2: How the repository is organized

**Builds on:** Byte 1

## In plain terms
The repository separates user interface, API, background processing, database changes, infrastructure, and tests. This makes each responsibility easier to run and review.

## Important paths
- `frontend/lib/screens/restaurant_list_screen.dart` — restaurant browsing UI.
- `frontend/lib/screens/menu_screen.dart` — menu display and add-to-cart flow.
- `frontend/lib/screens/cart_screen.dart` — cart review and next checkout step.
- `frontend/lib/config/app_config.dart` — API base URL configuration.
- `backend/app/models.py` — backend data models.
- `backend/app/api/schemas.py` — request/response validation schemas.
- `backend/app/api/routes/restaurants.py` — restaurant API routes.
- `workers/payment_worker.py` — payment-related asynchronous processing.
- `workers/restaurant_worker.py` — restaurant-order processing.
- `workers/delivery_worker.py` — delivery assignment processing.
- `workers/notification_worker.py` — notification processing.
- `workers/retry_scheduler.py` — delayed retry scheduling.
- `workers/base.py` — shared worker behavior.
- `migrations/` — database migration history.
- `scripts/seed.py` — development seed data.
- `infra/nginx.conf` — web/API reverse-proxy configuration.
- `compose.yaml` — service orchestration.
- `tests/` — automated tests.

## What's happening
A route file exposes HTTP operations; a schema describes valid incoming/outgoing data; a model represents stored data; a worker reacts to asynchronous work; a migration changes the database schema.

## Why it matters
When debugging, first identify which layer owns the behavior. A missing button is likely frontend; a 422 is often API validation; a stuck order may involve the database, outbox, broker, or worker.
