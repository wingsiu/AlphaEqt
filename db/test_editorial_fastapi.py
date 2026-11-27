#!/usr/bin/env python3
"""FastAPI editorial routes, including draft content pages. No MySQL."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import pymysql
from fastapi.routing import APIRoute
from fastapi.testclient import TestClient

import content_pages
import editorial_api


def page_row(**overrides) -> dict:
    row = {
        "page_id": "10",
        "slug": "draft-note",
        "title": "Draft",
        "kind": "note",
        "status": "D",
        "current_version_id": "20",
        "version_id": "20",
        "version_no": "1",
        "note": None,
        "version_status": "D",
    }
    row.update(overrides)
    return row


class ScriptDB:
    def __init__(self, rows_for, script_row=None):
        self.calls: list[str] = []
        self.scripts: list[str] = []
        self.rows_for = rows_for
        self.script_row = script_row or {
            "page_id": "10",
            "version_id": "20",
            "paper_id": "30",
            "item_count": "2",
            "revision_id": "40",
            "wrote": "1",
        }

    def query(self, sql: str) -> list[dict]:
        self.calls.append(sql)
        return self.rows_for(sql)

    def script(self, sql: str) -> list[dict]:
        self.scripts.append(sql)
        return [dict(self.script_row)]


class _Cursor:
    def __init__(self, conn: "_Conn"):
        self.conn = conn
        self.description = None
        self._rows: list[dict] = []
        self._index = -1

    def execute(self, sql: str, args=None):
        if args is not None:
            raise AssertionError("content SQL is already literal")
        self.conn.executed.append(sql)
        if self.conn.error is not None:
            raise self.conn.error
        self._index = -1
        self._advance()

    def _advance(self) -> bool:
        self._index += 1
        if self._index >= len(self.conn.sets):
            return False
        self.description, self._rows = self.conn.sets[self._index]
        return True

    def fetchall(self):
        return self._rows

    def nextset(self):
        if self._index + 1 >= len(self.conn.sets):
            return None
        return self._advance()

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class _Conn:
    def __init__(self, sets=None, error=None):
        self.executed: list[str] = []
        self.sets = sets or []
        self.error = error

    def cursor(self):
        return _Cursor(self)


class AdapterTests(unittest.TestCase):
    def test_script_stays_one_statement_and_returns_the_last_select(self):
        sql = (
            "USE alphaeqt;\nSTART TRANSACTION;\n"
            "INSERT INTO content_blocks (markdown) VALUES ('line;\nnext');\n"
            "SELECT 10 AS page_id;\n"
            "COMMIT;"
        )
        conn = _Conn(
            sets=[
                (None, []),
                (None, []),
                (None, []),
                (("page_id",), [{"page_id": 10}]),
                (None, []),
            ]
        )
        rows = editorial_api.PymysqlContentDB(conn).script(sql)
        self.assertEqual(conn.executed, [sql])
        self.assertEqual(rows, [{"page_id": 10}])

    def test_query_refuses_a_second_statement(self):
        with self.assertRaises(RuntimeError):
            editorial_api.PymysqlContentDB(_Conn()).query("SELECT 1; DROP TABLE content_pages")

    def test_duplicate_slug_from_mysql_is_page_exists(self):
        conn = _Conn(
            error=pymysql.err.IntegrityError(
                1062, "Duplicate entry 'draft-note' for key 'uq_content_pages_slug'"
            )
        )
        sql = "USE alphaeqt;\nSTART TRANSACTION;\nSELECT 1;\nCOMMIT;"
        with self.assertRaises(content_pages.ContentError) as caught:
            editorial_api.PymysqlContentDB(conn).script(sql)
        self.assertEqual(caught.exception.status, 409)
        self.assertEqual(caught.exception.code, "page_exists")

    def test_missing_table_is_503(self):
        conn = _Conn(error=pymysql.err.ProgrammingError(1146, "Table 'alphaeqt.content_pages' doesn't exist"))
        with self.assertRaises(content_pages.ContentError) as caught:
            editorial_api.PymysqlContentDB(conn).query("SELECT id FROM content_pages")
        self.assertEqual(caught.exception.status, 503)
        self.assertEqual(caught.exception.code, "missing_table")


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.database = None
        editorial_api.content_db_override = lambda: self.database

    def tearDown(self):
        editorial_api.content_db_override = None

    def test_editorial_routes_stay_registered_and_analyse_stays_get_only(self):
        paths = {
            (route.path, method)
            for route in editorial_api.app.routes
            if isinstance(route, APIRoute)
            for method in route.methods
        }
        required = {
            ("/health", "GET"),
            ("/topics", "GET"),
            ("/topics", "POST"),
            ("/topics/{topic_id}", "PATCH"),
            ("/topics/{topic_id}", "DELETE"),
            ("/papers", "GET"),
            ("/papers", "POST"),
            ("/questions/years", "GET"),
            ("/questions", "GET"),
            ("/questions/exists", "GET"),
            ("/questions/export-docx", "POST"),
            ("/questions/{qid}", "GET"),
            ("/questions/{qid}", "DELETE"),
            ("/questions/{qid}", "PATCH"),
            ("/questions", "POST"),
            ("/analyse/lookup", "GET"),
            ("/analyse/units/{unit}", "GET"),
            ("/analyse/gaps", "GET"),
            ("/mc-keys", "GET"),
            ("/mc-keys/lookup", "GET"),
            ("/sq-keys/lookup", "GET"),
            ("/content/pages", "POST"),
            ("/content/pages/{slug}", "GET"),
            ("/content/pages/{slug}/items", "POST"),
            ("/content/pages/{slug}/items/{sortorder}", "POST"),
            ("/content/pages/{slug}/publish", "POST"),
            ("/content/pages/{slug}/versions", "POST"),
        }
        self.assertTrue(required <= paths, sorted(required - paths))
        analyse = {method for path, method in paths if path.startswith("/analyse")}
        self.assertIn("GET", analyse)
        self.assertNotIn("POST", analyse)

        with TestClient(editorial_api.app) as client:
            health = client.get("/health")
            self.assertEqual(health.status_code, 200)
            self.assertEqual(health.json()["ok"], "1")
            for path in ("/analyse/lookup", "/analyse/gaps", "/analyse/units/1"):
                denied = client.post(path)
                self.assertEqual(denied.status_code, 405, path)
            if not editorial_api.DB_PASSWORD:
                missing = client.get("/topics")
                self.assertEqual(missing.status_code, 503)

    def test_import_get_append_edit_publish_and_version(self):
        def rows_for(sql: str):
            if sql.startswith("SELECT id FROM content_pages"):
                return []
            if sql.startswith("SELECT id FROM papers"):
                return []
            if "AS page_id" in sql:
                return [page_row()]
            if sql.startswith("SELECT i.sortorder"):
                return [
                    {
                        "sortorder": "1",
                        "content_block_id": "12",
                        "revision_id": "12",
                        "revision_no": "1",
                        "title": "Q1",
                        "kind": "question",
                        "markdown": "1. Show that the sum is 4.",
                        "question_id": "5",
                    }
                ]
            if sql.startswith("SELECT content_block_id FROM content_page_items"):
                return [{"content_block_id": "12"}]
            return []

        self.database = ScriptDB(rows_for)
        body = {
            "page": {"slug": "draft-note", "title": "Draft", "kind": "note", "status": "D"},
            "paper": {"slug": "draft-paper", "title": "Draft paper", "source_type": "S"},
            "items": [
                {
                    "kind": "stem",
                    "title": "Q1",
                    "qkind": "LQ",
                    "markdown": "1. Show that the sum is 4.",
                    "figure": {
                        "title": "fig1",
                        "markdown": "![figure-right](/imports/draft-note/fig1.svg)",
                    },
                }
            ],
        }
        with TestClient(editorial_api.app) as client:
            created = client.post("/content/pages", json=body)
            self.assertEqual(created.status_code, 201, created.text)
            self.assertEqual(created.json()["page"]["slug"], "draft-note")
            self.assertEqual(created.json()["page"]["status"], "D")
            self.assertEqual(len(self.database.scripts), 1)
            script = self.database.scripts[0]
            self.assertTrue(script.startswith("USE alphaeqt;\nSTART TRANSACTION;\n"), script[:80])
            self.assertTrue(script.strip().endswith("COMMIT;"))
            self.assertEqual(script.count("COMMIT;"), 1)
            self.assertIn("INSERT INTO questions", script)
            self.assertIn("'question'", script)
            self.assertNotIn("'stem'", script)
            self.assertIn("'LQ'", script)
            self.assertIn("'S'", script)
            self.assertIn("INSERT INTO content_blocks", script)
            self.assertEqual(script.count("INSERT INTO content_blocks"), 2)

            fetched = client.get("/content/pages/draft-note")
            self.assertEqual(fetched.status_code, 200, fetched.text)
            self.assertEqual(fetched.json()["items"][0]["question_id"], 5)
            self.assertEqual(fetched.json()["items"][0]["kind"], "question")

            appended = client.post(
                "/content/pages/draft-note/items",
                json={"kind": "text", "title": "Note", "markdown": "More."},
            )
            self.assertEqual(appended.status_code, 200, appended.text)
            self.assertIn("v.status = 'D'", self.database.scripts[-1])

            edited = client.post(
                "/content/pages/draft-note/items/1",
                json={"markdown": "1. Revised.", "title": "Q1"},
            )
            self.assertEqual(edited.status_code, 200, edited.text)
            self.assertIn("INSERT INTO content_block_revisions", self.database.scripts[-1])
            self.assertIn("'1. Revised.'", self.database.scripts[-1])

            published = client.post("/content/pages/draft-note/publish")
            self.assertEqual(published.status_code, 200, published.text)
            self.assertIn("status = 'A'", self.database.scripts[-1])

            versioned = client.post("/content/pages/draft-note/versions", json={})
            self.assertEqual(versioned.status_code, 201, versioned.text)
            self.assertIn("INSERT INTO content_page_versions", self.database.scripts[-1])
            self.assertIn("INSERT INTO content_page_items", self.database.scripts[-1])

            too_big = client.post(
                "/content/pages",
                content=b"{" + b" " * content_pages.MAX_BODY,
            )
            self.assertEqual(too_big.status_code, 413)
            self.assertEqual(too_big.json()["error"], "body_too_large")

    def test_existing_slug_does_not_write(self):
        def rows_for(sql: str):
            if "FROM content_pages" in sql:
                return [{"id": "1"}]
            return []

        self.database = ScriptDB(rows_for)
        with TestClient(editorial_api.app) as client:
            taken = client.post(
                "/content/pages",
                json={
                    "page": {"slug": "draft-note", "title": "Draft"},
                    "items": [{"kind": "text", "markdown": "Hello"}],
                },
            )
        self.assertEqual(taken.status_code, 409)
        self.assertEqual(taken.json()["error"], "page_exists")
        self.assertEqual(self.database.scripts, [])

    def test_author_source_when_the_question_and_paper_omit_it(self):
        def rows_for(sql: str):
            if "AS page_id" in sql:
                return [page_row()]
            if sql.startswith("SELECT i.sortorder"):
                return []
            return []

        self.database = ScriptDB(rows_for)
        with TestClient(editorial_api.app) as client:
            created = client.post(
                "/content/pages",
                json={
                    "page": {"slug": "draft-note", "title": "Draft"},
                    "items": [{"kind": "question", "title": "Q2", "markdown": "2. Why?"}],
                },
            )
        self.assertEqual(created.status_code, 201, created.text)
        script = self.database.scripts[0]
        self.assertIn("INSERT INTO questions", script)
        self.assertIn("'A'", script)
        self.assertNotIn("question_no", script)


if __name__ == "__main__":
    unittest.main()
