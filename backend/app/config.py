"""Central configuration for QuickBite v2.

Every service (API, workers, dispatcher, scheduler) reads the same settings
from environment variables. Copy `.env.example` to `.env` to override.
`validate()` is called at startup; it fails fast on unsafe configuration.
"""
from __future__ import annotations

import os


def _get(name: str, default: str) -> str:
    return os.getenv(name, default)


def _get_int(name: str, default: int) -> int:
    return int(os.getenv(name, str(default)))


def _get_float(name: str, default: float) -> float:
    return float(os.getenv(name, str(default)))


class Settings:
    # --- Database / broker -------------------------------------------------
    database_url: str = _get(
        "DATABASE_URL", "postgresql+psycopg://quickbite:quickbite@127.0.0.1:5432/quickbite"
    )
    amqp_url: str = _get("AMQP_URL", "amqp://guest:guest@127.0.0.1:5672/")

    # --- Topology names (assignment-mandated) -------------------------------
    exchange_name: str = _get("EXCHANGE_NAME", "quickbite.orders")
    dead_exchange_name: str = _get("DEAD_EXCHANGE_NAME", "quickbite.dead")
    dead_letter_queue: str = _get("DEAD_LETTER_QUEUE", "orders.dead-letter.queue")
    payment_queue: str = _get("PAYMENT_QUEUE", "payment.queue")
    restaurant_queue: str = _get("RESTAURANT_QUEUE", "restaurant.queue")
    delivery_queue: str = _get("DELIVERY_QUEUE", "delivery.queue")
    notification_queue: str = _get("NOTIFICATION_QUEUE", "notification.queue")

    # --- Reliability tuning -------------------------------------------------
    prefetch_count: int = _get_int("PREFETCH_COUNT", 10)
    # 1 initial attempt + 3 delayed retries, ~2s / 10s / 30s by default.
    retry_delays_s: tuple[float, ...] = tuple(
        float(x) for x in _get("RETRY_DELAYS_S", "2,10,30").split(",") if x.strip()
    )
    max_attempts: int = 1 + len(retry_delays_s)
    outbox_poll_interval_s: float = _get_float("OUTBOX_POLL_INTERVAL_S", 0.5)
    outbox_batch_size: int = _get_int("OUTBOX_BATCH_SIZE", 50)
    outbox_claim_lease_s: int = _get_int("OUTBOX_CLAIM_LEASE_S", 300)
    retry_scheduler_interval_s: float = _get_float("RETRY_SCHEDULER_INTERVAL_S", 0.5)

    # --- Deterministic simulation controls (dev/test/demo ONLY) -------------
    # payment: succeed | fail-twice-then-succeed | always-fail |
    #          crash-after-checkpoint | random
    payment_sim_mode: str = _get("PAYMENT_SIM_MODE", "succeed")
    # restaurant/delivery: off | always-fail ; notification: off | always-fail
    restaurant_fail_mode: str = _get("RESTAURANT_FAIL_MODE", "off")
    delivery_fail_mode: str = _get("DELIVERY_FAIL_MODE", "off")
    notification_fail_mode: str = _get("NOTIFICATION_FAIL_MODE", "off")
    # crash-after-checkpoint target: "before-tx" | "after-commit" | "before-ack"
    payment_crash_point: str = _get("PAYMENT_CRASH_POINT", "after-commit")
    # Optional per-stage artificial delays (seconds) for load demos.
    sim_payment_delay_s: float = _get_float("SIM_PAYMENT_DELAY_S", 0.0)
    sim_restaurant_delay_s: float = _get_float("SIM_RESTAURANT_DELAY_S", 0.0)
    sim_delivery_delay_s: float = _get_float("SIM_DELIVERY_DELAY_S", 0.0)

    # --- Auth ----------------------------------------------------------------
    jwt_secret: str = _get("JWT_SECRET", "dev-only-insecure-secret-change-me")
    jwt_algorithm: str = _get("JWT_ALGORITHM", "HS256")
    jwt_expires_minutes: int = _get_int("JWT_EXPIRES_MINUTES", 60)

    # --- HTTP -----------------------------------------------------------------
    api_host: str = _get("API_HOST", "127.0.0.1")
    api_port: int = _get_int("API_PORT", 8000)
    # Explicit origins; never "*" when credentials are used.
    cors_origins: tuple[str, ...] = tuple(
        o.strip() for o in _get("CORS_ORIGINS", "http://localhost:8080").split(",") if o.strip()
    )
    # Bounded readiness probes.
    ready_db_timeout_s: float = _get_float("READY_DB_TIMEOUT_S", 2.0)
    ready_amqp_timeout_s: float = _get_float("READY_AMQP_TIMEOUT_S", 2.0)

    def validate(self) -> None:
        if self.jwt_secret == "dev-only-insecure-secret-change-me" and os.getenv(
            "QUICKBITE_ENV", "dev"
        ) == "prod":
            raise RuntimeError("JWT_SECRET must be set to a real secret in prod (QUICKBITE_ENV=prod).")
        if self.payment_sim_mode not in (
            "succeed",
            "fail-twice-then-succeed",
            "always-fail",
            "crash-after-checkpoint",
            "random",
        ):
            raise RuntimeError(f"Unknown PAYMENT_SIM_MODE: {self.payment_sim_mode}")
        for name in ("restaurant_fail_mode", "delivery_fail_mode", "notification_fail_mode"):
            if getattr(self, name) not in ("off", "always-fail"):
                raise RuntimeError(f"Unknown {name.upper()}: {getattr(self, name)}")


settings = Settings()
