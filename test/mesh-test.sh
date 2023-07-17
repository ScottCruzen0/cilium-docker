#!/bin/sh
# ----
# File:        mesh-basic.sh
# Description: Script to test the cluster mesh on our cilium deployments
# Author:      Sergio Talens-Oliag <sto@mixinet.net>
# Copyright:   (c) 2023 Sergio Talens-Oliag <sto@mixinet.net>
# ----
# REF: https://docs.cilium.io/en/stable/network/clustermesh/services/
# ----

set -e

# Compute WORK_DIR
SCRIPT="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT")"
WORK_DIR_RELPATH="."
WORK_DIR="$(readlink -f "$SCRIPT_DIR/$WORK_DIR_RELPATH")"

# VARIABLES
NAMESPACE="mesh-test"
SERVICE="svc/rebel-base"
DEPLOYMENT_RB="deployment/rebel-base"
DEPLOYMENT_XW="deployment/x-wing"
YAML_DIR="$WORK_DIR/mesh-test"
GSC1_YAML="$YAML_DIR/cluster1.yaml"
GSC2_YAML="$YAML_DIR/cluster2.yaml"
ACCESS_TEST_LOOPS="7"

access_test() {
  for ctx in "$CTX1" "$CTX2"; do
    echo "Running $ACCESS_TEST_LOOPS tests from '$ctx'"
    counter=0
    while [ "$counter" -lt "$ACCESS_TEST_LOOPS" ]; do
      kubectl --context "$ctx" -n "$NAMESPACE" exec -ti "$DEPLOYMENT_XW" \
        -- curl rebel-base
      counter="$((counter + 1))"
    done
  done
}

create() {
  for cn in "1" "2"; do
    echo "Creating Global Service on Cluster $cn"
    create_namespace "$cn"
    deploy_objects "$cn"
  done
}

create_namespace() {
  case "$1" in
  1) ctx="$CTX1";;
  2) ctx="$CTX2";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  kubectl --context="$ctx" create ns "$NAMESPACE" || true
}

deploy_objects() {
  case "$1" in
  1) ctx="$CTX1"; yaml="$GSC1_YAML";;
  2) ctx="$CTX2"; yaml="$GSC2_YAML";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  sed -e "s/Cluster-/$CTOOL-cluster-/" "$yaml" |
    kubectl --context="$ctx" -n "$NAMESPACE" apply -f -
}

delete() { 
  for cn in "1" "2"; do
    echo "Deleting Global Service on Cluster $cn"
    delete_objects "$cn" || true
    delete_namespace "$cn"
  done
}

delete_deployment() {
  case "$1" in
  1) ctx="$CTX1";;
  2) ctx="$CTX2";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  echo "Deleting '$DEPLOYMENT_RB' on Cluster $1"
  kubectl --context="$ctx" -n "$NAMESPACE" delete "$DEPLOYMENT_RB" || true
}

delete_namespace() {
  case "$1" in
  1) ctx="$CTX1";;
  2) ctx="$CTX2";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  kubectl --context="$ctx" delete ns "$NAMESPACE" || true
}

delete_objects() {
  case "$1" in
  1) ctx="$CTX1"; yaml="$GSC1_YAML";;
  2) ctx="$CTX2"; yaml="$GSC2_YAML";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  sed -e "s/Cluster-/$CTOOL-cluster-/" "$yaml" |
    kubectl --context="$ctx" -n "$NAMESPACE" delete -f -
}

get_cilium_annotations() {
  for ctx in "$CTX1" "$CTX2"; do
    echo "Service '$SERVICE' cilium annotations on '$ctx'"
    kubectl --context "$ctx" -n "$NAMESPACE" get "$SERVICE" -o yaml |
      sed -ne 's/^    service.cilium.io/- service.cilium.io/p'
  done
}

status() {
  for ctx in "$CTX1" "$CTX2"; do
    echo "Mesh test status on '$ctx'"
    echo ""
    kubectl --context "$ctx" -n "$NAMESPACE" get all
    echo ""
  done
}

wait_for_deployments() {
  for ctx in "$CTX1" "$CTX2"; do
    for _deployment in "$DEPLOYMENT_RB" "$DEPLOYMENT_XW"; do
      echo "Waiting for '$_deployment' to be ready on '$ctx'"
      kubectl wait --context="$ctx" -n "$NAMESPACE" "$_deployment" \
        --for condition=Available=True --timeout=90s
    done
  done
}

service_affinity_default(){
  kubectl --context="$1" -n "$NAMESPACE" annotate "$SERVICE" \
    service.cilium.io/affinity-
}


service_affinity_local(){
  kubectl --context="$1" -n "$NAMESPACE" annotate "$SERVICE" \
    service.cilium.io/affinity="local" --overwrite 
}

service_affinity_none(){
  kubectl --context="$1" -n "$NAMESPACE" annotate "$SERVICE" \
    service.cilium.io/affinity="none" --overwrite
}

service_affinity_remote(){
  kubectl --context="$1" -n "$NAMESPACE" annotate "$SERVICE" \
    service.cilium.io/affinity="remote" --overwrite 
}

service_shared_default(){
  case "$1" in
  1) ctx="$CTX1";;
  2) ctx="$CTX2";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  kubectl --context="$ctx" -n "$NAMESPACE" annotate "$SERVICE" \
    service.cilium.io/shared-
}

service_shared_false(){
  case "$1" in
  1) ctx="$CTX1";;
  2) ctx="$CTX2";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  kubectl --context="$ctx" -n "$NAMESPACE" annotate "$SERVICE" \
    service.cilium.io/shared="false" --overwrite 
}

service_shared_true(){
  case "$1" in
  1) ctx="$CTX1";;
  2) ctx="$CTX2";;
  *) echo "Unknown cluster number '$1'"; exit 1;;
  esac
  kubectl --context="$ctx" -n "$NAMESPACE" annotate "$SERVICE" \
    service.cilium.io/shared="true" --overwrite 
}

usage() {
  cat <<EOF
Usage: $0 CLUST_TYPE ACTION

Where CLUST_TYPE is 'k3d' or 'kind' and ACTION is one of:

- create: creates namespaces and deploy services on both clusters
- delete: deletes services and namespaces on both clusters
- delete-deployment [CLUST]: delete rebel-base deployment from CLUST (default 1)
- delete-objects [CLUST]: delete objects from the cluster CLUST (default 1)
- deploy-objects [CLUST]: deploy objects on the cluster CLUST (default 1)
- get-annotations: get service annotations of both clusters
- svc-affinity-local: sets local affinity for the service on both clusters
- svc-affinity-remote: sets remote affinity for the service on both clusters
- svc-affinity-none: removes affinity for the service on both clusters
- svc-shared-default [CLUST]: remove shared annotation from the CLUST cluster
- svc-shared-false [CLUST]: removes service sharing from the CLUST cluster
- svc-shared-true [CLUST]: enables service sharing on the CLUST cluster
- status: prints the deployment status on both clusters
- test: calls the services $ACCESS_TEST_LOOPS times from each cluster
- wait: waits until the deployments are ready on both clusters
EOF
  exit "$1"
}

# ====
# MAIN
# ====

CTOOL="$1"
case "$CTOOL" in
k3d|kind)
  CTX1="$CTOOL-cilium1"
  CTX2="$CTOOL-cilium2"
  ;;
"") usage "0";;
*) usage "1";;
esac

case "$2" in
create) create;;
delete) delete;;
delete-deployment) delete_deployment "${3:-1}";;
delete-objects) delete_objects "${3:-1}";;
deploy-objects) deploy_objects "${3:-1}";;
get-annotations) get_cilium_annotations;;
svc-af-local|svc-affinity-local)
  for ctx in "$CTX1" "$CTX2"; do
    service_affinity_local "$ctx"
  done
;;
svc-af-remote|svc-affinity-remote)
  for ctx in "$CTX1" "$CTX2"; do
    service_affinity_remote "$ctx"
  done
;;
svc-af-none|svc-affinity-none)
  for ctx in "$CTX1" "$CTX2"; do
    service_affinity_local "$ctx"
  done
;;
svc-sh-default|svc-shared-default) service_shared_default "${3:-1}";;
svc-sh-false|svc-shared-false) service_shared_false "${3:-1}";;
svc-sh-true|svc-shared-true) service_shared_true "${3:-1}";;
status) status;;
test) access_test ;;
wait) wait_for_deployments ;;
*) usage "1" ;;
esac

# ----
# vim: ts=2:sw=2:et:ai:sts=2
