#!/bin/sh
# ----
# File:        cilium-install.sh
# Description: Tool to install k8s cilium test clusters using k3d or kind
# Author:      Sergio Talens-Oliag <sto@mixinet.net>
# Copyright:   (c) 2023 Sergio Talens-Oliag <sto@mixinet.net>
# ----

set -e

# Compute WORK_DIR
SCRIPT="$(readlink -f "$0")"
SCRIPT_DIR="$(dirname "$SCRIPT")"
WORK_DIR_RELPATH=".."
WORK_DIR="$(readlink -f "$SCRIPT_DIR/$WORK_DIR_RELPATH")"
TMPL_DIR="$WORK_DIR/tmpl"
YAML_DIR="$WORK_DIR/yaml"

# ---------
# VARIABLES
# ---------

GATEWAY_API_ENABLED="${GATEWAY_API_ENABLED:-false}"
INGRESS_CONTROLLER_DEFAULT="${INGRESS_CONTROLLER_DEFAULT:-false}"
INGRESS_CONTROLLER_ENABLED="${INGRESS_CONTROLLER_ENABLED:-false}"
LOADBALANCER_MODE="shared"

TUNNEL="vxlan"

CILIUM_VERSION="1.15.1"

K3D_NETWORK_NAME="cilium"
K3D_NET_PREFIX="172.30"
K3D_CLUSTER_SUBNET_PREFIX="10.1"
K3D_SERVICE_SUBNET_PREFIX="10.10"
KIND_NETWORK_NAME="kind"
KIND_NET_PREFIX="172.31"
KIND_CLUSTER_SUBNET_PREFIX="10.2"
KIND_SERVICE_SUBNET_PREFIX="10.20"

NETWORK_TYPE="bridge"

METALLB_ENABLED="true"
METALLB_BASE_URL="https://raw.githubusercontent.com/metallb/metallb"
METALLB_VERSION="v0.14.3"
METALLB_DEPLOY_YAML="config/manifests/metallb-native.yaml"
METALLB_YAML_URL="$METALLB_BASE_URL/$METALLB_VERSION/$METALLB_DEPLOY_YAML"
METALLB_YAML="$YAML_DIR/metallb-native.yaml"

NGINX_IC_ENABLED="true"
NGINX_IC_BASE_URL="https://raw.githubusercontent.com/kubernetes/ingress-nginx"
NGINX_IC_VERSION="controller-v1.7.0"
NGINX_IC_DEPLOY_YAML="deploy/static/provider/cloud/deploy.yaml"
NGINX_IC_YAML_URL="$NGINX_IC_BASE_URL/$NGINX_IC_VERSION/$NGINX_IC_DEPLOY_YAML"
NGINX_IC_YAML="$YAML_DIR/ingress-nginx-deploy.yaml"

# GOTMPLs
TMPL_K3D_CONFIG_YAML="$TMPL_DIR/k3d-config.yaml"
TMPL_KIND_CONFIG_YAML="$TMPL_DIR/kind-config.yaml"
TMPL_IPPOOLS_YAML="$TMPL_DIR/ippools.yaml"
TMPL_CILIUM_YAML="$TMPL_DIR/cilium.yaml"
TMPL_METALLB_CRDS_YAML="$TMPL_DIR/metallb-crds.yaml"

# Adjust variables based on other variables
if [ "$METALLB_ENABLED" = "true" ]; then
  BGP_CONTROL_PLANE_ENABLED="false"
else
  BGP_CONTROL_PLANE_ENABLED="true"
fi

# ---------
# FUNCTIONS
# ---------

tmpl() {
    ./sbin/tmpl $*
}

create_network() {
  NETWORK_ID="$(
    docker network inspect "$NETWORK_NAME" --format "{{.Id}}" 2>/dev/null
  )" || true
  if [ "$NETWORK_ID" ]; then
    echo "Using existing network '$NETWORK_NAME' with id '$NETWORK_ID'"
  else
    echo "Creating network '$NETWORK_NAME' in docker"
    docker network create \
      --driver "$NETWORK_TYPE" \
      --subnet "$NETWORK_SUBNET" \
      --gateway "$NETWORK_GATEWAY" \
      --ip-range "$NETWORK_IP_RANGE" \
      "$NETWORK_NAME"
  fi
}

create_cluster() {
  echo "Creating $CTOOL cluster '$CNAME'"
  case "$CTOOL" in
  k3d)
    tmpl \
      -v "cnum=$CNUM" \
      -v "cname=$CNAME" \
      -v "host_ip=$HOST_IP" \
      -v "cluster_subnet=$CLUSTER_SUBNET" \
      -v "service_subnet=$SERVICE_SUBNET" \
      -v "work_dir=$WORK_DIR" \
      "$TMPL_K3D_CONFIG_YAML" 
      echo k3d cluster create -c -
  ;;
  kind)
    tmpl \
      -v "cnum=$CNUM" \
      -v "cname=$CNAME" \
      -v "host_ip=$HOST_IP" \
      -v "cluster_subnet=$CLUSTER_SUBNET" \
      -v "service_subnet=$SERVICE_SUBNET" \
      -v "work_dir=$WORK_DIR" \
      "$TMPL_KIND_CONFIG_YAML" |
      kind create cluster --config="-"
  ;;
  esac
  echo "Cluster '$CNAME' info"
  kubectl --context "$CTX" cluster-info
}

install_gateway_api_crds() {
   BASE_URL="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api"
   BASE_URL="$BASE_URL/v0.5.1/config/crd"
   echo "Installing GatewayAPI CRDs"
   for crd_yaml in standard/gateway.networking.k8s.io_gatewayclasses.yaml \
     standard/gateway.networking.k8s.io_gateways.yaml \
     standard/gateway.networking.k8s.io_httproutes.yaml \
     experimental/gateway.networking.k8s.io_referencegrants.yaml; do
       kubectl --context "$CTX" apply -f "$BASE_URL/$crd_yaml"
   done
}

cilium_status() {
  echo "Checking cilium status"
  cilium status --wait --context "$CTX"
}

master_node_ip() {
  # If we are not running kube-proxy the cilium Pods can't reach the api server
  # because the in-cluster service can't be reached, to fix the issue we use an
  # internal IP that the pods can reach, in this case we get the internal IP of
  # the master node container
  case "$CTOOL" in
  k3d) MASTER_NODE="node/$CTX-server-0";;
  kind) MASTER_NODE="node/$CNAME-control-plane";;
  *) echo "Unknown master node"; exit 1;;
  esac
  kubectl --context "$CTX" get "$MASTER_NODE" -o wide --no-headers |
    awk '{ print $6 }'
}

cilium_cli_install() {
  if [ "$GATEWAY_API_ENABLED" = "true" ]; then
    install_gateway_api_crds
  fi
  _xtra_args=""
  if [ "$CNUM" = "2" ]; then
    _xtra_args="--inherit-ca kind-cilium1"
  fi
  MASTER_NODE_IP="$(master_node_ip)"
  # shellcheck disable=SC2086
  tmpl \
    -v "master_node_ip=$MASTER_NODE_IP" \
    -v "cnum=$CNUM" \
    -v "cname=$CNAME" \
    -v "bgp_control_plane_enabled=$BGP_CONTROL_PLANE_ENABLED" \
    -v "gateway_api_enabled=$GATEWAY_API_ENABLED" \
    -v "ingress_controller_default=$INGRESS_CONTROLLER_DEFAULT" \
    -v "ingress_controller_enabled=$INGRESS_CONTROLLER_ENABLED" \
    -v "loadbalancer_mode=$LOADBALANCER_MODE" \
    -v "tunnel=$TUNNEL" \
    "$TMPL_CILIUM_YAML" |
    cilium install --context "$CTX" --helm-values - $_xtra_args
  # Wait for the deployment
  cilium_status
  echo "Enabling hubble"
  cilium hubble enable --ui --context "$CTX"
}

cilium_helm_install() {
  if [ "$GATEWAY_API_ENABLED" = "true" ]; then
    install_gateway_api_crds
  fi
  helm repo add cilium https://helm.cilium.io/ >/dev/null || true
  # Copy the cilium-ca to the second cluster
  if [ "$CNUM" = "2" ]; then
    echo "Copying the 'cilium-ca' from '$CTOOL-cilium1' to '$CTX'"
    kubectl --context "$CTOOL-cilium1" -n kube-system get secrets/cilium-ca \
      -o yaml | kubectl apply --context "$CTX" -f -
  fi
  MASTER_NODE_IP="$(master_node_ip)"
  # shellcheck disable=SC2086
  tmpl \
    -v "master_node_ip=$MASTER_NODE_IP" \
    -v "cnum=$CNUM" \
    -v "cname=$CNAME" \
    -v "bgp_control_plane_enabled=$BGP_CONTROL_PLANE_ENABLED" \
    -v "gateway_api_enabled=$GATEWAY_API_ENABLED" \
    -v "ingress_controller_default=$INGRESS_CONTROLLER_DEFAULT" \
    -v "ingress_controller_enabled=$INGRESS_CONTROLLER_ENABLED" \
    -v "loadbalancer_mode=$LOADBALANCER_MODE" \
    -v "tunnel=$TUNNEL" \
    "$TMPL_CILIUM_YAML" |
    helm upgrade --install cilium cilium/cilium --version 1.13.1 \
      --kube-context "$CTX" --namespace=kube-system --values=-
}

cilium_install(){
  echo "Installing cilium in cluster '$CNAME'"
  cilium_helm_install
  cilium_status
}

lb_download_yaml() {
  [ -d "$YAML_DIR" ] || mkdir "$YAML_DIR"
  curl -fsSL -o "$METALLB_YAML" "$METALLB_YAML_URL"
}

lb_install() {
  if [ "$METALLB_ENABLED" = "true" ]; then
    if [ ! -f "$METALLB_YAML" ]; then
      lb_download_yaml
    fi
    echo "Installing metallb on kind cluster '$CNAME'"
    kubectl --context "$CTX" apply -f "$METALLB_YAML"
    echo "Waiting for metallb to be ready"
    kubectl --context "$CTX" rollout status deployment --timeout="120s" \
      -n "metallb-system" "controller"
    echo "Configuring metallb"
    tmpl -v "lb_pool_range=$LB_POOL_RANGE" "$TMPL_METALLB_CRDS_YAML" |
      kubectl --context "$CTX" apply -f -
  elif [ "$BGP_CONTROL_PLANE_ENABLED" = "true" ]; then
    echo "Adding LB IPAM Pools"
    tmpl -v "lb_pool_cdir=$LB_POOL_CDIR" "$TMPL_IPPOOLS_YAML" |
      kubectl --context "$CTX" apply -f -
  fi
}

ingress_download_yaml() {
  [ -d "$YAML_DIR" ] || mkdir "$YAML_DIR"
  curl -fsSL -o "$NGINX_IC_YAML" "$NGINX_IC_YAML_URL"
}

ingress_install() {
  if [ "$NGINX_IC_ENABLED" = "true" ]; then
    if [ ! -f "$NGINX_IC_YAML" ]; then
      ingress_download_yaml
    fi
    echo "Installing nginx ingress controller on kind cluster '$CNAME'"
    kubectl --context "$CTX" apply -f "$NGINX_IC_YAML"
    echo "Waiting for the nginx controller to be ready"
    kubectl --context "$CTX" wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=120s
  fi
}

mesh_install() {
  echo "Enabling cluster-mesh on cluster '$CNAME'"
  cilium clustermesh enable --context "$CTX" --service-type LoadBalancer
  echo "Checking cilium status on cluster '$CNAME'"
  cilium status --context "$CTX" --wait
  if [ "$CNUM" -eq "2" ]; then
    echo "Connecting cluster"
    cilium clustermesh connect --context "$CTOOL-cilium1" \
      --destination-context "$CTOOL-cilium2"
    echo "Checking cilium status on cluster '$CNAME'"
    cilium status --context "$CTX" --wait
  fi
}

usage() {
  cat <<EOF
Usage: $0 CTOOL CLUSTER [OPERATION]

- CTOOL is 'k3d' or 'kind'
- CLUSTER is '1' or '2'
- OPERATION is one of:
  - 'base' (== 'network,cluster,cilium,lb,ingress')
  - 'full' (== 'base,mesh')
  - 'network'
  - 'cluster'
  - 'cilium'
  - 'lb'
  - 'lb-yaml'
  - 'ingress'
  - 'ingress-yaml'
  - 'mesh'
  - 'status'
  If missing the default OPERATION is 'base'

EOF
  exit "$1"
}

# ====
# MAIN
# ====

CTOOL="$1"
CNUM="$2"
ACTION="$3"

case "$CTOOL" in
k3d)
  NETWORK_NAME="$K3D_NETWORK_NAME"
  NET_PREFIX="$K3D_NET_PREFIX"
  CLUSTER_SUBNET_PREFIX="$K3D_CLUSTER_SUBNET_PREFIX"
  SERVICE_SUBNET_PREFIX="$K3D_SERVICE_SUBNET_PREFIX"
  ;;
kind)
  NETWORK_NAME="$KIND_NETWORK_NAME"
  NET_PREFIX="$KIND_NET_PREFIX"
  CLUSTER_SUBNET_PREFIX="$KIND_CLUSTER_SUBNET_PREFIX"
  SERVICE_SUBNET_PREFIX="$KIND_SERVICE_SUBNET_PREFIX"
  ;;
*) usage 1;;
esac
case "$CNUM" in
1|2) ;;
*) usage 1 ;;
esac

# Adjust variables based on the input arguments
CNAME="cilium$CNUM"
CTX="$CTOOL-$CNAME"
HOST_IP="127.$NET_PREFIX.$CNUM"
CLUSTER_SUBNET="$CLUSTER_SUBNET_PREFIX$CNUM.0.0/16"
SERVICE_SUBNET="$SERVICE_SUBNET_PREFIX$CNUM.0.0/16"
NETWORK_SUBNET="$NET_PREFIX.0.0/16"
NETWORK_GATEWAY="$NET_PREFIX.0.1"
NETWORK_IP_RANGE="$NET_PREFIX.0.0/17"
LB_POOL_CDIR="$NET_PREFIX.20$CNUM.0/24"
LB_POOL_RANGE="$NET_PREFIX.20$CNUM.1-$NET_PREFIX.20$CNUM.254"

case "$ACTION" in
base|"")
  create_network
  create_cluster
  cilium_install
  lb_install
  ingress_install
;;
full)
  create_network
  create_cluster
  cilium_install
  lb_install
  ingress_install
  mesh_install
;;
network) create_network ;;
cluster) create_cluster ;;
cilium) cilium_install;;
lb) lb_install ;;
lb-yaml) lb_download_yaml ;;
ingress) ingress_install;;
ingress-yaml) ingress_download_yaml;;
status) cilium_status;;
mesh) mesh_install;;
*) usage 1;;
esac
