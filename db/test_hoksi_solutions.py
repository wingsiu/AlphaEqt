#!/usr/bin/env python3
"""Parser and SQL checks for the Hoksi M1/M2 solution ingest."""

from __future__ import annotations

import json
import os
import subprocess
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

    def test_live_question_columns_write_content_blocks(self):
        bundle = self._bundle(self._one_row(r"\sum p = 1"))
        tables = _live_tables()
        with self.assertRaises(ValueError) as caught:
            hs.layout_from_columns(tables)
        self.assertIn("question_no", str(caught.exception))
        sql = hs.render_for_tables(bundle, tables)
        self.assertIn("INSERT INTO content_blocks", sql)
        self.assertIn("`stem_block_id`", sql)
        self.assertIn("`content_block_id`", sql)
        self.assertIn("`sortorder`", sql)
        self.assertIn("`qkind`", sql)
        self.assertIn("'sq'", sql)
        self.assertIn("'hoksi'", sql)
        self.assertIn("dse2015-math-m1-q1:zh-HK", sql)
        self.assertIn("dse2015-math-m1-q1:stem", sql)
        self.assertIn(r"\\sum", sql)
        self.assertNotIn("question_no", sql)
        self.assertNotIn("`source_pdf`", sql)
        self.assertNotIn("`topic_id`", sql)
        self.assertNotIn("`level`", sql)
        self.assertNotIn("`marks`", sql)
        self.assertNotIn("`body`", sql)
        self.assertNotRegex(sql, r"(?i)\balter\s+table\b")
        self.assertNotRegex(sql, r"(?i)\bcreate\s+table\b")
        self.assertNotIn("DELETE ", sql)
        for statement in sql.split(";"):
            if "UPDATE content_blocks" in statement:
                self.assertNotIn(":stem", statement)
            self.assertNotIn("UPDATE questions", statement)
        solution_insert = _statement_with(sql, "INSERT INTO solutions")
        self.assertIn("dse2015-math-m1-q1:zh-HK", solution_insert)
        self.assertRegex(solution_insert, r", 1\s+FROM")

    def test_both_languages_use_sortorder_one_and_two(self):
        english = self._one_row("English")
        english.lang = "en"
        bundle = self._bundle(self._one_row("中文"), english)
        sql = hs.render_editorial_sql(bundle, _live_tables())
        chinese = [
            part
            for part in sql.split(";")
            if "INSERT INTO solutions" in part and "dse2015-math-m1-q1:zh-HK" in part
        ]
        western = [
            part
            for part in sql.split(";")
            if "INSERT INTO solutions" in part and "dse2015-math-m1-q1:en" in part
        ]
        self.assertEqual(len(chinese), 1)
        self.assertEqual(len(western), 1)
        self.assertRegex(chinese[0], r", 1\s+FROM")
        self.assertRegex(western[0], r", 2\s+FROM")
        self.assertIn("中文", sql)
        self.assertIn("English", sql)

    def test_solution_without_question_id_sorts_by_question_number(self):
        tables = _live_tables()
        tables["solutions"] = _cols("id", "paper_id", "content_block_id", "sortorder")
        sql = hs.render_editorial_sql(self._bundle(self._one_row("body")), tables)
        insert = [
            part
            for part in sql.split(";")
            if "INSERT INTO solutions" in part
        ][0]
        self.assertIn("`paper_id`", insert)
        self.assertNotIn("question_id", insert)
        self.assertRegex(insert, r", 11\s+FROM")

    def test_unique_paper_sortorder_does_not_collapse_languages(self):
        tables = _live_tables()
        tables["solutions"] = _cols(
            "id", "question_id", "paper_id", "content_block_id", "sortorder"
        )
        sql = hs.render_editorial_sql(
            self._bundle(self._one_row("body")),
            tables,
            unique_keys={"solutions": (("paper_id", "sortorder"),)},
        )
        insert = [part for part in sql.split(";") if "INSERT INTO solutions" in part][0]
        self.assertIn("`question_id`", insert)
        self.assertRegex(insert, r", 11\s+FROM")

    def test_editorial_refuses_a_block_table_with_no_text_column(self):
        tables = _live_tables()
        tables["content_blocks"] = _cols("id", "kind", nullable={"kind"})
        with self.assertRaises(ValueError) as caught:
            hs.render_editorial_sql(self._bundle(self._one_row("body")), tables)
        self.assertIn("no text column", str(caught.exception))

    def test_editorial_refuses_to_invent_topic_id_or_qkind(self):
        tables = _live_tables()
        tables["questions"] = _cols(
            "created",
            "id",
            "level",
            "marks",
            "paper_id",
            "qkind",
            "source_type",
            "stem_block_id",
            "topic_id",
            "updated",
            nullable={"level", "marks", "stem_block_id"},
            types={
                "qkind": "enum('mc','sq')",
                "source_type": "enum('ocr','hoksi','editorial')",
                "created": "timestamp",
                "updated": "timestamp",
            },
            defaults={
                "created": "current_timestamp()",
                "updated": "current_timestamp()",
            },
        )
        with self.assertRaises(ValueError) as caught:
            hs.render_editorial_sql(self._bundle(self._one_row("body")), tables)
        self.assertIn("topic_id", str(caught.exception))
        self.assertIn("invent a topic id", str(caught.exception))

        tables = _live_tables()
        tables["questions"] = _cols(
            "id",
            "paper_id",
            "qkind",
            "stem_block_id",
            nullable={"stem_block_id"},
            types={"qkind": "enum('mc')"},
        )
        with self.assertRaises(ValueError) as caught:
            hs.render_editorial_sql(self._bundle(self._one_row("body")), tables)
        self.assertIn("qkind", str(caught.exception))
        self.assertIn("mc", str(caught.exception))

    def test_missing_content_blocks_does_not_fall_back_to_question_no(self):
        tables = _live_tables()
        del tables["content_blocks"]
        with self.assertRaises(ValueError) as caught:
            hs.render_for_tables(self._bundle(self._one_row("body")), tables)
        message = str(caught.exception)
        self.assertIn("content_blocks", message)
        self.assertIn("question_no", message)
        self.assertNotIn("solutions_schema", message)

    def test_show_columns_keeps_enum_and_defaults(self):
        import seed_hoksi_solutions as seed

        text = "\n".join(
            [
                "Field\tType\tNull\tKey\tDefault\tExtra",
                "id\tint(11)\tNO\tPRI\tNULL\tauto_increment",
                "qkind\tenum('mc','sq')\tNO\t\tNULL\t",
                "created\ttimestamp\tNO\t\tcurrent_timestamp()\t",
            ]
        )
        columns = seed.parse_show_columns(text)
        self.assertEqual(columns["id"].key, "PRI")
        self.assertIn("auto_increment", columns["id"].extra)
        self.assertFalse(columns["id"].must_fill())
        self.assertEqual(columns["qkind"].column_type, "enum('mc','sq')")
        self.assertTrue(columns["qkind"].must_fill())
        self.assertEqual(columns["created"].default, "current_timestamp()")
        self.assertFalse(columns["created"].must_fill())
        index = "\n".join(
            [
                "Table\tNon_unique\tKey_name\tSeq_in_index\tColumn_name",
                "solutions\t0\tuq_paper_sort\t1\tpaper_id",
                "solutions\t0\tuq_paper_sort\t2\tsortorder",
                "solutions\t1\tidx_block\t1\tcontent_block_id",
            ]
        )
        self.assertEqual(hs.parse_show_index(index), (("paper_id", "sortorder"),))

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

    def _bundle(self, *rows: hs.SolutionRow) -> hs.Bundle:
        return hs.Bundle(
            source="fixture",
            subject="m1",
            lang=",".join(row.lang for row in rows),
            rows=rows,
            planned=tuple(row.planned for row in rows),
        )


def _statement_with(sql: str, needle: str) -> str:
    matches = [part for part in sql.split(";") if needle in part]
    if len(matches) != 1:
        raise AssertionError(f"expected one statement containing {needle!r}, found {len(matches)}")
    return matches[0]


def _live_tables() -> dict[str, dict[str, hs.ColumnInfo]]:
    return {
        "papers": _cols("id", "slug", "title", "source_pdf", nullable={"source_pdf"}),
        "questions": _cols(
            "created",
            "id",
            "level",
            "marks",
            "paper_id",
            "qkind",
            "source_type",
            "stem_block_id",
            "topic_id",
            "updated",
            nullable={"level", "marks", "topic_id", "stem_block_id"},
            types={
                "qkind": "enum('mc','sq')",
                "source_type": "enum('ocr','hoksi','editorial')",
                "created": "timestamp",
                "updated": "timestamp",
            },
            defaults={
                "created": "current_timestamp()",
                "updated": "current_timestamp()",
            },
        ),
        "solutions": _cols("id", "question_id", "content_block_id", "sortorder"),
        "content_blocks": _cols(
            "id",
            "content",
            "html",
            "kind",
            "format",
            "lang",
            "source",
            "source_slug",
            nullable={"html", "kind", "format", "lang", "source", "source_slug"},
        ),
    }


def _cols(
    *names: str,
    nullable: set[str] | None = None,
    types: dict[str, str] | None = None,
    defaults: dict[str, str] | None = None,
    keys: dict[str, str] | None = None,
) -> dict[str, hs.ColumnInfo]:
    optional = nullable or set()
    column_types = types or {}
    column_defaults = defaults or {}
    column_keys = keys or {}
    return {
        name: hs.ColumnInfo(
            name=name,
            nullable=name in optional,
            column_type=column_types.get(name, ""),
            default=column_defaults.get(name),
            extra="auto_increment" if name == "id" else "",
            key=column_keys.get(name, "PRI" if name == "id" else ""),
        )
        for name in names
    }


class EditorialApplyTest(unittest.TestCase):
    def test_apply_writes_content_blocks_and_leaves_core_rows(self):
        if not os.environ.get("MYSQL_PWD") or not os.environ.get("MYSQL_USER"):
            self.skipTest("MYSQL_PWD and MYSQL_USER are not set")
        if not _root_mysql("SELECT 1"):
            self.skipTest("local MariaDB root socket is unavailable")

        database = "hoksi_editorial_test"
        user = os.environ["MYSQL_USER"]
        self.assertTrue(
            _root_mysql(
                f"DROP DATABASE IF EXISTS `{database}`;"
                f"CREATE DATABASE `{database}` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
                f"GRANT ALL PRIVILEGES ON `{database}`.* TO '{user}'@'127.0.0.1';"
                "FLUSH PRIVILEGES;"
            )
        )
        try:
            self.assertEqual(_mysql(database, _EDITORIAL_DDL), 0)
            with tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                _write_pack(root, "zh-HK", "中文解")
                _write_pack(root, "en", "English")
                first = _seed(root, database)
                self.assertEqual(first.returncode, 0, first.stderr)
                self.assertEqual(
                    _mysql(
                        database,
                        "UPDATE content_blocks SET content = 'OCR-STEM' "
                        "WHERE source_slug = 'dse2015-math-m1-q1:stem';",
                    ),
                    0,
                )
                _write_pack(root, "zh-HK", "中文解-revised")
                second = _seed(root, database)
                self.assertEqual(second.returncode, 0, second.stderr)

            counts = _mysql_query(
                database,
                """
                SELECT
                  (SELECT COUNT(*) FROM papers WHERE slug = 'dse2015-math-m1'),
                  (SELECT COUNT(*) FROM questions q
                     JOIN papers p ON p.id = q.paper_id
                    WHERE p.slug = 'dse2015-math-m1'),
                  (SELECT COUNT(*) FROM solutions s
                     JOIN questions q ON q.id = s.question_id
                     JOIN papers p ON p.id = q.paper_id
                    WHERE p.slug = 'dse2015-math-m1'),
                  (SELECT COUNT(*) FROM content_blocks
                    WHERE source_slug LIKE 'dse2015-math-m1-q1:%'),
                  (SELECT content = 'OCR-STEM' FROM content_blocks WHERE source_slug = 'dse2015-math-m1-q1:stem'),
                  (SELECT LOCATE('中文解-revised', content) > 0 AND LOCATE('\\\\sum', content) > 0
                     FROM content_blocks WHERE source_slug = 'dse2015-math-m1-q1:zh-HK'),
                  (SELECT sortorder FROM solutions s
                     JOIN content_blocks b ON b.id = s.content_block_id
                    WHERE b.source_slug = 'dse2015-math-m1-q1:zh-HK'),
                  (SELECT sortorder FROM solutions s
                     JOIN content_blocks b ON b.id = s.content_block_id
                    WHERE b.source_slug = 'dse2015-math-m1-q1:en'),
                  (SELECT content = 'CORE-KEEP' FROM content_blocks WHERE source_slug = 'core-keep'),
                  (SELECT COUNT(*) FROM solutions s
                     JOIN questions q ON q.id = s.question_id
                     JOIN papers p ON p.id = q.paper_id
                    WHERE p.slug = 'dse2015-math-cp1'),
                  (SELECT note FROM analyse_m1_sq),
                  (SELECT note FROM sq_keys),
                  (SELECT qkind FROM questions q
                     JOIN papers p ON p.id = q.paper_id
                    WHERE p.slug = 'dse2015-math-m1'),
                  (SELECT source_type FROM questions q
                     JOIN papers p ON p.id = q.paper_id
                    WHERE p.slug = 'dse2015-math-m1')
                """,
            )
            fields = counts.split("\t")
            self.assertEqual(fields[0], "1")
            self.assertEqual(fields[1], "1")
            self.assertEqual(fields[2], "2")
            self.assertEqual(fields[3], "3")
            self.assertEqual(fields[4], "1")
            self.assertEqual(fields[5], "1")
            self.assertEqual(fields[6], "1")
            self.assertEqual(fields[7], "2")
            self.assertEqual(fields[8], "1")
            self.assertEqual(fields[9], "1")
            self.assertEqual(fields[10], "keep")
            self.assertEqual(fields[11], "core-key")
            self.assertEqual(fields[12], "sq")
            self.assertEqual(fields[13], "hoksi")
        finally:
            _root_mysql(f"DROP DATABASE IF EXISTS `{database}`;")


_EDITORIAL_DDL = """
CREATE TABLE papers (
  id INT NOT NULL AUTO_INCREMENT,
  slug VARCHAR(64) NOT NULL,
  title VARCHAR(255) NOT NULL,
  source_pdf VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_papers_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE content_blocks (
  id INT NOT NULL AUTO_INCREMENT,
  content MEDIUMTEXT NOT NULL,
  html MEDIUMTEXT NULL,
  kind VARCHAR(32) NULL,
  format VARCHAR(32) NULL,
  lang VARCHAR(16) NULL,
  source VARCHAR(32) NULL,
  source_slug VARCHAR(191) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_blocks_source_slug (source_slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE questions (
  id INT NOT NULL AUTO_INCREMENT,
  paper_id INT NOT NULL,
  level VARCHAR(16) NULL,
  marks INT NULL,
  qkind ENUM('mc','sq') NOT NULL,
  source_type ENUM('ocr','hoksi','editorial') NOT NULL,
  stem_block_id INT NULL,
  topic_id INT NULL,
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_questions_paper (paper_id),
  KEY idx_questions_stem (stem_block_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE solutions (
  id INT NOT NULL AUTO_INCREMENT,
  question_id INT NOT NULL,
  content_block_id INT NOT NULL,
  sortorder INT NOT NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_solutions_block (content_block_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE analyse_m1_sq (
  id INT NOT NULL PRIMARY KEY,
  note VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
CREATE TABLE sq_keys (
  id INT NOT NULL PRIMARY KEY,
  note VARCHAR(32) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
INSERT INTO papers (slug, title) VALUES ('dse2015-math-cp1', 'CORE');
INSERT INTO content_blocks (content, source_slug, kind) VALUES ('CORE-KEEP', 'core-keep', 'solution');
INSERT INTO questions (paper_id, qkind, source_type, stem_block_id)
SELECT p.id, 'sq', 'ocr', b.id
FROM papers p
JOIN content_blocks b ON b.source_slug = 'core-keep'
WHERE p.slug = 'dse2015-math-cp1';
INSERT INTO solutions (question_id, content_block_id, sortorder)
SELECT q.id, b.id, 1
FROM questions q
JOIN papers p ON p.id = q.paper_id
JOIN content_blocks b ON b.source_slug = 'core-keep'
WHERE p.slug = 'dse2015-math-cp1';
INSERT INTO analyse_m1_sq (id, note) VALUES (1, 'keep');
INSERT INTO sq_keys (id, note) VALUES (1, 'core-key');
"""


def _write_pack(root: Path, lang: str, body_text: str) -> None:
    folder = "hkdse-maths-m1-solutions-2015"
    article = "hkdse-maths-m1-solutions-2015-q1"
    topic_dir = root / "hkdse-maths-m1-solutions" / lang
    payload = {
        "slug": article,
        "name": "2015 M1 Q1",
        "sections": [
            {
                "content": f"<p>{body_text}</p><span class=\"math-tex\">\\(\\sum\\)</span>",
                "sort_order": 1,
            }
        ],
        "actual_lang": "zh-HK",
    }
    path = topic_dir / folder / f"{article}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
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


def _mysql_base() -> list[str]:
    return [
        os.environ.get("MYSQL_BIN", "mysql"),
        "--batch",
        "--connect-timeout=10",
        "-h",
        os.environ.get("MYSQL_HOST", "127.0.0.1"),
        "-P",
        os.environ.get("MYSQL_PORT", "3306"),
        "-u",
        os.environ["MYSQL_USER"],
    ]


def _mysql(database: str, sql: str) -> int:
    completed = subprocess.run(
        [*_mysql_base(), database],
        input=sql,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr)
    return completed.returncode


def _mysql_query(database: str, sql: str) -> str:
    completed = subprocess.run(
        [*_mysql_base(), "-N", database],
        input=sql,
        text=True,
        capture_output=True,
        check=False,
        env=os.environ.copy(),
    )
    if completed.returncode != 0:
        raise AssertionError(completed.stderr)
    lines = [line for line in completed.stdout.splitlines() if line.strip()]
    if len(lines) != 1:
        raise AssertionError(completed.stdout)
    return lines[0]


def _root_mysql(sql: str) -> bool:
    completed = subprocess.run(
        [
            "sudo",
            "mysql",
            "--socket=/var/run/mysqld/mysqld.sock",
            "--batch",
        ],
        input=sql,
        text=True,
        capture_output=True,
        check=False,
    )
    return completed.returncode == 0


def _seed(root: Path, database: str) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["MYSQL_DATABASE"] = database
    env["HOKSI_DOWNLOAD_ROOT"] = str(root)
    return subprocess.run(
        [
            sys.executable,
            str(ROOT / "seed_hoksi_solutions.py"),
            "--apply",
            "--subject",
            "m1",
            "--year",
            "2015",
        ],
        text=True,
        capture_output=True,
        check=False,
        env=env,
        cwd=str(ROOT.parent),
    )


if __name__ == "__main__":
    unittest.main()
