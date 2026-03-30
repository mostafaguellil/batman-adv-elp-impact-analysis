#!/usr/bin/env bash
set -euo pipefail

NODES=(node1 node2 node3)
BAT_IPS=(10.0.0.1/24 10.0.0.2/24 10.0.0.3/24)
UNDERLAY_IF="eth0"
OS_NAME="$(uname -s)"
MODE="${1:-auto}" # auto | batman | fallback

require_cmd() {
  local cmd="$1"
  local hint="$2"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: '${cmd}' not found."
    echo "Hint: ${hint}"
    exit 1
  fi
}

if [[ "${MODE}" != "auto" && "${MODE}" != "batman" && "${MODE}" != "fallback" ]]; then
  echo "ERROR: Invalid mode '${MODE}'."
  echo "Usage: ./scripts/setup_batman.sh [auto|batman|fallback]"
  exit 1
fi

require_cmd docker "Install Docker Engine and ensure the daemon is running."

if ! docker compose version >/dev/null 2>&1; then
  echo "ERROR: 'docker compose' is not available."
  echo "Hint: Install Docker Compose plugin, then retry."
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Cannot connect to Docker daemon."
  echo "Hint: start Docker Desktop/Engine, then retry."
  exit 1
fi

if [[ "${MODE}" == "auto" ]]; then
  if [[ "${OS_NAME}" == "Linux" ]]; then
    MODE="batman"
  else
    MODE="fallback"
  fi
fi

echo "==> Starting containers"
for node in "${NODES[@]}"; do
  if docker container inspect "${node}" >/dev/null 2>&1; then
    echo "==> Removing stale container: ${node}"
    docker rm -f "${node}" >/dev/null
  fi
done
docker compose up -d

if [[ "${MODE}" == "batman" ]]; then
  require_cmd sudo "Install sudo or run this script as root."
  require_cmd modprobe "Install kmod package on host and retry."
  if [[ "${OS_NAME}" != "Linux" ]]; then
    echo "ERROR: 'batman' mode requires Linux host kernel."
    echo "Hint: use './scripts/setup_batman.sh fallback' on macOS for immediate Docker testing."
    exit 1
  fi
  if ! sudo -n true >/dev/null 2>&1; then
    echo "ERROR: sudo requires a password or is unavailable for this user."
    echo "Hint: run 'sudo -v' first, then rerun this script."
    exit 1
  fi
  if ! modinfo batman-adv >/dev/null 2>&1; then
    echo "ERROR: Kernel module metadata for 'batman-adv' was not found."
    echo "Hint: install a kernel package that includes batman-adv, then retry."
    exit 1
  fi
  echo "==> Loading batman-adv module on host"
  sudo modprobe batman-adv
fi

echo "==> Installing tools in containers (batctl, iproute2, ping, iperf3, tcpdump)"
for node in "${NODES[@]}"; do
  docker exec "${node}" bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y kmod batctl iproute2 iputils-ping iperf3 tcpdump"
done

if [[ "${MODE}" == "batman" ]]; then
  echo "==> Configuring BATMAN-Adv in each node"
  for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    bat_ip="${BAT_IPS[$i]}"

    docker exec "${node}" bash -lc "
      modprobe batman-adv || true
      ip link set ${UNDERLAY_IF} up
      ip link add name bat0 type batadv || true
      batctl if add ${UNDERLAY_IF} || true
      ip link set up dev bat0
      ip addr flush dev bat0
      ip addr add ${bat_ip} dev bat0
    "
  done

  echo "==> BATMAN interfaces"
  for node in "${NODES[@]}"; do
    echo "--- ${node} ---"
    docker exec "${node}" bash -lc "batctl if && ip -4 addr show bat0"
  done
else
  echo "==> Fallback mode enabled (no batman-adv module required)"
  echo "==> Assigning test overlay IPs directly on ${UNDERLAY_IF}"
  for i in "${!NODES[@]}"; do
    node="${NODES[$i]}"
    bat_ip="${BAT_IPS[$i]}"
    docker exec "${node}" bash -lc "
      ip link set ${UNDERLAY_IF} up
      ip addr add ${bat_ip} dev ${UNDERLAY_IF} || true
      ip -4 addr show ${UNDERLAY_IF}
    "
  done
fi

echo "==> Connectivity test over 10.0.0.0/24"
docker exec node1 bash -lc "ping -c 3 10.0.0.2"
docker exec node1 bash -lc "ping -c 3 10.0.0.3"

echo "==> Optional: start iperf3 server on node2"
echo "docker exec -d node2 bash -lc 'iperf3 -s'"
echo "Then run from node1: docker exec node1 bash -lc 'iperf3 -c 10.0.0.2 -t 10'"

if [[ "${MODE}" == "batman" ]]; then
  echo "==> Optional: capture BATMAN packets (includes ELP frames)"
  echo "docker exec node1 bash -lc 'tcpdump -i ${UNDERLAY_IF} -nn -vv ether proto 0x4305'"
  echo "Tip: run batctl in node1 with 'batctl o' and 'batctl n' to observe routes/neighbors."
else
  echo "==> Optional: capture fallback traffic"
  echo "docker exec node1 bash -lc 'tcpdump -i ${UNDERLAY_IF} -nn -vv host 10.0.0.2'"
  echo "Note: fallback mode validates connectivity/perf tooling, not BATMAN-Adv behavior."
fi
