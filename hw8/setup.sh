#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw8_state.env"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
REGION="${REGION:-us-central1}"
ZONE_A="${ZONE_A:-us-central1-a}"
ZONE_B="${ZONE_B:-us-central1-b}"

BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
TOPIC_ID="${TOPIC_ID:-hw3-forbidden-topic}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-hw3-sub}"
BUILD_ID="${BUILD_ID:-hw8-vm}"

WEB_VM_A="${WEB_VM_A:-hw8-server-a}"
WEB_VM_B="${WEB_VM_B:-hw8-server-b}"
WEB_TAG="${WEB_TAG:-hw8-web}"
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
CREATED_APP_FIREWALL=0
CREATED_HEALTH_FIREWALL=0
CREATED_VM_A=0
CREATED_VM_B=0
CREATED_HTTP_HEALTH_CHECK=0
CREATED_TARGET_POOL=0
CREATED_ADDRESS=0
CREATED_FORWARDING_RULE=0

SERVER_PY_B64="$(base64 -w 0 "${SCRIPT_DIR}/service1_server.py")"

create_web_vm_if_needed() {
  local vm_name="$1"
  local zone="$2"
  local created_var="$3"
  if gcloud compute instances describe "${vm_name}" --zone="${zone}" >/dev/null 2>&1; then
    echo "[setup] VM exists: ${vm_name} (${zone})"
    return
  fi

  gcloud compute instances create "${vm_name}" \
    --zone="${zone}" \
    --machine-type="e2-micro" \
    --image-family="ubuntu-2404-lts-amd64" \
    --image-project="ubuntu-os-cloud" \
    --service-account="${WEB_SA_EMAIL}" \
    --scopes="https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/pubsub,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write" \
    --tags="${WEB_TAG}" \
    --metadata="BUCKET_NAME=${BUCKET_NAME},TOPIC_ID=${TOPIC_ID},BUILD_ID=${BUILD_ID},SERVER_PY_B64=${SERVER_PY_B64}" \
    --metadata-from-file "startup-script=${SCRIPT_DIR}/startup_web.sh" >/dev/null

  printf -v "${created_var}" '%s' "1"
  echo "[setup] Created VM: ${vm_name} (${zone})"
}

echo "[setup] Project: ${PROJECT_ID} (${PROJECT_NUMBER})"
echo "[setup] Region/Zones: ${REGION} / ${ZONE_A}, ${ZONE_B}"

echo "[setup] Enabling required APIs..."
gcloud services enable compute.googleapis.com pubsub.googleapis.com storage.googleapis.com logging.googleapis.com monitoring.googleapis.com iam.googleapis.com >/dev/null

if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "[setup] Bucket exists: gs://${BUCKET_NAME}"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" --location="${REGION}" >/dev/null
  CREATED_BUCKET=1
  echo "[setup] Created bucket: gs://${BUCKET_NAME}"
fi

TMP_DIR="$(mktemp -d)"
printf '<h1>hello hw8</h1>\n' > "${TMP_DIR}/index.html"
printf '<h1>file 0</h1>\n' > "${TMP_DIR}/0.html"
gcloud storage cp "${TMP_DIR}/index.html" "gs://${BUCKET_NAME}/index.html" >/dev/null
gcloud storage cp "${TMP_DIR}/0.html" "gs://${BUCKET_NAME}/0.html" >/dev/null
rm -rf "${TMP_DIR}"

if gcloud iam service-accounts describe "${WEB_SA_EMAIL}" >/dev/null 2>&1; then
  echo "[setup] Service account exists: ${WEB_SA_EMAIL}"
else
  gcloud iam service-accounts create "${WEB_SA_NAME}" --display-name="HW8 Web SA" >/dev/null
  CREATED_WEB_SA=1
  echo "[setup] Created service account: ${WEB_SA_EMAIL}"
fi

echo "[setup] Applying IAM roles..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/pubsub.publisher" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/monitoring.metricWriter" >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/storage.objectViewer" >/dev/null

if gcloud pubsub topics describe "${TOPIC_ID}" >/dev/null 2>&1; then
  echo "[setup] Topic exists: ${TOPIC_ID}"
else
  gcloud pubsub topics create "${TOPIC_ID}" >/dev/null
  CREATED_TOPIC=1
fi

if gcloud pubsub subscriptions describe "${SUBSCRIPTION_ID}" >/dev/null 2>&1; then
  echo "[setup] Subscription exists: ${SUBSCRIPTION_ID}"
else
  gcloud pubsub subscriptions create "${SUBSCRIPTION_ID}" --topic "${TOPIC_ID}" >/dev/null
  CREATED_SUBSCRIPTION=1
fi

if gcloud compute firewall-rules describe "${APP_FIREWALL_RULE}" >/dev/null 2>&1; then
  echo "[setup] Firewall exists: ${APP_FIREWALL_RULE}"
else
  gcloud compute firewall-rules create "${APP_FIREWALL_RULE}" \
    --allow=tcp:80 \
    --target-tags="${WEB_TAG}" \
    --source-ranges="0.0.0.0/0" >/dev/null
  CREATED_APP_FIREWALL=1
fi

if gcloud compute firewall-rules describe "${HEALTH_FIREWALL_RULE}" >/dev/null 2>&1; then
  echo "[setup] Firewall exists: ${HEALTH_FIREWALL_RULE}"
else
  gcloud compute firewall-rules create "${HEALTH_FIREWALL_RULE}" \
    --allow=tcp:80 \
    --target-tags="${WEB_TAG}" \
    --source-ranges="35.191.0.0/16,130.211.0.0/22" >/dev/null
  CREATED_HEALTH_FIREWALL=1
fi

create_web_vm_if_needed "${WEB_VM_A}" "${ZONE_A}" CREATED_VM_A
create_web_vm_if_needed "${WEB_VM_B}" "${ZONE_B}" CREATED_VM_B

if gcloud compute http-health-checks describe "${HEALTH_CHECK_NAME}" >/dev/null 2>&1; then
  echo "[setup] HTTP health check exists: ${HEALTH_CHECK_NAME}"
else
  gcloud compute http-health-checks create "${HEALTH_CHECK_NAME}" \
    --request-path="/healthz" \
    --port=80 \
    --check-interval=5s \
    --timeout=5s \
    --healthy-threshold=2 \
    --unhealthy-threshold=2 >/dev/null
  CREATED_HTTP_HEALTH_CHECK=1
fi

if gcloud compute target-pools describe "${TARGET_POOL_NAME}" --region="${REGION}" >/dev/null 2>&1; then
  echo "[setup] Target pool exists: ${TARGET_POOL_NAME}"
else
  gcloud compute target-pools create "${TARGET_POOL_NAME}" \
    --region="${REGION}" \
    --http-health-check="${HEALTH_CHECK_NAME}" \
    --session-affinity="NONE" >/dev/null
  CREATED_TARGET_POOL=1
fi

echo "[setup] Registering backend instances in target pool..."
gcloud compute target-pools add-instances "${TARGET_POOL_NAME}" \
  --region="${REGION}" \
  --instances="${WEB_VM_A}" \
  --instances-zone="${ZONE_A}" >/dev/null 2>&1 || true
gcloud compute target-pools add-instances "${TARGET_POOL_NAME}" \
  --region="${REGION}" \
  --instances="${WEB_VM_B}" \
  --instances-zone="${ZONE_B}" >/dev/null 2>&1 || true

if gcloud compute addresses describe "${ADDRESS_NAME}" --region="${REGION}" >/dev/null 2>&1; then
  echo "[setup] Address exists: ${ADDRESS_NAME}"
else
  gcloud compute addresses create "${ADDRESS_NAME}" --region="${REGION}" >/dev/null
  CREATED_ADDRESS=1
fi

LB_IP="$(gcloud compute addresses describe "${ADDRESS_NAME}" --region="${REGION}" --format='value(address)')"

if gcloud compute forwarding-rules describe "${FORWARDING_RULE_NAME}" --region="${REGION}" >/dev/null 2>&1; then
  echo "[setup] Forwarding rule exists: ${FORWARDING_RULE_NAME}"
else
  gcloud compute forwarding-rules create "${FORWARDING_RULE_NAME}" \
    --region="${REGION}" \
    --address="${ADDRESS_NAME}" \
    --ports="80" \
    --target-pool="${TARGET_POOL_NAME}" >/dev/null
  CREATED_FORWARDING_RULE=1
fi

cat > "${STATE_FILE}" <<EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE_A=${ZONE_A}
ZONE_B=${ZONE_B}
BUCKET_NAME=${BUCKET_NAME}
TOPIC_ID=${TOPIC_ID}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
BUILD_ID=${BUILD_ID}
WEB_VM_A=${WEB_VM_A}
WEB_VM_B=${WEB_VM_B}
WEB_TAG=${WEB_TAG}
WEB_SA_NAME=${WEB_SA_NAME}
WEB_SA_EMAIL=${WEB_SA_EMAIL}
APP_FIREWALL_RULE=${APP_FIREWALL_RULE}
HEALTH_FIREWALL_RULE=${HEALTH_FIREWALL_RULE}
HEALTH_CHECK_NAME=${HEALTH_CHECK_NAME}
TARGET_POOL_NAME=${TARGET_POOL_NAME}
ADDRESS_NAME=${ADDRESS_NAME}
FORWARDING_RULE_NAME=${FORWARDING_RULE_NAME}
LB_IP=${LB_IP}
CREATED_BUCKET=${CREATED_BUCKET}
CREATED_TOPIC=${CREATED_TOPIC}
CREATED_SUBSCRIPTION=${CREATED_SUBSCRIPTION}
CREATED_WEB_SA=${CREATED_WEB_SA}
CREATED_APP_FIREWALL=${CREATED_APP_FIREWALL}
CREATED_HEALTH_FIREWALL=${CREATED_HEALTH_FIREWALL}
CREATED_VM_A=${CREATED_VM_A}
CREATED_VM_B=${CREATED_VM_B}
CREATED_HTTP_HEALTH_CHECK=${CREATED_HTTP_HEALTH_CHECK}
CREATED_TARGET_POOL=${CREATED_TARGET_POOL}
CREATED_ADDRESS=${CREATED_ADDRESS}
CREATED_FORWARDING_RULE=${CREATED_FORWARDING_RULE}
EOF

echo "[setup] Done"
echo "[setup] Load balancer IP: ${LB_IP}"
echo "[setup] Validation commands:"
echo "  curl -i \"http://${LB_IP}/healthz\""
echo "  curl -i \"http://${LB_IP}/?file=index.html\""
echo "  gcloud compute target-pools get-health ${TARGET_POOL_NAME} --region=${REGION}"
