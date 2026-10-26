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

# Analyse HTTP API

`db/editorial_api.py` serves `GET /analyse/lookup`, `/analyse/units`, and `/analyse/gaps`.

With no `subject`, no `band`, and no module slug, those paths read only the compulsory tables (`analyse_mc`, `analyse_sq`, and the compulsory unit catalogue). They do not read `analyse_m1_*`, `analyse_pm_*`, or `content_blocks`. Compulsory paper 1 is `kind=sq`. Paper 2 is `kind=mc`. `dse2015-math-cp1` and `dse2015-math-cp2` stay on that path.

| Request | Map | Solutions |
| --- | --- | --- |
| `subject=m1`, `band=dse`, or `dse2015-math-m1` | `analyse_m1_*` syllabus `dse` | `content_blocks`, key `dse2015-math-m1-q3:zh-HK` |
| `subject=m2`, `band=m2`, or `dse2015-math-m2` | `analyse_pm_*` syllabus `m2`, paper 1 | same key shape for `math-m2` |
| `subject=pm` | `analyse_pm_*` syllabus `pm` | blocked. Analyse-only. No Hoksi pack |
| `subject=ms` | `analyse_m1_*` syllabus `ms` | blocked. Analyse-only. No Hoksi pack |

`dse2012-math-m1` is the DSE column `12#U`. `subject=ms&year=2012` is the M&S column `12#T`. `subject=m1&year=2012` with no band is rejected. `0X` and `0x` stay different on Pure Maths.

`--plan` does not connect. `--serve` uses the same `MYSQL_*` settings as the seed scripts and reads live column names with `SHOW COLUMNS`.

```bash
python3 db/test_editorial_api.py
python3 db/editorial_api.py --plan lookup --year 2015 --question 1 --kind sq
python3 db/editorial_api.py --plan lookup --slug dse2015-math-m1 --question 3
python3 db/editorial_api.py --plan gaps --subject pm
python3 db/editorial_api.py --serve
```

The route table is in [docs/CONTENT_MODEL.md](../docs/CONTENT_MODEL.md).
