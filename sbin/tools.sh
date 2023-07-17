#!/bin/sh
# ----
# File:        tools.sh
# Description: Tool to check and install tools used on this repo
# Author:      Sergio Talens-Oliag <sto@mixinet.net>
# Copyright:   (c) 2023 Sergio Talens-Oliag <sto@mixinet.net>
# ----

set -e

# ---------
# Variables
# ---------

# System dirs
BASH_COMPLETION="/etc/bash_completion.d"
ZSH_COMPLETIONS="/usr/share/zsh/vendor-completions"

# Terminal related variables
if [ "$TERM" ] && type tput >/dev/null; then
  bold="$(tput bold)"
  normal="$(tput sgr0)"
else
  bold=""
  normal=""
fi
export yes_no="(${bold}Y${normal}es/${bold}N${normal}o)"

# Versions
CILIUM_CLI_VERSION="${CILIUM_CLI_VERSION:-v0.13.2}"
# Uncomment to get the latest helm version
# GET_HELM_URL="https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3"
HELM_VERSION="${HELM_VERSION:-3.11.2}"
HUBBLE_VERSION="${HUBBLE_VERSION:-v0.11.3}"
K3D_VERSION="${K3D_VERSION:-v5.4.9}"
KIND_VERSION="${KIND_VERSION:-v0.18.0}"
KUBECTL_VERSION="${KUBECTL_VERSION:-1.26.3}"
TMPL_VERSION="${TMPL_VERSION:-v0.4.0}"

# ---------
# Functions
# ---------

# Auxiliary function to read a boolean value. $1 text to show - $2 default value
read_bool() {
  case "${2}" in
  y | Y | yes | Yes | YES | true | True | TRUE) _yn="Yes" ;;
  *) _yn="No" ;;
  esac
  printf "%s ${yes_no} [%s]: " "${1}" "${bold}${_yn}${normal}"
  read -r READ_VALUE
  case "${READ_VALUE}" in
  '') [ "$_yn" = "Yes" ] && READ_VALUE="true" || READ_VALUE="false" ;;
  y | Y | yes | Yes | YES | true | True | TRUE) READ_VALUE="true" ;;
  *) READ_VALUE="false" ;;
  esac
}

# Auxiliary function to check if a boolean value is set to yes/true or not
is_selected() {
  case "${1}" in
  y | Y | yes | Yes | YES | true | True | TRUE) return 0 ;;
  *) return 1 ;;
  esac
}

# Auxiliary function to check if an application is installed
tools_app_installed() {
  _app="$1"
  type "$_app" >/dev/null 2>&1 || return 1
}

# Function to check if all the tools are installed
tools_check_apps_installed() {
  _missing=""
  for _app in "$@"; do
    tools_app_installed "$_app" || _missing="$_missing $_app"
  done
  if [ "$_missing" ]; then
    echo "The following apps could not be found:"
    for _app in $_missing; do
      echo "- $_app"
    done
    exit 1
  fi
}

# Auxiliary function to check if we want to install an app
tools_install_app() {
  _app="$1"
  if tools_app_installed "$_app"; then
    echo "$_app found ($(type "$_app"))."
    MSG="Re-install in /usr/local/bin?"
    OPT="false"
  else
    echo "$_app could not be found."
    MSG="Install it in /usr/local/bin?"
    OPT="true"
  fi
  # Export NONINTERACTIVE as 'true' to use default values
  if [ "$NONINTERACTIVE" = "true" ]; then
    READ_VALUE="$OPT"
  else
    read_bool "$MSG" "$OPT"
  fi
  is_selected "${READ_VALUE}" && return 0 || return 1
}

tools_check_cilium() {
  if tools_install_app "cilium"; then
    tmp_dir="$(mktemp -d)"
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    esac
    url="https://github.com/cilium/cilium-cli/releases/download"
    url="$url/${CILIUM_CLI_VERSION}/cilium-linux-$arch.tar.gz"
    curl -fsSL -o "$tmp_dir/cilium.tar.gz" "$url"
    tar xzf "$tmp_dir/cilium.tar.gz" -C "$tmp_dir" "cilium"
    sudo install "$tmp_dir/cilium" /usr/local/bin
    rm -rf "$tmp_dir"
    cilium version
    if [ -d "$BASH_COMPLETION" ]; then
      sudo sh -c "cilium completion bash > $BASH_COMPLETION/cilium"
    fi
    if [ -d "$ZSH_COMPLETIONS" ]; then
      sudo sh -c "cilium completion zsh > $ZSH_COMPLETIONS/_cilium"
    fi
  fi
}

tools_check_docker() {
  if tools_install_app "docker"; then
    tmp_dir="$(mktemp -d)"
    curl -fsSL -o "$tmp_dir/install-docker.sh" "https://get.docker.com"
    sh "$tmp_dir/install-docker.sh"
    rm -rf "$tmp_dir"
    sudo usermod -aG docker "$(id -un)"
    docker --version
  fi
}

tools_check_helm() {
  if tools_install_app "helm"; then
    tmp_dir="$(mktemp -d)"
    if [ "$GET_HELM" ]; then
      curl -fsSL -o "$tmp_dir/get_helm.sh" "$GET_HELM"
      bash "$tmp_dir/get_helm.sh"
    else
      os="$(uname -s | tr '[:upper:]' '[:lower:]')"
      case "$(uname -m)" in
      x86_64) arch="amd64" ;;
      esac
      url="https://get.helm.sh/helm-v$HELM_VERSION-$os-$arch.tar.gz"
      curl -fsSL -o "$tmp_dir/helm.tar.gz" "$url"
      tar xzf "$tmp_dir/helm.tar.gz" -C "$tmp_dir" "$os-$arch/helm"
      sudo install "$tmp_dir/$os-$arch/helm" /usr/local/bin
    fi
    rm -rf "$tmp_dir"
    helm version
    if [ -d "$BASH_COMPLETION" ]; then
      sudo sh -c "helm completion bash > $BASH_COMPLETION/helm"
    fi
    if [ -d "$ZSH_COMPLETIONS" ]; then
      sudo sh -c "helm completion zsh > $ZSH_COMPLETIONS/_helm"
    fi
  fi
}

tools_check_hubble() {
  if tools_install_app "hubble"; then
    tmp_dir="$(mktemp -d)"
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    esac
    url="https://github.com/cilium/hubble/releases/download"
    url="$url/${HUBBLE_VERSION}/hubble-linux-$arch.tar.gz"
    curl -fsSL -o "$tmp_dir/hubble.tar.gz" "$url"
    tar xzf "$tmp_dir/hubble.tar.gz" -C "$tmp_dir" "hubble"
    sudo install "$tmp_dir/hubble" /usr/local/bin
    rm -rf "$tmp_dir"
    hubble version
    if [ -d "$BASH_COMPLETION" ]; then
      sudo sh -c "hubble completion bash > $BASH_COMPLETION/hubble"
    fi
    if [ -d "$ZSH_COMPLETIONS" ]; then
      sudo sh -c "hubble completion zsh > $ZSH_COMPLETIONS/_hubble"
    fi
  fi
}

tools_check_k3d() {
  if tools_install_app "k3d"; then
    [ -d /usr/local/bin ] || sudo mkdir /usr/local/bin
    curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh |
      TAG="$K3D_VERSION" bash
    k3d version
    if [ -d "$BASH_COMPLETION" ]; then
      sudo sh -c "k3d completion bash > $BASH_COMPLETION/k3d"
    fi
    if [ -d "$ZSH_COMPLETIONS" ]; then
      sudo sh -c "k3d completion zsh > $ZSH_COMPLETIONS/_k3d"
    fi
  fi
}

tools_check_kind() {
  if tools_install_app "kind"; then
    os="$(uname | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    esac
    url="https://github.com/kubernetes-sigs/kind/releases/download"
    url="$url/$KIND_VERSION/kind-$os-$arch"
    [ -d /usr/local/bin ] || sudo mkdir /usr/local/bin
    tmp_dir="$(mktemp -d)"
    curl -fsSL -o "$tmp_dir/kind" "$url"
    sudo install "$tmp_dir/kind" /usr/local/bin/
    rm -rf "$tmp_dir"
    kind version
    if [ -d "$BASH_COMPLETION" ]; then
      sudo sh -c "kind completion bash > $BASH_COMPLETION/kind"
    fi
    if [ -d "$ZSH_COMPLETIONS" ]; then
      sudo sh -c "kind completion zsh > $ZSH_COMPLETIONS/_kind"
    fi
  fi
}


tools_check_kubectl() {
  if tools_install_app "kubectl"; then
    os="$(uname | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    esac
    url="https://dl.k8s.io/release/v$KUBECTL_VERSION/bin/$os/$arch/kubectl"
    [ -d /usr/local/bin ] || sudo mkdir /usr/local/bin
    tmp_dir="$(mktemp -d)"
    curl -fsSL -o "$tmp_dir/kubectl" "$url"
    sudo install "$tmp_dir/kubectl" /usr/local/bin/
    rm -rf "$tmp_dir"
    kubectl version --client --output=yaml
    if [ -d "$BASH_COMPLETION" ]; then
      sudo sh -c "kubectl completion bash > $BASH_COMPLETION/kubectl"
    fi
    if [ -d "$ZSH_COMPLETIONS" ]; then
      sudo sh -c "kubectl completion zsh > $ZSH_COMPLETIONS/_kubectl"
    fi
  fi
}

tools_check_tmpl() {
  if tools_install_app "tmpl"; then
    tmp_dir="$(mktemp -d)"
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    case "$(uname -m)" in
    x86_64) arch="amd64" ;;
    esac
    url="https://github.com/krakozaure/tmpl/releases/download"
    url="$url/${TMPL_VERSION}/tmpl-linux_$arch"
    curl -fsSL -o "$tmp_dir/tmpl" "$url"
    sudo install "$tmp_dir/tmpl" /usr/local/bin
    rm -rf "$tmp_dir"
  fi
}
tools_check() {
  for _app in "$@"; do
    case "$_app" in
    cilium) tools_check_cilium;;
    docker) tools_check_docker ;;
    helm) tools_check_helm ;;
    k3d) tools_check_k3d ;;
    kind) tools_check_kind ;;
    kubectl) tools_check_kubectl ;;
    hubble) tools_check_hubble;;
    tmpl) tools_check_tmpl ;;
    *) echo "Unknown application '$_app'" ;;
    esac
  done
}

tools_apps_list() {
  tools="cilium docker helm k3d kind kubectl hubble tmpl"
  echo "$tools"
}

# Usage function
usage() {
  cat <<EOF
Command to check and install tools used by our scripts.

Usage:

  $(basename "$0") apps|SPACE_SEPARATED_LIST_OF_TOOLS

Where the SPACE_SEPARATED_LIST_OF_TOOLS can include the following apps:

$(for tool in $(tools_apps_list); do echo "- $tool"; done)

EOF
  exit "$1"
}

# ----
# MAIN
# ----

# shellcheck disable=SC2046
case "$1" in
"") usage 0 ;;
apps) tools_check $(tools_apps_list) ;;
*) tools_check "$@" ;;
esac

# ----
# vim: ts=2:sw=2:et:ai:sts=2
