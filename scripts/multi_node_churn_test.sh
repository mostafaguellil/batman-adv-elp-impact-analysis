#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/multi_node_churn_test.sh [rounds] [down_secs] [up_secs] [churn_count]
# Example:
#   ./scripts/multi_node_churn_test.sh 12 10 10 2

ROUNDS="${1:-12}"
DOWN_SECS="${2:-10}"
UP_SECS="${3:-10}"
CHURN_COUNT="${4:-2}"

CLIENT_NODE="node1"
SERVER_NODE="node2"
SERVER_IP="10.0.0.2"
CANDIDATE_NODES=(node3 node4 node5 node6 node7 node8 node9 node10)

LOG_DIR="./results"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="${LOG_DIR}/multi_node_churn_${TS}.log"

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

pick_random_nodes() {
  printf "%s\n" "${CANDIDATE_NODES[@]}" | shuf | head -n "${CHURN_COUNT}"
}

bring_all_candidates_up() {
  for n in "${CANDIDATE_NODES[@]}"; do
    run_in_node "${n}" "ip link set eth0 up" || true
  done
}

cleanup() {
  log "Cleanup: forcing all churn nodes back up"
  bring_all_candidates_up
  run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true" || true
}

trap cleanup EXIT

if [[ "${CHURN_COUNT}" -lt 1 ]]; then
  echo "ERROR: churn_count must be >= 1"
  exit 1
fi
if [[ "${CHURN_COUNT}" -gt "${#CANDIDATE_NODES[@]}" ]]; then
  echo "ERROR: churn_count must be <= ${#CANDIDATE_NODES[@]}"
  exit 1
fi

log "=== Multi-node BATMAN churn test started ==="
log "rounds=${ROUNDS}, down_secs=${DOWN_SECS}, up_secs=${UP_SECS}, churn_count=${CHURN_COUNT}"
log "client=${CLIENT_NODE}, server=${SERVER_NODE}, candidates=${CANDIDATE_NODES[*]}"

for n in "${CLIENT_NODE}" "${SERVER_NODE}" "${CANDIDATE_NODES[@]}"; do
  if ! check_node "${n}"; then
    log "ERROR: container ${n} not found."
    exit 1
  fi
  if ! run_in_node "${n}" "ip link show bat0 >/dev/null 2>&1"; then
    log "ERROR: bat0 missing in ${n}. Run setup first: ./scripts/setup_batman.sh batman"
    exit 1
  fi
done

bring_all_candidates_up

log "Starting iperf3 server on ${SERVER_NODE}"
run_in_node "${SERVER_NODE}" "pkill iperf3 >/dev/null 2>&1 || true; nohup iperf3 -s >/tmp/iperf3_server.log 2>&1 &"

log "--- Baseline checks ---"
run_in_node "${CLIENT_NODE}" "ping -c 5 ${SERVER_IP}" | tee -a "${OUT}" || true
run_in_node "${CLIENT_NODE}" "iperf3 -c ${SERVER_IP} -t 10" | tee -a "${OUT}" || true
run_in_node "${CLIENT_NODE}" "batctl n; batctl o" | tee -a "${OUT}" || true

for i in $(seq 1 "${ROUNDS}"); do
  mapfile -t selected_nodes < <(pick_random_nodes)
  selected_list="${selected_nodes[*]}"

  log "=== ROUND ${i}/${ROUNDS}: DISCONNECT ${selected_list} ==="
  for n in "${selected_nodes[@]}"; do
    run_in_node "${n}" "ip link set eth0 down"
  done
  sleep "${DOWN_SECS}"

  log "Ping during disconnect"
  run_in_node "${CLIENT_NODE}" "ping -c 3 -W 1 ${SERVER_IP}" | tee -a "${OUT}" || true
  log "Throughput during disconnect"
  run_in_node "${CLIENT_NODE}" "iperf3 -c ${SERVER_IP} -t 5" | tee -a "${OUT}" || true
  log "BATMAN tables after disconnect"
  run_in_node "${CLIENT_NODE}" "batctl n; batctl o" | tee -a "${OUT}" || true

  log "=== ROUND ${i}/${ROUNDS}: RECONNECT ${selected_list} ==="
  for n in "${selected_nodes[@]}"; do
    run_in_node "${n}" "ip link set eth0 up"
  done
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

echo
echo "Done. Results saved to: ${OUT}"
