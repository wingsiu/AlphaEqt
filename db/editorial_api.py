#!/usr/bin/env python3
"""AlphaEqt editorial API — topics / papers / questions / content pages.

Writes go to remote MySQL (ans4u.me). Files stay on DiskStation / local imports;
this API only stores relative paths and markdown.

  DB_HOST=ans4u.me DB_USER=alpha DB_PASSWORD=… \\
    uvicorn editorial_api:app --host 127.0.0.1 --port 8505

Or: ./run_editorial_api.sh

Draft content pages share this process. ``POST /content/pages`` imports a
document as a draft page of atoms in one ``USE alphaeqt`` transaction.
Fetch, append, edit, publish, and the next draft version live under
``/content/pages/{slug}`` and call ``content_pages.py``. Analyse routes
on this app stay GET-only.

The stdlib Analyse planner (``--plan``, ``--serve`` on 127.0.0.1:8765)
is ``editorial_analyse_api.py``. It is not this module.
"""

from __future__ import annotations

import os
import re
from contextlib import contextmanager
from typing import Any, Callable, Iterator, Optional

import pymysql
from fastapi import FastAPI, HTTPException, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field
from pymysql.constants import CLIENT

import content_pages

DB_HOST = os.environ.get("DB_HOST", "ans4u.me")
DB_PORT = int(os.environ.get("DB_PORT", "3306"))
DB_USER = os.environ.get("DB_USER", "alpha")
DB_PASSWORD = os.environ.get("DB_PASSWORD") or os.environ.get("MYSQL_PWD", "")
DB_NAME = os.environ.get("DB_NAME", "alphaeqt")

app = FastAPI(title="AlphaEqt Editorial API", version="0.1.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@contextmanager
def db(*, multi: bool = False) -> Iterator[pymysql.connections.Connection]:
    if not DB_PASSWORD:
        raise HTTPException(503, "DB_PASSWORD / MYSQL_PWD not set")
    # Content-page scripts are one COM_QUERY (USE / START TRANSACTION / … /
    # COMMIT). MULTI_STATEMENTS has to be negotiated at handshake. Other
    # routes keep the default so a stray semicolon cannot run a second statement.
    client_flag = CLIENT.MULTI_STATEMENTS if multi else 0
    conn = pymysql.connect(
        host=DB_HOST,
        port=DB_PORT,
        user=DB_USER,
        password=DB_PASSWORD,
        database=DB_NAME,
        charset="utf8mb4",
        cursorclass=pymysql.cursors.DictCursor,
        autocommit=False,
        client_flag=client_flag,
    )
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


def _table_exists(cur: Any, name: str) -> bool:
    cur.execute(
        """
        SELECT COUNT(*) AS c FROM information_schema.TABLES
        WHERE TABLE_SCHEMA=%s AND TABLE_NAME=%s
        """,
        (DB_NAME, name),
    )
    row = cur.fetchone()
    return bool(row and int(row["c"]) > 0)


def ensure_schema(conn: pymysql.connections.Connection) -> None:
    """Add questions.paper_id + analyse_* tables if missing."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT COUNT(*) AS c FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA=%s AND TABLE_NAME='questions' AND COLUMN_NAME='paper_id'
            """,
            (DB_NAME,),
        )
        row = cur.fetchone()
        if row and int(row["c"]) == 0:
            cur.execute(
                """
                ALTER TABLE questions
                  ADD COLUMN paper_id INT NULL AFTER id,
                  ADD KEY questions_paper (paper_id),
                  ADD CONSTRAINT fk_questions_paper
                    FOREIGN KEY (paper_id) REFERENCES papers (id) ON DELETE SET NULL
                """
            )

        if not _table_exists(cur, "analyse_units"):
            cur.execute(
                """
                CREATE TABLE analyse_units (
                  unit SMALLINT NOT NULL,
                  name VARCHAR(128) NOT NULL,
                  notes VARCHAR(255) DEFAULT NULL,
                  PRIMARY KEY (unit)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )
        if not _table_exists(cur, "analyse_unit_qtypes"):
            cur.execute(
                """
                CREATE TABLE analyse_unit_qtypes (
                  unit SMALLINT NOT NULL,
                  qtype VARCHAR(32) NOT NULL,
                  sortorder TINYINT NOT NULL DEFAULT 0,
                  PRIMARY KEY (unit, qtype),
                  KEY analyse_unit_qtypes_qtype (qtype),
                  CONSTRAINT fk_analyse_uq_unit
                    FOREIGN KEY (unit) REFERENCES analyse_units (unit) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )
        if not _table_exists(cur, "analyse_mc"):
            cur.execute(
                """
                CREATE TABLE analyse_mc (
                  year_key CHAR(2) NOT NULL,
                  calendar_year SMALLINT NOT NULL,
                  qno SMALLINT NOT NULL,
                  unit_raw VARCHAR(32) NOT NULL,
                  PRIMARY KEY (year_key, qno),
                  KEY analyse_mc_year_qno (calendar_year, qno),
                  KEY analyse_mc_unit_raw (unit_raw)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )
        if not _table_exists(cur, "analyse_mc_units"):
            cur.execute(
                """
                CREATE TABLE analyse_mc_units (
                  year_key CHAR(2) NOT NULL,
                  qno SMALLINT NOT NULL,
                  unit SMALLINT NOT NULL,
                  sortorder TINYINT NOT NULL DEFAULT 0,
                  PRIMARY KEY (year_key, qno, unit),
                  KEY analyse_mc_units_unit (unit),
                  CONSTRAINT fk_analyse_mu_cell
                    FOREIGN KEY (year_key, qno)
                    REFERENCES analyse_mc (year_key, qno) ON DELETE CASCADE,
                  CONSTRAINT fk_analyse_mu_unit
                    FOREIGN KEY (unit) REFERENCES analyse_units (unit) ON DELETE RESTRICT
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )
        if not _table_exists(cur, "analyse_sq"):
            cur.execute(
                """
                CREATE TABLE analyse_sq (
                  year_key CHAR(2) NOT NULL,
                  calendar_year SMALLINT NOT NULL,
                  qno SMALLINT NOT NULL,
                  unit_raw VARCHAR(32) NOT NULL,
                  PRIMARY KEY (year_key, qno),
                  KEY analyse_sq_year_qno (calendar_year, qno),
                  KEY analyse_sq_unit_raw (unit_raw)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )
        if not _table_exists(cur, "analyse_sq_units"):
            cur.execute(
                """
                CREATE TABLE analyse_sq_units (
                  year_key CHAR(2) NOT NULL,
                  qno SMALLINT NOT NULL,
                  unit SMALLINT NOT NULL,
                  sortorder TINYINT NOT NULL DEFAULT 0,
                  PRIMARY KEY (year_key, qno, unit),
                  KEY analyse_sq_units_unit (unit),
                  CONSTRAINT fk_analyse_su_cell
                    FOREIGN KEY (year_key, qno)
                    REFERENCES analyse_sq (year_key, qno) ON DELETE CASCADE,
                  CONSTRAINT fk_analyse_su_unit
                    FOREIGN KEY (unit) REFERENCES analyse_units (unit) ON DELETE RESTRICT
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )

        if not _table_exists(cur, "mc_keys"):
            cur.execute(
                """
                CREATE TABLE mc_keys (
                  exam CHAR(3) NOT NULL COMMENT 'CE|DSE',
                  year SMALLINT NOT NULL,
                  qno SMALLINT NOT NULL,
                  answer CHAR(1) NOT NULL,
                  correct_pct TINYINT UNSIGNED DEFAULT NULL,
                  source VARCHAR(64) DEFAULT NULL,
                  PRIMARY KEY (exam, year, qno),
                  KEY mc_keys_year (year, exam)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )

        if not _table_exists(cur, "sq_keys"):
            cur.execute(
                """
                CREATE TABLE sq_keys (
                  exam CHAR(3) NOT NULL COMMENT 'CE|DSE',
                  year SMALLINT NOT NULL,
                  qno SMALLINT NOT NULL,
                  part VARCHAR(16) NOT NULL DEFAULT '' COMMENT 'a|b|b.i|… empty if whole Q',
                  answer TEXT NOT NULL,
                  source VARCHAR(64) DEFAULT NULL,
                  PRIMARY KEY (exam, year, qno, part),
                  KEY sq_keys_year (year, exam)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )

        if not _table_exists(cur, "question_topic"):
            cur.execute(
                """
                CREATE TABLE question_topic (
                  question_id INT NOT NULL,
                  topic_id INT NOT NULL,
                  sortorder TINYINT NOT NULL DEFAULT 0,
                  PRIMARY KEY (question_id, topic_id),
                  KEY question_topic_topic (topic_id),
                  CONSTRAINT fk_qtopic_question
                    FOREIGN KEY (question_id) REFERENCES questions (id) ON DELETE CASCADE,
                  CONSTRAINT fk_qtopic_topic
                    FOREIGN KEY (topic_id) REFERENCES topics (id) ON DELETE CASCADE
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
                """
            )


def calendar_year_from_slug(slug: str) -> Optional[int]:
    import re

    m = re.search(r"(?:^|[^0-9])((?:19|20)\d{2})(?:[^0-9]|$)", slug.strip())
    return int(m.group(1)) if m else None


def year_key_from_calendar(year: int) -> str:
    return f"{year % 100:02d}"


def analyse_sheet_from_slug(slug: Optional[str]) -> str:
    """Paper 1 / cp1 / M1 / M2 → SQ; otherwise MC (core P2)."""
    import re

    s = (slug or "").lower()
    if re.search(r"(?:^|[-_])(?:cp1|paper[-_]?1|p1)(?:$|[-_])", s) or s.endswith(
        "cp1"
    ):
        return "sq"
    if re.search(r"(?:^|[-_])m[12](?:$|[-_])", s) or re.search(
        r"(?:^|[^a-z0-9])(19|20)\d{2}[-_]?m[12](?:$|[-_])", s
    ):
        return "sq"
    if analyse_family_from_slug(slug) in {"m1", "m2", "ms", "pm"}:
        return "sq"
    return "mc"


def analyse_family_from_slug(slug: Optional[str]) -> str:
    """core | m1 | m2 | ms | pm — from paper_slug (Content passes dseYYYY-math-m1/m2)."""
    import re

    s = (slug or "").lower()
    if re.search(r"(?:^|[-_])m1(?:$|[-_])", s):
        return "m1"
    if re.search(r"(?:^|[-_])m2(?:$|[-_])", s):
        return "m2"
    if re.search(r"(?:^|[-_])(?:pm|pure)(?:$|[-_])", s) or "pure-math" in s:
        return "pm"
    if re.search(r"(?:^|[-_])ms(?:$|[-_])", s) or "m&s" in s or "maths-and-stat" in s:
        return "ms"
    return "core"


def _module_year_labels(cal: int, family: str) -> tuple[list[str], Optional[str]]:
    """Return (year_label candidates, preferred year_key for 2012 dual columns)."""
    y2 = f"{cal % 100:02d}"
    y4 = str(cal)
    labels = [y2]
    if y4 != y2:
        labels.append(y4)
    preferred_key = None
    if cal == 2012:
        if family in {"m1"}:
            preferred_key = "12#U"
        elif family == "ms":
            preferred_key = "12#T"
    return labels, preferred_key


def _topic_ids_for_module_units(
    cur: Any, family: str, unit_codes: list[str], unit_names: Optional[list[Optional[str]]] = None
) -> tuple[Optional[int], list[int], list[str]]:
    """Map module analyse unit_code → EDB-M*-LU topics (codes ≠ EDB LU numbers)."""
    # analyse_m1 / analyse_pm (m2) legend codes → EDB learning-unit numbers
    # From analyse_pm_units syllabus=m2 vs seed_topics EDB_M2
    M2_UNIT_TO_EDB = {
        "1": [2],          # MI → Mathematical induction
        "2": [3],          # Bionomial → binomial theorem
        "3": [4],          # Trigonometry
        "4": [6],          # Limit → Limits
        "5": [7],          # Diff → Differentiation
        "6": [8],          # App of Diff (tangent)
        "7": [8],          # App of Diff (graph)
        "8": [8],          # App of Diff (rate/opt)
        "9": [9, 10],      # int → indefinite + definite
        "10": [11],        # app of int
        "11": [13],        # Matrices (EDB splits Determinants as LU12)
        "12": [14],        # System of equations
        "13": [15, 16, 17],  # Vectors family
    }
    # analyse_m1_units (ms) — load once from common short names if present
    # analyse_m1_units vs seed_topics EDB_M1 (LU numbers ≠ analyse codes)
    M1_UNIT_TO_EDB = {
        "1": [1],                # Binomial → Binomial expansion
        "2": [2],                # Exponential and Log
        "3": [3],                # limits → Derivative of a function (closest)
        "4": [4],                # differentiation
        "5": [5, 6],             # App Diff (1) → 2nd derivative + applications
        "6": [6],                # App Diff (2)
        "7": [7],                # Integration → indefinite
        "8": [8, 9],             # App of integration → definite + trapezoidal
        "9": [10],               # Probability → conditional / Bayes
        "10": [11, 12, 13, 14, 15],  # Probability distribution family
        "11": [16, 17, 18],      # Normal distribution
        "12": [19, 20],          # Sampling Distribution
    }

    fam = (family or "").lower()
    if fam in ("m2", "pm"):
        code_map = M2_UNIT_TO_EDB
        qtype_prefix = "EDB-M2-LU"
        band = "2"
    elif fam in ("m1", "ms"):
        code_map = M1_UNIT_TO_EDB
        qtype_prefix = "EDB-M1-LU"
        band = "1"
    else:
        return None, [], []

    topic_ids: list[int] = []
    qtypes: list[str] = []
    for code in unit_codes:
        key = str(code).strip()
        lu_nums = code_map.get(key)
        if not lu_nums:
            continue
        for n in lu_nums:
            qt = f"{qtype_prefix}{n}"
            cur.execute(
                "SELECT id, qtype FROM topics WHERE qtype=%s AND band=%s ORDER BY id LIMIT 1",
                (qt, band),
            )
            tr = cur.fetchone()
            if not tr:
                cur.execute(
                    "SELECT id, qtype FROM topics WHERE qtype=%s ORDER BY id LIMIT 1",
                    (qt,),
                )
                tr = cur.fetchone()
            if not tr:
                continue
            tid = int(tr["id"])
            qtv = tr["qtype"]
            if tid not in topic_ids:
                topic_ids.append(tid)
            if qtv and qtv not in qtypes:
                qtypes.append(str(qtv))
    topic_id = topic_ids[0] if topic_ids else None
    return topic_id, topic_ids, qtypes


def _analyse_lookup_module(
    cur: Any,
    family: str,
    cal: int,
    qn: int,
    ykey: str,
) -> dict[str, Any]:
    labels, preferred_key = _module_year_labels(cal, family)
    sheet = "sq"
    sheet_label = {"m1": "M1", "ms": "M&S", "m2": "M2", "pm": "PM"}[family]

    if family in {"m1", "ms"}:
        syllabus = "dse" if family == "m1" else "ms"
        if not _table_exists(cur, "analyse_m1_sq"):
            raise HTTPException(503, "analyse_m1_sq missing — run seed_analyse_m1.py")
        cell = None
        if preferred_key:
            cur.execute(
                """
                SELECT id, year_key, year_label, question_no, raw_cell, syllabus
                FROM analyse_m1_sq
                WHERE syllabus=%s AND year_key=%s AND question_no=%s
                LIMIT 1
                """,
                (syllabus, preferred_key, qn),
            )
            cell = cur.fetchone()
        if not cell:
            cur.execute(
                """
                SELECT id, year_key, year_label, question_no, raw_cell, syllabus
                FROM analyse_m1_sq
                WHERE syllabus=%s AND question_no=%s
                  AND (year_label IN ({placeholders}) OR year_key IN ({placeholders}))
                ORDER BY id
                LIMIT 1
                """.format(placeholders=",".join(["%s"] * len(labels))),
                (syllabus, qn, *labels, *labels),
            )
            cell = cur.fetchone()
        if not cell:
            return {
                "year": cal,
                "year_key": preferred_key or ykey,
                "qno": qn,
                "sheet": sheet,
                "unit_raw": None,
                "units": [],
                "qtypes": [],
                "topic_id": None,
                "topic_ids": [],
                "hint": f"Analyse {sheet_label}: no unit for {cal} Q{qn}",
                "subject": family,
            }
        cur.execute(
            """
            SELECT su.position, su.unit_code, u.short_name, u.name
            FROM analyse_m1_sq_units su
            JOIN analyse_m1_units u
              ON u.syllabus = su.syllabus AND u.unit_code = su.unit_code
            WHERE su.sq_id=%s
            ORDER BY su.position, su.unit_code
            """,
            (cell["id"],),
        )
        unit_rows = cur.fetchall()
        units_out = []
        codes: list[str] = []
        for ur in unit_rows:
            code = ur["unit_code"]
            codes.append(str(code))
            try:
                unit_num: Any = int(code)
            except (TypeError, ValueError):
                unit_num = code
            units_out.append(
                {
                    "unit": unit_num,
                    "name": ur["name"] or ur["short_name"],
                    "notes": ur["short_name"],
                    "qtypes": [],
                }
            )
        topic_id, topic_ids, qtypes = _topic_ids_for_module_units(cur, family, codes, [u.get("name") for u in units_out])
        unit_label = "; ".join(f"{u['unit']} ({u['name']})" for u in units_out) or "—"
        qt_label = " · ".join(qtypes) if qtypes else "no mapped topic"
        return {
            "year": cal,
            "year_key": cell["year_key"],
            "qno": qn,
            "sheet": sheet,
            "unit_raw": cell["raw_cell"],
            "units": units_out,
            "qtypes": qtypes,
            "topic_id": topic_id,
            "topic_ids": topic_ids,
            "hint": (
                f"Analyse {sheet_label} '{cell['year_key']}' Q{qn} "
                f"→ unit {unit_label} → {qt_label}"
            ),
            "subject": family,
        }

    # m2 / pm → analyse_pm_*
    syllabus = "m2" if family == "m2" else "pm"
    paper = 1 if family == "m2" else None  # pm may be paper 1 or 2; default both, prefer 1
    if not _table_exists(cur, "analyse_pm_sq"):
        raise HTTPException(503, "analyse_pm_sq missing — run seed_analyse_pm.py")
    cell = None
    if paper is not None:
        cur.execute(
            """
            SELECT id, year_key, year_label, question_no, raw_cell, syllabus, paper
            FROM analyse_pm_sq
            WHERE syllabus=%s AND paper=%s AND question_no=%s
              AND (year_label IN ({placeholders}) OR year_key IN ({placeholders}))
            ORDER BY id
            LIMIT 1
            """.format(placeholders=",".join(["%s"] * len(labels))),
            (syllabus, paper, qn, *labels, *labels),
        )
        cell = cur.fetchone()
    else:
        cur.execute(
            """
            SELECT id, year_key, year_label, question_no, raw_cell, syllabus, paper
            FROM analyse_pm_sq
            WHERE syllabus=%s AND question_no=%s
              AND (year_label IN ({placeholders}) OR year_key IN ({placeholders}))
            ORDER BY paper, id
            LIMIT 1
            """.format(placeholders=",".join(["%s"] * len(labels))),
            (syllabus, qn, *labels, *labels),
        )
        cell = cur.fetchone()
    if not cell:
        return {
            "year": cal,
            "year_key": ykey,
            "qno": qn,
            "sheet": sheet,
            "unit_raw": None,
            "units": [],
            "qtypes": [],
            "topic_id": None,
            "topic_ids": [],
            "hint": f"Analyse {sheet_label}: no unit for {cal} Q{qn}",
            "subject": family,
        }
    cur.execute(
        """
        SELECT su.position, su.unit_code, u.name
        FROM analyse_pm_sq_units su
        JOIN analyse_pm_units u
          ON u.syllabus = su.syllabus AND u.unit_code = su.unit_code
        WHERE su.sq_id=%s
        ORDER BY su.position, su.unit_code
        """,
        (cell["id"],),
    )
    unit_rows = cur.fetchall()
    units_out = []
    codes = []
    for ur in unit_rows:
        code = ur["unit_code"]
        codes.append(str(code))
        try:
            unit_num = int(code)
        except (TypeError, ValueError):
            unit_num = code
        units_out.append(
            {"unit": unit_num, "name": ur["name"], "notes": None, "qtypes": []}
        )
    topic_id, topic_ids, qtypes = _topic_ids_for_module_units(cur, family, codes, [u.get("name") for u in units_out])
    unit_label = "; ".join(f"{u['unit']} ({u['name']})" for u in units_out) or "—"
    qt_label = " · ".join(qtypes) if qtypes else "no mapped topic"
    return {
        "year": cal,
        "year_key": cell["year_key"],
        "qno": qn,
        "sheet": sheet,
        "unit_raw": cell["raw_cell"],
        "units": units_out,
        "qtypes": qtypes,
        "topic_id": topic_id,
        "topic_ids": topic_ids,
        "hint": (
            f"Analyse {sheet_label} '{cell['year_key']}' Q{qn} "
            f"→ unit {unit_label} → {qt_label}"
        ),
        "subject": family,
        "paper": cell.get("paper"),
    }


def exam_from_year(year: int) -> str:
    return "DSE" if year >= 2012 else "CE"


def find_existing_question(
    cur: Any, paper_id: int, qno: str, year: Optional[int]
) -> Optional[dict[str, Any]]:
    """Match by paper + qno (question_school.external_qid), prefer same calendar year."""
    q = (qno or "").strip()
    if not q:
        return None
    if year is not None:
        cur.execute(
            """
            SELECT q.id, q.paper_id, q.topic_id, q.qkind, qs.external_qid AS qno, qs.year
            FROM questions q
            JOIN question_school qs ON qs.question_id = q.id
            WHERE q.paper_id=%s AND qs.external_qid=%s AND qs.year=%s
            LIMIT 1
            """,
            (paper_id, q, year),
        )
        row = cur.fetchone()
        if row:
            return row
    cur.execute(
        """
        SELECT q.id, q.paper_id, q.topic_id, q.qkind, qs.external_qid AS qno, qs.year
        FROM questions q
        JOIN question_school qs ON qs.question_id = q.id
        WHERE q.paper_id=%s AND qs.external_qid=%s
        ORDER BY q.id DESC
        LIMIT 1
        """,
        (paper_id, q),
    )
    return cur.fetchone()


def _delete_question_answers(cur: Any, qid: int) -> None:
    cur.execute(
        "SELECT id, content_block_id FROM answers WHERE question_id=%s",
        (qid,),
    )
    ans_rows = cur.fetchall()
    cur.execute("DELETE FROM answers WHERE question_id=%s", (qid,))
    for a in ans_rows:
        bid = a["content_block_id"]
        cur.execute(
            """
            DELETE FROM content_blocks WHERE id=%s
              AND NOT EXISTS (SELECT 1 FROM answers WHERE content_block_id=%s)
              AND NOT EXISTS (SELECT 1 FROM solutions WHERE content_block_id=%s)
              AND NOT EXISTS (SELECT 1 FROM hints WHERE content_block_id=%s)
            """,
            (bid, bid, bid, bid),
        )


def _upsert_correct_answer(
    cur: Any, qid: int, markdown: str, label: str = ""
) -> None:
    md = (markdown or "").strip()
    lab = (label or "").strip()[:8]
    if not md:
        _delete_question_answers(cur, qid)
        return
    cur.execute(
        """
        SELECT a.id, a.content_block_id
        FROM answers a
        WHERE a.question_id=%s AND a.is_correct=1
        ORDER BY a.sortorder, a.id LIMIT 1
        """,
        (qid,),
    )
    existing = cur.fetchone()
    if existing:
        cur.execute(
            "UPDATE content_blocks SET markdown=%s WHERE id=%s",
            (md, existing["content_block_id"]),
        )
        cur.execute(
            "UPDATE answers SET label=%s WHERE id=%s",
            (lab, existing["id"]),
        )
        return
    cur.execute(
        "INSERT INTO content_blocks (kind, markdown, status) VALUES ('answer',%s,'D')",
        (md,),
    )
    ans_block = cur.lastrowid
    cur.execute(
        """
        INSERT INTO answers
          (question_id, content_block_id, label, is_correct, sortorder)
        VALUES (%s,%s,%s,1,0)
        """,
        (qid, ans_block, lab),
    )


def _correct_answer_row(cur: Any, qid: int) -> Optional[dict[str, Any]]:
    cur.execute(
        """
        SELECT a.label, cb.markdown
        FROM answers a
        JOIN content_blocks cb ON cb.id = a.content_block_id
        WHERE a.question_id=%s AND a.is_correct=1
        ORDER BY a.sortorder, a.id
        LIMIT 1
        """,
        (qid,),
    )
    return cur.fetchone()


def _lookup_mc_key_letter(
    cur: Any,
    *,
    year: Optional[int],
    qno: Optional[str],
    paper_slug: Optional[str] = None,
) -> Optional[str]:
    """Resolve MC letter from shared mc_keys bank (year + qno)."""
    if not _table_exists(cur, "mc_keys"):
        return None
    cal = year
    if cal is None and paper_slug:
        cal = calendar_year_from_slug(paper_slug or "")
    if cal is None:
        return None
    try:
        qn = int(str(qno or "").strip())
    except ValueError:
        return None
    ex = exam_from_year(int(cal))
    cur.execute(
        """
        SELECT answer FROM mc_keys
        WHERE exam=%s AND year=%s AND qno=%s
        LIMIT 1
        """,
        (ex, int(cal), qn),
    )
    row = cur.fetchone()
    if not row:
        return None
    letter = (row.get("answer") or "").strip().upper()[:1]
    return letter if letter in "ABCDE" else None


def resolve_topic_ids(body: "QuestionIn") -> list[int]:
    ids: list[int] = []
    for tid in body.topic_ids or []:
        if tid is not None and int(tid) not in ids:
            ids.append(int(tid))
    if body.topic_id is not None and int(body.topic_id) not in ids:
        ids.insert(0, int(body.topic_id))
    return ids



@app.on_event("startup")
def _startup() -> None:
    try:
        with db() as conn:
            ensure_schema(conn)
    except Exception as e:
        # Allow process to start; endpoints will surface DB errors
        print(f"editorial_api startup schema check: {e}")


# ---------------------------------------------------------------------------
# Models
# ---------------------------------------------------------------------------


class TopicIn(BaseModel):
    name: str
    parent_id: Optional[int] = None
    band: Optional[str] = None
    qtype: Optional[str] = None
    description: Optional[str] = None
    sortorder: int = 0


class TopicPatch(BaseModel):
    name: Optional[str] = None
    parent_id: Optional[int] = None
    band: Optional[str] = None
    qtype: Optional[str] = None
    description: Optional[str] = None
    sortorder: Optional[int] = None


class PaperIn(BaseModel):
    slug: str
    title: str = ""
    source_pdf: Optional[str] = None
    dpi: int = 200
    status: str = "D"


class QuestionIn(BaseModel):
    paper_slug: str
    qno: str = ""
    stem_markdown: str
    topic_id: Optional[int] = None
    topic_ids: list[int] = Field(default_factory=list)
    qkind: str = Field(default="MC", pattern="^(MC|SQ|LQ)$")
    source_type: str = Field(default="S", pattern="^[SP]$")
    level: Optional[int] = None
    marks: Optional[float] = None
    year: Optional[int] = None
    exam_type: Optional[str] = None
    section: Optional[str] = None
    image_paths: list[str] = Field(default_factory=list)
    mc_answer: Optional[str] = None
    answer_markdown: Optional[str] = None
    force: bool = False


class QuestionPatch(BaseModel):
    """Partial update for Browse DB editor."""

    stem_markdown: Optional[str] = None
    qno: Optional[str] = None
    topic_id: Optional[int] = None
    topic_ids: Optional[list[int]] = None
    qkind: Optional[str] = None
    source_type: Optional[str] = None
    level: Optional[int] = None
    marks: Optional[float] = None
    year: Optional[int] = None
    exam_type: Optional[str] = None
    section: Optional[str] = None
    mc_answer: Optional[str] = None
    answer_markdown: Optional[str] = None
    clear_level: bool = False
    clear_marks: bool = False
    clear_mc_answer: bool = False


class ExportDocxIn(BaseModel):
    ids: list[int] = Field(..., min_length=1, max_length=200)
    include_answers: bool = True
    include_meta: bool = True
    title: Optional[str] = None
    # TeX text → MathType OLE via Word Toggle TeX (Parallels Windows + MathType).
    # Default True so exported Word opens with equations, not $...$ source.
    convert_mathtype: bool = False


# ---------------------------------------------------------------------------
# Topics
# ---------------------------------------------------------------------------


@app.get("/health")
def health() -> dict[str, str]:
    return {"ok": "1", "db": DB_NAME, "host": DB_HOST}


@app.get("/topics")
def list_topics(band: Optional[str] = None) -> list[dict[str, Any]]:
    sql = (
        "SELECT id, parent_id, name, description, qtype, band, sortorder, "
        "created, updated FROM topics"
    )
    args: tuple[Any, ...] = ()
    if band:
        sql += " WHERE band=%s"
        args = (band,)
    sql += " ORDER BY band, sortorder, id"
    with db() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, args)
            return list(cur.fetchall())


@app.post("/topics")
def create_topic(body: TopicIn) -> dict[str, Any]:
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO topics (parent_id, name, description, qtype, band, sortorder)
                VALUES (%s,%s,%s,%s,%s,%s)
                """,
                (
                    body.parent_id,
                    body.name.strip(),
                    body.description,
                    body.qtype,
                    body.band,
                    body.sortorder,
                ),
            )
            tid = cur.lastrowid
            cur.execute(
                "SELECT id, parent_id, name, description, qtype, band, sortorder "
                "FROM topics WHERE id=%s",
                (tid,),
            )
            row = cur.fetchone()
            assert row
            return row


@app.patch("/topics/{topic_id}")
def patch_topic(topic_id: int, body: TopicPatch) -> dict[str, Any]:
    fields: list[str] = []
    args: list[Any] = []
    data = body.model_dump(exclude_unset=True)
    for k, v in data.items():
        fields.append(f"{k}=%s")
        args.append(v)
    if not fields:
        raise HTTPException(400, "no fields to update")
    args.append(topic_id)
    with db() as conn:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE topics SET {', '.join(fields)} WHERE id=%s", args)
            if cur.rowcount == 0:
                raise HTTPException(404, "topic not found")
            cur.execute(
                "SELECT id, parent_id, name, description, qtype, band, sortorder "
                "FROM topics WHERE id=%s",
                (topic_id,),
            )
            row = cur.fetchone()
            assert row
            return row


@app.delete("/topics/{topic_id}")
def delete_topic(topic_id: int) -> dict[str, Any]:
    with db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT COUNT(*) AS c FROM questions WHERE topic_id=%s", (topic_id,)
            )
            used = int(cur.fetchone()["c"])
            if used:
                raise HTTPException(
                    409, f"topic is referenced by {used} question(s); reassign first"
                )
            cur.execute("SELECT COUNT(*) AS c FROM topics WHERE parent_id=%s", (topic_id,))
            kids = int(cur.fetchone()["c"])
            if kids:
                raise HTTPException(
                    409, f"topic has {kids} child topic(s); move or delete children first"
                )
            cur.execute("DELETE FROM topic_publisher WHERE topic_id=%s", (topic_id,))
            cur.execute("DELETE FROM topics WHERE id=%s", (topic_id,))
            if cur.rowcount == 0:
                raise HTTPException(404, "topic not found")
            return {"deleted": topic_id}


# ---------------------------------------------------------------------------
# Papers
# ---------------------------------------------------------------------------


@app.get("/papers")
def list_papers() -> list[dict[str, Any]]:
    with db() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, slug, title, source_pdf, dpi, status, created, updated "
                "FROM papers ORDER BY id DESC"
            )
            return list(cur.fetchall())


@app.post("/papers")
def upsert_paper(body: PaperIn) -> dict[str, Any]:
    slug = body.slug.strip()
    if not slug:
        raise HTTPException(400, "slug required")
    title = (body.title or slug).strip()
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO papers (slug, title, source_pdf, dpi, status)
                VALUES (%s,%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE
                  title=VALUES(title),
                  source_pdf=COALESCE(VALUES(source_pdf), source_pdf),
                  dpi=VALUES(dpi),
                  id=LAST_INSERT_ID(id)
                """,
                (slug, title, body.source_pdf, body.dpi, body.status),
            )
            pid = cur.lastrowid
            cur.execute(
                "SELECT id, slug, title, source_pdf, dpi, status FROM papers WHERE id=%s",
                (pid,),
            )
            row = cur.fetchone()
            assert row
            return row


# ---------------------------------------------------------------------------
# Questions
# ---------------------------------------------------------------------------


def _question_topic_ids(cur: Any, qid: int, primary: Optional[int]) -> list[int]:
    cur.execute(
        "SELECT topic_id FROM question_topic WHERE question_id=%s ORDER BY sortorder, topic_id",
        (qid,),
    )
    ids = [int(r["topic_id"]) for r in cur.fetchall()]
    if primary is not None and int(primary) not in ids:
        ids.insert(0, int(primary))
    return ids


def _topic_names(cur: Any, topic_ids: list[int]) -> list[str]:
    if not topic_ids:
        return []
    ph = ",".join(["%s"] * len(topic_ids))
    cur.execute(f"SELECT id, name FROM topics WHERE id IN ({ph})", topic_ids)
    by = {int(r["id"]): r["name"] for r in cur.fetchall()}
    return [by[i] for i in topic_ids if i in by]


@app.get("/questions/years")
def list_question_years() -> dict[str, Any]:
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT DISTINCT qs.year AS year
                FROM question_school qs
                WHERE qs.year IS NOT NULL
                ORDER BY qs.year DESC
                """
            )
            years = [int(r["year"]) for r in cur.fetchall() if r.get("year") is not None]
            return {"years": years}


@app.get("/questions")
def list_questions(
    year: Optional[int] = None,
    topic_id: Optional[int] = None,
    paper_slug: Optional[str] = None,
    qkind: Optional[str] = None,
    qno: Optional[str] = None,
    sort: Optional[str] = None,
    limit: int = 100,
    offset: int = 0,
) -> dict[str, Any]:
    lim = max(1, min(int(limit), 500))
    off = max(0, int(offset))
    sort_key = (sort or "kind_qno").strip().lower()
    order_by = {
        # MC → SQ → LQ, then numeric qno (default after year filter)
        "kind_qno": (
            "ORDER BY qs.year DESC, "
            "FIELD(q.qkind, 'MC', 'SQ', 'LQ'), "
            "CAST(qs.external_qid AS UNSIGNED), p.slug, q.id DESC"
        ),
        "qno": (
            "ORDER BY qs.year DESC, "
            "CAST(qs.external_qid AS UNSIGNED), "
            "FIELD(q.qkind, 'MC', 'SQ', 'LQ'), p.slug, q.id DESC"
        ),
        "paper": (
            "ORDER BY qs.year DESC, p.slug, "
            "FIELD(q.qkind, 'MC', 'SQ', 'LQ'), "
            "CAST(qs.external_qid AS UNSIGNED), q.id DESC"
        ),
        "year": (
            "ORDER BY qs.year DESC, "
            "FIELD(q.qkind, 'MC', 'SQ', 'LQ'), "
            "CAST(qs.external_qid AS UNSIGNED), p.slug, q.id DESC"
        ),
    }.get(sort_key)
    if not order_by:
        raise HTTPException(
            400, "sort must be kind_qno|qno|paper|year"
        )
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            sql = """
                SELECT q.id, q.paper_id, q.qkind, q.source_type, q.level, q.marks,
                       q.topic_id, q.created, q.updated,
                       p.slug AS paper_slug,
                       qs.external_qid AS qno, qs.year,
                       LEFT(cb.markdown, 220) AS stem_preview
                FROM questions q
                LEFT JOIN papers p ON p.id = q.paper_id
                LEFT JOIN question_school qs ON qs.question_id = q.id
                LEFT JOIN content_blocks cb ON cb.id = q.stem_block_id
                WHERE 1=1
            """
            args: list[Any] = []
            if year is not None:
                sql += " AND qs.year=%s"
                args.append(year)
            if paper_slug and paper_slug.strip():
                sql += " AND p.slug=%s"
                args.append(paper_slug.strip())
            if qkind and qkind.strip():
                sql += " AND q.qkind=%s"
                args.append(qkind.strip().upper())
            if qno is not None and str(qno).strip():
                sql += " AND qs.external_qid=%s"
                args.append(str(qno).strip())
            if topic_id is not None:
                sql += """
                  AND (
                    q.topic_id=%s
                    OR EXISTS (
                      SELECT 1 FROM question_topic qt
                      WHERE qt.question_id=q.id AND qt.topic_id=%s
                    )
                  )
                """
                args.extend([topic_id, topic_id])
            sql += f" {order_by}"
            sql += " LIMIT %s OFFSET %s"
            args.extend([lim, off])
            cur.execute(sql, args)
            rows = cur.fetchall()
            out = []
            for r in rows:
                tids = _question_topic_ids(cur, int(r["id"]), r.get("topic_id"))
                out.append(
                    {
                        "id": r["id"],
                        "paper_id": r["paper_id"],
                        "paper_slug": r.get("paper_slug"),
                        "qno": r.get("qno") or "",
                        "year": r.get("year"),
                        "qkind": r["qkind"],
                        "source_type": r["source_type"],
                        "level": r.get("level"),
                        "marks": float(r["marks"]) if r.get("marks") is not None else None,
                        "topic_id": r.get("topic_id"),
                        "topic_ids": tids,
                        "topic_names": _topic_names(cur, tids),
                        "stem_preview": r.get("stem_preview") or "",
                        "created": r.get("created"),
                        "updated": r.get("updated"),
                    }
                )
            return {
                "count": len(out),
                "limit": lim,
                "offset": off,
                "sort": sort_key,
                "rows": out,
            }


@app.get("/questions/exists")
def question_exists(
    paper_slug: str,
    qno: str = "",
    year: Optional[int] = None,
) -> dict[str, Any]:
    slug = paper_slug.strip()
    if not slug:
        raise HTTPException(400, "paper_slug required")
    cal = year if year is not None else calendar_year_from_slug(slug)
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute("SELECT id, slug FROM papers WHERE slug=%s", (slug,))
            paper = cur.fetchone()
            if not paper:
                return {
                    "exists": False,
                    "paper_slug": slug,
                    "qno": qno,
                    "year": cal,
                    "question": None,
                }
            row = find_existing_question(cur, int(paper["id"]), qno, cal)
            if not row:
                return {
                    "exists": False,
                    "paper_slug": slug,
                    "qno": qno,
                    "year": cal,
                    "question": None,
                }
            cur.execute(
                "SELECT topic_id FROM question_topic WHERE question_id=%s ORDER BY sortorder, topic_id",
                (row["id"],),
            )
            extra = [int(r["topic_id"]) for r in cur.fetchall()]
            topic_ids = list(extra)
            if row.get("topic_id") is not None and int(row["topic_id"]) not in topic_ids:
                topic_ids.insert(0, int(row["topic_id"]))
            return {
                "exists": True,
                "paper_slug": slug,
                "qno": qno,
                "year": cal,
                "question": {
                    "id": row["id"],
                    "paper_id": row["paper_id"],
                    "qno": row["qno"],
                    "year": row["year"],
                    "qkind": row["qkind"],
                    "topic_id": row["topic_id"],
                    "topic_ids": topic_ids,
                },
            }


@app.post("/questions/export-docx")
def export_questions_docx(body: ExportDocxIn) -> Response:
    """Download selected questions as a .docx (stems + optional answers)."""
    from export_docx import build_questions_docx

    # Preserve caller order; drop dupes
    seen: set[int] = set()
    ids: list[int] = []
    for qid in body.ids:
        qid = int(qid)
        if qid in seen:
            continue
        seen.add(qid)
        ids.append(qid)
    if not ids:
        raise HTTPException(400, "ids required")

    rows_out: list[dict[str, Any]] = []
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            for qid in ids:
                cur.execute(
                    """
                    SELECT q.id, q.paper_id, q.qkind, q.source_type, q.level, q.marks,
                           q.topic_id, q.stem_block_id,
                           p.slug AS paper_slug,
                           qs.external_qid AS qno, qs.year, qs.exam_type,
                           cb.markdown AS stem_markdown
                    FROM questions q
                    LEFT JOIN papers p ON p.id = q.paper_id
                    LEFT JOIN question_school qs ON qs.question_id = q.id
                    LEFT JOIN content_blocks cb ON cb.id = q.stem_block_id
                    WHERE q.id=%s
                    """,
                    (qid,),
                )
                r = cur.fetchone()
                if not r:
                    raise HTTPException(404, f"question {qid} not found")
                tids = _question_topic_ids(cur, int(r["id"]), r.get("topic_id"))
                answer_md = ""
                if body.include_answers:
                    stored = _correct_answer_row(cur, qid)
                    if stored:
                        if r["qkind"] == "MC":
                            answer_md = (
                                (stored.get("label") or stored.get("markdown") or "")
                                .strip()
                            )
                        else:
                            answer_md = (stored.get("markdown") or "").strip()
                    elif r["qkind"] == "MC":
                        # Fall back to shared DSE/CE key bank
                        letter = _lookup_mc_key_letter(
                            cur,
                            year=r.get("year"),
                            qno=r.get("qno"),
                            paper_slug=r.get("paper_slug"),
                        )
                        if letter:
                            answer_md = letter
                    else:
                        year = r.get("year")
                        if year is None and r.get("paper_slug"):
                            year = calendar_year_from_slug(r["paper_slug"])
                        qno_raw = (r.get("qno") or "").strip()
                        try:
                            qn = int(qno_raw) if qno_raw else None
                        except ValueError:
                            qn = None
                        if year is not None and qn is not None and _table_exists(
                            cur, "sq_keys"
                        ):
                            ex = exam_from_year(int(year))
                            cur.execute(
                                """
                                SELECT part, answer
                                FROM sq_keys
                                WHERE exam=%s AND year=%s AND qno=%s
                                ORDER BY part
                                """,
                                (ex, int(year), qn),
                            )
                            parts = cur.fetchall() or []
                            lines: list[str] = []
                            for p in parts:
                                part = (p.get("part") or "").strip()
                                ans = (p.get("answer") or "").strip()
                                if not ans:
                                    continue
                                prefix = f"({part}) " if part else ""
                                lines.append(f"{prefix}{ans}")
                            answer_md = "\n\n".join(lines)

                rows_out.append(
                    {
                        "id": r["id"],
                        "paper_slug": r.get("paper_slug"),
                        "qno": r.get("qno") or "",
                        "year": r.get("year"),
                        "qkind": r["qkind"],
                        "level": r.get("level"),
                        "marks": float(r["marks"])
                        if r.get("marks") is not None
                        else None,
                        "topic_names": _topic_names(cur, tids),
                        "stem_markdown": r.get("stem_markdown") or "",
                        "answer_markdown": answer_md,
                    }
                )

    data = build_questions_docx(
        rows_out,
        include_answers=body.include_answers,
        include_meta=body.include_meta,
        title=body.title,
    )
    if body.convert_mathtype:
        from mathtype_tex_convert import convert_tex_docx_to_mathtype

        try:
            data = convert_tex_docx_to_mathtype(data)
        except Exception as e:
            raise HTTPException(
                503,
                f"Word export built, but MathType TeX convert failed: {e}",
            ) from e
    fname = "alphaeqt-questions.docx"
    if len(rows_out) == 1:
        q = rows_out[0]
        bit = q.get("qno") or q["id"]
        yr = q.get("year") or "q"
        fname = f"alphaeqt-{yr}-Q{bit}.docx"
    return Response(
        content=data,
        media_type=(
            "application/vnd.openxmlformats-officedocument"
            ".wordprocessingml.document"
        ),
        headers={
            "Content-Disposition": f'attachment; filename="{fname}"',
        },
    )


@app.get("/questions/{qid}")
def get_question(qid: int) -> dict[str, Any]:
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT q.id, q.paper_id, q.qkind, q.source_type, q.level, q.marks,
                       q.topic_id, q.stem_block_id, q.created, q.updated,
                       p.slug AS paper_slug,
                       qs.external_qid AS qno, qs.year, qs.exam_type, qs.section,
                       cb.markdown AS stem_markdown
                FROM questions q
                LEFT JOIN papers p ON p.id = q.paper_id
                LEFT JOIN question_school qs ON qs.question_id = q.id
                LEFT JOIN content_blocks cb ON cb.id = q.stem_block_id
                WHERE q.id=%s
                """,
                (qid,),
            )
            r = cur.fetchone()
            if not r:
                raise HTTPException(404, f"question {qid} not found")
            tids = _question_topic_ids(cur, int(r["id"]), r.get("topic_id"))
            stored = _correct_answer_row(cur, int(r["id"]))
            mc_answer = None
            answer_markdown = None
            if stored:
                answer_markdown = (stored.get("markdown") or "").strip() or None
                if r["qkind"] == "MC":
                    mc_answer = (
                        (stored.get("label") or answer_markdown or "").strip()
                        or None
                    )
            elif r["qkind"] == "MC":
                # Link shared key bank when question has no copied answer row
                letter = _lookup_mc_key_letter(
                    cur,
                    year=r.get("year"),
                    qno=r.get("qno"),
                    paper_slug=r.get("paper_slug"),
                )
                if letter:
                    mc_answer = letter
                    answer_markdown = letter
            return {
                "id": r["id"],
                "paper_id": r["paper_id"],
                "paper_slug": r.get("paper_slug"),
                "qno": r.get("qno") or "",
                "year": r.get("year"),
                "exam_type": r.get("exam_type"),
                "section": r.get("section"),
                "qkind": r["qkind"],
                "source_type": r["source_type"],
                "level": r.get("level"),
                "marks": float(r["marks"]) if r.get("marks") is not None else None,
                "topic_id": r.get("topic_id"),
                "topic_ids": tids,
                "topic_names": _topic_names(cur, tids),
                "stem_block_id": r["stem_block_id"],
                "stem_markdown": r.get("stem_markdown") or "",
                "mc_answer": mc_answer,
                "answer_markdown": answer_markdown,
                "created": r.get("created"),
                "updated": r.get("updated"),
            }


@app.delete("/questions/{qid}")
def delete_question(qid: int) -> dict[str, Any]:
    """Remove a question and orphaned content_blocks (child rows CASCADE)."""
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, stem_block_id FROM questions WHERE id=%s",
                (qid,),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(404, f"question {qid} not found")
            bids: list[int] = []
            if row.get("stem_block_id") is not None:
                bids.append(int(row["stem_block_id"]))
            cur.execute(
                "SELECT content_block_id FROM answers WHERE question_id=%s",
                (qid,),
            )
            bids.extend(
                int(r["content_block_id"])
                for r in cur.fetchall()
                if r.get("content_block_id") is not None
            )
            for table in ("solutions", "hints"):
                if not _table_exists(cur, table):
                    continue
                cur.execute(
                    f"SELECT content_block_id FROM {table} WHERE question_id=%s",
                    (qid,),
                )
                bids.extend(
                    int(r["content_block_id"])
                    for r in cur.fetchall()
                    if r.get("content_block_id") is not None
                )
            cur.execute("DELETE FROM questions WHERE id=%s", (qid,))
            for bid in dict.fromkeys(bids):
                clauses = [
                    "id=%s",
                    "NOT EXISTS (SELECT 1 FROM questions WHERE stem_block_id=%s)",
                    "NOT EXISTS (SELECT 1 FROM answers WHERE content_block_id=%s)",
                ]
                args: list[Any] = [bid, bid, bid]
                for table in ("solutions", "hints"):
                    if _table_exists(cur, table):
                        clauses.append(
                            f"NOT EXISTS (SELECT 1 FROM {table} WHERE content_block_id=%s)"
                        )
                        args.append(bid)
                cur.execute(
                    f"DELETE FROM content_blocks WHERE {' AND '.join(clauses)}",
                    args,
                )
    return {"ok": True, "id": qid}


@app.patch("/questions/{qid}")
def patch_question(qid: int, body: QuestionPatch) -> dict[str, Any]:
    mc_ans = None
    if body.mc_answer is not None:
        mc_ans = (body.mc_answer or "").strip().upper()[:1] or None
        if mc_ans and mc_ans not in "ABCDE":
            raise HTTPException(400, "mc_answer must be A–E")
    if body.qkind is not None and body.qkind not in ("MC", "SQ", "LQ"):
        raise HTTPException(400, "qkind must be MC|SQ|LQ")
    if body.source_type is not None and body.source_type not in ("S", "P"):
        raise HTTPException(400, "source_type must be S|P")

    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT q.id, q.paper_id, q.stem_block_id, q.qkind, q.source_type,
                       q.level, q.marks, q.topic_id,
                       p.slug AS paper_slug,
                       qs.external_qid AS qno, qs.year, qs.exam_type, qs.section
                FROM questions q
                LEFT JOIN papers p ON p.id = q.paper_id
                LEFT JOIN question_school qs ON qs.question_id = q.id
                WHERE q.id=%s
                """,
                (qid,),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(404, f"question {qid} not found")

            if body.stem_markdown is not None:
                stem = body.stem_markdown.strip()
                if not stem:
                    raise HTTPException(400, "stem_markdown cannot be empty")
                cur.execute(
                    "UPDATE content_blocks SET markdown=%s WHERE id=%s",
                    (stem, row["stem_block_id"]),
                )

            sets: list[str] = []
            args: list[Any] = []
            if body.qkind is not None:
                sets.append("qkind=%s")
                args.append(body.qkind)
            if body.source_type is not None:
                sets.append("source_type=%s")
                args.append(body.source_type)
            if body.clear_level:
                sets.append("level=NULL")
            elif body.level is not None:
                sets.append("level=%s")
                args.append(body.level)
            if body.clear_marks:
                sets.append("marks=NULL")
            elif body.marks is not None:
                sets.append("marks=%s")
                args.append(body.marks)

            topic_ids: Optional[list[int]] = None
            if body.topic_ids is not None:
                topic_ids = []
                for tid in body.topic_ids:
                    if tid is not None and int(tid) not in topic_ids:
                        topic_ids.append(int(tid))
            elif body.topic_id is not None:
                topic_ids = [int(body.topic_id)]

            if topic_ids is not None:
                primary = topic_ids[0] if topic_ids else None
                sets.append("topic_id=%s")
                args.append(primary)
                cur.execute("DELETE FROM question_topic WHERE question_id=%s", (qid,))
                for i, tid in enumerate(topic_ids):
                    cur.execute(
                        "INSERT INTO question_topic (question_id, topic_id, sortorder) VALUES (%s,%s,%s)",
                        (qid, tid, i),
                    )

            if sets:
                args.append(qid)
                cur.execute(
                    f"UPDATE questions SET {', '.join(sets)} WHERE id=%s",
                    args,
                )

            # question_school upsert when any school field touched
            touch_school = any(
                x is not None
                for x in (body.qno, body.year, body.exam_type, body.section)
            )
            if touch_school:
                new_qno = (
                    body.qno.strip()
                    if body.qno is not None
                    else (row.get("qno") or "")
                )
                new_year = body.year if body.year is not None else row.get("year")
                new_exam = (
                    body.exam_type
                    if body.exam_type is not None
                    else row.get("exam_type")
                )
                if new_exam is None and new_year is not None:
                    new_exam = exam_from_year(int(new_year))
                new_section = (
                    body.section if body.section is not None else row.get("section")
                )
                cur.execute(
                    "SELECT question_id FROM question_school WHERE question_id=%s",
                    (qid,),
                )
                if cur.fetchone():
                    cur.execute(
                        """
                        UPDATE question_school
                        SET external_qid=%s, year=%s, exam_type=%s, section=%s
                        WHERE question_id=%s
                        """,
                        (new_qno, new_year, new_exam, new_section, qid),
                    )
                else:
                    cur.execute(
                        """
                        INSERT INTO question_school
                          (question_id, external_qid, year, exam_type, section)
                        VALUES (%s,%s,%s,%s,%s)
                        """,
                        (qid, new_qno, new_year, new_exam, new_section),
                    )

            qkind_now = body.qkind if body.qkind is not None else row["qkind"]
            if qkind_now == "MC" and mc_ans:
                _upsert_correct_answer(cur, qid, mc_ans, mc_ans)
            elif body.answer_markdown is not None:
                md = (body.answer_markdown or "").strip()
                if md:
                    _upsert_correct_answer(cur, qid, md, "")
                else:
                    _delete_question_answers(cur, qid)
            elif body.clear_mc_answer or (
                body.mc_answer is not None and not mc_ans
            ):
                _delete_question_answers(cur, qid)

    # Return fresh detail
    return get_question(qid)


@app.post("/questions")
def create_question(body: QuestionIn) -> dict[str, Any]:
    slug = body.paper_slug.strip()
    if not slug:
        raise HTTPException(400, "paper_slug required")
    stem = body.stem_markdown.strip()
    if not stem:
        raise HTTPException(400, "stem_markdown required")

    topic_ids = resolve_topic_ids(body)
    primary = topic_ids[0] if topic_ids else body.topic_id
    mc_ans = (body.mc_answer or "").strip().upper()[:1] or None
    if mc_ans and mc_ans not in "ABCDE":
        raise HTTPException(400, "mc_answer must be A–E")

    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO papers (slug, title, status)
                VALUES (%s,%s,'D')
                ON DUPLICATE KEY UPDATE id=LAST_INSERT_ID(id)
                """,
                (slug, slug),
            )
            paper_id = cur.lastrowid
            year = body.year if body.year is not None else calendar_year_from_slug(slug)

            existing = find_existing_question(cur, paper_id, body.qno, year)
            if existing and not body.force:
                raise HTTPException(
                    409,
                    f"Question already in DB (id={existing['id']}, "
                    f"paper={slug}, qno={body.qno or existing.get('qno')}). "
                    "Pass force=true to insert another copy.",
                )

            cur.execute(
                "INSERT INTO content_blocks (kind, markdown, status) VALUES ('question',%s,'D')",
                (stem,),
            )
            block_id = cur.lastrowid

            cur.execute(
                """
                INSERT INTO questions
                  (paper_id, stem_block_id, source_type, qkind, level, marks, topic_id)
                VALUES (%s,%s,%s,%s,%s,%s,%s)
                """,
                (
                    paper_id,
                    block_id,
                    body.source_type,
                    body.qkind,
                    body.level,
                    body.marks,
                    primary,
                ),
            )
            qid = cur.lastrowid

            for i, tid in enumerate(topic_ids):
                cur.execute(
                    "INSERT INTO question_topic (question_id, topic_id, sortorder) VALUES (%s,%s,%s)",
                    (qid, tid, i),
                )

            if body.source_type == "S" or (body.qno or "").strip():
                # Always store paper-local qno/year when provided (needed for
                # exists/lookup). School papers always; publisher/DSE too.
                cur.execute(
                    """
                    INSERT INTO question_school
                      (question_id, external_qid, year, exam_type, section)
                    VALUES (%s,%s,%s,%s,%s)
                    """,
                    (
                        qid,
                        body.qno or "",
                        year,
                        body.exam_type
                        or (exam_from_year(year) if year is not None else None),
                        body.section,
                    ),
                )

            if body.qkind == "MC" and mc_ans:
                _upsert_correct_answer(cur, qid, mc_ans, mc_ans)
            elif (body.answer_markdown or "").strip():
                _upsert_correct_answer(
                    cur, qid, body.answer_markdown.strip(), ""
                )

            return {
                "id": qid,
                "paper_id": paper_id,
                "paper_slug": slug,
                "stem_block_id": block_id,
                "qno": body.qno,
                "topic_id": primary,
                "topic_ids": topic_ids,
                "qkind": body.qkind,
                "source_type": body.source_type,
                "year": year,
                "mc_answer": mc_ans,
                "image_paths": body.image_paths,
                "duplicate_of": existing["id"] if existing else None,
            }


# ---------------------------------------------------------------------------
# Analyse.xls (MySQL) — topic prefill + coverage gaps
# ---------------------------------------------------------------------------


@app.get("/analyse/lookup")
def analyse_lookup(
    qno: str,
    paper_slug: Optional[str] = None,
    year: Optional[int] = None,
) -> dict[str, Any]:
    """Resolve Analyse unit → topic_id for a paper year + question number.

    Paper 1 (cp1) uses Sheet3 / analyse_sq; Paper 2 MC uses Sheet1 / analyse_mc.
    Module slugs (*-math-m1 / *-math-m2) use analyse_m1_* / analyse_pm_*.
    """
    cal = year
    if cal is None and paper_slug:
        cal = calendar_year_from_slug(paper_slug)
    if cal is None:
        raise HTTPException(400, "year or paper_slug with a 4-digit year required")
    try:
        qn = int(str(qno).strip())
    except ValueError as e:
        raise HTTPException(400, "qno must be an integer") from e

    ykey = year_key_from_calendar(cal)
    family = analyse_family_from_slug(paper_slug)
    sheet = analyse_sheet_from_slug(paper_slug)
    cell_table = "analyse_sq" if sheet == "sq" else "analyse_mc"
    units_table = "analyse_sq_units" if sheet == "sq" else "analyse_mc_units"
    sheet_label = "SQ" if sheet == "sq" else "MC"

    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            if family != "core":
                return _analyse_lookup_module(cur, family, cal, qn, ykey)
            if not _table_exists(cur, cell_table):
                raise HTTPException(
                    503, f"{cell_table} missing — run seed_analyse.py"
                )
            cur.execute(f"SELECT COUNT(*) AS c FROM {cell_table}")
            if int(cur.fetchone()["c"]) == 0:
                raise HTTPException(
                    503, f"{cell_table} empty — run seed_analyse.py"
                )

            cur.execute(
                f"""
                SELECT year_key, calendar_year, qno, unit_raw
                FROM {cell_table}
                WHERE calendar_year=%s AND qno=%s
                """,
                (cal, qn),
            )
            cell = cur.fetchone()
            if not cell:
                return {
                    "year": cal,
                    "year_key": ykey,
                    "qno": qn,
                    "sheet": sheet,
                    "unit_raw": None,
                    "units": [],
                    "qtypes": [],
                    "topic_id": None,
                    "topic_ids": [],
                    "hint": f"Analyse {sheet_label}: no unit for {cal} Q{qn}",
                }

            cur.execute(
                f"""
                SELECT mu.unit, u.name, u.notes, mu.sortorder
                FROM {units_table} mu
                JOIN analyse_units u ON u.unit = mu.unit
                WHERE mu.year_key=%s AND mu.qno=%s
                ORDER BY mu.sortorder, mu.unit
                """,
                (cell["year_key"], qn),
            )
            unit_rows = cur.fetchall()

            qtypes: list[str] = []
            units_out: list[dict[str, Any]] = []
            for ur in unit_rows:
                cur.execute(
                    """
                    SELECT qtype FROM analyse_unit_qtypes
                    WHERE unit=%s ORDER BY sortorder, qtype
                    """,
                    (ur["unit"],),
                )
                uq = [r["qtype"] for r in cur.fetchall()]
                for qt in uq:
                    if qt not in qtypes:
                        qtypes.append(qt)
                units_out.append(
                    {
                        "unit": ur["unit"],
                        "name": ur["name"],
                        "notes": ur["notes"],
                        "qtypes": uq,
                    }
                )

            topic_ids: list[int] = []
            topic_id: Optional[int] = None
            for qt in qtypes:
                cur.execute(
                    "SELECT id FROM topics WHERE qtype=%s ORDER BY id LIMIT 1",
                    (qt,),
                )
                tr = cur.fetchone()
                if tr:
                    tid = int(tr["id"])
                    if tid not in topic_ids:
                        topic_ids.append(tid)
                    if topic_id is None:
                        topic_id = tid

            unit_label = "; ".join(f"{u['unit']} ({u['name']})" for u in units_out)
            qt_label = " · ".join(qtypes) if qtypes else "no qtype"
            hint = (
                f"Analyse {sheet_label} '{cell['year_key']}' Q{qn} "
                f"→ unit {unit_label} → {qt_label}"
            )
            return {
                "year": cal,
                "year_key": cell["year_key"],
                "qno": qn,
                "sheet": sheet,
                "unit_raw": cell["unit_raw"],
                "units": units_out,
                "qtypes": qtypes,
                "topic_id": topic_id,
                "topic_ids": topic_ids,
                "hint": hint,
            }


@app.get("/analyse/units/{unit}")
def analyse_unit_info(unit: int) -> dict[str, Any]:
    """Legend + qtypes for one Analyse unit number (for topic search)."""
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                "SELECT unit, name, notes FROM analyse_units WHERE unit=%s",
                (unit,),
            )
            row = cur.fetchone()
            if not row:
                raise HTTPException(404, f"unknown Analyse unit {unit}")
            cur.execute(
                """
                SELECT qtype FROM analyse_unit_qtypes
                WHERE unit=%s ORDER BY sortorder, qtype
                """,
                (unit,),
            )
            qtypes = [r["qtype"] for r in cur.fetchall()]
            topic_ids: list[int] = []
            for qt in qtypes:
                cur.execute(
                    "SELECT id FROM topics WHERE qtype=%s ORDER BY id LIMIT 1",
                    (qt,),
                )
                tr = cur.fetchone()
                if tr:
                    topic_ids.append(int(tr["id"]))
            return {
                "unit": row["unit"],
                "name": row["name"],
                "notes": row["notes"],
                "qtypes": qtypes,
                "topic_ids": topic_ids,
            }


@app.get("/analyse/gaps")
def analyse_gaps(
    year: Optional[int] = None,
    limit: int = 200,
    kind: str = "missing",
) -> dict[str, Any]:
    """Coverage helpers.

    kind=missing — Analyse MC cells with no saved question (year + qno)
    kind=unfilled — saved questions whose topic_id is NULL (optional year)
    """
    limit = max(1, min(limit, 2000))
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            if kind == "unfilled":
                sql = """
                    SELECT q.id AS question_id, p.slug AS paper_slug,
                           qs.year, qs.external_qid AS qno, q.qkind,
                           am.unit_raw, am.year_key
                    FROM questions q
                    LEFT JOIN papers p ON p.id = q.paper_id
                    LEFT JOIN question_school qs ON qs.question_id = q.id
                    LEFT JOIN analyse_mc am
                      ON am.calendar_year = qs.year
                     AND am.qno = CAST(NULLIF(qs.external_qid, '') AS UNSIGNED)
                    WHERE q.topic_id IS NULL
                """
                args: list[Any] = []
                if year is not None:
                    sql += " AND qs.year=%s"
                    args.append(year)
                sql += " ORDER BY qs.year DESC, q.id DESC LIMIT %s"
                args.append(limit)
                cur.execute(sql, args)
                rows = cur.fetchall()
                return {"kind": kind, "count": len(rows), "rows": rows}

            if kind != "missing":
                raise HTTPException(400, "kind must be missing|unfilled")

            sql = """
                SELECT am.year_key, am.calendar_year AS year, am.qno, am.unit_raw,
                       GROUP_CONCAT(mu.unit ORDER BY mu.sortorder SEPARATOR ',') AS units
                FROM analyse_mc am
                LEFT JOIN analyse_mc_units mu
                  ON mu.year_key = am.year_key AND mu.qno = am.qno
                LEFT JOIN question_school qs
                  ON qs.year = am.calendar_year
                 AND qs.external_qid = CAST(am.qno AS CHAR)
                WHERE qs.question_id IS NULL
            """
            args = []
            if year is not None:
                sql += " AND am.calendar_year=%s"
                args.append(year)
            sql += (
                " GROUP BY am.year_key, am.calendar_year, am.qno, am.unit_raw"
                " ORDER BY am.calendar_year DESC, am.qno LIMIT %s"
            )
            args.append(limit)
            cur.execute(sql, args)
            rows = cur.fetchall()
            return {"kind": kind, "count": len(rows), "rows": rows}


# ---------------------------------------------------------------------------
# MC keys (CE 1980–2011 / DSE 2012–2026) + facility %
# ---------------------------------------------------------------------------


@app.get("/mc-keys")
def list_mc_keys(
    year: Optional[int] = None,
    exam: Optional[str] = None,
    qno: Optional[int] = None,
) -> dict[str, Any]:
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            if not _table_exists(cur, "mc_keys"):
                raise HTTPException(503, "mc_keys missing — run seed_mc_keys.py")
            sql = (
                "SELECT exam, year, qno, answer, correct_pct, source FROM mc_keys WHERE 1=1"
            )
            args: list[Any] = []
            if year is not None:
                sql += " AND year=%s"
                args.append(year)
            if exam:
                sql += " AND exam=%s"
                args.append(exam.upper())
            if qno is not None:
                sql += " AND qno=%s"
                args.append(qno)
            sql += " ORDER BY year, exam, qno"
            cur.execute(sql, args)
            rows = cur.fetchall()
            return {"count": len(rows), "rows": rows}



def canonical_module_paper_slug(slug: Optional[str], year: int, family: str) -> Optional[str]:
    """Map OCR/folder slugs (2026-M2, dse2026-math-m2) to hoksi paper key."""
    import re

    s = (slug or "").strip().lower()
    fam = (family or "").lower()
    if fam not in {"m1", "m2"}:
        return None
    m = re.search(r"dse((?:\d{4}|sp|pp))-math-m[12]", s)
    if m:
        return f"dse{m.group(1)}-math-{fam}"
    return f"dse{int(year)}-math-{fam}"


def _hoksi_solution_markdown(cur: Any, paper_key: str, qno: int) -> Optional[str]:
    """Prefer English Hoksi solution block for module paper."""
    if not _table_exists(cur, "content_blocks"):
        return None
    like_en = f"%<!-- hoksi:{paper_key}:q{int(qno)}:en:solution -->%"
    like_any = f"%<!-- hoksi:{paper_key}:q{int(qno)}:%:solution -->%"
    cur.execute(
        """
        SELECT markdown FROM content_blocks
        WHERE kind=%s AND markdown LIKE %s
        ORDER BY id LIMIT 1
        """,
        ("solution", like_en),
    )
    row = cur.fetchone()
    if not row:
        cur.execute(
            """
            SELECT markdown FROM content_blocks
            WHERE kind=%s AND markdown LIKE %s
            ORDER BY id LIMIT 1
            """,
            ("solution", like_any),
        )
        row = cur.fetchone()
    if not row:
        return None
    md = row["markdown"] if isinstance(row, dict) else row[0]
    return (md or "").strip() or None


def _hoksi_solution_to_sq_parts(md: str) -> list[dict[str, Any]]:
    """Strip Hoksi banner; split ## (a)/(b) into sq_keys-style parts when present."""
    import re

    body = re.sub(r"<!--\s*hoksi:[^>]*-->\s*", "", md, count=1).strip()
    body = re.sub(r"^#\s+[^\n]+\n+", "", body)
    chunks = re.split(r"(?m)^##\s+(\([^\n]+\))\s*$", body)
    if len(chunks) >= 3:
        parts: list[dict[str, Any]] = []
        preamble = (chunks[0] or "").strip()
        if preamble:
            parts.append({"part": "", "answer": preamble, "source": "hoksi-solution"})
        for i in range(1, len(chunks), 2):
            label = chunks[i].strip()
            text_part = (chunks[i + 1] if i + 1 < len(chunks) else "").strip()
            part = label.replace(")(", ".").replace("(", "").replace(")", "")
            parts.append({"part": part, "answer": text_part, "source": "hoksi-solution"})
        return [x for x in parts if (x.get("answer") or "").strip()]
    return [{"part": "", "answer": body, "source": "hoksi-solution"}]


@app.get("/mc-keys/lookup")
def mc_keys_lookup(
    qno: str,
    paper_slug: Optional[str] = None,
    year: Optional[int] = None,
    exam: Optional[str] = None,
) -> dict[str, Any]:
    cal = year
    if cal is None and paper_slug:
        cal = calendar_year_from_slug(paper_slug)
    if cal is None:
        raise HTTPException(400, "year or paper_slug with a 4-digit year required")
    try:
        qn = int(str(qno).strip())
    except ValueError as e:
        raise HTTPException(400, "qno must be an integer") from e
    # Paper 1 shares year+qno with P2 MC bank — never return P2 letters for cp1
    if analyse_sheet_from_slug(paper_slug) == "sq":
        return {
            "exam": exam_from_year(cal),
            "year": cal,
            "qno": qn,
            "answer": None,
            "correct_pct": None,
            "source": None,
            "hint": f"Paper 1 — no MC key (SQ); use /sq-keys for {cal} Q{qn}",
        }
    ex = (exam or exam_from_year(cal)).upper()
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT exam, year, qno, answer, correct_pct, source
                FROM mc_keys WHERE exam=%s AND year=%s AND qno=%s
                """,
                (ex, cal, qn),
            )
            row = cur.fetchone()
            if not row:
                return {
                    "exam": ex,
                    "year": cal,
                    "qno": qn,
                    "answer": None,
                    "correct_pct": None,
                    "hint": f"No MC key for {ex} {cal} Q{qn}",
                }
            pct = row["correct_pct"]
            pct_s = f" ({pct}% correct)" if pct is not None else ""
            return {
                **row,
                "hint": f"{row['exam']} {row['year']} Q{row['qno']} → {row['answer']}{pct_s}",
            }


# ---------------------------------------------------------------------------
# SQ keys (Paper 1 final answers; parts a/b/…)
# ---------------------------------------------------------------------------


@app.get("/sq-keys/lookup")
def sq_keys_lookup(
    qno: str,
    paper_slug: Optional[str] = None,
    year: Optional[int] = None,
    exam: Optional[str] = None,
) -> dict[str, Any]:
    cal = year
    if cal is None and paper_slug:
        cal = calendar_year_from_slug(paper_slug)
    if cal is None:
        raise HTTPException(400, "year or paper_slug with a 4-digit year required")
    try:
        qn = int(str(qno).strip())
    except ValueError as e:
        raise HTTPException(400, "qno must be an integer") from e
    ex = (exam or exam_from_year(cal)).upper()
    family = analyse_family_from_slug(paper_slug)
    with db() as conn:
        ensure_schema(conn)
        with conn.cursor() as cur:
            # M1/M2: Hoksi worked solutions — never core Paper-1 sq_keys
            if family in {"m1", "m2"}:
                paper_key = canonical_module_paper_slug(paper_slug, int(cal), family)
                md = (
                    _hoksi_solution_markdown(cur, paper_key, qn)
                    if paper_key
                    else None
                )
                if not md:
                    return {
                        "exam": ex,
                        "year": cal,
                        "qno": qn,
                        "parts": [],
                        "hint": (
                            f"No Hoksi {family.upper()} solution for "
                            f"{paper_key or family} Q{qn}"
                        ),
                    }
                parts = _hoksi_solution_to_sq_parts(md)
                preview = (parts[0]["answer"] if parts else "").replace(chr(10), " ")
                if len(preview) > 48:
                    preview = preview[:47] + "…"
                return {
                    "exam": ex,
                    "year": cal,
                    "qno": qn,
                    "parts": parts,
                    "hint": f"{family.upper()} {cal} Q{qn} · Hoksi · {preview}",
                }
            if family in {"ms", "pm"}:
                return {
                    "exam": ex,
                    "year": cal,
                    "qno": qn,
                    "parts": [],
                    "hint": f"No SQ key bank for {family.upper()} (not core P1)",
                }
            if not _table_exists(cur, "sq_keys"):
                return {
                    "exam": ex,
                    "year": cal,
                    "qno": qn,
                    "parts": [],
                    "hint": "sq_keys missing — run seed_p1_sq_keys.py",
                }
            cur.execute(
                """
                SELECT exam, year, qno, part, answer, source
                FROM sq_keys
                WHERE exam=%s AND year=%s AND qno=%s
                ORDER BY part
                """,
                (ex, cal, qn),
            )
            rows = cur.fetchall()
            if not rows:
                return {
                    "exam": ex,
                    "year": cal,
                    "qno": qn,
                    "parts": [],
                    "hint": f"No SQ key for {ex} {cal} Q{qn}",
                }

            def part_sort(p: str) -> tuple:
                # '', a, b, b.i, b.ii, c …
                if not p:
                    return (0, "")
                return (1, p)

            parts = sorted(
                [
                    {
                        "part": r["part"] or "",
                        "answer": r["answer"],
                        "source": r.get("source"),
                    }
                    for r in rows
                ],
                key=lambda x: part_sort(x["part"]),
            )
            labels = []
            for p in parts:
                label = f"({p['part']}) " if p["part"] else ""
                ans = (p["answer"] or "").replace("\n", " ")
                if len(ans) > 48:
                    ans = ans[:47] + "…"
                labels.append(f"{label}{ans}")
            return {
                "exam": ex,
                "year": cal,
                "qno": qn,
                "parts": parts,
                "hint": f"{ex} {cal} Q{qn} · " + " · ".join(labels[:4])
                + ("…" if len(labels) > 4 else ""),
            }


# Tests replace this with a zero-arg callable that returns a content_pages.Database.
# Production leaves it unset and opens pymysql.
content_db_override: Optional[Callable[[], Any]] = None


class PymysqlContentDB:
    """content_pages.Database over one pymysql connection.

    script sends the helper SQL as one multi-statement query. Markdown sits
    inside quoted literals and may contain a semicolon followed by a newline,
    so the text is not split before it is sent.
    """

    def __init__(self, conn: pymysql.connections.Connection):
        self.conn = conn

    def query(self, sql: str) -> list[dict]:
        statement = sql.strip().rstrip(";")
        if ";" in statement:
            raise RuntimeError("refusing multiple statements")
        try:
            with self.conn.cursor() as cur:
                cur.execute(statement)
                rows = cur.fetchall()
        except (
            pymysql.err.IntegrityError,
            pymysql.err.ProgrammingError,
            pymysql.err.OperationalError,
        ) as exc:
            self._raise_mysql(exc)
        return [dict(row) for row in (rows or [])]

    def script(self, sql: str) -> list[dict]:
        stripped = sql.strip()
        if not stripped.startswith("USE alphaeqt;\nSTART TRANSACTION;\n"):
            raise RuntimeError("content script must be one alphaeqt transaction")
        if not stripped.endswith("COMMIT;"):
            raise RuntimeError("content script must commit")
        try:
            with self.conn.cursor() as cur:
                cur.execute(stripped)
                last: list[dict] = []
                while True:
                    if cur.description:
                        last = [dict(row) for row in (cur.fetchall() or [])]
                    if not cur.nextset():
                        break
                return last
        except (
            pymysql.err.IntegrityError,
            pymysql.err.ProgrammingError,
            pymysql.err.OperationalError,
        ) as exc:
            self._raise_mysql(exc)

    @staticmethod
    def _raise_mysql(exc: Exception) -> None:
        errno = exc.args[0] if exc.args else None
        message = str(exc)
        if errno == 1062 or "Duplicate entry" in message:
            if "content_pages" in message or "uq_content_pages_slug" in message:
                raise content_pages.ContentError(
                    409, "page_exists", "a page with this slug already exists"
                ) from exc
            if "papers" in message or "uq_papers_slug" in message:
                raise content_pages.ContentError(
                    409, "paper_exists", "a paper with this slug already exists"
                ) from exc
            raise content_pages.ContentError(409, "conflict", "unique key conflict") from exc
        if errno == 1452:
            raise content_pages.ContentError(
                409, "missing_block", "a referenced block or revision is missing"
            ) from exc
        if errno == 1146 or "doesn't exist" in message or "does not exist" in message:
            raise content_pages.ContentError(
                503, "missing_table", "content page tables are not in this database"
            ) from exc
        raise exc


@contextmanager
def content_database() -> Iterator[Any]:
    if content_db_override is not None:
        yield content_db_override()
        return
    with db(multi=True) as conn:
        yield PymysqlContentDB(conn)


def serve_content(method: str, path: str, body: bytes) -> JSONResponse:
    """Run one content-page helper call and keep its JSON error shape."""
    try:
        with content_database() as database:
            status, payload = content_pages.dispatch(method, path, body, database)
    except content_pages.ContentError as exc:
        status, payload = exc.status, exc.payload()
    return JSONResponse(payload, status_code=status)


def _content_too_large() -> JSONResponse:
    return JSONResponse(
        {"error": "body_too_large", "message": "body exceeds 2MB"},
        status_code=413,
    )


async def _content_request(request: Request) -> JSONResponse:
    raw_length = request.headers.get("content-length")
    try:
        length = int(raw_length or 0)
    except (TypeError, ValueError):
        length = 0
    if length > content_pages.MAX_BODY:
        return _content_too_large()
    body = await request.body()
    if len(body) > content_pages.MAX_BODY:
        return _content_too_large()
    return serve_content(request.method, request.url.path, body)


@app.post("/content/pages")
async def import_content_page(request: Request) -> JSONResponse:
    """Import a document as a new draft page. An existing slug is rejected."""
    return await _content_request(request)


@app.get("/content/pages/{slug}")
async def get_content_page(slug: str, request: Request) -> JSONResponse:
    """Current version and items, including pinned-revision markdown."""
    return await _content_request(request)


@app.post("/content/pages/{slug}/items")
async def append_content_item(slug: str, request: Request) -> JSONResponse:
    """Append one atom to the current draft. A question may include a figure."""
    return await _content_request(request)


@app.post("/content/pages/{slug}/items/{sortorder}")
async def edit_content_item(slug: str, sortorder: int, request: Request) -> JSONResponse:
    """Draft edit: new revision, then retarget that draft item."""
    return await _content_request(request)


@app.post("/content/pages/{slug}/publish")
async def publish_content_page(slug: str, request: Request) -> JSONResponse:
    """Mark the current version and the page active. Pins stay put."""
    return await _content_request(request)


@app.post("/content/pages/{slug}/versions")
async def version_content_page(slug: str, request: Request) -> JSONResponse:
    """Open the next draft version. Omitting items clones the current pins."""
    return await _content_request(request)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "editorial_api:app",
        host="127.0.0.1",
        port=int(os.environ.get("PORT", "8505")),
        reload=False,
    )
