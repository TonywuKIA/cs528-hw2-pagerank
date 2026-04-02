from db import execute_script


SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS countries (
    country_id BIGSERIAL PRIMARY KEY,
    country_name TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS client_ip_dim (
    client_ip_id BIGSERIAL PRIMARY KEY,
    client_ip INET NOT NULL UNIQUE,
    country_id BIGINT NOT NULL REFERENCES countries(country_id)
);

CREATE TABLE IF NOT EXISTS demographic_dim (
    demographic_id BIGSERIAL PRIMARY KEY,
    gender TEXT,
    age TEXT,
    income TEXT,
    UNIQUE NULLS NOT DISTINCT (gender, age, income)
);

CREATE TABLE IF NOT EXISTS request_facts (
    request_id BIGINT PRIMARY KEY,
    request_ts TIMESTAMPTZ NOT NULL,
    client_ip_id BIGINT REFERENCES client_ip_dim(client_ip_id),
    demographic_id BIGINT REFERENCES demographic_dim(demographic_id),
    is_banned BOOLEAN NOT NULL,
    time_of_day TEXT NOT NULL,
    requested_file TEXT NOT NULL,
    http_method TEXT NOT NULL,
    status_code INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS error_facts (
    error_id BIGINT PRIMARY KEY,
    request_ts TIMESTAMPTZ NOT NULL,
    requested_file TEXT,
    error_code INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_client_ip_dim_country_id ON client_ip_dim(country_id);
CREATE INDEX IF NOT EXISTS idx_request_facts_client_ip_id ON request_facts(client_ip_id);
CREATE INDEX IF NOT EXISTS idx_request_facts_demographic_id ON request_facts(demographic_id);
CREATE INDEX IF NOT EXISTS idx_request_facts_status_code ON request_facts(status_code);
CREATE INDEX IF NOT EXISTS idx_request_facts_is_banned ON request_facts(is_banned);
"""


def main() -> int:
    execute_script(SCHEMA_SQL)
    print("3NF schema ready", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
