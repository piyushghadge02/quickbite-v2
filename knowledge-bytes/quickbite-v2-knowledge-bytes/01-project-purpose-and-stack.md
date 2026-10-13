# Byte 1: What QuickBite v2 does

**Builds on:** None — starting point

## In plain terms
QuickBite is a food-delivery application. A customer browses restaurants, chooses menu items, checks out, and follows an order as backend services process payment, restaurant confirmation, delivery assignment, and notifications.

## Main technologies
- **Flutter**: customer-facing UI for web and mobile.
- **FastAPI**: HTTP API and server-side validation/business logic.
- **PostgreSQL**: persistent relational data.
- **RabbitMQ**: transports asynchronous events between services.
- **Workers**: independent processes for payment, restaurant, delivery, and notifications.
- **Transactional outbox**: stores events alongside database changes so a broker outage does not silently lose the intent to publish.
- **Docker Compose**: starts the application services together.

## Simplified flow
```text
Flutter UI -> FastAPI -> PostgreSQL
                    \-> Outbox -> Dispatcher -> RabbitMQ -> Workers
```

## Why it matters
The UI should not be responsible for deciding trusted prices or payment status. The backend owns business decisions, while asynchronous workers handle work that should not block the initial HTTP response.

## Relevant paths
`frontend/`, `backend/`, `workers/`, `migrations/`, `infra/`, `compose.yaml`
