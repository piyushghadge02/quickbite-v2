# Byte 5: Database models and migrations

**Builds on:** Byte 4

## In plain terms
PostgreSQL stores durable application state: restaurants, menu data, customers, orders, order items, event/outbox records, retry state, and notifications as implemented in the current schema.

## Relevant paths
- `backend/app/models.py`
- `migrations/`
- `scripts/seed.py`

A known migration filename from the current work is:
`migrations/versions/266989b273ed_add_restaurant_fields.py`

## What a migration does
A migration records a repeatable database change. It lets a developer bring an existing database schema forward without manually recreating the database.

## Typical lifecycle
```text
Model/schema change -> create migration -> review migration -> apply migration -> test
```

## Why it matters
The application code and database schema must agree. If a worker expects a table such as a retry table that has not been migrated, the service may fail even though its Python code imports successfully.

## Verify
Use the project's documented migration command and inspect migration status before assuming the schema is current. Do not delete a database volume to “fix” a migration problem unless you are comfortable losing its data.
