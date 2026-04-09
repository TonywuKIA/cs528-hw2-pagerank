import argparse
import html
import json
import re
import time
from pathlib import Path
from typing import Iterable

DEFAULT_INPUT = "gs://cs528-hw2-chunyu/pages/*.html"
DEFAULT_OUTPUT = "hw7/output/local"

HREF_RE = re.compile(r'href\s*=\s*["\'](\d+)\.html["\']', re.IGNORECASE)
TOKEN_RE = re.compile(r"[a-z0-9']+", re.IGNORECASE)


def normalize_source_name(path: str) -> str:
    normalized = path.replace("\\", "/")
    return normalized.rsplit("/", maxsplit=1)[-1]


def extract_outgoing_links(html_text: str) -> Iterable[str]:
    for match in HREF_RE.findall(html_text):
        yield f"{match}.html"


def html_to_tokens(html_text: str) -> list[str]:
    # Piazza clarification: any sequence of letters, digits, or apostrophes counts as a word.
    # Everything else acts as a separator, so HTML markup is tokenized rather than stripped.
    unescaped = html.unescape(html_text).lower()
    return TOKEN_RE.findall(unescaped)


def iter_bigrams_from_html(html_text: str) -> Iterable[str]:
    tokens = html_to_tokens(html_text)
    for left, right in zip(tokens, tokens[1:]):
        yield f"{left} {right}"


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


def _read_match_content(readable_file) -> str:
    data = readable_file.read_utf8()
    return data if isinstance(data, str) else data.decode("utf-8", errors="ignore")


def _safe_read_file(readable_file) -> tuple[str, str]:
    path = readable_file.metadata.path
    try:
        content = _read_match_content(readable_file)
        return path, content
    except Exception as e:
        raise RuntimeError(f"Failed to read file {path}: {e}") from e


def _to_outgoing_pair(file_record: tuple[str, str]) -> tuple[str, int]:
    path, html_text = file_record
    source = normalize_source_name(path)
    outdegree = sum(1 for _ in extract_outgoing_links(html_text))
    return source, outdegree


def _to_incoming_pairs(file_record: tuple[str, str]) -> Iterable[tuple[str, int]]:
    _, html_text = file_record
    for target in extract_outgoing_links(html_text):
        yield target, 1


def _to_bigram_pairs(file_record: tuple[str, str]) -> Iterable[tuple[str, int]]:
    _, html_text = file_record
    for bigram in iter_bigrams_from_html(html_text):
        yield bigram, 1


def _top_sort_key(item: tuple[str, int]) -> tuple[int, str]:
    return item[1], item[0]


def _sort_rows_desc(rows: list[tuple[str, int]]) -> list[tuple[str, int]]:
    return sorted(rows, key=lambda item: (-item[1], item[0]))


def _format_record_item(item: tuple[str, int], kind: str) -> str:
    name, count = item
    return format_count_record(name, count, kind)


def build_pipeline(pipeline, input_pattern: str, output_prefix: str):
    import apache_beam as beam
    from apache_beam.io import WriteToText, fileio

    files = (
        pipeline
        | "MatchFiles" >> fileio.MatchFiles(input_pattern)
        | "ReadMatches" >> fileio.ReadMatches()
        | "ReadFileContents" >> beam.Map(_safe_read_file)
    )

    incoming_counts = (
        files
        | "IncomingPairs" >> beam.FlatMap(_to_incoming_pairs)
        | "CountIncoming" >> beam.CombinePerKey(sum)
    )

    outgoing_counts = (
        files
        | "OutgoingPairs" >> beam.Map(_to_outgoing_pair)
    )

    bigram_counts = (
        files
        | "BigramPairs" >> beam.FlatMap(_to_bigram_pairs)
        | "CountBigrams" >> beam.CombinePerKey(sum)
    )

    def write_top_five(pcoll, label: str, kind: str):
        (
            pcoll
            | f"{label}TopFive" >> beam.combiners.Top.Of(5, key=_top_sort_key)
            | f"{label}SortTopFive" >> beam.Map(_sort_rows_desc)
            | f"{label}FlattenTopFive" >> beam.FlatMap(lambda rows: rows)
            | f"{label}FormatTopFive" >> beam.Map(_format_record_item, kind)
            | f"{label}WriteTopFive"
            >> WriteToText(
                f"{output_prefix}/{kind}",
                file_name_suffix=".jsonl",
                shard_name_template="-00000-of-00001",
                num_shards=1,
            )
        )

    write_top_five(incoming_counts, "Incoming", "top_incoming_links")
    write_top_five(outgoing_counts, "Outgoing", "top_outgoing_links")
    write_top_five(bigram_counts, "Bigrams", "top_bigrams")


def parse_args(argv: list[str] | None = None):
    parser = argparse.ArgumentParser(description="HW7 Apache Beam analytics on HW2 pages")
    parser.add_argument("--input", default=DEFAULT_INPUT, help="File pattern to process")
    parser.add_argument("--output", default=DEFAULT_OUTPUT, help="Output directory or bucket prefix")
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

    with beam.Pipeline(options=options) as pipeline:
        build_pipeline(pipeline, known_args.input, known_args.output)

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