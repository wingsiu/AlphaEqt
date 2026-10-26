-- Worked solutions for HKDSE M1 and M2, loaded from Hoksi LaTeX/HTML.
--
-- This file creates the editorial parent rows the solution text hangs on:
--   papers → questions → solutions
--
-- It does not create or alter:
--   analyse_mc, analyse_mc_units, analyse_sq, analyse_sq_units,
--   analyse_units, analyse_unit_qtypes,
--   analyse_m1_*, analyse_pm_*,
--   sq_keys, mc_keys, answers, hints
--
-- Core compulsory papers (slugs such as dse2015-math-cp1) are not written
-- by db/seed_hoksi_solutions.py. Pure Maths and M&S have no Hoksi pack;
-- this schema does not invent those rows.
--
-- CREATE TABLE IF NOT EXISTS does not change a table that already exists.
-- db/seed_hoksi_solutions.py --apply probes columns and refuses to write
-- when papers, questions, or solutions already exist with a shape it
-- cannot map. It creates these tables only when all three are absent.
--
-- answers and hints stay empty: a Hoksi M1/M2 article is one worked
-- solution, not a separate key or hint.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS papers (
  id INT NOT NULL AUTO_INCREMENT,
  slug VARCHAR(64) NOT NULL COMMENT 'dse2015-math-m1, dsesp-math-m2, dsepp-math-m1',
  title VARCHAR(255) NOT NULL,
  subject VARCHAR(16) NOT NULL COMMENT 'm1 or m2 for this ingest',
  year_label VARCHAR(16) NOT NULL COMMENT '2015, SP, or PP',
  year SMALLINT NULL COMMENT 'Calendar year; NULL for sample and practice papers',
  paper_no SMALLINT NULL COMMENT 'NULL for the single M1/M2 paper',
  source VARCHAR(32) NOT NULL DEFAULT 'hoksi',
  source_topic VARCHAR(128) NULL COMMENT 'Hoksi topic slug',
  PRIMARY KEY (id),
  UNIQUE KEY uq_papers_slug (slug),
  KEY idx_papers_subject_year (subject, year_label)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS questions (
  id INT NOT NULL AUTO_INCREMENT,
  paper_id INT NOT NULL,
  question_no SMALLINT NOT NULL,
  slug VARCHAR(128) NOT NULL COMMENT 'dse2015-math-m1-q1',
  title VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_questions_paper_no (paper_id, question_no),
  UNIQUE KEY uq_questions_slug (slug),
  CONSTRAINT fk_questions_paper
    FOREIGN KEY (paper_id) REFERENCES papers (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS solutions (
  id INT NOT NULL AUTO_INCREMENT,
  question_id INT NOT NULL,
  lang VARCHAR(16) NOT NULL DEFAULT 'zh-HK',
  format VARCHAR(16) NOT NULL DEFAULT 'markdown' COMMENT 'markdown (LaTeX in $ / $$) or html',
  body MEDIUMTEXT NOT NULL COMMENT 'Worked solution. LaTeX uses $ and $$ when format is markdown',
  html MEDIUMTEXT NULL COMMENT 'Original Hoksi section HTML, including math-tex spans',
  source VARCHAR(32) NOT NULL DEFAULT 'hoksi',
  source_slug VARCHAR(191) NOT NULL COMMENT 'Hoksi article slug',
  source_url VARCHAR(255) NULL,
  PRIMARY KEY (id),
  UNIQUE KEY uq_solutions_question_lang_source (question_id, lang, source),
  CONSTRAINT fk_solutions_question
    FOREIGN KEY (question_id) REFERENCES questions (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
