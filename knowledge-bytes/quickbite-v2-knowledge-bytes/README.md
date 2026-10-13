# QuickBite v2 — Knowledge Bytes

A modular learning guide for the QuickBite v2 food-delivery application. It follows the uploaded Knowledge Bytes format: one responsibility per byte, plain-language explanation, relevant file paths, short code/flow examples, and why each part matters.

## Project structure covered
- `backend/` — FastAPI application, API routes, schemas, models, business logic
- `frontend/` — Flutter screens, API client/configuration, tests
- `migrations/` — database schema migrations
- `scripts/seed.py` — development data seeding
- `workers/` — payment, restaurant, delivery, notification, and retry scheduler workers
- `infra/` — Dockerfiles, entrypoint, Nginx configuration
- `tests/` — backend and integration/reliability tests
- `compose.yaml` — local multi-service orchestration
- `requirements.txt` / `requirements.lock` — Python dependencies

## Knowledge byte index
1. `01-project-purpose-and-stack.md`
2. `02-repository-map.md`
3. `03-flutter-frontend-and-api-config.md`
4. `04-fastapi-api-boundary.md`
5. `05-data-models-and-migrations.md`
6. `06-order-checkout-and-idempotency.md`
7. `07-transactional-outbox.md`
8. `08-rabbitmq-events-and-workers.md`
9. `09-retries-dlq-and-recovery.md`
10. `10-docker-nginx-and-local-run.md`
11. `11-testing-and-acceptance-evidence.md`
12. `12-troubleshooting-and-viva.md`

## Accuracy note
This guide is based on the project structure, assignment requirements, and implementation details available in the conversation. The actual repository source files were not uploaded into this execution environment, so it does **not** claim line-by-line inspection of the current source or invent exact code excerpts. The paths are based on the known QuickBite v2 tree; verify them against the checked-out repository if your local branch has changed. Any test marked as required is not automatically a passed test.
