# Byte 9: Retry scheduling, quarantine, and crash recovery

**Builds on:** Byte 8

## In plain terms
Temporary errors should be retried; permanently invalid or repeatedly failing events should stop retrying and be moved to a terminal/quarantine path that operators can inspect.

## Relevant path
`workers/retry_scheduler.py` and shared `workers/base.py`.

## Assignment target
The revised assignment describes one initial attempt followed by up to three delayed retries, approximately 2, 10, and 30 seconds, then quarantine/dead-letter handling. Treat these as required behavior to verify—not as proven implementation results.

## Failure cases to test
1. Worker fails twice, then succeeds: confirm delayed retry and one final side effect.
2. Worker always fails: confirm bounded attempts and quarantine/DLQ visibility.
3. Kill a worker during processing: verify the message is redelivered or otherwise recovered.
4. Kill it after database commit but before acknowledgement: verify duplicate delivery does not duplicate the business effect.
5. Stop RabbitMQ: verify pending outbox events publish after broker recovery.

## Why it matters
Infinite immediate retries can overload a failing service. Bounded backoff reduces pressure, while quarantine makes poison messages visible rather than silently looping forever.
