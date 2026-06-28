#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

FAILED=0

log_section() {
  echo
  echo "==> $1"
}

show_service_logs() {
  local service="$1"

  echo
  echo "Docker Compose logs for ${service}:"
  docker compose logs --no-color "$service" || true
}

wait_for_service_health() {
  local service="$1"
  local container_id
  local status

  container_id="$(docker compose ps -q "$service" 2>/dev/null || true)"
  if [ -z "$container_id" ]; then
    echo "FAIL: no container found for service '${service}'."
    docker compose ps || true
    return 1
  fi

  for i in {1..45}; do
    status="$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id" 2>/dev/null || true)"

    if [ "$status" = "healthy" ]; then
      echo "OK: ${service} is healthy."
      return 0
    fi

    if [ "$status" = "running" ]; then
      echo "OK: ${service} is running and has no Docker health check."
      return 0
    fi

    if [ "$status" = "unhealthy" ] || [ "$status" = "exited" ] || [ "$status" = "dead" ]; then
      echo "FAIL: ${service} is ${status}."
      show_service_logs "$service"
      return 1
    fi

    echo "Waiting for ${service} health (${i}/45): ${status:-unknown}"
    sleep 2
  done

  echo "FAIL: ${service} did not become healthy in time."
  show_service_logs "$service"
  return 1
}

wait_for_url() {
  local name="$1"
  local url="$2"
  local service="$3"

  for i in {1..30}; do
    if curl --fail --silent --show-error "$url" >/dev/null; then
      echo "OK: ${name} endpoint is ready (${url})."
      return 0
    fi

    echo "Waiting for ${name} endpoint (${i}/30): ${url}"
    sleep 2
  done

  echo "FAIL: ${name} endpoint did not respond successfully: ${url}"
  show_service_logs "$service"
  return 1
}

run_check() {
  if ! "$@"; then
    FAILED=1
  fi
}

log_section "Checking Docker Compose service health"
run_check wait_for_service_health backend
run_check wait_for_service_health frontend
run_check wait_for_service_health prometheus
run_check wait_for_service_health loki
run_check wait_for_service_health grafana

log_section "Checking service endpoints"
run_check wait_for_url "backend health" "http://127.0.0.1:8000/api/health" backend
run_check wait_for_url "frontend health" "http://127.0.0.1:3000/health" frontend
run_check wait_for_url "Prometheus readiness" "http://127.0.0.1:9090/-/ready" prometheus
run_check wait_for_url "Loki readiness" "http://127.0.0.1:3100/ready" loki
run_check wait_for_url "Grafana health" "http://127.0.0.1:3001/api/health" grafana

if [ "$FAILED" -ne 0 ]; then
  echo
  echo "Environment validation failed."
  exit 1
fi

echo
echo "Environment validation passed."
