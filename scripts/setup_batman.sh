#!/usr/bin/env bash
set -euo pipefail

NODES=(node1 node2 node3)
BAT_IPS=(10.0.0.1/24 10.0.0.2/24 10.0.0.3/24)
UNDERLAY_IF="eth0"

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "ERROR: BATMAN-Adv requires a Linux kernel with the batman-adv module."
  echo "Current host: $(uname -s)"
  echo "Run this project from Linux (native or VM), then rerun this script."
  exit 1
fi

if ! command -v modprobe >/dev/null 2>&1; then
  echo "ERROR: 'modprobe' not found. Install kmod package on host and retry."
  exit 1
fi

echo "==> Starting containers"
docker compose up -d

echo "==> Loading batman-adv module on host"
sudo modprobe batman-adv

echo "==> Installing tools in containers (batctl, iproute2, ping, iperf3, tcpdump)"
for node in "${NODES[@]}"; do
  docker exec "${node}" bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y kmod batctl iproute2 iputils-ping iperf3 tcpdump"
done

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

echo "==> Mesh ping test over bat0"
docker exec node1 bash -lc "ping -c 3 10.0.0.2"
docker exec node1 bash -lc "ping -c 3 10.0.0.3"

echo "==> Optional: start iperf3 server on node2"
echo "docker exec -d node2 bash -lc 'iperf3 -s'"
echo "Then run from node1: docker exec node1 bash -lc 'iperf3 -c 10.0.0.2 -t 10'"

echo "==> Optional: capture BATMAN packets (includes ELP frames)"
echo "docker exec node1 bash -lc 'tcpdump -i ${UNDERLAY_IF} -nn -vv ether proto 0x4305'"
echo "Tip: run batctl in node1 with 'batctl o' and 'batctl n' to observe routes/neighbors."
