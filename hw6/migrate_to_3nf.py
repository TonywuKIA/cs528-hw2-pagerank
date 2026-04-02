from db import execute_script


MIGRATION_SQL = """
INSERT INTO countries (country_name)
SELECT DISTINCT rl.country
FROM request_logs AS rl
WHERE rl.country IS NOT NULL
ON CONFLICT (country_name) DO NOTHING;

INSERT INTO client_ip_dim (client_ip, country_id)
SELECT DISTINCT rl.client_ip, c.country_id
FROM request_logs AS rl
JOIN countries AS c ON c.country_name = rl.country
WHERE rl.client_ip IS NOT NULL
ON CONFLICT (client_ip) DO UPDATE
SET country_id = EXCLUDED.country_id;

INSERT INTO demographic_dim (gender, age, income)
SELECT DISTINCT rl.gender, rl.age, rl.income
FROM request_logs AS rl
ON CONFLICT (gender, age, income) DO NOTHING;

INSERT INTO request_facts (
    request_id,
    request_ts,
    client_ip_id,
    demographic_id,
    is_banned,
    time_of_day,
    requested_file,
    http_method,
    status_code
)
SELECT
    rl.request_id,
    rl.request_ts,
    cid.client_ip_id,
    dd.demographic_id,
    rl.is_banned,
    rl.time_of_day,
    rl.requested_file,
    rl.http_method,
    rl.status_code
FROM request_logs AS rl
LEFT JOIN client_ip_dim AS cid ON cid.client_ip = rl.client_ip
LEFT JOIN demographic_dim AS dd
    ON dd.gender IS NOT DISTINCT FROM rl.gender
   AND dd.age IS NOT DISTINCT FROM rl.age
   AND dd.income IS NOT DISTINCT FROM rl.income
ON CONFLICT (request_id) DO UPDATE
SET
    request_ts = EXCLUDED.request_ts,
    client_ip_id = EXCLUDED.client_ip_id,
    demographic_id = EXCLUDED.demographic_id,
    is_banned = EXCLUDED.is_banned,
    time_of_day = EXCLUDED.time_of_day,
    requested_file = EXCLUDED.requested_file,
    http_method = EXCLUDED.http_method,
    status_code = EXCLUDED.status_code;

INSERT INTO error_facts (error_id, request_ts, requested_file, error_code)
SELECT
    el.error_id,
    el.request_ts,
    el.requested_file,
    el.error_code
FROM error_logs AS el
ON CONFLICT (error_id) DO UPDATE
SET
    request_ts = EXCLUDED.request_ts,
    requested_file = EXCLUDED.requested_file,
    error_code = EXCLUDED.error_code;
"""


def main() -> int:
    execute_script(MIGRATION_SQL)
    print("Data migration complete", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
