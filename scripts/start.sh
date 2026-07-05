#!/usr/bin/env bash
# start.sh — Load .env and start a Go service with env vars
# Usage: bash start.sh <service-dir> [port]
set -euo pipefail
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
GOWORK="$PROJ/backend/go.work"
export GOWORK

# Source .env if it exists
if [ -f "$PROJ/.env" ]; then
  set -a
  source "$PROJ/.env"
  set +a
fi

cd "$PROJ/backend/$1"
exec go run ./cmd/server/
