# HW5 (VM + Cloud SQL)

This directory satisfies the required grading workflow:

```bash
HW=5
git clone --recursive <repo> repo/
pushd repo/hw${HW}/
bash setup.sh
# tests...
bash cleanup.sh
popd
```

## Files
- `setup.sh`: provisions HW5 infrastructure and starts the Cloud SQL instance
- `cleanup.sh`: deletes VMs, releases the static IP, and stops Cloud SQL
- `startup.sh`: bootstrap for the web server VM
- `startup_forbidden.sh`: bootstrap for the forbidden-country subscriber VM
- `setup_schema.py`: idempotent PostgreSQL schema creation
- `db.py`: shared Cloud SQL connector helpers
- `service1_server.py`: VM web server with Cloud SQL logging
- `service2_subscriber.py`: forbidden-country subscriber
- `query_stats.py`: required post-run analytics helper
- `stop_sql_function/`: hourly Cloud Function that stops the SQL instance

## Defaults
- Project ID: `sonorous-sign-487022-a1`
- Region: `us-central1`
- Zone: `us-central1-a`
- Bucket: `cs528-hw2-chunyu`
- Topic: `hw3-forbidden-topic`
- Subscription: `hw3-sub`
- SQL instance: `hw5-sql`
- Database: `hw5db`

## Setup
Run:

```bash
bash setup.sh
```

At the end of setup, record screenshots for:
- Cloud SQL running and schema creation
- setup completion with VM names, static IP, and DB status

## Curl checks
After setup, use the printed static IP:

```bash
SERVER_IP="<replace-with-setup-output>"
curl -i "http://${SERVER_IP}/?file=index.html"
curl -i -H "X-Country: Iran" "http://${SERVER_IP}/?file=index.html"
curl -i "http://${SERVER_IP}/?file=does_not_exist.html"
curl -i -X POST "http://${SERVER_IP}/?file=index.html"
```

Before the first request, capture a screenshot showing both tables empty. After each required curl request, capture:
- the curl output
- `request_logs`
- `error_logs`

## Querying the database
Connect with Cloud SQL or any PostgreSQL client and run:

```sql
SELECT * FROM request_logs ORDER BY request_id DESC LIMIT 20;
SELECT * FROM error_logs ORDER BY error_id DESC LIMIT 20;
```

For required statistics, run:

```bash
python query_stats.py
```

with these environment variables set:

```bash
export DB_INSTANCE_CONNECTION_NAME="sonorous-sign-487022-a1:us-central1:hw5-sql"
export DB_NAME="hw5db"
export DB_USER="hw5user"
export DB_PASS="Hw5Pass_528_Project!"
```

## Cleanup
Run:

```bash
bash cleanup.sh
```

This stops the Cloud SQL instance instead of deleting it.
