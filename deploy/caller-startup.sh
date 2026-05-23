#!/usr/bin/env bash
# =============================================================================
# rehan-caller startup script
# Installs Node.js, runs TypeScript caller worker
# =============================================================================

set -euo pipefail

ENGINE_IP="${ENGINE_IP:-192.168.1.3}"
ENGINE_URL="ws://${ENGINE_IP}:49134"

apt-get update -y
apt-get install -y git curl

curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

git clone https://github.com/Alchemyst-ai/hiring.git /opt/alchemyst
WORKER_DIR=/opt/alchemyst/may-2026/devops/quickstart/workers/caller-worker

cd "$WORKER_DIR"
npm install

cat > /etc/systemd/system/rehan-caller.service <<EOF
[Unit]
Description=Alchemyst Caller Worker (TypeScript HTTP trigger)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORKER_DIR}
ExecStart=/usr/bin/npm run dev
Restart=on-failure
RestartSec=5
Environment="III_URL=${ENGINE_URL}"
Environment="PATH=/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rehan-caller
systemctl start rehan-caller

echo "Caller worker started → connected to engine at ${ENGINE_URL}"
