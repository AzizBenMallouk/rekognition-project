#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/provision/provision-upload-web.sh ec2-user@PUBLIC_IP

HOST="${1:?Usage: provision-upload-web.sh ec2-user@PUBLIC_IP}"
REPO_URL="${2:-https://github.com/AzizBenMallouk/rekognition-project.git}"
BRANCH_NAME="${3:-main}"

ssh -o StrictHostKeyChecking=no "$HOST" << EOF
set -eux

echo "=== [upload-web] System update ==="
sudo dnf update -y

echo "=== [upload-web] Install packages ==="
sudo dnf install -y git nginx php-cli php-fpm php-json php-mbstring php-mysqlnd curl

sudo systemctl enable php-fpm
sudo systemctl start php-fpm
sudo systemctl enable nginx
sudo systemctl start nginx

echo "=== [upload-web] Prepare /var/www ==="
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

echo "=== [upload-web] Composer install ==="
cd apps/upload-web

if ! command -v composer >/dev/null 2>&1; then
  php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
  php composer-setup.php --install-dir=/usr/local/bin --filename=composer
fi

composer install --no-dev --prefer-dist

echo "=== [upload-web] Configure nginx ==="
sudo bash -c 'cat >/etc/nginx/nginx.conf' << "NGINXCONF"
user nginx;
worker_processes auto;

error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    sendfile on;

    server {
        listen 80;
        server_name _;

        root /var/www/rekognition-project/apps/upload-web/public;
        index index.php index.html;

        location / {
            try_files $uri /index.php?$query_string;
        }

        location ~ \.php$ {
            fastcgi_pass unix:/run/php-fpm/www.sock;
            fastcgi_index index.php;
            include fastcgi_params;
            fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        }
    }
}
NGINXCONF

sudo nginx -t
sudo systemctl restart nginx

echo "=== [upload-web] Done ==="
EOF
