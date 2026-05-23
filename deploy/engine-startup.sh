#!/usr/bin/env bash
# =============================================================================
# rehan-engine startup script
# Installs iii engine and runs it as a systemd service
# =============================================================================

set -euo pipefail

apt-get update -y
apt-get install -y curl jq

# Install iii
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

mkdir -p /opt/alchemyst

cat > /etc/systemd/system/iii-engine.service <<EOF
[Unit]
Description=iii Process Communication Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/alchemyst
ExecStart=/root/.local/bin/iii --use-default-config
Restart=on-failure
RestartSec=5
Environment="PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable iii-engine
systemctl start iii-engine

INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo "iii engine running at ws://${INTERNAL_IP}:49134"
echo "HTTP API at http://${INTERNAL_IP}:3111"
