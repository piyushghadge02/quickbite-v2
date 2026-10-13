# Byte 11: Testing and evidence

**Builds on:** Bytes 3–10

## In plain terms
A reliable demo needs evidence for both the normal customer journey and failure scenarios. A successful manual order is useful, but it does not prove retry, idempotency, crash recovery, or load requirements.

## Core evidence checklist
- Customer: sign in, browse, add items, checkout, see order ID/status, view history.
- API: invalid input, missing/expired token, cross-customer access, admin authorization.
- Idempotency: retry same key, changed payload conflict, concurrent duplicate submissions.
- Event path: `PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED`.
- Reliability: broker outage/outbox recovery, worker crash, fail-twice-then-succeed, always-fail quarantine.
- Isolation: notification worker failure does not become a payment failure.
- Ordering: duplicate/out-of-order status events do not regress the order.
- Frontend: Flutter widget/integration tests, web reload/deep-link behavior, responsive layouts.
- Load: at least 100 orders; record p50/p95 latency, throughput, backlog, machine/resources, and compare one versus three payment workers using the same workload twice.

## Results discipline
Record the command, date, pass/fail, and captured logs/screenshots for each test. Do not mark a requirement passed unless it was actually run and its result saved.

## Why it matters
A clear evidence trail lets a reviewer distinguish implemented behavior from tested behavior and known limitations.
