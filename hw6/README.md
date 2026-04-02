# HW6 (3NF + ML on VM)

This directory builds on the populated `hw5db` database from Homework 5.

## Files
- `run.sh`: starts Cloud SQL, creates a VM, runs schema migration plus both models, prints bucket outputs, then deletes the VM and stops the database
- `cleanup.sh`: manual cleanup fallback
- `setup_3nf.py`: creates the normalized schema
- `migrate_to_3nf.py`: copies HW5 data into the normalized schema
- `run_models.py`: loads normalized data, evaluates both models, and uploads test-set outputs to GCS
- `db.py`: PostgreSQL helpers used by the migration and ML scripts
- `startup.sh`: installs Python and dependencies on the VM
- `normalization_queries.sql`: plain SQL version of the schema and migration statements for the report

## 3NF schema

The HW5 `request_logs` table is not in 3NF because `client_ip -> country`, so `country` is transitively dependent on `request_id` through `client_ip`.

The normalized schema is:
- `countries(country_id, country_name)`
- `client_ip_dim(client_ip_id, client_ip, country_id)`
- `demographic_dim(demographic_id, gender, age, income)`
- `request_facts(request_id, request_ts, client_ip_id, demographic_id, is_banned, time_of_day, requested_file, http_method, status_code)`
- `error_facts(error_id, request_ts, requested_file, error_code)`

## Run

From this directory:

```bash
bash run.sh
```

The script:
1. Starts the existing Cloud SQL instance.
2. Creates a VM.
3. Creates the 3NF schema.
4. Migrates data from `request_logs` and `error_logs`.
5. Trains and evaluates the IP-to-country model and the income model.
6. Uploads test-set outputs to `gs://<bucket>/hw6/`.
7. Prints those bucket files on the terminal.
8. Deletes the VM and stops the database.

## Output files

The script uploads:
- `gs://<bucket>/hw6/model_metrics.json`
- `gs://<bucket>/hw6/ip_country_test_predictions.jsonl`
- `gs://<bucket>/hw6/income_test_predictions.jsonl`
