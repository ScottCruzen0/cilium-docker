#!/bin/sh
# ----
# File:        cilium-connectivity.sh
# Description: Script to test cilium connectivity in our deployments
# Author:      Sergio Talens-Oliag <sto@mixinet.net>
# Copyright:   (c) 2023 Sergio Talens-Oliag <sto@mixinet.net>
# ----

set -e

# ---------
# VARIABLES
# ---------

HUBBLE_PF="${HUBBLE_PF:-false}"

# ---------
# FUNCTIONS
# ---------

usage() {
  cat <<EOF
Usage: $0 CTOOL CLUSTER

Where:

- CTOOL is 'k3d' or 'kind'
- CLUSTER is '1', '2' or '12' (multicluster test)

EOF
  exit "$1"
}

start_pf() {
  if [ "$HUBBLE_PF" = "true" ]; then
    cilium hubble port-forward --context "$CTX" &
    PF_PID="$!"
    echo "Started hubble port-forward for $CTX with PID '$PF_PID'"
  else
    PF_PID=""
  fi
}

stop_pf() {
  if [ "$PF_PID" ]; then
    echo "Killing hubble port-forward (PID '$PF_PID')"
    kill "$PF_PID"
  fi
}

# ====
# MAIN
# ====

CTOOL="$1"
CNUM="$2"

case "$CTOOL" in
k3d|kind) ;;
*) usage 1;;
esac
case "$CNUM" in
1|2)
  CNAME="cilium$CNUM"
  CTX="$CTOOL-$CNAME"
  start_pf
  cilium connectivity test --context "$CTX"
  ;;
12)
  CTX="$CTOOL-cilium1"
  CTX2="$CTOOL-cilium2"
  start_pf
  cilium connectivity test --context "$CTX" --multi-cluster "$CTX2"
  ;;
*) usage 1 ;;
esac

stop_pf
