#!/usr/bin/env bash

# Stop the script if any command fails
set -e

# Move to project root
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

# Define production folders and ports
BLUE_DIR="$PROJECT_ROOT/production/blue"
GREEN_DIR="$PROJECT_ROOT/production/green"
CURRENT_FILE="$PROJECT_ROOT/production/current"
PREVIOUS_FILE="$PROJECT_ROOT/production/previous"

BLUE_PORT=8001
GREEN_PORT=8002

echo "Starting blue-green deployment..."

# Make sure production folders exist
mkdir -p "$BLUE_DIR" "$GREEN_DIR"

# If no current environment exists, start with blue as current
if [ ! -f "$CURRENT_FILE" ]; then
  echo "blue" > "$CURRENT_FILE"
fi

CURRENT="$(cat "$CURRENT_FILE")"

# Pick target environment
if [ "$CURRENT" = "blue" ]; then
  TARGET="green"
  TARGET_DIR="$GREEN_DIR"
  TARGET_PORT="$GREEN_PORT"
else
  TARGET="blue"
  TARGET_DIR="$BLUE_DIR"
  TARGET_PORT="$BLUE_PORT"
fi

echo "Current production: $CURRENT"
echo "Deploying new version to: $TARGET"
echo "Target port: $TARGET_PORT"

# Clean target folder
rm -rf "$TARGET_DIR"
mkdir -p "$TARGET_DIR"

# Build frontend
echo "Building frontend..."
cd "$PROJECT_ROOT/frontend"
npm run build

# Copy frontend build
echo "Copying frontend build..."
mkdir -p "$TARGET_DIR/frontend"
cp -r "$PROJECT_ROOT/frontend/dist" "$TARGET_DIR/frontend/dist"

# Copy backend source
echo "Copying backend source..."
mkdir -p "$TARGET_DIR/backend"
cp "$PROJECT_ROOT/backend/main.py" "$TARGET_DIR/backend/main.py"
cp "$PROJECT_ROOT/backend/pyproject.toml" "$TARGET_DIR/backend/pyproject.toml"
cp "$PROJECT_ROOT/backend/uv.lock" "$TARGET_DIR/backend/uv.lock"
cp "$PROJECT_ROOT/backend/.python-version" "$TARGET_DIR/backend/.python-version"

# Install backend dependencies in target folder
echo "Installing production backend dependencies..."
cd "$TARGET_DIR/backend"
uv sync --all-groups

# Stop old process on target port if it exists
echo "Stopping any old process on port $TARGET_PORT..."
if lsof -ti ":$TARGET_PORT" > /dev/null 2>&1; then
  kill -9 "$(lsof -ti ":$TARGET_PORT")"
fi

# Start target app
echo "Starting $TARGET environment..."
nohup uv run uvicorn main:app --host 127.0.0.1 --port "$TARGET_PORT" > "$TARGET_DIR/app.log" 2>&1 &

# Give server time to start
sleep 3

# Health check target environment
echo "Running health check..."
curl --fail "http://127.0.0.1:$TARGET_PORT/api/health" > /dev/null

# Switch production pointer
echo "$CURRENT" > "$PREVIOUS_FILE"
echo "$TARGET" > "$CURRENT_FILE"

echo "Deployment successful."
echo "Previous production: $CURRENT"
echo "Current production: $TARGET"
echo "Running at: http://127.0.0.1:$TARGET_PORT/api/health"
