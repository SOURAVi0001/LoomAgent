#!/usr/bin/env bash
# _lib.sh — shared helpers for run.sh and test.sh
# shellcheck disable=all

# Colors
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'

step()  { echo -e "\n${CYAN}═══ $1 ═══${NC}"; }
ok()    { echo -e "${GREEN}✓ $1${NC}"; }
warn()  { echo -e "${YELLOW}⚠ $1${NC}"; }
fail()  { echo -e "${RED}✗ $1${NC}"; exit 1; }

# Wait for TCP ports to be reachable
wait_for_ports() {
  for port in "$@"; do
    for i in $(seq 1 30); do
      nc -z localhost "$port" 2>/dev/null && break
      sleep 1
    done
    if ! nc -z localhost "$port" 2>/dev/null; then
      warn "Port $port not reachable after 30s"
    fi
  done
}

# Start a Go service in background
go_serve() {
  local dir="$1" port="$2" name="$3"
  step "  ${name} (:${port})"
  GOWORK="${ROOT}/backend/go.work" go run "${dir}/cmd/server/" > "/tmp/${name}.log" 2>&1 &
  echo "$!" >> "/tmp/.ai-pr-pids"
}

# Start a Python service in background
py_serve() {
  local dir="$1" port="$2" name="$3"
  step "  ${name} (:${port})"
  local venv="${dir}/.venv"
  if [ ! -d "$venv" ]; then
    python3 -m venv "$venv"
    "$venv/bin/pip" install -q -r "${dir}/requirements.txt"
  fi
  nohup bash -c "cd '${dir}' && '${venv}/bin/uvicorn' app.main:app --port '${port}' --host 0.0.0.0" > "/tmp/${name}.log" 2>&1 &
  echo "$!" >> "/tmp/.ai-pr-pids"
}

# Health check an HTTP service
health_check() {
  local port="$1" name="$2"
  local url="http://localhost:${port}/healthz"
  for i in $(seq 1 10); do
    code=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
    [ "$code" = "200" ] && return 0
    sleep 1
  done
  warn "${name} health check failed (port ${port})"
  return 1
}
