#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/provision/provision-db.sh ec2-user@UPLOAD_PUBLIC_IP ec2-user@DB_PRIVATE_IP DB_NAME DB_USER DB_PASS

BASTION_HOST="${1:?Usage: provision-db.sh ec2-user@UPLOAD_IP ec2-user@DB_PRIV_IP DB_NAME DB_USER DB_PASS}"
DB_HOST="${2:?Missing DB host (ec2-user@10.0.x.x)}"
DB_NAME="${3:-rekognition_db}"
DB_USER="${4:-appuser}"
DB_PASS="${5:-SuperSecret123!}"

# On utilise ProxyJump pour ne pas copier la clé privée sur l'EC2
ssh -o StrictHostKeyChecking=no -J "$BASTION_HOST" "$DB_HOST" << EOF
set -eux

echo "=== [db] System update ==="
sudo dnf update -y

echo "=== [db] Install MariaDB server ==="
sudo dnf install -y mariadb105-server

sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "=== [db] Configure MariaDB users & DB ==="
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}'"
mysql -uroot -p'${DB_PASS}' -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"
mysql -uroot -p'${DB_PASS}' -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}'"
mysql -uroot -p'${DB_PASS}' -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%'"
mysql -uroot -p'${DB_PASS}' -e "FLUSH PRIVILEGES"

echo "=== [db] Create uploads table if not exists ==="
mysql -u'${DB_USER}' -p'${DB_PASS}' '${DB_NAME}' <<'SQL'
CREATE TABLE IF NOT EXISTS uploads(
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key TEXT NOT NULL,
  rekognition_faces JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
SQL

echo "=== [db] Done ==="
EOF
