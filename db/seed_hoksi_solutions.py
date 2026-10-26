#!/usr/bin/env python3
"""Load Hoksi M1/M2 worked solutions into the live alphaeqt editorial tables.

The default is a dry run. It reads the JSON tree written by
db/download_hoksi_solutions.py (the same layout as core's
downloads/hoksi/hkdse-maths-core-solutions) and prints how many solution
rows would be written. It does not connect to MySQL.

--apply and --emit-sql read SHOW COLUMNS and write through content_blocks:
questions.stem_block_id points at a label block, and solutions.content_block_id
plus sortorder point at the worked solution. They do not ALTER tables and
they do not create a question_no/body schema.

Slugs are only dse{year}-math-m1, dse{year}-math-m2, dsesp-math-m1,
dsesp-math-m2, dsepp-math-m1, and dsepp-math-m2. Analyse tables, sq_keys,
answers, hints, and core compulsory papers are not modified.

The on-disk packs (zh-HK and en) live at
/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi/. Omit --lang
to load every language directory found there.

Examples:
  HOKSI_DOWNLOAD_ROOT=/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi \\
    python3 db/seed_hoksi_solutions.py --dry-run --subject m1 --year 2015
  python3 db/seed_hoksi_solutions.py --emit-sql --subject m1 --year 2015
  python3 db/seed_hoksi_solutions.py --apply --subject m1 --year 2015
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys

from hoksi_solutions import (
    ColumnInfo,
    gap_report,
    load_bundle,
    parse_show_index,
    render_for_tables,
    render_report,
    resolve_download_root,
    TOPIC_BY_SUBJECT,
)

PROBE_TABLES = ("papers", "questions", "solutions", "content_blocks")


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
            "Refusing to write SQL: set MYSQL_DATABASE (and MYSQL_HOST, MYSQL_PORT, "
            "MYSQL_USER, MYSQL_PWD) on the machine that hosts alphaeqt. "
            "--apply and --emit-sql read SHOW COLUMNS so the statement matches "
            "the live content_blocks model. --dry-run does not connect."
        )
    return database


def _header_index(header: list[str], name: str) -> int | None:
    return header.index(name) if name in header else None


def _cell(parts: list[str], index: int | None) -> str:
    if index is None or index >= len(parts):
        return ""
    return parts[index]


def parse_show_columns(text: str) -> dict[str, ColumnInfo]:
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return {}
    header = lines[0].split("\t")
    field_index = _header_index(header, "Field")
    null_index = _header_index(header, "Null")
    if field_index is None or null_index is None:
        raise SystemExit(f"unexpected SHOW COLUMNS header: {header}")
    type_index = _header_index(header, "Type")
    key_index = _header_index(header, "Key")
    default_index = _header_index(header, "Default")
    extra_index = _header_index(header, "Extra")
    columns: dict[str, ColumnInfo] = {}
    for line in lines[1:]:
        parts = line.split("\t")
        name = parts[field_index]
        raw_default = _cell(parts, default_index)
        if raw_default.upper() in {"", "NULL", r"\N"}:
            default = None
        else:
            default = raw_default
        columns[name] = ColumnInfo(
            name=name,
            nullable=_cell(parts, null_index).upper() == "YES",
            column_type=_cell(parts, type_index),
            default=default,
            extra=_cell(parts, extra_index),
            key=_cell(parts, key_index),
        )
    return columns


def _probe_statement(sql: str, database: str, label: str) -> subprocess.CompletedProcess[str] | None:
    completed = mysql_exec(sql, database, capture=True)
    if completed.returncode != 0:
        stderr = (completed.stderr or "").lower()
        if "1146" in stderr or "doesn't exist" in stderr or "does not exist" in stderr:
            return None
        sys.stderr.write(completed.stderr or "")
        raise SystemExit(f"mysql exited {completed.returncode} while reading {label}")
    return completed


def probe_tables(database: str) -> dict[str, dict[str, ColumnInfo]]:
    found: dict[str, dict[str, ColumnInfo]] = {}
    for table in PROBE_TABLES:
        completed = _probe_statement(f"SHOW COLUMNS FROM `{table}`;", database, table)
        if completed is None:
            continue
        found[table] = parse_show_columns(completed.stdout or "")
    return found


def probe_unique_keys(database: str, tables: dict[str, dict[str, ColumnInfo]]) -> dict[str, tuple[tuple[str, ...], ...]]:
    found: dict[str, tuple[tuple[str, ...], ...]] = {}
    for table in tables:
        completed = _probe_statement(f"SHOW INDEX FROM `{table}`;", database, f"{table} indexes")
        if completed is None:
            found[table] = ()
            continue
        try:
            found[table] = parse_show_index(completed.stdout or "")
        except ValueError as exc:
            raise SystemExit(str(exc)) from exc
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
    parser.add_argument(
        "--lang",
        default=None,
        help="zh-HK or en. Omit to load every language directory on disk (both, when both were downloaded).",
    )
    parser.add_argument(
        "--download-root",
        help=(
            "Hoksi tree. Default: HOKSI_DOWNLOAD_ROOT, then "
            "/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi, "
            "then ./downloads/hoksi."
        ),
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
        help=(
            "Print INSERT/UPDATE SQL for the live columns. Connects only to run "
            "SHOW COLUMNS / SHOW INDEX. Requires MYSQL_DATABASE."
        ),
    )
    parser.add_argument(
        "--with-schema",
        action="store_true",
        help="Rejected. db/solutions_schema.sql is not the live alphaeqt shape.",
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help=(
            "Write through the local mysql client into content_blocks and the "
            "existing papers, questions, and solutions tables. Does not ALTER "
            "and does not create a question_no/body schema."
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

    if args.with_schema:
        print(
            "error: db/solutions_schema.sql is not the live alphaeqt shape. "
            "--apply writes content_blocks and does not create that file.",
            file=sys.stderr,
        )
        return 2

    if args.emit_sql or args.apply:
        try:
            database = require_database()
            tables = probe_tables(database)
            sql = render_for_tables(bundle, tables, probe_unique_keys(database, tables))
            if args.emit_sql:
                sys.stdout.write(sql)
                return 0
            completed = mysql_exec(sql, database, capture=False)
            if completed.returncode != 0:
                return completed.returncode
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1

    print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
