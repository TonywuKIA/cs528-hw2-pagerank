import unittest

from hw7.beam_pipeline import (
    build_bigrams,
    extract_outgoing_links,
    html_to_tokens,
    parse_document,
    select_top_k,
)


class ParsingTests(unittest.TestCase):
    def test_extract_outgoing_links_preserves_hw2_semantics(self):
        html = '<a href="12.html">A</a><a HREF="345.html">B</a><a href="x.html">skip</a>'
        self.assertEqual(extract_outgoing_links(html), ["12.html", "345.html"])

    def test_html_to_tokens_strips_tags_and_normalizes_case(self):
        html = "<html><body>Hello, <b>Beam</b> &amp; Dataflow 101! it's</body></html>"
        self.assertEqual(
            html_to_tokens(html),
            ["html", "body", "hello", "b", "beam", "b", "dataflow", "101", "it's", "body", "html"],
        )

    def test_build_bigrams_is_consecutive_within_single_document(self):
        self.assertEqual(
            build_bigrams(["hello", "beam", "world"]),
            ["hello beam", "beam world"],
        )

    def test_parse_document_emits_expected_fields(self):
        html = "<p>Hello world hello</p><a href='9.html'>nine</a>"
        parsed = parse_document("gs://bucket/pages/7.html", html)
        self.assertEqual(parsed["source"], "7.html")
        self.assertEqual(parsed["outgoing"], ["9.html"])
        self.assertEqual(parsed["outdegree"], 1)
        self.assertEqual(
            parsed["bigrams"],
            [
                "p hello",
                "hello world",
                "world hello",
                "hello p",
                "p a",
                "a href",
                "href '9",
                "'9 html'",
                "html' nine",
                "nine a",
            ],
        )

    def test_select_top_k_sorts_by_count_then_name(self):
        items = [("b.html", 3), ("a.html", 3), ("c.html", 10), ("d.html", 1)]
        self.assertEqual(select_top_k(items, limit=3), [("c.html", 10), ("a.html", 3), ("b.html", 3)])


if __name__ == "__main__":
    unittest.main()
