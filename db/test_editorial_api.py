#!/usr/bin/env python3
"""Routing tests for the analyse API.

Compulsory requests must not mention M1, Pure Maths, or content_blocks.
M1/M2 requests must not read the compulsory question tables.
"""

from __future__ import annotations

import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import editorial_api as api


def tables_in(sql: str) -> set[str]:
    return set(re.findall(r"(?:FROM|JOIN)\s+`([A-Za-z0-9_]+)`", sql))


def joined(statements: list[str]) -> str:
    return "\n".join(statements)


CORE_ONLY = {
    "analyse_mc",
    "analyse_mc_units",
    "analyse_sq",
    "analyse_sq_units",
    "analyse_units",
    "analyse_unit_qtypes",
}
MODULE_TABLES = {
    "analyse_m1_sq",
    "analyse_m1_sq_units",
    "analyse_m1_units",
    "analyse_pm_sq",
    "analyse_pm_sq_units",
    "analyse_pm_units",
    "content_blocks",
    "solutions",
    "papers",
    "questions",
}


class FakeDB:
    def __init__(self, rows_for):
        self.calls: list[str] = []
        self.rows_for = rows_for

    def query(self, sql: str) -> list[dict]:
        self.calls.append(sql)
        return self.rows_for(sql)


def call_app(app, path: str, method: str = "GET") -> tuple[str, dict, list]:
    captured: dict = {}

    def start(status, headers):
        captured["status"] = status
        captured["headers"] = headers

    query = ""
    route = path
    if "?" in path:
        route, query = path.split("?", 1)
    body = b"".join(
        app(
            {"REQUEST_METHOD": method, "PATH_INFO": route, "QUERY_STRING": query},
            start,
        )
    )
    payload = json.loads(body.decode("utf-8")) if body else {}
    return captured["status"], payload, captured["headers"]


class RouteTest(unittest.TestCase):
    def setUp(self):
        self.schema = api.assumed_schema()

    def test_core_lookup_uses_only_compulsory_tables(self):
        statements = api.plan_statements(
            "/analyse/lookup",
            {"year": "2015", "question": "1", "kind": "sq"},
            self.schema,
        )
        used = set().union(*(tables_in(sql) for sql in statements))
        self.assertIn("analyse_sq", used)
        self.assertIn("analyse_sq_units", used)
        self.assertIn("analyse_units", used)
        self.assertIn("analyse_unit_qtypes", used)
        self.assertNotIn("analyse_mc", used)
        self.assertTrue(used <= CORE_ONLY)

    def test_core_paper_2_slug_is_multiple_choice(self):
        statements = api.plan_statements(
            "/analyse/lookup",
            {"slug": "dse2015-math-cp2", "question": "4"},
            self.schema,
        )
        used = set().union(*(tables_in(sql) for sql in statements))
        self.assertIn("analyse_mc", used)
        self.assertNotIn("analyse_sq", used)
        self.assertTrue(used <= CORE_ONLY)
        target = api.resolve_target({"slug": "dse2015-math-cp2", "question": "4"})
        self.assertEqual(target.subject, "core")
        self.assertEqual(target.kind, "mc")
        self.assertEqual(target.solutions_mode, "omit")

    def test_core_include_solutions_does_not_read_blocks(self):
        statements = api.plan_statements(
            "/analyse/lookup",
            {"year": "2015", "question": "1", "kind": "sq", "include": "solutions"},
            self.schema,
        )
        used = set().union(*(tables_in(sql) for sql in statements))
        self.assertTrue(used <= CORE_ONLY)
        target = api.resolve_target(
            {"year": "2015", "question": "1", "kind": "sq", "include": "solutions"}
        )
        self.assertEqual(target.solutions_mode, "not_served")

    def test_core_units_and_gaps_stay_on_compulsory_tables(self):
        for path in ("/analyse/units", "/analyse/gaps"):
            statements = api.plan_statements(path, {}, self.schema)
            used = set().union(*(tables_in(sql) for sql in statements))
            self.assertTrue(used <= CORE_ONLY, path)
            self.assertIn("analyse_units", used)

    def test_m1_slug_reads_m1_tables_and_solution_keys(self):
        statements = api.plan_statements(
            "/analyse/lookup",
            {"slug": "dse2015-math-m1-q3"},
            self.schema,
        )
        blob = joined(statements)
        used = set().union(*(tables_in(sql) for sql in statements))
        self.assertIn("analyse_m1_sq", used)
        self.assertIn("analyse_m1_sq_units", used)
        self.assertIn("content_blocks", used)
        self.assertNotIn("analyse_sq", used)
        self.assertNotIn("analyse_mc", used)
        self.assertIn("'dse2015-math-m1-q3:zh-HK'", blob)
        self.assertIn("'dse2015-math-m1-q3:en'", blob)
        self.assertIn("syllabus", blob)
        where = statements[0].split("WHERE", 1)[1]
        self.assertIn("'15'", where)
        self.assertIn("'dse'", where)
        self.assertNotIn("year_key", where)

    def test_2012_slug_is_the_dse_column(self):
        statements = api.plan_statements(
            "/analyse/lookup",
            {"slug": "dse2012-math-m1", "question": "11"},
            self.schema,
        )
        where = statements[0].split("WHERE", 1)[1]
        self.assertIn("12#U", where)
        self.assertNotIn("year_label", where)
        target = api.resolve_target({"slug": "dse2012-math-m1", "question": "11"})
        self.assertEqual(target.band, "dse")
        self.assertEqual(target.year_key, "12#U")
        self.assertEqual(target.paper_slug, "dse2012-math-m1")

    def test_2012_without_band_is_rejected(self):
        with self.assertRaises(api.RouteError) as caught:
            api.resolve_target({"subject": "m1", "year": "2012", "question": "1"})
        self.assertEqual(caught.exception.code, "ambiguous_2012")

    def test_ms_2012_is_the_first_column_and_blocks_solutions(self):
        statements = api.plan_statements(
            "/analyse/lookup",
            {"subject": "ms", "year": "2012", "question": "11"},
            self.schema,
        )
        blob = joined(statements)
        where = statements[0].split("WHERE", 1)[1]
        self.assertIn("12#T", where)
        self.assertIn("analyse_m1_sq", blob)
        self.assertNotIn("content_blocks", blob)
        self.assertNotIn("`analyse_sq`", blob)
        target = api.resolve_target({"subject": "ms", "year": "2012", "question": "11"})
        self.assertEqual(target.solutions_mode, "blocked")
        self.assertIsNone(target.paper_slug)

    def test_2012_falls_back_to_label_occurrence(self):
        schema = self.schema.without()
        del schema.tables["analyse_m1_sq"]["year_key"]
        target = api.resolve_target({"slug": "dse2012-math-m1", "question": "1"})
        sql = api.question_sql(schema, target, "sq")
        where = sql.split("WHERE", 1)[1]
        self.assertIn("label_occurrence", where)
        self.assertIn("= 2", where)
        self.assertIn("'12'", where)

    def test_pre_2012_m1_points_at_ms(self):
        with self.assertRaises(api.RouteError) as caught:
            api.resolve_target({"subject": "m1", "year": "1994", "question": "1"})
        self.assertEqual(caught.exception.code, "use_ms")

    def test_m2_slug_uses_analyse_pm_paper_1(self):
        statements = api.plan_statements(
            "/analyse/lookup",
            {"slug": "dse2015-math-m2", "question": "2"},
            self.schema,
        )
        blob = joined(statements)
        where = statements[0].split("WHERE", 1)[1]
        self.assertIn("analyse_pm_sq", blob)
        self.assertNotIn("analyse_m1_sq", blob)
        self.assertNotIn("`analyse_sq`", blob)
        self.assertIn("'m2'", where)
        self.assertIn("`paper` = 1", where)
        self.assertIn("content_blocks", blob)
        self.assertIn("'dse2015-math-m2-q2:en'", blob)

    def test_pure_maths_keeps_0x_distinct_and_blocks_solutions(self):
        lower = joined(
            api.plan_statements(
                "/analyse/units",
                {"subject": "pm", "unit": "0x", "year": "1989", "paper": "1"},
                self.schema,
            )
        )
        upper = joined(
            api.plan_statements(
                "/analyse/units",
                {"subject": "pm", "unit": "0X", "year": "1989", "paper": "1"},
                self.schema,
            )
        )
        self.assertIn("'0x'", lower)
        self.assertNotIn("'0X'", lower)
        self.assertIn("'0X'", upper)
        self.assertNotIn("'0x'", upper)
        self.assertIn("utf8mb4_bin", lower)
        self.assertNotIn("content_blocks", lower)
        lookup = joined(
            api.plan_statements(
                "/analyse/lookup",
                {"subject": "pm", "year": "1989", "question": "7", "paper": "1"},
                self.schema,
            )
        )
        self.assertIn("analyse_pm_sq", lookup)
        self.assertNotIn("content_blocks", lookup)
        target = api.resolve_target(
            {"subject": "pm", "year": "1989", "question": "7", "paper": "1"}
        )
        self.assertEqual(target.solutions_mode, "blocked")

    def test_old_m2_year_is_pure_maths(self):
        with self.assertRaises(api.RouteError) as caught:
            api.resolve_target({"subject": "m2", "year": "1998", "question": "1"})
        self.assertEqual(caught.exception.code, "use_pm")
        with self.assertRaises(api.RouteError) as caught:
            api.resolve_target({"subject": "pm", "year": "2015", "question": "1"})
        self.assertEqual(caught.exception.code, "use_m2")

    def test_slug_subject_conflict(self):
        with self.assertRaises(api.RouteError) as caught:
            api.resolve_target({"subject": "m1", "slug": "dse2015-math-m2", "question": "1"})
        self.assertEqual(caught.exception.code, "slug_mismatch")

    def test_module_mc_is_rejected(self):
        with self.assertRaises(api.RouteError) as caught:
            api.resolve_target({"subject": "m1", "year": "2015", "question": "1", "kind": "mc"})
        self.assertEqual(caught.exception.code, "no_mc")


class ExecuteTest(unittest.TestCase):
    def setUp(self):
        self.schema = api.assumed_schema()

    def test_core_lookup_response_has_no_solutions_key(self):
        def rows_for(sql: str):
            if "FROM `analyse_sq` s WHERE" in sql:
                return [
                    {
                        "id": "4",
                        "question_no": "1",
                        "year_label": "2015",
                        "raw_cell": "3,5",
                    }
                ]
            if "FROM `analyse_sq_units`" in sql:
                return [
                    {
                        "position": "1",
                        "unit_code": "3",
                        "short_name": "quad",
                        "name": "Quadratic",
                    }
                ]
            if "analyse_unit_qtypes" in sql:
                return [{"unit_code": "3", "qtype": "complete"}]
            return []

        db = FakeDB(rows_for)
        status, payload = api.dispatch(
            "/analyse/lookup",
            {"year": "2015", "question": "1", "kind": "sq"},
            self.schema,
            db,
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["subject"], "core")
        self.assertNotIn("solutions", payload)
        self.assertEqual(payload["units"][0]["qtypes"], ["complete"])
        self.assertEqual(payload["results"][0]["units"][0]["qtypes"], ["complete"])
        self.assertEqual(payload["results"][0]["paper"], 1)
        blob = joined(db.calls)
        self.assertNotIn("content_blocks", blob)
        self.assertNotIn("analyse_m1", blob)
        self.assertNotIn("analyse_pm", blob)
        self.assertTrue(any("= 4" in sql and "analyse_sq_units" in sql for sql in db.calls))

    def test_core_not_found_does_not_touch_module_tables(self):
        db = FakeDB(lambda sql: [])
        with self.assertRaises(api.RouteError) as caught:
            api.dispatch(
                "/analyse/lookup",
                {"slug": "dse2015-math-cp1", "question": "9"},
                self.schema,
                db,
            )
        self.assertEqual(caught.exception.status, 404)
        blob = joined(db.calls)
        self.assertIn("analyse_sq", blob)
        self.assertNotIn("content_blocks", blob)
        self.assertNotIn("analyse_m1", blob)

    def test_m1_lookup_returns_units_and_solution_text(self):
        def rows_for(sql: str):
            if "FROM `analyse_m1_sq` s WHERE" in sql:
                return [
                    {
                        "id": "10",
                        "question_no": "3",
                        "year_label": "15",
                        "year_key": "15",
                        "raw_cell": "7, 8",
                        "syllabus": "dse",
                    }
                ]
            if "analyse_m1_sq_units" in sql:
                return [
                    {
                        "position": "1",
                        "unit_code": "7",
                        "short_name": "int",
                        "name": "Integration",
                    },
                    {
                        "position": "2",
                        "unit_code": "8",
                        "short_name": "app int",
                        "name": "Application of integration",
                    },
                ]
            if "content_blocks" in sql:
                return [
                    {
                        "body": "<!-- hoksi:dse2015-math-m1:q3:zh-HK:solution -->\n\\frac{1}{2}",
                        "block_key": "dse2015-math-m1-q3:zh-HK",
                        "lang": "zh-HK",
                        "sortorder": "1",
                    }
                ]
            return []

        db = FakeDB(rows_for)
        status, payload = api.dispatch(
            "/analyse/lookup",
            {"slug": "dse2015-math-m1", "question": "3"},
            self.schema,
            db,
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["subject"], "m1")
        self.assertEqual(payload["band"], "dse")
        units = payload["results"][0]["units"]
        self.assertEqual([unit["unit_code"] for unit in units], ["7", "8"])
        self.assertNotIn("qtypes", units[0])
        solutions = payload["solutions"]
        self.assertEqual(solutions["status"], "ok")
        self.assertEqual(solutions["question_slug"], "dse2015-math-m1-q3")
        self.assertEqual(solutions["items"][0]["lang"], "zh-HK")
        self.assertEqual(solutions["items"][0]["text"], r"\frac{1}{2}")
        self.assertNotIn("hoksi:", solutions["items"][0]["text"])
        self.assertNotIn("`analyse_sq`", joined(db.calls))

    def test_pure_maths_lookup_blocks_solutions(self):
        def rows_for(sql: str):
            if "FROM `analyse_pm_sq` s WHERE" in sql:
                return [
                    {
                        "id": "7",
                        "question_no": "7",
                        "year_label": "89",
                        "paper": "1",
                        "syllabus": "pm",
                        "raw_cell": "0x",
                    }
                ]
            if "analyse_pm_sq_units" in sql:
                return [
                    {"position": "1", "unit_code": "0x", "short_name": None, "name": None}
                ]
            return []

        db = FakeDB(rows_for)
        _status, payload = api.dispatch(
            "/analyse/lookup",
            {"subject": "pm", "year": "1989", "question": "7", "paper": "1"},
            self.schema,
            db,
        )
        self.assertEqual(payload["results"][0]["units"][0]["unit_code"], "0x")
        self.assertEqual(payload["solutions"]["status"], "blocked")
        self.assertIn("analyse-only", payload["solutions"]["reason"])
        self.assertNotIn("content_blocks", joined(db.calls))

    def test_m1_gaps_list_missing_languages_and_block_ms(self):
        def rows_for(sql: str):
            if "content_blocks" in sql:
                return [{"block_key": "dse2015-math-m1-q1:zh-HK"}]
            if "IS NULL" in sql or "analyse_m1_units" in sql:
                return []
            if "syllabus" in sql and "'dse'" in sql:
                return [
                    {
                        "id": "1",
                        "question_no": "1",
                        "year_label": "15",
                        "year_key": "15",
                        "syllabus": "dse",
                    },
                    {
                        "id": "2",
                        "question_no": "2",
                        "year_label": "15",
                        "year_key": "15",
                        "syllabus": "dse",
                    },
                ]
            return []

        db = FakeDB(rows_for)
        status, payload = api.dispatch("/analyse/gaps", {"subject": "m1"}, self.schema, db)
        self.assertEqual(status, 200)
        self.assertEqual(payload["band"], "all")
        by_band = {section["band"]: section for section in payload["syllabi"]}
        self.assertEqual(by_band["ms"]["solutions"], "blocked")
        self.assertNotIn("missing_solutions", by_band["ms"])
        missing = {row["question_no"]: row["missing_langs"] for row in by_band["dse"]["missing_solutions"]}
        self.assertEqual(missing[1], ["en"])
        self.assertEqual(missing[2], ["zh-HK", "en"])
        self.assertNotIn("`analyse_sq`", joined(db.calls))

    def test_gaps_without_content_blocks_are_not_fake_missing_rows(self):
        schema = self.schema.without("content_blocks")
        db = FakeDB(lambda sql: [])
        _status, payload = api.dispatch(
            "/analyse/gaps",
            {"subject": "m2", "year": "2015"},
            schema,
            db,
        )
        self.assertEqual(payload["solutions"], "not_installed")
        self.assertNotIn("missing_solutions", payload)
        self.assertNotIn("content_blocks", joined(db.calls))

    def test_unit_order_keeps_0x_after_0X(self):
        codes = ["10", "2", "0x", "0", "14X", "0X"]
        self.assertEqual(
            sorted(codes, key=api.unit_sort_key),
            ["0", "0X", "0x", "2", "10", "14X"],
        )


class HttpTest(unittest.TestCase):
    def test_get_lookup_and_unknown_path(self):
        def rows_for(sql: str):
            if "FROM `analyse_m1_sq` s WHERE" in sql:
                return [
                    {
                        "id": "1",
                        "question_no": "1",
                        "year_label": "SP",
                        "year_key": "SP",
                        "syllabus": "dse",
                        "raw_cell": "1",
                    }
                ]
            if "analyse_m1_sq_units" in sql:
                return [
                    {"position": "1", "unit_code": "1", "short_name": "binomial", "name": "Binomial"}
                ]
            return []

        app = api.build_app(api.assumed_schema(), FakeDB(rows_for))
        status, payload, headers = call_app(app, "/analyse/lookup?slug=dsesp-math-m1&question=1")
        self.assertTrue(status.startswith("200"), status)
        self.assertEqual(payload["results"][0]["year_label"], "SP")
        self.assertEqual(payload["solutions"]["status"], "missing")
        self.assertEqual(payload["solutions"]["paper_slug"], "dsesp-math-m1")
        self.assertIn(("Access-Control-Allow-Origin", "*"), headers)
        missing, body, _headers = call_app(app, "/analyse/nope")
        self.assertTrue(missing.startswith("404"))
        self.assertEqual(body["error"], "not_found")
        denied, _body, _headers = call_app(app, "/analyse/lookup", method="POST")
        self.assertTrue(denied.startswith("405"))

    def test_integer_year_column_uses_the_calendar_year(self):
        schema = api.assumed_schema()
        schema.tables["analyse_sq"] = {
            "id": "int",
            "year": "smallint",
            "question_no": "smallint",
            "raw_cell": "varchar(255)",
        }
        target = api.resolve_target({"year": "2015", "question": "1", "kind": "sq"})
        sql = api.question_sql(schema, target, "sq")
        self.assertIn("`year` IN (2015)", sql)
        self.assertNotIn("'15'", sql)
        with self.assertRaises(api.RouteError) as caught:
            api.question_sql(
                schema,
                api.resolve_target({"year": "SP", "question": "1", "kind": "sq"}),
                "sq",
            )
        self.assertEqual(caught.exception.code, "bad_year")

    def test_plan_cli_stays_offline(self):
        import contextlib
        import io

        stdout, stderr = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
            code = api.main(["--plan", "lookup", "--year", "2015", "--question", "1", "--kind", "sq"])
        self.assertEqual(code, 0)
        self.assertIn("subject=core", stdout.getvalue())
        self.assertNotIn("analyse_m1", stdout.getvalue())
        self.assertNotIn("content_blocks", stdout.getvalue())
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(stderr):
            failed = api.main(
                ["--plan", "lookup", "--subject", "m1", "--year", "2012", "--question", "1"]
            )
        self.assertEqual(failed, 1)
        self.assertIn("ambiguous_2012", stderr.getvalue())

    def test_mysql_xml_null_and_refuses_multiple_statements(self):
        rows = api.parse_mysql_xml(
            """
            <resultset>
              <row>
                <field name="unit_code">0x</field>
                <field name="name" xsi:nil="true" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"/>
              </row>
            </resultset>
            """
        )
        self.assertEqual(rows[0]["unit_code"], "0x")
        self.assertIsNone(rows[0]["name"])
        self.assertEqual(api.lit("O'Brien"), "'O''Brien'")
        with self.assertRaises(RuntimeError):
            api.MysqlCli().query("SELECT 1; DROP TABLE analyse_sq")


if __name__ == "__main__":
    unittest.main()
