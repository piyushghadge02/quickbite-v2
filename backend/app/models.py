"""SQLAlchemy models — all assignment-required records.

IDs use readable string prefixes (order_…, user_…, rest_…, item_…, evt_…)
matching the assignment examples. Money is integer minor units (INR paise).
All timestamps are timezone-aware UTC.
"""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    Index,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .database import Base


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


class User(Base):
    __tablename__ = "users"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(255), nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    role: Mapped[str] = mapped_column(String(16), nullable=False, default="customer")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )

    orders: Mapped[list["Order"]] = relationship("Order", back_populates="customer")


class Restaurant(Base):
    __tablename__ = "restaurants"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    address: Mapped[str] = mapped_column(String(255), nullable=False, default="")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    image_url: Mapped[str | None] = mapped_column(String(512), nullable=True)
    cuisine: Mapped[str | None] = mapped_column(String(80), nullable=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    rating: Mapped[float | None] = mapped_column(nullable=True)
    delivery_time_minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )

    menu_items: Mapped[list["MenuItem"]] = relationship("MenuItem", back_populates="restaurant")


class MenuItem(Base):
    __tablename__ = "menu_items"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    restaurant_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("restaurants.id"), nullable=False, index=True
    )
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    price_minor: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str] = mapped_column(String(8), nullable=False, default="INR")
    is_available: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    restaurant: Mapped["Restaurant"] = relationship("Restaurant", back_populates="menu_items")


class Driver(Base):
    __tablename__ = "drivers"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone: Mapped[str] = mapped_column(String(32), nullable=False, default="")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    customer_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False, index=True
    )
    restaurant_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("restaurants.id"), nullable=False
    )
    delivery_address: Mapped[str] = mapped_column(String(500), nullable=False)
    currency: Mapped[str] = mapped_column(String(8), nullable=False, default="INR")
    total_minor: Mapped[int] = mapped_column(Integer, nullable=False)
    status: Mapped[str] = mapped_column(String(32), nullable=False, default="PENDING", index=True)
    version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    failure_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    driver_id: Mapped[str | None] = mapped_column(
        String(64), ForeignKey("drivers.id"), nullable=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow, onupdate=_utcnow
    )

    customer: Mapped["User"] = relationship("User", back_populates="orders")
    items: Mapped[list["OrderItem"]] = relationship(
        "OrderItem", back_populates="order", cascade="all, delete-orphan"
    )
    history: Mapped[list["OrderStatusHistory"]] = relationship(
        "OrderStatusHistory", back_populates="order", cascade="all, delete-orphan"
    )


class OrderItem(Base):
    """Server-authoritative price snapshot at checkout."""

    __tablename__ = "order_items"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id"), nullable=False, index=True
    )
    menu_item_id: Mapped[str] = mapped_column(String(64), nullable=False)
    item_name: Mapped[str] = mapped_column(String(160), nullable=False)
    quantity: Mapped[int] = mapped_column(Integer, nullable=False)
    unit_price_minor: Mapped[int] = mapped_column(Integer, nullable=False)

    order: Mapped["Order"] = relationship("Order", back_populates="items")


class OrderStatusHistory(Base):
    """Append-only transition log; every row carries the resulting version."""

    __tablename__ = "order_status_history"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id"), nullable=False, index=True
    )
    from_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
    to_status: Mapped[str] = mapped_column(String(32), nullable=False)
    version: Mapped[int] = mapped_column(Integer, nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )

    order: Mapped["Order"] = relationship("Order", back_populates="history")


class SimulatedPayment(Base):
    __tablename__ = "simulated_payments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id"), nullable=False, unique=True
    )
    status: Mapped[str] = mapped_column(String(32), nullable=False)  # SUCCEEDED | FAILED
    failure_code: Mapped[str | None] = mapped_column(String(64), nullable=True)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )


class DriverAssignment(Base):
    __tablename__ = "driver_assignments"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    order_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("orders.id"), nullable=False, unique=True
    )
    driver_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("drivers.id"), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )


class Notification(Base):
    __tablename__ = "notifications"
    __table_args__ = (UniqueConstraint("customer_id", "event_id", name="uq_notification_customer_event"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    customer_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False, index=True
    )
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    event_type: Mapped[str] = mapped_column(String(64), nullable=False)
    order_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False, default="")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )


class ProcessedEvent(Base):
    """Dedup ledger: (consumer_name, event_id) is unique per logical worker type."""

    __tablename__ = "processed_events"
    __table_args__ = (
        UniqueConstraint("consumer_name", "event_id", name="uq_processed_consumer_event"),
        Index("ix_processed_order", "order_id"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    consumer_name: Mapped[str] = mapped_column(String(32), nullable=False)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    order_id: Mapped[str] = mapped_column(String(64), nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )


class OutboxEvent(Base):
    """Transactional outbox. UNIQUE(event_id, exchange, routing_key, attempt) is
    the publication identity — the same logical event may be published to
    more than one destination, and each retry attempt is a distinct
    publication (the AMQP message_id / event_id itself is preserved across
    redelivery per the assignment)."""

    __tablename__ = "outbox_events"
    __table_args__ = (
        UniqueConstraint(
            "event_id", "exchange", "routing_key", "attempt",
            name="uq_outbox_publication",
        ),
        Index("ix_outbox_due", "state", "available_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    exchange: Mapped[str] = mapped_column(String(128), nullable=False)
    routing_key: Mapped[str] = mapped_column(String(128), nullable=False)
    # Durable attempt counter: 1 = original publication, 2+ = retry attempts.
    attempt: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    # pending | scheduled | inflight | sent
    state: Mapped[str] = mapped_column(String(16), nullable=False, default="pending", index=True)
    available_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    last_error: Mapped[str | None] = mapped_column(Text, nullable=True)
    claimed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    claimed_by: Mapped[str | None] = mapped_column(String(64), nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class RetryJob(Base):
    """Durable record of a scheduled redelivery for one consumer/event/attempt."""

    __tablename__ = "retry_jobs"
    __table_args__ = (
        UniqueConstraint(
            "consumer_name", "event_id", "attempt", name="uq_retry_consumer_event_attempt"
        ),
        Index("ix_retry_due", "state", "run_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    consumer_name: Mapped[str] = mapped_column(String(32), nullable=False)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False)
    attempt: Mapped[int] = mapped_column(Integer, nullable=False)
    queue_name: Mapped[str] = mapped_column(String(128), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    run_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    # scheduled | done | cancelled
    state: Mapped[str] = mapped_column(String(16), nullable=False, default="scheduled", index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )


class QuarantineRecord(Base):
    __tablename__ = "quarantine_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    event_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    consumer_name: Mapped[str] = mapped_column(String(32), nullable=False)
    queue_name: Mapped[str] = mapped_column(String(128), nullable=False)
    event_type: Mapped[str | None] = mapped_column(String(64), nullable=True)
    order_id: Mapped[str | None] = mapped_column(String(64), nullable=True, index=True)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    failure_code: Mapped[str] = mapped_column(String(64), nullable=False)
    payload: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )


class IdempotencyRecord(Base):
    """Checkout idempotency: key scoped to the authenticated customer,
    canonical request hash under a uniqueness constraint."""

    __tablename__ = "idempotency_records"
    __table_args__ = (
        UniqueConstraint("user_id", "idem_key", name="uq_idempotency_user_key"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[str] = mapped_column(
        String(64), ForeignKey("users.id"), nullable=False, index=True
    )
    idem_key: Mapped[str] = mapped_column(String(128), nullable=False)
    request_hash: Mapped[str] = mapped_column(String(64), nullable=False)
    order_id: Mapped[str] = mapped_column(String(64), nullable=False)
    response: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=_utcnow
    )
