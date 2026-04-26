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
BUILD_ID = os.environ.get("BUILD_ID", "hw9-gke")
PORT = int(os.environ.get("PORT", "8080"))

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
    except Exception as exc:  # noqa: BLE001
        return False, str(exc)


def resolve_filename(path: str, query: str) -> str:
    qs = parse_qs(query)
    if "file" in qs and qs["file"]:
        return qs["file"][0]

    parts = [part for part in path.split("/") if part]
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
        if self.command != "HEAD":
            self.wfile.write(body_bytes)

    def _country_header(self) -> str:
        for key, value in self.headers.items():
            if key.lower() == "x-country":
                return (value or "").strip()
        return ""

    def _remote_addr(self) -> str:
        return self.client_address[0] if self.client_address else ""

    def _handle_get(self) -> None:
        parsed = urlparse(self.path)

        if parsed.path == "/healthz":
            self._write(
                json.dumps({"status": "ok", "build_id": BUILD_ID}),
                200,
                "application/json; charset=utf-8",
            )
            return

        filename = resolve_filename(parsed.path, parsed.query)
        if not filename:
            log_struct(severity="WARNING", status=400, msg="Missing file parameter", path=parsed.path)
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
        except Exception as exc:  # noqa: BLE001
            log_struct(severity="ERROR", status=500, msg="Internal error", error=str(exc))
            self._write("Internal error", 500)

    def do_GET(self) -> None:  # noqa: N802
        self._handle_get()

    def do_POST(self) -> None:  # noqa: N802
        self._method_not_implemented()

    def do_PUT(self) -> None:  # noqa: N802
        self._method_not_implemented()

    def do_DELETE(self) -> None:  # noqa: N802
        self._method_not_implemented()

    def do_HEAD(self) -> None:  # noqa: N802
        self._method_not_implemented()

    def do_CONNECT(self) -> None:  # noqa: N802
        self._method_not_implemented()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._method_not_implemented()

    def do_TRACE(self) -> None:  # noqa: N802
        self._method_not_implemented()

    def do_PATCH(self) -> None:  # noqa: N802
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
