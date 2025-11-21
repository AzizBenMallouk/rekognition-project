#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/provision/provision-search-web.sh ec2-user@PUBLIC_IP

HOST="${1:?Usage: provision-search-web.sh ec2-user@PUBLIC_IP}"
REPO_URL="${2:-https://github.com/AzizBenMallouk/rekognition-project.git}"
BRANCH_NAME="${3:-main}"

ssh -o StrictHostKeyChecking=no "$HOST" << EOF
set -eux

echo "=== [search-web] System update ==="
sudo dnf update -y

echo "=== [search-web] Install git & Node.js 18 ==="
sudo dnf install -y git curl
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo dnf install -y nodejs

node -v
npm -v

echo "=== [search-web] Prepare /var/www ==="
if [ ! -d /var/www ]; then
  sudo mkdir -p /var/www
  sudo chown ec2-user:ec2-user /var/www
fi

cd /var/www

if [ ! -d rekognition-project ]; then
  git clone "$REPO_URL" rekognition-project
fi

cd rekognition-project
git fetch origin
git checkout "$BRANCH_NAME"
git pull origin "$BRANCH_NAME"

cd apps/search-web
npm install

echo "=== [search-web] Configure systemd service ==="
sudo bash -c 'cat >/etc/systemd/system/search-web.service' << "SERVICE"
[Unit]
Description=Search Web Node App
After=network.target

[Service]
WorkingDirectory=/var/www/rekognition-project/apps/search-web
ExecStart=/usr/bin/node server.js
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable search-web
sudo systemctl restart search-web

echo "=== [search-web] Done ==="
EOF
