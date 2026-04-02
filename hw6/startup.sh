#!/usr/bin/env bash
set -euo pipefail

LOCK_FILE="/var/log/startup_already_done_hw6_model_vm"
if [ -f "${LOCK_FILE}" ]; then
  echo "Startup script already ran once. Skipping."
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y python3-venv python3-pip curl

mkdir -p /opt/hw6/app

fetch_metadata() {
  local key="$1"
  curl -fsS -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/attributes/${key}"
}

fetch_metadata APP_DB_PY > /opt/hw6/app/db.py
fetch_metadata APP_SETUP_3NF_PY > /opt/hw6/app/setup_3nf.py
fetch_metadata APP_MIGRATE_PY > /opt/hw6/app/migrate_to_3nf.py
fetch_metadata APP_RUN_MODELS_PY > /opt/hw6/app/run_models.py

python3 -m venv /opt/hw6/venv
/opt/hw6/venv/bin/pip install --upgrade pip
/opt/hw6/venv/bin/pip install google-cloud-storage==2.19.0 pg8000==1.31.2 scikit-learn==1.5.2

touch "${LOCK_FILE}"
