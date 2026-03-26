import json

from db import fetch_all, fetch_one


def first_row_or_default(rows, default_label="none", default_value=0):
    if rows:
        return {"label": rows[0][0], "count": rows[0][1]}
    return {"label": default_label, "count": default_value}


def main() -> int:
    successful = fetch_one("SELECT COUNT(*) FROM request_logs WHERE status_code = 200")[0]
    unsuccessful = fetch_one("SELECT COUNT(*) FROM request_logs WHERE status_code <> 200")[0]
    banned = fetch_one("SELECT COUNT(*) FROM request_logs WHERE is_banned = TRUE")[0]
    gender_rows = fetch_all(
        """
        SELECT COALESCE(gender, 'unknown') AS label, COUNT(*)
        FROM request_logs
        GROUP BY label
        ORDER BY COUNT(*) DESC, label ASC
        """
    )
    top_countries = fetch_all(
        """
        SELECT COALESCE(country, 'unknown') AS label, COUNT(*)
        FROM request_logs
        GROUP BY label
        ORDER BY COUNT(*) DESC, label ASC
        LIMIT 5
        """
    )
    top_age_group = fetch_all(
        """
        SELECT COALESCE(age, 'unknown') AS label, COUNT(*)
        FROM request_logs
        GROUP BY label
        ORDER BY COUNT(*) DESC, label ASC
        LIMIT 1
        """
    )
    top_income_group = fetch_all(
        """
        SELECT COALESCE(income, 'unknown') AS label, COUNT(*)
        FROM request_logs
        GROUP BY label
        ORDER BY COUNT(*) DESC, label ASC
        LIMIT 1
        """
    )

    payload = {
        "successful_requests": successful,
        "unsuccessful_requests": unsuccessful,
        "banned_country_requests": banned,
        "gender_counts": [{"label": row[0], "count": row[1]} for row in gender_rows],
        "top_5_countries": [{"label": row[0], "count": row[1]} for row in top_countries],
        "top_age_group": first_row_or_default(top_age_group),
        "top_income_group": first_row_or_default(top_income_group),
    }
    print(json.dumps(payload, indent=2), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
