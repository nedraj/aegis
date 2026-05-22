#!/usr/bin/env bash
# 03-install-k3s.sh - Pre-install K3s on the golden image
set -euo pipefail

echo "=== [3/5] Aegis Golden Image - K3s Installation ==="

# Install K3s (we will run it in airgap mode later; here we just install the binary + service)
curl -sfL https://get.k3s.io | INSTALL_K3S_SKIP_START=true sh -

# Create the airgap images directory (where we will later drop tars from the bundle)
mkdir -p /var/lib/rancher/k3s/agent/images

# Pre-create the aegis namespace expectation
mkdir -p /opt/aegis/{models,manifests,scripts,images,logs}

# Make kubectl available for the default user after boot
ln -sf /usr/local/bin/kubectl /usr/local/bin/k 2>/dev/null || true

echo "K3s installed (will be started by bootstrap after bundle is present)."
systemctl disable k3s || true   # we control startup via bootstrap.sh
