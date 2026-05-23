#!/usr/bin/env bash
# =============================================================================
# rehan-inference startup script
# Sets up Python venv, installs deps, runs Gemma inference worker
# =============================================================================

set -euo pipefail

ENGINE_IP="${ENGINE_IP:-192.168.1.3}"
ENGINE_URL="ws://${ENGINE_IP}:49134"

apt-get update -y
apt-get install -y python3 python3-pip python3-venv git curl

# Install Node.js (needed for iii CLI)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Clone assignment repo
git clone https://github.com/Alchemyst-ai/hiring.git /opt/alchemyst
WORKER_DIR=/opt/alchemyst/may-2026/devops/quickstart/workers/inference-worker

# Isolated virtualenv
python3 -m venv /opt/inference-venv
source /opt/inference-venv/bin/activate

pip install --upgrade pip
pip install iii-sdk watchfiles transformers accelerate gguf
# CPU-only torch — no GPU needed for Gemma 270M
pip install torch --index-url https://download.pytorch.org/whl/cpu

cat > /etc/systemd/system/rehan-inference.service <<EOF
[Unit]
Description=Alchemyst Inference Worker (Gemma 3 270M)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${WORKER_DIR}
ExecStart=/opt/inference-venv/bin/python3 inference_worker.py
Restart=on-failure
RestartSec=15
Environment="III_URL=${ENGINE_URL}"
Environment="PATH=/opt/inference-venv/bin:/usr/local/bin:/usr/bin:/bin"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rehan-inference
systemctl start rehan-inference

echo "Inference worker started → connected to engine at ${ENGINE_URL}"
