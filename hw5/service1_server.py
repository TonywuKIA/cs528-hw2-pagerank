import json
import os
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from google.api_core.exceptions import NotFound
from google.cloud import pubsub_v1
from google.cloud import storage

from db import insert_error_record, insert_request_record


BUCKET_NAME = os.environ.get("BUCKET_NAME", "cs528-hw2-chunyu")
PROJECT_ID = os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCP_PROJECT")
TOPIC_ID = os.environ.get("TOPIC_ID", "hw3-forbidden-topic")
BUILD_ID = os.environ.get("BUILD_ID", "hw5-vm")
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

HEADER_ALIASES = {
    "country": ("x-country", "country"),
    "gender": ("x-gender", "gender", "x-user-gender"),
    "age": ("x-age", "age", "x-user-age"),
    "income": ("x-income", "income", "x-user-income"),
    "client_ip": ("x-client-ip", "x-forwarded-for", "x-real-ip"),
    "request_time": ("x-time", "time"),
}

storage_client = storage.Client()


@dataclass
class RequestRecord:
    request_ts: datetime
    country: str | None
    client_ip: str | None
    gender: str | None
    age: str | None
    income: str | None
    is_banned: bool
    time_of_day: str
    requested_file: str
    http_method: str
    status_code: int


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def log_struct(**kwargs) -> None:
    print(json.dumps(kwargs, ensure_ascii=False), flush=True)


def timed_call(func, *args, **kwargs):
    started = time.perf_counter()
    result = func(*args, **kwargs)
    duration_ms = (time.perf_counter() - started) * 1000
    return result, duration_ms


def get_header_case_insensitive(headers, *candidates: str) -> str:
    lowered = {k.lower(): v for k, v in headers.items()}
    for candidate in candidates:
        value = lowered.get(candidate.lower(), "")
        if value:
            return value.strip()
    return ""


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


def bucket_time_of_day(ts: datetime) -> str:
    hour = ts.hour
    if 5 <= hour <= 11:
        return "morning"
    if 12 <= hour <= 16:
        return "afternoon"
    if 17 <= hour <= 20:
        return "evening"
    return "night"


def normalize_ip(value: str, fallback: str) -> str | None:
    candidate = value.split(",")[0].strip() if value else fallback.strip()
    return candidate or None


def parse_request_timestamp(value: str) -> datetime:
    if not value:
        return utc_now()
    try:
        normalized = value.strip().replace(" ", "T")
        parsed = datetime.fromisoformat(normalized)
        if parsed.tzinfo is None:
            return parsed.replace(tzinfo=timezone.utc)
        return parsed.astimezone(timezone.utc)
    except ValueError:
        return utc_now()


def extract_request_metadata(handler: BaseHTTPRequestHandler) -> tuple[RequestRecord, dict[str, str]]:
    parsed = urlparse(handler.path)
    filename = resolve_filename(parsed.path, parsed.query)
    request_time_header = get_header_case_insensitive(handler.headers, *HEADER_ALIASES["request_time"])
    request_ts = parse_request_timestamp(request_time_header)

    country = get_header_case_insensitive(handler.headers, *HEADER_ALIASES["country"]) or None
    gender = get_header_case_insensitive(handler.headers, *HEADER_ALIASES["gender"]) or None
    age = get_header_case_insensitive(handler.headers, *HEADER_ALIASES["age"]) or None
    income = get_header_case_insensitive(handler.headers, *HEADER_ALIASES["income"]) or None
    forwarded_ip = get_header_case_insensitive(handler.headers, *HEADER_ALIASES["client_ip"])
    client_ip = normalize_ip(forwarded_ip, handler.client_address[0] if handler.client_address else "")
    is_banned = bool(country and country.lower() in FORBIDDEN_LOWER)

    record = RequestRecord(
        request_ts=request_ts,
        country=country,
        client_ip=client_ip,
        gender=gender,
        age=age,
        income=income,
        is_banned=is_banned,
        time_of_day=bucket_time_of_day(request_ts),
        requested_file=filename,
        http_method=handler.command,
        status_code=0,
    )
    request_context = {"path": parsed.path, "query_string": parsed.query}
    return record, request_context


def fetch_file_from_gcs(filename: str) -> str:
    bucket = storage_client.bucket(BUCKET_NAME)
    blob = bucket.blob(filename)
    return blob.download_as_text()


def write_http_response(handler: BaseHTTPRequestHandler, body: str, status: int, content_type: str = "text/html; charset=utf-8") -> float:
    started = time.perf_counter()
    body_bytes = body.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", content_type)
    handler.send_header("Content-Length", str(len(body_bytes)))
    handler.end_headers()
    if handler.command != "HEAD":
        handler.wfile.write(body_bytes)
    return (time.perf_counter() - started) * 1000


def publish_forbidden_event(record: RequestRecord, request_context: dict[str, str]) -> tuple[bool, str]:
    if not PROJECT_ID:
        return False, "PROJECT_ID missing"
    publisher = pubsub_v1.PublisherClient()
    topic_path = publisher.topic_path(PROJECT_ID, TOPIC_ID)
    event = {
        "timestamp_utc": record.request_ts.isoformat(),
        "country": record.country or "",
        "file": record.requested_file,
        "http_method": record.http_method,
        "path": request_context["path"],
        "query_string": request_context["query_string"],
        "remote_addr": record.client_ip or "",
        "build_id": BUILD_ID,
    }
    try:
        future = publisher.publish(topic_path, json.dumps(event, ensure_ascii=False).encode("utf-8"))
        message_id = future.result(timeout=5)
        return True, f"message_id={message_id}"
    except Exception as e:  # noqa: BLE001
        return False, str(e)


def persist_request(record: RequestRecord) -> float:
    started = time.perf_counter()
    insert_request_record(asdict(record))
    return (time.perf_counter() - started) * 1000


def persist_error(request_ts: datetime, requested_file: str, error_code: int) -> float:
    started = time.perf_counter()
    insert_error_record(
        {
            "request_ts": request_ts,
            "requested_file": requested_file or None,
            "error_code": error_code,
        }
    )
    return (time.perf_counter() - started) * 1000


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _handle_request(self) -> None:
        try:
            (record, request_context), extract_ms = timed_call(extract_request_metadata, self)

            if self.command != "GET":
                record.status_code = 501
                request_db_ms = persist_request(record)
                error_db_ms = persist_error(record.request_ts, record.requested_file, 501)
                response_ms = write_http_response(self, "Method not implemented", 501)
                self._log_completion(record, extract_ms, 0.0, response_ms, request_db_ms + error_db_ms, "Method not implemented")
                return

            if not record.requested_file:
                record.status_code = 400
                request_db_ms = persist_request(record)
                error_db_ms = persist_error(record.request_ts, record.requested_file, 400)
                response_ms = write_http_response(self, "Missing file parameter", 400)
                self._log_completion(record, extract_ms, 0.0, response_ms, request_db_ms + error_db_ms, "Missing file parameter")
                return

            if record.is_banned:
                ok, detail = publish_forbidden_event(record, request_context)
                record.status_code = 400
                request_db_ms = persist_request(record)
                error_db_ms = persist_error(record.request_ts, record.requested_file, 400)
                response_ms = write_http_response(self, "Permission denied", 400)
                self._log_completion(
                    record,
                    extract_ms,
                    0.0,
                    response_ms,
                    request_db_ms + error_db_ms,
                    "Forbidden country",
                    publish_ok=ok,
                    publish_detail=detail,
                )
                return

            try:
                content, gcs_ms = timed_call(fetch_file_from_gcs, record.requested_file)
                record.status_code = 200
                request_db_ms = persist_request(record)
                response_ms = write_http_response(self, content, 200)
                self._log_completion(record, extract_ms, gcs_ms, response_ms, request_db_ms, "File served")
            except NotFound:
                record.status_code = 404
                request_db_ms = persist_request(record)
                error_db_ms = persist_error(record.request_ts, record.requested_file, 404)
                response_ms = write_http_response(self, "Not found", 404)
                self._log_completion(record, extract_ms, 0.0, response_ms, request_db_ms + error_db_ms, "File not found")
        except Exception as e:  # noqa: BLE001
            response_ms = 0.0
            db_ms = 0.0
            fallback_ts = utc_now()
            filename = resolve_filename(urlparse(self.path).path, urlparse(self.path).query)
            try:
                db_ms = persist_error(fallback_ts, filename, 500)
            except Exception:  # noqa: BLE001
                pass
            try:
                response_ms = write_http_response(self, "Internal error", 500)
            except Exception:  # noqa: BLE001
                pass
            log_struct(severity="ERROR", status=500, msg="Internal error", error=str(e), response_ms=round(response_ms, 3), db_ms=round(db_ms, 3))

    def _log_completion(
        self,
        record: RequestRecord,
        extract_ms: float,
        gcs_ms: float,
        response_ms: float,
        db_ms: float,
        msg: str,
        **extra,
    ) -> None:
        severity = "INFO"
        if record.status_code == 400 and record.is_banned:
            severity = "CRITICAL"
        elif record.status_code in {400, 404, 501}:
            severity = "WARNING"

        total_ms = extract_ms + gcs_ms + response_ms + db_ms
        log_struct(
            severity=severity,
            status=record.status_code,
            msg=msg,
            country=record.country,
            client_ip=record.client_ip,
            gender=record.gender,
            age=record.age,
            income=record.income,
            is_banned=record.is_banned,
            time_of_day=record.time_of_day,
            file=record.requested_file,
            extract_ms=round(extract_ms, 3),
            gcs_ms=round(gcs_ms, 3),
            response_ms=round(response_ms, 3),
            db_ms=round(db_ms, 3),
            total_ms=round(total_ms, 3),
            **extra,
        )

    def do_GET(self) -> None:  # noqa: N802
        self._handle_request()

    def do_POST(self) -> None:  # noqa: N802
        self._handle_request()

    def do_PUT(self) -> None:  # noqa: N802
        self._handle_request()

    def do_DELETE(self) -> None:  # noqa: N802
        self._handle_request()

    def do_HEAD(self) -> None:  # noqa: N802
        self._handle_request()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._handle_request()

    def do_PATCH(self) -> None:  # noqa: N802
        self._handle_request()

    def log_message(self, fmt: str, *args) -> None:
        log_struct(severity="INFO", msg="http_access", method=self.command, path=self.path, detail=fmt % args)


def main() -> None:
    log_struct(severity="INFO", msg="server_start", port=PORT, bucket=BUCKET_NAME, topic=TOPIC_ID, build_id=BUILD_ID)
    httpd = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    httpd.serve_forever()


if __name__ == "__main__":
    main()
