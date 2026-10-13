# Byte 7: Transactional outbox

**Builds on:** Bytes 5–6

## In plain terms
The outbox pattern solves a dual-write problem: the app needs to save a database change and publish an event. If it saves the order but the broker is down, publishing directly can fail and leave the system inconsistent.

## Conceptual sequence
```text
One database transaction:
  1. Save order/state change
  2. Save an outbox event
Commit
  -> dispatcher reads pending outbox events
  -> publishes to RabbitMQ
  -> marks event as published
```

## What's happening
The order and the intent to publish are committed together in PostgreSQL. A separate dispatcher retries publishing after broker recovery. Publishing may happen more than once, so consumers must be idempotent.

## Why it matters
The outbox improves eventual delivery of events, but it does not magically guarantee exactly-once processing. The practical design is durable event intent plus at-least-once delivery and duplicate-safe consumers.

## Relevant paths
Inspect backend order/service code, outbox model/dispatcher modules, and `tests/` for outage/recovery coverage. Confirm exact filenames in the current checkout.
