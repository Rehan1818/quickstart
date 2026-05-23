#!/usr/bin/env bash
# =============================================================================
# rehan-gateway startup script
# nginx reverse proxy — only VM with a public IP
# Forwards :3111 traffic to the iii engine on engine-vm
# =============================================================================

set -euo pipefail

ENGINE_IP="${ENGINE_IP:-192.168.1.3}"

apt-get update -y
apt-get install -y nginx curl

cat > /etc/nginx/sites-available/alchemyst-api <<EOF
server {
    listen 3111;
    server_name _;

    # Health check endpoint
    location /health {
        return 200 '{"status":"ok"}';
        add_header Content-Type application/json;
    }

    # Forward all API traffic to the engine
    location / {
        proxy_pass http://${ENGINE_IP}:3111;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_connect_timeout 10s;
        proxy_send_timeout 300s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/alchemyst-api /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl enable nginx && systemctl restart nginx

PUBLIC_IP=$(curl -s ifconfig.me)
echo "Gateway ready at http://${PUBLIC_IP}:3111"
echo "Forwarding to engine at http://${ENGINE_IP}:3111"
