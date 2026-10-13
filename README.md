# QuickBite v2 — Food Delivery Order Processing System

Full-stack food-delivery ordering: **Flutter** client (web / Android / iOS),
**FastAPI** API, **PostgreSQL** with a **transactional outbox**, **RabbitMQ**
with four independent workers, bounded retries, and quarantine.

## Repository layout

```
backend/app/          FastAPI API: routes, domain (checkout, state machine),
                      messaging (outbox, topology, envelopes), security, models
workers/              payment / restaurant / delivery / notification workers,
                      retry scheduler, reliable worker base
migrations/           Alembic (PostgreSQL)
scripts/              seed.py, load_test.py, demo_*.sh/.py,
                      make_architecture_diagram.py
frontend/             Flutter app (separate track — see frontend/README if present)
infra/                Dockerfile.api, Dockerfile.worker, nginx.conf (web host)
docs/                 API_CONTRACT.md (+ openapi.json), ARCHITECTURE.md,
                      ENGINEERING_REPORT.md, DEMO.md
compose.yaml          Full stack with pinned images, healthchecks, named volumes
.env.example          Placeholder config (copy to .env; never commit a real one)
requirements.txt / requirements.lock   Pinned Python deps
```

Key docs: [API contract](docs/API_CONTRACT.md) · [Architecture](docs/ARCHITECTURE.md)
· [Engineering report](docs/ENGINEERING_REPORT.md) · [Demo script](docs/DEMO.md)

## Prerequisites

* **Option A — Docker (recommended for demos):** Docker Engine + Compose v2.
  No other dependencies.
* **Option B — host-local dev (this VM):** Python 3.12 with the project
  `.venv`, PostgreSQL 16, RabbitMQ 3.12+ with the management plugin.
  The sandbox quirk file applies: run local HTTP tests with
  `no_proxy=localhost,127.0.0.1 NO_PROXY=localhost,127.0.0.1`, and set
  `TMPDIR=~/workspace/quickbite-build/piptmp` before pip installs (host
  `/tmp` is a tiny tmpfs).
* **Flutter** (frontend track): Flutter SDK for `flutter build web` /
  `flutter run`; Android emulator or iOS simulator for mobile targets.
  iOS builds require macOS and cannot run on this Linux VM.

## Setup & run

### Option A — Docker Compose

```bash
export TMPDIR=~/workspace/quickbite-build/piptmp   # host /tmp is a tiny tmpfs
cp .env.example .env                                # then set real secrets
docker compose build
docker compose up -d postgres rabbitmq

# Deliberate manual steps (NOT automatic startup commands):
docker compose exec api alembic -c migrations/alembic.ini upgrade head
docker compose exec api python scripts/seed.py

docker compose up -d
docker compose ps
curl -s http://127.0.0.1:8000/health/ready
```

Scale payment workers horizontally:

```bash
docker compose up -d --scale payment-worker=3
```

### Option B — host-local (VM with apt postgres + rabbitmq)

```bash
cd ~/workspace/quickbite-build/quickbite-v2
export TMPDIR=~/workspace/quickbite-build/piptmp
no_proxy=localhost,127.0.0.1 NO_PROXY=localhost,127.0.0.1
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt  # or reuse the existing .venv
cp .env.example .env                                # defaults already point at 127.0.0.1
.venv/bin/alembic -c migrations/alembic.ini upgrade head
.venv/bin/python scripts/seed.py

# terminal 1: API
.venv/bin/uvicorn backend.app.main:app --host 127.0.0.1 --port 8000
# terminal 2: outbox dispatcher + retry scheduler
.venv/bin/python backend/app/messaging/outbox.py & .venv/bin/python workers/retry_scheduler.py &
# terminals 3-6: workers
.venv/bin/python workers/payment_worker.py &
.venv/bin/python workers/restaurant_worker.py &
.venv/bin/python workers/delivery_worker.py &
.venv/bin/python workers/notification_worker.py &
```

### Test accounts (fictional seed data)

| Email | Password | Role |
|---|---|---|
| `admin@quickbite.test` | `admin123` | admin |
| `aarav@quickbite.test` | `customer123` | customer |
| `diya@quickbite.test` | `customer123` | customer |

Seeded catalog: Spice Symphony, Dragon Wok, Crust & Co. (menus in INR minor
units), plus 3 drivers. Re-running `scripts/seed.py` is idempotent.

### URLs

| Service | Address |
|---|---|
| API | http://127.0.0.1:8000 (docs: `/docs`, contract: `/openapi.json`) |
| RabbitMQ management | http://localhost:15672 |
| Flutter web (compose `web`) | http://localhost:8080 |

### Platform API addresses (Flutter)

`API_BASE_URL` is public configuration via `--dart-define`, never a secret
(`frontend/lib/config/app_config.dart`):

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
flutter run -d <android-device> --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Desktop browsers and the iOS simulator use the host's `localhost`; Android
emulators use `10.0.2.2` (the emulator cannot reach the host's `localhost`).
Physical devices need a reachable host LAN address or HTTPS.

## Tests

```bash
.venv/bin/python -m pytest tests/ -v
```

The pytest suite (coordinator's Phase 9) runs against real PostgreSQL and a
real RabbitMQ broker: contract, auth/RBAC, idempotency incl. concurrency,
outbox atomicity, state machine, dedup, retries, quarantine, and
notification isolation. No mocked broker.

## Load test & demos

```bash
# 100 orders, latency p50/p95, throughput, drain check (needs PAYMENT_SIM_MODE=succeed)
.venv/bin/python scripts/load_test.py --orders 100 --concurrency 10 --workers 1

# failure / recovery demos (each narrates the exact commands it runs)
bash scripts/demo_fail_twice_then_succeed.sh
bash scripts/demo_always_fail.sh
bash scripts/demo_kill_worker_recovery.sh [before-tx|after-commit|before-ack]
bash scripts/demo_broker_stop_outbox.sh
bash scripts/demo_notification_backlog.sh
.venv/bin/python scripts/demo_idempotent_checkout.py --concurrency 10
```

Full step-by-step: [docs/DEMO.md](docs/DEMO.md) (covers every §17 sequence).

## Configuration

All services read the same env vars (`backend/app/config.py`); see
`.env.example`. The knobs that matter:

| Var | Default | Purpose |
|---|---|---|
| `DATABASE_URL` / `AMQP_URL` | `127.0.0.1` locals | Connection URLs (compose overrides to service names) |
| `JWT_SECRET` | insecure dev default | **Must** be set to a real secret when `QUICKBITE_ENV=prod` (startup refuses otherwise) |
| `RETRY_DELAYS_S` | `2,10,30` | 1 attempt + 3 delayed retries, then quarantine |
| `PAYMENT_SIM_MODE` | `succeed` | `succeed` \| `fail-twice-then-succeed` \| `always-fail` \| `crash-after-checkpoint` \| `random` (dev/test/demo only — not selectable via the API) |
| `PAYMENT_CRASH_POINT` | `after-commit` | `before-tx` \| `after-commit` \| `before-ack` |
| `RESTAURANT_FAIL_MODE` / `DELIVERY_FAIL_MODE` / `NOTIFICATION_FAIL_MODE` | `off` | `off` \| `always-fail` |
| `PREFETCH_COUNT` | `10` | AMQP prefetch per worker |

## Troubleshooting

* **`docker compose` healthchecks never turn green** — `postgres` needs
  ~10 s on first start (initdb); `rabbitmq` ~20 s. `docker compose logs
  rabbitmq` to watch.
* **`alembic upgrade head` fails: connection refused** — postgres isn't up
  yet, or `DATABASE_URL` points at the wrong host (inside compose it must be
  the `postgres` service name; the compose file sets this for you).
* **Orders stuck `PENDING`, `outbox_pending` grows** — the outbox dispatcher
  or broker is down. Check `docker compose ps`, then
  `docker compose logs outbox-dispatcher`. `/health/ready` tells you whether
  the broker is the problem.
* **Management UI login fails** — compose sets `RABBITMQ_USER` /
  `RABBITMQ_PASSWORD` from `.env` (defaults `guest`/`guest`); the host-local
  broker uses its own configured credentials.
* **`curl`/httpx fail with "Invalid port" on localhost** — the sandbox
  `no_proxy` contains bracketed IPv6 entries that break httpx proxy parsing;
  export `no_proxy=localhost,127.0.0.1 NO_PROXY=localhost,127.0.0.1`.
* **pip fails with no space** — host `/tmp` is a tiny tmpfs; export
  `TMPDIR=~/workspace/quickbite-build/piptmp` first.
* **Demo env changes don't take effect** — workers read env at startup;
  `scripts/demo_*.sh` handle this via `docker compose up -d <service>` after
  editing `.env`. If you edit `.env` by hand, recreate the service yourself.
* **Flutter web shows an empty/403 page** — the `web` service mounts
  `./frontend/build/web`, which only exists after the Flutter track runs
  `flutter build web`. Until then nginx serves an empty directory.
* **bcrypt "password too long"** — passwords are capped at 72 bytes by design.
* **iOS** — cannot be built or run on Linux (no macOS toolchain); reported
  separately by the Flutter track, never claimed as done.
