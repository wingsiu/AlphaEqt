# Content model: M1 Analyse

Analyse maps a past-paper question onto the topic numbers written in the Analyse workbook. For Module 1 that workbook is `math/M1/analyse.xlsx`.

## Why these tables are separate

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

## Topic numbers

`analyse_m1_units.unit_code` is the integer in the workbook. It is not one list for every year. The primary key is `(syllabus, unit_code)`.

| syllabus | Columns in `math/M1/analyse.xlsx` | Allowed topics |
| --- | --- | --- |
| `ms` | `94`–`99`, `00`–`11` (before 2012). These columns use 13, 14, and 16. | 1–16 |
| `dse` | Both columns labelled `12`, then `13`–`26`. Also `SP`, `PP`, and `ON`. | 1–12 |

Checked on the workbook attached for this seed:

- Every column from `94` through `11` cites at least one topic in 13–16, and none of them cite topics 1, 5, or 10.
- `SP` and `PP` cite only 1–12, and they cite topics 1, 5, and 10. They are the new-syllabus sample and practice papers, so they use the 1–12 list. An older-regime SP/PP would use 1–16; this file does not have that paper.
- `ON` is not a column in this file. A header `ON` is seeded as `dse` (topics 1–12).
- Topics 13–16 are seeded only on `ms`. Topics 1–12 are seeded on both syllabi, with the same legend names. A 2012-or-later cell that cites 13, 14, 15, or 16 is an error, and `--emit-sql` / `--apply` refuse the workbook.

The first column labelled `12` (`12#T`, cell T12, question 11) contains topic 13. That number is outside 1–12, so the current workbook fails `--check`. No other 2012-or-later cell does. Dry-run counts on this file: `ms` 226 questions and 256 links; `dse` 222 questions and 242 links.

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

## Question rows

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

The workbook has two columns labelled `12` (T and U) with different topic maps. They are `12#T` (`label_occurrence` 1) and `12#U` (`label_occurrence` 2). Both are calendar year 2012, so both are `dse`. `SP` and `PP` in this file are the new-syllabus sample and practice papers (`dse`). Header `00` is the text `00`, not 2000.

Empty question cells are not inserted. Re-seeding deletes and reinserts only `analyse_m1_sq_units`, `analyse_m1_sq`, and `analyse_m1_units`.

## Files

- `db/analyse_m1_schema.sql` — table definitions
- `db/seed_analyse_m1.py` — reader and SQL generator
- `db/fixtures/M1/analyse.xlsx` — offline copy of the workbook
- `db/README.md` — how to dry-run and how to apply against alphaeqt
