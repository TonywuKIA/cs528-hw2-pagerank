import argparse
import fnmatch
import html
import json
import re
import time
from functools import lru_cache
from glob import glob
from pathlib import Path
from typing import Iterable


DEFAULT_INPUT = "gs://cs528-hw2-chunyu/pages/*.html"
DEFAULT_OUTPUT = "hw7/output/local"
TASK_INCOMING = "incoming"
TASK_OUTGOING = "outgoing"
TASK_BIGRAMS = "bigrams"
TASK_ALL = "all"
TASK_CHOICES = (TASK_ALL, TASK_INCOMING, TASK_OUTGOING, TASK_BIGRAMS)
HREF_RE = re.compile(r'href\s*=\s*["\'](\d+)\.html["\']', re.IGNORECASE)
TOKEN_RE = re.compile(r"[a-z0-9']+", re.IGNORECASE)


def normalize_source_name(path: str) -> str:
    normalized = path.replace("\\", "/")
    return normalized.rsplit("/", maxsplit=1)[-1]


def extract_outgoing_links(html_text: str) -> list[str]:
    return [f"{match}.html" for match in HREF_RE.findall(html_text)]


def html_to_tokens(html_text: str) -> list[str]:
    # Piazza clarification: any sequence of letters, digits, or apostrophes counts as a word.
    # Everything else acts as a separator, so HTML markup is tokenized rather than stripped.
    unescaped = html.unescape(html_text).lower()
    return TOKEN_RE.findall(unescaped)


def build_bigrams(tokens: list[str]) -> list[str]:
    return [f"{left} {right}" for left, right in zip(tokens, tokens[1:], strict=False)]


def parse_document(path: str, html_text: str) -> dict[str, object]:
    outgoing = extract_outgoing_links(html_text)
    tokens = html_to_tokens(html_text)
    return {
        "source": normalize_source_name(path),
        "outgoing": outgoing,
        "outdegree": len(outgoing),
        "bigrams": build_bigrams(tokens),
    }


def select_top_k(items: Iterable[tuple[str, int]], limit: int = 5) -> list[tuple[str, int]]:
    return sorted(items, key=lambda item: (-item[1], item[0]))[:limit]


def format_count_record(name: str, count: int, kind: str) -> str:
    return json.dumps({"kind": kind, "name": name, "count": count}, ensure_ascii=False)


def format_runtime_summary(
    runtime_seconds: float,
    runner: str,
    input_pattern: str,
    output_prefix: str,
) -> str:
    payload = {
        "runner": runner,
        "input_pattern": input_pattern,
        "output_prefix": output_prefix,
        "runtime_seconds": round(runtime_seconds, 3),
    }
    return json.dumps(payload, indent=2) + "\n"


def _ensure_local_parent(path: str) -> None:
    if "://" in path:
        return
    Path(path).parent.mkdir(parents=True, exist_ok=True)


def write_runtime_summary(path: str, content: str) -> None:
    if "://" not in path:
        _ensure_local_parent(path)
        Path(path).write_text(content, encoding="utf-8")
        return

    from apache_beam.io.filesystems import FileSystems

    with FileSystems.create(path) as handle:
        handle.write(content.encode("utf-8"))


def _split_gcs_pattern(input_pattern: str) -> tuple[str, str, str]:
    without_scheme = input_pattern[len("gs://"):]
    bucket_name, _, object_pattern = without_scheme.partition("/")
    wildcard_index = len(object_pattern)
    for marker in ("*", "?", "["):
        index = object_pattern.find(marker)
        if index != -1:
            wildcard_index = min(wildcard_index, index)
    prefix = object_pattern[:wildcard_index]
    if "/" in prefix:
        prefix = prefix[: prefix.rfind("/") + 1]
    else:
        prefix = ""
    return bucket_name, prefix, object_pattern


def list_input_paths(input_pattern: str, manifest_limit: int = 0) -> list[str]:
    if input_pattern.startswith("gs://"):
        from google.cloud import storage

        bucket_name, prefix, object_pattern = _split_gcs_pattern(input_pattern)
        client = storage.Client()
        bucket = client.bucket(bucket_name)
        matches: list[str] = []
        for blob in bucket.list_blobs(prefix=prefix):
            if fnmatch.fnmatch(blob.name, object_pattern):
                matches.append(f"gs://{bucket_name}/{blob.name}")
        matches = sorted(matches)
        if manifest_limit > 0:
            return matches[:manifest_limit]
        return matches

    matches = sorted(glob(input_pattern))
    if manifest_limit > 0:
        return matches[:manifest_limit]
    return matches


@lru_cache(maxsize=1)
def _get_storage_client():
    from google.cloud import storage

    return storage.Client()


def read_document_text(path: str) -> str:
    if path.startswith("gs://"):
        without_scheme = path[len("gs://"):]
        bucket_name, _, object_name = without_scheme.partition("/")
        bucket = _get_storage_client().bucket(bucket_name)
        blob = bucket.blob(object_name)
        return blob.download_as_text(encoding="utf-8")

    return Path(path).read_text(encoding="utf-8", errors="ignore")


def _to_incoming_pairs(parsed: dict[str, object]) -> Iterable[tuple[str, int]]:
    for target in parsed["outgoing"]:
        yield (str(target), 1)


def _to_bigram_pairs(parsed: dict[str, object]) -> Iterable[tuple[str, int]]:
    for bigram in parsed["bigrams"]:
        yield (str(bigram), 1)


def _to_outgoing_pair(parsed: dict[str, object]) -> tuple[str, int]:
    return (str(parsed["source"]), int(parsed["outdegree"]))


def _document_from_readable_file(readable_file) -> dict[str, object]:
    return parse_document(readable_file, read_document_text(readable_file))


def _top_sort_key(item: tuple[str, int]) -> tuple[int, str]:
    return (item[1], item[0])


def _format_record_tuple(item: tuple[str, int], kind: str) -> str:
    name, count = item
    return format_count_record(name, count, kind)


def _format_record_tuple_expanded(name: str, count: int, kind: str) -> str:
    return format_count_record(name, count, kind)


def _format_record_item(item: tuple[str, int], kind: str) -> str:
    name, count = item
    return _format_record_tuple_expanded(name, count, kind)


def _sort_top_records(rows: list[tuple[str, int]]) -> list[tuple[str, int]]:
    return select_top_k(rows, limit=len(rows))


def _task_selected(selected_tasks: set[str], task_name: str) -> bool:
    return TASK_ALL in selected_tasks or task_name in selected_tasks


def build_pipeline(
    pipeline,
    input_pattern: str,
    output_prefix: str,
    selected_tasks: set[str],
    manifest_limit: int,
):
    import apache_beam as beam
    from apache_beam.io import WriteToText

    input_paths = list_input_paths(input_pattern, manifest_limit=manifest_limit)
    if not input_paths:
        raise RuntimeError(f"No input files matched pattern: {input_pattern}")

    documents = (
        pipeline
        | "CreateInputPaths" >> beam.Create(input_paths)
        | "ParseDocuments" >> beam.Map(_document_from_readable_file)
    )

    def write_top_five(pcoll, label: str, kind: str):
        (
            pcoll
            | f"{label}TopFive" >> beam.combiners.Top.Of(5, key=_top_sort_key)
            | f"{label}SortTopFive" >> beam.Map(_sort_top_records)
            | f"{label}FlattenTopFive" >> beam.FlatMap(list)
            | f"{label}FormatTopFive" >> beam.Map(_format_record_item, kind)
            | f"{label}WriteTopFive"
            >> WriteToText(
                f"{output_prefix}/{kind}",
                file_name_suffix=".jsonl",
                shard_name_template="-SSSSS-of-NNNNN",
                num_shards=1,
            )
        )

    if _task_selected(selected_tasks, TASK_INCOMING):
        incoming_counts = (
            documents
            | "IncomingPairs" >> beam.FlatMap(_to_incoming_pairs)
            | "CountIncoming" >> beam.CombinePerKey(sum)
        )
        write_top_five(incoming_counts, "Incoming", "top_incoming_links")

    if _task_selected(selected_tasks, TASK_OUTGOING):
        outgoing_counts = (
            documents
            | "OutgoingPairs" >> beam.Map(_to_outgoing_pair)
        )
        write_top_five(outgoing_counts, "Outgoing", "top_outgoing_links")

    if _task_selected(selected_tasks, TASK_BIGRAMS):
        bigram_counts = (
            documents
            | "BigramPairs" >> beam.FlatMap(_to_bigram_pairs)
            | "CountBigrams" >> beam.CombinePerKey(sum)
        )
        write_top_five(bigram_counts, "Bigrams", "top_bigrams")


def parse_args(argv: list[str] | None = None):
    parser = argparse.ArgumentParser(description="HW7 Apache Beam analytics on HW2 pages")
    parser.add_argument("--input", default=DEFAULT_INPUT, help="File pattern to process")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Output directory or bucket prefix")
    parser.add_argument(
        "--tasks",
        nargs="+",
        default=[TASK_ALL],
        choices=TASK_CHOICES,
        help="Which analytics to run: all, incoming, outgoing, bigrams",
    )
    parser.add_argument(
        "--manifest-limit",
        type=int,
        default=0,
        help="Optional limit on how many matched files to include from the input manifest",
    )
    parser.add_argument("--runtime-runner", default="", help="Runner name to record in runtime summary")
    known_args, pipeline_args = parser.parse_known_args(argv)
    return known_args, pipeline_args


def run(argv: list[str] | None = None) -> int:
    known_args, pipeline_args = parse_args(argv)

    import apache_beam as beam
    from apache_beam.options.pipeline_options import PipelineOptions

    options = PipelineOptions(pipeline_args)
    runner_name = known_args.runtime_runner or options.get_all_options().get("runner") or "DirectRunner"
    runtime_started = time.perf_counter()
    selected_tasks = set(known_args.tasks)

    with beam.Pipeline(options=options) as pipeline:
        build_pipeline(
            pipeline,
            known_args.input,
            known_args.output,
            selected_tasks=selected_tasks,
            manifest_limit=known_args.manifest_limit,
        )

    runtime_seconds = time.perf_counter() - runtime_started
    runtime_summary = format_runtime_summary(
        runtime_seconds=runtime_seconds,
        runner=runner_name,
        input_pattern=known_args.input,
        output_prefix=known_args.output,
    )
    write_runtime_summary(f"{known_args.output}/runtime_summary.json", runtime_summary)
    print(runtime_summary, end="")
    return 0


def main() -> int:
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
