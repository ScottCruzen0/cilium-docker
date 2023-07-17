#!/bin/sh
# ----
# File:        cilium-remove.sh
# Description: Tool to remove k8s cilium test clusters using k3d or kind
# Author:      Sergio Talens-Oliag <sto@mixinet.net>
# Copyright:   (c) 2023 Sergio Talens-Oliag <sto@mixinet.net>
# ----

set -e

# ---------
# VARIABLES
# ---------
K3D_NETWORK_NAME="cilium"
KIND_NETWORK_NAME="kind"

# ---------
# FUNCTIONS
# ---------

delete_network() {
  NETWORK_ID="$(
    docker network inspect "$NETWORK_NAME" --format "{{.Id}}" 2>/dev/null
  )" || true
  if [ "$NETWORK_ID" ]; then
    echo "Removing network '$NETWORK_NAME' with id '$NETWORK_ID'"
    docker network rm "$NETWORK_NAME"
  else
    echo "Network '$NETWORK_NAME' not found in docker"
  fi
}

delete_cluster() {
  case "$CTOOL" in
  k3d)
    echo "Deleting k3d cluster '$CNAME'"
    k3d cluster delete "$CNAME"
  ;;
  kind)
    echo "Deleting kind cluster '$CNAME'"
    kind delete cluster -n "$CNAME"
  ;;
  esac
}

usage() {
  cat <<EOF
Usage: $0 CTOOL CLUSTER [OPERATION]

Where:

- CTOOL is 'k3d' or 'kind'
- CLUSTER is '1' or '2'
- OPERATION is one of:
  - 'all'
  - 'network'
  - 'cluster'
  If missing the default OPERATION is 'all'
EOF
  exit "$1"
}

# ====
# MAIN
# ====

CTOOL="$1"
CNUM="$2"
ACTION="${3:-all}"

case "$CTOOL" in
k3d) NETWORK_NAME="$K3D_NETWORK_NAME" ;;
kind) NETWORK_NAME="$KIND_NETWORK_NAME" ;;
*) usage 1;;
esac

case "$CNUM" in
1|2) ;;
*) usage 1 ;;
esac
CNAME="cilium$CNUM"

case "$ACTION" in
all|"")
  delete_cluster
  delete_network
;;
cluster) delete_cluster ;;
network) delete_network ;;
*) usage 1;;
esac
