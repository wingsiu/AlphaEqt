#!/usr/bin/env python3
"""Draft content pages on the editorial API.

A content page is an ordered list of atoms. Each atom is a ``content_blocks``
row pinned to a ``content_block_revisions`` row. A question atom is also a
``questions`` row whose ``stem_block_id`` points at the block (not a revision).
Answers and solutions are not page items.

The page stays draft (``D``) until ``POST /content/pages/{slug}/publish``.
Import refuses a slug that already exists. A later update inserts a new
``content_page_versions`` row and leaves any published version's items alone.

Writes run as one transaction and start with ``USE alphaeqt`` so
``binlog-do-db`` records them. Figures are markdown links, not MySQL blobs.

Example import::

    curl -s -X POST http://127.0.0.1:8765/content/pages \\
      -H 'Content-Type: application/json' \\
      -d @- <<'JSON'
    {
      "page": {"slug": "s6-alg-notes", "title": "S6 algebra notes", "kind": "note", "status": "D"},
      "paper": {"slug": "s6-alg-2024", "title": "S6 algebra 2024", "source_type": "S"},
      "items": [
        {"kind": "title", "title": "Section A", "markdown": "## Section A"},
        {"kind": "text", "title": "Instructions", "markdown": "Answer all questions."},
        {
          "kind": "question",
          "qkind": "MC",
          "title": "Q13",
          "marks": 3,
          "source_type": "P",
          "markdown": "13. Which is larger?\\n\\n- A. 2\\n- B. 3",
          "figure": {"title": "fig13", "markdown": "![figure-right](/imports/s6-alg-notes/fig13.svg)"}
        },
        {"content_block_id": 1234}
      ]
    }
    JSON
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from typing import Protocol
from urllib.parse import unquote

SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$")
PATH_RE = re.compile(
    r"^/content/pages"
    r"(?:/(?P<slug>[A-Za-z0-9][A-Za-z0-9_-]{0,63})"
    r"(?:/(?P<action>items|publish|versions)"
    r"(?:/(?P<sortorder>[1-9][0-9]{0,8}))?"
    r")?)?$"
)

PAGE_KINDS = {"note": "note", "web": "web", "app": "app"}
# Stored kind for a new atom. stem is accepted as question.
ATOM_KINDS = {
    "question": "question",
    "stem": "question",
    "text": "text",
    "figure": "figure",
    "title": "title",
    "formula": "formula",
    "topic": "topic",
    "theorem": "theorem",
}
NOT_ON_PAGE = {"answer", "solution", "hint"}
SOURCE_TYPES = {"A", "S", "P"}
QKIND_ALIASES = {
    "mc": "MC",
    "multiple": "MC",
    "multiple-choice": "MC",
    "multiple_choice": "MC",
    "sq": "SQ",
    "structured": "SQ",
    "short": "SQ",
    "lq": "LQ",
    "long": "LQ",
}
MAX_ITEMS = 400
MAX_MARKDOWN = 1_000_000
MAX_BODY = 2_000_000

EXAMPLE_IMPORT = {
    "page": {
        "slug": "s6-alg-notes",
        "title": "S6 algebra notes",
        "kind": "note",
        "status": "D",
    },
    "paper": {
        "slug": "s6-alg-2024",
        "title": "S6 algebra 2024",
        "source_type": "S",
    },
    "items": [
        {"kind": "title", "title": "Section A", "markdown": "## Section A"},
        {"kind": "text", "title": "Instructions", "markdown": "Answer all questions."},
        {
            "kind": "question",
            "qkind": "MC",
            "title": "Q13",
            "marks": 3,
            "source_type": "P",
            "markdown": "13. Which is larger?\n\n- A. 2\n- B. 3",
            "figure": {
                "title": "fig13",
                "markdown": "![figure-right](/imports/s6-alg-notes/fig13.svg)",
            },
        },
        {"content_block_id": 1234},
    ],
}


class ContentError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message

    def payload(self) -> dict:
        return {"error": self.code, "message": self.message}


class Database(Protocol):
    def query(self, sql: str) -> list[dict]:
        ...

    def script(self, sql: str) -> list[dict]:
        ...


def lit(value: object) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool) or not isinstance(value, (int, str)):
        raise ContentError(500, "bad_literal", "refusing a non-text SQL value")
    if isinstance(value, int):
        return str(value)
    text = value.replace("\\", "\\\\").replace("'", "''").replace("\x00", "")
    return f"'{text}'"


def transaction(statements: list[str]) -> str:
    body = ";\n".join(statements)
    return f"USE alphaeqt;\nSTART TRANSACTION;\n{body};\nCOMMIT;\n"


def _int(value: object) -> int | None:
    if value is None or value == "":
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    text = str(value).strip()
    if not text or text[0] == "+":
        return None
    try:
        return int(text)
    except ValueError:
        return None


def _require_object(value: object, label: str) -> dict:
    if not isinstance(value, dict):
        raise ContentError(400, "bad_json", f"{label} must be a JSON object")
    return value


def _optional_text(value: object, label: str, limit: int) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        raise ContentError(400, "bad_item", f"{label} must be a string")
    text = value.strip()
    if len(text) > limit:
        raise ContentError(400, "bad_item", f"{label} is longer than {limit} characters")
    return text or None


def _markdown(value: object, label: str) -> str:
    if not isinstance(value, str):
        raise ContentError(400, "bad_item", f"{label} must be a string")
    if len(value) > MAX_MARKDOWN:
        raise ContentError(400, "bad_item", f"{label} is longer than {MAX_MARKDOWN} characters")
    if "\x00" in value:
        raise ContentError(400, "bad_item", f"{label} contains a NUL")
    return value


def _slug(value: object, label: str) -> str:
    if not isinstance(value, str) or not SLUG_RE.fullmatch(value.strip()):
        raise ContentError(
            400,
            "bad_slug",
            f"{label} must be 1-64 characters of letters, digits, hyphen, or underscore",
        )
    return value.strip()


def _source_type(value: object) -> str:
    if not isinstance(value, str):
        raise ContentError(400, "bad_source_type", "source_type must be A, S, or P")
    token = value.strip().upper()
    if token not in SOURCE_TYPES:
        raise ContentError(
            400,
            "bad_source_type",
            "source_type must be A (author), S (school), or P (publisher)",
        )
    return token


def _qkind(value: object) -> str:
    if not isinstance(value, str):
        raise ContentError(400, "bad_qkind", "qkind must be MC, SQ, or LQ")
    token = QKIND_ALIASES.get(value.strip().lower())
    if token is None:
        raise ContentError(400, "bad_qkind", "qkind must be MC, SQ, or LQ")
    return token


def _marks(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        raise ContentError(400, "bad_item", "marks must be an integer")
    if value < 0 or value > 10000:
        raise ContentError(400, "bad_item", "marks is out of range")
    return value


def _topic_id(value: object) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ContentError(400, "bad_item", "topic_id must be a positive integer")
    return value


def _level(value: object) -> str:
    if isinstance(value, bool):
        raise ContentError(400, "bad_item", "level must be a string or integer")
    if isinstance(value, int):
        return str(value)
    if not isinstance(value, str):
        raise ContentError(400, "bad_item", "level must be a string or integer")
    text = value.strip()
    if not text or len(text) > 32:
        raise ContentError(400, "bad_item", "level must be 1-32 characters")
    return text


def _positive_id(value: object, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise ContentError(400, "bad_item", f"{label} must be a positive integer")
    return value


@dataclass
class FigureIn:
    title: str | None
    markdown: str


@dataclass
class ItemIn:
    reuse_block_id: int | None = None
    reuse_revision_id: int | None = None
    resolved_revision_id: int | None = None
    kind: str | None = None
    title: str | None = None
    markdown: str | None = None
    figure: FigureIn | None = None
    qkind: str | None = None
    source_type: str | None = None
    marks: int | None = None
    level: str | None = None
    topic_id: int | None = None

    @property
    def is_question(self) -> bool:
        return self.kind == "question"


@dataclass
class PaperIn:
    slug: str
    title: str
    source_type: str | None = None
    source_pdf: str | None = None
    dpi: int | None = None
    existing_id: int | None = None


@dataclass
class PageIn:
    slug: str
    title: str
    kind: str | None
    paper: PaperIn | None = None
    # None means "clone the current version" on a version update.
    items: list[ItemIn] | None = None
    note: str | None = None


@dataclass
class Atom:
    """One page item in list order, after a question's figure is expanded."""

    item: ItemIn | None
    kind: str | None
    title: str | None
    markdown: str | None
    block_id: int | None = None
    revision_id: int | None = None
    block_var: str | None = None
    revision_var: str | None = None


def _parse_figure(value: object) -> FigureIn:
    raw = _require_object(value, "figure")
    return FigureIn(
        title=_optional_text(raw.get("title"), "figure title", 255),
        markdown=_markdown(raw.get("markdown"), "figure markdown"),
    )


def _parse_item(value: object, index: int) -> ItemIn:
    raw = _require_object(value, f"items[{index}]")
    label = f"items[{index}]"
    if "content_block_id" in raw:
        if "kind" in raw or "markdown" in raw or "figure" in raw:
            raise ContentError(
                400,
                "bad_item",
                f"{label} reuses content_block_id and cannot also create a block",
            )
        revision = None
        if "revision_id" in raw and raw.get("revision_id") is not None:
            revision = _positive_id(raw.get("revision_id"), f"{label}.revision_id")
        return ItemIn(
            reuse_block_id=_positive_id(raw.get("content_block_id"), f"{label}.content_block_id"),
            reuse_revision_id=revision,
        )
    kind_raw = raw.get("kind")
    if not isinstance(kind_raw, str):
        raise ContentError(400, "bad_kind", f"{label}.kind is required")
    folded = kind_raw.strip().lower()
    if folded in NOT_ON_PAGE:
        raise ContentError(
            400,
            "not_on_page",
            f"{label} kind {folded} belongs on the question, not on the page",
        )
    kind = ATOM_KINDS.get(folded)
    if kind is None:
        raise ContentError(
            400,
            "bad_kind",
            f"{label}.kind must be question, text, figure, title, formula, topic, or theorem",
        )
    figure = _parse_figure(raw["figure"]) if "figure" in raw and raw["figure"] is not None else None
    item = ItemIn(
        kind=kind,
        title=_optional_text(raw.get("title"), f"{label}.title", 255),
        markdown=_markdown(raw.get("markdown"), f"{label}.markdown"),
        figure=figure,
    )
    if kind == "question":
        item.qkind = _qkind(raw["qkind"]) if raw.get("qkind") not in (None, "") else "MC"
        if raw.get("source_type") not in (None, ""):
            item.source_type = _source_type(raw.get("source_type"))
        if raw.get("marks") is not None:
            item.marks = _marks(raw.get("marks"))
        if raw.get("level") is not None:
            item.level = _level(raw.get("level"))
        if raw.get("topic_id") is not None:
            item.topic_id = _topic_id(raw.get("topic_id"))
    return item


def _parse_paper(value: object) -> PaperIn:
    raw = _require_object(value, "paper")
    dpi = None
    if raw.get("dpi") is not None:
        if isinstance(raw.get("dpi"), bool) or not isinstance(raw.get("dpi"), int) or raw["dpi"] < 1:
            raise ContentError(400, "bad_item", "paper.dpi must be a positive integer")
        dpi = raw["dpi"]
    source = None
    if raw.get("source_type") not in (None, ""):
        source = _source_type(raw.get("source_type"))
    return PaperIn(
        slug=_slug(raw.get("slug"), "paper.slug"),
        title=_optional_text(raw.get("title"), "paper.title", 255) or "",
        source_type=source,
        source_pdf=_optional_text(raw.get("source_pdf"), "paper.source_pdf", 255),
        dpi=dpi,
    )


def _parse_page(value: object, *, require_title: bool, default_kind: str | None) -> tuple[str, str, str | None]:
    raw = _require_object(value, "page")
    if raw.get("status") not in (None, "", "D", "d"):
        raise ContentError(
            400,
            "use_publish",
            "new pages and versions stay draft; publish with POST /content/pages/{slug}/publish",
        )
    kind_raw = raw.get("kind")
    if kind_raw in (None, ""):
        kind = default_kind
    elif isinstance(kind_raw, str) and kind_raw.strip().lower() in PAGE_KINDS:
        kind = PAGE_KINDS[kind_raw.strip().lower()]
    else:
        raise ContentError(400, "bad_kind", "page.kind must be note, web, or app")
    title = _optional_text(raw.get("title"), "page.title", 255)
    if require_title and not title:
        raise ContentError(400, "bad_item", "page.title is required")
    slug = raw.get("slug")
    return (_slug(slug, "page.slug") if slug not in (None, "") else ""), title or "", kind


def parse_import(payload: dict) -> PageIn:
    page_slug, title, kind = _parse_page(payload.get("page"), require_title=True, default_kind="note")
    kind = kind or "note"
    if not page_slug:
        raise ContentError(400, "bad_slug", "page.slug is required")
    items_raw = payload.get("items")
    if not isinstance(items_raw, list) or not items_raw:
        raise ContentError(400, "bad_item", "items must be a non-empty list")
    if len(items_raw) > MAX_ITEMS:
        raise ContentError(400, "bad_item", f"items is limited to {MAX_ITEMS}")
    paper = _parse_paper(payload["paper"]) if payload.get("paper") is not None else None
    if paper is not None and not paper.title:
        raise ContentError(400, "bad_item", "paper.title is required")
    note = _optional_text(payload.get("note"), "note", 255)
    return PageIn(
        slug=page_slug,
        title=title,
        kind=kind,
        paper=paper,
        items=[_parse_item(item, index) for index, item in enumerate(items_raw)],
        note=note,
    )


def parse_one_item(payload: dict) -> ItemIn:
    if "items" in payload:
        items = payload.get("items")
        if not isinstance(items, list) or len(items) != 1:
            raise ContentError(400, "one_item", "append one item at a time")
        return _parse_item(items[0], 0)
    if "item" in payload:
        return _parse_item(payload.get("item"), 0)
    return _parse_item(payload, 0)


def parse_version(payload: dict, slug: str) -> PageIn:
    """A new draft version. Omitted items clone the current version."""
    page = payload.get("page")
    title = ""
    kind = None
    if page is not None:
        page_slug, title, kind = _parse_page(page, require_title=False, default_kind=None)
        if page_slug and page_slug != slug:
            raise ContentError(400, "bad_slug", "page.slug does not match the URL")
    if "items" not in payload or payload.get("items") is None:
        items: list[ItemIn] | None = None
    else:
        items_raw = payload.get("items")
        if not isinstance(items_raw, list):
            raise ContentError(400, "bad_item", "items must be a list")
        if len(items_raw) > MAX_ITEMS:
            raise ContentError(400, "bad_item", f"items is limited to {MAX_ITEMS}")
        items = [_parse_item(item, index) for index, item in enumerate(items_raw)]
    paper = _parse_paper(payload["paper"]) if payload.get("paper") is not None else None
    note = _optional_text(payload.get("note"), "note", 255)
    return PageIn(slug=slug, title=title, kind=kind, paper=paper, items=items, note=note)


def _expand(items: list[ItemIn], paper: PaperIn | None) -> list[Atom]:
    atoms: list[Atom] = []
    for item in items:
        if item.reuse_block_id is not None:
            atoms.append(
                Atom(
                    item=None,
                    kind=None,
                    title=None,
                    markdown=None,
                    block_id=item.reuse_block_id,
                    revision_id=item.resolved_revision_id,
                )
            )
            continue
        atoms.append(
            Atom(item=item, kind=item.kind, title=item.title, markdown=item.markdown)
        )
        if item.figure is not None:
            atoms.append(
                Atom(
                    item=None,
                    kind="figure",
                    title=item.figure.title,
                    markdown=item.figure.markdown,
                )
            )
    default_source = paper.source_type if paper is not None else None
    for atom in atoms:
        if atom.item is not None and atom.item.is_question and atom.item.source_type is None:
            atom.item.source_type = default_source or "A"
    return atoms


def _assign_vars(atoms: list[Atom]) -> None:
    number = 0
    for atom in atoms:
        if atom.block_id is not None:
            continue
        atom.block_var = f"@b{number}"
        atom.revision_var = f"@r{number}"
        number += 1


def _insert_block(statements: list[str], atom: Atom, guard: str | None) -> None:
    assert atom.block_var and atom.revision_var and atom.kind is not None and atom.markdown is not None
    values = ", ".join(
        [lit(atom.kind), lit(atom.title), lit(atom.markdown), "'D'"]
    )
    if guard is None:
        statements.append(
            "INSERT INTO content_blocks (kind, title, markdown, status) "
            f"VALUES ({values})"
        )
    else:
        statements.append(
            "INSERT INTO content_blocks (kind, title, markdown, status) "
            f"SELECT {values} FROM DUAL WHERE {guard}"
        )
    inserted = f"{atom.block_var}_ok"
    statements.append(f"SET {inserted} = ROW_COUNT()")
    statements.append(f"SET {atom.block_var} = IF({inserted} = 1, LAST_INSERT_ID(), NULL)")
    statements.append(
        "INSERT INTO content_block_revisions (content_block_id, revision_no, markdown) "
        f"SELECT {atom.block_var}, 1, {lit(atom.markdown)} FROM DUAL "
        f"WHERE {atom.block_var} IS NOT NULL"
    )
    statements.append(f"SET {atom.revision_var}_ok = ROW_COUNT()")
    statements.append(
        f"SET {atom.revision_var} = IF({atom.revision_var}_ok = 1, LAST_INSERT_ID(), NULL)"
    )


def _insert_questions(statements: list[str], atoms: list[Atom]) -> None:
    for atom in atoms:
        item = atom.item
        if item is None or not item.is_question:
            continue
        assert atom.block_var is not None
        columns = ["paper_id", "stem_block_id", "source_type", "qkind"]
        values = ["@paper_id", atom.block_var, lit(item.source_type or "A"), lit(item.qkind or "MC")]
        if item.marks is not None:
            columns.append("marks")
            values.append(lit(item.marks))
        if item.level is not None:
            columns.append("level")
            values.append(lit(item.level))
        if item.topic_id is not None:
            columns.append("topic_id")
            values.append(lit(item.topic_id))
        col_sql = ", ".join(f"`{name}`" for name in columns)
        val_sql = ", ".join(values)
        statements.append(
            f"INSERT INTO questions ({col_sql}) "
            f"SELECT {val_sql} FROM DUAL WHERE {atom.block_var} IS NOT NULL"
        )


def _paper_statements(statements: list[str], paper: PaperIn | None, guard: str | None = None) -> None:
    if paper is None:
        statements.append("SET @paper_id = NULL")
        return
    if paper.existing_id is not None:
        if guard is None:
            statements.append(f"SET @paper_id = {lit(paper.existing_id)}")
        else:
            statements.append(f"SET @paper_id = IF({guard}, {lit(paper.existing_id)}, NULL)")
        return
    values = ", ".join(
        [lit(paper.slug), lit(paper.title), lit(paper.source_pdf), lit(paper.dpi), "'D'"]
    )
    if guard is None:
        statements.append(
            "INSERT INTO papers (slug, title, source_pdf, dpi, status) "
            f"VALUES ({values})"
        )
        statements.append("SET @paper_id = LAST_INSERT_ID()")
        return
    statements.append(
        "INSERT INTO papers (slug, title, source_pdf, dpi, status) "
        f"SELECT {values} FROM DUAL WHERE {guard}"
    )
    statements.append("SET @paper_ok = ROW_COUNT()")
    statements.append("SET @paper_id = IF(@paper_ok = 1, LAST_INSERT_ID(), NULL)")


def _item_values(atom: Atom) -> tuple[str, str]:
    if atom.block_id is not None:
        if atom.revision_id is None:
            raise ContentError(500, "missing_revision", "reused block has no revision")
        return lit(atom.block_id), lit(atom.revision_id)
    assert atom.block_var and atom.revision_var
    return atom.block_var, atom.revision_var


def _insert_items(
    statements: list[str],
    atoms: list[Atom],
    *,
    version_sql: str,
    sort_start: int | None,
    guard: str | None,
    count: bool,
) -> None:
    if count:
        statements.append("SET @item_count = 0")
    if sort_start is None:
        statements.append(
            "SET @sort = (SELECT COALESCE(MAX(sortorder), 0) FROM content_page_items "
            f"WHERE version_id = {version_sql})"
        )
    else:
        statements.append(f"SET @sort = {sort_start}")
    for atom in atoms:
        block_sql, revision_sql = _item_values(atom)
        statements.append("SET @sort = @sort + 1")
        where = [f"{version_sql} IS NOT NULL", f"{revision_sql} IS NOT NULL"]
        if guard is not None:
            where.append(guard)
        statements.append(
            "INSERT INTO content_page_items "
            "(version_id, sortorder, content_block_id, revision_id) "
            f"SELECT {version_sql}, @sort, {block_sql}, {revision_sql} "
            f"FROM DUAL WHERE {' AND '.join(where)}"
        )
        if count:
            statements.append("SET @item_count = @item_count + ROW_COUNT()")


def render_import_script(page: PageIn) -> str:
    atoms = _expand(page.items, page.paper)
    _assign_vars(atoms)
    statements: list[str] = []
    _paper_statements(statements, page.paper)
    for atom in atoms:
        if atom.block_var is not None:
            _insert_block(statements, atom, None)
    _insert_questions(statements, atoms)
    statements.append(
        "INSERT INTO content_pages (slug, title, kind, status, current_version_id) "
        f"VALUES ({lit(page.slug)}, {lit(page.title)}, {lit(page.kind)}, 'D', NULL)"
    )
    statements.append("SET @page_id = LAST_INSERT_ID()")
    statements.append(
        "INSERT INTO content_page_versions (page_id, version_no, note, status) "
        f"VALUES (@page_id, 1, {lit(page.note)}, 'D')"
    )
    statements.append("SET @version_id = LAST_INSERT_ID()")
    if atoms:
        _insert_items(
            statements,
            atoms,
            version_sql="@version_id",
            sort_start=0,
            guard=None,
            count=False,
        )
    statements.append(
        "UPDATE content_pages SET current_version_id = @version_id WHERE id = @page_id"
    )
    statements.append(
        "SELECT @page_id AS page_id, @version_id AS version_id, @paper_id AS paper_id"
    )
    return transaction(statements)


def render_append_script(slug: str, item: ItemIn, paper: PaperIn | None) -> str:
    atoms = _expand([item], paper)
    _assign_vars(atoms)
    statements = [
        "SET @version_id = NULL",
        "SELECT v.id INTO @version_id FROM content_page_versions v "
        "JOIN content_pages p ON p.current_version_id = v.id "
        f"WHERE p.slug = {lit(slug)} AND v.status = 'D' LIMIT 1 FOR UPDATE",
    ]
    _paper_statements(statements, paper, "@version_id IS NOT NULL")
    for atom in atoms:
        if atom.block_var is not None:
            _insert_block(statements, atom, "@version_id IS NOT NULL")
    _insert_questions(statements, atoms)
    _insert_items(
        statements,
        atoms,
        version_sql="@version_id",
        sort_start=None,
        guard="@version_id IS NOT NULL",
        count=True,
    )
    statements.append("SELECT @version_id AS version_id, @item_count AS item_count")
    return transaction(statements)


def render_edit_script(slug: str, sortorder: int, markdown: str, title: str | None, set_title: bool) -> str:
    assignments = [f"b.markdown = {lit(markdown)}"]
    if set_title:
        assignments.append(f"b.title = {lit(title)}")
    set_sql = ", ".join(assignments)
    draft = (
        "JOIN content_page_versions v ON v.id = i.version_id AND v.status = 'D' "
        "JOIN content_pages p ON p.current_version_id = v.id "
        f"AND p.slug = {lit(slug)} "
    )
    statements = [
        "SET @block_id = NULL",
        "SELECT i.content_block_id INTO @block_id FROM content_page_items i "
        + draft
        + f"WHERE i.sortorder = {lit(sortorder)} LIMIT 1 FOR UPDATE",
        "INSERT INTO content_block_revisions (content_block_id, revision_no, markdown) "
        "SELECT i.content_block_id, COALESCE(MAX(r.revision_no), 0) + 1, "
        f"{lit(markdown)} "
        "FROM content_page_items i "
        + draft
        + "LEFT JOIN content_block_revisions r ON r.content_block_id = i.content_block_id "
        f"WHERE i.sortorder = {lit(sortorder)} AND @block_id IS NOT NULL "
        "GROUP BY i.content_block_id",
        "SET @rev_ok = ROW_COUNT()",
        "SET @rev = IF(@rev_ok = 1, LAST_INSERT_ID(), NULL)",
        "UPDATE content_blocks b "
        "JOIN content_page_items i ON i.content_block_id = b.id "
        f"AND i.sortorder = {lit(sortorder)} "
        + draft
        + f"SET {set_sql} "
        "WHERE @rev IS NOT NULL",
        "UPDATE content_page_items i "
        + draft
        + "SET i.revision_id = @rev "
        f"WHERE i.sortorder = {lit(sortorder)} AND @rev IS NOT NULL",
        "SELECT @rev AS revision_id",
    ]
    return transaction(statements)


def render_publish_script(slug: str) -> str:
    statements = [
        "UPDATE content_pages p "
        "JOIN content_page_versions v ON v.id = p.current_version_id "
        "SET p.status = 'A', v.status = 'A' "
        f"WHERE p.slug = {lit(slug)} AND v.status = 'D'",
        "SELECT ROW_COUNT() AS wrote",
    ]
    return transaction(statements)


def render_version_script(page: PageIn, *, clone: bool) -> str:
    atoms = [] if clone else _expand(page.items or [], page.paper)
    _assign_vars(atoms)
    statements = [
        "SET @page_id = NULL",
        "SELECT id INTO @page_id FROM content_pages "
        f"WHERE slug = {lit(page.slug)} LIMIT 1 FOR UPDATE",
    ]
    if clone:
        statements.append("SET @paper_id = NULL")
    else:
        _paper_statements(statements, page.paper, "@page_id IS NOT NULL")
    if not clone:
        for atom in atoms:
            if atom.block_var is not None:
                _insert_block(statements, atom, "@page_id IS NOT NULL")
        _insert_questions(statements, atoms)
    statements.append(
        "INSERT INTO content_page_versions (page_id, version_no, note, status) "
        "SELECT p.id, COALESCE(MAX(v.version_no), 0) + 1, "
        f"{lit(page.note)}, 'D' "
        "FROM content_pages p "
        "LEFT JOIN content_page_versions v ON v.page_id = p.id "
        f"WHERE p.slug = {lit(page.slug)} AND @page_id IS NOT NULL "
        "GROUP BY p.id"
    )
    statements.append("SET @version_ok = ROW_COUNT()")
    statements.append("SET @version_id = IF(@version_ok = 1, LAST_INSERT_ID(), NULL)")
    if clone:
        statements.append(
            "INSERT INTO content_page_items (version_id, sortorder, content_block_id, revision_id) "
            "SELECT @version_id, i.sortorder, i.content_block_id, i.revision_id "
            "FROM content_page_items i "
            "JOIN content_pages p ON p.current_version_id = i.version_id "
            "WHERE p.id = @page_id AND @version_id IS NOT NULL"
        )
    elif atoms:
        _insert_items(
            statements,
            atoms,
            version_sql="@version_id",
            sort_start=0,
            guard="@version_id IS NOT NULL",
            count=False,
        )
    assignments = ["current_version_id = @version_id", "status = 'D'"]
    if page.title:
        assignments.append(f"title = {lit(page.title)}")
    if page.kind:
        assignments.append(f"kind = {lit(page.kind)}")
    statements.append(
        "UPDATE content_pages SET "
        + ", ".join(assignments)
        + " WHERE id = @page_id AND @version_id IS NOT NULL"
    )
    statements.append(
        "SELECT @page_id AS page_id, @version_id AS version_id, @paper_id AS paper_id"
    )
    return transaction(statements)


def _first(db: Database, sql: str) -> dict | None:
    rows = db.query(sql)
    return rows[0] if rows else None


def _run(db: Database, sql: str) -> dict:
    rows = db.script(sql)
    return rows[0] if rows else {}


def _lookup_paper(db: Database, paper: PaperIn | None) -> None:
    if paper is None:
        return
    row = _first(db, f"SELECT id FROM papers WHERE slug = {lit(paper.slug)} LIMIT 1")
    if row is not None:
        found = _int(row.get("id"))
        if found is None:
            raise ContentError(500, "server", "papers.id is missing")
        paper.existing_id = found
        return
    if not paper.title:
        raise ContentError(400, "bad_item", "paper.title is required")


def _lookup_reuses(db: Database, items: list[ItemIn]) -> None:
    for item in items:
        if item.reuse_block_id is None:
            continue
        block = _first(
            db,
            "SELECT id FROM content_blocks WHERE id = "
            f"{lit(item.reuse_block_id)} LIMIT 1",
        )
        if block is None:
            raise ContentError(
                404,
                "missing_block",
                f"content block {item.reuse_block_id} was not found",
            )
        if item.reuse_revision_id is not None:
            revision = _first(
                db,
                "SELECT id FROM content_block_revisions WHERE id = "
                f"{lit(item.reuse_revision_id)} AND content_block_id = "
                f"{lit(item.reuse_block_id)} LIMIT 1",
            )
            if revision is None:
                raise ContentError(
                    400,
                    "bad_revision",
                    f"revision {item.reuse_revision_id} is not on block {item.reuse_block_id}",
                )
            item.resolved_revision_id = item.reuse_revision_id
            continue
        revision = _first(
            db,
            "SELECT id FROM content_block_revisions WHERE content_block_id = "
            f"{lit(item.reuse_block_id)} ORDER BY revision_no DESC, id DESC LIMIT 1",
        )
        if revision is None or _int(revision.get("id")) is None:
            raise ContentError(
                400,
                "missing_revision",
                f"content block {item.reuse_block_id} has no revision",
            )
        item.resolved_revision_id = _int(revision.get("id"))


def _page_sql(slug: str) -> str:
    return (
        "SELECT p.id AS page_id, p.slug AS slug, p.title AS title, p.kind AS kind, "
        "p.status AS status, p.current_version_id AS current_version_id, "
        "v.id AS version_id, v.version_no AS version_no, v.note AS note, "
        "v.status AS version_status "
        "FROM content_pages p "
        "LEFT JOIN content_page_versions v ON v.id = p.current_version_id "
        f"WHERE p.slug = {lit(slug)} LIMIT 1"
    )


def _items_sql(version_id: int) -> str:
    return (
        "SELECT i.sortorder AS sortorder, i.content_block_id AS content_block_id, "
        "i.revision_id AS revision_id, b.title AS title, b.kind AS kind, "
        "r.markdown AS markdown, r.revision_no AS revision_no, q.id AS question_id "
        "FROM content_page_items i "
        "JOIN content_blocks b ON b.id = i.content_block_id "
        "JOIN content_block_revisions r ON r.id = i.revision_id "
        "LEFT JOIN (SELECT stem_block_id, MIN(id) AS id FROM questions "
        "GROUP BY stem_block_id) q ON q.stem_block_id = i.content_block_id "
        f"WHERE i.version_id = {lit(version_id)} ORDER BY i.sortorder"
    )


def _page_payload(row: dict, items: list[dict]) -> dict:
    version_id = _int(row.get("version_id"))
    version = None
    if version_id is not None:
        version = {
            "id": version_id,
            "version_no": _int(row.get("version_no")),
            "note": row.get("note"),
            "status": row.get("version_status"),
        }
    return {
        "page": {
            "id": _int(row.get("page_id")),
            "slug": row.get("slug"),
            "title": row.get("title"),
            "kind": row.get("kind"),
            "status": row.get("status"),
            "current_version_id": _int(row.get("current_version_id")),
        },
        "version": version,
        "items": [
            {
                "sortorder": _int(item.get("sortorder")),
                "content_block_id": _int(item.get("content_block_id")),
                "revision_id": _int(item.get("revision_id")),
                "revision_no": _int(item.get("revision_no")),
                "title": item.get("title"),
                "kind": item.get("kind"),
                "markdown": item.get("markdown"),
                "question_id": _int(item.get("question_id")),
            }
            for item in items
        ],
    }


def fetch_page(db: Database, slug: str) -> dict:
    if not SLUG_RE.fullmatch(slug):
        raise ContentError(400, "bad_slug", "page slug is not valid")
    row = _first(db, _page_sql(slug))
    if row is None:
        raise ContentError(404, "page_not_found", f"no content page {slug}")
    version_id = _int(row.get("version_id"))
    items = db.query(_items_sql(version_id)) if version_id is not None else []
    return _page_payload(row, items)


def _current(db: Database, slug: str) -> dict:
    row = _first(db, _page_sql(slug))
    if row is None:
        raise ContentError(404, "page_not_found", f"no content page {slug}")
    return row


def import_document(db: Database, payload: dict) -> dict:
    page = parse_import(payload)
    existing = _first(db, f"SELECT id FROM content_pages WHERE slug = {lit(page.slug)} LIMIT 1")
    if existing is not None:
        raise ContentError(
            409,
            "page_exists",
            f"content page {page.slug} already exists; add a version instead of overwriting",
        )
    _lookup_paper(db, page.paper)
    _lookup_reuses(db, page.items)
    created = _run(db, render_import_script(page))
    if _int(created.get("page_id")) is None:
        raise ContentError(500, "import_failed", "page was not created")
    body = fetch_page(db, page.slug)
    body["paper_id"] = _int(created.get("paper_id"))
    return body


def append_item(db: Database, slug: str, payload: dict) -> dict:
    item = parse_one_item(payload)
    paper = None
    if item.is_question and payload.get("paper") is not None:
        paper = _parse_paper(payload["paper"])
    row = _current(db, slug)
    if row.get("version_status") != "D":
        raise ContentError(
            409,
            "published_version",
            "the current version is published; POST /content/pages/{slug}/versions "
            "to open a draft, then append",
        )
    _lookup_paper(db, paper)
    _lookup_reuses(db, [item])
    created = _run(db, render_append_script(slug, item, paper))
    if _int(created.get("version_id")) is None or _int(created.get("item_count")) in (None, 0):
        raise ContentError(
            409,
            "published_version",
            "the current version is not a draft, so nothing was appended",
        )
    return fetch_page(db, slug)


def edit_item(db: Database, slug: str, sortorder: int, payload: dict) -> dict:
    raw = _require_object(payload, "body")
    if "markdown" not in raw:
        raise ContentError(400, "bad_item", "markdown is required")
    markdown = _markdown(raw.get("markdown"), "markdown")
    set_title = "title" in raw
    title = _optional_text(raw.get("title"), "title", 255) if set_title else None
    row = _current(db, slug)
    if row.get("version_status") != "D":
        raise ContentError(
            409,
            "published_version",
            "the current version is published; open a new draft version before editing",
        )
    version_id = _int(row.get("version_id"))
    if version_id is None:
        raise ContentError(409, "published_version", "this page has no draft version")
    found = _first(
        db,
        "SELECT content_block_id FROM content_page_items WHERE version_id = "
        f"{lit(version_id)} AND sortorder = {lit(sortorder)} LIMIT 1",
    )
    if found is None:
        raise ContentError(404, "missing_item", f"sortorder {sortorder} is not on the current version")
    created = _run(db, render_edit_script(slug, sortorder, markdown, title, set_title))
    if _int(created.get("revision_id")) is None:
        raise ContentError(
            409,
            "published_version",
            "the current version is not a draft, so the atom was not edited",
        )
    return fetch_page(db, slug)


def publish_page(db: Database, slug: str) -> dict:
    row = _current(db, slug)
    if _int(row.get("version_id")) is None:
        raise ContentError(409, "not_draft", "this page has no version to publish")
    if row.get("version_status") == "A" and row.get("status") == "A":
        return fetch_page(db, slug)
    created = _run(db, render_publish_script(slug))
    body = fetch_page(db, slug)
    version = body.get("version") or {}
    if version.get("status") != "A" or body["page"].get("status") != "A":
        if _int(created.get("wrote")) in (None, 0):
            raise ContentError(409, "not_draft", "the current version is not a draft")
    return body


def new_version(db: Database, slug: str, payload: dict) -> dict:
    if payload is None:
        payload = {}
    page = parse_version(payload, slug)
    _current(db, slug)
    clone = page.items is None
    items = [] if page.items is None else page.items
    if page.paper is not None:
        _lookup_paper(db, page.paper)
    if not clone:
        _lookup_reuses(db, items)
        page.items = items
    created = _run(db, render_version_script(page, clone=clone))
    if _int(created.get("version_id")) is None:
        raise ContentError(500, "import_failed", "draft version was not created")
    return fetch_page(db, slug)


def _json_body(raw: bytes) -> dict:
    if len(raw) > MAX_BODY:
        raise ContentError(413, "body_too_large", "body exceeds 2MB")
    if not raw:
        return {}
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ContentError(400, "bad_json", "body is not JSON") from exc
    return _require_object(payload, "body")


def dispatch(method: str, path: str, raw_body: bytes, db: Database) -> tuple[int, dict]:
    path = unquote(path).rstrip("/") or "/"
    match = PATH_RE.fullmatch(path)
    if match is None:
        raise ContentError(404, "not_found", f"unknown path {path}")
    slug = match.group("slug")
    action = match.group("action")
    sortorder = match.group("sortorder")
    method = method.upper()
    if action in {"publish", "versions"} and sortorder is not None:
        raise ContentError(404, "not_found", f"unknown path {path}")
    if slug is None:
        if method != "POST":
            raise ContentError(405, "method_not_allowed", "POST /content/pages imports a draft page")
        return 201, import_document(db, _json_body(raw_body))
    if action is None:
        if method != "GET":
            raise ContentError(405, "method_not_allowed", "GET fetches the page")
        return 200, fetch_page(db, slug)
    if action == "items" and sortorder is None:
        if method != "POST":
            raise ContentError(405, "method_not_allowed", "POST appends one atom to the draft")
        return 200, append_item(db, slug, _json_body(raw_body))
    if action == "items":
        if method != "POST":
            raise ContentError(405, "method_not_allowed", "POST edits one draft atom")
        return 200, edit_item(db, slug, int(sortorder), _json_body(raw_body))
    if action == "publish":
        if method != "POST":
            raise ContentError(405, "method_not_allowed", "POST publishes the draft version")
        return 200, publish_page(db, slug)
    if action == "versions":
        if method != "POST":
            raise ContentError(405, "method_not_allowed", "POST adds a draft version")
        return 201, new_version(db, slug, _json_body(raw_body))
    raise ContentError(404, "not_found", f"unknown path {path}")
