This HW3 uses:

- `service1` on Google Cloud Functions (Gen2)
- `service2` on local laptop (Pub/Sub pull subscriber)
- existing bucket from HW2: `cs528-hw2-chunyu`
- existing topic: `hw3-forbidden-topic`

## Repo Layout (Same Repository Rule)

Instructor guidance says to keep using the same repository and add a new directory.  
Recommended structure:

```text
repo-root/
  hw1/
  hw2/
  hw3/
    service1/
    service2/
    README.md
```

## Files In HW3

- `service1/main.py`
- `service1/requirements.txt`
- `service2/server.py`
- `service2/requirements.txt`

## Cloud Setup (Cloud Shell)

```bash
cd ~/hw3
export PROJECT_ID="$(gcloud config get-value project)"
export REGION="us-central1"
export BUCKET_NAME="cs528-hw2-chunyu"
export TOPIC_ID="hw3-forbidden-topic"
export SUBSCRIPTION_ID="hw3-sub"
export LOG_OBJECT="forbidden/forbidden_requests.log"
export SERVICE1_NAME="hw3-service1-fn"
export SA_EMAIL="hw3-sa@${PROJECT_ID}.iam.gserviceaccount.com"
```

Enable APIs:

```bash
gcloud services enable cloudfunctions.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com pubsub.googleapis.com storage.googleapis.com run.googleapis.com
```

IAM (service account used by both services):

```bash
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member "serviceAccount:${SA_EMAIL}" --role "roles/pubsub.publisher"
gcloud projects add-iam-policy-binding "${PROJECT_ID}" --member "serviceAccount:${SA_EMAIL}" --role "roles/pubsub.subscriber"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member "serviceAccount:${SA_EMAIL}" --role "roles/storage.objectViewer"
gcloud storage buckets add-iam-policy-binding "gs://${BUCKET_NAME}" --member "serviceAccount:${SA_EMAIL}" --role "roles/storage.objectAdmin"
```

Subscription:

```bash
gcloud pubsub subscriptions create "${SUBSCRIPTION_ID}" --topic "${TOPIC_ID}" || true
```

Deploy `service1`:

```bash
gcloud functions deploy "${SERVICE1_NAME}" \
  --gen2 \
  --runtime python312 \
  --region "${REGION}" \
  --source ./service1 \
  --entry-point handler \
  --trigger-http \
  --allow-unauthenticated \
  --service-account "${SA_EMAIL}" \
  --set-env-vars "BUCKET_NAME=${BUCKET_NAME},TOPIC_ID=${TOPIC_ID},GOOGLE_CLOUD_PROJECT=${PROJECT_ID},BUILD_ID=v4"
```

Get URL:

```bash
SERVICE1_URL="$(gcloud functions describe "${SERVICE1_NAME}" --region "${REGION}" --gen2 --format='value(serviceConfig.uri)')"
echo "${SERVICE1_URL}"
```

## Local Setup (`service2`)

### Windows PowerShell

```powershell
cd "C:\Users\omen\OneDrive\桌面\cs528 hw3\service2"
py -3 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt

$env:GOOGLE_APPLICATION_CREDENTIALS="C:\Users\omen\Downloads\hw3-sa-key.json"
$env:GOOGLE_CLOUD_PROJECT="sonorous-sign-487022-a1"
$env:SUBSCRIPTION_ID="hw3-sub"
$env:BUCKET_NAME="cs528-hw2-chunyu"
$env:LOG_OBJECT="forbidden/forbidden_requests.log"

.\.venv\Scripts\python.exe server.py
```

Notes:

- This satisfies the requirement that service2 runs locally.
- Authentication mechanism used: service account key (`GOOGLE_APPLICATION_CREDENTIALS`).
- Do not use `gcloud auth application-default login`.

## Functional Tests

Create test file(s):

```bash
echo "<h1>hello hw3</h1>" > index.html
gcloud storage cp index.html "gs://${BUCKET_NAME}/index.html"
echo "<h1>file 0</h1>" > 0.html
gcloud storage cp 0.html "gs://${BUCKET_NAME}/0.html"
```

Status checks:

```bash
curl -i "${SERVICE1_URL}?file=index.html"                       # 200
curl -i "${SERVICE1_URL}?file=does_not_exist.html"              # 404
curl -i -X POST "${SERVICE1_URL}?file=index.html"               # 501
curl -i -H "X-Country: Iran" "${SERVICE1_URL}?file=index.html"  # 400
```

## 100 Requests With Provided Client

```powershell
cd "C:\Users\omen\Downloads"
.\http-client.exe -d "us-central1-sonorous-sign-487022-a1.cloudfunctions.net" -b "none" -w "hw3-service1-fn" -n 100 -i 1 -s -v | Tee-Object .\http_client_100_ok.log
```

## Evidence Commands

Cloud Logging:

```bash
gcloud logging read "resource.type=cloud_function AND resource.labels.function_name=${SERVICE1_NAME}" --limit=50 --format=json
```

Forbidden append file:

```bash
gcloud storage cat "gs://${BUCKET_NAME}/${LOG_OBJECT}" | tail -n 10
```
