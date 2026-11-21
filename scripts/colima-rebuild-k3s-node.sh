#!/usr/bin/env bash
# Tears down the local Colima k3s cluster and starts a fresh one.
#
# Usage: scripts/colima-rebuild-k3s-node.sh

set -euo pipefail

if colima status &>/dev/null; then
  echo "Stopping and deleting Colima instance..."
  colima delete -f
else
  echo "No running Colima instance found; nothing to tear down."
fi

echo "Bootstrapping Colima k3s cluster..."
colima start --kubernetes --runtime containerd --cpu 4 --memory 8 --disk 60 \
  --k3s-arg=--disable=traefik \
  --k3s-arg=--disable=servicelb
