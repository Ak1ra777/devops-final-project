#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

REQUIREMENTS_FILE="/tmp/backend-requirements.txt"

require_command() {
  local command_name="$1"

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Required command not found: ${command_name}"
    exit 1
  fi
}

optional_command() {
  local command_name="$1"

  command -v "$command_name" >/dev/null 2>&1
}

image_exists() {
  local image="$1"

  docker image inspect "$image" >/dev/null 2>&1
}

echo "Running local security checks..."

require_command npm
require_command uv

echo
echo "==> Frontend npm audit"
(
  cd "$PROJECT_ROOT/frontend"
  npm audit --audit-level=high
)

echo
echo "==> Backend pip-audit"
(
  cd "$PROJECT_ROOT/backend"
  uv export \
    --frozen \
    --all-groups \
    --format requirements.txt \
    --no-emit-project \
    --no-hashes \
    --output-file "$REQUIREMENTS_FILE" \
    >/dev/null

  uv tool run --from pip-audit pip-audit --requirement "$REQUIREMENTS_FILE" --strict
)

echo
echo "==> Optional local tools"

if optional_command gitleaks; then
  echo "Running Gitleaks..."
  gitleaks detect --source "$PROJECT_ROOT" --no-banner
else
  echo "Warning: gitleaks is not installed; skipping local secrets scan."
fi

if optional_command hadolint; then
  echo "Running Hadolint..."
  hadolint "$PROJECT_ROOT/backend/Dockerfile" "$PROJECT_ROOT/frontend/Dockerfile"
else
  echo "Warning: hadolint is not installed; skipping Dockerfile linting."
fi

if optional_command trivy; then
  echo "Running Trivy image scans for existing local images..."

  if image_exists devops-final-backend:local; then
    trivy image \
      --ignore-unfixed \
      --vuln-type os,library \
      --severity HIGH,CRITICAL \
      --exit-code 1 \
      devops-final-backend:local
  else
    echo "Warning: devops-final-backend:local does not exist; skipping backend image scan."
  fi

  if image_exists devops-final-frontend:local; then
    trivy image \
      --ignore-unfixed \
      --vuln-type os,library \
      --severity HIGH,CRITICAL \
      --exit-code 1 \
      devops-final-frontend:local
  else
    echo "Warning: devops-final-frontend:local does not exist; skipping frontend image scan."
  fi
else
  echo "Warning: trivy is not installed; skipping local image vulnerability scans."
fi

echo
echo "Local security checks completed."
