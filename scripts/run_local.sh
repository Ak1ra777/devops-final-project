#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "Starting local Docker Compose stack..."

echo "Preparing backend log directory..."
mkdir -p logs
chmod 777 logs

if [ ! -f ".env" ]; then
  if [ -f ".env.example" ]; then
    echo "Creating .env from .env.example..."
    cp .env.example .env
  else
    echo "Warning: .env.example was not found; continuing without creating .env."
  fi
else
  echo ".env already exists."
fi

echo "Validating Docker Compose configuration..."
docker compose config >/dev/null

echo "Building Docker Compose images with fresh base images..."
docker compose build --pull

echo "Starting services..."
docker compose up -d

echo "Validating local environment..."
"$PROJECT_ROOT/scripts/validate_environment.sh"

cat <<'URLS'

Local stack is ready.

Useful URLs:
  Frontend:       http://127.0.0.1:3000
  Backend health: http://127.0.0.1:8000/api/health
  Backend docs:   http://127.0.0.1:8000/docs
  Prometheus:     http://127.0.0.1:9090
  Grafana:        http://127.0.0.1:3001
  Loki:           http://127.0.0.1:3100

URLS
