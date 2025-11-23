#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/provision/provision-search-web.sh ec2-user@PUBLIC_IP [REPO_URL] [BRANCH_NAME]

HOST="${1:?Usage: provision-search-web.sh ec2-user@PUBLIC_IP}"
REPO_URL="${2:-https://github.com/AzizBenMallouk/rekognition-project.git}"
BRANCH_NAME="${3:-main}"

# Ces variables viennent de l'environnement du runner (GitHub Actions)
AWS_REGION_VAR="${AWS_REGION:-us-east-1}"
SEARCH_BUCKET_VAR="${SEARCH_BUCKET:-}"

ssh -o StrictHostKeyChecking=no "$HOST" << EOF
set -eux

echo "=== [search-web] System update ==="
sudo dnf update -y

echo "=== [search-web] Install git & Node.js 18 ==="
sudo dnf install -y git

curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo dnf install -y nodejs

node -v
npm -v

echo "=== [search-web] Prepare /var/www ==="
sudo mkdir -p /var/www
sudo chown -R ec2-user:ec2-user /var/www

cd /var/www

if [ ! -d rekognition-project ]; then
  git clone "$REPO_URL" rekognition-project
fi

cd rekognition-project

# 🔐 Dire à Git que ce repo est safe pour cet utilisateur
git config --global --add safe.directory /var/www/rekognition-project

git fetch origin
git checkout "$BRANCH_NAME"
git pull origin "$BRANCH_NAME"

echo "=== [search-web] npm install ==="
cd apps/search-web
npm install

echo "=== [search-web] Creating .env ==="
cat > .env << ENVFILE
AWS_REGION=${AWS_REGION_VAR}
SEARCH_BUCKET=${SEARCH_BUCKET_VAR}
PORT=3000
ENVFILE

echo "=== [search-web] .env content ==="
cat .env

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
