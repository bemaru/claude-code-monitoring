#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; ERRORS=$((ERRORS + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }

ERRORS=0

echo "=== Claude Code Monitoring Healthcheck ==="
echo ""

# 1. Container status
echo "[1/5] Containers"
EXPECTED="otel-collector prometheus loki grafana"
RUNNING=$(docker compose ps --format '{{.Service}} {{.Status}}' 2>/dev/null || true)
for svc in $EXPECTED; do
  LINE=$(echo "$RUNNING" | grep "^${svc} " || true)
  if [ -z "$LINE" ]; then
    fail "$svc — not found"
  elif echo "$LINE" | grep -qi "up"; then
    STATUS=$(echo "$LINE" | cut -d' ' -f2-)
    pass "$svc — $STATUS"
  else
    STATUS=$(echo "$LINE" | cut -d' ' -f2-)
    fail "$svc — $STATUS"
  fi
done

echo ""

# 2. OTel Collector metrics endpoint
echo "[2/5] OTel Collector (localhost:8889)"
if curl -sf http://localhost:8889/metrics > /dev/null 2>&1; then
  METRIC_COUNT=$(curl -sf http://localhost:8889/metrics | grep -c "^claude_code_" || true)
  if [ "$METRIC_COUNT" -gt 0 ]; then
    pass "Reachable — $METRIC_COUNT claude_code_* metrics exposed"
  else
    warn "Reachable but no claude_code_* metrics yet (no session data?)"
  fi
else
  fail "Cannot reach metrics endpoint"
fi

echo ""

# 3. Prometheus scrape
echo "[3/5] Prometheus (localhost:9090)"
if curl -sf http://localhost:9090/-/ready > /dev/null 2>&1; then
  PROM_RESP=$(curl -sf 'http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22otel-collector%22%7D' || true)
  if echo "$PROM_RESP" | grep -q '"1"'; then
    pass "Ready — otel-collector scrape target UP"
  elif [ -n "$PROM_RESP" ]; then
    warn "Ready but otel-collector scrape target may be down"
  else
    warn "Ready but could not query scrape status"
  fi
else
  fail "Cannot reach Prometheus"
fi

echo ""

# 4. Loki
echo "[4/5] Loki (localhost:3100)"
if curl -sf http://localhost:3100/ready > /dev/null 2>&1; then
  pass "Ready"
else
  fail "Cannot reach Loki"
fi

echo ""

# 5. Grafana
echo "[5/5] Grafana (localhost:3030)"
GRAFANA_HEALTH=$(curl -sf http://localhost:3030/api/health 2>/dev/null || true)
if echo "$GRAFANA_HEALTH" | grep -q "ok"; then
  pass "Healthy"
else
  fail "Cannot reach Grafana"
fi

echo ""

# 6. Collector config sanity check
echo "[Bonus] Collector config"
CONFIG="$(dirname "$0")/../collector-config.yaml"
if [ -f "$CONFIG" ]; then
  if grep -q "send_timestamps: false" "$CONFIG"; then
    pass "send_timestamps: false"
  else
    fail "send_timestamps is NOT false — Prometheus will drop stale samples!"
  fi
else
  warn "collector-config.yaml not found at $CONFIG"
fi

echo ""

if [ "$ERRORS" -gt 0 ]; then
  echo -e "${RED}$ERRORS issue(s) found.${NC}"
  exit 1
else
  echo -e "${GREEN}All checks passed.${NC}"
fi
