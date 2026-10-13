# Byte 6: Checkout and idempotency

**Builds on:** Bytes 3–5

## In plain terms
Checkout turns a cart into an order. The server validates items and calculates the total. An idempotency key lets a client safely retry a request after a timeout without unintentionally creating a second order.

## Important behavior to test
- Same key + same payload: return the same logical result/order ID.
- Same key + changed payload: reject the conflicting reuse (the assignment expects a conflict response).
- Two concurrent requests with the same key: only one order should be created.
- A client timeout does not prove the server failed; retry using the same key.

## Conceptual sequence
```text
Flutter -> POST checkout + idempotency key
        -> validate items and calculate price
        -> persist order and idempotency outcome
        -> return order ID/status
```

## Why it matters
Mobile and web networks can fail after the server has committed an order but before the response reaches the client. Idempotency prevents a normal retry from duplicating the purchase.

## Relevant paths
Inspect the order route/service and database model under `backend/`; exact filenames should be confirmed against the current repository.
