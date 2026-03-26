#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/log/startup_already_done_hw5_forbidden"
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
SUBSCRIPTION_ID="$(fetch_metadata SUBSCRIPTION_ID)"
BUCKET_NAME="$(fetch_metadata BUCKET_NAME)"
LOG_OBJECT="$(fetch_metadata LOG_OBJECT)"

fetch_metadata APP_SERVICE2_PY > /opt/hw5/app/service2_subscriber.py

python3 -m venv /opt/hw5/venv
/opt/hw5/venv/bin/pip install --upgrade pip
/opt/hw5/venv/bin/pip install google-cloud-storage==2.19.0 google-cloud-pubsub==2.28.0

cat > /etc/systemd/system/hw5-forbidden.service <<EOF
[Unit]
Description=HW5 Service2
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/hw5/app
Environment=GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
Environment=SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
Environment=BUCKET_NAME=${BUCKET_NAME}
Environment=LOG_OBJECT=${LOG_OBJECT}
ExecStart=/opt/hw5/venv/bin/python /opt/hw5/app/service2_subscriber.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw5-forbidden
systemctl restart hw5-forbidden

touch "$LOCK_FILE"
