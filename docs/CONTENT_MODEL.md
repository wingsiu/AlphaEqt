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

## Analyse HTTP API

`db/editorial_api.py` serves the three GET paths used for compulsory Analyse:

| Path | What it returns |
| --- | --- |
| `/analyse/lookup` | One question’s topic row, the unit names on that row, and (for M1/M2) worked solutions |
| `/analyse/units` | The unit catalogue. Add `unit`, `year`, or `questions=1` to include the questions that cite a unit |
| `/analyse/gaps` | Questions with no topic link, units that no question cites, and (for DSE M1 and M2) solution languages that were not loaded |

A request with no `subject`, no `band`, and no module slug reads only `analyse_mc`, `analyse_sq`, `analyse_units`, and `analyse_unit_qtypes`. It does not read `analyse_m1_*`, `analyse_pm_*`, `content_blocks`, or `solutions`. Compulsory paper 1 is `kind=sq` (`analyse_sq`). Compulsory paper 2 is `kind=mc` (`analyse_mc`). Slugs `dse2015-math-cp1` and `dse2015-math-cp2` stay on that path.

`--serve` discovers live column names with `SHOW COLUMNS`. `--plan` prints the SQL for the column names in this repo and does not connect.

### Which map a request uses

| Request | Tables | Solutions |
| --- | --- | --- |
| no subject, `subject=core`, or `dse2015-math-cp1` / `cp2` | compulsory `analyse_*` | not read |
| `subject=m1`, `band=dse`, or `dse2015-math-m1` | `analyse_m1_*`, syllabus `dse` | `content_blocks` |
| `subject=m2`, `band=m2`, or `dse2015-math-m2` | `analyse_pm_*`, syllabus `m2`, paper 1 | `content_blocks` |
| `subject=pm` or `band=pm` | `analyse_pm_*`, syllabus `pm` | blocked |
| `subject=ms` or `band=ms` | `analyse_m1_*`, syllabus `ms` | blocked |

2012 is two columns on the M1 sheet. `dse2012-math-m1` is DSE M1, `year_key` `12#U`. `subject=ms&year=2012` is M&S, `year_key` `12#T`. `subject=m1&year=2012` with no band is rejected. Years before 2012 on that sheet are M&S. Years before 2012 in `PManalyse.xlsx` are Pure Maths. There is no `analyse_m2_*` table.

M1 and M2 solution text is the block whose key is `{question_slug}:zh-HK` or `{question_slug}:en` (`dse2015-math-m1-q3:zh-HK`), or the `<!-- hoksi:...:solution -->` marker when that key column is absent. `solutions.sortorder` is 1 for zh-HK and 2 for en when the row is tied to a question. Sample and practice papers use `dsesp-math-m1` and `dsepp-math-m2`.

Pure Maths and M&S are analyse-only. Lookup returns `"solutions": {"status": "blocked", ...}`. Gaps do not list those questions as missing Hoksi articles, because no pack was ingested. `ON` has no paper slug, so it is reported as unslugged rather than missing.

`python3 db/editorial_api.py --plan` prints this routing without MySQL. `python3 db/editorial_api.py --serve` binds `127.0.0.1:8765` (override with `EDITORIAL_BIND` and `EDITORIAL_PORT`) and uses the same `MYSQL_*` variables as the seed scripts.
