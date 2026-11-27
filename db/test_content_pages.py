#!/usr/bin/env python3
"""Content-page import, fetch, append, edit, and publish. No MySQL."""

from __future__ import annotations

import io
import json
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import content_pages as pages
import editorial_api as api


def statements(script: str) -> list[str]:
    if not script.startswith("USE alphaeqt;\nSTART TRANSACTION;\n"):
        raise AssertionError(script[:80])
    body = script.split("START TRANSACTION;\n", 1)[1]
    body = body.rsplit("\nCOMMIT;", 1)[0]
    return [part for part in body.split(";\n") if part]


def inserts(script: str) -> list[str]:
    names = []
    for statement in statements(script):
        if statement.startswith("INSERT INTO "):
            names.append(statement.split()[2])
    return names


class ScriptDB:
    def __init__(self, rows_for=None, script_row=None):
        self.calls: list[str] = []
        self.scripts: list[str] = []
        self.rows_for = rows_for or (lambda _sql: [])
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


def page_row(**overrides) -> dict:
    row = {
        "page_id": "10",
        "slug": "s6-alg-notes",
        "title": "S6 algebra notes",
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


def item_row(**overrides) -> dict:
    row = {
        "sortorder": "3",
        "content_block_id": "12",
        "revision_id": "12",
        "revision_no": "1",
        "title": "Q13",
        "kind": "question",
        "markdown": "13. Which is larger?",
        "question_id": "5",
    }
    row.update(overrides)
    return row


def call_app(app, path: str, method: str = "GET", body=None):
    captured: dict = {}

    def start(status, headers):
        captured["status"] = status
        captured["headers"] = headers

    raw = b""
    if body is not None:
        raw = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
    route, query = path, ""
    if "?" in path:
        route, query = path.split("?", 1)
    payload_bytes = b"".join(
        app(
            {
                "REQUEST_METHOD": method,
                "PATH_INFO": route,
                "QUERY_STRING": query,
                "CONTENT_LENGTH": str(len(raw)),
                "wsgi.input": io.BytesIO(raw),
            },
            start,
        )
    )
    payload = json.loads(payload_bytes.decode("utf-8")) if payload_bytes else {}
    return captured["status"], payload, captured["headers"]


class SqlTests(unittest.TestCase):
    def test_import_writes_paper_blocks_questions_then_page(self):
        page = pages.parse_import(pages.EXAMPLE_IMPORT)
        page.items[-1].resolved_revision_id = 99
        script = pages.render_import_script(page)
        names = inserts(script)
        self.assertEqual(names[0], "papers")
        self.assertLess(names.index("papers"), names.index("content_blocks"))
        self.assertLess(names.index("content_blocks"), names.index("questions"))
        block_at = [index for index, name in enumerate(names) if name == "content_blocks"]
        revision_at = [index for index, name in enumerate(names) if name == "content_block_revisions"]
        self.assertEqual(len(block_at), 4)
        self.assertEqual(len(revision_at), 4)
        self.assertTrue(all(block < revision_at[offset] for offset, block in enumerate(block_at)))
        self.assertLess(names.index("questions"), names.index("content_pages"))
        self.assertLess(names.index("content_pages"), names.index("content_page_versions"))
        self.assertLess(names.index("content_page_versions"), names.index("content_page_items"))
        page_insert = next(part for part in statements(script) if part.startswith("INSERT INTO content_pages"))
        self.assertIn("NULL", page_insert)
        update_at = next(
            index for index, part in enumerate(statements(script)) if part.startswith("UPDATE content_pages")
        )
        items_at = next(
            index for index, part in enumerate(statements(script)) if part.startswith("INSERT INTO content_page_items")
        )
        self.assertLess(items_at, update_at)
        self.assertEqual(names.count("questions"), 1)
        question_sql = next(part for part in statements(script) if part.startswith("INSERT INTO questions"))
        self.assertIn("'P'", question_sql)
        self.assertNotIn("'S'", question_sql)
        self.assertNotIn("source_type", next(part for part in statements(script) if "INSERT INTO papers" in part))
        self.assertNotIn("INSERT INTO content_blocks", script.split("INSERT INTO questions", 1)[1])
        for part in statements(script):
            if part.startswith("INSERT INTO content_blocks"):
                self.assertNotIn("1234", part)
        reused = [
            part for part in statements(script)
            if part.startswith("INSERT INTO content_page_items") and "1234" in part
        ]
        self.assertEqual(len(reused), 1)
        self.assertIn("1234, 99", reused[0])
        self.assertIn("'question'", script)
        self.assertIn("'figure'", script)
        self.assertIn("'text'", script)
        self.assertNotIn("'answer'", script)
        self.assertNotIn("'solution'", script)
        self.assertEqual(script.count("START TRANSACTION"), 1)
        self.assertTrue(script.strip().endswith("COMMIT;"))

    def test_source_type_falls_through_paper_then_author(self):
        inherited = {
            "page": {"slug": "notes", "title": "Notes"},
            "paper": {"slug": "paper-s", "title": "School", "source_type": "S"},
            "items": [{"kind": "question", "title": "Q1", "markdown": "1. Stem"}],
        }
        page = pages.parse_import(inherited)
        question = next(part for part in statements(pages.render_import_script(page)) if part.startswith("INSERT INTO questions"))
        self.assertIn("'S'", question)
        author = {
            "page": {"slug": "notes", "title": "Notes"},
            "items": [{"kind": "question", "markdown": "Stem", "qkind": "sq"}],
        }
        page = pages.parse_import(author)
        question = next(part for part in statements(pages.render_import_script(page)) if part.startswith("INSERT INTO questions"))
        self.assertIn("'A'", question)
        self.assertIn("'SQ'", question)
        self.assertNotIn("INSERT INTO papers", pages.render_import_script(page))

    def test_existing_paper_is_not_updated(self):
        page = pages.parse_import(
            {
                "page": {"slug": "notes", "title": "Notes"},
                "paper": {"slug": "paper-s", "title": "School", "source_type": "S"},
                "items": [{"kind": "text", "markdown": "Hi"}],
            }
        )
        page.paper.existing_id = 7
        script = pages.render_import_script(page)
        self.assertNotIn("INSERT INTO papers", script)
        self.assertIn("SET @paper_id = 7", script)
        self.assertNotIn("UPDATE papers", script)

    def test_edit_inserts_a_revision_and_guards_the_draft(self):
        script = pages.render_edit_script("notes", 2, "new stem", "Q2", True)
        self.assertTrue(any(part.startswith("INSERT INTO content_block_revisions") for part in statements(script)))
        self.assertIn("INSERT INTO content_block_revisions", script)
        self.assertNotIn("UPDATE content_block_revisions", script)
        self.assertIn("UPDATE content_blocks", script)
        self.assertIn("b.markdown = 'new stem'", script)
        self.assertIn("b.title = 'Q2'", script)
        self.assertIn("SET i.revision_id = @rev", script)
        self.assertIn("v.status = 'D'", script)
        self.assertNotIn("status = 'A'", script)
        self.assertEqual(script.count("UPDATE content_page_items"), 1)

    def test_publish_sets_version_and_page_only(self):
        script = pages.render_publish_script("notes")
        self.assertIn("p.status = 'A'", script)
        self.assertIn("v.status = 'A'", script)
        self.assertNotIn("content_page_items", script)
        self.assertNotIn("revision_id", script)
        self.assertNotIn("content_blocks", script)
        self.assertNotIn("questions", script)

    def test_new_version_does_not_rewrite_published_items(self):
        page = pages.parse_version({"note": "rebuild"}, "notes")
        script = pages.render_version_script(page, clone=True)
        self.assertIn("INSERT INTO content_page_versions", script)
        self.assertIn("status = 'D'", script)
        self.assertNotIn("UPDATE content_page_items", script)
        self.assertNotIn("UPDATE content_page_versions", script)
        self.assertIn("p.current_version_id = i.version_id", script)
        fresh = pages.parse_version(
            {"items": [{"kind": "text", "markdown": "replacement"}]},
            "notes",
        )
        replacement = pages.render_version_script(fresh, clone=False)
        self.assertIn("INSERT INTO content_blocks", replacement)
        self.assertNotIn("UPDATE content_page_items", replacement)
        self.assertNotIn("UPDATE content_page_versions", replacement)

    def test_fetch_sql_uses_pinned_revision_markdown(self):
        sql = pages._items_sql(4)
        self.assertIn("r.markdown AS markdown", sql)
        self.assertNotIn("b.markdown", sql)
        self.assertIn("q.id AS question_id", sql)
        self.assertIn("stem_block_id", sql)
        self.assertIn("ORDER BY i.sortorder", sql)

    def test_quote_in_markdown_stays_inside_the_literal(self):
        page = pages.parse_import(
            {
                "page": {"slug": "notes", "title": "Notes"},
                "items": [{"kind": "text", "markdown": "'; DROP TABLE content_pages; --"}],
            }
        )
        script = pages.render_import_script(page)
        self.assertIn("''; DROP TABLE content_pages; --'", script)
        self.assertEqual(script.count("COMMIT;"), 1)


class BehaviorTests(unittest.TestCase):
    def test_example_import_rejects_an_existing_slug_and_fetches_question_id(self):
        def rows_for(sql: str):
            if sql.startswith("SELECT id FROM content_pages"):
                return []
            if sql.startswith("SELECT id FROM papers"):
                return []
            if "FROM content_blocks WHERE id = 1234" in sql:
                return [{"id": "1234"}]
            if "FROM content_block_revisions" in sql and "1234" in sql:
                return [{"id": "99"}]
            if "AS page_id" in sql:
                return [page_row()]
            if sql.startswith("SELECT i.sortorder"):
                return [item_row()]
            return []

        db = ScriptDB(rows_for)
        body = pages.import_document(db, pages.EXAMPLE_IMPORT)
        self.assertEqual(len(db.scripts), 1)
        self.assertTrue(db.scripts[0].startswith("USE alphaeqt;"))
        self.assertEqual(body["page"]["status"], "D")
        self.assertEqual(body["items"][0]["question_id"], 5)
        self.assertEqual(body["items"][0]["markdown"], "13. Which is larger?")
        self.assertEqual(body["paper_id"], 30)
        taken = ScriptDB(lambda sql: [{"id": "1"}] if "content_pages" in sql else [])
        with self.assertRaises(pages.ContentError) as caught:
            pages.import_document(taken, pages.EXAMPLE_IMPORT)
        self.assertEqual(caught.exception.code, "page_exists")
        self.assertEqual(taken.scripts, [])

    def test_append_and_edit_refuse_a_published_version(self):
        def rows_for(sql: str):
            if "AS page_id" in sql:
                return [page_row(status="A", version_status="A")]
            return []

        db = ScriptDB(rows_for)
        with self.assertRaises(pages.ContentError) as caught:
            pages.append_item(db, "s6-alg-notes", {"kind": "text", "markdown": "more"})
        self.assertEqual(caught.exception.code, "published_version")
        with self.assertRaises(pages.ContentError) as edit_caught:
            pages.edit_item(db, "s6-alg-notes", 1, {"markdown": "changed"})
        self.assertEqual(edit_caught.exception.code, "published_version")
        self.assertEqual(db.scripts, [])
        published = pages.publish_page(db, "s6-alg-notes")
        self.assertEqual(published["page"]["status"], "A")
        self.assertEqual(db.scripts, [])

    def test_append_question_on_a_draft_pins_a_new_revision(self):
        def rows_for(sql: str):
            if "AS page_id" in sql:
                return [page_row()]
            if sql.startswith("SELECT i.sortorder"):
                return [item_row(sortorder="1", kind="question")]
            return []

        db = ScriptDB(rows_for, {"version_id": "20", "item_count": "2"})
        pages.append_item(
            db,
            "s6-alg-notes",
            {
                "kind": "question",
                "title": "Q2",
                "qkind": "LQ",
                "markdown": "2. Show that ...",
                "figure": {"title": "fig2", "markdown": "![figure-right](/imports/s6-alg-notes/fig2.svg)"},
            },
        )
        script = db.scripts[0]
        self.assertIn("v.status = 'D'", script)
        self.assertIn("'LQ'", script)
        self.assertIn("'A'", script)
        self.assertEqual(inserts(script).count("content_blocks"), 2)
        self.assertEqual(inserts(script).count("questions"), 1)

    def test_validation(self):
        with self.assertRaises(pages.ContentError) as status:
            pages.parse_import(
                {"page": {"slug": "notes", "title": "Notes", "status": "A"}, "items": [{"kind": "text", "markdown": "x"}]}
            )
        self.assertEqual(status.exception.code, "use_publish")
        with self.assertRaises(pages.ContentError) as kind:
            pages.parse_import(
                {"page": {"slug": "notes", "title": "Notes"}, "items": [{"kind": "answer", "markdown": "4"}]}
            )
        self.assertEqual(kind.exception.code, "not_on_page")
        with self.assertRaises(pages.ContentError) as source:
            pages.parse_import(
                {
                    "page": {"slug": "notes", "title": "Notes"},
                    "items": [{"kind": "question", "markdown": "Stem", "source_type": "hoksi"}],
                }
            )
        self.assertEqual(source.exception.code, "bad_source_type")
        self.assertEqual(pages.lit("O'Brien"), "'O''Brien'")
        self.assertEqual(pages.lit("a\\b"), "'a\\\\b'")
        stem = pages.parse_import(
            {"page": {"slug": "notes", "title": "Notes"}, "items": [{"kind": "stem", "markdown": "Stem"}]}
        )
        self.assertEqual(stem.items[0].kind, "question")


class HttpTests(unittest.TestCase):
    def test_analyse_post_stays_rejected_and_content_import_is_served(self):
        def rows_for(sql: str):
            if sql.startswith("SELECT id FROM content_pages"):
                return []
            if "AS page_id" in sql:
                return [page_row(slug="draft-note", title="Draft")]
            if sql.startswith("SELECT i.sortorder"):
                return []
            if "FROM `analyse_sq`" in sql:
                return []
            return []

        db = ScriptDB(rows_for)
        app = api.build_app(api.assumed_schema(), db)
        denied, body, _headers = call_app(app, "/analyse/lookup", method="POST", body={})
        self.assertTrue(denied.startswith("405"), denied)
        self.assertEqual(body["message"], "GET only")
        self.assertEqual(db.scripts, [])
        created, payload, headers = call_app(
            app,
            "/content/pages",
            method="POST",
            body={
                "page": {"slug": "draft-note", "title": "Draft"},
                "items": [{"kind": "text", "markdown": "Hello"}],
            },
        )
        self.assertTrue(created.startswith("201"), created)
        self.assertEqual(payload["page"]["slug"], "draft-note")
        self.assertEqual(payload["page"]["status"], "D")
        self.assertEqual(len(db.scripts), 1)
        self.assertIn(("Access-Control-Allow-Origin", "*"), headers)
        fetched, page, _headers = call_app(app, "/content/pages/draft-note")
        self.assertTrue(fetched.startswith("200"), fetched)
        self.assertEqual(page["page"]["slug"], "draft-note")

    def test_schema_matches_the_live_content_page_design(self):
        text = Path(__file__).resolve().parent.joinpath("content_pages_schema.sql").read_text(encoding="utf-8")
        self.assertIn("USE alphaeqt;", text)
        self.assertIn("utf8mb4_general_ci", text)
        block = text.split("CREATE TABLE IF NOT EXISTS content_blocks", 1)[1].split("ENGINE=InnoDB", 1)[0]
        self.assertNotIn("slug", block.lower())
        self.assertLess(block.index("kind"), block.index("title VARCHAR(255) NULL"))
        self.assertIn("content_block_revisions", text)
        self.assertIn("UNIQUE KEY uq_content_block_revisions_block_no (content_block_id, revision_no)", text)
        self.assertIn("ON DELETE CASCADE", text)
        self.assertLess(
            text.index("CREATE TABLE IF NOT EXISTS content_page_versions"),
            text.index("fk_content_pages_current_version"),
        )
        self.assertIn(
            "FOREIGN KEY (current_version_id) REFERENCES content_page_versions (id) ON DELETE SET NULL",
            text,
        )
        self.assertIn("ON DELETE RESTRICT", text)
        questions = text.split("CREATE TABLE IF NOT EXISTS questions", 1)[1].split("ENGINE=InnoDB", 1)[0]
        self.assertNotIn("question_no", questions.lower())
        self.assertIn("A=author", questions)
        self.assertIn("COMMENT 'note|web|app'", text)
        self.assertIn("COMMENT 'D=draft A=published'", text)
        for line in text.splitlines():
            word = line.strip().split(" ", 1)[0].upper() if line.strip() else ""
            self.assertNotIn(word, {"INSERT", "UPDATE", "DELETE"}, line)


if __name__ == "__main__":
    unittest.main()
