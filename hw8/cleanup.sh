#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw8_state.env"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
REGION="${REGION:-us-central1}"
ZONE_A="${ZONE_A:-us-central1-a}"
ZONE_B="${ZONE_B:-us-central1-b}"
BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
TOPIC_ID="${TOPIC_ID:-hw3-forbidden-topic}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-hw3-sub}"

WEB_VM_A="${WEB_VM_A:-hw8-server-a}"
WEB_VM_B="${WEB_VM_B:-hw8-server-b}"
WEB_SA_NAME="${WEB_SA_NAME:-hw8-web-sa}"
WEB_SA_EMAIL="${WEB_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

APP_FIREWALL_RULE="${APP_FIREWALL_RULE:-hw8-allow-http-public}"
HEALTH_FIREWALL_RULE="${HEALTH_FIREWALL_RULE:-hw8-allow-health-check}"
HEALTH_CHECK_NAME="${HEALTH_CHECK_NAME:-hw8-health-check}"
TARGET_POOL_NAME="${TARGET_POOL_NAME:-hw8-target-pool}"
ADDRESS_NAME="${ADDRESS_NAME:-hw8-lb-ip}"
FORWARDING_RULE_NAME="${FORWARDING_RULE_NAME:-hw8-forwarding-rule}"

CREATED_BUCKET=0
CREATED_TOPIC=0
CREATED_SUBSCRIPTION=0
CREATED_WEB_SA=0

if [ -f "${STATE_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
fi

echo "[cleanup] Deleting forwarding rule and target pool..."
gcloud compute forwarding-rules delete "${FORWARDING_RULE_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1 || true
gcloud compute target-pools remove-instances "${TARGET_POOL_NAME}" --instances="${WEB_VM_A}" --instances-zone="${ZONE_A}" --region="${REGION}" >/dev/null 2>&1 || true
gcloud compute target-pools remove-instances "${TARGET_POOL_NAME}" --instances="${WEB_VM_B}" --instances-zone="${ZONE_B}" --region="${REGION}" >/dev/null 2>&1 || true
gcloud compute target-pools delete "${TARGET_POOL_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1 || true

echo "[cleanup] Deleting health check and address..."
gcloud compute http-health-checks delete "${HEALTH_CHECK_NAME}" --quiet >/dev/null 2>&1 || true
gcloud compute addresses delete "${ADDRESS_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1 || true

echo "[cleanup] Deleting VMs..."
gcloud compute instances delete "${WEB_VM_A}" --zone="${ZONE_A}" --quiet >/dev/null 2>&1 || true
gcloud compute instances delete "${WEB_VM_B}" --zone="${ZONE_B}" --quiet >/dev/null 2>&1 || true

echo "[cleanup] Deleting firewall rules..."
gcloud compute firewall-rules delete "${APP_FIREWALL_RULE}" --quiet >/dev/null 2>&1 || true
gcloud compute firewall-rules delete "${HEALTH_FIREWALL_RULE}" --quiet >/dev/null 2>&1 || true

if [ "${CREATED_SUBSCRIPTION}" = "1" ]; then
  gcloud pubsub subscriptions delete "${SUBSCRIPTION_ID}" >/dev/null 2>&1 || true
fi

if [ "${CREATED_TOPIC}" = "1" ]; then
  gcloud pubsub topics delete "${TOPIC_ID}" >/dev/null 2>&1 || true
fi

if [ "${CREATED_WEB_SA}" = "1" ]; then
  gcloud iam service-accounts delete "${WEB_SA_EMAIL}" --quiet >/dev/null 2>&1 || true
fi

if [ "${CREATED_BUCKET}" = "1" ]; then
  gcloud storage rm --recursive "gs://${BUCKET_NAME}" >/dev/null 2>&1 || true
fi

rm -f "${STATE_FILE}"
echo "[cleanup] Done"
