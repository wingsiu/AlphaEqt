# Content model: Analyse maps

Analyse maps a past-paper question onto the topic numbers written in the Analyse workbook.

- Module 1 uses `math/M1/analyse.xlsx` and the `analyse_m1_*` tables.
- Pure Maths and M2 share `math/M2/PManalyse.xlsx` and the `analyse_pm_*` tables. Pure Maths has two papers. The upper block is Paper 1. M2 is not a separate workbook, and its topic numbers are not a cap on the Pure Maths tokens.

## M1 Analyse

### Why these tables are separate

Compulsory-core Analyse uses:

| Table | Role |
| --- | --- |
| `analyse_mc` | Multiple-choice question |
| `analyse_mc_units` | MC question to compulsory unit |
| `analyse_sq` | Structured question |
| `analyse_sq_units` | Structured question to compulsory unit |
| `analyse_units` | Compulsory unit catalogue |
| `analyse_unit_qtypes` | Question types for a compulsory unit |

`analyse_units` is the compulsory catalogue. M1 topic numbers are a different list, taken from the M1 workbook, so they live in `analyse_m1_*` and do not share those rows. This repository does not create or alter the compulsory tables. `db/seed_analyse_m1.py` never reads `math/HKDSE/Analyse.xls`.

M1 has no multiple-choice paper, and the current workbook leaves Sheet2 and Sheet3 empty, so there is no `analyse_m1_mc` table. The grid has topic numbers only, so there is no `analyse_m1_unit_qtypes` table.

### Topic numbers

`analyse_m1_units.unit_code` is the integer in the workbook. It is not one list for every year. The primary key is `(syllabus, unit_code)`.

| syllabus | Columns in `math/M1/analyse.xlsx` | Allowed topics |
| --- | --- | --- |
| `ms` | `94`–`99`, `00`–`11`, and the first column labelled `12` (`12#T`). | 1–16 |
| `dse` | `SP` (sample paper, 2011), `PP` (practice paper, 2022), the second column labelled `12` (`12#U`), then `13`–`26`, and `ON`. | 1–12 |

Checked on the workbook attached for this seed:

- Every column from `94` through `11` cites at least one topic in 13–16, and none of them cite topics 1, 5, or 10.
- `SP` is the sample paper (2011) and `PP` is the practice paper (2022). Both use topics 1–12. Their cells cite topics 1, 5, and 10, which `94`–`11` do not.
- In the sheet those two columns sit after the headers labelled `12`. Seed order is `… 11`, `SP`, `PP`, `12#T` (M&S, topics 1–16), `12#U` (DSE M1, topics 1–12), `13` …. `ON`, when present, follows `PP` and precedes the 2012 columns.
- The two headers labelled `12` are not the same syllabus. The first is older M&S, so question 11 topic 13 (`Sheet1!T12`) is in range. The second is DSE M1 and stays on topics 1–12.
- Topics 13–16 are seeded only on `ms`. Topics 1–12 are seeded on both syllabi, with the same legend names. A 2012-or-later cell that cites 13, 14, 15, or 16 is an error, and `--emit-sql` / `--apply` refuse the workbook.

Dry-run on this file passes. `12#T` question 11 (cell T12) is topic 13 on the M&S column. Counts: `ms` 238 questions and 268 links; `dse` 210 questions and 230 links.

- Legend column A is the topic number.
- Legend column B is `short_name` (`binomial`, `exp and log`, …).
- Legend column F is `name` (`Binomial`, `Exponential and Log`, …).
- A year × question cell holds one number (`12`) or several (`10,12`, `4, 7`). Each number is a `unit_code` in that column’s syllabus. Order inside the cell is `analyse_m1_sq_units.position`, starting at 1.

Codes 13–16 are in the legend with no names. They are stored on `ms` with NULL names. Code 15 is listed and unused by the current grid; it is still an `ms` unit because the older list is 1–16. Codes that appear in a cell are never rewritten to another id.

The curriculum tree (`seed_topics.sql`, `band = '1'`, codes such as `HKDSE-M1-*`) is a different list. This seed does not update that tree and does not assume `unit_code` equals a curriculum topic id. Join the two only through a mapping you have checked against `seed_topics.sql`.

Names currently printed in the workbook:

| unit_code | short_name | name |
| --- | --- | --- |
| 1 | binomial | Binomial |
| 2 | exp and log | Exponential and Log |
| 3 | limit | limits |
| 4 | diff | differentiation |
| 5 | app diff 1 | Application of Differentiation(1) |
| 6 | app diff 2 | Application of Differentiation(2) |
| 7 | int | Integration |
| 8 | app int | Application of integration |
| 9 | prob | Probability |
| 10 | distribution | Probability distribution |
| 11 | normal | Normal distribution |
| 12 | sampling | Sampling Distribution |
| 13–16 | *(blank)* | *(blank)* |

### Question rows

`analyse_m1_sq` is one populated year column × question number.

| Column | Meaning |
| --- | --- |
| `syllabus` | `ms` or `dse`, from the year column |
| `year_label` | Header cell, unchanged (`94`, `00`, `12`, `SP`, `PP`, `26`) |
| `label_occurrence` | Which column that label is, left to right, starting at 1 |
| `source_column` | Excel column letter |
| `year_key` | `year_label`, or `year_label#column` when the header is repeated |
| `question_no` | Column A |
| `raw_cell` | The cell text, so `4, 7` stays distinguishable from `4,7` |

The workbook has two columns labelled `12` (T and U) with different topic maps. They are `12#T` (`label_occurrence` 1, M&S, topics 1–16) and `12#U` (`label_occurrence` 2, DSE M1, topics 1–12). `SP` is the 2011 sample paper and `PP` is the 2022 practice paper; both are `dse` with topics 1–12. Header `00` is the text `00`, not 2000.

`year_key` sequence follows pre-2012 years, then `SP`, `PP`, then 2012 onward. That is the insert order as well. It does not follow the sheet, which places `SP` and `PP` after the two `12` columns.

Empty question cells are not inserted. Re-seeding deletes and reinserts only `analyse_m1_sq_units`, `analyse_m1_sq`, and `analyse_m1_units`.

### Files

- `db/analyse_m1_schema.sql` — table definitions
- `db/seed_analyse_m1.py` — reader and SQL generator
- `db/fixtures/M1/analyse.xlsx` — offline copy of the workbook
- `db/README.md` — how to dry-run and how to apply against alphaeqt

## Pure Maths and M2

`math/M2/PManalyse.xlsx` is one Sheet1 grid with two question blocks and two legends. The file records its folder as `W:\M2\`. Sheet2 and Sheet3 are empty.

| Block | Rows on the current sheet | What it is |
| --- | --- | --- |
| Upper, column A = 1–14 | 2–15 | Paper 1 |
| Lower, column A = 1–14 again | 18–31 | Paper 2 |
| Bottom, column A = 0–15 and column B = name | 35–50 | Pure Maths legend |
| Lower block, columns headed `15` and `16` | 18–30 | M2 legend (1–13 and the names), not a 2015/2016 Paper 2 script |

Paper 1 of the columns headed `15` and `16` is the real 2015 and 2016 M2 paper. Column I of the bottom legend repeats the M2 names (`MI`, `Bionomial`, …). Those cells are not Pure Maths names for the codes in column A. `3` is Polynomial on Pure Maths and Trigonometry on M2.

### Which syllabus a column uses

| Paper | Columns | syllabus | Topic tokens |
| --- | --- | --- | --- |
| 1 | `80`–`99`, `00`–`11` | `pm` | Whatever the cell prints. The legend names 0–15. Cells also use `16`, `17`, `0X`, and `0x`. |
| 1 | `SP`, `PP`, `12`–`26` | `m2` | The M2 legend, 1–13, and nothing else. |
| 2 | `80`–`99`, `00`–`11` | `pm` | Same Pure Maths catalogue, plus `14X` and `15X`, which appear only on Paper 2. |

Two-digit years on this sheet use 80 as the century split: `80` is 1980, `00` is 2000, `12` is 2012. That is wider than the M1 workbook, which starts at `94`.

There is one column labelled `12`. It is M2. A second column labelled `12`, or both `12` and `2012`, is refused. The M1 rule (first `12` is M&S, second `12` is DSE) is not applied here. `ON` is not a header in this file and has no rule.

Seed order is the pre-2012 years, then `SP`, then `PP`, then `12` onward. This sheet already stores the headers in that order. Paper 2 stops at `11`.

From about 2006, Paper 1 stops citing `16`, `17`, and `0X`, but the sheet does not start a new legend there. Those years stay Pure Maths through `11`.

### Topic tokens

`analyse_pm_units.unit_code` is the token text, with collation `utf8mb4_bin` on both the unit catalogue and `analyse_pm_sq_units.unit_code`. That keeps `0X` and `0x` as different keys. `utf8mb4_unicode_ci` folds them together and the insert fails. Integer tokens are stored without leading zeros. `raw_cell` keeps the cell text, so `8, 10` stays distinguishable from `8,10`. The only `0x` on the current sheet is Paper 1, 1989, question 7. Re-applying `db/analyse_pm_schema.sql` alters an existing `unit_code` column to `utf8mb4_bin`.

Pure Maths names, from the bottom legend, shared by both papers:

| unit_code | name |
| --- | --- |
| 0 | Sets Language |
| 1 | Mathematical Induction |
| 2 | Binomial theorem |
| 3 | Polynomial |
| 4 | Inequality |
| 5 | Matrices |
| 6 | System of Linear Equations |
| 7 | Complex Numbers |
| 8 | Functions |
| 9 | sequence |
| 10 | limit |
| 11 | differentiation |
| 12 | application of differentiation |
| 13 | integration |
| 14 | application of integration |
| 15 | analytical geometry |

Tokens in Pure Maths cells that the legend does not name, stored with NULL names: `0X`, `0x`, `14X`, `15X`, `16`, `17`. They are not dropped and they are not renumbered onto 1–13.

M2 names, from the lower-block list. The spelling in the sheet is kept, including `Bionomial`. A trailing space on `MI` is stripped.

| unit_code | name |
| --- | --- |
| 1 | MI |
| 2 | Bionomial |
| 3 | Trigonometry |
| 4 | Limit |
| 5 | Diff |
| 6 | App of Diff(tangent) |
| 7 | App of Diff(graph) |
| 8 | App of Diff(Rate and Optimization) |
| 9 | int |
| 10 | app of int |
| 11 | Matrices |
| 12 | System of equations |
| 13 | Vectors |

An M2 cell that cites anything outside that list is an error, and `--emit-sql` / `--apply` refuse the workbook. A Pure Maths cell is not capped at 1–13.

Dry-run on the current fixture: 937 questions and 1045 topic links.

| syllabus | paper | questions | topic links |
| --- | --- | --- | --- |
| `pm` | 1 | 360 | 397 |
| `pm` | 2 | 362 | 412 |
| `m2` | 1 | 215 | 236 |

22 Pure Maths units and 13 M2 units. There is no `analyse_m2_*` table and no `analyse_pm_mc` table.

### Question rows

`analyse_pm_sq` is one paper × year column × question number. The same year and question number can exist on both papers (1980 question 1 is Paper 1 topics `16,6` and Paper 2 topic `15`).

| Column | Meaning |
| --- | --- |
| `paper` | `1` upper block, `2` lower block |
| `syllabus` | `pm` or `m2` |
| `year_label` | Header cell, unchanged (`80`, `00`, `12`, `SP`, `PP`, `26`) |
| `label_occurrence` | Always 1 in this workbook, because each header appears once |
| `source_column` | Excel column letter |
| `year_key` | The header text |
| `question_no` | Column A inside that paper’s block |
| `raw_cell` | The cell text |

`analyse_pm_sq_units.position` is the left-to-right order inside the cell, starting at 1. Re-seeding deletes and reinserts only `analyse_pm_sq_units`, `analyse_pm_sq`, and `analyse_pm_units`.

### Files

- `db/analyse_pm_schema.sql` — table definitions
- `db/seed_analyse_pm.py` — reader and SQL generator
- `db/fixtures/M2/PManalyse.xlsx` — offline copy of the workbook
- `db/README.md` — how to dry-run and how to apply against alphaeqt

## Worked solutions (Hoksi)

Analyse rows are topic numbers. Worked solutions are a different path: `papers` → `questions` → `solutions`. `answers`, `hints`, and `sq_keys` are not filled from these packs. Core compulsory Hoksi text previously landed in `sq_keys`; this loader does not read that pack and does not write `sq_keys`.

There is no `editorial_api` and no `db/import_docx_tex.py` in this repository. Paper slugs follow the shape that importer is described as using.

| Paper | Slug |
| --- | --- |
| 2015 M1 | `dse2015-math-m1` |
| 2015 M2 | `dse2015-math-m2` |
| M1 sample paper | `dsesp-math-m1` |
| M2 practice paper | `dsepp-math-m2` |

Question slugs append `-q` and the question number (`dse2015-math-m1-q1`). One Hoksi article is one question. Parts such as `(a)` and `(b)` stay inside that solution.

### Where the text comes from

The same site and API as core. AlphaEqtContent downloads `hkdse-maths-core-solutions` from `https://hoksiresources.com/api` into `downloads/hoksi/<topic>/<lang>/` (`_topic.json`, one JSON article, one Markdown article). Module solutions use that tree:

| Subject | Hoksi topic | What it is |
| --- | --- | --- |
| M1 | `hkdse-maths-m1-solutions` | Suggested worked solutions, `zh-HK` |
| M2 | `hkdse-maths-m2-solutions` | Suggested worked solutions, `zh-HK` |
| Pure Maths | *(none)* | No subject and no topic on Hoksi |
| M&S | *(none)* | No subject and no topic on Hoksi |

`hkcee-maths-solutions` is HKCEE Mathematics (Paper 1 sections and Paper 2 multiple choice, 1998–2011 in the current pack). It is not Mathematics & Statistics and it is not Pure Maths. The loader refuses it.

Checked on 26 October 2026, both module topics list 17 folders and no missing question number inside a paper. The index is `db/fixtures/hoksi/m1_topic.json` and `db/fixtures/hoksi/m2_topic.json`. Refresh it with `python3 db/download_hoksi_solutions.py --inventory`.

| Slug | Questions |
| --- | --- |
| `dsesp-math-m1` | 14 |
| `dsepp-math-m1` | 13 |
| `dse2012-math-m1` … `dse2014-math-m1` | 13 each |
| `dse2015-math-m1` … `dse2025-math-m1` | 12 each |
| `dse2026-math-m1` | 13 |
| `dsesp-math-m2`, `dsepp-math-m2` | 14 each |
| `dse2012-math-m2`, `dse2013-math-m2` | 14 each |
| `dse2014-math-m2` | 13 |
| `dse2015-math-m2` … `dse2023-math-m2` | 12 each |
| `dse2024-math-m2`, `dse2025-math-m2` | 13 each |
| `dse2026-math-m2` | 12 |

211 M1 articles and 215 M2 articles. 2026 is in the pack, so those rows are Hoksi suggested solutions. A year that is not listed is not invented. DiskStation marking-scheme PDFs are not read. Nothing is OCR'd.

Each article is HTML with `<span class="math-tex">\(\ldots\)</span>`. The loader keeps that HTML on `solutions.html` and writes Markdown on `solutions.body`, with `\(...\)` turned into `$...$` and `\[...\]` into `$$`. That is the same light conversion AlphaEqtContent uses, plus Markdown tables so a probability grid is not flattened. `format` is `markdown` when that conversion yields text, and `html` when the article is only markup.

### What `--apply` writes

`db/solutions_schema.sql` creates `papers`, `questions`, and `solutions` when all three are absent. When they already exist, `--apply` reads `SHOW COLUMNS` and maps the usual names (`body` or `content`, `question_no` or `number`, `paper_id`, and so on). It stops without writing if a solution cannot be hung off `questions` and `papers`. It does not alter an existing table. `CREATE TABLE IF NOT EXISTS` is not used as a way to change columns that are already there.

Deletes are limited to the paper slugs in that run, and to `source = 'hoksi'` when that column exists. `analyse_m1_*`, `analyse_pm_*`, the compulsory Analyse tables, `sq_keys`, `answers`, and `hints` are not in the statement.

Sample and practice papers store `year_label` `SP` or `PP` and a NULL `year`, so the 2022 practice paper is `dsepp-math-m1` and the 2022 exam stays `dse2022-math-m1`.

`hoksi_solutions.load_bundle` is the read hook for a later API. This change does not add that API.

Commands, the M1 2015 pilot, and the batch order are in [db/README.md](../db/README.md).
