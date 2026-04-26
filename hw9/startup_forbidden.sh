#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/log/startup_already_done_hw9_forbidden"
if [ -f "${LOCK_FILE}" ]; then
  echo "Startup script already ran once. Skipping."
  exit 0
fi

apt-get update -y
apt-get install -y python3-venv python3-pip curl

mkdir -p /opt/hw9/service2
python3 -m venv /opt/hw9/venv
/opt/hw9/venv/bin/pip install --upgrade pip
/opt/hw9/venv/bin/pip install google-cloud-storage==2.19.0 google-cloud-pubsub==2.28.0

metadata() {
  curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/$1"
}

PROJECT_ID="$(metadata project/project-id)"
SUBSCRIPTION_ID="$(metadata instance/attributes/SUBSCRIPTION_ID)"
BUCKET_NAME="$(metadata instance/attributes/BUCKET_NAME)"
LOG_OBJECT="$(metadata instance/attributes/LOG_OBJECT)"
SUBSCRIBER_PY_B64="$(metadata instance/attributes/SUBSCRIBER_PY_B64)"

printf '%s' "${SUBSCRIBER_PY_B64}" | base64 -d > /opt/hw9/service2/subscriber.py

cat > /etc/systemd/system/hw9-forbidden.service <<EOF
[Unit]
Description=HW9 Forbidden Country Subscriber
After=network.target

[Service]
Type=simple
Environment=GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
Environment=SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
Environment=BUCKET_NAME=${BUCKET_NAME}
Environment=LOG_OBJECT=${LOG_OBJECT}
ExecStart=/opt/hw9/venv/bin/python /opt/hw9/service2/subscriber.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw9-forbidden
systemctl restart hw9-forbidden

touch "${LOCK_FILE}"
