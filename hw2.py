
"""
CS528 HW2 - Graph Analysis & PageRank

This script:
1. Reads 20,000 HTML files from a Google Cloud Storage bucket
2. Extracts outgoing links from each page
3. Computes incoming / outgoing link statistics
4. Implements the original iterative PageRank algorithm
5. Stops when the sum of PageRank values converges within 0.5%

All logic is implemented explicitly without using external graph libraries.
"""

import re
import time
import statistics
from collections import defaultdict
from typing import Dict, List, Tuple

from google.cloud import storage

# -----------------------------
# Configuration
# -----------------------------

BUCKET = "cs528-hw2-chunyu"
PREFIX = "pages/"          # Folder inside the bucket
NUM_PAGES = 1000

# Regex to extract links of the form href="123.html"
HREF_RE = re.compile(
    r'href\s*=\s*["\'](\d+)\.html["\']',
    re.IGNORECASE)

# -----------------------------
# Utility: Statistics
# -----------------------------

def summarize_int(values: List[int]) -> Dict[str, float]:
    """
    Compute min, max, average, median, and quintiles
    (20%, 40%, 60%, 80%) for a list of integers.
    """
    values = sorted(values)
    n = len(values)

    def quantile(p: float) -> float:
        # Nearest-rank style quantile
        idx = int(round(p * (n - 1)))
        idx = max(0, min(n - 1, idx))
        return float(values[idx])

    return {
        "min": float(values[0]),
        "max": float(values[-1]),
        "avg": float(sum(values) / n),
        "median": float(statistics.median(values)),
        "q20": quantile(0.20),
        "q40": quantile(0.40),
        "q60": quantile(0.60),
        "q80": quantile(0.80),
    }

# -----------------------------
# Graph Construction
# -----------------------------

def build_graph() -> Tuple[
    Dict[str, List[str]],
    Dict[str, int],
    Dict[str, int]
]:
    """
    Build the directed graph from GCS HTML files.

    Returns:
      graph  : node -> list of outgoing neighbors
      indeg  : node -> incoming degree
      outdeg : node -> outgoing degree
    """
    client = storage.Client()
    bucket = client.bucket(BUCKET)

    graph: Dict[str, List[str]] = {}
    indeg = defaultdict(int)
    outdeg = {}

    start_time = time.time()
    parsed = 0

    # Iterate over objects in the bucket without loading all at once
    for blob in bucket.list_blobs(prefix=PREFIX):
        if not blob.name.endswith(".html"):
            continue

        # Normalize node name (e.g., "pages/123.html" -> "123.html")
        node = blob.name[len(PREFIX):]

        html = blob.download_as_bytes().decode("utf-8", errors="ignore")

        # Extract outgoing links
        outgoing = [f"{m}.html" for m in HREF_RE.findall(html)]
        graph[node] = outgoing
        outdeg[node] = len(outgoing)

        for target in outgoing:
            indeg[target] += 1

        parsed += 1
        if parsed % 500 == 0:
            elapsed = time.time() - start_time
            print(f"Parsed {parsed} pages in {elapsed:.1f}s")

    # Ensure every page appears in the dictionaries
    for i in range(NUM_PAGES):
        node = f"{i}.html"
        graph.setdefault(node, [])
        outdeg.setdefault(node, 0)
        indeg.setdefault(node, 0)

    print(f"Total pages parsed: {parsed}")
    return graph, dict(indeg), outdeg

# -----------------------------
# PageRank
# -----------------------------

def pagerank_iterative(
    graph: Dict[str, List[str]],
    outdeg: Dict[str, int],
    tol_pct: float = 0.005,
    max_iter: int = 200
) -> Dict[str, float]:
    """
    Original iterative PageRank algorithm:

    PR(A) = 0.15 / N + 0.85 * sum(PR(Ti) / C(Ti))

    Iteration stops when the relative change in the
    sum of PageRank values is <= 0.5%.
    """
    nodes = list(graph.keys())
    n = len(nodes)

    # Initialize PageRank uniformly
    pr = {u: 1.0 / n for u in nodes}

    # Build incoming adjacency list for efficiency
    incoming = defaultdict(list)
    for src, outs in graph.items():
        for tgt in outs:
            if tgt in pr:
                incoming[tgt].append(src)

    prev_sum = sum(pr.values())

    for iteration in range(1, max_iter + 1):
        new_pr = {}
        base = 0.15 / n

        for u in nodes:
            score = 0.0
            for src in incoming.get(u, []):
                c = outdeg.get(src, 0)
                if c > 0:
                    score += pr[src] / c
            new_pr[u] = base + 0.85 * score

        current_sum = sum(new_pr.values())
        rel_change = abs(current_sum - prev_sum) / (
            prev_sum if prev_sum > 0 else 1.0
        )

        print(
            f"Iter {iteration}: "
            f"sum(PR)={current_sum:.6f}, "
            f"relative change={rel_change*100:.3f}%"
        )

        pr = new_pr
        prev_sum = current_sum

        if rel_change <= tol_pct:
            break

    # Normalize to ensure sum(PR) = 1 (numerical stability)
    total = sum(pr.values())
    if total > 0:
        for k in pr:
            pr[k] /= total

    return pr

# -----------------------------
# Main
# -----------------------------

def main():
    start = time.time()

    graph, indeg, outdeg = build_graph()
    after_graph = time.time()

    out_list = [outdeg[f"{i}.html"] for i in range(NUM_PAGES)]
    in_list  = [indeg[f"{i}.html"]  for i in range(NUM_PAGES)]

    print("\n=== Outgoing Link Statistics ===")
    print(summarize_int(out_list))

    print("\n=== Incoming Link Statistics ===")
    print(summarize_int(in_list))

    pr = pagerank_iterative(graph, outdeg)
    top5 = sorted(pr.items(), key=lambda x: x[1], reverse=True)[:5]

    print("\n=== Top 5 Pages by PageRank ===")
    for page, score in top5:
        print(page, score)

    end = time.time()

    print("\n=== Timing ===")
    print(f"Graph construction: {after_graph - start:.1f}s")
    print(f"PageRank + stats:  {end - after_graph:.1f}s")
    print(f"Total runtime:     {end - start:.1f}s")

if __name__ == "__main__":
    main()

