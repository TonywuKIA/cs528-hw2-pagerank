import json
import os
from collections import Counter
from pathlib import Path

from google.cloud import storage
from sklearn.feature_extraction import DictVectorizer
from sklearn.linear_model import SGDClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline

from db import fetch_all


BUCKET_NAME = os.environ["BUCKET_NAME"]
OUTPUT_PREFIX = os.environ.get("OUTPUT_PREFIX", "hw6")
RANDOM_STATE = int(os.environ.get("MODEL_RANDOM_STATE", "42"))
MAX_IP_COUNTRY_TEST_ROWS = int(os.environ.get("MAX_IP_COUNTRY_TEST_ROWS", "5000"))
MAX_INCOME_TRAIN_ROWS = int(os.environ.get("MAX_INCOME_TRAIN_ROWS", "15000"))
MAX_INCOME_TEST_ROWS = int(os.environ.get("MAX_INCOME_TEST_ROWS", "5000"))


def log_progress(message: str, **kwargs) -> None:
    payload = {"message": message, **kwargs}
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def fetch_joined_requests() -> list[dict[str, object]]:
    log_progress("fetch_joined_requests_start")
    rows = fetch_all(
        """
        SELECT
            rf.request_id,
            rf.request_ts,
            HOST(cid.client_ip)::TEXT AS client_ip,
            c.country_name,
            dd.gender,
            dd.age,
            dd.income,
            rf.is_banned,
            rf.time_of_day,
            rf.requested_file,
            rf.http_method,
            rf.status_code
        FROM request_facts AS rf
        LEFT JOIN client_ip_dim AS cid ON cid.client_ip_id = rf.client_ip_id
        LEFT JOIN countries AS c ON c.country_id = cid.country_id
        LEFT JOIN demographic_dim AS dd ON dd.demographic_id = rf.demographic_id
        ORDER BY rf.request_id
        """
    )
    result: list[dict[str, object]] = []
    for row in rows:
        client_ip = row[2]
        result.append(
            {
                "request_id": row[0],
                "request_ts": row[1].isoformat() if row[1] else None,
                "client_ip": client_ip,
                "country": row[3],
                "gender": row[4],
                "age": row[5],
                "income": row[6],
                "is_banned": row[7],
                "time_of_day": row[8],
                "requested_file": row[9],
                "http_method": row[10],
                "status_code": row[11],
                "ip_prefix_8": extract_ip_prefix(client_ip, 1),
                "ip_prefix_16": extract_ip_prefix(client_ip, 2),
                "ip_prefix_24": extract_ip_prefix(client_ip),
            }
        )
    log_progress("fetch_joined_requests_done", row_count=len(result))
    return result


def extract_ip_prefix(client_ip: object, octets: int = 3) -> str | None:
    if not client_ip or not isinstance(client_ip, str):
        return None
    parts = client_ip.split(".")
    if len(parts) == 4:
        return ".".join(parts[:octets])
    return client_ip


def split_rows(rows: list[dict[str, object]], target_key: str) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    filtered = [row for row in rows if row.get(target_key)]
    if len(filtered) < 5:
        raise RuntimeError(f"Not enough labeled rows for {target_key}: {len(filtered)}")
    labels = [str(row[target_key]) for row in filtered]
    can_stratify = len(set(labels)) > 1 and min(labels.count(label) for label in set(labels)) >= 2
    return train_test_split(
        filtered,
        test_size=0.2,
        random_state=RANDOM_STATE,
        stratify=labels if can_stratify else None,
    )


def upload_text(blob_name: str, content: str) -> None:
    log_progress("upload_start", blob_name=blob_name, byte_count=len(content.encode("utf-8")))
    client = storage.Client()
    bucket = client.bucket(BUCKET_NAME)
    bucket.blob(blob_name).upload_from_string(content, content_type="application/json")
    log_progress("upload_done", blob_name=blob_name)


def write_jsonl(path: Path, rows: list[dict[str, object]]) -> None:
    payload = "\n".join(json.dumps(row, ensure_ascii=False) for row in rows)
    path.write_text(payload + ("\n" if payload else ""), encoding="utf-8")


def run_ip_country_model(rows: list[dict[str, object]], output_dir: Path) -> dict[str, object]:
    log_progress("ip_country_model_start")
    train_rows, test_rows = split_rows(rows, "country")
    log_progress("ip_country_model_split_done", train_rows=len(train_rows), test_rows=len(test_rows))
    test_rows = cap_rows(test_rows, MAX_IP_COUNTRY_TEST_ROWS, "country")
    log_progress("ip_country_model_capped", test_rows=len(test_rows), max_test_rows=MAX_IP_COUNTRY_TEST_ROWS)
    log_progress("ip_country_lookup_build_start")
    ip_country_lookup = {
        str(row["client_ip"]): str(row["country"])
        for row in rows
        if row.get("client_ip") and row.get("country")
    }
    log_progress("ip_country_lookup_build_done", lookup_size=len(ip_country_lookup))
    country_counts = Counter(str(row["country"]) for row in train_rows if row.get("country"))
    fallback_country = country_counts.most_common(1)[0][0]
    log_progress("ip_country_fallback_ready", fallback_country=fallback_country, distinct_countries=len(country_counts))

    predictions = []
    actual = []
    predicted = []
    log_progress("ip_country_prediction_loop_start", test_rows=len(test_rows))
    for row in test_rows:
        predicted_country = ip_country_lookup.get(str(row["client_ip"]), fallback_country)
        actual_country = str(row["country"])
        actual.append(actual_country)
        predicted.append(predicted_country)
        predictions.append(
            {
                "request_id": row["request_id"],
                "client_ip": row["client_ip"],
                "actual_country": actual_country,
                "predicted_country": predicted_country,
                "correct": actual_country == predicted_country,
            }
        )
    log_progress("ip_country_prediction_loop_done", prediction_rows=len(predictions))

    output_path = output_dir / "ip_country_test_predictions.jsonl"
    write_jsonl(output_path, predictions)
    log_progress("ip_country_write_done", output_path=str(output_path))
    upload_text(f"{OUTPUT_PREFIX}/ip_country_test_predictions.jsonl", output_path.read_text(encoding="utf-8"))
    metrics = {
        "model_name": "lookup_by_client_ip",
        "test_rows": len(test_rows),
        "accuracy": accuracy_score(actual, predicted),
        "output_blob": f"{OUTPUT_PREFIX}/ip_country_test_predictions.jsonl",
    }
    log_progress("ip_country_model_done", **metrics)
    return metrics


def build_income_features(row: dict[str, object]) -> dict[str, str]:
    feature_names = [
        "ip_prefix_8",
        "ip_prefix_16",
        "ip_prefix_24",
        "country",
        "gender",
        "age",
        "time_of_day",
        "requested_file",
        "http_method",
        "status_code",
        "is_banned",
    ]
    features: dict[str, str] = {}
    for name in feature_names:
        value = row.get(name)
        features[name] = "unknown" if value is None else str(value)
    features["country_age"] = f'{features["country"]}|{features["age"]}'
    features["country_gender"] = f'{features["country"]}|{features["gender"]}'
    features["age_gender"] = f'{features["age"]}|{features["gender"]}'
    features["country_time_of_day"] = f'{features["country"]}|{features["time_of_day"]}'
    features["country_requested_file"] = f'{features["country"]}|{features["requested_file"]}'
    features["age_time_of_day"] = f'{features["age"]}|{features["time_of_day"]}'
    return features


def build_income_pipeline() -> Pipeline:
    classifier = SGDClassifier(
        loss="log_loss",
        max_iter=2000,
        tol=1e-3,
        class_weight="balanced",
        random_state=RANDOM_STATE,
    )
    return Pipeline(steps=[("vectorizer", DictVectorizer(sparse=True)), ("classifier", classifier)])


def _can_stratify(rows: list[dict[str, object]], key: str) -> bool:
    labels = [str(row[key]) for row in rows if row.get(key)]
    if len(set(labels)) <= 1:
        return False
    return min(labels.count(label) for label in set(labels)) >= 2


def cap_rows(rows: list[dict[str, object]], limit: int, key: str) -> list[dict[str, object]]:
    if len(rows) <= limit:
        return rows
    labels = [str(row[key]) for row in rows]
    capped, _ = train_test_split(
        rows,
        train_size=limit,
        random_state=RANDOM_STATE,
        stratify=labels if _can_stratify(rows, key) else None,
    )
    return capped


def run_income_model(rows: list[dict[str, object]], output_dir: Path) -> dict[str, object]:
    log_progress("income_model_start")
    train_rows, test_rows = split_rows(rows, "income")
    log_progress("income_model_split_done", train_rows=len(train_rows), test_rows=len(test_rows))
    train_rows = cap_rows(train_rows, MAX_INCOME_TRAIN_ROWS, "income")
    test_rows = cap_rows(test_rows, MAX_INCOME_TEST_ROWS, "income")
    log_progress(
        "income_model_capped",
        train_rows=len(train_rows),
        test_rows=len(test_rows),
        max_train_rows=MAX_INCOME_TRAIN_ROWS,
        max_test_rows=MAX_INCOME_TEST_ROWS,
    )
    unique_incomes = sorted({str(row["income"]) for row in train_rows})
    if len(unique_incomes) == 1:
        constant_income = unique_incomes[0]
        predicted = [constant_income for _ in test_rows]
        best_model_name = "constant_income_baseline"
    else:
        best_model_name = "sgd_log_loss_sparse_sampled"
        model = build_income_pipeline()
        log_progress("income_model_fit_start", model_name=best_model_name)
        model.fit([build_income_features(row) for row in train_rows], [str(row["income"]) for row in train_rows])
        log_progress("income_model_fit_done", model_name=best_model_name)
        predicted = [str(label) for label in model.predict([build_income_features(row) for row in test_rows])]
        log_progress("income_model_predict_done", model_name=best_model_name)
    actual = [str(row["income"]) for row in test_rows]

    predictions = []
    for row, predicted_income in zip(test_rows, predicted, strict=True):
        predictions.append(
            {
                "request_id": row["request_id"],
                "client_ip": row["client_ip"],
                "country": row["country"],
                "gender": row["gender"],
                "age": row["age"],
                "actual_income": row["income"],
                "predicted_income": predicted_income,
                "correct": str(row["income"]) == predicted_income,
            }
        )

    output_path = output_dir / "income_test_predictions.jsonl"
    write_jsonl(output_path, predictions)
    upload_text(f"{OUTPUT_PREFIX}/income_test_predictions.jsonl", output_path.read_text(encoding="utf-8"))
    metrics = {
        "model_name": best_model_name,
        "test_rows": len(test_rows),
        "accuracy": accuracy_score(actual, predicted),
        "output_blob": f"{OUTPUT_PREFIX}/income_test_predictions.jsonl",
    }
    log_progress("income_model_done", **metrics)
    return metrics


def main() -> int:
    output_dir = Path(os.environ.get("LOCAL_OUTPUT_DIR", "/tmp/hw6-output"))
    output_dir.mkdir(parents=True, exist_ok=True)
    log_progress("run_models_start", output_dir=str(output_dir))

    rows = fetch_joined_requests()
    if not rows:
        raise RuntimeError("No rows available in request_facts. Run migration first.")

    ip_country_metrics = run_ip_country_model(rows, output_dir)
    income_metrics = run_income_model(rows, output_dir)

    metrics = {
        "row_count": len(rows),
        "ip_country_model": ip_country_metrics,
        "income_model": income_metrics,
    }
    metrics_payload = json.dumps(metrics, indent=2)
    metrics_path = output_dir / "model_metrics.json"
    metrics_path.write_text(metrics_payload + "\n", encoding="utf-8")
    upload_text(f"{OUTPUT_PREFIX}/model_metrics.json", metrics_payload + "\n")
    log_progress("run_models_done", row_count=len(rows))
    print(metrics_payload, flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
