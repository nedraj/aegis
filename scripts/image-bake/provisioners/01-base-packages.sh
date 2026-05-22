#!/usr/bin/env bash
# 01-base-packages.sh - Phase 4 Golden Image Provisioner
set -euo pipefail

echo "=== [1/5] Aegis Golden Image - Base packages ==="

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y \
  curl wget gnupg lsb-release ca-certificates \
  software-properties-common apt-transport-https \
  build-essential dkms linux-headers-$(uname -r) \
  jq unzip

# Enable universe + multiverse for NVIDIA bits
add-apt-repository -y universe
apt-get update -y

echo "Base packages installed successfully."
