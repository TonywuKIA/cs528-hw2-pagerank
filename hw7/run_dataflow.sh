#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_ID="${PROJECT_ID:-sonorous-sign-487022-a1}"
REGION="${REGION:-us-central1}"
BUCKET_NAME="${BUCKET_NAME:-cs528-hw2-chunyu}"
INPUT_PATTERN="${INPUT_PATTERN:-gs://${BUCKET_NAME}/pages/*.html}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_PREFIX="${OUTPUT_PREFIX:-gs://${BUCKET_NAME}/hw7/output/${RUN_ID}}"
TEMP_LOCATION="${TEMP_LOCATION:-gs://${BUCKET_NAME}/hw7/tmp}"
STAGING_LOCATION="${STAGING_LOCATION:-gs://${BUCKET_NAME}/hw7/staging}"
SANITIZED_RUN_ID="$(printf '%s' "${RUN_ID}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"
JOB_NAME="${JOB_NAME:-hw7-beam-${SANITIZED_RUN_ID}}"

if [[ -n "${PYTHON_BIN:-}" ]]; then
  PYTHON_CMD=("${PYTHON_BIN}")
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD=(python3)
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD=(python)
elif command -v py >/dev/null 2>&1; then
  PYTHON_CMD=(py -3)
else
  echo "No Python interpreter found on PATH." >&2
  exit 1
fi

START_TS="$(date +%s)"
"${PYTHON_CMD[@]}" "${SCRIPT_DIR}/beam_pipeline.py" \
  --input "${INPUT_PATTERN}" \
  --output "${OUTPUT_PREFIX}" \
  --runtime-runner "DataflowRunner" \
  --runner=DataflowRunner \
  --project="${PROJECT_ID}" \
  --region="${REGION}" \
  --job_name="${JOB_NAME}" \
  --temp_location="${TEMP_LOCATION}" \
  --staging_location="${STAGING_LOCATION}" \
  --requirements_file="${SCRIPT_DIR}/requirements.txt" \
  --save_main_session
END_TS="$(date +%s)"

echo "Dataflow wall-clock runtime: $((END_TS - START_TS))s"
echo "Output prefix: ${OUTPUT_PREFIX}"
echo "Job name: ${JOB_NAME}"
