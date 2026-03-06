#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/log/startup_already_done_hw4_server"
if [ -f "$LOCK_FILE" ]; then
  echo "Startup script already ran once. Skipping."
  exit 0
fi

apt-get update -y
apt-get install -y python3-venv python3-pip curl

mkdir -p /opt/hw4/service1

if [ ! -d /opt/hw4/venv ]; then
  python3 -m venv /opt/hw4/venv
fi

/opt/hw4/venv/bin/pip install --upgrade pip
/opt/hw4/venv/bin/pip install google-cloud-storage==2.19.0 google-cloud-pubsub==2.28.0

cat > /opt/hw4/service1/server.py <<'PY'
import json
import os
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from google.api_core.exceptions import NotFound
from google.cloud import pubsub_v1
from google.cloud import storage


BUCKET_NAME = os.environ.get("BUCKET_NAME", "cs528-hw2-chunyu")
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCP_PROJECT")
TOPIC_ID = os.environ.get("TOPIC_ID", "hw3-forbidden-topic")
BUILD_ID = os.environ.get("BUILD_ID", "hw4-vm")
PORT = int(os.environ.get("PORT", "80"))

FORBIDDEN_LOWER = {
    "north korea",
    "iran",
    "cuba",
    "myanmar",
    "iraq",
    "libya",
    "sudan",
    "zimbabwe",
    "syria",
}

storage_client = storage.Client()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def log_struct(**kwargs) -> None:
    print(json.dumps(kwargs, ensure_ascii=False), flush=True)


def publish_forbidden_event(event: dict) -> tuple[bool, str]:
    if not PROJECT_ID:
        return False, "PROJECT_ID missing"
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)
    try:
        future = publisher.publish(topic_path, json.dumps(event, ensure_ascii=False).encode("utf-8"))
        message_id = future.result(timeout=5)
        return True, f"message_id={message_id}"
    except Exception as e:
        return False, str(e)


def resolve_filename(path: str, query: str) -> str:
    qs = parse_qs(query)
    if "file" in qs and qs["file"]:
        return qs["file"][0]

    parts = [p for p in path.split("/") if p]
    if parts:
        candidate = parts[-1]
        if candidate.lower().endswith(".html"):
            return candidate
    return ""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _write(self, body: str, status: int, content_type: str = "text/html; charset=utf-8") -> None:
        body_bytes = body.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body_bytes)))
        self.end_headers()
        self.wfile.write(body_bytes)

    def _country_header(self) -> str:
        for k, v in self.headers.items():
            if k.lower() == "x-country":
                return (v or "").strip()
        return ""

    def _remote_addr(self) -> str:
        return self.client_address[0] if self.client_address else ""

    def _handle_get(self) -> None:
        parsed = urlparse(self.path)
        filename = resolve_filename(parsed.path, parsed.query)
        if not filename:
            log_struct(severity="WARNING", status=400, msg="Missing file parameter")
            self._write("Missing file parameter", 400)
            return

        country = self._country_header()
        country_lower = country.lower()

        if country_lower in FORBIDDEN_LOWER:
            event = {
                "timestamp_utc": utc_now(),
                "country": country,
                "file": filename,
                "http_method": "GET",
                "path": parsed.path,
                "query_string": parsed.query,
                "remote_addr": self._remote_addr(),
                "build_id": BUILD_ID,
            }
            ok, detail = publish_forbidden_event(event)
            log_struct(
                severity="CRITICAL",
                status=400,
                msg="Forbidden country",
                country=country,
                file=filename,
                publish_ok=ok,
                publish_detail=detail,
            )
            self._write("Permission denied", 400)
            return

        try:
            bucket = storage_client.bucket(BUCKET_NAME)
            blob = bucket.blob(filename)
            content = blob.download_as_text()
            log_struct(severity="INFO", status=200, file=filename, msg="File served")
            self._write(content, 200)
        except NotFound:
            log_struct(severity="WARNING", status=404, file=filename, msg="File not found")
            self._write("Not found", 404)
        except Exception as e:
            log_struct(severity="ERROR", status=500, msg="Internal error", error=str(e))
            self._write("Internal error", 500)

    def do_GET(self) -> None:
        self._handle_get()

    def do_POST(self) -> None:
        self._method_not_implemented()

    def do_PUT(self) -> None:
        self._method_not_implemented()

    def do_DELETE(self) -> None:
        self._method_not_implemented()

    def do_HEAD(self) -> None:
        self._method_not_implemented()

    def do_OPTIONS(self) -> None:
        self._method_not_implemented()

    def do_PATCH(self) -> None:
        self._method_not_implemented()

    def _method_not_implemented(self) -> None:
        log_struct(severity="WARNING", status=501, method=self.command, msg="Method not implemented")
        self._write("Method not implemented", 501)

    def log_message(self, fmt: str, *args) -> None:
        log_struct(severity="INFO", msg="http_access", method=self.command, path=self.path, detail=fmt % args)


def main() -> None:
    log_struct(severity="INFO", msg="server_start", port=PORT, bucket=BUCKET_NAME, topic=TOPIC_ID, build_id=BUILD_ID)
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
PY

PROJECT_ID=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/project/project-id")
BUCKET_NAME=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/BUCKET_NAME")
TOPIC_ID=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/TOPIC_ID")
BUILD_ID=$(curl -s -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/BUILD_ID")

cat > /etc/systemd/system/hw4-server.service <<EOF
[Unit]
Description=HW4 Service1
After=network.target

[Service]
Type=simple
Environment=GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
Environment=BUCKET_NAME=${BUCKET_NAME}
Environment=TOPIC_ID=${TOPIC_ID}
Environment=BUILD_ID=${BUILD_ID}
Environment=PORT=80
ExecStart=/opt/hw4/venv/bin/python /opt/hw4/service1/server.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable hw4-server
systemctl restart hw4-server

touch "$LOCK_FILE"
