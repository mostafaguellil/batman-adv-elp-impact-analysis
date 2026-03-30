#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${ROOT}"

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker not found."
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: docker compose plugin not found."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Docker daemon. Start Docker Desktop/Engine, then retry."
  exit 1
fi

echo "==> Starting full stack (nodes + metrics + Grafana + InfluxDB)…"
if docker compose up -d --help 2>/dev/null | grep -q -- '--wait'; then
  docker compose up -d --wait
else
  echo "NOTE: 'docker compose up --wait' not available; starting without wait."
  docker compose up -d
fi

echo "==> Configuring MANET node tools and overlay IPs (see setup_batman.sh)…"
"${ROOT}/scripts/setup_batman.sh" auto --skip-compose

echo "==> Starting iperf3 server on node2 (port 5201)…"
if docker exec node2 bash -lc "ss -ltn 2>/dev/null | grep -q ':5201 '"; then
  echo "    (iperf3 already listening on 5201)"
else
  docker exec -d node2 bash -lc "iperf3 -s"
fi

echo ""
echo "Lab is ready."
echo "  Grafana     http://localhost:3000   (admin / admin)"
echo "  Prometheus  http://localhost:9090"
echo "  InfluxDB    http://localhost:8086   (admin / adminadmin)"
echo "  cAdvisor    http://localhost:8080"
echo "  Dashboards  Grafana → MANET → MANET Overview"
echo ""
echo "Quick checks:"
echo "  docker exec node1 bash -lc \"ping -c 3 10.0.0.2\""
echo "  docker exec node1 bash -lc \"iperf3 -c 10.0.0.2 -t 10\""
