# Byte 8: RabbitMQ and independent workers

**Builds on:** Bytes 6–7

## In plain terms
RabbitMQ transports events from the API/outbox dispatcher to workers. Each worker owns a separate responsibility, so notification trouble should not automatically be treated as a payment failure.

## Known worker paths
- `workers/payment_worker.py`
- `workers/restaurant_worker.py`
- `workers/delivery_worker.py`
- `workers/notification_worker.py`
- `workers/base.py`

## Conceptual order lifecycle
```text
PENDING -> PAID -> CONFIRMED -> DRIVER_ASSIGNED
```
The exact transitions and failure states are determined by the implementation and should be verified through API/database evidence.

## What's happening
A producer publishes an event to a configured exchange/routing key. A queue receives matching events, and the appropriate worker processes them. A worker should acknowledge a message only after its side effect is safely committed.

## Why it matters
Independent workers isolate workloads and can be scaled separately. Durable queues/messages, publisher confirms, correct acknowledgements, and idempotent handlers are all important to avoid lost or duplicated effects.

## Verify
Inspect `compose.yaml` for worker services and RabbitMQ configuration; inspect worker code for event names, routing keys, ack behavior, and transaction boundaries.
