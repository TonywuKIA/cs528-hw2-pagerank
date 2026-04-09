#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

INPUT_PATTERN="${INPUT_PATTERN:-gs://cs528-hw2-chunyu/pages/*.html}"
RUN_ID="${RUN_ID:-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_DIR="${OUTPUT_DIR:-${REPO_ROOT}/hw7/output/local/${RUN_ID}}"
TASKS="${TASKS:-all}"
MANIFEST_LIMIT="${MANIFEST_LIMIT:-0}"

mkdir -p "${OUTPUT_DIR}"

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
  --output "${OUTPUT_DIR}" \
  --tasks "${TASKS}" \
  --manifest-limit "${MANIFEST_LIMIT}" \
  --runtime-runner "DirectRunner" \
  --runner=DirectRunner
END_TS="$(date +%s)"

echo "Local wall-clock runtime: $((END_TS - START_TS))s"
echo "Output directory: ${OUTPUT_DIR}"
echo "Tasks: ${TASKS}"
echo "Manifest limit: ${MANIFEST_LIMIT}"
