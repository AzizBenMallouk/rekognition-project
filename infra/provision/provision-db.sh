#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/provision/provision-db.sh ec2-user@UPLOAD_IP ec2-user@DB_PRIV_IP DB_NAME DB_USER DB_PASS

BASTION_HOST="${1:?Usage: provision-db.sh ec2-user@UPLOAD_IP ec2-user@DB_PRIV_IP DB_NAME DB_USER DB_PASS}"
DB_HOST="${2:?Missing DB host (ec2-user@10.0.x.x)}"
DB_NAME="${3:-rekognition_db}"
DB_USER="${4:-appuser}"
DB_PASS="${5:-SuperSecret123!}"

# ⚠️ DB_PASS sans guillemets chelous de préférence (pas de ' ni " pour simplifier)

ssh -o StrictHostKeyChecking=no -J "$BASTION_HOST" "$DB_HOST" << EOF
set -eo pipefail

echo "=== [db] System update ==="
sudo dnf update -y

echo "=== [db] Install MariaDB server ==="
sudo dnf install -y mariadb105-server

sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "=== [db] Configure MariaDB users & DB ==="

# On NE TOUCHE PAS root. On utilise sudo mysql (auth socket) pour tout faire.

sudo mysql -e "CREATE DATABASE IF NOT EXISTS \\\`${DB_NAME}\\\\\`"
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}'"
sudo mysql -e "GRANT ALL PRIVILEGES ON \\\`${DB_NAME}\\\\\`.* TO '${DB_USER}'@'%'"
sudo mysql -e "FLUSH PRIVILEGES"

echo "=== [db] Create uploads table if not exists ==="

sudo mysql "${DB_NAME}" -e "
CREATE TABLE IF NOT EXISTS uploads (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key TEXT NOT NULL,
  rekognition_faces JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"

echo "=== [db] Done ==="
EOF
