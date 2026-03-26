#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/log/startup_already_done_hw5_server"
if [ -f "$LOCK_FILE" ]; then
  echo "Startup script already ran once. Skipping."
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3-venv python3-pip curl

mkdir -p /opt/hw5/app

fetch_metadata() {
  local key="$1"
  curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}"
}

PROJECT_ID="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")"
BUCKET_NAME="$(fetch_metadata BUCKET_NAME)"
TOPIC_ID="$(fetch_metadata TOPIC_ID)"
BUILD_ID="$(fetch_metadata BUILD_ID)"
DB_INSTANCE_CONNECTION_NAME="$(fetch_metadata DB_INSTANCE_CONNECTION_NAME)"
DB_HOST="$(fetch_metadata DB_HOST)"
DB_NAME="$(fetch_metadata DB_NAME)"
DB_USER="$(fetch_metadata DB_USER)"
DB_PASS="$(fetch_metadata DB_PASS)"

fetch_metadata APP_DB_PY > /opt/hw5/app/db.py
fetch_metadata APP_SERVICE1_PY > /opt/hw5/app/service1_server.py
fetch_metadata APP_QUERY_STATS_PY > /opt/hw5/app/query_stats.py

python3 -m venv /opt/hw5/venv
/opt/hw5/venv/bin/pip install --upgrade pip
/opt/hw5/venv/bin/pip install google-cloud-storage==2.19.0 google-cloud-pubsub==2.28.0 "cloud-sql-python-connector[pg8000]==1.18.2" "pg8000==1.31.2"

cat > /etc/systemd/system/hw5-server.service <<EOF
[Unit]
Description=HW5 Service1
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/hw5/app
Environment=GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
Environment=BUCKET_NAME=${BUCKET_NAME}
Environment=TOPIC_ID=${TOPIC_ID}
Environment=BUILD_ID=${BUILD_ID}
Environment=PORT=80
Environment=DB_INSTANCE_CONNECTION_NAME=${DB_INSTANCE_CONNECTION_NAME}
Environment=DB_HOST=${DB_HOST}
Environment=DB_PORT=5432
Environment=DB_NAME=${DB_NAME}
Environment=DB_USER=${DB_USER}
Environment=DB_PASS=${DB_PASS}
ExecStart=/opt/hw5/venv/bin/python /opt/hw5/app/service1_server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw5-server
systemctl restart hw5-server

touch "$LOCK_FILE"
