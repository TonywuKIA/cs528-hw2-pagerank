# CS528 HW2 – PageRank on Google Cloud Storage

This repository contains the implementation of the PageRank algorithm for CS528 HW2.

## Files
- `hw2.py`: Main program that reads HTML pages from a GCS bucket, constructs a web graph, computes statistics, and runs PageRank.
- `test_hw2.py`: Correctness test using a small deterministic graph with known PageRank behavior.

## How to Run

```bash
python hw2.py
python test_hw2.py

Environment：
Python 3.10+
google-cloud-storage
