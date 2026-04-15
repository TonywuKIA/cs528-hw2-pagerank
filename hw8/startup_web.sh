#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/log/startup_already_done_hw8_server"
if [ -f "$LOCK_FILE" ]; then
  echo "Startup script already ran once. Skipping."
  exit 0
fi

apt-get update -y
apt-get install -y python3-venv python3-pip curl

mkdir -p /opt/hw8/service1

if [ ! -d /opt/hw8/venv ]; then
  python3 -m venv /opt/hw8/venv
fi

/opt/hw8/venv/bin/pip install --upgrade pip
/opt/hw8/venv/bin/pip install google-cloud-storage==2.19.0 google-cloud-pubsub==2.28.0

SERVER_PY_B64="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/SERVER_PY_B64")"
printf '%s' "${SERVER_PY_B64}" | base64 -d > /opt/hw8/service1/server.py
chmod 0644 /opt/hw8/service1/server.py

PROJECT_ID="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")"
BUCKET_NAME="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/BUCKET_NAME")"
TOPIC_ID="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/TOPIC_ID")"
BUILD_ID="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/BUILD_ID")"
ZONE_PATH="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/zone")"
ZONE_NAME="${ZONE_PATH##*/}"
INSTANCE_NAME="$(curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/name")"

cat > /etc/systemd/system/hw8-server.service <<EOF
[Unit]
Description=HW8 Service1
After=network.target

[Service]
Type=simple
Environment=GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
Environment=BUCKET_NAME=${BUCKET_NAME}
Environment=TOPIC_ID=${TOPIC_ID}
Environment=BUILD_ID=${BUILD_ID}
Environment=ZONE=${ZONE_NAME}
Environment=INSTANCE_NAME=${INSTANCE_NAME}
Environment=PORT=80
ExecStart=/opt/hw8/venv/bin/python /opt/hw8/service1/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw8-server
systemctl restart hw8-server

touch "$LOCK_FILE"
