#!/bin/sh
# Entrypoint for API service: run migrations then start uvicorn.
set -e

echo "Running database migrations..."
alembic -c migrations/alembic.ini upgrade head

echo "Starting API server..."
exec uvicorn backend.app.main:app --host 0.0.0.0 --port 8000