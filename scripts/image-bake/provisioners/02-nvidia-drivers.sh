#!/usr/bin/env bash
# 02-nvidia-drivers.sh - Install NVIDIA drivers + CUDA + Container Toolkit
# This is the step that normally requires internet on first boot.
set -euo pipefail

echo "=== [2/5] Aegis Golden Image - NVIDIA Drivers + CUDA ==="

# Add NVIDIA Container Toolkit repo
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

apt-get update -y

# Install NVIDIA driver for T4 (535 server branch is stable on 22.04 + GCP)
apt-get install -y \
  nvidia-driver-535-server \
  nvidia-utils-535-server \
  nvidia-container-toolkit

# Configure NVIDIA runtime for containerd / Docker
nvidia-ctk runtime configure --runtime=containerd || true

# Enable persistence mode (good for inference workloads)
nvidia-persistenced || true

# Verify
nvidia-smi --query-gpu=name,driver_version --format=csv

echo "NVIDIA drivers and container toolkit installed."
