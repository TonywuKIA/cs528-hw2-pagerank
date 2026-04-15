import argparse
import csv
import json
import sys
import time
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Probe the HW8 load balancer and record backend zone headers.")
    parser.add_argument("--base-url", required=True, help="Base URL such as http://34.1.2.3")
    parser.add_argument("--file", default="index.html", help="Object name passed as ?file=...")
    parser.add_argument("--country", default="", help="Optional X-Country header for testing forbidden flows")
    parser.add_argument("--interval", type=float, default=1.0, help="Seconds between requests")
    parser.add_argument("--count", type=int, default=0, help="Number of requests to send; 0 means until duration or Ctrl+C")
    parser.add_argument("--duration", type=float, default=0.0, help="Total runtime in seconds; 0 means no time limit")
    parser.add_argument("--timeout", type=float, default=5.0, help="Per-request timeout in seconds")
    parser.add_argument("--jsonl-out", default="", help="Optional JSONL file path for machine-readable logs")
    parser.add_argument("--csv-out", default="", help="Optional CSV file path for machine-readable logs")
    return parser.parse_args()


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def ensure_parent(path_str: str) -> None:
    if not path_str:
        return
    Path(path_str).expanduser().resolve().parent.mkdir(parents=True, exist_ok=True)


def open_csv(path_str: str):
    if not path_str:
        return None, None
    ensure_parent(path_str)
    handle = open(path_str, "w", newline="", encoding="utf-8")
    writer = csv.DictWriter(
        handle,
        fieldnames=[
            "timestamp_utc",
            "request_id",
            "url",
            "classification",
            "http_status",
            "error",
            "zone",
            "instance_name",
            "latency_ms",
        ],
    )
    writer.writeheader()
    return handle, writer


def build_request(url: str, country: str) -> urllib.request.Request:
    headers = {}
    if country:
        headers["X-Country"] = country
    return urllib.request.Request(url, method="GET", headers=headers)


def classify_result(http_status: int | None, error: str) -> str:
    if error:
        return "network_error"
    if http_status is None:
        return "unknown"
    if 200 <= http_status < 300:
        return "ok"
    return "http_error"


def main() -> int:
    args = parse_args()
    base_url = args.base_url.rstrip("/")
    url = f"{base_url}/?file={args.file}"

    jsonl_handle = None
    csv_handle, csv_writer = open_csv(args.csv_out)
    if args.jsonl_out:
        ensure_parent(args.jsonl_out)
        jsonl_handle = open(args.jsonl_out, "w", encoding="utf-8")

    zone_counter: Counter[str] = Counter()
    success_counter = 0
    started = time.monotonic()
    request_id = 0

    try:
        while True:
            if args.count > 0 and request_id >= args.count:
                break
            if args.duration > 0 and (time.monotonic() - started) >= args.duration:
                break

            request_id += 1
            ts = utc_now_iso()
            start = time.perf_counter()
            status = None
            zone = ""
            instance_name = ""
            error = ""

            try:
                with urllib.request.urlopen(build_request(url, args.country), timeout=args.timeout) as resp:
                    status = resp.status
                    zone = resp.headers.get("X-Zone", "")
                    instance_name = resp.headers.get("X-Instance-Name", "")
                    _ = resp.read()
            except urllib.error.HTTPError as exc:
                status = exc.code
                zone = exc.headers.get("X-Zone", "")
                instance_name = exc.headers.get("X-Instance-Name", "")
                _ = exc.read()
            except Exception as exc:  # noqa: BLE001
                error = str(exc)

            latency_ms = round((time.perf_counter() - start) * 1000, 2)
            classification = classify_result(status, error)

            record = {
                "timestamp_utc": ts,
                "request_id": request_id,
                "url": url,
                "classification": classification,
                "http_status": status,
                "error": error,
                "zone": zone,
                "instance_name": instance_name,
                "latency_ms": latency_ms,
            }

            if classification == "ok" and zone:
                zone_counter[zone] += 1
                success_counter += 1

            status_display = status if status is not None else "ERR"
            zone_display = zone or "-"
            instance_display = instance_name or "-"
            error_display = error if error else "-"
            print(
                f"{ts} req={request_id:04d} status={status_display} class={classification} "
                f"zone={zone_display} instance={instance_display} latency_ms={latency_ms:.2f} error={error_display}"
            )

            if jsonl_handle:
                jsonl_handle.write(json.dumps(record, ensure_ascii=False) + "\n")
                jsonl_handle.flush()
            if csv_writer:
                csv_writer.writerow(record)
                csv_handle.flush()

            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("Interrupted by user.", file=sys.stderr)
    finally:
        if jsonl_handle:
            jsonl_handle.close()
        if csv_handle:
            csv_handle.close()

    print("\nSummary:")
    print(f"  successful responses: {success_counter}")
    if success_counter:
        for zone, count in sorted(zone_counter.items()):
            ratio = count / success_counter
            print(f"  {zone}: {count} ({ratio:.2%})")
    else:
        print("  no successful responses recorded")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
