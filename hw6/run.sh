#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_ID="${PROJECT_ID:-sonorous-sign-487022-a1}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-hw5-sql}"
DB_NAME="${DB_NAME:-hw5db}"
DB_USER="${DB_USER:-hw5user}"
DB_PASS="${DB_PASS:-Hw5Pass_528_Project!}"
DB_PORT="${DB_PORT:-5432}"

MODEL_VM="${MODEL_VM:-hw6-model-vm}"
MODEL_MACHINE_TYPE="${MODEL_MACHINE_TYPE:-e2-standard-4}"
MODEL_SA_NAME="${MODEL_SA_NAME:-hw6-model-sa}"
MODEL_SA_EMAIL="${MODEL_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-hw6}"

run_ssh_with_retry() {
  local remote_command="$1"
  local attempts="${2:-12}"
  local sleep_seconds="${3:-10}"
  local attempt

  for attempt in $(seq 1 "${attempts}"); do
    if gcloud compute ssh "${MODEL_VM}" --zone="${ZONE}" --command="${remote_command}"; then
      return 0
    fi
    echo "[run] SSH attempt ${attempt}/${attempts} failed; retrying in ${sleep_seconds}s..."
    sleep "${sleep_seconds}"
  done

  echo "[run] SSH failed after ${attempts} attempts." >&2
  return 1
}

cleanup() {
  set +e
  if gcloud compute instances describe "${MODEL_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
    echo "[cleanup] Deleting VM ${MODEL_VM}..."
    gcloud compute instances delete "${MODEL_VM}" --zone="${ZONE}" --quiet >/dev/null
  fi
  if gcloud sql instances describe "${DB_INSTANCE_NAME}" >/dev/null 2>&1; then
    echo "[cleanup] Stopping Cloud SQL instance ${DB_INSTANCE_NAME}..."
    gcloud sql instances patch "${DB_INSTANCE_NAME}" --activation-policy=NEVER --quiet >/dev/null
  fi
}

trap cleanup EXIT

create_sa_if_needed() {
  local sa_name="$1"
  local sa_email="$2"
  if gcloud iam service-accounts describe "${sa_email}" >/dev/null 2>&1; then
    echo "[setup] Service account exists: ${sa_email}"
  else
    gcloud iam service-accounts create "${sa_name}" --display-name="HW6 Model VM SA" >/dev/null
    echo "[setup] Created service account: ${sa_email}"
  fi
}

echo "[setup] Enabling required APIs..."
gcloud services enable \
  compute.googleapis.com \
  iam.googleapis.com \
  sqladmin.googleapis.com \
  storage.googleapis.com >/dev/null

create_sa_if_needed "${MODEL_SA_NAME}" "${MODEL_SA_EMAIL}"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${MODEL_SA_EMAIL}" --role="roles/storage.objectAdmin" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${MODEL_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null

echo "[setup] Starting Cloud SQL instance ${DB_INSTANCE_NAME}..."
gcloud sql instances patch "${DB_INSTANCE_NAME}" --activation-policy=ALWAYS --authorized-networks=0.0.0.0/0 --quiet >/dev/null
DB_HOST="$(gcloud sql instances describe "${DB_INSTANCE_NAME}" --format='value(ipAddresses[0].ipAddress)')"

echo "[setup] Creating VM ${MODEL_VM}..."
if gcloud compute instances describe "${MODEL_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
  gcloud compute instances delete "${MODEL_VM}" --zone="${ZONE}" --quiet >/dev/null
fi

gcloud compute instances create "${MODEL_VM}" \
  --zone="${ZONE}" \
  --machine-type="${MODEL_MACHINE_TYPE}" \
  --image-family="ubuntu-2404-lts-amd64" \
  --image-project="ubuntu-os-cloud" \
  --service-account="${MODEL_SA_EMAIL}" \
  --scopes="https://www.googleapis.com/auth/cloud-platform" \
  --metadata="BUCKET_NAME=${BUCKET_NAME},DB_HOST=${DB_HOST},DB_PORT=${DB_PORT},DB_NAME=${DB_NAME},DB_USER=${DB_USER},DB_PASS=${DB_PASS},OUTPUT_PREFIX=${OUTPUT_PREFIX}" \
  --metadata-from-file="startup-script=${SCRIPT_DIR}/startup.sh,APP_DB_PY=${SCRIPT_DIR}/db.py,APP_SETUP_3NF_PY=${SCRIPT_DIR}/setup_3nf.py,APP_MIGRATE_PY=${SCRIPT_DIR}/migrate_to_3nf.py,APP_RUN_MODELS_PY=${SCRIPT_DIR}/run_models.py" >/dev/null

echo "[run] Waiting for VM bootstrap to finish..."
run_ssh_with_retry "while [ ! -x /opt/hw6/venv/bin/python ]; do sleep 5; done" 18 10

echo "[run] Applying 3NF schema and migrating data..."
run_ssh_with_retry "cd /opt/hw6/app && export DB_HOST='${DB_HOST}' DB_PORT='${DB_PORT}' DB_NAME='${DB_NAME}' DB_USER='${DB_USER}' DB_PASS='${DB_PASS}' && /opt/hw6/venv/bin/python setup_3nf.py && /opt/hw6/venv/bin/python migrate_to_3nf.py" 6 10

echo "[run] Training and evaluating models..."
run_ssh_with_retry "cd /opt/hw6/app && export BUCKET_NAME='${BUCKET_NAME}' OUTPUT_PREFIX='${OUTPUT_PREFIX}' DB_HOST='${DB_HOST}' DB_PORT='${DB_PORT}' DB_NAME='${DB_NAME}' DB_USER='${DB_USER}' DB_PASS='${DB_PASS}' && /opt/hw6/venv/bin/python run_models.py" 6 10

echo "[output] Metrics file:"
gcloud storage cat "gs://${BUCKET_NAME}/${OUTPUT_PREFIX}/model_metrics.json"
echo "[output] IP-country predictions:"
gcloud storage cat "gs://${BUCKET_NAME}/${OUTPUT_PREFIX}/ip_country_test_predictions.jsonl"
echo "[output] Income predictions:"
gcloud storage cat "gs://${BUCKET_NAME}/${OUTPUT_PREFIX}/income_test_predictions.jsonl"
