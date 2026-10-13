"""Shared fixtures: real PostgreSQL (quickbite_test) + real RabbitMQ.

conftest sets DATABASE_URL before any backend import so the app binds to
the test database. Every test starts from a truncated, minimally seeded DB
and purged queues.
"""
from __future__ import annotations

import asyncio
import os
import uuid

os.environ["DATABASE_URL"] = "postgresql+psycopg://quickbite:quickbite@127.0.0.1:5432/quickbite_test"
os.environ["QUICKBITE_ENV"] = "dev"
os.environ["no_proxy"] = "localhost,127.0.0.1"
os.environ["NO_PROXY"] = "localhost,127.0.0.1"

import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import aio_pika  # noqa: E402
import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import create_engine, text  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402

from backend.app.config import settings  # noqa: E402
from backend.app.database import Base  # noqa: E402
from backend.app.main import create_app  # noqa: E402
from backend.app.messaging.topology import declare_topology  # noqa: E402
from backend.app.models import Driver, MenuItem, Restaurant, User  # noqa: E402
from backend.app.security import create_access_token, hash_password  # noqa: E402

ALL_TABLES = [
    "order_status_history", "order_items", "simulated_payments",
    "driver_assignments", "notifications", "processed_events",
    "outbox_events", "retry_jobs", "quarantine_records",
    "idempotency_records", "orders", "menu_items", "restaurants",
    "drivers", "users", "alembic_version",
]

QUEUES = [
    settings.payment_queue, settings.restaurant_queue, settings.delivery_queue,
    settings.notification_queue, settings.dead_letter_queue,
]


@pytest.fixture(scope="session")
def engine():
    eng = create_engine(settings.database_url, future=True)
    yield eng
    eng.dispose()


@pytest.fixture(scope="session")
def session_factory(engine):
    return sessionmaker(bind=engine, autoflush=False, expire_on_commit=False, future=True)


def seed_minimal(db):
    """Fictional seed: 1 admin, 2 customers, 1 restaurant, 4 menu items, 1 driver."""
    if db.get(User, "t_admin") is None:
        db.add(User(id="t_admin", email="admin@t.test", name="T Admin",
                    role="admin", password_hash=hash_password("admin123")))
        db.add(User(id="t_cust1", email="cust1@t.test", name="T Cust1",
                    role="customer", password_hash=hash_password("cust123")))
        db.add(User(id="t_cust2", email="cust2@t.test", name="T Cust2",
                    role="customer", password_hash=hash_password("cust123")))
        db.add(Restaurant(id="t_rest", name="T Restaurant", address="1 Test Street, Bengaluru",
                          is_active=True))
        db.add(Restaurant(id="t_rest2", name="T Other", address="2 Test Street, Bengaluru",
                          is_active=True))
        db.add_all([
            MenuItem(id="t_biryani", restaurant_id="t_rest", name="Chicken Biryani",
                     price_minor=1250, currency="INR", is_available=True),
            MenuItem(id="t_lassi", restaurant_id="t_rest", name="Mango Lassi",
                     price_minor=400, currency="INR", is_available=True),
            MenuItem(id="t_stale", restaurant_id="t_rest", name="Stale Item",
                     price_minor=999, currency="INR", is_available=False),
            MenuItem(id="t_other_item", restaurant_id="t_rest2", name="Other Item",
                     price_minor=500, currency="INR", is_available=True),
        ])
        db.add(Driver(id="t_driver", name="T Driver", phone="+91-1", is_active=True))
        db.commit()


@pytest.fixture()
def db(session_factory):
    """Truncated + minimally seeded database session for one test."""
    session = session_factory()
    try:
        tables = ", ".join(ALL_TABLES)
        session.execute(text(f"TRUNCATE {tables} RESTART IDENTITY CASCADE"))
        session.commit()
        seed_minimal(session)
        yield session
        session.rollback()
    finally:
        session.close()


@pytest.fixture()
def client(db):
    return TestClient(create_app(), raise_server_exceptions=False)


def _token(user_id: str, role: str) -> str:
    token, _ = create_access_token(user_id=user_id, role=role)
    return token


@pytest.fixture()
def cust1_headers():
    return {"Authorization": f"Bearer {_token('t_cust1', 'customer')}"}


@pytest.fixture()
def cust2_headers():
    return {"Authorization": f"Bearer {_token('t_cust2', 'customer')}"}


@pytest.fixture()
def admin_headers():
    return {"Authorization": f"Bearer {_token('t_admin', 'admin')}"}


@pytest.fixture()
def rmq():
    """Declare topology and purge all queues.

    Setup/teardown only: it yields nothing because aio-pika connections
    are bound to the event loop that created them, and each test helper
    runs its own asyncio.run() loop. Tests must open their own connections.
    """
    async def _setup():
        conn = await aio_pika.connect_robust(settings.amqp_url)
        async with conn:
            ch = await conn.channel()
            await declare_topology(ch)
            for q in QUEUES:
                queue = await ch.get_queue(q, ensure=False)
                await queue.purge()
    asyncio.run(_setup())
    yield


def checkout_payload(**over):
    body = {
        "restaurant_id": "t_rest",
        "delivery_address": "12 Lake Road, Bengaluru",
        "items": [
            {"menu_item_id": "t_biryani", "quantity": 2},
            {"menu_item_id": "t_lassi", "quantity": 1},
        ],
    }
    body.update(over)
    return body


def place_order(client, headers, key=None, **over):
    key = key or str(uuid.uuid4())
    h = dict(headers)
    h["Idempotency-Key"] = key
    return client.post("/api/v1/orders", json=checkout_payload(**over), headers=h), key
