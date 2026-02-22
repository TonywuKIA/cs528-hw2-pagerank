import json
import os
from datetime import datetime, timezone

from google.api_core.exceptions import NotFound
from google.cloud import pubsub_v1
from google.cloud import storage


BUCKET_NAME = os.environ.get("BUCKET_NAME", "cs528-hw2-chunyu")
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCP_PROJECT")
TOPIC_ID = os.environ.get("TOPIC_ID", "hw3-forbidden-topic")
BUILD_ID = os.environ.get("BUILD_ID", "unknown")

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


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def log_struct(**kwargs) -> None:
    print(json.dumps(kwargs, ensure_ascii=False), flush=True)


def get_header_case_insensitive(request, name: str) -> str:
    try:
        headers_lower = {k.lower(): v for k, v in request.headers.items()}
        return headers_lower.get(name.lower(), "")
    except Exception:
        return request.headers.get(name, "")


def publish_forbidden_event(event: dict) -> tuple[bool, str]:
    if not PROJECT_ID:
        return False, "PROJECT_ID missing"

    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)
    try:
        future = publisher.publish(
            topic_path,
            json.dumps(event, ensure_ascii=False).encode("utf-8"),
        )
        msg_id = future.result(timeout=5)
        return True, f"message_id={msg_id}"
    except Exception as e:
        return False, str(e)


def resolve_filename(request) -> str:
    filename = request.args.get("file")
    if filename:
        return filename

    # Support provided http-client path style, e.g. /hw3-service1-fn/0.html
    parts = [p for p in request.path.split("/") if p]
    if parts:
        candidate = parts[-1]
        if candidate.lower().endswith(".html"):
            return candidate

    return ""


def handler(request):
    log_struct(severity="INFO", msg="BUILD_ID", build_id=BUILD_ID, at=utc_now())

    if request.method != "GET":
        log_struct(
            severity="WARNING",
            status=501,
            method=request.method,
            msg="Method not implemented",
        )
        return ("Method not implemented", 501)

    filename = resolve_filename(request)
    if not filename:
        log_struct(severity="ERROR", status=400, msg="Missing file parameter")
        return ("Missing file parameter", 400)

    raw_country = get_header_case_insensitive(request, "X-Country")
    country = raw_country.strip() if raw_country else ""
    country_lower = country.lower()

    if country_lower in FORBIDDEN_LOWER:
        event = {
            "timestamp_utc": utc_now(),
            "country": country,
            "file": filename,
            "http_method": request.method,
            "path": request.path,
            "query_string": request.query_string.decode("utf-8", "ignore"),
            "remote_addr": request.remote_addr,
            "build_id": BUILD_ID,
        }
        ok, detail = publish_forbidden_event(event)
        log_struct(
            severity="ERROR",
            status=400,
            country=country,
            file=filename,
            msg="Forbidden country",
            publish_ok=ok,
            publish_detail=detail,
            project_id=PROJECT_ID,
            topic_id=TOPIC_ID,
        )
        return (f"Permission denied. build={BUILD_ID}", 400)

    try:
        storage_client = storage.Client()
        bucket = storage_client.bucket(BUCKET_NAME)
        blob = bucket.blob(filename)
        content = blob.download_as_text()
        log_struct(severity="INFO", status=200, file=filename, msg="File served")
        return (content, 200, {"Content-Type": "text/html; charset=utf-8"})
    except NotFound:
        log_struct(severity="ERROR", status=404, file=filename, msg="File not found")
        return ("Not found", 404)
    except Exception as e:
        log_struct(severity="ERROR", status=500, msg="Internal error", error=str(e))
        return ("Internal error", 500)
