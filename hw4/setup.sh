#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw4_state.env"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
TOPIC_ID="${TOPIC_ID:-hw3-forbidden-topic}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-hw3-sub}"
LOG_OBJECT="${LOG_OBJECT:-forbidden/forbidden_requests.log}"

SERVER_VM="${SERVER_VM:-hw4-server-vm}"
FORBIDDEN_VM="${FORBIDDEN_VM:-hw4-forbidden-vm}"
CLIENT_VM="${CLIENT_VM:-hw4-client-vm}"
CREATE_CLIENT_VM="${CREATE_CLIENT_VM:-true}"

SERVER_SA_NAME="${SERVER_SA_NAME:-hw4-server-sa}"
FORBIDDEN_SA_NAME="${FORBIDDEN_SA_NAME:-hw4-forbidden-sa}"
CLIENT_SA_NAME="${CLIENT_SA_NAME:-hw4-client-sa}"

SERVER_SA_EMAIL="${SERVER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
FORBIDDEN_SA_EMAIL="${FORBIDDEN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CLIENT_SA_EMAIL="${CLIENT_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

SERVER_IP_NAME="${SERVER_IP_NAME:-hw4-server-ip}"
FIREWALL_RULE="${FIREWALL_RULE:-hw4-allow-http}"

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

create_sa_if_needed() {
  local sa_name="$1"
  local sa_email="$2"
  local label="$3"
  if gcloud iam service-accounts describe "${sa_email}" >/dev/null 2>&1; then
    echo "[setup] Service account exists: ${sa_email}"
  else
    gcloud iam service-accounts create "${sa_name}" --display-name="${label}"
    echo "[setup] Created service account: ${sa_email}"
    case "${sa_name}" in
      "${SERVER_SA_NAME}") CREATED_SERVER_SA=1 ;;
      "${FORBIDDEN_SA_NAME}") CREATED_FORBIDDEN_SA=1 ;;
      "${CLIENT_SA_NAME}") CREATED_CLIENT_SA=1 ;;
    esac
  fi
}

echo "[setup] Project: ${PROJECT_ID} (${PROJECT_NUMBER})"
echo "[setup] Region/Zone: ${REGION}/${ZONE}"

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
printf '<h1>hello hw4</h1>\n' > "${TMP_DIR}/index.html"
printf '<h1>file 0</h1>\n' > "${TMP_DIR}/0.html"
gcloud storage cp "${TMP_DIR}/index.html" "gs://${BUCKET_NAME}/index.html" >/dev/null
gcloud storage cp "${TMP_DIR}/0.html" "gs://${BUCKET_NAME}/0.html" >/dev/null
rm -rf "${TMP_DIR}"

create_sa_if_needed "${SERVER_SA_NAME}" "${SERVER_SA_EMAIL}" "HW4 Server SA"
create_sa_if_needed "${FORBIDDEN_SA_NAME}" "${FORBIDDEN_SA_EMAIL}" "HW4 Forbidden SA"
create_sa_if_needed "${CLIENT_SA_NAME}" "${CLIENT_SA_EMAIL}" "HW4 Client SA"

echo "[setup] Applying IAM roles..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/pubsub.publisher" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/monitoring.metricWriter" >/dev/null

gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/pubsub.subscriber" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/monitoring.metricWriter" >/dev/null

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/storage.objectViewer" >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/storage.objectAdmin" >/dev/null

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

if gcloud compute addresses describe "${SERVER_IP_NAME}" --region="${REGION}" >/dev/null 2>&1; then
  echo "[setup] Address exists: ${SERVER_IP_NAME}"
else
  gcloud compute addresses create "${SERVER_IP_NAME}" --region="${REGION}" >/dev/null
  CREATED_ADDRESS=1
fi

SERVER_IP="$(gcloud compute addresses describe "${SERVER_IP_NAME}" --region="${REGION}" --format='value(address)')"

if gcloud compute firewall-rules describe "${FIREWALL_RULE}" >/dev/null 2>&1; then
  echo "[setup] Firewall exists: ${FIREWALL_RULE}"
else
  gcloud compute firewall-rules create "${FIREWALL_RULE}" --allow=tcp:80 --target-tags=hw4-server >/dev/null
  CREATED_FIREWALL=1
fi

if gcloud compute instances describe "${SERVER_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "[setup] VM exists: ${SERVER_VM}"
else
  gcloud compute instances create "${SERVER_VM}" \
    --zone="${ZONE}" \
    --machine-type="e2-micro" \
    --service-account="${SERVER_SA_EMAIL}" \
    --scopes="https://www.googleapis.com/auth/devstorage.read_only,https://www.googleapis.com/auth/pubsub,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write" \
    --address="${SERVER_IP}" \
    --tags="hw4-server" \
    --metadata="BUCKET_NAME=${BUCKET_NAME},TOPIC_ID=${TOPIC_ID},BUILD_ID=hw4-vm" \
    --metadata-from-file "startup-script=${SCRIPT_DIR}/startup.sh" >/dev/null
  CREATED_SERVER_VM=1
fi

if gcloud compute instances describe "${FORBIDDEN_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "[setup] VM exists: ${FORBIDDEN_VM}"
else
  gcloud compute instances create "${FORBIDDEN_VM}" \
    --zone="${ZONE}" \
    --machine-type="e2-micro" \
    --service-account="${FORBIDDEN_SA_EMAIL}" \
    --scopes="https://www.googleapis.com/auth/devstorage.read_write,https://www.googleapis.com/auth/pubsub,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write" \
    --metadata="SUBSCRIPTION_ID=${SUBSCRIPTION_ID},BUCKET_NAME=${BUCKET_NAME},LOG_OBJECT=${LOG_OBJECT}" \
    --metadata-from-file "startup-script=${SCRIPT_DIR}/startup_forbidden.sh" >/dev/null
  CREATED_FORBIDDEN_VM=1
fi

if [ "${CREATE_CLIENT_VM}" = "true" ]; then
  if gcloud compute instances describe "${CLIENT_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
    echo "[setup] VM exists: ${CLIENT_VM}"
  else
    gcloud compute instances create "${CLIENT_VM}" \
      --zone="${ZONE}" \
      --machine-type="e2-micro" \
      --image-family="ubuntu-2404-lts-amd64" \
      --image-project="ubuntu-os-cloud" \
      --service-account="${CLIENT_SA_EMAIL}" \
      --scopes="https://www.googleapis.com/auth/logging.write" >/dev/null
    CREATED_CLIENT_VM=1
  fi
fi

cat > "${STATE_FILE}" <<EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
TOPIC_ID=${TOPIC_ID}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
LOG_OBJECT=${LOG_OBJECT}
SERVER_VM=${SERVER_VM}
FORBIDDEN_VM=${FORBIDDEN_VM}
CLIENT_VM=${CLIENT_VM}
CREATE_CLIENT_VM=${CREATE_CLIENT_VM}
SERVER_SA_NAME=${SERVER_SA_NAME}
FORBIDDEN_SA_NAME=${FORBIDDEN_SA_NAME}
CLIENT_SA_NAME=${CLIENT_SA_NAME}
SERVER_SA_EMAIL=${SERVER_SA_EMAIL}
FORBIDDEN_SA_EMAIL=${FORBIDDEN_SA_EMAIL}
CLIENT_SA_EMAIL=${CLIENT_SA_EMAIL}
SERVER_IP_NAME=${SERVER_IP_NAME}
FIREWALL_RULE=${FIREWALL_RULE}
CREATED_BUCKET=${CREATED_BUCKET}
CREATED_SERVER_SA=${CREATED_SERVER_SA}
CREATED_FORBIDDEN_SA=${CREATED_FORBIDDEN_SA}
CREATED_CLIENT_SA=${CREATED_CLIENT_SA}
CREATED_TOPIC=${CREATED_TOPIC}
CREATED_SUBSCRIPTION=${CREATED_SUBSCRIPTION}
CREATED_ADDRESS=${CREATED_ADDRESS}
CREATED_FIREWALL=${CREATED_FIREWALL}
CREATED_SERVER_VM=${CREATED_SERVER_VM}
CREATED_FORBIDDEN_VM=${CREATED_FORBIDDEN_VM}
CREATED_CLIENT_VM=${CREATED_CLIENT_VM}
EOF

echo "[setup] Done"
echo "[setup] Server endpoint: http://${SERVER_IP}/?file=index.html"
