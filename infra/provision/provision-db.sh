#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/provision/provision-db.sh ec2-user@UPLOAD_IP ec2-user@DB_PRIV_IP DB_NAME DB_USER DB_PASS

BASTION_HOST="${1:?Usage: provision-db.sh ec2-user@UPLOAD_IP ec2-user@DB_PRIV_IP DB_NAME DB_USER DB_PASS}"
DB_HOST="${2:?Missing DB host (ec2-user@10.0.x.x)}"
DB_NAME="${3:-rekognition_db}"
DB_USER="${4:-appuser}"
DB_PASS="${5:-SuperSecret123!}"

# ⚠️ Hypothèse : DB_PASS ne contient pas de ' ou " (sinon il faudra encore plus d’échappements)

ssh -o StrictHostKeyChecking=no -J "$BASTION_HOST" "$DB_HOST" << EOF
set -euo pipefail

echo "=== [db] System update ==="
sudo dnf update -y

echo "=== [db] Install MariaDB server ==="
sudo dnf install -y mariadb105-server

sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "=== [db] Configure MariaDB users & DB (using root + password) ==="

# 👉 IMPORTANT :
# On suppose que le mot de passe actuel de root est DB_PASS (déjà set dans un run précédent).
# On se connecte donc en root avec ce mot de passe.
sudo mysql -u root -p'${DB_PASS}' <<SQL
CREATE DATABASE IF NOT EXISTS ${DB_NAME};
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
SQL

echo "=== [db] Create uploads table if not exists ==="

sudo mysql -u root -p'${DB_PASS}' ${DB_NAME} <<SQL2
CREATE TABLE IF NOT EXISTS uploads (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key TEXT NOT NULL,
  rekognition_faces JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL2

echo "=== [db] Done ==="
EOF
