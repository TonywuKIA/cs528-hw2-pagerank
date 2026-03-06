#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/log/startup_already_done_hw4_forbidden"
if [ -f "$LOCK_FILE" ]; then
  echo "Startup script already ran once. Skipping."
  exit 0
fi

apt-get update -y
apt-get install -y python3-venv python3-pip curl

mkdir -p /opt/hw4/service2

if [ ! -d /opt/hw4/venv ]; then
  python3 -m venv /opt/hw4/venv
fi

/opt/hw4/venv/bin/pip install --upgrade pip
/opt/hw4/venv/bin/pip install google-cloud-storage==2.19.0 google-cloud-pubsub==2.28.0

cat > /opt/hw4/service2/subscriber.py <<'PY'
import json
import os
import signal
import threading
from datetime import datetime, timezone

from google.api_core.exceptions import NotFound
from google.cloud import pubsub_v1
from google.cloud import storage

PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCP_PROJECT")
SUBSCRIPTION_ID = os.environ.get("SUBSCRIPTION_ID", "hw3-sub")
BUCKET_NAME = os.environ.get("BUCKET_NAME", "cs528-hw2-chunyu")
LOG_OBJECT = os.environ.get("LOG_OBJECT", "forbidden/forbidden_requests.log")

storage_client = storage.Client()
subscriber = pubsub_v1.SubscriberClient()
stop_event = threading.Event()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def log_struct(**kwargs) -> None:
    print(json.dumps(kwargs, ensure_ascii=False), flush=True)


def append_line_to_gcs(line: str) -> None:
    bucket = storage_client.bucket(BUCKET_NAME)
    blob = bucket.blob(LOG_OBJECT)
    try:
        existing = blob.download_as_text()
    except NotFound:
        existing = ""
    updated = existing + ("" if existing == "" or existing.endswith("\n") else "\n") + line + "\n"
    blob.upload_from_string(updated, content_type="text/plain; charset=utf-8")


def callback(message):
    try:
        payload = json.loads(message.data.decode("utf-8"))
        country = payload.get("country", "")
        file_name = payload.get("file", "")
        line_obj = {
            "received_at_utc": utc_now(),
            "country": country,
            "file": file_name,
            "method": payload.get("http_method", ""),
            "path": payload.get("path", ""),
            "remote_addr": payload.get("remote_addr", ""),
            "build_id": payload.get("build_id", ""),
        }
        line = json.dumps(line_obj, ensure_ascii=False)
        print(f"FORBIDDEN request: country={country} file={file_name}", flush=True)
        append_line_to_gcs(line)
        log_struct(severity="INFO", msg="forbidden_logged", event=line_obj)
        message.ack()
    except Exception as e:
        log_struct(severity="ERROR", msg="callback_failed", error=str(e))
        message.nack()


def main() -> int:
    if not PROJECT_ID:
        print("Missing GOOGLE_CLOUD_PROJECT/GCP_PROJECT", flush=True)
        return 1

    subscription_path = subscriber.subscription_path(PROJECT_ID, SUBSCRIPTION_ID)
    log_struct(
        severity="INFO",
        msg="subscriber_start",
        project_id=PROJECT_ID,
        subscription_path=subscription_path,
        bucket_name=BUCKET_NAME,
        log_object=LOG_OBJECT,
    )

    streaming_future = subscriber.subscribe(subscription_path, callback=callback)

    def _stop(signum, _frame):
        log_struct(severity="INFO", msg="signal_received", signum=signum)
        stop_event.set()
        streaming_future.cancel()

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    try:
        while not stop_event.is_set():
            stop_event.wait(1)
    finally:
        streaming_future.cancel()
        subscriber.close()
        log_struct(severity="INFO", msg="subscriber_stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")
SUBSCRIPTION_ID=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/SUBSCRIPTION_ID")
BUCKET_NAME=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/BUCKET_NAME")
LOG_OBJECT=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/LOG_OBJECT")

cat > /etc/systemd/system/hw4-forbidden.service <<EOF
[Unit]
Description=HW4 Service2
After=network.target

[Service]
Type=simple
Environment=GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
Environment=SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
Environment=BUCKET_NAME=${BUCKET_NAME}
Environment=LOG_OBJECT=${LOG_OBJECT}
ExecStart=/opt/hw4/venv/bin/python /opt/hw4/service2/subscriber.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw4-forbidden
systemctl restart hw4-forbidden

touch "$LOCK_FILE"
