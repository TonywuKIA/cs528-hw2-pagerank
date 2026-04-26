#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="${SCRIPT_DIR}/.hw9_state.env"
RENDERED_MANIFEST="${SCRIPT_DIR}/.hw9-web.rendered.yaml"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
PROJECT_NUMBER="$(gcloud projects describe "${PROJECT_ID}" --format='value(projectNumber)' 2>/dev/null || true)"
REGION="${REGION:-us-central1}"
ZONE="${ZONE:-us-central1-a}"
BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
TOPIC_ID="${TOPIC_ID:-hw3-forbidden-topic}"
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-hw3-sub}"
CLUSTER_NAME="${CLUSTER_NAME:-hw9-gke}"
AR_REPO="${AR_REPO:-hw9-repo}"
IMAGE_NAME="${IMAGE_NAME:-hw9-web}"
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

if [ -f "${STATE_FILE}" ]; then
  # shellcheck disable=SC1090
  source "${STATE_FILE}"
fi

echo "[cleanup] Getting cluster credentials if cluster exists..."
if gcloud container clusters describe "${CLUSTER_NAME}" --region="${REGION}" >/dev/null 2>&1; then
  gcloud container clusters get-credentials "${CLUSTER_NAME}" --region="${REGION}" --project="${PROJECT_ID}" >/dev/null || true
  kubectl delete service hw9-web --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete deployment hw9-web --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete serviceaccount hw9-web-ksa --ignore-not-found=true >/dev/null 2>&1 || true
fi

if [ "${CREATED_CLUSTER}" = "1" ]; then
  echo "[cleanup] Deleting GKE cluster: ${CLUSTER_NAME}"
  gcloud container clusters delete "${CLUSTER_NAME}" --region="${REGION}" --quiet >/dev/null 2>&1 || true
fi

echo "[cleanup] Deleting VMs..."
if [ "${CREATED_FORBIDDEN_VM}" = "1" ]; then
  gcloud compute instances delete "${FORBIDDEN_VM}" --zone="${ZONE}" --quiet >/dev/null 2>&1 || true
fi
if [ "${CREATED_CLIENT_VM}" = "1" ]; then
  gcloud compute instances delete "${CLIENT_VM}" --zone="${ZONE}" --quiet >/dev/null 2>&1 || true
fi

if [ "${CREATED_AR_REPO}" = "1" ]; then
  echo "[cleanup] Deleting Artifact Registry repo: ${AR_REPO}"
  gcloud artifacts repositories delete "${AR_REPO}" --location="${REGION}" --quiet >/dev/null 2>&1 || true
else
  gcloud artifacts docker images delete "${REGION}-docker.pkg.dev/${PROJECT_ID}/${AR_REPO}/${IMAGE_NAME}" --delete-tags --quiet >/dev/null 2>&1 || true
fi

if [ "${CREATED_SUBSCRIPTION}" = "1" ]; then
  gcloud pubsub subscriptions delete "${SUBSCRIPTION_ID}" >/dev/null 2>&1 || true
fi
if [ "${CREATED_TOPIC}" = "1" ]; then
  gcloud pubsub topics delete "${TOPIC_ID}" >/dev/null 2>&1 || true
fi

if [ "${CREATED_WEB_SA}" = "1" ]; then
  gcloud iam service-accounts delete "${WEB_SA_EMAIL}" --quiet >/dev/null 2>&1 || true
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

rm -f "${STATE_FILE}" "${RENDERED_MANIFEST}"
echo "[cleanup] Done"
