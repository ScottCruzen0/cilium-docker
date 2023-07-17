#!/bin/sh
# ----
# File:        k3d-entrypoint-cilium.sh
# Description: Script to be run on k3d clusters to be able to use cilium
# Author:      Sergio Talens-Oliag <sto@mixinet.net>
# Copyright:   (c) 2023 Sergio Talens-Oliag <sto@mixinet.net>
# ----

set -e

echo "Mounting bpf on node"
mount bpffs -t bpf /sys/fs/bpf
mount --make-shared /sys/fs/bpf

echo "Mounting cgroups v2 to /run/cilium/cgroupv2 on node"
mkdir -p /run/cilium/cgroupv2
mount -t cgroup2 none /run/cilium/cgroupv2
mount --make-shared /run/cilium/cgroupv2/
