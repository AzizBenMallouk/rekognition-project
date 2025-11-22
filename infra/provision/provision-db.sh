#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./infra/provision/provision-db.sh IP_UPLOAD_WEB IP_DB DB_NAME DB_USER DB_PASS

UPLOAD_WEB="${1:?Missing upload-web public IP}"
DB_IP="${2:?Missing DB private IP}"
DB_NAME="${3:-rekognition_db}"
DB_USER="${4:-appuser}"
DB_PASS="${5:-StrongPass123!}"

echo "=== [LOCAL] Testing SSH to upload-web (${UPLOAD_WEB}) ==="
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ec2-user@${UPLOAD_WEB}" "echo '[upload-web] SSH OK'"

echo "=== [LOCAL] SSH into upload-web and test DB connection ==="
ssh -o StrictHostKeyChecking=no "ec2-user@${UPLOAD_WEB}" << EOF
set -eo pipefail

echo "=== [upload-web] Testing SSH to DB (${DB_IP}) ==="
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "ec2-user@${DB_IP}" "echo '[db] SSH OK'"

echo "=== [upload-web] Start provisioning DB ==="
ssh -o StrictHostKeyChecking=no "ec2-user@${DB_IP}" << INNER
set -eo pipefail

echo "=== [db] Install MariaDB ==="
sudo dnf update -y
sudo dnf install -y mariadb105-server

sudo systemctl enable mariadb
sudo systemctl start mariadb

echo "=== [db] Create database and user ==="
sudo mysql -e "CREATE DATABASE IF NOT EXISTS \\\`${DB_NAME}\\\\\`"
sudo mysql -e "CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}'"
sudo mysql -e "GRANT ALL PRIVILEGES ON \\\`${DB_NAME}\\\\\`.* TO '${DB_USER}'@'%'"
sudo mysql -e "FLUSH PRIVILEGES"

echo "=== [db] Create uploads table ==="
sudo mysql "${DB_NAME}" -e "
CREATE TABLE IF NOT EXISTS uploads (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  s3_bucket VARCHAR(255) NOT NULL,
  s3_key TEXT NOT NULL,
  rekognition_faces JSON NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
"

echo "=== [db] Provision complete ==="
INNER

EOF

echo "=== All good : DB provisioned successfully ==="
