-- HKDSE Mathematics Module 1 (M1) past-paper Analyse map.
--
-- Parallel to the compulsory-core tables, which this file does not create
-- and does not alter:
--   analyse_mc, analyse_mc_units, analyse_sq, analyse_sq_units,
--   analyse_units, analyse_unit_qtypes
--
-- Those core rows are compulsory-topic specific. M1 unit codes are the topic
-- numbers printed in math/M1/analyse.xlsx (legend column A and the year x
-- question cells). They are stored as-is. This schema does not renumber them
-- and does not write the curriculum tree in seed_topics.sql (band = '1',
-- HKDSE-M1-*).
--
-- The M1 workbook has no multiple-choice paper. Sheet2 and Sheet3 are empty
-- in the current file, so only structured-question tables are defined.
-- There is no question-type axis in the grid, so there is no
-- analyse_m1_unit_qtypes table.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS analyse_m1_units (
  unit_code SMALLINT NOT NULL COMMENT 'Topic number from analyse.xlsx, not a generated id',
  short_name VARCHAR(64) NULL COMMENT 'Legend column B, NULL when the workbook leaves it blank',
  name VARCHAR(191) NULL COMMENT 'Legend column F, NULL when the workbook leaves it blank',
  PRIMARY KEY (unit_code)
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
  PRIMARY KEY (id),
  UNIQUE KEY uq_analyse_m1_sq (sheet_name, year_key, question_no),
  KEY idx_analyse_m1_sq_year (year_label, question_no)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS analyse_m1_sq_units (
  sq_id INT NOT NULL,
  position SMALLINT NOT NULL COMMENT '1-based order of the topic number inside the cell',
  unit_code SMALLINT NOT NULL COMMENT 'Same topic number as analyse_m1_units.unit_code',
  PRIMARY KEY (sq_id, position),
  KEY idx_analyse_m1_sq_units_unit (unit_code),
  CONSTRAINT fk_analyse_m1_sq_units_sq
    FOREIGN KEY (sq_id) REFERENCES analyse_m1_sq (id)
    ON DELETE CASCADE,
  CONSTRAINT fk_analyse_m1_sq_units_unit
    FOREIGN KEY (unit_code) REFERENCES analyse_m1_units (unit_code)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
