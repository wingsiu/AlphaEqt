-- HKDSE Mathematics Module 1 (M1) past-paper Analyse map.
--
-- Parallel to the compulsory-core tables, which this file does not create
-- and does not alter:
--   analyse_mc, analyse_mc_units, analyse_sq, analyse_sq_units,
--   analyse_units, analyse_unit_qtypes
--
-- Those core rows are compulsory-topic specific. M1 unit codes are the topic
-- numbers printed in math/M1/analyse.xlsx. They are stored as-is and scoped
-- by syllabus:
--   ms  = M&S / older syllabus (years before 2012): topics 1-16
--   dse = 2012 and after, including this workbook's SP/PP and an ON paper: topics 1-12
-- The same topic number can exist in both catalogues. 13-16 exist only on ms.
-- This schema does not renumber them and does not write seed_topics.sql
-- (band = '1', HKDSE-M1-*).
--
-- If an earlier draft created these tables with unit_code as the only key,
-- drop analyse_m1_sq_units, analyse_m1_sq, and analyse_m1_units before
-- applying this file. CREATE TABLE IF NOT EXISTS will not add syllabus.
--
-- The M1 workbook has no multiple-choice paper. Sheet2 and Sheet3 are empty
-- in the current file, so only structured-question tables are defined.
-- There is no question-type axis in the grid, so there is no
-- analyse_m1_unit_qtypes table.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS analyse_m1_units (
  syllabus VARCHAR(8) NOT NULL COMMENT 'ms = topics 1-16; dse = topics 1-12',
  unit_code SMALLINT NOT NULL COMMENT 'Topic number from analyse.xlsx, not a generated id',
  short_name VARCHAR(64) NULL COMMENT 'Legend column B, NULL when the workbook leaves it blank',
  name VARCHAR(191) NULL COMMENT 'Legend column F, NULL when the workbook leaves it blank',
  PRIMARY KEY (syllabus, unit_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analyse_m1_sq (
  id INT NOT NULL COMMENT 'Stable id assigned by db/seed_analyse_m1.py',
  sheet_name VARCHAR(64) NOT NULL,
  year_key VARCHAR(32) NOT NULL COMMENT 'Header text; repeated headers gain #column, e.g. 12#T',
  year_label VARCHAR(32) NOT NULL COMMENT 'Exact header cell, including a repeated 12',
  label_occurrence SMALLINT NOT NULL COMMENT '1-based left-to-right occurrence of year_label on this sheet',
  source_column VARCHAR(8) NOT NULL COMMENT 'Excel column letter of the year header',
  question_no SMALLINT NOT NULL COMMENT 'Question number from column A',
  raw_cell VARCHAR(255) NOT NULL COMMENT 'Topic-number cell exactly as stored, e.g. 10,12 or 4, 7',
  syllabus VARCHAR(8) NOT NULL COMMENT 'ms or dse, from the year column',
  PRIMARY KEY (id),
  UNIQUE KEY uq_analyse_m1_sq (sheet_name, year_key, question_no),
  UNIQUE KEY uq_analyse_m1_sq_id_syllabus (id, syllabus),
  KEY idx_analyse_m1_sq_year (year_label, question_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analyse_m1_sq_units (
  sq_id INT NOT NULL,
  position SMALLINT NOT NULL COMMENT '1-based order of the topic number inside the cell',
  syllabus VARCHAR(8) NOT NULL COMMENT 'Same syllabus as the question',
  unit_code SMALLINT NOT NULL COMMENT 'Same topic number as analyse_m1_units.unit_code',
  PRIMARY KEY (sq_id, position),
  KEY idx_analyse_m1_sq_units_unit (syllabus, unit_code),
  CONSTRAINT fk_analyse_m1_sq_units_sq
    FOREIGN KEY (sq_id, syllabus) REFERENCES analyse_m1_sq (id, syllabus)
    ON DELETE CASCADE,
  CONSTRAINT fk_analyse_m1_sq_units_unit
    FOREIGN KEY (syllabus, unit_code) REFERENCES analyse_m1_units (syllabus, unit_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
