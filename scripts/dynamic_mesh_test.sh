#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/dynamic_mesh_test.sh [rounds] [down_secs] [up_secs]
# Example:
#   ./scripts/dynamic_mesh_test.sh 10 12 12

ROUNDS="${1:-10}"
DOWN_SECS="${2:-12}"
UP_SECS="${3:-12}"

CLIENT_NODE="node1"
SERVER_NODE="node2"
CHURN_NODE="node3"
SERVER_IP="10.0.0.2"

LOG_DIR="./results"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${LOG_DIR}/dynamic_mesh_${TS}.log"

mkdir -p "${LOG_DIR}"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "${OUT}"
}

run_in_node() {
  local node="$1"
  shift
  docker exec "${node}" bash -lc "$*"
}

check_node() {
  docker container inspect "$1" >/dev/null 2>&1
}

log "=== Dynamic BATMAN-adv mesh test started ==="
log "rounds=${ROUNDS}, down_secs=${DOWN_SECS}, up_secs=${UP_SECS}"
log "client=${CLIENT_NODE}, server=${SERVER_NODE}, churn=${CHURN_NODE}"

for n in "${CLIENT_NODE}" "${SERVER_NODE}" "${CHURN_NODE}"; do
  if ! check_node "${n}"; then
    log "ERROR: container ${n} not found."
    exit 1
  fi
done

# Quick sanity check that BATMAN setup is present.
for n in "${CLIENT_NODE}" "${SERVER_NODE}" "${CHURN_NODE}"; do
  if ! run_in_node "${n}" "ip link show bat0 >/dev/null 2>&1"; then
    log "ERROR: bat0 missing in ${n}. Run setup first: ./scripts/setup_batman.sh batman"
    exit 1
  fi
done

log "Starting iperf3 server on ${SERVER_NODE}"
run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true; nohup iperf3 -s >/tmp/iperf3_server.log 2>&1 &"

log "--- Baseline ping + iperf ---"
run_in_node "${CLIENT_NODE}" "ping -c 5 ${SERVER_IP}" | tee -a "${OUT}" || true
run_in_node "${CLIENT_NODE}" "iperf3 -c ${SERVER_IP} -t 10" | tee -a "${OUT}" || true
run_in_node "${CLIENT_NODE}" "batctl n; batctl o" | tee -a "${OUT}" || true

for i in $(seq 1 "${ROUNDS}"); do
  log "=== ROUND ${i}/${ROUNDS}: DISCONNECT ${CHURN_NODE} (eth0 down) ==="
  run_in_node "${CHURN_NODE}" "ip link set eth0 down"
  sleep "${DOWN_SECS}"

  log "Ping during disconnect"
  run_in_node "${CLIENT_NODE}" "ping -c 3 -W 1 ${SERVER_IP}" | tee -a "${OUT}" || true

  log "Throughput during disconnect"
  run_in_node "${CLIENT_NODE}" "iperf3 -c ${SERVER_IP} -t 5" | tee -a "${OUT}" || true

  log "BATMAN tables after disconnect"
  run_in_node "${CLIENT_NODE}" "batctl n; batctl o" | tee -a "${OUT}" || true

  log "=== ROUND ${i}/${ROUNDS}: RECONNECT ${CHURN_NODE} (eth0 up) ==="
  run_in_node "${CHURN_NODE}" "ip link set eth0 up"
  sleep "${UP_SECS}"

  log "Ping after reconnect"
  run_in_node "${CLIENT_NODE}" "ping -c 3 -W 1 ${SERVER_IP}" | tee -a "${OUT}" || true

  log "Throughput after reconnect"
  run_in_node "${CLIENT_NODE}" "iperf3 -c ${SERVER_IP} -t 5" | tee -a "${OUT}" || true

  log "BATMAN tables after reconnect"
  run_in_node "${CLIENT_NODE}" "batctl n; batctl o" | tee -a "${OUT}" || true
done

log "=== Test complete ==="
log "Log file: ${OUT}"
log "Stopping iperf3 server"
run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true"

echo
echo "Done. Results saved to: ${OUT}"
