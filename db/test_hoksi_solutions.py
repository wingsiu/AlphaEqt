#!/usr/bin/env python3
"""Parser and SQL checks for the Hoksi M1/M2 solution ingest."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

import hoksi_solutions as hs  # noqa: E402

M1_TOPIC = ROOT / "fixtures" / "hoksi" / "m1_topic.json"
M2_TOPIC = ROOT / "fixtures" / "hoksi" / "m2_topic.json"
M1_YEARS = {str(year) for year in range(2012, 2027)} | {"SP", "PP"}
M2_YEARS = M1_YEARS

SAMPLE_HTML = """
<h2>(a)</h2>
<p>
<span class="math-tex">\\(\\displaystyle \\begin{aligned}\\because &amp;\\sum p =1\\\\ a=0.25 \\end{aligned}\\)</span><br/>
解聯立方程，得出：
</p>
<table>
<tr><th><span class="math-tex">\\(x^2\\)</span></th><td>4</td><td>9</td></tr>
<tr><th>P</th><td>0.08</td><td>0.15</td></tr>
</table>
"""


def year_labels(topic: dict, subject: str) -> set[str]:
    planned, notices = hs.plan_from_topic(topic, subject, None)
    errors = [notice for notice in notices if notice.level == "error"]
    if errors:
        raise AssertionError(errors)
    return {item.year_label for item in planned}


class HoksiSolutionTest(unittest.TestCase):
    def test_catalogue_covers_m1_and_m2_without_internal_gaps(self):
        m1 = json.loads(M1_TOPIC.read_text(encoding="utf-8"))
        m2 = json.loads(M2_TOPIC.read_text(encoding="utf-8"))
        self.assertEqual(year_labels(m1, "m1"), M1_YEARS)
        self.assertEqual(year_labels(m2, "m2"), M2_YEARS)
        m1_planned, m1_notices = hs.plan_from_topic(m1, "m1", {"2015"})
        self.assertEqual(
            sorted(item.question_no for item in m1_planned),
            list(range(1, 13)),
        )
        self.assertFalse(any(notice.level == "warning" for notice in m1_notices))
        self.assertIn("dse2015-math-m1", hs.catalogue_summary(m1, "m1"))
        self.assertIn("dse2026-math-m2", hs.catalogue_summary(m2, "m2"))

    def test_slugs_match_module_shape_and_reject_core(self):
        self.assertEqual(hs.paper_slug("m1", "2015"), "dse2015-math-m1")
        self.assertEqual(hs.paper_slug("m2", "2015"), "dse2015-math-m2")
        self.assertEqual(hs.paper_slug("m1", "SP"), "dsesp-math-m1")
        self.assertEqual(hs.paper_slug("m2", "PP"), "dsepp-math-m2")
        self.assertEqual(hs.question_slug("dse2015-math-m1", 12), "dse2015-math-m1-q12")
        with self.assertRaises(ValueError):
            hs.assert_module_slugs(["dse2015-math-cp1"])
        with self.assertRaises(ValueError):
            hs.paper_slug("pm", "2015")
        blocked, notices = hs.plan_from_topic(
            {"slug": "hkdse-maths-core-solutions", "folders": []},
            "m1",
        )
        self.assertEqual(blocked, ())
        self.assertTrue(notices)
        cee, cee_notices = hs.plan_from_topic(
            {"slug": "hkcee-maths-solutions", "folders": []},
            "m1",
        )
        self.assertEqual(cee, ())
        self.assertIn("HKCEE", cee_notices[0].message)

    def test_html_keeps_latex_and_tables(self):
        markdown = hs.hoksi_html_to_markdown(SAMPLE_HTML)
        self.assertIn("## (a)", markdown)
        self.assertIn("解聯立方程", markdown)
        self.assertIn(r"\sum p =1", markdown)
        self.assertIn("$", markdown)
        self.assertIn("| 4 |", markdown)
        self.assertNotIn("<span", markdown)
        self.assertNotIn("&amp;", markdown)

    def test_bundle_and_sql_for_one_m1_question(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            folder = "hkdse-maths-m1-solutions-2015"
            article = "hkdse-maths-m1-solutions-2015-q1"
            topic_dir = root / "hkdse-maths-m1-solutions" / "zh-HK"
            payload = {
                "slug": article,
                "name": "2015 M1 Q1",
                "sections": [{"content": SAMPLE_HTML, "sort_order": 1}],
                "actual_lang": "zh-HK",
            }
            article_path = topic_dir / folder / f"{article}.json"
            article_path.parent.mkdir(parents=True)
            article_path.write_text(json.dumps(payload), encoding="utf-8")
            topic = {
                "slug": "hkdse-maths-m1-solutions",
                "name": "M1試題答案",
                "folders": [
                    {
                        "slug": folder,
                        "name": "HKDSE 2015 M1",
                        "articles": [{"slug": article, "name": "2015 M1 Q1"}],
                    }
                ],
            }
            (topic_dir / "_topic.json").write_text(json.dumps(topic), encoding="utf-8")
            bundle = hs.load_bundle(root, "m1", years={"2015"}, lang="zh-HK")
            self.assertEqual(bundle.errors, ())
            self.assertEqual(len(bundle.rows), 1)
            self.assertEqual(bundle.rows[0].planned.paper_slug, "dse2015-math-m1")
            self.assertEqual(bundle.rows[0].body_format, "markdown")
            self.assertIn(r"\sum", bundle.rows[0].body)
            sql = hs.render_sql(bundle)
            self.assertIn("INSERT INTO solutions", sql)
            self.assertIn("dse2015-math-m1", sql)
            self.assertIn("dse2015-math-m1-q1", sql)
            self.assertNotIn("analyse_", sql.lower())
            self.assertNotIn("sq_keys", sql.lower())
            self.assertNotIn("math-cp", sql)
            self.assertNotIn("DELETE FROM papers", sql)
            self.assertIn(r"\\sum", sql)
            report = hs.render_report(bundle)
            self.assertIn("solutions: 1", report)
            self.assertIn("result: ok", report)

    def test_sql_maps_body_onto_content_and_refuses_a_flat_table(self):
        row = self._one_row("O'Brien \\frac")
        bundle = hs.Bundle(
            source="fixture",
            subject="m1",
            lang="zh-HK",
            rows=(row,),
            planned=(row.planned,),
        )
        layout = hs.layout_from_columns(
            {
                "papers": _cols("id", "slug", "title", "subject", nullable={"title", "subject"}),
                "questions": _cols("id", "paper_id", "question_no", "slug"),
                "solutions": _cols("id", "question_id", "content", "source"),
            }
        )
        self.assertEqual(layout.solution["body"], "content")
        sql = hs.render_sql(bundle, layout)
        self.assertIn("INSERT INTO solutions (`question_id`, `content`, `source`)", sql)
        self.assertIn("O''Brien", sql)
        self.assertIn("\\\\frac", sql)
        with self.assertRaises(ValueError):
            hs.layout_from_columns(
                {
                    "papers": _cols("id", "slug"),
                    "questions": _cols("id", "number"),
                    "solutions": _cols("id", "content"),
                }
            )

    def test_sample_paper_year_is_null_and_practice_does_not_use_2022(self):
        row = self._one_row("body")
        planned = row.planned
        sample = hs.PlannedQuestion(
            subject="m1",
            year_label="SP",
            year=None,
            question_no=1,
            paper_slug="dsesp-math-m1",
            question_slug="dsesp-math-m1-q1",
            paper_title="HKDSE Sample Paper M1",
            question_title="Sample Paper M1 Q1",
            source_topic=planned.source_topic,
            folder_slug="sample",
            article_slug="article-1357",
        )
        sample_row = hs.SolutionRow(
            planned=sample,
            lang="zh-HK",
            body="sample\n",
            html="<p>sample</p>",
            body_format="markdown",
            source_url="https://hoksiresources.com/zh-HK/articles/article-1357",
        )
        bundle = hs.Bundle(
            source="fixture",
            subject="m1",
            lang="zh-HK",
            rows=(sample_row,),
            planned=(sample,),
        )
        sql = hs.render_sql(bundle)
        self.assertIn("'dsesp-math-m1'", sql)
        self.assertIn("'SP'", sql)
        self.assertIn(", NULL,", sql)
        self.assertNotIn("2011", sql)
        self.assertNotIn("2022", sql)

    def test_both_on_disk_languages_stay_separate_rows(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self._write_article(root, "zh-HK", "中文", actual_lang="zh-HK")
            self._write_article(root, "en", "English", actual_lang="zh-HK")
            self.assertEqual(
                [lang for lang, _path in hs.language_dirs(root, "hkdse-maths-m1-solutions")],
                ["zh-HK", "en"],
            )
            bundle = hs.load_bundle(root, "m1", years={"2015"})
            self.assertEqual(bundle.errors, ())
            self.assertEqual(sorted(row.lang for row in bundle.rows), ["en", "zh-HK"])
            english = next(row for row in bundle.rows if row.lang == "en")
            self.assertIn("English", english.body)
            self.assertIn("/en/articles/", english.source_url)
            sql = hs.render_sql(bundle)
            self.assertIn("'en'", sql)
            self.assertIn("'zh-HK'", sql)
            report = hs.render_report(bundle)
            self.assertIn("solutions: 2", report)
            self.assertIn("langs: en 1, zh-HK 1", report)

    def test_on_disk_root_is_searched_before_a_partial_checkout(self):
        roots = [str(path) for path in hs.candidate_download_roots()]
        self.assertEqual(roots[0], "/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi")

    def test_gap_subjects_do_not_emit_sql(self):
        bundle = hs.load_bundle(Path("."), "pm")
        self.assertEqual(bundle.rows, ())
        self.assertIn("no Hoksi", hs.render_report(bundle))
        with self.assertRaises(ValueError):
            hs.render_sql(bundle)
        ms = hs.load_bundle(Path("."), "ms")
        self.assertIn("not M&S", hs.render_report(ms))
        self.assertIn("Pure Maths", hs.gap_report())
        self.assertIn("hkcee-maths-solutions", hs.gap_report())

    def test_solution_text_mentioning_core_does_not_fail_the_scope_check(self):
        row = self._one_row("see sq_keys and analyse_sq, not math-cp1")
        bundle = hs.Bundle(
            source="fixture",
            subject="m1",
            lang="zh-HK",
            rows=(row,),
            planned=(row.planned,),
        )
        sql = hs.render_sql(bundle)
        self.assertIn("sq_keys", sql)
        self.assertIn("dse2015-math-m1", sql)

    def _write_article(self, root: Path, lang: str, body_text: str, actual_lang: str) -> None:
        folder = "hkdse-maths-m1-solutions-2015"
        article = "hkdse-maths-m1-solutions-2015-q1"
        topic_dir = root / "hkdse-maths-m1-solutions" / lang
        payload = {
            "slug": article,
            "name": "2015 M1 Q1",
            "sections": [{"content": f"<p>{body_text}</p>", "sort_order": 1}],
            "actual_lang": actual_lang,
        }
        path = topic_dir / folder / f"{article}.json"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps(payload), encoding="utf-8")
        topic = {
            "slug": "hkdse-maths-m1-solutions",
            "name": "M1試題答案",
            "folders": [
                {
                    "slug": folder,
                    "name": "HKDSE 2015 M1",
                    "articles": [{"slug": article, "name": "2015 M1 Q1"}],
                }
            ],
        }
        (topic_dir / "_topic.json").write_text(json.dumps(topic), encoding="utf-8")

    def _one_row(self, body: str) -> hs.SolutionRow:
        planned = hs.PlannedQuestion(
            subject="m1",
            year_label="2015",
            year=2015,
            question_no=1,
            paper_slug="dse2015-math-m1",
            question_slug="dse2015-math-m1-q1",
            paper_title="HKDSE 2015 M1",
            question_title="2015 M1 Q1",
            source_topic="hkdse-maths-m1-solutions",
            folder_slug="hkdse-maths-m1-solutions-2015",
            article_slug="hkdse-maths-m1-solutions-2015-q1",
        )
        return hs.SolutionRow(
            planned=planned,
            lang="zh-HK",
            body=body,
            html="<p>html</p>",
            body_format="markdown",
            source_url="https://hoksiresources.com/zh-HK/articles/hkdse-maths-m1-solutions-2015-q1",
        )


def _cols(*names: str, nullable: set[str] | None = None) -> dict[str, hs.ColumnInfo]:
    optional = nullable or set()
    return {
        name: hs.ColumnInfo(name=name, nullable=name in optional) for name in names
    }


if __name__ == "__main__":
    unittest.main()
