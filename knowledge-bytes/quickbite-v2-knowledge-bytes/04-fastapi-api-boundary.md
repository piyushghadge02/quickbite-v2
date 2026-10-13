# Byte 4: FastAPI is the trusted API boundary

**Builds on:** Bytes 1–3

## In plain terms
FastAPI receives requests from Flutter, validates them, checks identity/permissions, calls application logic, and returns structured responses. Client-submitted prices or role claims must not be trusted.

## Relevant paths
- `backend/app/api/schemas.py` — input and output validation.
- `backend/app/models.py` — persistent domain entities.
- `backend/app/api/routes/restaurants.py` — restaurant-facing routes.
- `backend/` — inspect the current route modules for auth, orders, health, and admin endpoints.

## Example request shape (illustrative)
```json
{
  "restaurant_id": 12,
  "items": [
    {"menu_item_id": 34, "quantity": 2}
  ]
}
```
This is an example of client intent, not a claim that these exact IDs exist in your database.

## What's happening
The server should verify that requested items exist and are available, calculate totals from database prices, validate quantities, and check the caller's permissions. Invalid input should receive a clear 4xx response rather than creating a partial order.

## Why it matters
Validation and authorization protect data integrity. Server-side price calculation prevents a modified client from ordering at a self-selected price.

## Verify
Check the OpenAPI page at `http://localhost:8000/docs` and compare each endpoint with the assignment's `/api/v1` requirement.
