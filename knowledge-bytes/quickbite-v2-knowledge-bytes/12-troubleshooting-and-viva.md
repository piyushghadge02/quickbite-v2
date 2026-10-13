# Byte 12: Troubleshooting and viva preparation

**Builds on:** All previous bytes

## Common issues
- **PowerShell rejects `cd /d`:** that syntax is for Command Prompt. In PowerShell, use `Set-Location 'C:\path\to\project'` or `cd 'C:\path\to\project'`.
- **Git says “not a git repository”:** run `git status` from the actual repository root; initialize Git only if this is genuinely a new local repo.
- **Flutter “Failed to fetch”:** verify the API URL, CORS, Nginx proxy, and whether the frontend bundle was rebuilt after changing `API_BASE_URL`.
- **API healthy but order stuck:** inspect API logs, database order state, outbox/dispatcher, RabbitMQ queue depth, and the relevant worker logs.
- **Worker keeps failing:** inspect exception logs, retry count/schedule, database schema/migrations, and terminal/DLQ records.
- **Push rejected:** do not force-push automatically; inspect remote history and reconcile safely.

## Viva questions
**Why use RabbitMQ?** To decouple request handling from asynchronous order-processing tasks.

**Why an outbox?** To persist the intent to publish an event in the same database transaction as the business change.

**Does the outbox guarantee exactly-once delivery?** No. Duplicate publication can occur; consumers should be idempotent.

**Why calculate prices on the server?** The client is untrusted and could alter submitted totals.

**Why use idempotency keys?** To make safe retries return the same logical checkout result rather than create duplicate orders.

**Why separate notification processing?** A notification outage should not rewrite the payment outcome.

**What is a dead-letter/quarantine queue for?** To isolate messages that exhausted retries or cannot be processed, so they can be investigated.

## Putting it together
Flutter presents the user journey and sends requests to FastAPI. The API validates requests and stores durable state in PostgreSQL. Order changes create outbox events, which a dispatcher publishes to RabbitMQ. Dedicated workers process payment, restaurant, delivery, and notification tasks, using retries and idempotent handlers to recover from transient failures. Tests and logs provide evidence that both the happy path and failure recovery behave as intended.
