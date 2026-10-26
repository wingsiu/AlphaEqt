#!/usr/bin/env python3
"""Read Hoksi M1/M2 worked solutions and render papers → questions → solutions.

Core downloaded `hkdse-maths-core-solutions` through AlphaEqtContent into
`downloads/hoksi/<topic>/<lang>/`. This module reads the same tree for

- `hkdse-maths-m1-solutions`
- `hkdse-maths-m2-solutions`

and turns each article into one solution row. It does not download or write
the core topic, HKCEE, Pure Maths, or M&S, and it does not touch Analyse
tables or `sq_keys`.

`load_bundle` is the hook a later editorial API can call. This module does
not open MySQL.
"""

from __future__ import annotations

import html
import json
import re
from dataclasses import dataclass, field
from pathlib import Path

HOKSI_ORIGIN = "https://hoksiresources.com"
HOKSI_API = HOKSI_ORIGIN + "/api"

TOPIC_BY_SUBJECT = {
    "m1": "hkdse-maths-m1-solutions",
    "m2": "hkdse-maths-m2-solutions",
}

# Both languages are already saved beside the core pack.
ON_DISK_ROOT = Path("/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi")
PACK_LANGS = ("zh-HK", "en")

BLOCKED_TOPICS = {
    "hkdse-maths-core-solutions": (
        "core compulsory solutions stay on the existing core path; "
        "this ingest does not download or write them"
    ),
    "hkcee-maths-solutions": (
        "HKCEE Mathematics (Paper 1 sections and Paper 2 MC), not M&S "
        "and not Pure Maths"
    ),
}

SUBJECTS_WITH_PACKS = frozenset(TOPIC_BY_SUBJECT)
GAP_SUBJECTS = frozenset({"pm", "ms"})
MODULE_SUBJECTS = SUBJECTS_WITH_PACKS | GAP_SUBJECTS

PAPER_SLUG = re.compile(r"^dse(?:\d{4}|sp|pp)-math-m[12]$")
CORE_SLUG = re.compile(r"math-(?:cp|core)|-core(?:-|$)")

# Logical column → names seen on editorial tables, first match wins.
PAPER_ALIASES = {
    "slug": ("slug", "paper_slug", "code"),
    "title": ("title", "name"),
    "subject": ("subject", "module", "syllabus", "paper_type"),
    "year_label": ("year_label", "year_key", "label"),
    "year": ("year", "exam_year", "calendar_year"),
    "paper_no": ("paper_no", "paper_number"),
    "source": ("source", "origin"),
    "source_topic": ("source_topic", "topic_slug", "hoksi_topic"),
}
QUESTION_ALIASES = {
    "paper_id": ("paper_id", "papers_id"),
    "question_no": ("question_no", "q_no", "question_number", "number", "qno"),
    "slug": ("slug", "question_slug", "code"),
    "title": ("title", "name"),
}
SOLUTION_ALIASES = {
    "question_id": ("question_id", "questions_id"),
    "lang": ("lang", "language", "locale"),
    "format": ("format", "content_format", "body_format"),
    "body": (
        "body",
        "content",
        "markdown",
        "md",
        "latex",
        "tex",
        "solution",
        "solution_text",
        "text",
    ),
    "html": ("html", "html_body", "source_html", "raw_html"),
    "source": ("source", "origin"),
    "source_slug": ("source_slug", "hoksi_slug", "external_slug", "article_slug"),
    "source_url": ("source_url", "url", "source_link"),
}

SOURCE_NAME = "hoksi"
PROTECTED_TABLES = (
    "analyse_mc",
    "analyse_mc_units",
    "analyse_sq",
    "analyse_sq_units",
    "analyse_units",
    "analyse_unit_qtypes",
    "analyse_m1_units",
    "analyse_m1_sq",
    "analyse_m1_sq_units",
    "analyse_pm_units",
    "analyse_pm_sq",
    "analyse_pm_sq_units",
    "sq_keys",
    "mc_keys",
    "answers",
    "hints",
)


@dataclass(frozen=True)
class Notice:
    level: str
    message: str


@dataclass(frozen=True)
class PlannedQuestion:
    subject: str
    year_label: str
    year: int | None
    question_no: int
    paper_slug: str
    question_slug: str
    paper_title: str
    question_title: str
    source_topic: str
    folder_slug: str
    article_slug: str


@dataclass
class SolutionRow:
    planned: PlannedQuestion
    lang: str
    body: str
    html: str
    body_format: str
    source_url: str


@dataclass
class Bundle:
    source: str
    subject: str
    lang: str
    rows: tuple[SolutionRow, ...] = ()
    notices: tuple[Notice, ...] = ()
    planned: tuple[PlannedQuestion, ...] = ()

    @property
    def errors(self) -> tuple[Notice, ...]:
        return tuple(notice for notice in self.notices if notice.level == "error")


@dataclass(frozen=True)
class ColumnInfo:
    name: str
    nullable: bool


@dataclass(frozen=True)
class Layout:
    """Physical column names for papers, questions, and solutions."""

    paper: dict[str, str]
    question: dict[str, str]
    solution: dict[str, str]
    paper_nullable: dict[str, bool] = field(default_factory=dict)
    question_nullable: dict[str, bool] = field(default_factory=dict)
    solution_nullable: dict[str, bool] = field(default_factory=dict)
    paper_id: str = "id"
    question_id: str = "id"

    def paper_col(self, logical: str) -> str | None:
        return self.paper.get(logical)

    def question_col(self, logical: str) -> str | None:
        return self.question.get(logical)

    def solution_col(self, logical: str) -> str | None:
        return self.solution.get(logical)


def canonical_layout() -> Layout:
    return Layout(
        paper={
            "slug": "slug",
            "title": "title",
            "subject": "subject",
            "year_label": "year_label",
            "year": "year",
            "paper_no": "paper_no",
            "source": "source",
            "source_topic": "source_topic",
        },
        question={
            "paper_id": "paper_id",
            "question_no": "question_no",
            "slug": "slug",
            "title": "title",
        },
        solution={
            "question_id": "question_id",
            "lang": "lang",
            "format": "format",
            "body": "body",
            "html": "html",
            "source": "source",
            "source_slug": "source_slug",
            "source_url": "source_url",
        },
        paper_nullable={"year": True, "paper_no": True, "source_topic": True},
        question_nullable={"title": True},
        solution_nullable={"html": True, "source_url": True},
    )


def gap_report() -> str:
    return "\n".join(
        [
            "Hoksi subject hkdse-maths exposes solution topics for core, M1, and M2.",
            "M1 pack: hkdse-maths-m1-solutions (suggested worked solutions, zh-HK and en).",
            "M2 pack: hkdse-maths-m2-solutions (suggested worked solutions, zh-HK and en).",
            "Pure Maths: blocked. No Hoksi subject or topic, so nothing is ingested.",
            "M&S: blocked. No Hoksi subject or topic, so nothing is ingested.",
            "hkcee-maths-solutions is HKCEE Mathematics (1998–2011 Paper 1/2),",
            "not Mathematics & Statistics and not Pure Maths. It is not ingested.",
            "2026 M1 and 2026 M2 are present on Hoksi as suggested solutions.",
            "They are loaded only because those articles exist. No official",
            "marking scheme is invented for a year Hoksi does not list.",
            "DiskStation marking-scheme PDFs are not the source for this path.",
            "PDF/OCR is not used. Article HTML is converted to Markdown with",
            "LaTeX in $ / $$, and the original HTML is stored beside it.",
        ]
    )


def candidate_download_roots() -> list[Path]:
    """Places a core-style Hoksi tree may already live.

    The packs downloaded by AlphaEqtContent sit next to core at ON_DISK_ROOT.
    """
    home = Path.home()
    return [
        ON_DISK_ROOT,
        home / "Desktop" / "swift" / "AlphaEqtContent" / "downloads" / "hoksi",
        Path("AlphaEqtContent") / "downloads" / "hoksi",
        home / "swift" / "AlphaEqtContent" / "downloads" / "hoksi",
        home / "AlphaEqtContent" / "downloads" / "hoksi",
        Path("downloads") / "hoksi",
    ]


def language_dirs(root: Path, topic_slug: str) -> tuple[tuple[str, Path], ...]:
    """Return `(lang, directory)` for each saved Hoksi language.

    AlphaEqtContent writes `downloads/hoksi/<topic>/<lang>/`. An older zh-HK
    download may sit directly in `<topic>/`.
    """
    base = root / topic_slug
    if not base.is_dir():
        return ()
    found: list[tuple[str, Path]] = []
    seen: set[str] = set()
    for lang in PACK_LANGS + ("zh-TW", "zh"):
        path = base / lang
        if (path / "_topic.json").is_file():
            found.append((lang, path))
            seen.add(lang)
    if base.is_dir():
        for child in sorted(base.iterdir(), key=lambda item: item.name):
            if not child.is_dir() or child.name in seen or child.name.startswith("."):
                continue
            if (child / "_topic.json").is_file():
                found.append((child.name, child))
                seen.add(child.name)
    if "zh-HK" not in seen and (base / "_topic.json").is_file():
        found.insert(0, ("zh-HK", base))
    return tuple(found)


def resolve_download_root(
    explicit: str | None,
    env: str | None,
    topic_slug: str | None = None,
    lang: str | None = None,
) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if not path.is_dir():
            raise FileNotFoundError(f"Hoksi download root not found: {path}")
        return path
    if env:
        path = Path(env).expanduser()
        if not path.is_dir():
            raise FileNotFoundError(f"HOKSI_DOWNLOAD_ROOT does not exist: {path}")
        return path
    checked: list[Path] = []
    first_existing: Path | None = None
    for root in candidate_download_roots():
        checked.append(root)
        if not root.is_dir():
            continue
        if first_existing is None:
            first_existing = root
        if topic_slug and _topic_is_present(root, topic_slug, lang):
            return root
    if first_existing is not None and topic_slug is None:
        return first_existing
    searched = "\n".join(f"  - {path}" for path in checked)
    raise FileNotFoundError(
        "No Hoksi download tree was found. Run db/download_hoksi_solutions.py "
        "or set HOKSI_DOWNLOAD_ROOT to AlphaEqtContent/downloads/hoksi.\n"
        f"Looked in:\n{searched}"
    )


def paper_slug(subject: str, year_label: str) -> str:
    if subject not in SUBJECTS_WITH_PACKS:
        raise ValueError(f"no paper slug for subject {subject}")
    label = year_label.strip()
    if label in {"SP", "PP"}:
        token = label.lower()
    elif re.fullmatch(r"20\d{2}", label):
        token = label
    else:
        raise ValueError(f"year label {year_label!r} is not a DSE year, SP, or PP")
    slug = f"dse{token}-math-{subject}"
    if not PAPER_SLUG.fullmatch(slug) or CORE_SLUG.search(slug):
        raise ValueError(f"refusing slug {slug}")
    return slug


def question_slug(parent: str, question_no: int) -> str:
    if question_no < 1:
        raise ValueError(f"question number {question_no} is out of range")
    return f"{parent}-q{question_no}"


def assert_module_slugs(slugs: list[str]) -> None:
    for slug in slugs:
        if CORE_SLUG.search(slug) or not PAPER_SLUG.fullmatch(slug):
            raise ValueError(f"refusing to write paper slug {slug}")


def folder_year_label(name: str, folder_slug: str) -> str:
    blob = f"{name} {folder_slug}"
    if re.search(r"sample", blob, re.IGNORECASE):
        return "SP"
    if re.search(r"practice", blob, re.IGNORECASE):
        return "PP"
    match = re.search(r"\b(20\d{2})\b", name) or re.search(r"(20\d{2})", folder_slug)
    if not match:
        raise ValueError(f"folder {name!r} ({folder_slug}) has no year")
    return match.group(1)


def calendar_year(year_label: str) -> int | None:
    if re.fullmatch(r"20\d{2}", year_label):
        return int(year_label)
    return None


def question_number(name: str, article_slug: str) -> int | None:
    match = re.search(r"\bQ\s*(\d+)\b", name, re.IGNORECASE)
    if match:
        return int(match.group(1))
    match = re.search(r"(?:^|-)q(\d+)$", article_slug, re.IGNORECASE)
    if match:
        return int(match.group(1))
    return None


def plan_from_topic(
    topic: dict,
    subject: str,
    years: set[str] | None = None,
) -> tuple[tuple[PlannedQuestion, ...], tuple[Notice, ...]]:
    topic_slug = str(topic.get("slug") or "")
    expected = TOPIC_BY_SUBJECT.get(subject)
    notices: list[Notice] = []
    if topic_slug in BLOCKED_TOPICS:
        notices.append(Notice("error", f"{topic_slug}: {BLOCKED_TOPICS[topic_slug]}"))
        return (), tuple(notices)
    if expected is None:
        notices.append(Notice("error", f"subject {subject} has no Hoksi solution pack"))
        return (), tuple(notices)
    if topic_slug != expected:
        notices.append(
            Notice("error", f"topic {topic_slug or '(missing)'} is not the {subject} pack {expected}")
        )
        return (), tuple(notices)

    wanted = {year.strip().upper() for year in years} if years else None
    if wanted is not None:
        normalized: set[str] = set()
        for year in wanted:
            if year in {"SP", "PP"} or re.fullmatch(r"20\d{2}", year):
                normalized.add(year)
            else:
                notices.append(Notice("error", f"year {year} is not a DSE year, SP, or PP"))
        wanted = normalized

    planned: list[PlannedQuestion] = []
    seen_years: set[str] = set()
    for folder in topic.get("folders") or []:
        folder_slug = str(folder.get("slug") or "")
        folder_name = str(folder.get("name") or folder_slug)
        try:
            year_label = folder_year_label(folder_name, folder_slug)
        except ValueError as exc:
            notices.append(Notice("error", str(exc)))
            continue
        seen_years.add(year_label)
        if wanted is not None and year_label not in wanted:
            continue
        parent = paper_slug(subject, year_label)
        title = folder_name.strip() or parent
        numbers: list[int] = []
        for article in folder.get("articles") or []:
            article_slug = str(article.get("slug") or "")
            article_name = str(article.get("name") or article_slug)
            number = question_number(article_name, article_slug)
            if number is None:
                notices.append(
                    Notice(
                        "error",
                        f"{folder_name}: article {article_slug} has no question number",
                    )
                )
                continue
            numbers.append(number)
            planned.append(
                PlannedQuestion(
                    subject=subject,
                    year_label=year_label,
                    year=calendar_year(year_label),
                    question_no=number,
                    paper_slug=parent,
                    question_slug=question_slug(parent, number),
                    paper_title=title,
                    question_title=article_name.strip() or f"Q{number}",
                    source_topic=topic_slug,
                    folder_slug=folder_slug,
                    article_slug=article_slug,
                )
            )
        if numbers:
            missing = [n for n in range(1, max(numbers) + 1) if n not in numbers]
            if missing:
                rendered = ", ".join(str(n) for n in missing)
                notices.append(
                    Notice(
                        "warning",
                        f"{subject} {year_label} is missing question numbers {rendered}",
                    )
                )
            dupes = sorted({n for n in numbers if numbers.count(n) > 1})
            if dupes:
                notices.append(
                    Notice(
                        "error",
                        f"{subject} {year_label} repeats question numbers {dupes}",
                    )
                )

    if wanted is not None:
        for year in sorted(wanted):
            if year not in seen_years:
                notices.append(
                    Notice("error", f"{subject} Hoksi topic has no folder for {year}")
                )
    planned.sort(key=lambda row: (row.year_label, row.question_no, row.article_slug))
    assert_module_slugs([row.paper_slug for row in planned])
    return tuple(planned), tuple(notices)


def hoksi_html_to_markdown(content: str) -> str:
    """Light HTML → Markdown, matching AlphaEqtContent's Hoksi converter.

    MathJax `\\( \\)` / `\\[ \\]` become remark-math `$` / `$$`. Tables are
    kept as Markdown tables so M1 probability grids survive tag stripping.
    The original HTML is stored separately; this pass is not OCR.
    """
    text = html.unescape(content or "")
    text = re.sub(
        r"<span\b[^>]*class=['\"][^'\"]*math-tex[^'\"]*['\"][^>]*>(.*?)</span>",
        lambda match: match.group(1).strip(),
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    text = _tables_to_markdown(text)

    def heading(match: re.Match[str]) -> str:
        inner = re.sub(r"<[^>]+>", "", match.group(2))
        inner = re.sub(r"\s+", " ", inner).strip()
        return f"\n{'#' * int(match.group(1))} {inner}\n\n"

    text = re.sub(
        r"<h([1-6])\b[^>]*>(.*?)</h\1>",
        heading,
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    text = re.sub(r"<br\s*/?>\s*<br\s*/?>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"<br\s*/?>", "  \n", text, flags=re.IGNORECASE)
    text = re.sub(r"</p>\s*<p\b[^>]*>", "\n\n", text, flags=re.IGNORECASE)
    text = re.sub(r"</?p\b[^>]*>", "\n", text, flags=re.IGNORECASE)
    text = re.sub(
        r"<(b|strong)\b[^>]*>(.*?)</\1>",
        r"**\2**",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    text = re.sub(
        r"<(i|em)\b[^>]*>(.*?)</\1>",
        r"*\2*",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    text = re.sub(
        r"<img\b[^>]*src=['\"]([^'\"]+)['\"][^>]*>",
        r"![](\1)",
        text,
        flags=re.IGNORECASE,
    )
    text = re.sub(
        r"<li\b[^>]*>(.*?)</li>",
        lambda match: "- " + re.sub(r"\s+", " ", match.group(1)).strip() + "\n",
        text,
        flags=re.IGNORECASE | re.DOTALL,
    )
    text = re.sub(r"</?(ul|ol|div|span)\b[^>]*>", "", text, flags=re.IGNORECASE)
    text = re.sub(r"<[^>]+>", "", text)
    text = (
        text.replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", '"')
        .replace("&#39;", "'")
        .replace("&nbsp;", " ")
        .replace("\r\n", "\n")
    )
    text = re.sub(
        r"\\\((.*?)\\\)",
        lambda match: f"${_sanitize_math_dollars(match.group(1).strip())}$",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(
        r"\\\[(.*?)\\\]",
        lambda match: f"\n$$\n{_sanitize_math_dollars(match.group(1).strip())}\n$$\n",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(r"\n{3,}", "\n\n", text).strip()
    return (text + "\n") if text else ""


def _sanitize_math_dollars(body: str) -> str:
    return body.replace("\\$", "\\unicode{x24}")


def _tables_to_markdown(text: str) -> str:
    def convert(match: re.Match[str]) -> str:
        rows = re.findall(r"<tr\b[^>]*>(.*?)</tr>", match.group(0), flags=re.IGNORECASE | re.DOTALL)
        parsed: list[list[str]] = []
        for row in rows:
            cells = re.findall(
                r"<t[hd]\b[^>]*>(.*?)</t[hd]>",
                row,
                flags=re.IGNORECASE | re.DOTALL,
            )
            parsed.append([_cell_text(cell) for cell in cells])
        parsed = [row for row in parsed if any(cell.strip() for cell in row)]
        if not parsed:
            return "\n"
        width = max(len(row) for row in parsed)
        padded = [row + [""] * (width - len(row)) for row in parsed]

        def line(cells: list[str]) -> str:
            escaped = [cell.replace("|", "\\|") for cell in cells]
            return "| " + " | ".join(escaped) + " |"

        lines = [
            line(padded[0]),
            "| " + " | ".join("---" for _ in padded[0]) + " |",
        ]
        lines.extend(line(row) for row in padded[1:])
        return "\n" + "\n".join(lines) + "\n"

    return re.sub(r"<table\b[^>]*>.*?</table>", convert, text, flags=re.IGNORECASE | re.DOTALL)


def _cell_text(cell: str) -> str:
    cell = re.sub(r"<br\s*/?>", " ", cell, flags=re.IGNORECASE)
    cell = re.sub(r"<[^>]+>", "", cell)
    return re.sub(r"\s+", " ", cell).strip()


def body_from_article(data: dict, title: str) -> tuple[str, str, str]:
    """Return (markdown, html, format) for one saved Hoksi article."""
    sections = sorted(
        data.get("sections") or [],
        key=lambda section: section.get("sort_order") or 0,
    )
    html_parts = [str(section.get("content") or "") for section in sections]
    raw_html = "\n".join(part for part in html_parts if part.strip()).strip()
    markdown_parts = [hoksi_html_to_markdown(part) for part in html_parts]
    body = "\n\n".join(part.strip() for part in markdown_parts if part.strip()).strip()
    if body:
        heading = title.strip() or str(data.get("name") or "").strip()
        if heading:
            body = f"# {heading}\n\n{body}\n"
        else:
            body += "\n"
        return body, raw_html, "markdown"
    if raw_html:
        return raw_html, raw_html, "html"
    return "", raw_html, "html"


def _read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def _topic_is_present(root: Path, topic_slug: str, lang: str | None) -> bool:
    pairs = language_dirs(root, topic_slug)
    if lang is None:
        return bool(pairs)
    return any(saved == lang for saved, _path in pairs)


def load_bundle(
    root: Path,
    subject: str,
    *,
    years: set[str] | None = None,
    lang: str | None = None,
) -> Bundle:
    """Load one subject from a core-style `downloads/hoksi` tree.

    `lang=None` reads every language directory on disk (`zh-HK` and `en`
    when both were downloaded). The stored language is that directory name,
    so an English file whose API payload still says `zh-HK` stays `en`.

    A later API can call this and serve `bundle.rows` without SQL.
    """
    if subject in GAP_SUBJECTS:
        message = (
            "Pure Maths is blocked: no Hoksi solution pack."
            if subject == "pm"
            else "M&S is blocked: no Hoksi solution pack. hkcee-maths-solutions is HKCEE Mathematics, not M&S."
        )
        return Bundle(
            source="",
            subject=subject,
            lang=lang or "",
            notices=(Notice("warning", message),),
        )
    if subject not in TOPIC_BY_SUBJECT:
        return Bundle(
            source="",
            subject=subject,
            lang=lang or "",
            notices=(Notice("error", f"unknown subject {subject}"),),
        )

    topic_slug = TOPIC_BY_SUBJECT[subject]
    pairs = language_dirs(root, topic_slug)
    if lang is not None:
        pairs = tuple(pair for pair in pairs if pair[0] == lang)
    if not pairs:
        expected = root / topic_slug / (lang or "zh-HK")
        return Bundle(
            source=str(root / topic_slug),
            subject=subject,
            lang=lang or "",
            notices=(
                Notice(
                    "error",
                    f"missing Hoksi articles under {expected}. "
                    f"The packs already on disk are in {ON_DISK_ROOT}. "
                    "Re-download from AlphaEqtContent (Download Hoksi) or "
                    f"python3 db/download_hoksi_solutions.py --subject {subject}"
                    + (f" --year {' --year '.join(sorted(years))}" if years else ""),
                ),
            ),
        )

    bundles = [
        _load_language(root, subject, topic_slug, saved_lang, topic_dir, years)
        for saved_lang, topic_dir in pairs
    ]
    return _merge_bundles(bundles, source=str(root / topic_slug))


def _load_language(
    root: Path,
    subject: str,
    topic_slug: str,
    lang: str,
    topic_dir: Path,
    years: set[str] | None,
) -> Bundle:
    del root
    topic = _read_json(topic_dir / "_topic.json")
    planned, notices = plan_from_topic(topic, subject, years)
    rows: list[SolutionRow] = []
    notice_list = list(notices)
    for item in planned:
        json_path = topic_dir / item.folder_slug / f"{item.article_slug}.json"
        md_path = topic_dir / item.folder_slug / f"{item.article_slug}.md"
        if json_path.is_file():
            article = _read_json(json_path)
            body, raw_html, body_format = body_from_article(article, item.question_title)
        elif md_path.is_file():
            body = md_path.read_text(encoding="utf-8")
            raw_html = ""
            body_format = "markdown"
            notice_list.append(
                Notice("warning", f"{lang} {item.article_slug} has Markdown only; HTML was not saved")
            )
        else:
            notice_list.append(
                Notice(
                    "error",
                    f"missing {lang} article for {item.paper_slug} Q{item.question_no}: {json_path}",
                )
            )
            continue
        if not body.strip():
            notice_list.append(
                Notice("error", f"{lang} {item.article_slug} has an empty solution body")
            )
            continue
        if body_format == "html":
            notice_list.append(
                Notice(
                    "warning",
                    f"{lang} {item.article_slug} has no text after HTML conversion; "
                    "the original HTML is stored as the body",
                )
            )
        rows.append(
            SolutionRow(
                planned=item,
                lang=lang,
                body=body,
                html=raw_html,
                body_format=body_format,
                source_url=f"{HOKSI_ORIGIN}/{lang}/articles/{item.article_slug}",
            )
        )
    return Bundle(
        source=str(topic_dir),
        subject=subject,
        lang=lang,
        rows=tuple(rows),
        notices=tuple(notice_list),
        planned=planned,
    )


def _merge_bundles(bundles: list[Bundle], source: str) -> Bundle:
    if len(bundles) == 1:
        only = bundles[0]
        return Bundle(
            source=source,
            subject=only.subject,
            lang=only.lang,
            rows=only.rows,
            notices=only.notices,
            planned=only.planned,
        )
    rows: list[SolutionRow] = []
    notices: list[Notice] = []
    planned: list[PlannedQuestion] = []
    langs: list[str] = []
    subject = bundles[0].subject
    for bundle in bundles:
        rows.extend(bundle.rows)
        notices.extend(bundle.notices)
        planned.extend(bundle.planned)
        if bundle.lang:
            langs.append(bundle.lang)
    return Bundle(
        source=source,
        subject=subject,
        lang=",".join(langs),
        rows=tuple(rows),
        notices=tuple(notices),
        planned=tuple(planned),
    )


def render_report(bundle: Bundle) -> str:
    lines = [
        f"source: {bundle.source or '(none)'}",
        f"subject: {bundle.subject}",
        f"lang: {bundle.lang}",
    ]
    by_paper: dict[str, list[SolutionRow]] = {}
    for row in bundle.rows:
        by_paper.setdefault(row.planned.paper_slug, []).append(row)
    counts: dict[str, int] = {}
    for row in bundle.rows:
        counts[row.lang] = counts.get(row.lang, 0) + 1
    if counts:
        lines.append(
            "langs: " + ", ".join(f"{lang} {counts[lang]}" for lang in sorted(counts))
        )
    lines.append(f"papers: {len(by_paper)}")
    lines.append(f"solutions: {len(bundle.rows)}")
    for slug in sorted(by_paper):
        group = by_paper[slug]
        questions = sorted({row.planned.question_no for row in group})
        span = f"q{questions[0]}-q{questions[-1]}" if questions else "none"
        lines.append(
            f"{slug}: {len(group)} solutions, {len(questions)} questions ({span})"
        )
    for notice in bundle.notices:
        lines.append(f"{notice.level}: {notice.message}")
    if bundle.subject in GAP_SUBJECTS and not bundle.rows:
        lines.append("result: no hoksi pack")
    elif bundle.errors:
        lines.append("result: failed")
    else:
        lines.append("result: ok")
    return "\n".join(lines)


def sql_str(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "''").replace("\x00", "")
    return f"'{escaped}'"


def sql_nullable(value: str | None) -> str:
    if value is None:
        return "NULL"
    return sql_str(value)


def _quote_ident(name: str) -> str:
    if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
        raise ValueError(f"refusing SQL identifier {name!r}")
    return f"`{name}`"


def layout_from_columns(
    tables: dict[str, dict[str, ColumnInfo]],
) -> Layout:
    """Map an existing alphaeqt shape onto papers, questions, and solutions.

    `tables[table][column].nullable` comes from SHOW COLUMNS. A missing
    table key means that table is absent. This raises ValueError when the
    three tables exist but a solution cannot be attached.
    """
    missing = [name for name in ("papers", "questions", "solutions") if name not in tables]
    if missing:
        raise ValueError(
            "missing tables: " + ", ".join(missing) + ". Apply db/solutions_schema.sql first."
        )
    paper_cols = tables["papers"]
    question_cols = tables["questions"]
    solution_cols = tables["solutions"]
    if "id" not in paper_cols or "id" not in question_cols:
        raise ValueError("papers.id and questions.id are required to attach solutions")

    def pick(
        columns: dict[str, ColumnInfo],
        aliases: dict[str, tuple[str, ...]],
        required: tuple[str, ...],
        table: str,
    ) -> dict[str, str]:
        found: dict[str, str] = {}
        for logical, names in aliases.items():
            for name in names:
                if name in columns:
                    found[logical] = name
                    break
        absent = [logical for logical in required if logical not in found]
        if absent:
            present = ", ".join(sorted(columns)) or "(none)"
            raise ValueError(
                f"{table} is missing {', '.join(absent)}. Columns: {present}"
            )
        return found

    paper = pick(paper_cols, PAPER_ALIASES, ("slug",), "papers")
    question = pick(question_cols, QUESTION_ALIASES, ("paper_id", "question_no"), "questions")
    solution = pick(solution_cols, SOLUTION_ALIASES, ("question_id", "body"), "solutions")
    if solution.get("html") == solution.get("body"):
        solution.pop("html", None)
    return Layout(
        paper=paper,
        question=question,
        solution=solution,
        paper_nullable={key: paper_cols[value].nullable for key, value in paper.items()},
        question_nullable={
            key: question_cols[value].nullable for key, value in question.items()
        },
        solution_nullable={
            key: solution_cols[value].nullable for key, value in solution.items()
        },
    )


def render_sql(bundle: Bundle, layout: Layout | None = None) -> str:
    if bundle.subject in GAP_SUBJECTS:
        raise ValueError(f"{bundle.subject} has no Hoksi pack; refusing to emit SQL")
    if bundle.errors:
        details = "\n".join(notice.message for notice in bundle.errors)
        raise ValueError(f"refusing to render SQL with parse errors:\n{details}")
    if not bundle.rows:
        raise ValueError("refusing to render SQL with zero solutions")

    layout = layout or canonical_layout()
    slugs = sorted({row.planned.paper_slug for row in bundle.rows})
    assert_module_slugs(slugs)
    for slug in slugs:
        if not slug.endswith(f"-math-{bundle.subject}"):
            raise ValueError(f"slug {slug} is outside subject {bundle.subject}")

    paper_slug_col = _quote_ident(layout.paper["slug"])
    question_paper = _quote_ident(layout.question["paper_id"])
    question_no_col = _quote_ident(layout.question["question_no"])
    solution_question = _quote_ident(layout.solution["question_id"])
    papers_id = _quote_ident(layout.paper_id)
    questions_id = _quote_ident(layout.question_id)

    lines = [
        "-- Generated by db/seed_hoksi_solutions.py",
        f"-- Source: {bundle.source}",
        "-- Hoksi worked solutions only. Compulsory-core papers are not in this statement.",
        "SET NAMES utf8mb4;",
        "START TRANSACTION;",
    ]

    slug_list = ", ".join(sql_str(slug) for slug in slugs)
    delete = [
        "DELETE s FROM solutions s",
        f"INNER JOIN questions q ON q.{questions_id} = s.{solution_question}",
        f"INNER JOIN papers p ON p.{papers_id} = q.{question_paper}",
        f"WHERE p.{paper_slug_col} IN ({slug_list})",
    ]
    if "lang" in layout.solution:
        langs = sorted({row.lang for row in bundle.rows})
        rendered = ", ".join(sql_str(lang) for lang in langs)
        delete.append(f"AND s.{_quote_ident(layout.solution['lang'])} IN ({rendered})")
    if "source" in layout.solution:
        delete.append(
            f"AND s.{_quote_ident(layout.solution['source'])} = {sql_str(SOURCE_NAME)}"
        )
    lines.append(" ".join(delete) + ";")

    papers = []
    seen_papers: set[str] = set()
    for row in bundle.rows:
        if row.planned.paper_slug in seen_papers:
            continue
        seen_papers.add(row.planned.paper_slug)
        papers.append(row.planned)

    for paper in papers:
        columns, values, assignments = _paper_sql(paper, layout)
        lines.append(
            f"INSERT INTO papers ({', '.join(columns)}) "
            f"SELECT {', '.join(values)} FROM DUAL "
            f"WHERE NOT EXISTS (SELECT 1 FROM papers p WHERE p.{paper_slug_col} = {sql_str(paper.paper_slug)});"
        )
        if assignments:
            lines.append(
                f"UPDATE papers SET {', '.join(assignments)} "
                f"WHERE {paper_slug_col} = {sql_str(paper.paper_slug)};"
            )

    for row in bundle.rows:
        planned = row.planned
        columns, select_items, assignments = _question_sql(planned, layout)
        lines.append(
            f"INSERT INTO questions ({', '.join(columns)}) "
            f"SELECT {', '.join(select_items)} "
            f"FROM papers p "
            f"WHERE p.{paper_slug_col} = {sql_str(planned.paper_slug)} "
            f"AND NOT EXISTS ("
            f"SELECT 1 FROM questions q "
            f"WHERE q.{question_paper} = p.{papers_id} "
            f"AND q.{question_no_col} = {planned.question_no});"
        )
        if assignments:
            lines.append(
                "UPDATE questions q "
                f"INNER JOIN papers p ON p.{papers_id} = q.{question_paper} "
                f"SET {', '.join(assignments)} "
                f"WHERE p.{paper_slug_col} = {sql_str(planned.paper_slug)} "
                f"AND q.{question_no_col} = {planned.question_no};"
            )

    for row in bundle.rows:
        columns, select_items = _solution_sql(row, layout)
        lines.append(
            f"INSERT INTO solutions ({', '.join(columns)}) "
            f"SELECT {', '.join(select_items)} "
            "FROM questions q "
            f"INNER JOIN papers p ON p.{papers_id} = q.{question_paper} "
            f"WHERE p.{paper_slug_col} = {sql_str(row.planned.paper_slug)} "
            f"AND q.{question_no_col} = {row.planned.question_no};"
        )

    lines.append("COMMIT;")
    lines.append("")
    sql = "\n".join(lines)
    _assert_sql_scope(sql)
    return sql


def _paper_sql(
    paper: PlannedQuestion, layout: Layout
) -> tuple[list[str], list[str], list[str]]:
    logical_values: dict[str, str] = {
        "slug": sql_str(paper.paper_slug),
        "title": sql_str(paper.paper_title),
        "subject": sql_str(paper.subject),
        "year_label": sql_str(paper.year_label),
        "year": "NULL" if paper.year is None else str(paper.year),
        "paper_no": "NULL",
        "source": sql_str(SOURCE_NAME),
        "source_topic": sql_str(paper.source_topic),
    }
    if paper.year is None and not layout.paper_nullable.get("year", True):
        raise ValueError(
            f"{paper.paper_slug}: papers.year is NOT NULL, so sample/practice "
            "papers are not written (a 2022 practice paper must not share the "
            "2022 exam year)"
        )
    if not layout.paper_nullable.get("paper_no", True) and "paper_no" in layout.paper:
        logical_values["paper_no"] = "1"
    return _paired(layout.paper, logical_values, layout.paper_nullable, skip_null=False)


def _question_sql(
    planned: PlannedQuestion, layout: Layout
) -> tuple[list[str], list[str], list[str]]:
    logical_values = {
        "paper_id": f"p.{_quote_ident(layout.paper_id)}",
        "question_no": str(planned.question_no),
        "slug": sql_str(planned.question_slug),
        "title": sql_str(planned.question_title),
    }
    columns, select_items, _assignments = _paired(
        layout.question, logical_values, layout.question_nullable, skip_null=False
    )
    assignments = []
    for logical, physical in layout.question.items():
        if logical == "paper_id":
            continue
        if logical not in logical_values:
            continue
        assignments.append(
            f"q.{_quote_ident(physical)} = {logical_values[logical]}"
        )
    return columns, select_items, assignments


def _solution_sql(row: SolutionRow, layout: Layout) -> tuple[list[str], list[str]]:
    logical_values = {
        "question_id": f"q.{_quote_ident(layout.question_id)}",
        "lang": sql_str(row.lang),
        "format": sql_str(row.body_format),
        "body": sql_str(row.body),
        "html": sql_nullable(row.html or None),
        "source": sql_str(SOURCE_NAME),
        "source_slug": sql_str(row.planned.article_slug),
        "source_url": sql_str(row.source_url),
    }
    columns, select_items, _assignments = _paired(
        layout.solution,
        logical_values,
        layout.solution_nullable,
        skip_null=False,
    )
    return columns, select_items


def _paired(
    mapping: dict[str, str],
    logical_values: dict[str, str],
    nullable: dict[str, bool],
    skip_null: bool,
) -> tuple[list[str], list[str], list[str]]:
    columns: list[str] = []
    values: list[str] = []
    assignments: list[str] = []
    for logical, physical in mapping.items():
        if logical not in logical_values:
            continue
        rendered = logical_values[logical]
        if rendered == "NULL" and skip_null and nullable.get(logical, True):
            continue
        quoted = _quote_ident(physical)
        columns.append(quoted)
        values.append(rendered)
        if logical != "slug":
            assignments.append(f"{quoted} = {rendered}")
    return columns, values, assignments


def _strip_sql_strings(sql: str) -> str:
    """Drop quoted literals so solution text cannot trip the scope check."""
    return re.sub(r"'(?:''|[^'])*'", "''", sql)


def _assert_sql_scope(sql: str) -> None:
    lowered = _strip_sql_strings(sql).lower()
    for table in PROTECTED_TABLES:
        if re.search(rf"\b(into|update|from|join|table)\s+`?{table}\b", lowered):
            raise ValueError(f"SQL must not touch {table}")
    if CORE_SLUG.search(lowered):
        raise ValueError("SQL contains a core compulsory paper slug")
    if "analyse_" in lowered or "sq_keys" in lowered:
        raise ValueError("SQL must not mention Analyse tables or sq_keys")


def catalogue_summary(topic: dict, subject: str) -> str:
    planned, notices = plan_from_topic(topic, subject, None)
    by_year: dict[str, list[int]] = {}
    for item in planned:
        by_year.setdefault(item.year_label, []).append(item.question_no)
    lines = [f"{subject} {TOPIC_BY_SUBJECT[subject]}: {len(by_year)} papers, {len(planned)} articles"]

    def sort_key(label: str) -> tuple[int, int, str]:
        if label == "SP":
            return (2, 0, label)
        if label == "PP":
            return (2, 1, label)
        if label.isdigit():
            return (0 if int(label) < 2012 else 1, int(label), label)
        return (3, 0, label)

    for label in sorted(by_year, key=sort_key):
        numbers = sorted(by_year[label])
        missing = [n for n in range(1, numbers[-1] + 1) if n not in numbers] if numbers else []
        gap = f" missing {missing}" if missing else ""
        lines.append(
            f"  {paper_slug(subject, label)}: {len(numbers)} questions "
            f"(q{numbers[0]}-q{numbers[-1]}){gap}"
        )
    for notice in notices:
        lines.append(f"  {notice.level}: {notice.message}")
    return "\n".join(lines)
