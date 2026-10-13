"""QuickBite v2 FastAPI application factory."""
from __future__ import annotations

import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .api.routes import admin, auth, health, orders, restaurants
from .config import settings
from .errors import register_error_handlers

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)

log = logging.getLogger("quickbite.api")


def create_app() -> FastAPI:
    settings.validate()
    app = FastAPI(
        title="QuickBite Order Processing API",
        version="2.0.0",
        description=(
            "Food-delivery order processing: versioned REST API, transactional "
            "outbox, RabbitMQ workers, bounded retries, quarantine."
        ),
    )
    register_error_handlers(app)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(settings.cors_origins),
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key", "X-Request-ID"],
        expose_headers=["Location", "X-Request-ID"],
    )
    app.include_router(auth.router, prefix="/api/v1", tags=["auth"])
    app.include_router(restaurants.router, prefix="/api/v1", tags=["restaurants"])
    app.include_router(orders.router, prefix="/api/v1", tags=["orders"])
    app.include_router(admin.router, prefix="/api/v1", tags=["admin"])
    app.include_router(health.router, tags=["health"])
    return app


app = create_app()
