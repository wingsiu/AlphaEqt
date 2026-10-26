# M1 Analyse seed

Seeds the HKDSE Mathematics Module 1 past-paper Analyse map into MySQL.

The topic number stored for each question is the number printed in `math/M1/analyse.xlsx`. A cell such as `10,12` or `4, 7` becomes those topic numbers, in that order. The legend under the grid (column A, with the short name in column B and the full name in column F) supplies the labels. Blank legend names stay blank. Nothing in this folder renumbers those codes.

Which numbers are legal depends on the column:

- Before 2012 (`94`–`99`, `00`–`11`): topics **1–16** (`syllabus = ms`, the older M&S list). The sheet uses 13, 14, and 16 here.
- `SP` (sample paper, 2011), `PP` (practice paper, 2022), 2012 and after (both columns labelled `12`, then `13`–`26`), and `ON`: topics **1–12** (`syllabus = dse`).

`SP` and `PP` stay on topics 1–12. The sheet places those columns after the two headers labelled `12`. The seed orders year keys `SP`, then `PP`, then 2012 (`12#T`, `12#U`, then `13` onward). `ON`, if a column uses that header, sits after `PP` and before 2012. Topics 13–16 are seeded only on `ms`.

The current Sheet1 fails that check in one cell: `12#T` question 11 (T12) is topic 13. `--check` exits non-zero, and `--emit-sql` / `--apply` will not write the map until that cell is inside 1–12.

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

Sheet1 is the year (row 1) by question (column A) grid. Sheet2 and Sheet3 are empty and are skipped. `SP` is the 2011 sample paper and `PP` is the 2022 practice paper. Two columns are both labelled `12`; they hold different questions, so they are stored as `12#T` and `12#U` while `year_label` stays `12`. A text header such as `00` stays `00`. Year order in the seed is the pre-2012 years, then `SP`, `PP`, then 2012 onward.

## Dry run

No database credentials are required.

```bash
pip install -r db/requirements.txt
python3 db/seed_analyse_m1.py --dry-run
python3 db/seed_analyse_m1.py --check
python3 db/test_seed_analyse_m1.py
```

`--dry-run` is the default. `--check` exits non-zero when a cell is not a topic number in range for that column. On the current fixture that is `12#T` question 11, topic 13.

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
