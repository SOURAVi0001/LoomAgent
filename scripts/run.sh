#!/usr/bin/env bash
# run.sh — one-command dev environment startup
# Usage: ./scripts/run.sh [--build] [--test]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${ROOT}/scripts/_lib.sh"

# ─── Parse flags ───
BUILD=false
TEST=false
for arg in "$@"; do
  case "$arg" in
    --build) BUILD=true ;;
    --test)  TEST=true  ;;
  esac
done

# ─── 1. Start infrastructure ───
step "Starting infrastructure (Docker Compose)"
docker compose -f "${ROOT}/infra/docker-compose.yml" up -d
wait_for_ports 5432 6379 9092 16686 4317
ok "Infrastructure is up"

# ─── 2. Load env vars ───
if [ -f "${ROOT}/.env" ]; then
  step "Loading .env"
  set -a; source "${ROOT}/.env"; set +a
  ok "Environment loaded"
else
  warn "No .env file found — copy .env.example to .env and fill in secrets"
fi

# ─── 3. Start Go backend services ───
step "Starting Go backend services"
GOWORK="${ROOT}/backend/go.work"
export GOWORK

go_serve "${ROOT}/backend/api-gateway"       8080  "api-gateway"
go_serve "${ROOT}/backend/auth-service"       8081  "auth-service"
go_serve "${ROOT}/backend/user-service"       8082  "user-service"
go_serve "${ROOT}/backend/model-gateway"      8100  "model-gateway"
go_serve "${ROOT}/backend/prompt-registry"    8101  "prompt-registry"
go_serve "${ROOT}/backend/guardrail-service"  8102  "guardrail-service"
go_serve "${ROOT}/backend/cost-analytics"     8103  "cost-analytics"
go_serve "${ROOT}/backend/audit-service"      8104  "audit-service"
go_serve "${ROOT}/backend/notification-service" 8105 "notification-service"
ok "Go services started"

# ─── 4. Start Python AI services ───
step "Starting Python AI services"
py_serve "${ROOT}/ai-services/pr-analysis"     8090  "pr-analysis"  &
py_serve "${ROOT}/ai-services/langgraph-agent" 8091  "langgraph-agent" &
py_serve "${ROOT}/ai-services/rag-service"     8092  "rag-service" &
py_serve "${ROOT}/ai-services/eval-service"    8093  "eval-service" &
wait
ok "Python services started"

# ─── 5. Wait for health ───
step "Waiting for all services to report healthy"
sleep 3
health_check 8080 "api-gateway"
health_check 8081 "auth-service"
health_check 8082 "user-service"
health_check 8100 "model-gateway"
health_check 8101 "prompt-registry"
health_check 8102 "guardrail-service"
health_check 8103 "cost-analytics"
health_check 8104 "audit-service"
health_check 8105 "notification-service"
health_check 8090 "pr-analysis"
health_check 8091 "langgraph-agent"
health_check 8092 "rag-service"
health_check 8093 "eval-service"
ok "All services healthy"

# ─── 6. Optional test run ───
if $TEST; then
  step "Running smoke tests"
  bash "${ROOT}/scripts/test.sh"
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║  All services are running!              ║"
echo "║  Gateway:  http://localhost:8080         ║"
echo "║  Jaeger:   http://localhost:16686        ║"
echo "╚══════════════════════════════════════════╝"
echo "Press Ctrl+C to stop all services"
echo ""

# ─── Wait and clean up on Ctrl+C ───
trap 'echo ""; step "Shutting down..."; kill 0; ok "Done"' EXIT INT TERM
wait
