#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw9_state.env"
RENDERED_MANIFEST="${SCRIPT_DIR}/.hw9-web.rendered.yaml"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)')"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"

BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
TOPIC_ID="${TOPIC_ID:-hw3-forbidden-topic}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-hw3-sub}"
LOG_OBJECT="${LOG_OBJECT:-forbidden/forbidden_requests.log}"

CLUSTER_NAME="${CLUSTER_NAME:-hw9-gke}"
AR_REPO="${AR_REPO:-hw9-repo}"
IMAGE_NAME="${IMAGE_NAME:-hw9-web}"
IMAGE_TAG="${IMAGE_TAG:-$(date +%Y%m%d-%H%M%S)}"
IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${IMAGE_NAME}:${IMAGE_TAG}"

WEB_SA_NAME="${WEB_SA_NAME:-hw9-web-sa}"
WEB_SA_EMAIL="${WEB_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
FORBIDDEN_SA_NAME="${FORBIDDEN_SA_NAME:-hw9-forbidden-sa}"
FORBIDDEN_SA_EMAIL="${FORBIDDEN_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
CLIENT_SA_NAME="${CLIENT_SA_NAME:-hw9-client-sa}"
CLIENT_SA_EMAIL="${CLIENT_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

FORBIDDEN_VM="${FORBIDDEN_VM:-hw9-forbidden-vm}"
CLIENT_VM="${CLIENT_VM:-hw9-client-vm}"

CREATED_BUCKET=0
CREATED_TOPIC=0
CREATED_SUBSCRIPTION=0
CREATED_AR_REPO=0
CREATED_CLUSTER=0
CREATED_WEB_SA=0
CREATED_FORBIDDEN_SA=0
CREATED_CLIENT_SA=0
CREATED_FORBIDDEN_VM=0
CREATED_CLIENT_VM=0

create_sa_if_needed() {
  local sa_name="$1"
  local sa_email="$2"
  local label="$3"
  local created_var="$4"
  if gcloud iam service-accounts describe "${sa_email}" >/dev/null 2>&1; then
    echo "[setup] Service account exists: ${sa_email}"
  else
    gcloud iam service-accounts create "${sa_name}" --display-name="${label}" >/dev/null
    printf -v "${created_var}" '%s' "1"
    echo "[setup] Created service account: ${sa_email}"
  fi
}

echo "[setup] Project: ${PROJECT_ID} (${PROJECT_NUMBER})"
echo "[setup] Region/Zone: ${REGION}/${ZONE}"

echo "[setup] Enabling APIs..."
gcloud services enable \
  artifactregistry.googleapis.com \
  cloudbuild.googleapis.com \
  compute.googleapis.com \
  container.googleapis.com \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  logging.googleapis.com \
  monitoring.googleapis.com \
  pubsub.googleapis.com \
  storage.googleapis.com >/dev/null

if gcloud storage buckets describe "gs://${BUCKET_NAME}" >/dev/null 2>&1; then
  echo "[setup] Bucket exists: gs://${BUCKET_NAME}"
else
  gcloud storage buckets create "gs://${BUCKET_NAME}" --location="${REGION}" >/dev/null
  CREATED_BUCKET=1
  echo "[setup] Created bucket: gs://${BUCKET_NAME}"
fi

TMP_DIR="$(mktemp -d)"
printf '<h1>hello hw9</h1>\n' > "${TMP_DIR}/index.html"
printf '<h1>file 0</h1>\n' > "${TMP_DIR}/0.html"
gcloud storage cp "${TMP_DIR}/index.html" "gs://${BUCKET_NAME}/index.html" >/dev/null
gcloud storage cp "${TMP_DIR}/0.html" "gs://${BUCKET_NAME}/0.html" >/dev/null
rm -rf "${TMP_DIR}"

if gcloud pubsub topics describe "${TOPIC_ID}" >/dev/null 2>&1; then
  echo "[setup] Topic exists: ${TOPIC_ID}"
else
  gcloud pubsub topics create "${TOPIC_ID}" >/dev/null
  CREATED_TOPIC=1
fi

if gcloud pubsub subscriptions describe "${SUBSCRIPTION_ID}" >/dev/null 2>&1; then
  echo "[setup] Subscription exists: ${SUBSCRIPTION_ID}"
else
  gcloud pubsub subscriptions create "${SUBSCRIPTION_ID}" --topic="${TOPIC_ID}" >/dev/null
  CREATED_SUBSCRIPTION=1
fi

if gcloud artifacts repositories describe "${AR_REPO}" --location="${REGION}" >/dev/null 2>&1; then
  echo "[setup] Artifact Registry repo exists: ${AR_REPO}"
else
  gcloud artifacts repositories create "${AR_REPO}" \
    --repository-format=docker \
    --location="${REGION}" \
    --description="CS528 HW9 images" >/dev/null
  CREATED_AR_REPO=1
fi

create_sa_if_needed "${WEB_SA_NAME}" "${WEB_SA_EMAIL}" "HW9 GKE Web SA" CREATED_WEB_SA
create_sa_if_needed "${FORBIDDEN_SA_NAME}" "${FORBIDDEN_SA_EMAIL}" "HW9 Forbidden Subscriber SA" CREATED_FORBIDDEN_SA
create_sa_if_needed "${CLIENT_SA_NAME}" "${CLIENT_SA_EMAIL}" "HW9 Client VM SA" CREATED_CLIENT_SA

echo "[setup] Applying IAM roles..."
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/pubsub.publisher" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/monitoring.metricWriter" >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${WEB_SA_EMAIL}" --role="roles/storage.objectViewer" >/dev/null

gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/pubsub.subscriber" >/dev/null
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/logging.logWriter" >/dev/null
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member="serviceAccount:${FORBIDDEN_SA_EMAIL}" --role="roles/storage.objectAdmin" >/dev/null

gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${PROJECT_NUMBER}@cloudbuild.gserviceaccount.com" --role="roles/artifactregistry.writer" >/dev/null || true
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" --role="roles/artifactregistry.writer" >/dev/null || true
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member="serviceAccount:${PROJECT_NUMBER}-compute@developer.gserviceaccount.com" --role="roles/artifactregistry.reader" >/dev/null || true

echo "[setup] Building and pushing image with Cloud Build: ${IMAGE_URI}"
gcloud builds submit "${SCRIPT_DIR}" --tag="${IMAGE_URI}" >/dev/null

if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" >/dev/null 2>&1; then
  echo "[setup] GKE cluster exists: ${CLUSTER_NAME}"
else
  gcloud container clusters create-auto "${CLUSTER_NAME}" \
    --region="${REGION}" \
    --release-channel=regular >/dev/null
  CREATED_CLUSTER=1
fi

gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null

gcloud iam service-accounts add-iam-policy-binding "${WEB_SA_EMAIL}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="serviceAccount:${PROJECT_ID}.svc.id.goog[default/hw9-web-ksa]" >/dev/null

sed \
  -e "s#__GCP_SERVICE_ACCOUNT__#${WEB_SA_EMAIL}#g" \
  -e "s#__IMAGE_URI__#${IMAGE_URI}#g" \
  -e "s#__PROJECT_ID__#${PROJECT_ID}#g" \
  -e "s#__BUCKET_NAME__#${BUCKET_NAME}#g" \
  -e "s#__TOPIC_ID__#${TOPIC_ID}#g" \
  "${SCRIPT_DIR}/k8s/hw9-web.yaml" > "${RENDERED_MANIFEST}"

kubectl apply -f "${RENDERED_MANIFEST}" >/dev/null
kubectl rollout status deployment/hw9-web --timeout=300s

echo "[setup] Waiting for LoadBalancer external IP..."
EXTERNAL_IP=""
for _ in $(seq 1 60); do
  EXTERNAL_IP="$(kubectl get service hw9-web -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [ -n "${EXTERNAL_IP}" ]; then
    break
  fi
  sleep 10
done

if [ -z "${EXTERNAL_IP}" ]; then
  echo "[setup] Service external IP is still pending. Re-run: kubectl get svc hw9-web"
else
  echo "[setup] External IP: ${EXTERNAL_IP}"
fi

SUBSCRIBER_PY_B64="$(base64 -w 0 "${SCRIPT_DIR}/service2_subscriber.py")"

if gcloud compute instances describe "${FORBIDDEN_VM}" --zone="${ZONE}" >/dev/null 2>&1; then
  echo "[setup] VM exists: ${FORBIDDEN_VM}"
else
  gcloud compute instances create "${FORBIDDEN_VM}" \
    --zone="${ZONE}" \
    --machine-type="e2-micro" \
    --image-family="ubuntu-2404-lts-amd64" \
    --image-project="ubuntu-os-cloud" \
    --service-account="${FORBIDDEN_SA_EMAIL}" \
    --scopes="https://www.googleapis.com/auth/devstorage.read_write,https://www.googleapis.com/auth/pubsub,https://www.googleapis.com/auth/logging.write" \
    --metadata="SUBSCRIPTION_ID=${SUBSCRIPTION_ID},BUCKET_NAME=${BUCKET_NAME},LOG_OBJECT=${LOG_OBJECT},SUBSCRIBER_PY_B64=${SUBSCRIBER_PY_B64}" \
    --metadata-from-file="startup-script=${SCRIPT_DIR}/startup_forbidden.sh" >/dev/null
  CREATED_FORBIDDEN_VM=1
fi

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

cat > "${STATE_FILE}" <<EOF
PROJECT_ID=${PROJECT_ID}
PROJECT_NUMBER=${PROJECT_NUMBER}
REGION=${REGION}
ZONE=${ZONE}
BUCKET_NAME=${BUCKET_NAME}
TOPIC_ID=${TOPIC_ID}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
LOG_OBJECT=${LOG_OBJECT}
CLUSTER_NAME=${CLUSTER_NAME}
AR_REPO=${AR_REPO}
IMAGE_NAME=${IMAGE_NAME}
IMAGE_TAG=${IMAGE_TAG}
IMAGE_URI=${IMAGE_URI}
WEB_SA_NAME=${WEB_SA_NAME}
WEB_SA_EMAIL=${WEB_SA_EMAIL}
FORBIDDEN_SA_NAME=${FORBIDDEN_SA_NAME}
FORBIDDEN_SA_EMAIL=${FORBIDDEN_SA_EMAIL}
CLIENT_SA_NAME=${CLIENT_SA_NAME}
CLIENT_SA_EMAIL=${CLIENT_SA_EMAIL}
FORBIDDEN_VM=${FORBIDDEN_VM}
CLIENT_VM=${CLIENT_VM}
EXTERNAL_IP=${EXTERNAL_IP}
CREATED_BUCKET=${CREATED_BUCKET}
CREATED_TOPIC=${CREATED_TOPIC}
CREATED_SUBSCRIPTION=${CREATED_SUBSCRIPTION}
CREATED_AR_REPO=${CREATED_AR_REPO}
CREATED_CLUSTER=${CREATED_CLUSTER}
CREATED_WEB_SA=${CREATED_WEB_SA}
CREATED_FORBIDDEN_SA=${CREATED_FORBIDDEN_SA}
CREATED_CLIENT_SA=${CREATED_CLIENT_SA}
CREATED_FORBIDDEN_VM=${CREATED_FORBIDDEN_VM}
CREATED_CLIENT_VM=${CREATED_CLIENT_VM}
EOF

echo "[setup] Done"
echo "[setup] Validation commands:"
echo "  kubectl get deployments,pods,svc"
echo "  curl -i \"http://${EXTERNAL_IP}/?file=index.html\""
echo "  curl -i \"http://${EXTERNAL_IP}/?file=does_not_exist.html\""
echo "  curl -i -X POST \"http://${EXTERNAL_IP}/?file=index.html\""
echo "  curl -i -H \"X-Country: Iran\" \"http://${EXTERNAL_IP}/?file=index.html\""
echo "  gcloud compute ssh ${FORBIDDEN_VM} --zone ${ZONE} --command 'sudo journalctl -u hw9-forbidden -n 50 --no-pager'"
echo "  gcloud compute scp ./http-client ${CLIENT_VM}:~/http-client --zone ${ZONE}"
