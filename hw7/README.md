# HW7 (Apache Beam + Dataflow)

This directory reuses the HW2 page dataset in Google Cloud Storage and processes it with Apache Beam.

The pipeline computes:
- top 5 files with the most incoming links
- top 5 files with the most outgoing links
- top 5 most frequent word bigrams
- runtime metadata for the run

## Files
- `beam_pipeline.py`: main Beam pipeline
- `requirements.txt`: Python dependencies for local runs and Dataflow workers
- `run_local.sh`: run with `DirectRunner`
- `run_dataflow.sh`: run with `DataflowRunner`
- `test_parsing.py`: local parsing/unit tests

## Default dataset

The default input matches the HW2 dataset:

```text
gs://cs528-hw2-chunyu/pages/*.html
```

Link extraction intentionally matches HW2 semantics and only counts links of the form `href="123.html"`.

For bigrams, follow the Piazza clarification: any consecutive token composed of `a-z`, `A-Z`, `0-9`, or `'` counts as a word, and every other character is a separator. This means the pipeline tokenizes the raw HTML text instead of stripping tags first.

## Setup

Create an environment and install dependencies:

```bash
cd hw7
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

If you are running against GCP resources locally, authenticate first:

```bash
gcloud auth application-default login
gcloud config set project sonorous-sign-487022-a1
```

Enable required APIs before Dataflow runs:

```bash
gcloud services enable dataflow.googleapis.com compute.googleapis.com storage.googleapis.com
```

## Local run

From the repo root:

```bash
bash hw7/run_local.sh
```

Defaults:
- input: `gs://cs528-hw2-chunyu/pages/*.html`
- output base: `hw7/output/local/<timestamp>/`
- tasks: `all`
- manifest limit: `0` (no limit)

Override example:

```bash
INPUT_PATTERN="gs://cs528-hw2-chunyu/pages/*.html" OUTPUT_DIR="$(pwd)/hw7/output/local/manual-run" bash hw7/run_local.sh
```

Run only one task on a smaller subset:

```bash
TASKS="incoming" MANIFEST_LIMIT=10 OUTPUT_DIR="$(pwd)/hw7/output/incoming-10" bash hw7/run_local.sh
```

To validate smaller bucket subsets with DirectRunner, you can run the Python entrypoint directly:

```bash
python3 hw7/beam_pipeline.py \
  --input "gs://cs528-hw2-chunyu/pages/*.html" \
  --output "hw7/output/incoming-10" \
  --tasks incoming \
  --manifest-limit 10 \
  --runtime-runner DirectRunner \
  --runner DirectRunner \
  --direct_running_mode=in_memory \
  --direct_num_workers=1
```

## Dataflow run

From the repo root:

```bash
bash hw7/run_dataflow.sh
```

Defaults:
- project: `sonorous-sign-487022-a1`
- region: `us-central1`
- output prefix: `gs://cs528-hw2-chunyu/hw7/output/<timestamp>/`
- temp: `gs://cs528-hw2-chunyu/hw7/tmp`
- staging: `gs://cs528-hw2-chunyu/hw7/staging`

Override example:

```bash
PROJECT_ID="sonorous-sign-487022-a1" REGION="us-central1" BUCKET_NAME="cs528-hw2-chunyu" bash hw7/run_dataflow.sh
```

## Output files

Each run writes:
- `top_incoming_links-00000-of-00001.jsonl`
- `top_outgoing_links-00000-of-00001.jsonl`
- `top_bigrams-00000-of-00001.jsonl`
- `runtime_summary.json`

Local outputs go under:

```text
hw7/output/local/<timestamp>/
```

Dataflow outputs go under:

```text
gs://<bucket>/hw7/output/<timestamp>/
```

Each JSONL line looks like:

```json
{"kind":"top_incoming_links","name":"123.html","count":42}
```

## Tests

Run local parsing tests:

```bash
python -m unittest hw7.test_parsing
```

These tests cover:
- link extraction
- Piazza-compatible tokenization
- bigram generation
- deterministic top-k ordering

## Report checklist

Include in the PDF:
- setup and run steps for local and Dataflow execution
- exact commands used
- local runtime and Dataflow runtime
- sample output for incoming links, outgoing links, and bigrams
- short explanation of how the Beam pipeline works
- GitHub link to the Python code
