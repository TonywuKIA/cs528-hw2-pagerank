import os
from collections.abc import Iterable
from typing import Any

from google.cloud.sql.connector import Connector, IPTypes
import pg8000


DB_INSTANCE_CONNECTION_NAME = os.environ["DB_INSTANCE_CONNECTION_NAME"]
DB_NAME = os.environ["DB_NAME"]
DB_USER = os.environ["DB_USER"]
DB_PASS = os.environ["DB_PASS"]
DB_HOST = os.environ.get("DB_HOST", "").strip()
DB_PORT = int(os.environ.get("DB_PORT", "5432"))


_connector: Connector | None = None


def _get_connector() -> Connector:
    global _connector
    if _connector is None:
        _connector = Connector(refresh_strategy="lazy")
    return _connector


def get_connection():
    if DB_HOST:
        return pg8000.connect(
            host=DB_HOST,
            port=DB_PORT,
            database=DB_NAME,
            user=DB_USER,
            password=DB_PASS,
        )
    connector = _get_connector()
    return connector.connect(
        DB_INSTANCE_CONNECTION_NAME,
        "pg8000",
        user=DB_USER,
        password=DB_PASS,
        db=DB_NAME,
        ip_type=IPTypes.PUBLIC,
    )


def close_connector() -> None:
    global _connector
    if _connector is not None:
        _connector.close()
        _connector = None


def insert_request_record(record: dict[str, Any]) -> None:
    query = """
        INSERT INTO request_logs (
            request_ts,
            country,
            client_ip,
            gender,
            age,
            income,
            is_banned,
            time_of_day,
            requested_file,
            http_method,
            status_code
        ) VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)
    """
    values = (
        record["request_ts"],
        record.get("country"),
        record.get("client_ip"),
        record.get("gender"),
        record.get("age"),
        record.get("income"),
        record["is_banned"],
        record["time_of_day"],
        record["requested_file"],
        record["http_method"],
        record["status_code"],
    )
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, values)
            conn.commit()
        finally:
            cursor.close()


def insert_error_record(record: dict[str, Any]) -> None:
    query = """
        INSERT INTO error_logs (request_ts, requested_file, error_code)
        VALUES (%s, %s, %s)
    """
    values = (record["request_ts"], record.get("requested_file"), record["error_code"])
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, values)
            conn.commit()
        finally:
            cursor.close()


def fetch_one(query: str, params: Iterable[Any] = ()) -> Any:
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, tuple(params))
            return cursor.fetchone()
        finally:
            cursor.close()


def fetch_all(query: str, params: Iterable[Any] = ()) -> list[tuple[Any, ...]]:
    with get_connection() as conn:
        cursor = conn.cursor()
        try:
            cursor.execute(query, tuple(params))
            return list(cursor.fetchall())
        finally:
            cursor.close()
