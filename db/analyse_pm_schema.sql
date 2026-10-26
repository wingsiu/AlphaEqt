-- Pure Maths and DSE M2 past-paper Analyse map.
--
-- The source workbook is math/M2/PManalyse.xlsx (the file records W:\M2\).
-- It is not an M2-only grid:
--   Paper 1 is the upper question block (column A restarts at 1).
--   Paper 2 is the lower question block (column A restarts at 1).
--   Pure Maths years are the calendar columns before 2012. Their topic
--     tokens come from the cells, including values past the M2 list
--     (0, 14, 15, 16, 17, 0X, 0x, 14X, 15X).
--   DSE M2 is Paper 1 from SP, PP, and 2012 onward. Those cells use the
--     separate 1-13 name list. The sheet has one column labelled 12.
--
-- The same integer means different topics on the two syllabi
-- (3 is Polynomial on pm and Trigonometry on m2). unit_code is the token
-- printed in the cell, stored as text so 0X, 0x, 14X, and 15X stay distinct.
-- The column uses utf8mb4_bin. utf8mb4_unicode_ci treats 0X and 0x as one
-- primary key, and the seed insert then fails.
--
-- Parallel to the compulsory-core tables and to analyse_m1_*. This file
-- does not create or alter:
--   analyse_mc, analyse_mc_units, analyse_sq, analyse_sq_units,
--   analyse_units, analyse_unit_qtypes,
--   analyse_m1_units, analyse_m1_sq, analyse_m1_sq_units
-- There is no analyse_m2_* table. M2 rows live here with syllabus = 'm2'.
--
-- Sheet2 and Sheet3 are empty. The grid has no multiple-choice paper and
-- no question-type axis, so there is no analyse_pm_mc or
-- analyse_pm_unit_qtypes table.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS analyse_pm_units (
  syllabus VARCHAR(8) NOT NULL COMMENT 'pm = Pure Maths; m2 = DSE M2 name list',
  unit_code VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'Topic token from PManalyse.xlsx, e.g. 13, 0X, 0x, 14X',
  name VARCHAR(191) NULL COMMENT 'Legend name, NULL when the workbook has no name for this token',
  PRIMARY KEY (syllabus, unit_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analyse_pm_sq (
  id INT NOT NULL COMMENT 'Stable id assigned by db/seed_analyse_pm.py',
  sheet_name VARCHAR(64) NOT NULL,
  paper SMALLINT NOT NULL COMMENT '1 = upper block, 2 = lower block',
  syllabus VARCHAR(8) NOT NULL COMMENT 'pm or m2, from the paper and year column',
  year_key VARCHAR(32) NOT NULL COMMENT 'Header text. This workbook has one column per header',
  year_label VARCHAR(32) NOT NULL COMMENT 'Exact header cell, including 00',
  label_occurrence SMALLINT NOT NULL COMMENT '1-based left-to-right occurrence of year_label. Always 1 in this workbook',
  source_column VARCHAR(8) NOT NULL COMMENT 'Excel column letter of the year header',
  question_no SMALLINT NOT NULL COMMENT 'Question number from column A of this paper block',
  raw_cell VARCHAR(255) NOT NULL COMMENT 'Topic cell text, e.g. 16,6 or 8, 10 or 0x',
  PRIMARY KEY (id),
  UNIQUE KEY uq_analyse_pm_sq (sheet_name, paper, year_key, question_no),
  UNIQUE KEY uq_analyse_pm_sq_id_syllabus (id, syllabus),
  KEY idx_analyse_pm_sq_year (paper, year_label, question_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analyse_pm_sq_units (
  sq_id INT NOT NULL,
  position SMALLINT NOT NULL COMMENT '1-based order of the topic token inside the cell',
  syllabus VARCHAR(8) NOT NULL COMMENT 'Same syllabus as the question',
  unit_code VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL COMMENT 'Same token as analyse_pm_units.unit_code',
  PRIMARY KEY (sq_id, position),
  KEY idx_analyse_pm_sq_units_unit (syllabus, unit_code),
  CONSTRAINT fk_analyse_pm_sq_units_sq
    FOREIGN KEY (sq_id, syllabus) REFERENCES analyse_pm_sq (id, syllabus)
    ON DELETE CASCADE,
  CONSTRAINT fk_analyse_pm_sq_units_unit
    FOREIGN KEY (syllabus, unit_code) REFERENCES analyse_pm_units (syllabus, unit_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- CREATE TABLE IF NOT EXISTS does not change unit_code on a table that
-- already exists. An earlier apply used utf8mb4_unicode_ci, which folds
-- 0X and 0x together. Drop the foreign key, set both columns to
-- utf8mb4_bin, then put the key back. Safe to run again.
ALTER TABLE analyse_pm_sq_units DROP FOREIGN KEY fk_analyse_pm_sq_units_unit;
ALTER TABLE analyse_pm_units
  MODIFY unit_code VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL
  COMMENT 'Topic token from PManalyse.xlsx, e.g. 13, 0X, 0x, 14X';
ALTER TABLE analyse_pm_sq_units
  MODIFY unit_code VARCHAR(16) CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL
  COMMENT 'Same token as analyse_pm_units.unit_code';
ALTER TABLE analyse_pm_sq_units
  ADD CONSTRAINT fk_analyse_pm_sq_units_unit
  FOREIGN KEY (syllabus, unit_code) REFERENCES analyse_pm_units (syllabus, unit_code);
