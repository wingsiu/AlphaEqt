# M1 Analyse seed

Seeds the HKDSE Mathematics Module 1 past-paper Analyse map into MySQL.

The topic number stored for each question is the number printed in `math/M1/analyse.xlsx`. A cell such as `10,12` or `4, 7` becomes those topic numbers, in that order. The legend under the grid (column A, with the short name in column B and the full name in column F) supplies the labels. Blank legend names stay blank. Nothing in this folder renumbers those codes.

Which numbers are legal depends on the column:

- Before 2012 (`94`–`99`, `00`–`11`) and the **first** column labelled `12` (`12#T`): topics **1–16** (`syllabus = ms`, the older M&S list). Topic 13 on that column is valid.
- `SP` (sample paper, 2011), `PP` (practice paper, 2022), the **second** column labelled `12` (`12#U`), years `13`–`26`, and `ON`: topics **1–12** (`syllabus = dse`).

`SP` and `PP` stay on topics 1–12. The sheet places those columns after the two headers labelled `12`. The seed orders year keys `SP`, then `PP`, then `12#T` (M&S), `12#U` (DSE M1), then `13` onward. `ON`, if a column uses that header, sits after `PP` and before those 2012 columns. Topics 13–16 are seeded only on `ms`.

`--check` passes on the current Sheet1, including `12#T` question 11 (T12) topic 13.

Compulsory-core Analyse (`math/HKDSE/Analyse.xls`, `db/seed_analyse.py`, `analyse_schema.sql`, tables `analyse_mc`, `analyse_mc_units`, `analyse_sq`, `analyse_sq_units`, `analyse_units`, `analyse_unit_qtypes`) is a separate map. This script does not open that workbook and does not create or modify those tables. See [docs/CONTENT_MODEL.md](../docs/CONTENT_MODEL.md).

## Workbook

Canonical path on the Synology share `math`:

```text
math/M1/analyse.xlsx
```

The file itself records the folder `D:\math\M1\`. On a Mac with the share mounted, the usual paths are:

- `/Volumes/math/M1/analyse.xlsx`
- `/Volumes/DiskStation/math/M1/analyse.xlsx`
- `~/SynologyDrive/math/M1/analyse.xlsx`

On the NAS:

- `/volume1/math/M1/analyse.xlsx`

`db/fixtures/M1/analyse.xlsx` is a copy used when the share is not mounted, so `--dry-run` and `--check` work without DiskStation. When you seed the alphaeqt database, point the script at the live share so you pick up edits made after this copy.

Sheet1 is the year (row 1) by question (column A) grid. Sheet2 and Sheet3 are empty and are skipped. `SP` is the 2011 sample paper and `PP` is the 2022 practice paper. Two columns are both labelled `12`; the first (`12#T`) is M&S topics 1–16 and the second (`12#U`) is DSE M1 topics 1–12. `year_label` stays `12` for both. A text header such as `00` stays `00`. Year order in the seed is the pre-2012 years, then `SP`, `PP`, then `12#T`, `12#U`, then `13` onward.

## Dry run

No database credentials are required.

```bash
pip install -r db/requirements.txt
python3 db/seed_analyse_m1.py --dry-run
python3 db/seed_analyse_m1.py --check
python3 db/test_seed_analyse_m1.py
```

`--dry-run` is the default. `--check` exits non-zero when a cell is not a topic number in range for that column. On the current fixture it passes, including topic 13 on the first `12` column.

Use another copy of the workbook with `--xlsx` or `M1_ANALYSE_XLSX`. The first existing path wins if you set neither: the NAS and mount locations above, then `math/M1/analyse.xlsx` relative to the current directory, then the fixture in this repo.

## Apply on the alphaeqt machine

Do this locally, where the MySQL client can reach the alphaeqt database. Do not run `--apply` against production from a cloud VM that has no credentials.

```bash
export M1_ANALYSE_XLSX="/Volumes/math/M1/analyse.xlsx"
export MYSQL_HOST=127.0.0.1
export MYSQL_PORT=3306
export MYSQL_USER=alphaeqt
export MYSQL_PWD="..."          # read by the mysql client, not printed by this script
export MYSQL_DATABASE=alphaeqt

python3 db/seed_analyse_m1.py --dry-run
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" < db/analyse_m1_schema.sql
python3 db/seed_analyse_m1.py --apply
```

`--apply` creates the `analyse_m1_*` tables if they are missing, then replaces their rows. `--emit-sql` prints that replacement SQL and does not connect. Add `--with-schema` to prepend `db/analyse_m1_schema.sql`.

If an earlier draft of these tables was created with `unit_code` as the only key, drop `analyse_m1_sq_units`, `analyse_m1_sq`, and `analyse_m1_units` before applying `db/analyse_m1_schema.sql`. `CREATE TABLE IF NOT EXISTS` will not add the `syllabus` column.

`MYSQL_DEFAULTS_FILE` is passed through as `--defaults-extra-file` when a login path file is preferable to `MYSQL_PWD`.

# Pure Maths and M2 Analyse seed

Seeds the Pure Maths and DSE M2 past-paper Analyse map into MySQL from the same workbook.

The topic token stored for each question is the text printed in `math/M2/PManalyse.xlsx`. A cell such as `16,6`, `8, 10`, `0X`, or `14X` becomes those tokens, in that order. Pure Maths is not truncated to the M2 list.

The sheet has two papers and two legends:

- The upper block is Paper 1. Years before 2012 (`80`–`99`, `00`–`11`) are Pure Maths (`syllabus = pm`). `SP`, `PP`, and the single column labelled `12` through `26` are M2 (`syllabus = m2`, topics 1–13 from the M2 name list).
- The lower block is Paper 2. Only the years before 2012 are exam columns, and they are Pure Maths. `14X` and `15X` appear on Paper 2. The columns headed `15` and `16` in this lower block are the M2 names (`MI`, `Bionomial`, `Trigonometry`, …), not 2015/2016 Paper 2 scripts. Paper 1 of those same columns is the real M2 paper.
- The bottom legend (column A `0`–`15`, column B the name) is the Pure Maths catalogue, shared by both papers. `0X`, `0x`, `14X`, `15X`, `16`, and `17` are seeded too, with no name, because the cells use them. `0X` and `0x` stay different. Column I beside that legend repeats the M2 names and is not a second Pure Maths name.

The M1 dual-2012 rule is not used. This file has one column labelled `12`, and that column is M2. A second `12` column is an error. Two-digit years here start at `80` (1980), not at the M1 cutoff of `94`.

There is no `analyse_m2_*` table. M2 rows are `analyse_pm_*` with `syllabus = m2`. Compulsory-core Analyse and `analyse_m1_*` are not opened or modified. See [docs/CONTENT_MODEL.md](../docs/CONTENT_MODEL.md).

## Workbook

Canonical path on the Synology share `math`:

```text
math/M2/PManalyse.xlsx
```

The file itself records the folder `W:\M2\`. On a Mac with the share mounted, the usual path is:

- `/Volumes/math/M2/PManalyse.xlsx`
- `/Volumes/DiskStation/math/M2/PManalyse.xlsx`
- `~/SynologyDrive/math/M2/PManalyse.xlsx`

On the NAS:

- `/volume1/math/M2/PManalyse.xlsx`

`D:\math\M2\PManalyse.xlsx` and `W:\M2\PManalyse.xlsx` are also searched. Set `M2_ANALYSE_XLSX` to point at the live share. `db/fixtures/M2/PManalyse.xlsx` is the copy used when the share is not mounted. If the canonical name is absent, `PManalysis.xlsx` and `pmanalysis.xlsx` are fallbacks, after every canonical path.

Sheet1 holds both papers. Sheet2 and Sheet3 are empty and are skipped. `year_label` `00` stays `00`. Year order in the seed is the pre-2012 years, then `SP`, `PP`, then `12` onward. Paper 2 year keys stop at `11`.

## Dry run

```bash
pip install -r db/requirements.txt
python3 db/seed_analyse_pm.py --dry-run
python3 db/seed_analyse_pm.py --check
python3 db/test_seed_analyse_pm.py
```

`--dry-run` is the default. `--check` exits non-zero when an M2 cell uses a token outside the 1–13 name list, or when the two paper blocks cannot be read. Pure Maths tokens outside 1–13 are kept. On the current fixture the check passes: 937 questions and 1045 topic links (Paper 1 Pure Maths 360/397, Paper 2 Pure Maths 362/412, Paper 1 M2 215/236).

## Apply on the alphaeqt machine

Do this locally, where the MySQL client can reach the alphaeqt database. Do not run `--apply` against production from a cloud VM that has no credentials.

```bash
export M2_ANALYSE_XLSX="/Volumes/math/M2/PManalyse.xlsx"
export MYSQL_HOST=127.0.0.1
export MYSQL_PORT=3306
export MYSQL_USER=alphaeqt
export MYSQL_PWD="..."          # read by the mysql client, not printed by this script
export MYSQL_DATABASE=alphaeqt

python3 db/seed_analyse_pm.py --dry-run
mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" "$MYSQL_DATABASE" < db/analyse_pm_schema.sql
python3 db/seed_analyse_pm.py --apply
```

`--apply` creates the `analyse_pm_*` tables if they are missing, then replaces their rows. It does not delete `analyse_m1_*` or the compulsory Analyse tables. `--emit-sql` prints that replacement SQL and does not connect. Add `--with-schema` to prepend `db/analyse_pm_schema.sql`.

`unit_code` uses `utf8mb4_bin` so `0X` and `0x` are different keys. A table created earlier with `utf8mb4_unicode_ci` rejects the seed. `db/analyse_pm_schema.sql` alters those columns when you apply it again. `CREATE TABLE IF NOT EXISTS` alone does not change the collation.

`MYSQL_DEFAULTS_FILE` is passed through as `--defaults-extra-file` when a login path file is preferable to `MYSQL_PWD`.

# Hoksi worked solutions (M1, M2)

Loads the M1 and M2 packs already saved beside core into the live editorial tables. Solution text goes into `content_blocks`. `questions.stem_block_id` points at a label block and `solutions.content_block_id` plus `sortorder` point at the worked solution. AlphaEqtContent's `vite.hoksi-download.ts` is what wrote those files (the same call core uses for `hkdse-maths-core-solutions`). There is no core MySQL seeder for that pack; this script is the loader, and it does not read or rewrite the core topic.

On disk:

```text
/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi/hkdse-maths-m1-solutions/{zh-HK,en}/
/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi/hkdse-maths-m2-solutions/{zh-HK,en}/
```

Each language directory has `_topic.json`, then `<folder>/<article>.json` and `<folder>/<article>.md`. M1 is 211 articles per language (SP, PP, 2012–2026). M2 is 215 per language. The seeder stores one solution per article per language, so a full apply is 422 M1 rows and 430 M2 rows.

| Subject | Topic | Paper slug |
| --- | --- | --- |
| M1 | `hkdse-maths-m1-solutions` | `dse2015-math-m1`, `dsesp-math-m1`, `dsepp-math-m1` |
| M2 | `hkdse-maths-m2-solutions` | `dse2015-math-m2`, `dsesp-math-m2`, `dsepp-math-m2` |

Pure Maths and M&S are blocked: Hoksi has no pack for them, and this loader will not invent one. `hkcee-maths-solutions` is HKCEE Mathematics, not M&S, and is refused. Core `hkdse-maths-core-solutions` is not read and not written. Analyse tables, `sq_keys`, `answers`, and `hints` are not modified. See [docs/CONTENT_MODEL.md](../docs/CONTENT_MODEL.md).

The offline indexes (article names only, no solution text) are `db/fixtures/hoksi/m1_topic.json` and `db/fixtures/hoksi/m2_topic.json`, captured 26 October 2026. Both packs run from 2012 through 2026 plus the sample paper (`SP`) and the practice paper (`PP`), with no missing question number inside a paper. 2026 is included because those articles are on Hoksi. They are suggested solutions, not an official marking scheme invented here.

## Re-download

Use the AlphaEqtContent dev app, which calls `vite.hoksi-download.ts`:

```bash
cd /Users/alpha/Desktop/swift/AlphaEqtContent
npm run dev
```

Set the topic URL and the Language menu, then click Download Hoksi. Do that for both languages of each module:

- `https://hoksiresources.com/zh-HK/topics/hkdse-maths-m1-solutions` with 中文 (zh-HK)
- `https://hoksiresources.com/en/topics/hkdse-maths-m1-solutions` with English (en)
- the same two URLs with `hkdse-maths-m2-solutions` instead of `m1`

Files are written under `/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi/<topic>/<lang>/`. Do not point this at Pure Maths, M&S, HKCEE, or the core topic if the goal is this loader.

The same API from this repo, into that directory:

```bash
export HOKSI_DOWNLOAD_ROOT="/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi"
python3 db/download_hoksi_solutions.py --subject m1
python3 db/download_hoksi_solutions.py --subject m2
```

That fetches zh-HK and en. Add `--refresh` to replace files already on disk. Add `--lang zh-HK` or `--lang en` for one language. `--subject pm` and `--subject ms` exit without downloading.

## Pilot: M1 2015

The packs are already on disk, so the pilot does not need a new download. From the AlphaEqt repo root, on the machine that has that tree:

```bash
export HOKSI_DOWNLOAD_ROOT="/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi"
python3 db/seed_hoksi_solutions.py --dry-run --subject m1 --year 2015
python3 db/test_hoksi_solutions.py
```

`--dry-run` does not connect to MySQL. With both languages present it reports:

```text
langs: en 12, zh-HK 12
papers: 1
solutions: 24
dse2015-math-m1: 24 solutions, 12 questions (q1-q12)
result: ok
```

Omit `--lang` to load every language directory. Pass `--lang zh-HK` or `--lang en` to load one.

Apply that pilot on the alphaeqt machine:

```bash
export HOKSI_DOWNLOAD_ROOT="/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi"
export MYSQL_HOST=127.0.0.1
export MYSQL_PORT=3306
export MYSQL_USER=alphaeqt
export MYSQL_PWD="..."          # read by the mysql client, not printed by this script
export MYSQL_DATABASE=alphaeqt

python3 db/seed_hoksi_solutions.py --apply --subject m1 --year 2015
```

`--apply` reads `SHOW COLUMNS` and writes the live content_blocks model. It does not `ALTER`, and it does not create `db/solutions_schema.sql` (that file is a `question_no` / `solutions.body` shape, which live `questions` does not have). `qkind` is `sq` when that column allows it. Live `source_type` is `CHAR(1)` (`S` and `P`), so the value written is `S`, or `P` when the enum does not list `S`. A longer token such as `hoksi` is used only when it fits and `S`/`P` are not accepted. `topic_id`, `level`, `marks`, and `source_pdf` are left null. `sortorder` is 1 for zh-HK and 2 for en. If a required column cannot be filled, the command prints the column list and writes nothing.

After apply, `dse2015-math-m1` should have 24 `solutions` rows (12 questions × zh-HK and en), each pointing at its own content block:

```sql
SELECT p.slug, COUNT(*)
FROM papers p
JOIN questions q ON q.paper_id = p.id
JOIN solutions s ON s.question_id = q.id
JOIN content_blocks b ON b.id = s.content_block_id
WHERE p.slug = 'dse2015-math-m1'
GROUP BY p.slug;
```

`MYSQL_DEFAULTS_FILE` is passed through as `--defaults-extra-file` when a login path file is preferable to `MYSQL_PWD`.

The seeder finds `/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi` on its own when `HOKSI_DOWNLOAD_ROOT` is unset and that directory exists. It still will not read the core topic sitting beside the module packs.

## Batch the rest of M1 and M2

Run this after the 2015 pilot looks right. It reads the packs already on disk. It does not create Pure Maths or M&S rows.

```bash
export HOKSI_DOWNLOAD_ROOT="/Users/alpha/Desktop/swift/AlphaEqtContent/downloads/hoksi"
python3 db/seed_hoksi_solutions.py --dry-run --subject m1
python3 db/seed_hoksi_solutions.py --dry-run --subject m2
python3 db/seed_hoksi_solutions.py --apply --subject m1
python3 db/seed_hoksi_solutions.py --apply --subject m2
```

A full dry-run is 422 M1 solutions (211 × 2 languages) and 430 M2 solutions (215 × 2).

`--inventory` only prints the live catalogue and the gaps. A year filter on download fetches those articles only; `--apply` for a subject then requires every selected article file to be present. Re-running a subject updates the Hoksi solution blocks for the articles in that run and inserts rows that are missing. It does not rewrite a stem block that already exists, and it leaves every other paper alone.

```bash
python3 db/seed_hoksi_solutions.py --emit-sql --subject m1 --year 2015 > /tmp/m1-2015-solutions.sql
```

`--emit-sql` needs `MYSQL_DATABASE` as well. It runs `SHOW COLUMNS` and prints the same INSERT/UPDATE statement `--apply` would run. It does not create tables. `--with-schema` is rejected.

## Gaps

- Pure Maths: no Hoksi topic. Do not invent papers from another source in this loader.
- M&S: no Hoksi topic. Do not point `hkcee-maths-solutions` at M&S.
- HKCEE Mathematics is a blocked topic. It is the old compulsory syllabus, not a module paper.
- Core compulsory stays on its own path. This loader never writes a `math-cp` or `math-core` slug.
- `answers` and `hints` stay empty. The Hoksi article is the worked solution.
- zh-HK and en are both loaded when both directories are on disk. The language is the directory name (`zh-HK` or `en`), not `actual_lang` inside the JSON. On the live table that is `solutions.sortorder` 1 and 2, and `content_blocks.lang` when that column exists.
- 2026 M1 (13 questions) and 2026 M2 (12 questions) are in the Hoksi pack. Years the inventory does not list are skipped.
