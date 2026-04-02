#!/usr/bin/env bash
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-sonorous-sign-487022-a1}"
ZONE="${ZONE:-us-central1-a}"
MODEL_VM="${MODEL_VM:-hw6-model-vm}"
DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-hw5-sql}"

if gcloud compute instances describe "${MODEL_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "[cleanup] Deleting VM ${MODEL_VM}..."
  gcloud compute instances delete "${MODEL_VM}" --zone="${ZONE}" --quiet >/dev/null
fi

if gcloud sql instances describe "${DB_INSTANCE_NAME}" >/dev/null 2>&1; then
  echo "[cleanup] Stopping Cloud SQL instance ${DB_INSTANCE_NAME}..."
  gcloud sql instances patch "${DB_INSTANCE_NAME}" --activation-policy=NEVER --quiet >/dev/null
fi

echo "[cleanup] Complete for project ${PROJECT_ID}"
