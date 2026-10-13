# Byte 10: Docker Compose, Nginx, and local execution

**Builds on:** Bytes 1–9

## In plain terms
Docker Compose starts the app's related containers on one development network. Nginx can serve the Flutter web build and reverse-proxy API requests to FastAPI.

## Relevant paths
- `compose.yaml`
- `infra/Dockerfile.api`
- `infra/Dockerfile.worker`
- `infra/entrypoint.api.sh`
- `infra/nginx.conf`

## Useful PowerShell commands
Run these from the repository root:
```powershell
docker compose ps
docker compose logs --tail=100 api
docker compose logs --tail=100 payment-worker
docker compose up -d --build
```
To inspect API health, open `http://localhost:8000/health/live` and the readiness endpoint configured by the project. The API docs are commonly at `http://localhost:8000/docs`; the RabbitMQ dashboard is commonly at `http://localhost:15672`.

## What's happening
Compose wires services, networks, environment variables, health checks, and dependencies. A container being “running” does not guarantee that its app is ready; use health checks and logs.

## Why it matters
A healthy API does not prove that the database, broker, dispatcher, or all workers are healthy. Check the specific service involved in the failing flow.
