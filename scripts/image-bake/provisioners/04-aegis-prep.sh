#!/usr/bin/env bash
# 04-aegis-prep.sh - Aegis-specific directories and helper user
set -euo pipefail

echo "=== [4/5] Aegis Golden Image - Aegis preparation ==="

# Create dedicated aegis user (for future least-privilege work)
useradd -m -s /bin/bash -G sudo aegis || true
echo "aegis ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/aegis

# Prepare mount point for the large bundle disk (used in Pulumi)
mkdir -p /opt/aegis
chown -R aegis:aegis /opt/aegis || true

# Add useful aliases for the operator
cat >> /home/aegis/.bashrc << 'EOF'
alias k='kubectl'
alias aegis-logs='journalctl -u k3s -f'
alias aegis-validate='/opt/aegis/scripts/validate.sh'
EOF

echo "Aegis user and directories prepared."
