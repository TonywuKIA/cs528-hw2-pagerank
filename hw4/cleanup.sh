#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw4_state.env"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
TOPIC_ID="${TOPIC_ID:-hw3-forbidden-topic}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-hw3-sub}"

SERVER_VM="${SERVER_VM:-hw4-server-vm}"
FORBIDDEN_VM="${FORBIDDEN_VM:-hw4-forbidden-vm}"
CLIENT_VM="${CLIENT_VM:-hw4-client-vm}"
SERVER_IP_NAME="${SERVER_IP_NAME:-hw4-server-ip}"
FIREWALL_RULE="${FIREWALL_RULE:-hw4-allow-http}"

SERVER_SA_NAME="${SERVER_SA_NAME:-hw4-server-sa}"
FORBIDDEN_SA_NAME="${FORBIDDEN_SA_NAME:-hw4-forbidden-sa}"
CLIENT_SA_NAME="${CLIENT_SA_NAME:-hw4-client-sa}"

SERVER_SA_EMAIL="${SERVER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
FORBIDDEN_SA_EMAIL="${FORBIDDEN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CLIENT_SA_EMAIL="${CLIENT_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

CREATED_BUCKET=0
CREATED_SERVER_SA=0
CREATED_FORBIDDEN_SA=0
CREATED_CLIENT_SA=0
CREATED_TOPIC=0
CREATED_SUBSCRIPTION=0
CREATED_ADDRESS=0
CREATED_FIREWALL=0
CREATED_SERVER_VM=0
CREATED_FORBIDDEN_VM=0
CREATED_CLIENT_VM=0
CREATE_CLIENT_VM=true

if [ -f "${STATE_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
fi

echo "[cleanup] Deleting VMs..."
gcloud compute instances delete "${SERVER_VM}" --zone="${ZONE}" --quiet >/dev/null 2>&1 || true
gcloud compute instances delete "${FORBIDDEN_VM}" --zone="${ZONE}" --quiet >/dev/null 2>&1 || true
if [ "${CREATE_CLIENT_VM}" = "true" ]; then
  gcloud compute instances delete "${CLIENT_VM}" --zone="${ZONE}" --quiet >/dev/null 2>&1 || true
fi

if [ "${CREATED_FIREWALL}" = "1" ]; then
  gcloud compute firewall-rules delete "${FIREWALL_RULE}" --quiet >/dev/null 2>&1 || true
fi

if [ "${CREATED_ADDRESS}" = "1" ]; then
  gcloud compute addresses delete "${SERVER_IP_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1 || true
fi

if [ "${CREATED_SUBSCRIPTION}" = "1" ]; then
  gcloud pubsub subscriptions delete "${SUBSCRIPTION_ID}" >/dev/null 2>&1 || true
fi

if [ "${CREATED_TOPIC}" = "1" ]; then
  gcloud pubsub topics delete "${TOPIC_ID}" >/dev/null 2>&1 || true
fi

if [ "${CREATED_SERVER_SA}" = "1" ]; then
  gcloud iam service-accounts delete "${SERVER_SA_EMAIL}" --quiet >/dev/null 2>&1 || true
fi
if [ "${CREATED_FORBIDDEN_SA}" = "1" ]; then
  gcloud iam service-accounts delete "${FORBIDDEN_SA_EMAIL}" --quiet >/dev/null 2>&1 || true
fi
if [ "${CREATED_CLIENT_SA}" = "1" ]; then
  gcloud iam service-accounts delete "${CLIENT_SA_EMAIL}" --quiet >/dev/null 2>&1 || true
fi

if [ "${CREATED_BUCKET}" = "1" ]; then
  gcloud storage rm --recursive "gs://${BUCKET_NAME}" >/dev/null 2>&1 || true
fi

gcloud auth application-default revoke --quiet >/dev/null 2>&1 || true

rm -f "${STATE_FILE}"
echo "[cleanup] Done"
