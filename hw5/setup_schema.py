import os

import pg8000

from db import get_connection


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS request_logs (
    request_id BIGSERIAL PRIMARY KEY,
    request_ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    country TEXT,
    client_ip INET,
    gender TEXT,
    age TEXT,
    income TEXT,
    is_banned BOOLEAN NOT NULL,
    time_of_day TEXT NOT NULL,
    requested_file TEXT NOT NULL,
    http_method TEXT NOT NULL,
    status_code INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS error_logs (
    error_id BIGSERIAL PRIMARY KEY,
    request_ts TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    requested_file TEXT,
    error_code INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_request_logs_country ON request_logs(country);
CREATE INDEX IF NOT EXISTS idx_request_logs_gender ON request_logs(gender);
CREATE INDEX IF NOT EXISTS idx_request_logs_age ON request_logs(age);
CREATE INDEX IF NOT EXISTS idx_request_logs_income ON request_logs(income);
CREATE INDEX IF NOT EXISTS idx_request_logs_is_banned ON request_logs(is_banned);
CREATE INDEX IF NOT EXISTS idx_request_logs_status_code ON request_logs(status_code);
"""


def ensure_database_exists() -> None:
    admin_conn = pg8000.connect(
        user=os.environ["DB_USER"],
        password=os.environ["DB_PASS"],
        host=os.environ["DB_HOST"],
        port=int(os.environ.get("DB_PORT", "5432")),
        database="postgres",
    )
    admin_conn.autocommit = True
    db_name = os.environ["DB_NAME"]
    with admin_conn.cursor() as cursor:
        cursor.execute("SELECT 1 FROM pg_database WHERE datname = %s", (db_name,))
        exists = cursor.fetchone()
        if not exists:
            cursor.execute(f'CREATE DATABASE "{db_name}"')
    admin_conn.close()


def main() -> int:
    ensure_database_exists()
    with get_connection() as conn:
        with conn.cursor() as cursor:
            cursor.execute(SCHEMA_SQL)
            cursor.execute(
                """
                ALTER TABLE request_logs
                ALTER COLUMN age TYPE TEXT
                USING age::TEXT
                """
            )
        conn.commit()
    print("Schema setup complete", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
