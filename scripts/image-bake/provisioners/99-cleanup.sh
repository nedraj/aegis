#!/usr/bin/env bash
# 99-cleanup.sh - Minimize image size and remove build artifacts
set -euo pipefail

echo "=== [5/5] Aegis Golden Image - Cleanup ==="

apt-get autoremove -y
apt-get clean
rm -rf /var/lib/apt/lists/*

# Remove packer SSH key artifacts if present
rm -f /home/packer/.ssh/authorized_keys || true

# Clear logs
journalctl --vacuum-time=1d || true

echo "Golden image cleanup complete. Image is ready for export."
