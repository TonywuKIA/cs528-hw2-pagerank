#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw5_state.env"

PROJECT_ID="sonorous-sign-487022-a1"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
TOPIC_ID="${TOPIC_ID:-hw3-forbidden-topic}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-hw3-sub}"
LOG_OBJECT="${LOG_OBJECT:-forbidden/forbidden_requests.log}"

SERVER_VM="${SERVER_VM:-hw5-server-vm}"
FORBIDDEN_VM="${FORBIDDEN_VM:-hw5-forbidden-vm}"
SERVER_MACHINE_TYPE="${SERVER_MACHINE_TYPE:-e2-standard-4}"
FORBIDDEN_MACHINE_TYPE="${FORBIDDEN_MACHINE_TYPE:-e2-micro}"

SERVER_SA_NAME="${SERVER_SA_NAME:-hw5-server-sa}"
FORBIDDEN_SA_NAME="${FORBIDDEN_SA_NAME:-hw5-forbidden-sa}"
FUNCTION_SA_NAME="${FUNCTION_SA_NAME:-hw5-db-stop-sa}"
SCHEDULER_SA_NAME="${SCHEDULER_SA_NAME:-hw5-scheduler-sa}"

SERVER_SA_EMAIL="${SERVER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
FORBIDDEN_SA_EMAIL="${FORBIDDEN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
FUNCTION_SA_EMAIL="${FUNCTION_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
SCHEDULER_SA_EMAIL="${SCHEDULER_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

SERVER_IP_NAME="${SERVER_IP_NAME:-hw5-server-ip}"
FIREWALL_RULE="${FIREWALL_RULE:-hw5-allow-http}"
DB_INSTANCE_NAME="${DB_INSTANCE_NAME:-hw5-sql}"
DB_VERSION="${DB_VERSION:-POSTGRES_16}"
DB_TIER="${DB_TIER:-db-custom-1-3840}"
DB_NAME="${DB_NAME:-hw5db}"
DB_USER="${DB_USER:-hw5user}"
DB_PASS="${DB_PASS:-Hw5Pass_528_Project!}"

DB_FUNCTION_NAME="${DB_FUNCTION_NAME:-hw5-stop-sql}"
DB_FUNCTION_REGION="${DB_FUNCTION_REGION:-us-central1}"
SCHEDULER_JOB_NAME="${SCHEDULER_JOB_NAME:-hw5-stop-sql-hourly}"
STOP_SQL_ENABLED="${STOP_SQL_ENABLED:-true}"

create_sa_if_needed() {
  local sa_name="$1"
  local sa_email="$2"
  local label="$3"
  if gcloud iam service-accounts describe "${sa_email}" >/dev/null 2>&1; then
    echo "[setup] Service account exists: ${sa_email}"
  else
    gcloud iam service-accounts create "${sa_name}" --display-name="${label}" >/dev/null
    echo "[setup] Created service account: ${sa_email}"
  fi
}

echo "[setup] Project: ${PROJECT_ID} (${PROJECT_NUMBER})"
echo "[setup] Region/Zone: ${REGION}/${ZONE}"

echo "[setup] Enabling required APIs..."
gcloud services enable \
  compute.googleapis.com \
  pubsub.googleapis.com \
  storage.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  iam.googleapis.com \
  sqladmin.googleapis.com \
  cloudfunctions.googleapis.com \
  cloudscheduler.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  run.googleapis.com >/dev/null

if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "[setup] Bucket exists: gs://${BUCKET_NAME}"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" --location="${REGION}" >/dev/null
fi

TMP_DIR="$(mktemp -d)"
printf '<h1>hello hw5</h1>\n' > "${TMP_DIR}/index.html"
printf '<h1>file 0</h1>\n' > "${TMP_DIR}/0.html"
gcloud storage cp "${TMP_DIR}/index.html" "gs://${BUCKET_NAME}/index.html" >/dev/null
gcloud storage cp "${TMP_DIR}/0.html" "gs://${BUCKET_NAME}/0.html" >/dev/null
rm -rf "${TMP_DIR}"

create_sa_if_needed "${SERVER_SA_NAME}" "${SERVER_SA_EMAIL}" "HW5 Server SA"
create_sa_if_needed "${FORBIDDEN_SA_NAME}" "${FORBIDDEN_SA_EMAIL}" "HW5 Forbidden SA"
create_sa_if_needed "${FUNCTION_SA_NAME}" "${FUNCTION_SA_EMAIL}" "HW5 DB Stop Function SA"
create_sa_if_needed "${SCHEDULER_SA_NAME}" "${SCHEDULER_SA_EMAIL}" "HW5 Scheduler SA"

echo "[setup] Applying IAM roles..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/pubsub.publisher" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/monitoring.metricWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/cloudsql.client" >/dev/null

gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/pubsub.subscriber" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/monitoring.metricWriter" >/dev/null

gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FUNCTION_SA_EMAIL}" --role="roles/cloudsql.admin" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FUNCTION_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${SCHEDULER_SA_EMAIL}" --role="roles/run.invoker" >/dev/null

gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${SERVER_SA_EMAIL}" --role="roles/storage.objectViewer" >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/storage.objectAdmin" >/dev/null

if gcloud pubsub topics describe "${TOPIC_ID}" >/dev/null 2>&1; then
  echo "[setup] Topic exists: ${TOPIC_ID}"
else
  gcloud pubsub topics create "${TOPIC_ID}" >/dev/null
fi

if gcloud pubsub subscriptions describe "${SUBSCRIPTION_ID}" >/dev/null 2>&1; then
  echo "[setup] Subscription exists: ${SUBSCRIPTION_ID}"
else
  gcloud pubsub subscriptions create "${SUBSCRIPTION_ID}" --topic "${TOPIC_ID}" >/dev/null
fi

if gcloud sql instances describe "${DB_INSTANCE_NAME}" >/dev/null 2>&1; then
  echo "[setup] Cloud SQL instance exists: ${DB_INSTANCE_NAME}"
else
  echo "[setup] Creating Cloud SQL instance..."
  gcloud sql instances create "${DB_INSTANCE_NAME}" \
    --database-version="${DB_VERSION}" \
    --tier="${DB_TIER}" \
    --region="${REGION}" \
    --edition=enterprise \
    --storage-size=10GB \
    --storage-type=SSD \
    --assign-ip \
    --authorized-networks=0.0.0.0/0 >/dev/null
fi

echo "[setup] Starting Cloud SQL instance..."
gcloud sql instances patch "${DB_INSTANCE_NAME}" --activation-policy=ALWAYS --quiet >/dev/null

gcloud sql users create "${DB_USER}" --instance="${DB_INSTANCE_NAME}" --password="${DB_PASS}" >/dev/null 2>&1 || \
  gcloud sql users set-password "${DB_USER}" --instance="${DB_INSTANCE_NAME}" --password="${DB_PASS}" >/dev/null

DB_HOST="$(gcloud sql instances describe "${DB_INSTANCE_NAME}" --format='value(ipAddresses[0].ipAddress)')"
DB_CONN_NAME="${PROJECT_ID}:${REGION}:${DB_INSTANCE_NAME}"

SETUP_PYTHON="python"
if command -v py >/dev/null 2>&1; then
  SETUP_PYTHON="py -3"
fi

SETUP_VENV="${SCRIPT_DIR}/.setup_venv"
${SETUP_PYTHON} -m venv "${SETUP_VENV}"
if [ -x "${SETUP_VENV}/Scripts/python.exe" ]; then
  SETUP_VENV_PY="${SETUP_VENV}/Scripts/python.exe"
else
  SETUP_VENV_PY="${SETUP_VENV}/bin/python"
fi

"${SETUP_VENV_PY}" -m pip install --upgrade pip >/dev/null
"${SETUP_VENV_PY}" -m pip install "cloud-sql-python-connector[pg8000]==1.18.2" "pg8000==1.31.2" >/dev/null

DB_HOST="${DB_HOST}" \
DB_PORT=5432 \
DB_INSTANCE_CONNECTION_NAME="${DB_CONN_NAME}" \
DB_NAME="${DB_NAME}" \
DB_USER="${DB_USER}" \
DB_PASS="${DB_PASS}" \
"${SETUP_VENV_PY}" "${SCRIPT_DIR}/setup_schema.py"

if gcloud compute addresses describe "${SERVER_IP_NAME}" --region="${REGION}" >/dev/null 2>&1; then
  echo "[setup] Address exists: ${SERVER_IP_NAME}"
else
  gcloud compute addresses create "${SERVER_IP_NAME}" --region="${REGION}" >/dev/null
fi

SERVER_IP="$(gcloud compute addresses describe "${SERVER_IP_NAME}" --region="${REGION}" --format='value(address)')"

if gcloud compute firewall-rules describe "${FIREWALL_RULE}" >/dev/null 2>&1; then
  echo "[setup] Firewall exists: ${FIREWALL_RULE}"
else
  gcloud compute firewall-rules create "${FIREWALL_RULE}" --allow=tcp:80 --target-tags=hw5-server >/dev/null
fi

if gcloud compute instances describe "${SERVER_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "[setup] VM exists: ${SERVER_VM}"
  gcloud compute instances add-metadata "${SERVER_VM}" \
    --zone="${ZONE}" \
    --metadata="BUCKET_NAME=${BUCKET_NAME},TOPIC_ID=${TOPIC_ID},BUILD_ID=hw5-vm,DB_INSTANCE_CONNECTION_NAME=${DB_CONN_NAME},DB_HOST=${DB_HOST},DB_NAME=${DB_NAME},DB_USER=${DB_USER},DB_PASS=${DB_PASS}" \
    --metadata-from-file="startup-script=${SCRIPT_DIR}/startup.sh,APP_DB_PY=${SCRIPT_DIR}/db.py,APP_SERVICE1_PY=${SCRIPT_DIR}/service1_server.py,APP_QUERY_STATS_PY=${SCRIPT_DIR}/query_stats.py" >/dev/null
else
  gcloud compute instances create "${SERVER_VM}" \
    --zone="${ZONE}" \
    --machine-type="${SERVER_MACHINE_TYPE}" \
    --image-family="ubuntu-2404-lts-amd64" \
    --image-project="ubuntu-os-cloud" \
    --service-account="${SERVER_SA_EMAIL}" \
    --scopes="https://www.googleapis.com/auth/cloud-platform" \
    --address="${SERVER_IP}" \
    --tags="hw5-server" \
    --metadata="BUCKET_NAME=${BUCKET_NAME},TOPIC_ID=${TOPIC_ID},BUILD_ID=hw5-vm,DB_INSTANCE_CONNECTION_NAME=${DB_CONN_NAME},DB_HOST=${DB_HOST},DB_NAME=${DB_NAME},DB_USER=${DB_USER},DB_PASS=${DB_PASS}" \
    --metadata-from-file="startup-script=${SCRIPT_DIR}/startup.sh,APP_DB_PY=${SCRIPT_DIR}/db.py,APP_SERVICE1_PY=${SCRIPT_DIR}/service1_server.py,APP_QUERY_STATS_PY=${SCRIPT_DIR}/query_stats.py" >/dev/null
fi

if gcloud compute instances describe "${FORBIDDEN_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "[setup] VM exists: ${FORBIDDEN_VM}"
  gcloud compute instances add-metadata "${FORBIDDEN_VM}" \
    --zone="${ZONE}" \
    --metadata="SUBSCRIPTION_ID=${SUBSCRIPTION_ID},BUCKET_NAME=${BUCKET_NAME},LOG_OBJECT=${LOG_OBJECT}" \
    --metadata-from-file="startup-script=${SCRIPT_DIR}/startup_forbidden.sh,APP_SERVICE2_PY=${SCRIPT_DIR}/service2_subscriber.py" >/dev/null
else
  gcloud compute instances create "${FORBIDDEN_VM}" \
    --zone="${ZONE}" \
    --machine-type="${FORBIDDEN_MACHINE_TYPE}" \
    --image-family="ubuntu-2404-lts-amd64" \
    --image-project="ubuntu-os-cloud" \
    --service-account="${FORBIDDEN_SA_EMAIL}" \
    --scopes="https://www.googleapis.com/auth/cloud-platform" \
    --metadata="SUBSCRIPTION_ID=${SUBSCRIPTION_ID},BUCKET_NAME=${BUCKET_NAME},LOG_OBJECT=${LOG_OBJECT}" \
    --metadata-from-file="startup-script=${SCRIPT_DIR}/startup_forbidden.sh,APP_SERVICE2_PY=${SCRIPT_DIR}/service2_subscriber.py" >/dev/null
fi

echo "[setup] Deploying stop-sql Cloud Function..."
gcloud functions deploy "${DB_FUNCTION_NAME}" \
  --gen2 \
  --runtime=python312 \
  --region="${DB_FUNCTION_REGION}" \
  --source="${SCRIPT_DIR}/stop_sql_function" \
  --entry-point=stop_sql_if_enabled \
  --trigger-http \
  --allow-unauthenticated \
  --service-account="${FUNCTION_SA_EMAIL}" \
  --set-env-vars="PROJECT_ID=${PROJECT_ID},INSTANCE_NAME=${DB_INSTANCE_NAME},STOP_SQL_ENABLED=${STOP_SQL_ENABLED}" >/dev/null

FUNCTION_URL="$(gcloud functions describe "${DB_FUNCTION_NAME}" --gen2 --region="${DB_FUNCTION_REGION}" --format='value(serviceConfig.uri)')"

if gcloud scheduler jobs describe "${SCHEDULER_JOB_NAME}" --location="${DB_FUNCTION_REGION}" >/dev/null 2>&1; then
  gcloud scheduler jobs update http "${SCHEDULER_JOB_NAME}" \
    --location="${DB_FUNCTION_REGION}" \
    --schedule="0 * * * *" \
    --uri="${FUNCTION_URL}" \
    --http-method=GET \
    --oidc-service-account-email="${SCHEDULER_SA_EMAIL}" >/dev/null
else
  gcloud scheduler jobs create http "${SCHEDULER_JOB_NAME}" \
    --location="${DB_FUNCTION_REGION}" \
    --schedule="0 * * * *" \
    --uri="${FUNCTION_URL}" \
    --http-method=GET \
    --oidc-service-account-email="${SCHEDULER_SA_EMAIL}" >/dev/null
fi

cat > "${STATE_FILE}" <<EOF
PROJECT_ID=${PROJECT_ID}
REGION=${REGION}
ZONE=${ZONE}
SERVER_VM=${SERVER_VM}
FORBIDDEN_VM=${FORBIDDEN_VM}
SERVER_IP_NAME=${SERVER_IP_NAME}
FIREWALL_RULE=${FIREWALL_RULE}
DB_INSTANCE_NAME=${DB_INSTANCE_NAME}
DB_FUNCTION_NAME=${DB_FUNCTION_NAME}
DB_FUNCTION_REGION=${DB_FUNCTION_REGION}
SCHEDULER_JOB_NAME=${SCHEDULER_JOB_NAME}
SERVER_IP=${SERVER_IP}
DB_HOST=${DB_HOST}
EOF

echo "[setup] Done"
echo "[setup] Server endpoint: http://${SERVER_IP}/?file=index.html"
echo "[setup] Cloud SQL host: ${DB_HOST}"
echo "[setup] Screenshot now: Cloud SQL instance running and schema created."
echo "[setup] Screenshot now: setup completion with VM names, static IP, and DB status."
