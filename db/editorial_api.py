#!/usr/bin/env python3
"""Analyse lookup for compulsory core, M1, M2, Pure Maths, and M&S.

The live server exposes three GET paths:

  /analyse/lookup
  /analyse/units
  /analyse/gaps

This module is that surface, versioned in the repo. A request with no
``subject``, no ``band``, and no module slug reads only the compulsory
tables (``analyse_mc``, ``analyse_sq``, and their unit catalogues). It
does not read ``analyse_m1_*``, ``analyse_pm_*``, ``content_blocks``, or
``solutions``.

M1 and M2 use the same paths. Pass ``subject``, ``band``, or a paper slug
such as ``dse2015-math-m1``. Worked solutions for those two syllabi are
read from ``content_blocks`` (keys ``{question_slug}:zh-HK`` and ``:en``,
or the ``<!-- hoksi:...:solution -->`` marker the ingest writes).

Pure Maths (``analyse_pm_*``, syllabus ``pm``) and M&S (``analyse_m1_*``,
syllabus ``ms``) are analyse-only. Solution lookup returns status
``blocked`` and gaps do not pretend those questions are missing a Hoksi
article. There is no solution pack for either syllabus.

``--plan`` prints the SQL and does not connect. ``--serve`` binds a
small HTTP server. The mysql client uses the same ``MYSQL_*`` variables
as the seed scripts.

Examples:
  python3 db/editorial_api.py --plan lookup --year 2015 --question 1 --kind sq
  python3 db/editorial_api.py --plan lookup --slug dse2015-math-m1 --question 3
  python3 db/editorial_api.py --plan gaps --subject pm
  python3 db/editorial_api.py --serve
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import traceback
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Callable
from urllib.parse import parse_qs, urlparse

CORE_TABLES = (
    "analyse_mc",
    "analyse_mc_units",
    "analyse_sq",
    "analyse_sq_units",
    "analyse_units",
    "analyse_unit_qtypes",
)
M1_TABLES = ("analyse_m1_units", "analyse_m1_sq", "analyse_m1_sq_units")
PM_TABLES = ("analyse_pm_units", "analyse_pm_sq", "analyse_pm_sq_units")

NOTE_PM = (
    "Pure Maths is analyse-only. Topic rows are on analyse_pm_* "
    "(syllabus pm). There is no Hoksi solution pack and nothing was loaded "
    "into content_blocks, so solutions are blocked rather than listed as gaps."
)
NOTE_MS = (
    "M&S is analyse-only. Topic rows are on analyse_m1_* (syllabus ms), "
    "including the first 2012 column (12#T). There is no Hoksi solution pack "
    "and nothing was loaded into content_blocks, so solutions are blocked "
    "rather than listed as gaps."
)
NOTE_CORE = (
    "Compulsory lookup reads analyse_mc and analyse_sq only. It does not "
    "read content_blocks. Worked core text stays on the existing core path."
)
NOTE_ON = "ON has no paper slug, so there is no content_blocks key to read."
NOTE_MISSING_BLOCKS = (
    "content_blocks is not in this database, so M1/M2 solution text was not read."
)
NOTE_UNREADABLE = (
    "content_blocks has no source_slug (or slug) column and no text column, "
    "so solution text cannot be matched."
)

SLUG_RE = re.compile(
    r"^dse(?P<token>\d{4}|sp|pp)-math-(?P<tail>m1|m2|cp1|cp2|core)$",
    re.IGNORECASE,
)
QUESTION_SLUG_RE = re.compile(
    r"^(?P<paper>dse(?:\d{4}|sp|pp)-math-(?:m1|m2|cp1|cp2|core))-q(?P<q>\d+)$",
    re.IGNORECASE,
)
KEY_RE = re.compile(
    r"^(dse(?:\d{4}|sp|pp)-math-m[12]-q\d+):(zh-HK|en)$"
)
MARKER_RE = re.compile(
    r"<!-- hoksi:(dse(?:\d{4}|sp|pp)-math-m[12]):q(\d+):(zh-HK|en):solution -->"
)
IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
UNIT_RE = re.compile(r"^[0-9A-Za-z]+$")
YEAR_RE = re.compile(r"^(?:\d{2,4}|[A-Za-z]{1,6})$")
SPECIAL_YEARS = frozenset({"SP", "PP", "ON"})
LANGS = ("zh-HK", "en")

SUBJECT_ALIASES = {
    "core": "core",
    "cp": "core",
    "compulsory": "core",
    "compulsory-core": "core",
    "m1": "m1",
    "module1": "m1",
    "module-1": "m1",
    "m2": "m2",
    "module2": "m2",
    "module-2": "m2",
    "pm": "pm",
    "pure": "pm",
    "puremath": "pm",
    "pure-math": "pm",
    "pure_math": "pm",
    "ms": "ms",
    "m&s": "ms",
    "m-s": "ms",
    "maths-and-stats": "ms",
    "math-and-stat": "ms",
}
BAND_ALIASES = {
    "core": "core",
    "cp": "core",
    "compulsory": "core",
    "dse": "dse",
    "dse-m1": "dse",
    "m1": "dse",
    "ms": "ms",
    "m&s": "ms",
    "m2": "m2",
    "pm": "pm",
    "pure": "pm",
}
KIND_ALIASES = {
    "sq": "sq",
    "structured": "sq",
    "long": "sq",
    "mc": "mc",
    "multiple": "mc",
    "multiple-choice": "mc",
}

YEAR_LABEL_ALIASES = ("year_label", "year", "yr", "exam_year")
YEAR_KEY_ALIASES = ("year_key",)
QUESTION_ALIASES = ("question_no", "q_no", "question_number", "qno", "number")
RAW_ALIASES = ("raw_cell", "raw", "topics", "unit_codes")
PAPER_COL_ALIASES = ("paper", "paper_no", "paper_number")
SYLLABUS_ALIASES = ("syllabus",)
OCCURRENCE_ALIASES = ("label_occurrence", "occurrence")
ID_ALIASES = ("id",)
UNIT_ALIASES = ("unit_code", "code", "topic", "topic_code")
SHORT_ALIASES = ("short_name", "short", "abbr")
NAME_ALIASES = ("name", "unit_name", "title")
POSITION_ALIASES = ("position", "pos", "seq", "ordinal")
QTYPE_ALIASES = ("qtype", "question_type", "q_type", "type")
SQ_LINK_ALIASES = ("sq_id", "question_id", "analyse_sq_id")
MC_LINK_ALIASES = ("mc_id", "question_id", "analyse_mc_id")
BLOCK_KEY_ALIASES = ("source_slug", "slug", "external_slug", "hoksi_slug", "code")
BLOCK_TEXT_ALIASES = ("content", "markdown", "md", "body", "text", "latex", "html")
BLOCK_LANG_ALIASES = ("lang", "language", "locale")
BLOCK_ID_ALIASES = ("id", "block_id")
SOLUTION_BLOCK_ALIASES = ("content_block_id", "block_id", "solution_block_id")
SOLUTION_SORT_ALIASES = ("sortorder", "sort_order", "position", "ordinal")


class RouteError(Exception):
    def __init__(self, status: int, code: str, message: str):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message

    def payload(self) -> dict:
        return {"error": self.code, "message": self.message}


class MissingTable(Exception):
    pass


@dataclass(frozen=True)
class Target:
    subject: str
    band: str
    family: str
    syllabus: str | None
    kind: str | None
    paper: int | None
    year_labels: tuple[str, ...]
    year_key: str | None
    question_no: int | None
    unit_code: str | None
    paper_slug: str | None
    question_slug: str | None
    solutions_mode: str
    embed_questions: bool


@dataclass
class Schema:
    tables: dict[str, dict[str, str]]

    def has_table(self, name: str) -> bool:
        return name in self.tables

    def columns(self, name: str) -> dict[str, str]:
        return self.tables.get(name, {})

    def pick(self, table: str, aliases: tuple[str, ...]) -> str | None:
        columns = self.columns(table)
        folded = {column.lower(): column for column in columns}
        for alias in aliases:
            found = folded.get(alias.lower())
            if found is not None:
                return found
        return None

    def type_of(self, table: str, column: str) -> str:
        return self.columns(table).get(column, "")

    def without(self, *names: str) -> Schema:
        skip = set(names)
        return Schema(
            {key: dict(value) for key, value in self.tables.items() if key not in skip}
        )


def ident(name: str) -> str:
    if not IDENT_RE.fullmatch(name):
        raise RouteError(500, "bad_identifier", f"refusing SQL identifier {name!r}")
    return f"`{name}`"


def lit(value: object) -> str:
    if value is None:
        return "NULL"
    if isinstance(value, bool):
        return "1" if value else "0"
    if isinstance(value, int):
        return str(value)
    text = str(value).replace("\\", "\\\\").replace("'", "''").replace("\x00", "")
    return f"'{text}'"


def is_int_type(type_name: str) -> bool:
    base = type_name.lower().split("(", 1)[0].strip()
    return base in {
        "int",
        "integer",
        "smallint",
        "tinyint",
        "bigint",
        "mediumint",
        "year",
    }


def calendar_year(label: str) -> int | None:
    token = label.strip()
    upper = token.upper()
    if upper == "SP":
        return 2011
    if upper == "PP":
        return 2022
    if upper in SPECIAL_YEARS or not token.isdigit():
        return None
    if len(token) == 4:
        return int(token)
    number = int(token)
    return 1900 + number if number >= 80 else 2000 + number


def numeric_years(labels: tuple[str, ...]) -> list[int]:
    years: list[int] = []
    for label in labels:
        if label.upper() in SPECIAL_YEARS:
            continue
        year = calendar_year(label)
        if year is not None:
            years.append(year)
    return years


def canonical_labels(labels: tuple[str, ...]) -> tuple[str, ...]:
    specials = [label.upper() for label in labels if label.upper() in SPECIAL_YEARS]
    if specials:
        return tuple(dict.fromkeys(specials))
    years = numeric_years(labels)
    if not years:
        return tuple(labels)
    year = years[0]
    two = f"{year % 100:02d}"
    four = str(year)
    if two == four:
        return (four,)
    return (two, four)


def parse_year_token(raw: str) -> tuple[str, ...]:
    token = raw.strip()
    if not YEAR_RE.fullmatch(token):
        raise RouteError(400, "bad_year", f"year {raw!r} is not a number, SP, PP, or ON")
    if token.upper() in SPECIAL_YEARS:
        return canonical_labels((token.upper(),))
    if not token.isdigit():
        raise RouteError(400, "bad_year", f"year {raw!r} is not a number, SP, PP, or ON")
    return canonical_labels((token,))


def years_agree(left: tuple[str, ...], right: tuple[str, ...]) -> bool:
    left_special = {label.upper() for label in left if label.upper() in SPECIAL_YEARS}
    right_special = {label.upper() for label in right if label.upper() in SPECIAL_YEARS}
    if left_special and right_special:
        return bool(left_special & right_special)
    if left_special or right_special:
        return False
    return bool(set(numeric_years(left)) & set(numeric_years(right)))


def parse_question(raw: str | None) -> int | None:
    if raw is None:
        return None
    if not raw.isdigit() or raw.startswith("+"):
        raise RouteError(400, "bad_question", f"question {raw!r} is not a question number")
    number = int(raw)
    if number < 1 or number > 200:
        raise RouteError(400, "bad_question", f"question {raw!r} is out of range")
    return number


def parse_paper(raw: str | None) -> int | None:
    if raw is None:
        return None
    if raw not in {"1", "2"}:
        raise RouteError(400, "bad_paper", "paper must be 1 or 2")
    return int(raw)


def parse_unit(raw: str | None) -> str | None:
    if raw is None:
        return None
    if not UNIT_RE.fullmatch(raw):
        raise RouteError(400, "bad_unit", f"unit {raw!r} is not a topic token")
    return raw


def parse_kind(raw: str | None) -> str | None:
    if raw is None:
        return None
    kind = KIND_ALIASES.get(raw.lower())
    if kind is None:
        raise RouteError(400, "bad_kind", "kind must be sq or mc")
    return kind


def parse_subject(raw: str | None) -> str | None:
    if raw is None:
        return None
    subject = SUBJECT_ALIASES.get(raw.lower())
    if subject is None:
        raise RouteError(400, "bad_subject", f"unknown subject {raw!r}")
    return subject


def parse_band(raw: str | None) -> str | None:
    if raw is None:
        return None
    band = BAND_ALIASES.get(raw.lower())
    if band is None:
        raise RouteError(400, "bad_band", f"unknown band {raw!r}")
    return band


def _slug_parts(raw: str) -> tuple[str, tuple[str, ...], int | None]:
    """Return paper-slug tail, year labels, and question number when present."""
    question = QUESTION_SLUG_RE.fullmatch(raw)
    question_no = None
    paper = raw
    if question is not None:
        paper = question.group("paper")
        question_no = int(question.group("q"))
    match = SLUG_RE.fullmatch(paper)
    if match is None:
        raise RouteError(400, "bad_slug", f"slug {raw!r} is not a paper or question slug")
    token = match.group("token")
    tail = match.group("tail").lower()
    if token.isdigit():
        labels = canonical_labels((token,))
    else:
        labels = canonical_labels((token.upper(),))
    return tail, labels, question_no


def _year_key(band: str, labels: tuple[str, ...]) -> str | None:
    years = numeric_years(labels)
    if not years or set(years) != {2012}:
        return None
    if any(label.upper() in SPECIAL_YEARS for label in labels):
        return None
    if band == "dse":
        return "12#U"
    if band == "ms":
        return "12#T"
    return None


def _paper_slug(subject: str, labels: tuple[str, ...]) -> str | None:
    if subject not in {"m1", "m2"}:
        return None
    specials = [label.upper() for label in labels if label.upper() in SPECIAL_YEARS]
    if "ON" in specials:
        return None
    if "SP" in specials:
        token = "sp"
    elif "PP" in specials:
        token = "pp"
    else:
        years = numeric_years(labels)
        if not years:
            return None
        year = years[0]
        if year < 2012:
            return None
        token = str(year)
    return f"dse{token}-math-{subject}"


def _reject_year_for_band(subject: str, band: str, labels: tuple[str, ...]) -> None:
    if not labels:
        return
    specials = {label.upper() for label in labels if label.upper() in SPECIAL_YEARS}
    years = numeric_years(labels)
    if subject in {"m1", "ms"} or band in {"dse", "ms"}:
        if band == "dse" and years and all(year < 2012 for year in years) and not specials:
            raise RouteError(
                400,
                "use_ms",
                "Years before 2012 on the M1 sheet are M&S (subject=ms or band=ms), not DSE M1.",
            )
        if band == "ms" and specials:
            raise RouteError(
                400,
                "use_m1",
                "SP, PP, and ON on the M1 sheet are DSE M1 (subject=m1 or band=dse).",
            )
        if band == "ms" and years and all(year > 2012 for year in years):
            raise RouteError(
                400,
                "use_m1",
                "Years after 2012 on the M1 sheet are DSE M1 (subject=m1 or band=dse).",
            )
        if "ON" in specials and subject == "m2":
            raise RouteError(400, "bad_year", "ON is not a year header in the Pure Maths / M2 workbook.")
    if subject == "m2" or band == "m2":
        if "ON" in specials:
            raise RouteError(400, "bad_year", "ON is not a year header in the Pure Maths / M2 workbook.")
        if years and all(year < 2012 for year in years) and not specials:
            raise RouteError(
                400,
                "use_pm",
                "Years before 2012 in PManalyse.xlsx are Pure Maths (subject=pm), not M2.",
            )
    if subject == "pm" or band == "pm":
        if "ON" in specials:
            raise RouteError(400, "bad_year", "ON is not a year header in the Pure Maths / M2 workbook.")
        if specials & {"SP", "PP"} or (years and all(year >= 2012 for year in years)):
            raise RouteError(
                400,
                "use_m2",
                "Paper 1 from SP, PP, and 2012 onward is M2 (subject=m2). Paper 2 has no columns after 2011.",
            )


def _resolve_band(subject: str, band: str | None, labels: tuple[str, ...]) -> str:
    """Pick dse/ms/m2/pm/core/all once subject and optional band are known."""
    if subject == "core":
        if band not in (None, "core"):
            raise RouteError(400, "band_mismatch", "compulsory core does not take an M1/M2/PM band")
        return "core"
    if subject == "m2":
        if band not in (None, "m2"):
            raise RouteError(400, "band_mismatch", "subject m2 only uses band m2")
        return "m2"
    if subject == "pm":
        if band not in (None, "pm"):
            raise RouteError(400, "band_mismatch", "subject pm only uses band pm")
        return "pm"
    if subject == "ms":
        if band not in (None, "ms"):
            raise RouteError(400, "band_mismatch", "subject ms only uses band ms")
        return "ms"
    # subject m1
    if band == "ms":
        return "ms"
    if band in {"dse", "m2", "pm", "core"} and band != "dse":
        raise RouteError(400, "band_mismatch", f"subject m1 does not use band {band}")
    if band == "dse":
        return "dse"
    if not labels:
        return "all"
    specials = {label.upper() for label in labels if label.upper() in SPECIAL_YEARS}
    years = numeric_years(labels)
    if specials:
        return "dse"
    if years and all(year < 2012 for year in years):
        raise RouteError(
            400,
            "use_ms",
            "Years before 2012 on the M1 sheet are M&S. Pass subject=ms or band=ms.",
        )
    if years and set(years) == {2012}:
        raise RouteError(
            400,
            "ambiguous_2012",
            "2012 is two M1 columns. Use slug dse2012-math-m1 for DSE (12#U) "
            "or subject=ms for M&S (12#T).",
        )
    return "dse"


def _family_for(subject: str, band: str) -> tuple[str, str | None]:
    if subject == "core" or band == "core":
        return "core", None
    if band == "all":
        return "m1", None
    if band == "dse":
        return "m1", "dse"
    if band == "ms" or subject == "ms":
        return "m1", "ms"
    if band == "m2" or subject == "m2":
        return "pm", "m2"
    if band == "pm" or subject == "pm":
        return "pm", "pm"
    raise RouteError(400, "bad_subject", f"cannot route subject {subject!r} band {band!r}")


def _solutions_mode(subject: str, band: str, include_solutions: bool) -> str:
    if subject == "core" or band == "core":
        return "not_served" if include_solutions else "omit"
    if band == "all":
        return "mixed"
    if band in {"ms", "pm"} or subject in {"ms", "pm"}:
        return "blocked"
    if band in {"dse", "m2"}:
        return "content"
    return "omit"


def resolve_target(params: dict[str, str]) -> Target:
    include_solutions = params.get("include", "").lower() in {"solutions", "1", "true", "yes"}
    embed_questions = params.get("questions", "").lower() in {"1", "true", "yes"}
    subject = parse_subject(params.get("subject"))
    band = parse_band(params.get("band"))
    kind = parse_kind(params.get("kind"))
    paper = parse_paper(params.get("paper"))
    unit_code = parse_unit(params.get("unit") or params.get("unit_code") or params.get("code"))
    question_no = parse_question(params.get("question") or params.get("q") or params.get("question_no"))
    year_raw = params.get("year")
    slug_raw = params.get("slug")

    slug_tail = None
    slug_labels: tuple[str, ...] = ()
    if slug_raw:
        slug_tail, slug_labels, slug_question = _slug_parts(slug_raw.strip())
        if slug_question is not None:
            if question_no is not None and question_no != slug_question:
                raise RouteError(400, "slug_mismatch", "slug question does not match question")
            question_no = slug_question
        slug_subject = {
            "m1": "m1",
            "m2": "m2",
            "cp1": "core",
            "cp2": "core",
            "core": "core",
        }[slug_tail]
        if subject is not None and subject != slug_subject:
            raise RouteError(400, "slug_mismatch", "slug subject does not match subject")
        subject = slug_subject
        slug_kind = {"cp1": "sq", "cp2": "mc"}.get(slug_tail or "")
        slug_paper = {"cp1": 1, "cp2": 2, "m2": 1}.get(slug_tail or "")
        if slug_kind is not None:
            if kind is not None and kind != slug_kind:
                raise RouteError(400, "slug_mismatch", "slug paper does not match kind")
            kind = slug_kind
        if slug_tail == "m1":
            if band == "ms":
                raise RouteError(
                    400,
                    "slug_mismatch",
                    "slug dse…-math-m1 is DSE M1 (12#U for 2012), not the M&S column",
                )
            band = "dse"
        if slug_tail == "m2":
            if band not in (None, "m2"):
                raise RouteError(400, "slug_mismatch", "slug does not match band")
            band = "m2"
        if slug_paper is not None:
            if paper is not None and paper != slug_paper:
                raise RouteError(400, "slug_mismatch", "slug paper does not match paper")
            if slug_tail == "m2":
                paper = 1
            elif slug_tail in {"cp1", "cp2"} and paper is None:
                paper = slug_paper

    year_labels: tuple[str, ...] = ()
    if year_raw:
        year_labels = parse_year_token(year_raw)
    if slug_labels and year_labels and not years_agree(slug_labels, year_labels):
        raise RouteError(400, "slug_mismatch", "slug year does not match year")
    if slug_labels or year_labels:
        year_labels = canonical_labels(slug_labels or year_labels)
        if slug_labels and year_labels:
            year_labels = canonical_labels(slug_labels + year_labels)

    if subject is None and band is not None:
        subject = {"core": "core", "dse": "m1", "ms": "ms", "m2": "m2", "pm": "pm"}[band]
    if subject is None:
        subject = "core"

    if paper == 1 and kind == "mc" and subject == "core":
        raise RouteError(400, "band_mismatch", "compulsory paper 1 is structured (kind=sq), paper 2 is multiple choice")
    if paper == 2 and kind == "sq" and subject == "core":
        raise RouteError(400, "band_mismatch", "compulsory paper 2 is multiple choice (kind=mc)")
    if subject == "core" and kind is None and paper == 1:
        kind = "sq"
    if subject == "core" and kind is None and paper == 2:
        kind = "mc"

    if subject != "core" and kind == "mc":
        raise RouteError(400, "no_mc", f"{subject} Analyse has no multiple-choice table")

    resolved_band = _resolve_band(subject, band, year_labels)
    if year_labels:
        _reject_year_for_band(subject, resolved_band, year_labels)
    if subject == "m2" and paper == 2:
        raise RouteError(400, "bad_paper", "M2 Analyse rows are paper 1 of analyse_pm_*")
    if subject == "pm" and paper == 2 and year_labels:
        years = numeric_years(year_labels)
        if years and all(year >= 2012 for year in years):
            raise RouteError(
                400,
                "use_m2",
                "Paper 2 has no columns after 2011. Paper 1 from 2012 onward is M2.",
            )
    if subject == "m2" and paper is None:
        paper = 1

    family, syllabus = _family_for(subject, resolved_band)
    mode = _solutions_mode(subject, resolved_band, include_solutions)
    # A lookup that names the M&S band through subject=m1&band=ms stays blocked.
    if resolved_band == "ms":
        mode = "blocked"
    if resolved_band == "pm":
        mode = "blocked"

    public_subject = subject
    if resolved_band == "ms" and subject == "m1":
        public_subject = "m1"
    year_key = _year_key(resolved_band, year_labels) if resolved_band in {"dse", "ms"} else None
    slug_subject = "m1" if resolved_band == "dse" else "m2" if resolved_band == "m2" else ""
    paper_slug = _paper_slug(slug_subject, year_labels) if slug_subject else None
    question_slug = None
    if paper_slug and question_no is not None:
        question_slug = f"{paper_slug}-q{question_no}"
    if unit_code or year_labels or embed_questions:
        embed_questions = bool(unit_code or year_labels or embed_questions)

    return Target(
        subject=public_subject,
        band=resolved_band,
        family=family,
        syllabus=syllabus,
        kind=kind,
        paper=paper,
        year_labels=year_labels,
        year_key=year_key,
        question_no=question_no,
        unit_code=unit_code,
        paper_slug=paper_slug,
        question_slug=question_slug,
        solutions_mode=mode,
        embed_questions=embed_questions,
    )


def assumed_schema() -> Schema:
    """Column names this API plans against. ``--serve`` uses SHOW COLUMNS instead."""

    def columns(*pairs: tuple[str, str]) -> dict[str, str]:
        return {name: type_name for name, type_name in pairs}

    sq = columns(
        ("id", "int"),
        ("year_label", "varchar(32)"),
        ("question_no", "smallint"),
        ("raw_cell", "varchar(255)"),
    )
    link = columns(
        ("sq_id", "int"),
        ("position", "smallint"),
        ("unit_code", "smallint"),
    )
    mc_link = columns(
        ("mc_id", "int"),
        ("position", "smallint"),
        ("unit_code", "smallint"),
    )
    units = columns(
        ("unit_code", "smallint"),
        ("short_name", "varchar(64)"),
        ("name", "varchar(191)"),
    )
    m1_sq = columns(
        ("id", "int"),
        ("year_key", "varchar(32)"),
        ("year_label", "varchar(32)"),
        ("label_occurrence", "smallint"),
        ("question_no", "smallint"),
        ("raw_cell", "varchar(255)"),
        ("syllabus", "varchar(8)"),
    )
    m1_link = columns(
        ("sq_id", "int"),
        ("position", "smallint"),
        ("syllabus", "varchar(8)"),
        ("unit_code", "smallint"),
    )
    m1_units = columns(
        ("syllabus", "varchar(8)"),
        ("unit_code", "smallint"),
        ("short_name", "varchar(64)"),
        ("name", "varchar(191)"),
    )
    pm_sq = columns(
        ("id", "int"),
        ("paper", "smallint"),
        ("syllabus", "varchar(8)"),
        ("year_key", "varchar(32)"),
        ("year_label", "varchar(32)"),
        ("label_occurrence", "smallint"),
        ("question_no", "smallint"),
        ("raw_cell", "varchar(255)"),
    )
    pm_link = columns(
        ("sq_id", "int"),
        ("position", "smallint"),
        ("syllabus", "varchar(8)"),
        ("unit_code", "varchar(16)"),
    )
    pm_units = columns(
        ("syllabus", "varchar(8)"),
        ("unit_code", "varchar(16)"),
        ("name", "varchar(191)"),
    )
    return Schema(
        {
            "analyse_sq": dict(sq),
            "analyse_sq_units": dict(link),
            "analyse_mc": dict(sq),
            "analyse_mc_units": dict(mc_link),
            "analyse_units": dict(units),
            "analyse_unit_qtypes": columns(
                ("unit_code", "smallint"),
                ("qtype", "varchar(64)"),
            ),
            "analyse_m1_sq": dict(m1_sq),
            "analyse_m1_sq_units": dict(m1_link),
            "analyse_m1_units": dict(m1_units),
            "analyse_pm_sq": dict(pm_sq),
            "analyse_pm_sq_units": dict(pm_link),
            "analyse_pm_units": dict(pm_units),
            "content_blocks": columns(
                ("id", "int"),
                ("content", "mediumtext"),
                ("source_slug", "varchar(191)"),
                ("lang", "varchar(16)"),
            ),
            "solutions": columns(
                ("id", "int"),
                ("content_block_id", "int"),
                ("sortorder", "int"),
            ),
            "papers": columns(("id", "int"), ("slug", "varchar(64)")),
            "questions": columns(
                ("id", "int"),
                ("paper_id", "int"),
                ("stem_block_id", "int"),
            ),
        }
    )


def _require_table(schema: Schema, name: str) -> None:
    if not schema.has_table(name):
        raise RouteError(503, "missing_table", f"{name} is not in this database")


def _require_col(schema: Schema, table: str, aliases: tuple[str, ...], label: str) -> str:
    found = schema.pick(table, aliases)
    if found is None:
        looked = ", ".join(aliases)
        raise RouteError(
            500,
            "missing_column",
            f"{table} has no {label} column (looked for {looked})",
        )
    return found


def _table_for(target: Target, kind: str) -> tuple[str, str, str | None]:
    if target.family == "core":
        if kind == "mc":
            return "analyse_mc", "analyse_mc_units", "analyse_units"
        return "analyse_sq", "analyse_sq_units", "analyse_units"
    if target.family == "m1":
        return "analyse_m1_sq", "analyse_m1_sq_units", "analyse_m1_units"
    return "analyse_pm_sq", "analyse_pm_sq_units", "analyse_pm_units"


def _kinds_for(target: Target, schema: Schema) -> list[str]:
    if target.family != "core":
        return ["sq"]
    if target.kind == "mc":
        return ["mc"]
    if target.kind == "sq":
        return ["sq"]
    kinds = []
    if schema.has_table("analyse_sq"):
        kinds.append("sq")
    if schema.has_table("analyse_mc"):
        kinds.append("mc")
    if not kinds:
        raise RouteError(503, "missing_table", "analyse_sq and analyse_mc are not in this database")
    return kinds


def _year_sql(schema: Schema, table: str, alias: str, target: Target) -> str:
    if target.year_key:
        column = schema.pick(table, YEAR_KEY_ALIASES)
        if column is not None:
            return f"{alias}.{ident(column)} = {lit(target.year_key)}"
        occurrence = schema.pick(table, OCCURRENCE_ALIASES)
        label = schema.pick(table, YEAR_LABEL_ALIASES)
        if occurrence is None or label is None:
            raise RouteError(
                500,
                "ambiguous_column",
                f"{table} cannot tell the two 2012 columns apart (need year_key or label_occurrence)",
            )
        which = 1 if target.year_key.endswith("#T") else 2
        return (
            f"{alias}.{ident(label)} = '12' AND {alias}.{ident(occurrence)} = {which}"
        )
    if not target.year_labels:
        return ""
    column = _require_col(schema, table, YEAR_LABEL_ALIASES, "year")
    type_name = schema.type_of(table, column)
    if is_int_type(type_name):
        values: list[object] = []
        for year in numeric_years(target.year_labels):
            if year not in values:
                values.append(year)
        if not values:
            raise RouteError(
                400,
                "bad_year",
                f"{table}.{column} is an integer, so SP, PP, and ON cannot be stored there",
            )
    else:
        values = list(target.year_labels)
    rendered = ", ".join(lit(value) for value in values)
    return f"{alias}.{ident(column)} IN ({rendered})"


def _common_filters(schema: Schema, table: str, alias: str, target: Target, *, question: bool) -> list[str]:
    parts: list[str] = []
    if question:
        if target.question_no is None:
            raise RouteError(400, "missing_param", "lookup needs a question and a year or slug")
        column = _require_col(schema, table, QUESTION_ALIASES, "question number")
        parts.append(f"{alias}.{ident(column)} = {lit(target.question_no)}")
    year_sql = _year_sql(schema, table, alias, target)
    if year_sql:
        parts.append(year_sql)
    elif question:
        raise RouteError(400, "missing_param", "lookup needs a year or slug")
    syllabus = schema.pick(table, SYLLABUS_ALIASES)
    if target.family != "core":
        if syllabus is None:
            raise RouteError(500, "missing_column", f"{table} has no syllabus column")
        if target.syllabus is not None:
            parts.append(f"{alias}.{ident(syllabus)} = {lit(target.syllabus)}")
    paper_col = schema.pick(table, PAPER_COL_ALIASES)
    if target.family == "pm":
        if paper_col is None:
            raise RouteError(500, "missing_column", f"{table} has no paper column")
        if target.paper is not None:
            parts.append(f"{alias}.{ident(paper_col)} = {lit(target.paper)}")
    elif target.paper is not None and paper_col is not None and target.family == "core":
        parts.append(f"{alias}.{ident(paper_col)} = {lit(target.paper)}")
    return parts


def _select_fields(schema: Schema, table: str, alias: str) -> str:
    id_col = _require_col(schema, table, ID_ALIASES, "id")
    question = _require_col(schema, table, QUESTION_ALIASES, "question number")
    fields = [
        f"{alias}.{ident(id_col)} AS `id`",
        f"{alias}.{ident(question)} AS `question_no`",
    ]
    seen = {id_col, question}
    for aliases, output in (
        (YEAR_LABEL_ALIASES, "year_label"),
        (YEAR_KEY_ALIASES, "year_key"),
        (RAW_ALIASES, "raw_cell"),
        (PAPER_COL_ALIASES, "paper"),
        (SYLLABUS_ALIASES, "syllabus"),
    ):
        column = schema.pick(table, aliases)
        if column is None or column in seen:
            continue
        seen.add(column)
        fields.append(f"{alias}.{ident(column)} AS `{output}`")
    return ", ".join(fields)


def question_sql(schema: Schema, target: Target, kind: str) -> str:
    table, _link, _units = _table_for(target, kind)
    _require_table(schema, table)
    filters = _common_filters(schema, table, "s", target, question=True)
    return (
        f"SELECT {_select_fields(schema, table, 's')} "
        f"FROM {ident(table)} s WHERE " + " AND ".join(filters)
    )


def _unit_compare(family: str, left: str, right: str) -> str:
    if family == "pm":
        return f"{left} COLLATE utf8mb4_bin = {right} COLLATE utf8mb4_bin"
    return f"{left} = {right}"


def _unit_literal(family: str, code: str) -> str:
    if family != "pm" and code.isdigit():
        return str(int(code))
    return lit(code)


def links_sql(schema: Schema, target: Target, kind: str, parent_id: int) -> str:
    _table, link, catalogue = _table_for(target, kind)
    _require_table(schema, link)
    if catalogue is None or not schema.has_table(catalogue):
        raise RouteError(503, "missing_table", f"unit catalogue for {kind} is missing")
    parent_aliases = MC_LINK_ALIASES if kind == "mc" else SQ_LINK_ALIASES
    parent = _require_col(schema, link, parent_aliases, "question id")
    unit = _require_col(schema, link, UNIT_ALIASES, "unit code")
    catalogue_unit = _require_col(schema, catalogue, UNIT_ALIASES, "unit code")
    position = schema.pick(link, POSITION_ALIASES)
    short = schema.pick(catalogue, SHORT_ALIASES)
    name = schema.pick(catalogue, NAME_ALIASES)
    link_syllabus = schema.pick(link, SYLLABUS_ALIASES)
    catalogue_syllabus = schema.pick(catalogue, SYLLABUS_ALIASES)
    fields = [
        f"u.{ident(position)} AS `position`" if position else "NULL AS `position`",
        f"u.{ident(unit)} AS `unit_code`",
        f"cat.{ident(short)} AS `short_name`" if short else "NULL AS `short_name`",
        f"cat.{ident(name)} AS `name`" if name else "NULL AS `name`",
    ]
    join = _unit_compare(target.family, f"cat.{ident(catalogue_unit)}", f"u.{ident(unit)}")
    if link_syllabus and catalogue_syllabus:
        join += f" AND cat.{ident(catalogue_syllabus)} = u.{ident(link_syllabus)}"
    where = [f"u.{ident(parent)} = {lit(parent_id)}"]
    if target.syllabus is not None and link_syllabus is not None:
        where.append(f"u.{ident(link_syllabus)} = {lit(target.syllabus)}")
    order = f"u.{ident(position)}" if position else f"u.{ident(unit)}"
    return (
        f"SELECT {', '.join(fields)} FROM {ident(link)} u "
        f"LEFT JOIN {ident(catalogue)} cat ON {join} "
        f"WHERE {' AND '.join(where)} ORDER BY {order}"
    )


def qtypes_sql(schema: Schema) -> str | None:
    table = "analyse_unit_qtypes"
    if not schema.has_table(table):
        return None
    unit = _require_col(schema, table, UNIT_ALIASES, "unit code")
    qtype = _require_col(schema, table, QTYPE_ALIASES, "question type")
    return (
        f"SELECT {ident(unit)} AS `unit_code`, {ident(qtype)} AS `qtype` "
        f"FROM {ident(table)}"
    )


def catalogue_sql(schema: Schema, target: Target, syllabus: str | None) -> str:
    _table, _link, catalogue = _table_for(target, "sq" if target.family != "core" else "sq")
    if catalogue is None:
        raise RouteError(503, "missing_table", "unit catalogue is missing")
    _require_table(schema, catalogue)
    unit = _require_col(schema, catalogue, UNIT_ALIASES, "unit code")
    short = schema.pick(catalogue, SHORT_ALIASES)
    name = schema.pick(catalogue, NAME_ALIASES)
    syllabus_col = schema.pick(catalogue, SYLLABUS_ALIASES)
    fields = [f"cat.{ident(unit)} AS `unit_code`"]
    fields.append(f"cat.{ident(short)} AS `short_name`" if short else "NULL AS `short_name`")
    fields.append(f"cat.{ident(name)} AS `name`" if name else "NULL AS `name`")
    if syllabus_col:
        fields.append(f"cat.{ident(syllabus_col)} AS `syllabus`")
    sql = f"SELECT {', '.join(fields)} FROM {ident(catalogue)} cat"
    if syllabus is not None and syllabus_col is not None:
        sql += f" WHERE cat.{ident(syllabus_col)} = {lit(syllabus)}"
    return sql


def questions_for_units_sql(schema: Schema, target: Target, syllabus: str | None) -> str:
    table, link, catalogue = _table_for(target, "sq")
    _require_table(schema, table)
    _require_table(schema, link)
    parent = _require_col(schema, link, SQ_LINK_ALIASES, "question id")
    id_col = _require_col(schema, table, ID_ALIASES, "id")
    unit = _require_col(schema, link, UNIT_ALIASES, "unit code")
    filters = _common_filters(
        schema,
        table,
        "s",
        Target(**{**target.__dict__, "syllabus": syllabus}),
        question=False,
    )
    if target.unit_code is not None:
        filters.append(
            _unit_compare(target.family, f"u.{ident(unit)}", _unit_literal(target.family, target.unit_code))
        )
    link_syllabus = schema.pick(link, SYLLABUS_ALIASES)
    if syllabus is not None and link_syllabus is not None:
        filters.append(f"u.{ident(link_syllabus)} = {lit(syllabus)}")
    where = f" WHERE {' AND '.join(filters)}" if filters else ""
    return (
        f"SELECT {_select_fields(schema, table, 's')}, u.{ident(unit)} AS `unit_code`, "
        f"u.{ident(parent)} AS `link_parent` "
        f"FROM {ident(table)} s "
        f"INNER JOIN {ident(link)} u ON u.{ident(parent)} = s.{ident(id_col)} "
        f"{where}"
    )


def gap_question_sql(schema: Schema, target: Target, syllabus: str | None) -> str:
    scoped = Target(**{**target.__dict__, "syllabus": syllabus, "question_no": None})
    table, _link, _units = _table_for(scoped, "sq" if scoped.family != "core" else (scoped.kind or "sq"))
    _require_table(schema, table)
    filters = _common_filters(schema, table, "s", scoped, question=False)
    where = f" WHERE {' AND '.join(filters)}" if filters else ""
    return f"SELECT {_select_fields(schema, table, 's')} FROM {ident(table)} s{where}"


def unlinked_sql(schema: Schema, target: Target, kind: str, syllabus: str | None) -> str:
    scoped = Target(**{**target.__dict__, "syllabus": syllabus})
    table, link, _units = _table_for(scoped, kind)
    _require_table(schema, table)
    _require_table(schema, link)
    parent_aliases = MC_LINK_ALIASES if kind == "mc" else SQ_LINK_ALIASES
    parent = _require_col(schema, link, parent_aliases, "question id")
    id_col = _require_col(schema, table, ID_ALIASES, "id")
    filters = _common_filters(schema, table, "s", scoped, question=False)
    link_syllabus = schema.pick(link, SYLLABUS_ALIASES)
    join = f"u.{ident(parent)} = s.{ident(id_col)}"
    if syllabus is not None and link_syllabus is not None:
        join += f" AND u.{ident(link_syllabus)} = {lit(syllabus)}"
    where = " AND ".join(filters + [f"u.{ident(parent)} IS NULL"])
    return (
        f"SELECT {_select_fields(schema, table, 's')} FROM {ident(table)} s "
        f"LEFT JOIN {ident(link)} u ON {join} WHERE {where}"
    )


def unused_units_sql(schema: Schema, target: Target, syllabus: str | None) -> str:
    _table, link, catalogue = _table_for(target, "sq")
    if catalogue is None:
        raise RouteError(503, "missing_table", "unit catalogue is missing")
    _require_table(schema, catalogue)
    _require_table(schema, link)
    unit = _require_col(schema, catalogue, UNIT_ALIASES, "unit code")
    link_unit = _require_col(schema, link, UNIT_ALIASES, "unit code")
    syllabus_col = schema.pick(catalogue, SYLLABUS_ALIASES)
    link_syllabus = schema.pick(link, SYLLABUS_ALIASES)
    compare = _unit_compare(target.family, f"u.{ident(link_unit)}", f"cat.{ident(unit)}")
    exists = f"SELECT 1 FROM {ident(link)} u WHERE {compare}"
    if syllabus is not None and link_syllabus is not None and syllabus_col is not None:
        exists += f" AND u.{ident(link_syllabus)} = cat.{ident(syllabus_col)}"
    where = []
    if syllabus is not None and syllabus_col is not None:
        where.append(f"cat.{ident(syllabus_col)} = {lit(syllabus)}")
    where.append(f"NOT EXISTS ({exists})")
    if target.family == "core" and schema.has_table("analyse_mc_units"):
        mc_unit = _require_col(schema, "analyse_mc_units", UNIT_ALIASES, "unit code")
        mc_compare = f"m.{ident(mc_unit)} = cat.{ident(unit)}"
        where.append(
            f"NOT EXISTS (SELECT 1 FROM `analyse_mc_units` m WHERE {mc_compare})"
        )
    return (
        f"SELECT cat.{ident(unit)} AS `unit_code` FROM {ident(catalogue)} cat "
        f"WHERE {' AND '.join(where)}"
    )


def content_probe(schema: Schema) -> dict[str, str | None]:
    table = "content_blocks"
    if not schema.has_table(table):
        return {"key": None, "text": None, "key_sql": None, "marker_sql": None}
    key = schema.pick(table, BLOCK_KEY_ALIASES)
    text = schema.pick(table, BLOCK_TEXT_ALIASES)
    key_sql = None
    marker_sql = None
    if key is not None:
        key_sql = (
            f"SELECT b.{ident(key)} AS `block_key` FROM {ident(table)} b "
            f"WHERE b.{ident(key)} IS NOT NULL"
        )
    if text is not None:
        marker_sql = (
            f"SELECT b.{ident(text)} AS `body` FROM {ident(table)} b "
            f"WHERE b.{ident(text)} LIKE '%<!-- hoksi:%:solution -->%'"
        )
    return {"key": key, "text": text, "key_sql": key_sql, "marker_sql": marker_sql}


def solutions_sql(schema: Schema, target: Target) -> str | None:
    if target.solutions_mode != "content" or not target.question_slug or not target.paper_slug:
        return None
    probe = content_probe(schema)
    if probe["key"] is None and probe["text"] is None:
        return None
    table = "content_blocks"
    predicates = []
    if probe["key"] is not None:
        keys = [lit(f"{target.question_slug}:{lang}") for lang in LANGS]
        predicates.append(f"b.{ident(probe['key'])} IN ({', '.join(keys)})")
    question = target.question_no
    if probe["text"] is not None and question is not None:
        for lang in LANGS:
            marker = f"<!-- hoksi:{target.paper_slug}:q{question}:{lang}:solution -->"
            predicates.append(f"b.{ident(probe['text'])} LIKE {lit('%' + marker + '%')}")
    if not predicates:
        return None
    fields = []
    if probe["text"] is not None:
        fields.append(f"b.{ident(probe['text'])} AS `body`")
    else:
        fields.append("NULL AS `body`")
    if probe["key"] is not None:
        fields.append(f"b.{ident(probe['key'])} AS `block_key`")
    else:
        fields.append("NULL AS `block_key`")
    lang = schema.pick(table, BLOCK_LANG_ALIASES)
    fields.append(f"b.{ident(lang)} AS `lang`" if lang else "NULL AS `lang`")
    join = ""
    if schema.has_table("solutions"):
        block_id = schema.pick(table, BLOCK_ID_ALIASES)
        solution_block = schema.pick("solutions", SOLUTION_BLOCK_ALIASES)
        sort_col = schema.pick("solutions", SOLUTION_SORT_ALIASES)
        if block_id and solution_block:
            join = (
                f" LEFT JOIN `solutions` s ON s.{ident(solution_block)} = "
                f"b.{ident(block_id)}"
            )
            fields.append(
                f"s.{ident(sort_col)} AS `sortorder`" if sort_col else "NULL AS `sortorder`"
            )
        else:
            fields.append("NULL AS `sortorder`")
    else:
        fields.append("NULL AS `sortorder`")
    return (
        f"SELECT {', '.join(fields)} FROM {ident(table)} b{join} "
        f"WHERE {' OR '.join(predicates)}"
    )


def lookup_plan(schema: Schema, target: Target) -> list[str]:
    if target.question_no is None or not target.year_labels:
        raise RouteError(400, "missing_param", "lookup needs a question and a year or slug")
    statements = []
    for kind in _kinds_for(target, schema):
        statements.append(question_sql(schema, target, kind))
        statements.append(links_sql(schema, target, kind, 1))
    if target.family == "core":
        qtypes = qtypes_sql(schema)
        if qtypes:
            statements.append(qtypes)
    solved = solutions_sql(schema, target)
    if solved:
        statements.append(solved)
    return statements


def units_plan(schema: Schema, target: Target) -> list[str]:
    syllabi = _syllabi(target)
    statements = []
    for syllabus in syllabi:
        statements.append(catalogue_sql(schema, target, syllabus))
        if target.embed_questions and target.family != "core":
            statements.append(questions_for_units_sql(schema, target, syllabus))
        elif target.embed_questions and target.family == "core":
            for kind in _kinds_for(target, schema):
                statements.append(_core_questions_sql(schema, target, kind))
    if target.family == "core":
        qtypes = qtypes_sql(schema)
        if qtypes:
            statements.append(qtypes)
    return statements


def _core_questions_sql(schema: Schema, target: Target, kind: str) -> str:
    table, link, _units = _table_for(target, kind)
    _require_table(schema, table)
    _require_table(schema, link)
    parent_aliases = MC_LINK_ALIASES if kind == "mc" else SQ_LINK_ALIASES
    parent = _require_col(schema, link, parent_aliases, "question id")
    id_col = _require_col(schema, table, ID_ALIASES, "id")
    unit = _require_col(schema, link, UNIT_ALIASES, "unit code")
    filters = _common_filters(schema, table, "s", target, question=False)
    if target.unit_code is not None:
        filters.append(f"u.{ident(unit)} = {_unit_literal('core', target.unit_code)}")
    where = f" WHERE {' AND '.join(filters)}" if filters else ""
    return (
        f"SELECT {_select_fields(schema, table, 's')}, u.{ident(unit)} AS `unit_code` "
        f"FROM {ident(table)} s INNER JOIN {ident(link)} u ON u.{ident(parent)} = s.{ident(id_col)}"
        f"{where}"
    )


def gaps_plan(schema: Schema, target: Target) -> list[str]:
    statements = []
    wants_content = False
    for syllabus in _syllabi(target):
        mode = _mode_for(target, syllabus)
        kinds = _kinds_for(target, schema) if target.family == "core" else ["sq"]
        for kind in kinds:
            if target.family != "core" and kind != "sq":
                continue
            statements.append(unlinked_sql(schema, target, kind, syllabus))
        if target.family != "core" and mode == "content":
            statements.append(gap_question_sql(schema, target, syllabus))
            wants_content = True
        statements.append(unused_units_sql(schema, target, syllabus))
    if wants_content:
        probe = content_probe(schema)
        if probe["key_sql"]:
            statements.append(probe["key_sql"])
        elif probe["marker_sql"]:
            statements.append(probe["marker_sql"])
    return statements


def plan_statements(path: str, params: dict[str, str], schema: Schema) -> list[str]:
    target = resolve_target(params)
    if path == "/analyse/lookup":
        return lookup_plan(schema, target)
    if path == "/analyse/units":
        return units_plan(schema, target)
    if path == "/analyse/gaps":
        return gaps_plan(schema, target)
    raise RouteError(404, "not_found", f"unknown path {path}")


def _syllabi(target: Target) -> list[str | None]:
    if target.band == "all":
        return ["dse", "ms"]
    return [target.syllabus]


def _mode_for(target: Target, syllabus: str | None) -> str:
    if syllabus == "ms" or syllabus == "pm":
        return "blocked"
    if syllabus in {"dse", "m2"}:
        return "content"
    return target.solutions_mode


def _as_int(value: object) -> int | None:
    if value is None or value == "":
        return None
    return int(str(value))


def _text(value: object) -> str | None:
    if value is None:
        return None
    return str(value)


def unit_sort_key(code: str) -> tuple[int, str]:
    match = re.match(r"^(\d+)(.*)$", code)
    if match:
        return (int(match.group(1)), match.group(2))
    return (10**9, code)


def question_sort_key(row: dict) -> tuple:
    label = str(row.get("year_label") or "")
    upper = label.upper()
    if upper == "SP":
        year, tie = 2011, -1
    elif upper == "PP":
        year, tie = 2022, -1
    elif upper == "ON":
        year, tie = 2012, -2
    else:
        year, tie = calendar_year(label) or 0, 0
    key = str(row.get("year_key") or "")
    occurrence = 1 if key.endswith("#T") else 2 if key.endswith("#U") else 0
    paper = _as_int(row.get("paper")) or 0
    question = _as_int(row.get("question_no")) or 0
    return (year, tie, occurrence, paper, question)


def _present_units(rows: list[dict], qtypes: dict[str, list[str]] | None) -> list[dict]:
    units = []
    for row in rows:
        code = _text(row.get("unit_code"))
        if code is None:
            continue
        unit = {
            "position": _as_int(row.get("position")),
            "unit_code": code,
            "short_name": _text(row.get("short_name")),
            "name": _text(row.get("name")),
        }
        if qtypes is not None:
            unit["qtypes"] = qtypes.get(code, [])
        units.append(unit)
    return units


def _qtype_map(rows: list[dict]) -> dict[str, list[str]]:
    grouped: dict[str, list[str]] = {}
    for row in rows:
        code = _text(row.get("unit_code"))
        qtype = _text(row.get("qtype"))
        if code is None or qtype is None:
            continue
        grouped.setdefault(code, []).append(qtype)
    return grouped


def _display_paper(kind: str, row: dict, target: Target) -> int | None:
    paper = _as_int(row.get("paper"))
    if paper is not None:
        return paper
    if target.family == "core":
        return 1 if kind == "sq" else 2
    return target.paper


def _present_question(kind: str, row: dict, units: list[dict], target: Target) -> dict:
    return {
        "id": _as_int(row.get("id")),
        "kind": kind,
        "paper": _display_paper(kind, row, target),
        "band": _text(row.get("syllabus")) or target.band,
        "year_label": _text(row.get("year_label")),
        "year_key": _text(row.get("year_key")),
        "question_no": _as_int(row.get("question_no")),
        "raw_cell": _text(row.get("raw_cell")),
        "units": units,
    }


def _prefer_rows(rows: list[dict], labels: tuple[str, ...]) -> list[dict]:
    if len(rows) <= 1 or not labels:
        return rows
    for label in labels:
        chosen = [row for row in rows if str(row.get("year_label")) == label]
        if chosen:
            return chosen
    return rows


def strip_marker(text: str) -> str:
    return re.sub(r"<!-- hoksi:[^>]*-->\s*", "", text, count=1).strip()


def _lang_from_row(row: dict) -> str | None:
    key = _text(row.get("block_key")) or ""
    match = KEY_RE.fullmatch(key)
    if match:
        return match.group(2)
    body = _text(row.get("body")) or ""
    marker = MARKER_RE.search(body)
    if marker:
        return marker.group(3)
    lang = _text(row.get("lang"))
    if lang in LANGS:
        return lang
    sortorder = _as_int(row.get("sortorder"))
    if sortorder == 1:
        return "zh-HK"
    if sortorder == 2:
        return "en"
    return None


def _present_solutions(target: Target, rows: list[dict] | None, schema: Schema) -> dict:
    if target.solutions_mode == "blocked":
        reason = NOTE_MS if target.band == "ms" or target.syllabus == "ms" else NOTE_PM
        return {"status": "blocked", "reason": reason}
    if target.solutions_mode == "not_served":
        return {"status": "not_served", "reason": NOTE_CORE}
    if target.solutions_mode != "content":
        return {"status": "not_served", "reason": NOTE_CORE}
    if target.paper_slug is None or target.question_slug is None:
        return {"status": "unslugged", "reason": NOTE_ON}
    probe = content_probe(schema)
    if probe["key"] is None and probe["text"] is None:
        if not schema.has_table("content_blocks"):
            return {"status": "not_installed", "reason": NOTE_MISSING_BLOCKS}
        return {"status": "unreadable", "reason": NOTE_UNREADABLE}
    items = []
    seen: set[str] = set()
    for row in rows or []:
        lang = _lang_from_row(row)
        if lang is None or lang in seen:
            continue
        seen.add(lang)
        body = _text(row.get("body")) or ""
        items.append(
            {
                "lang": lang,
                "sortorder": _as_int(row.get("sortorder")),
                "text": strip_marker(body),
            }
        )
    items.sort(key=lambda item: LANGS.index(item["lang"]) if item["lang"] in LANGS else 9)
    status = "ok" if items else "missing"
    return {
        "status": status,
        "paper_slug": target.paper_slug,
        "question_slug": target.question_slug,
        "items": items,
    }


def _solution_index(rows: list[dict], *, markers: bool) -> set[tuple[str, str]]:
    found: set[tuple[str, str]] = set()
    for row in rows:
        if markers:
            body = _text(row.get("body")) or ""
            for match in MARKER_RE.finditer(body):
                paper, question, lang = match.group(1), match.group(2), match.group(3)
                found.add((f"{paper}-q{question}", lang))
            continue
        key = _text(row.get("block_key")) or ""
        match = KEY_RE.fullmatch(key)
        if match:
            found.add((match.group(1), match.group(2)))
    return found


class Database:
    def query(self, sql: str) -> list[dict]:
        raise NotImplementedError


def run_lookup(target: Target, schema: Schema, db: Database) -> tuple[int, dict]:
    if target.question_no is None or not target.year_labels:
        raise RouteError(400, "missing_param", "lookup needs a question and a year or slug")
    qtypes = None
    if target.family == "core":
        statement = qtypes_sql(schema)
        qtypes = _qtype_map(db.query(statement)) if statement else {}
    results = []
    for kind in _kinds_for(target, schema):
        rows = _prefer_rows(db.query(question_sql(schema, target, kind)), target.year_labels)
        for row in rows:
            parent = _as_int(row.get("id"))
            if parent is None:
                continue
            link_rows = db.query(links_sql(schema, target, kind, parent))
            units = _present_units(link_rows, qtypes if target.family == "core" else None)
            results.append(_present_question(kind, row, units, target))
    if not results:
        raise RouteError(404, "not_found", "no analyse row for that question")
    payload: dict = {
        "subject": target.subject,
        "band": target.band if target.band != "all" else (results[0].get("band") or target.band),
        "question_no": target.question_no,
        "results": results,
    }
    # One kind (the usual compulsory call, and every M1/M2 call) also exposes
    # the row at the top level so a client can read `units` without unwrapping.
    if len(results) == 1:
        only = results[0]
        payload["kind"] = only["kind"]
        payload["paper"] = only["paper"]
        payload["year_label"] = only["year_label"]
        payload["year_key"] = only["year_key"]
        payload["raw_cell"] = only["raw_cell"]
        payload["units"] = only["units"]
    if target.solutions_mode == "omit":
        return 200, payload
    statement = solutions_sql(schema, target)
    rows = db.query(statement) if statement else None
    if statement is None and target.solutions_mode == "content":
        payload["solutions"] = _present_solutions(target, [], schema)
    else:
        payload["solutions"] = _present_solutions(target, rows, schema)
    return 200, payload


def _catalogue_units(rows: list[dict], qtypes: dict[str, list[str]] | None, band: str | None) -> list[dict]:
    units = []
    for row in rows:
        code = _text(row.get("unit_code"))
        if code is None:
            continue
        unit = {
            "unit_code": code,
            "short_name": _text(row.get("short_name")),
            "name": _text(row.get("name")),
            "band": _text(row.get("syllabus")) or band,
        }
        if qtypes is not None:
            unit["qtypes"] = qtypes.get(code, [])
        units.append(unit)
    units.sort(key=lambda unit: unit_sort_key(unit["unit_code"]))
    return units


def _attach_questions(units: list[dict], rows: list[dict], kind: str, target: Target) -> None:
    by_code: dict[str, list[dict]] = {}
    for row in rows:
        code = _text(row.get("unit_code"))
        if code is None:
            continue
        by_code.setdefault(code, []).append(
            {
                "id": _as_int(row.get("id")),
                "kind": kind,
                "paper": _display_paper(kind, row, target),
                "year_label": _text(row.get("year_label")),
                "year_key": _text(row.get("year_key")),
                "question_no": _as_int(row.get("question_no")),
                "raw_cell": _text(row.get("raw_cell")),
                "position": _as_int(row.get("position")),
            }
        )
    for unit in units:
        questions = list(unit.get("questions") or [])
        questions.extend(by_code.get(unit["unit_code"], []))
        questions.sort(key=question_sort_key)
        unit["questions"] = questions


def run_units(target: Target, schema: Schema, db: Database) -> tuple[int, dict]:
    qtypes = None
    if target.family == "core":
        statement = qtypes_sql(schema)
        qtypes = _qtype_map(db.query(statement)) if statement else {}
    units: list[dict] = []
    for syllabus in _syllabi(target):
        rows = db.query(catalogue_sql(schema, target, syllabus))
        band = syllabus or target.band
        found = _catalogue_units(rows, qtypes if target.family == "core" else None, band)
        if target.unit_code is not None:
            found = [unit for unit in found if unit["unit_code"] == target.unit_code]
        if target.embed_questions:
            if target.family == "core":
                for kind in _kinds_for(target, schema):
                    _attach_questions(found, db.query(_core_questions_sql(schema, target, kind)), kind, target)
            else:
                _attach_questions(
                    found,
                    db.query(questions_for_units_sql(schema, target, syllabus)),
                    "sq",
                    target,
                )
            if target.year_labels:
                found = [unit for unit in found if unit.get("questions")]
        units.extend(found)
    return 200, {"subject": target.subject, "band": target.band, "units": units}


def _row_brief(kind: str, row: dict, target: Target) -> dict:
    return {
        "kind": kind,
        "paper": _display_paper(kind, row, target),
        "band": _text(row.get("syllabus")) or target.band,
        "year_label": _text(row.get("year_label")),
        "year_key": _text(row.get("year_key")),
        "question_no": _as_int(row.get("question_no")),
        "raw_cell": _text(row.get("raw_cell")),
    }


def _missing_solutions(
    question_rows: list[dict],
    found: set[tuple[str, str]],
    subject: str,
) -> tuple[list[dict], list[dict]]:
    missing = []
    unslugged = []
    for row in question_rows:
        label = _text(row.get("year_label")) or ""
        question_no = _as_int(row.get("question_no"))
        if question_no is None:
            continue
        labels = canonical_labels((label,)) if label else ()
        paper_slug = _paper_slug(subject, labels)
        brief = {
            "year_label": label or None,
            "year_key": _text(row.get("year_key")),
            "question_no": question_no,
            "paper": _as_int(row.get("paper")),
        }
        if paper_slug is None:
            unslugged.append(brief)
            continue
        question_slug = f"{paper_slug}-q{question_no}"
        absent = [lang for lang in LANGS if (question_slug, lang) not in found]
        if not absent:
            continue
        brief["paper_slug"] = paper_slug
        brief["question_slug"] = question_slug
        brief["missing_langs"] = absent
        missing.append(brief)
    missing.sort(key=question_sort_key)
    unslugged.sort(key=question_sort_key)
    return missing, unslugged


def _load_solution_index(schema: Schema, db: Database) -> tuple[str, set[tuple[str, str]]]:
    probe = content_probe(schema)
    if not schema.has_table("content_blocks"):
        return "not_installed", set()
    if probe["key_sql"]:
        rows = db.query(probe["key_sql"])
        if rows:
            return "ok", _solution_index(rows, markers=False)
        if probe["marker_sql"]:
            return "ok", _solution_index(db.query(probe["marker_sql"]), markers=True)
        return "ok", set()
    if probe["marker_sql"]:
        return "ok", _solution_index(db.query(probe["marker_sql"]), markers=True)
    return "unreadable", set()


def _gap_section(
    target: Target,
    schema: Schema,
    db: Database,
    syllabus: str | None,
    found: set[tuple[str, str]] | None,
    index_state: str | None,
) -> dict:
    mode = _mode_for(target, syllabus)
    kinds = _kinds_for(target, schema) if target.family == "core" else ["sq"]
    missing_links = []
    for kind in kinds:
        rows = db.query(unlinked_sql(schema, target, kind, syllabus))
        missing_links.extend(_row_brief(kind, row, target) for row in rows)
    unused_rows = db.query(unused_units_sql(schema, target, syllabus))
    unused = [_text(row.get("unit_code")) for row in unused_rows]
    unused = [code for code in unused if code is not None]
    unused.sort(key=unit_sort_key)
    band = syllabus or target.band
    section: dict = {
        "band": band,
        "missing_unit_links": missing_links,
        "unused_units": unused,
    }
    if mode == "blocked":
        section["solutions"] = "blocked"
        section["solutions_note"] = NOTE_MS if band == "ms" else NOTE_PM
        return section
    if mode != "content":
        section["solutions"] = "not_served" if target.solutions_mode == "not_served" else "core_path"
        if target.family == "core":
            section["solutions_note"] = NOTE_CORE
        return section
    if index_state == "not_installed":
        section["solutions"] = "not_installed"
        section["solutions_note"] = NOTE_MISSING_BLOCKS
        return section
    if index_state == "unreadable":
        section["solutions"] = "unreadable"
        section["solutions_note"] = NOTE_UNREADABLE
        return section
    subject = "m1" if syllabus == "dse" else "m2"
    questions = db.query(gap_question_sql(schema, target, syllabus))
    missing, unslugged = _missing_solutions(questions, found or set(), subject)
    section["solutions"] = "available"
    section["missing_solutions"] = missing
    section["unslugged"] = unslugged
    return section


def run_gaps(target: Target, schema: Schema, db: Database) -> tuple[int, dict]:
    syllabi = _syllabi(target)
    needs_index = any(_mode_for(target, syllabus) == "content" for syllabus in syllabi)
    found: set[tuple[str, str]] | None = None
    index_state = None
    if needs_index:
        index_state, found = _load_solution_index(schema, db)
    sections = [
        _gap_section(target, schema, db, syllabus, found, index_state) for syllabus in syllabi
    ]
    if len(sections) == 1:
        section = sections[0]
        return 200, {"subject": target.subject, "band": target.band, **section}
    return 200, {"subject": target.subject, "band": "all", "syllabi": sections}


def dispatch(path: str, params: dict[str, str], schema: Schema, db: Database) -> tuple[int, dict]:
    path = path.rstrip("/") or "/"
    if path not in {"/analyse/lookup", "/analyse/units", "/analyse/gaps"}:
        raise RouteError(404, "not_found", f"unknown path {path}")
    target = resolve_target(params)
    if path == "/analyse/lookup":
        return run_lookup(target, schema, db)
    if path == "/analyse/units":
        return run_units(target, schema, db)
    return run_gaps(target, schema, db)


def params_from_query(query: str) -> dict[str, str]:
    parsed = parse_qs(query, keep_blank_values=False)
    values: dict[str, str] = {}
    for key, items in parsed.items():
        if items and items[0].strip():
            values[key] = items[0].strip()
    return values


_XSI_NIL = "{http://www.w3.org/2001/XMLSchema-instance}nil"


def parse_mysql_xml(text: str) -> list[dict[str, str | None]]:
    stripped = text.strip()
    if not stripped:
        return []
    start = stripped.find("<resultset")
    if start < 0:
        raise RuntimeError(stripped[:500])
    root = ET.fromstring(stripped[start:])
    rows: list[dict[str, str | None]] = []
    for row in root.findall("row"):
        item: dict[str, str | None] = {}
        for field in row.findall("field"):
            name = field.attrib.get("name") or ""
            nil = field.attrib.get(_XSI_NIL) or field.attrib.get("nil")
            if nil == "true":
                item[name] = None
            else:
                item[name] = field.text if field.text is not None else ""
        rows.append(item)
    return rows


class MysqlCli(Database):
    def query(self, sql: str) -> list[dict]:
        statement = sql.strip().rstrip(";")
        if ";" in statement:
            raise RuntimeError("refusing multiple statements")
        return parse_mysql_xml(self._run(statement))

    def columns(self, table: str) -> dict[str, str]:
        if not IDENT_RE.fullmatch(table):
            raise RuntimeError(f"refusing SQL identifier {table!r}")
        rows = self.query(f"SHOW COLUMNS FROM `{table}`")
        found: dict[str, str] = {}
        for row in rows:
            name = row.get("Field") or row.get("field")
            if not name:
                continue
            found[str(name)] = str(row.get("Type") or row.get("type") or "")
        return found

    def _run(self, sql: str) -> str:
        mysql = os.environ.get("MYSQL_BIN", "mysql")
        database = os.environ.get("MYSQL_DATABASE", "")
        if not database:
            raise RuntimeError(
                "Set MYSQL_DATABASE (and MYSQL_HOST, MYSQL_PORT, MYSQL_USER, MYSQL_PWD) "
                "on the machine that hosts alphaeqt."
            )
        command = [
            mysql,
            "--xml",
            "--batch",
            "--connect-timeout=10",
            "--default-character-set=utf8mb4",
            "-h",
            os.environ.get("MYSQL_HOST", "127.0.0.1"),
            "-P",
            os.environ.get("MYSQL_PORT", "3306"),
            "-u",
            os.environ.get("MYSQL_USER", "root"),
        ]
        defaults = os.environ.get("MYSQL_DEFAULTS_FILE")
        if defaults:
            command.append(f"--defaults-extra-file={defaults}")
        command.extend(["-e", sql, database])
        completed = subprocess.run(command, text=True, capture_output=True, check=False)
        if completed.returncode != 0:
            message = (completed.stderr or completed.stdout or "").strip()
            if (
                "ERROR 1146" in message
                or "doesn't exist" in message
                or "does not exist" in message
            ):
                raise MissingTable(message)
            raise RuntimeError(message or f"mysql exited {completed.returncode}")
        return completed.stdout


def load_schema(db: MysqlCli) -> Schema:
    names = (
        *CORE_TABLES,
        *M1_TABLES,
        *PM_TABLES,
        "content_blocks",
        "solutions",
        "papers",
        "questions",
    )
    tables: dict[str, dict[str, str]] = {}
    for name in names:
        try:
            tables[name] = db.columns(name)
        except MissingTable:
            continue
    return Schema(tables)


def json_bytes(payload: dict) -> bytes:
    return json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")


def cors_headers() -> list[tuple[str, str]]:
    return [
        ("Access-Control-Allow-Origin", "*"),
        ("Access-Control-Allow-Methods", "GET, OPTIONS"),
        ("Access-Control-Allow-Headers", "Content-Type"),
        ("Cache-Control", "no-store"),
    ]


def build_app(schema: Schema, db: Database) -> Callable:
    def app(environ, start_response):
        method = (environ.get("REQUEST_METHOD") or "GET").upper()
        headers = [("Content-Type", "application/json; charset=utf-8"), *cors_headers()]
        if method == "OPTIONS":
            start_response("204 No Content", cors_headers())
            return [b""]
        if method != "GET":
            body = json_bytes({"error": "method_not_allowed", "message": "GET only"})
            start_response("405 Method Not Allowed", headers)
            return [body]
        path = environ.get("PATH_INFO") or "/"
        params = params_from_query(environ.get("QUERY_STRING") or "")
        try:
            status, payload = dispatch(path, params, schema, db)
        except RouteError as exc:
            status, payload = exc.status, exc.payload()
        except Exception:
            traceback.print_exc()
            status, payload = 500, {"error": "server", "message": "internal error"}
        start_response(f"{status} {'OK' if status == 200 else 'ERROR'}", headers)
        return [json_bytes(payload)]

    return app


class _Handler(BaseHTTPRequestHandler):
    schema: Schema
    database: Database

    def do_GET(self) -> None:  # noqa: N802
        self._handle()

    def do_OPTIONS(self) -> None:  # noqa: N802
        self._handle()

    def do_POST(self) -> None:  # noqa: N802
        self._handle()

    def log_message(self, fmt: str, *args) -> None:
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _handle(self) -> None:
        parsed = urlparse(self.path)
        method = self.command.upper()
        if method == "OPTIONS":
            self._send(204, b"")
            return
        if method != "GET":
            self._send(405, json_bytes({"error": "method_not_allowed", "message": "GET only"}))
            return
        try:
            status, payload = dispatch(
                parsed.path,
                params_from_query(parsed.query),
                self.schema,
                self.database,
            )
        except RouteError as exc:
            status, payload = exc.status, exc.payload()
        except Exception:
            traceback.print_exc()
            status, payload = 500, {"error": "server", "message": "internal error"}
        self._send(status, json_bytes(payload))

    def _send(self, status: int, body: bytes) -> None:
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        for key, value in cors_headers():
            self.send_header(key, value)
        self.end_headers()
        if body and self.command != "HEAD":
            self.wfile.write(body)


def serve(host: str, port: int, schema: Schema, db: Database) -> None:
    class Handler(_Handler):
        pass

    Handler.schema = schema
    Handler.database = db
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"editorial analyse API on http://{host}:{port}", file=sys.stderr)
    server.serve_forever()


def _params_from_args(args: argparse.Namespace) -> dict[str, str]:
    values = {}
    for name in ("subject", "band", "slug", "year", "question", "kind", "paper", "unit", "include"):
        value = getattr(args, name)
        if value:
            values[name] = str(value)
    return values


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serve", action="store_true", help="Bind the HTTP server. Reads MYSQL_* like the seed scripts.")
    parser.add_argument("--plan", choices=("lookup", "units", "gaps"), help="Print SQL for one path and do not connect.")
    parser.add_argument("--host", default=os.environ.get("EDITORIAL_BIND", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("EDITORIAL_PORT", "8765")))
    parser.add_argument("--subject")
    parser.add_argument("--band")
    parser.add_argument("--slug")
    parser.add_argument("--year")
    parser.add_argument("--question")
    parser.add_argument("--kind", help="sq or mc. Compulsory paper 1 is sq, paper 2 is mc.")
    parser.add_argument("--paper")
    parser.add_argument("--unit")
    parser.add_argument("--include", help="Pass solutions to attach the core not_served note.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    params = _params_from_args(args)
    if args.plan:
        path = f"/analyse/{args.plan}"
        try:
            statements = plan_statements(path, params, assumed_schema())
            target = resolve_target(params)
        except RouteError as exc:
            print(f"{exc.code}: {exc.message}", file=sys.stderr)
            return 1
        print(f"subject={target.subject} band={target.band} solutions={target.solutions_mode}")
        print("\n".join(statements))
        return 0
    if args.serve:
        client = MysqlCli()
        schema = load_schema(client)
        serve(args.host, args.port, schema, client)
        return 0
    parser.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
