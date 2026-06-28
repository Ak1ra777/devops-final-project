#!/usr/bin/env bash

# Stop the script if any required command fails unexpectedly
set -euo pipefail

# Move to project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Define production state file and log file
CURRENT_FILE="$PROJECT_ROOT/production/current"
LOG_FILE="$PROJECT_ROOT/logs/health.log"

# Define blue and green ports
BLUE_PORT=8001
GREEN_PORT=8002

# First argument = interval between checks, default is 5 seconds
INTERVAL_SECONDS="${1:-5}"

# Second argument = number of checks, default 0 means run forever
MAX_CHECKS="${2:-0}"

# Make sure logs folder and log file exist
mkdir -p "$PROJECT_ROOT/logs"
touch "$LOG_FILE"

echo "Starting health monitoring..."
echo "Logging results to: $LOG_FILE"
echo "Interval: ${INTERVAL_SECONDS}s"
echo "Max checks: ${MAX_CHECKS}"

COUNT=0
FAILED=0

while true; do
  # Prefer the blue-green deployment state when it exists.
  if [ -f "$CURRENT_FILE" ]; then
    CURRENT="$(cat "$CURRENT_FILE")"

    if [ "$CURRENT" = "blue" ]; then
      PORT="$BLUE_PORT"
    elif [ "$CURRENT" = "green" ]; then
      PORT="$GREEN_PORT"
    else
      echo "Invalid production/current value: $CURRENT"
      exit 1
    fi

    HEALTH_URL="http://127.0.0.1:$PORT/api/health"
  else
    # If blue-green has not been deployed, monitor the Docker Compose backend.
    CURRENT="compose"
    PORT="${BACKEND_PORT:-8000}"
    HEALTH_URL="http://127.0.0.1:$PORT/api/health"
  fi

  # Create timestamp for log line
  TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"

  # Run health check and write result to log file
  if curl --silent --fail --max-time 5 "$HEALTH_URL" > /dev/null; then
    echo "$TIMESTAMP HEALTH OK environment=$CURRENT url=$HEALTH_URL" | tee -a "$LOG_FILE"
  else
    echo "$TIMESTAMP HEALTH FAIL environment=$CURRENT url=$HEALTH_URL" | tee -a "$LOG_FILE"
    FAILED=1
  fi

  # Increase check counter
  COUNT=$((COUNT + 1))

  # Stop after MAX_CHECKS if a limit was provided
  if [ "$MAX_CHECKS" -gt 0 ] && [ "$COUNT" -ge "$MAX_CHECKS" ]; then
    echo "Monitoring completed after $COUNT checks."
    if [ "$FAILED" -ne 0 ]; then
      echo "One or more health checks failed."
      exit 1
    fi
    break
  fi

  # Wait before next health check
  sleep "$INTERVAL_SECONDS"
done
