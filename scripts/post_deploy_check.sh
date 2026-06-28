#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

FAILED=0

run_check() {
  if ! "$@"; then
    FAILED=1
  fi
}

wait_for_url() {
  local name="$1"
  local url="$2"

  for i in {1..30}; do
    if curl --fail --silent --show-error "$url" >/dev/null; then
      echo "OK: ${name} responded (${url})."
      return 0
    fi

    echo "Waiting for ${name} (${i}/30): ${url}"
    sleep 2
  done

  echo "FAIL: ${name} did not respond successfully: ${url}"
  return 1
}

check_prometheus_backend_target() {
  local url="http://127.0.0.1:9090/api/v1/targets?state=active"
  local response

  for i in {1..40}; do
    response="$(curl --fail --silent --show-error "$url" 2>/dev/null || true)"

    if [ -n "$response" ] && python3 -c '
import json
import sys

data = json.load(sys.stdin)
targets = data.get("data", {}).get("activeTargets", [])
ok = any(
    target.get("scrapePool") == "fastapi-backend"
    and target.get("health") == "up"
    for target in targets
)
sys.exit(0 if ok else 1)
' <<<"$response"; then
      echo "OK: Prometheus fastapi-backend target is up."
      return 0
    fi

    echo "Waiting for Prometheus fastapi-backend target (${i}/40)..."
    sleep 2
  done

  echo "FAIL: Prometheus fastapi-backend target is not up."
  docker compose logs --no-color prometheus || true
  return 1
}

echo "Running post-deploy checks..."

"$PROJECT_ROOT/scripts/validate_environment.sh"

echo
echo "Checking post-deploy backend endpoints..."
run_check wait_for_url "backend metrics" "http://127.0.0.1:8000/metrics"
run_check wait_for_url "backend deployments API" "http://127.0.0.1:8000/api/deployments"

echo
echo "Checking Prometheus scrape target..."
run_check check_prometheus_backend_target

if [ "$FAILED" -ne 0 ]; then
  echo
  echo "Post-deploy checks failed."
  exit 1
fi

echo
echo "Post-deploy checks passed."
