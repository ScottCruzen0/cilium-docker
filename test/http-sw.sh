#!/bin/sh

# REF: https://docs.cilium.io/en/stable/gettingstarted/demo/#starwars-demo

# Compute WORK_DIR
SCRIPT="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT")"
WORK_DIR_RELPATH="."
WORK_DIR="$(readlink -f "$SCRIPT_DIR/$WORK_DIR_RELPATH")"

# VARIABLES
NAMESPACE="http-sw"
YAML_DIR="$WORK_DIR/http-sw"
APP_YAML="$YAML_DIR/http-sw-app.yaml"
SW_L3_L4_POLICY_YAML="$YAML_DIR/sw_l3_l4_policy.yaml"
SW_L3_L4_L7_POLICY_YAML="$YAML_DIR/sw_l3_l4_l7_policy.yaml"

access_test() {
  for pod in xwing tiefighter; do
    ret="0"
    echo "Checking deathstar access from '$pod'"
    kubectl -n "$NAMESPACE" exec "$pod" -- curl --connect-timeout 5 \
      -s -XPOST deathstar.$NAMESPACE.svc.cluster.local/v1/request-landing ||
      ret="$?"
    if [ "$ret" -ne "0" ]; then
      echo "Connection failed!"
    fi
  done
  # shellcheck disable=SC2043
  for pod in tiefighter; do
    ret="0"
    echo "Checking deathstar exaust-port access from '$pod'"
    kubectl -n "$NAMESPACE" exec "$pod" -- curl --connect-timeout 5 \
      -s -XPUT deathstar.$NAMESPACE.svc.cluster.local/v1/exhaust-port ||
      ret="$?"
    if [ "$ret" -ne "0" ]; then
      echo "Connection failed!"
    fi
  done
}

create_deployment() {
  kubectl create ns "$NAMESPACE" || true
  kubectl -n "$NAMESPACE" apply -f "$APP_YAML"
}

delete_deployment() {
  kubectl delete ns "$NAMESPACE"
}

list_sw_endpoints() {
  for pod in $(kubectl -n kube-system get pods -l k8s-app=cilium -o name); do
    OUTPUT="$(
      kubectl -n kube-system exec "$pod" -c cilium-agent \
        -- cilium endpoint list
    )"
    echo "$OUTPUT" | head -1
    echo "$OUTPUT" | grep -B6 "org=\(alliance\|empire\)" | grep -v "^--"
  done
}

status() {
  kubectl -n "$NAMESPACE" get all,CiliumNetworkPolicy
}

usage() {
  echo "Usage: $0 create|delete|desc|endpoints|policy-(l34|l7|none)|status|test"
  exit "$1"
}

# ====
# MAIN
# ====

case "$1" in
create) create_deployment;;
delete) delete_deployment;;
desc|describe)
  if kubectl -n "$NAMESPACE" get cnp/rule1 -o name 2>/dev/null 1>&2; then
    echo "Describe current policy"
    kubectl -n "$NAMESPACE" describe CiliumNetworkPolicy/rule1
  else
    echo "Policy not installed"
  fi
  ;;
eps|endpoints) list_sw_endpoints;;
policy-l34)
  echo "Adding SW L3-L4 policy"
  echo ""
  cat "$SW_L3_L4_POLICY_YAML"
  echo ""
  kubectl -n "$NAMESPACE" apply -f "$SW_L3_L4_POLICY_YAML"
;;
policy-l7)
  echo "Adding SW L3-L4-L7 policy:"
  echo ""
  cat "$SW_L3_L4_L7_POLICY_YAML"
  echo ""
  kubectl -n "$NAMESPACE" apply -f "$SW_L3_L4_L7_POLICY_YAML"
;;
policy-none)
  echo "Removing Cilium Network Policy 'rule1'"
  kubectl -n "$NAMESPACE" delete CiliumNetworkPolicy/rule1
;;
status) status;;
test)
  echo "Running access test"
  access_test
;;
"") usage "0" ;;
*) usage "1" ;;
esac

# ----
# vim: ts=2:sw=2:et:ai:sts=2
