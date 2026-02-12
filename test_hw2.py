from hw2 import pagerank_iterative

def test_pagerank_small_graph():
    # Fixed tiny graph (independent of the random 20K graph)
    graph = {
        "A": ["B", "C"],
        "B": ["C"],
        "C": ["A"],
        "D": ["C"],
    }
    outdeg = {k: len(v) for k, v in graph.items()}
    pr = pagerank_iterative(graph, outdeg, tol_pct=0.005, max_iter=100)

    # PR values should sum to 1 after normalization
    assert abs(sum(pr.values()) - 1.0) < 1e-6

    # Sanity check: C receives multiple incoming links, should rank higher than B
    assert pr["C"] > pr["B"]

if __name__ == "__main__":
    test_pagerank_small_graph()
    print("OK")
