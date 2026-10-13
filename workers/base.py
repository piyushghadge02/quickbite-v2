"""Reliable worker base (assignment §§10–11).

Consumer processing sequence per message:
  1. validate the envelope (malformed/unknown schema -> quarantine, no retry)
  2. SELECT ... FOR UPDATE the order row
  3. check processed_events UNIQUE(consumer_name, event_id) — already seen
     -> ack without repeating effects
  4. state/version check -> apply ONE allowed transition + insert related
     rows (payment / assignment / history / notification) + child outbox
     event(s) in the SAME transaction
  5. commit, THEN ack
  6. transient failure -> roll back, atomically persist retry_jobs row +
     scheduled TARGETED outbox publication (default exchange -> failing
     queue), then ack the original
  7. attempts exhausted -> quarantine record + outbox publication to
     quickbite.dead (key "failed") + terminal transition + terminal event,
     then ack
  8. business-transaction failure (could not even schedule a retry) ->
     do NOT ack; leave unacked, close channel, reconnect with backoff.
     Never a tight nack/requeue loop.

Subclasses implement `handle(session, envelope, attempt) -> HandleResult`.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys
import time
from datetime import datetime, timedelta, timezone

import aio_pika
from aio_pika.abc import AbstractIncomingMessage
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from backend.app.config import settings  # noqa: E402
from backend.app.database import SessionLocal  # noqa: E402
from backend.app.messaging.envelope import (  # noqa: E402
    EnvelopeError,
    build_event,
    validate_envelope,
)
from backend.app.messaging.topology import amqp_message, declare_topology  # noqa: E402
from backend.app.models import (  # noqa: E402
    Order,
    OutboxEvent,
    ProcessedEvent,
    QuarantineRecord,
    RetryJob,
)

log = logging.getLogger("quickbite.worker")

OK = "ok"
TRANSIENT = "transient"
PERMANENT = "permanent"
MALFORMED = "malformed"


class HandleResult:
    def __init__(self, outcome: str, *, failure_code: str | None = None, note: str = ""):
        self.outcome = outcome
        self.failure_code = failure_code
        self.note = note


class Worker:
    consumer_name: str = "base"   # logical worker type, e.g. "payment"
    queue_name: str = ""          # bound queue to consume

    def __init__(self):
        self._shutdown = asyncio.Event()

    # -- to be implemented by subclasses -------------------------------------
    def handle(self, session: Session, envelope: dict, attempt: int) -> HandleResult:
        raise NotImplementedError

    def terminal_event_for(self, session: Session, envelope: dict,
                           failure_code: str) -> dict | None:
        """Child event emitted when attempts are exhausted (or None)."""
        return None

    def terminal_transition(self, session: Session, order: Order,
                            failure_code: str) -> None:
        """Apply the terminal state transition on exhaustion (or no-op)."""
        return None

    # -- framework ------------------------------------------------------------
    def _already_processed(self, session: Session, event_id: str) -> bool:
        row = session.execute(
            select(ProcessedEvent).where(
                ProcessedEvent.consumer_name == self.consumer_name,
                ProcessedEvent.event_id == event_id,
            )
        ).scalar_one_or_none()
        return row is not None

    def _mark_processed(self, session: Session, event_id: str, order_id: str) -> None:
        session.add(ProcessedEvent(
            consumer_name=self.consumer_name, event_id=event_id, order_id=order_id))

    def _schedule_retry(self, session: Session, envelope: dict, attempt: int,
                        queue_name: str) -> bool:
        """Persist retry_jobs + scheduled targeted outbox publication atomically.

        Returns False when no attempts remain (caller should quarantine).
        """
        next_attempt = attempt + 1
        if next_attempt > settings.max_attempts:
            return False
        delay = settings.retry_delays_s[next_attempt - 2]  # attempt1->delays[0]
        run_at = datetime.now(timezone.utc) + timedelta(seconds=delay)
        session.add(RetryJob(
            consumer_name=self.consumer_name,
            event_id=envelope["event_id"],
            attempt=next_attempt,
            queue_name=queue_name,
            payload=envelope,
            run_at=run_at,
            state="scheduled",
        ))
        # Targeted redelivery: default exchange, routing key = failing queue.
        # The publication identity includes the attempt counter so each
        # retry is a distinct outbox row (event_id itself is preserved).
        session.add(OutboxEvent(
            event_id=envelope["event_id"],
            exchange="",
            routing_key=queue_name,
            attempt=next_attempt,
            payload={**envelope, "_headers": {"attempt": next_attempt}},
            state="scheduled",
            available_at=run_at,
        ))
        return True

    def _quarantine(self, session: Session, envelope: dict | None, raw: bytes,
                    attempt: int, failure_code: str, order_id: str | None) -> None:
        payload = envelope if envelope is not None else {"raw": raw[:4000].decode("utf-8", "replace")}
        session.add(QuarantineRecord(
            event_id=(envelope or {}).get("event_id", "unknown"),
            consumer_name=self.consumer_name,
            queue_name=self.queue_name,
            event_type=(envelope or {}).get("event_type"),
            order_id=order_id,
            attempts=attempt,
            failure_code=failure_code,
            payload=payload,
        ))
        # Publish the quarantined envelope to quickbite.dead / key "failed".
        dead_event = build_event(
            event_type="order.failed",
            order_id=order_id or "unknown",
            order_version=0,
            data={
                "quarantined_event_id": (envelope or {}).get("event_id", "unknown"),
                "consumer": self.consumer_name,
                "failure_code": failure_code,
                "original_event": payload,
            },
        )
        session.add(OutboxEvent(
            event_id=dead_event["event_id"],
            exchange=settings.dead_exchange_name,
            routing_key="failed",
            payload=dead_event,
            state="pending",
            available_at=datetime.now(timezone.utc),
        ))

    async def _process(self, message: AbstractIncomingMessage) -> None:
        started = time.monotonic()
        attempt = int((message.headers or {}).get("attempt", 1))
        raw = message.body
        envelope = None
        order_id = None
        try:
            decoded = json.loads(raw.decode("utf-8"))
        except Exception:  # noqa: BLE001
            decoded = None
        try:
            envelope = validate_envelope(decoded)
        except EnvelopeError as exc:
            # Malformed / unknown schema: quarantine immediately, never retry.
            session = SessionLocal()
            try:
                order_id = decoded.get("order_id") if isinstance(decoded, dict) else None
                self._quarantine(session, decoded if isinstance(decoded, dict) else None,
                                 raw, attempt, "MALFORMED_ENVELOPE", order_id)
                session.commit()
            finally:
                session.close()
            log.warning("quarantined malformed event consumer=%s reason=%s",
                        self.consumer_name, exc.message)
            await message.ack()
            return

        order_id = envelope["order_id"]
        session = SessionLocal()
        try:
            if self._already_processed(session, envelope["event_id"]):
                session.rollback()
                log.info("duplicate event ignored consumer=%s event=%s",
                         self.consumer_name, envelope["event_id"])
                await message.ack()
                return
            try:
                result = self.handle(session, envelope, attempt)
            except Exception as exc:  # noqa: BLE001
                # Business transaction failed: do NOT ack, do NOT record.
                session.rollback()
                log.exception("business tx failed consumer=%s event=%s",
                              self.consumer_name, envelope["event_id"])
                raise  # -> outer handler: leave unacked, reconnect/backoff

            if result.outcome == OK:
                self._mark_processed(session, envelope["event_id"], order_id)
                session.commit()
                await message.ack()
            elif result.outcome == TRANSIENT:
                session.rollback()
                self._handle_transient(session, envelope, attempt, result)
                await message.ack()
            else:  # PERMANENT / MALFORMED business-level
                session.rollback()
                self._handle_terminal(session, envelope, attempt, result)
                await message.ack()
            elapsed = time.monotonic() - started
            log.info(
                "handled consumer=%s event=%s order=%s attempt=%d outcome=%s elapsed=%.3fs",
                self.consumer_name, envelope["event_id"], order_id, attempt,
                result.outcome, elapsed,
            )
        except Exception:
            # Anything unexpected after this point: leave the message unacked
            # and let the connection drop trigger redelivery with backoff.
            session.rollback()
            raise
        finally:
            session.close()

    def _handle_transient(self, session: Session, envelope: dict, attempt: int,
                          result: HandleResult) -> None:
        try:
            scheduled = self._schedule_retry(
                session, envelope, attempt, self.queue_name)
            if scheduled:
                session.commit()
                log.info("retry scheduled consumer=%s event=%s next_attempt=%d",
                         self.consumer_name, envelope["event_id"], attempt + 1)
                return
        except IntegrityError:
            # Another racing failure handler already scheduled this attempt.
            session.rollback()
            log.info("retry already scheduled consumer=%s event=%s attempt=%d",
                     self.consumer_name, envelope["event_id"], attempt + 1)
            return
        # Attempts exhausted -> quarantine + terminal handling.
        self._handle_terminal(session, envelope, attempt, result)

    def _handle_terminal(self, session: Session, envelope: dict, attempt: int,
                         result: HandleResult) -> None:
        failure_code = result.failure_code or "PERMANENT_FAILURE"
        order = session.execute(
            select(Order).where(Order.id == envelope["order_id"])
            .with_for_update()
        ).scalar_one_or_none()
        if order is not None:
            self.terminal_transition(session, order, failure_code)
        child = self.terminal_event_for(session, envelope, failure_code)
        if child is not None and order is not None:
            session.add(OutboxEvent(
                event_id=child["event_id"],
                exchange=settings.exchange_name,
                routing_key=child["event_type"],
                payload=child,
                state="pending",
                available_at=datetime.now(timezone.utc),
            ))
        self._quarantine(session, envelope, b"", attempt, failure_code, envelope["order_id"])
        self._mark_processed(session, envelope["event_id"], envelope["order_id"])
        session.commit()
        log.warning("quarantined consumer=%s event=%s code=%s",
                    self.consumer_name, envelope["event_id"], failure_code)

    async def _consume_loop(self) -> None:
        connection = await aio_pika.connect_robust(settings.amqp_url)
        async with connection:
            channel = await connection.channel()
            await channel.set_qos(prefetch_count=settings.prefetch_count)
            await declare_topology(channel)
            queue = await channel.get_queue(self.queue_name, ensure=False)

            async def on_message(message: AbstractIncomingMessage):
                try:
                    # Manual acks are performed inside _process; on any
                    # unexpected failure we leave the message unacked.
                    await self._process(message)
                except Exception as exc:  # noqa: BLE001
                    # Leave unacked: close the channel so the broker
                    # redelivers after reconnect with backoff. Never a
                    # tight nack/requeue loop.
                    log.warning("processing failed unacked consumer=%s err=%s",
                                self.consumer_name, exc)
                    try:
                        await channel.close()
                    except Exception:  # noqa: BLE001
                        pass

            await queue.consume(on_message, no_ack=False)
            log.info("worker %s consuming queue %s", self.consumer_name, self.queue_name)
            await self._shutdown.wait()

    async def run(self) -> None:
        settings.validate()
        loop = asyncio.get_running_loop()
        for sig in (signal.SIGINT, signal.SIGTERM):
            loop.add_signal_handler(sig, self._shutdown.set)
        backoff = 1.0
        while not self._shutdown.is_set():
            try:
                await self._consume_loop()
            except Exception as exc:  # noqa: BLE001
                if self._shutdown.is_set():
                    break
                log.warning("worker %s connection lost: %s; retry in %.1fs",
                            self.consumer_name, exc, backoff)
                await asyncio.sleep(backoff)
                backoff = min(backoff * 2, 30.0)
            else:
                backoff = 1.0
        log.info("worker %s stopped", self.consumer_name)
