#!/bin/sh
# ----
# File:        ingress-basic.sh
# Description: Script to test the ingress services on our cilium deployments
# Author:      Sergio Talens-Oliag <sto@mixinet.net>
# Copyright:   (c) 2023 Sergio Talens-Oliag <sto@mixinet.net>
# ----
# REF: https://docs.cilium.io/en/latest/network/servicemesh/http/
# ----

set -e

# Compute WORK_DIR
SCRIPT="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT")"
WORK_DIR_RELPATH="."
WORK_DIR="$(readlink -f "$SCRIPT_DIR/$WORK_DIR_RELPATH")"

# VARIABLES
NAMESPACE="ingress-basic"
YAML_DIR="$WORK_DIR/ingress-basic"
BOOKINFO_YAML="$YAML_DIR/bookinfo.yaml"

create_deployment() {
  kubectl create ns "$NAMESPACE" || true
  kubectl apply -n "$NAMESPACE" -f "$BOOKINFO_YAML"
  kubectl apply -n "$NAMESPACE" -f "$INGRESS_BASIC_YAML"
}

delete_deployment() {
  kubectl delete ns "$NAMESPACE"
}

wait_for_deployments() {
  for _deployment in productpage-v1 details-v1; do
    echo "Waiting for '$_deployment' deployment to be ready"
    kubectl wait -n "$NAMESPACE" deployment "$_deployment" \
      --for condition=Available=True --timeout=90s
  done
}

wait_for_ingress(){
  printf "Waiting for the ingress to be ready "
  while true; do
    INGRESS="$(
      kubectl get -n "$NAMESPACE" ingress \
        -o jsonpath="{.items[0].status.loadBalancer.ingress}"
    )"
    if [ -z "$INGRESS" ]; then
      printf "."
      sleep 1
    else
      echo ". OK"
    break
    fi
  done
}

print_objects() {
  kubectl get -n "$NAMESPACE" pods
  kubectl get -n "$NAMESPACE" svc
  kubectl get -n "$NAMESPACE" ingress
  kubectl get -n "$INGRESS_NAMESPACE" "$INGRESS_CONTROLLER"
}

test_ingress() {
  HTTP_INGRESS="$(
    kubectl get -n "$INGRESS_NAMESPACE" "$INGRESS_CONTROLLER" \
      -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
  )"
  URL="http://$HTTP_INGRESS/details/1"
  echo "Testing 'details-v1' service connecting to '$URL'"
  curl -s --fail "$URL" | jq
  URL="http://$HTTP_INGRESS/"
  echo "Testing 'productpage-v1' service connecting to '$URL' (10 first lines)"
  curl -s --fail "$URL" | head -n 10
}

usage() {
  echo "Usage: $0 cilium|nginx create|delete|status|test|wait"
  exit "$1"
}

# ----
# MAIN
# ----

case "$1" in
cilium)
  # We assume that the cilium ingress is shared
  INGRESS_NAMESPACE="kube-system"
  INGRESS_CONTROLLER="service/cilium-ingress"
  INGRESS_BASIC_YAML="$YAML_DIR/ingress-basic-cilium.yaml"
;;
nginx)
  INGRESS_NAMESPACE="ingress-nginx"
  INGRESS_CONTROLLER="service/ingress-nginx-controller"
  INGRESS_BASIC_YAML="$YAML_DIR/ingress-basic-nginx.yaml"
;;
"") usage 0;;
*) usage 1;;
esac

case "$2" in
create) create_deployment;;
delete) delete_deployment;;
status) print_objects;;
test) test_ingress;;
wait) wait_for_deployments && wait_for_ingress;;
*) usage 1;;
esac

# ----
# vim: ts=2:sw=2:et:ai:sts=2
