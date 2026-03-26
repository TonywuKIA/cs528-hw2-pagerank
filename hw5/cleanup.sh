#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw5_state.env"

PROJECT_ID="sonorous-sign-487022-a1"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
SERVER_VM="${SERVER_VM:-hw5-server-vm}"
FORBIDDEN_VM="${FORBIDDEN_VM:-hw5-forbidden-vm}"
SERVER_IP_NAME="${SERVER_IP_NAME:-hw5-server-ip}"
FIREWALL_RULE="${FIREWALL_RULE:-hw5-allow-http}"
DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-hw5-sql}"
DB_FUNCTION_NAME="${DB_FUNCTION_NAME:-hw5-stop-sql}"
DB_FUNCTION_REGION="${DB_FUNCTION_REGION:-us-central1}"
SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-hw5-stop-sql-hourly}"

if [ -f "${STATE_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
fi

echo "[cleanup] Deleting VMs..."
gcloud compute instances delete "${SERVER_VM}" --zone="${ZONE}" --quiet >/dev/null 2>&1 || true
gcloud compute instances delete "${FORBIDDEN_VM}" --zone="${ZONE}" --quiet >/dev/null 2>&1 || true

echo "[cleanup] Releasing static IP..."
gcloud compute addresses delete "${SERVER_IP_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1 || true

echo "[cleanup] Removing firewall..."
gcloud compute firewall-rules delete "${FIREWALL_RULE}" --quiet >/dev/null 2>&1 || true

echo "[cleanup] Removing scheduler and function..."
gcloud scheduler jobs delete "${SCHEDULER_JOB_NAME}" --location="${DB_FUNCTION_REGION}" --quiet >/dev/null 2>&1 || true
gcloud functions delete "${DB_FUNCTION_NAME}" --gen2 --region="${DB_FUNCTION_REGION}" --quiet >/dev/null 2>&1 || true

echo "[cleanup] Stopping Cloud SQL instance..."
gcloud sql instances patch "${DB_INSTANCE_NAME}" --activation-policy=NEVER --quiet >/dev/null

rm -f "${STATE_FILE}"
echo "[cleanup] Done"
echo "[cleanup] Screenshot now: cleanup stopping DB and deleting VMs."
