#!/usr/bin/env python3
"""Download Hoksi M1/M2 worked solutions the same way core downloaded its pack.

Core used AlphaEqtContent's Vite plugin against

    https://hoksiresources.com/api/topics/hkdse-maths-core-solutions

and wrote `downloads/hoksi/<topic>/<lang>/`. This script calls that API for
the M1 and M2 topics and writes the same JSON + Markdown tree. It does not
download core, HKCEE, Pure Maths, or M&S.

Examples:
  python3 db/download_hoksi_solutions.py --inventory
  python3 db/download_hoksi_solutions.py --subject m1 --year 2015
  HOKSI_DOWNLOAD_ROOT=~/Desktop/swift/AlphaEqtContent/downloads/hoksi \\
    python3 db/download_hoksi_solutions.py --subject m2
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

from hoksi_solutions import (
    BLOCKED_TOPICS,
    HOKSI_API,
    HOKSI_ORIGIN,
    ON_DISK_ROOT,
    PACK_LANGS,
    TOPIC_BY_SUBJECT,
    catalogue_summary,
    folder_year_label,
    gap_report,
    hoksi_html_to_markdown,
)

USER_AGENT = "AlphaEqtContent/0.1"


def fetch_json(path: str) -> dict:
    url = HOKSI_API + path
    request = urllib.request.Request(
        url,
        headers={"Accept": "application/json", "User-Agent": USER_AGENT},
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"Hoksi HTTP {exc.code} for {url}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Hoksi request failed for {url}: {exc.reason}") from exc
    if not isinstance(payload, dict):
        raise SystemExit(f"Hoksi returned {type(payload).__name__} for {url}")
    return payload


def default_root() -> Path:
    env = os.environ.get("HOKSI_DOWNLOAD_ROOT")
    if env:
        return Path(env).expanduser()
    if ON_DISK_ROOT.is_dir():
        return ON_DISK_ROOT
    return Path("downloads") / "hoksi"


def langs_to_fetch(values: list[str]) -> list[str]:
    if not values or "all" in values:
        return list(PACK_LANGS)
    return values


def write_json(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def article_markdown(data: dict) -> str:
    title = str(data.get("name") or data.get("slug") or "article")
    sections = sorted(
        data.get("sections") or [],
        key=lambda section: section.get("sort_order") or 0,
    )
    parts = [f"# {title}", "", f"<!-- source: {data.get('slug') or ''} -->", ""]
    for section in sections:
        parts.append(hoksi_html_to_markdown(str(section.get("content") or "")))
        parts.append("")
    return "\n".join(parts).strip() + "\n"


def download_subject(
    subject: str,
    root: Path,
    years: set[str] | None,
    lang: str,
    refresh: bool,
) -> int:
    if subject not in TOPIC_BY_SUBJECT:
        print(gap_report() if subject in {"pm", "ms"} else f"unknown subject {subject}", file=sys.stderr)
        return 1
    topic_slug = TOPIC_BY_SUBJECT[subject]
    if topic_slug in BLOCKED_TOPICS:
        print(BLOCKED_TOPICS[topic_slug], file=sys.stderr)
        return 1

    topic = fetch_json(f"/topics/{topic_slug}")
    out_dir = root / topic_slug / lang
    out_dir.mkdir(parents=True, exist_ok=True)
    write_json(out_dir / "_topic.json", topic)

    wanted = {year.upper() for year in years} if years else None
    saved = 0
    skipped = 0
    index_rows = [
        f"# {topic.get('name') or topic_slug} ({lang})",
        "",
        f"Source: {HOKSI_ORIGIN}/{lang}/topics/{topic_slug}",
        "",
        "| Folder | Article | File |",
        "|--------|---------|------|",
    ]
    for folder in topic.get("folders") or []:
        folder_slug = str(folder.get("slug") or "")
        folder_name = str(folder.get("name") or folder_slug)
        try:
            year_label = folder_year_label(folder_name, folder_slug)
        except ValueError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 1
        if wanted is not None and year_label not in wanted:
            continue
        for article in folder.get("articles") or []:
            article_slug = str(article.get("slug") or "")
            article_name = str(article.get("name") or article_slug)
            folder_dir = out_dir / folder_slug
            json_path = folder_dir / f"{article_slug}.json"
            md_path = folder_dir / f"{article_slug}.md"
            if json_path.is_file() and md_path.is_file() and not refresh:
                skipped += 1
            else:
                data = fetch_json(
                    f"/articles/{urllib.request.quote(article_slug)}?lang={urllib.request.quote(lang)}"
                )
                write_json(json_path, data)
                md_path.write_text(article_markdown(data), encoding="utf-8")
                saved += 1
                print(f"saved {subject} {year_label} {article_name}", file=sys.stderr)
            index_rows.append(
                f"| {folder_name} | {article_name} | [{folder_slug}/{article_slug}.md]({folder_slug}/{article_slug}.md) |"
            )
    (out_dir / "README.md").write_text("\n".join(index_rows) + "\n", encoding="utf-8")
    print(
        f"topic {topic_slug} lang {lang}\n"
        f"dir {out_dir}\n"
        f"saved {saved}\n"
        f"skipped {skipped}"
    )
    return 0


def print_inventory() -> int:
    print(gap_report())
    print()
    for subject, topic_slug in TOPIC_BY_SUBJECT.items():
        topic = fetch_json(f"/topics/{topic_slug}")
        print(catalogue_summary(topic, subject))
        print()
    print("Blocked topics (not downloaded):")
    for slug, reason in BLOCKED_TOPICS.items():
        print(f"  {slug}: {reason}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--subject", choices=["m1", "m2", "pm", "ms"], help="Pack to download.")
    parser.add_argument(
        "--year",
        action="append",
        default=[],
        help="Limit articles to this year label (2015, SP, PP). Repeatable. Default: every folder.",
    )
    parser.add_argument(
        "--lang",
        action="append",
        default=[],
        help="zh-HK, en, or all. Repeatable. Default: both zh-HK and en.",
    )
    parser.add_argument(
        "--download-root",
        help=(
            "Output root. Default: HOKSI_DOWNLOAD_ROOT, the AlphaEqtContent "
            "tree at /Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi "
            "when that directory exists, otherwise ./downloads/hoksi."
        ),
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="Re-download article JSON even when the file is already present.",
    )
    parser.add_argument(
        "--inventory",
        action="store_true",
        help="Print the live M1/M2 catalogue and the Pure Maths / M&S gaps. Writes nothing.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.inventory:
        if args.subject or args.year:
            print("--inventory does not take --subject or --year", file=sys.stderr)
            return 2
        return print_inventory()
    if not args.subject:
        print("pass --subject m1 or --subject m2, or --inventory", file=sys.stderr)
        return 2
    if args.subject in {"pm", "ms"}:
        print(gap_report(), file=sys.stderr)
        return 1
    root = Path(args.download_root).expanduser() if args.download_root else default_root()
    years = set(args.year) if args.year else None
    status = 0
    for lang in langs_to_fetch(args.lang):
        status = download_subject(args.subject, root, years, lang, args.refresh)
        if status != 0:
            return status
    return status


if __name__ == "__main__":
    raise SystemExit(main())
