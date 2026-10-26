#!/usr/bin/env python3
"""Load Hoksi M1/M2 worked solutions into alphaeqt papers, questions, and solutions.

The default is a dry run. It reads the JSON tree written by
db/download_hoksi_solutions.py (the same layout as core's
downloads/hoksi/hkdse-maths-core-solutions) and prints how many solution
rows would be written. It does not connect to MySQL.

--apply writes only slugs dse{year}-math-m1, dse{year}-math-m2, dsesp-math-m1,
dsesp-math-m2, dsepp-math-m1, and dsepp-math-m2. Analyse tables, sq_keys,
answers, hints, and core compulsory papers are not modified.

Examples:
  python3 db/download_hoksi_solutions.py --subject m1 --year 2015
  python3 db/seed_hoksi_solutions.py --dry-run --subject m1 --year 2015
  python3 db/seed_hoksi_solutions.py --emit-sql --subject m1 --year 2015
  python3 db/seed_hoksi_solutions.py --apply --subject m1 --year 2015
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from hoksi_solutions import (
    ColumnInfo,
    canonical_layout,
    gap_report,
    layout_from_columns,
    load_bundle,
    render_report,
    render_sql,
    resolve_download_root,
    TOPIC_BY_SUBJECT,
)

SCRIPT_DIR = Path(__file__).resolve().parent
SCHEMA_PATH = SCRIPT_DIR / "solutions_schema.sql"
CONTENT_TABLES = ("papers", "questions", "solutions")


def mysql_command(database: str) -> list[str]:
    command = [
        os.environ.get("MYSQL_BIN", "mysql"),
        "--batch",
        "--connect-timeout=10",
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
    command.append(database)
    return command


def mysql_exec(sql: str, database: str, capture: bool) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        mysql_command(database),
        input=sql,
        text=True,
        capture_output=capture,
        check=False,
    )


def require_database() -> str:
    database = os.environ.get("MYSQL_DATABASE", "")
    if not database:
        raise SystemExit(
            "Refusing to apply: set MYSQL_DATABASE (and MYSQL_HOST, MYSQL_PORT, "
            "MYSQL_USER, MYSQL_PWD) on the machine that hosts alphaeqt. "
            "This script does not contact a database during --dry-run."
        )
    return database


def parse_show_columns(text: str) -> dict[str, ColumnInfo]:
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return {}
    header = lines[0].split("\t")
    try:
        field_index = header.index("Field")
        null_index = header.index("Null")
    except ValueError as exc:
        raise SystemExit(f"unexpected SHOW COLUMNS header: {header}") from exc
    columns: dict[str, ColumnInfo] = {}
    for line in lines[1:]:
        parts = line.split("\t")
        name = parts[field_index]
        columns[name] = ColumnInfo(name=name, nullable=parts[null_index].upper() == "YES")
    return columns


def probe_tables(database: str) -> dict[str, dict[str, ColumnInfo]]:
    found: dict[str, dict[str, ColumnInfo]] = {}
    for table in CONTENT_TABLES:
        completed = mysql_exec(f"SHOW COLUMNS FROM `{table}`;", database, capture=True)
        if completed.returncode != 0:
            stderr = (completed.stderr or "").lower()
            if "1146" in stderr or "doesn't exist" in stderr or "does not exist" in stderr:
                continue
            sys.stderr.write(completed.stderr or "")
            raise SystemExit(f"mysql exited {completed.returncode} while reading {table}")
        found[table] = parse_show_columns(completed.stdout or "")
    return found


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subject", required=True, choices=["m1", "m2", "pm", "ms"])
    parser.add_argument(
        "--year",
        action="append",
        default=[],
        help="Year label to load (2015, SP, PP). Repeatable. Default: every downloaded folder.",
    )
    parser.add_argument("--lang", default="zh-HK")
    parser.add_argument(
        "--download-root",
        help="Hoksi tree. Default: HOKSI_DOWNLOAD_ROOT, then ./downloads/hoksi, then AlphaEqtContent.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print the report. This is the default.")
    parser.add_argument(
        "--check",
        action="store_true",
        help="Exit 1 when a selected paper is missing a question number or a body is empty.",
    )
    parser.add_argument(
        "--emit-sql",
        action="store_true",
        help="Print SQL for db/solutions_schema.sql. Does not connect.",
    )
    parser.add_argument(
        "--with-schema",
        action="store_true",
        help="With --emit-sql, prepend db/solutions_schema.sql.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help=(
            "Write through the local mysql client. Creates papers/questions/solutions "
            "only when all three are absent. When they already exist, maps known "
            "column names and refuses if a solution cannot be attached."
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    selected = sum(bool(flag) for flag in (args.check, args.emit_sql, args.apply))
    if args.dry_run and selected:
        print("--dry-run cannot be combined with --check, --emit-sql, or --apply", file=sys.stderr)
        return 2
    if selected > 1:
        print("use only one of --check, --emit-sql, --apply", file=sys.stderr)
        return 2

    if args.subject in {"pm", "ms"}:
        print(gap_report())
        print(render_report(load_bundle(Path("."), args.subject, lang=args.lang)))
        return 0 if not selected else 1

    topic_slug = TOPIC_BY_SUBJECT[args.subject]
    try:
        root = resolve_download_root(
            args.download_root,
            os.environ.get("HOKSI_DOWNLOAD_ROOT"),
            topic_slug,
            args.lang,
        )
    except FileNotFoundError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    years = set(args.year) if args.year else None
    bundle = load_bundle(root, args.subject, years=years, lang=args.lang)
    report = render_report(bundle)
    if args.check and (bundle.errors or any(notice.level == "warning" for notice in bundle.notices)):
        print(report, file=sys.stderr)
        return 1
    if bundle.errors and (args.emit_sql or args.apply or args.check):
        print(report, file=sys.stderr)
        return 1
    if bundle.errors and not (args.emit_sql or args.apply):
        print(report, file=sys.stderr)
        return 1

    if args.emit_sql or args.apply:
        try:
            if args.apply:
                database = require_database()
                tables = probe_tables(database)
                present = [name for name in CONTENT_TABLES if name in tables]
                if not present:
                    sql = SCHEMA_PATH.read_text(encoding="utf-8") + "\n" + render_sql(bundle)
                elif present == list(CONTENT_TABLES):
                    sql = render_sql(bundle, layout_from_columns(tables))
                else:
                    print(
                        "content tables are only partly present: "
                        + ", ".join(present)
                        + ". Refusing to create the missing ones beside an existing shape.",
                        file=sys.stderr,
                    )
                    return 1
                completed = mysql_exec(sql, database, capture=False)
                if completed.returncode != 0:
                    return completed.returncode
            else:
                sql = render_sql(bundle, canonical_layout())
                if args.with_schema:
                    sql = SCHEMA_PATH.read_text(encoding="utf-8") + "\n" + sql
                sys.stdout.write(sql)
                return 0
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
