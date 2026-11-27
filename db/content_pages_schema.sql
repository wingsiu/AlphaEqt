-- Live alphaeqt content-page shape.
--
-- Production already has these tables (InnoDB, utf8mb4_general_ci). This file
-- is the repo copy of that design. It does not INSERT, UPDATE, or DELETE
-- rows. Do not source it into the live server from a cloud agent; apply it
-- only on a database you mean to change.
--
-- OCR `pages` are a different table. This file does not create or alter them.
-- content_blocks has no slug. questions has no question_no.
-- questions.source_type is CHAR(1) with no CHECK: S=school, P=publisher,
-- A=author (a question written by the user).
--
-- content_pages.current_version_id points at content_page_versions, and
-- content_page_versions.page_id points back. The version table is created
-- first without the pages FK, then the pages FK is added.
--
-- USE alphaeqt because binlog-do-db filters on the selected database.

USE alphaeqt;

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS content_blocks (
  id INT NOT NULL AUTO_INCREMENT,
  kind VARCHAR(16) NOT NULL COMMENT 'question|answer|solution|hint|formula|topic|title|theorem|text|figure',
  title VARCHAR(255) NULL,
  markdown MEDIUMTEXT NOT NULL,
  status CHAR(1) NOT NULL DEFAULT 'D' COMMENT 'D=draft A=active',
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- An older content_blocks may already exist without title. Add the column
-- after kind. Do not add a slug.
SET @content_block_title_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'content_blocks'
    AND COLUMN_NAME = 'title'
);
SET @content_block_title_sql := IF(
  @content_block_title_exists = 0,
  'ALTER TABLE content_blocks ADD COLUMN title VARCHAR(255) NULL AFTER `kind`',
  'SELECT 1'
);
PREPARE content_block_title_stmt FROM @content_block_title_sql;
EXECUTE content_block_title_stmt;
DEALLOCATE PREPARE content_block_title_stmt;

CREATE TABLE IF NOT EXISTS content_block_revisions (
  id INT NOT NULL AUTO_INCREMENT,
  content_block_id INT NOT NULL,
  revision_no INT NOT NULL,
  markdown MEDIUMTEXT NOT NULL,
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_content_block_revisions_block_no (content_block_id, revision_no),
  CONSTRAINT fk_content_block_revisions_block
    FOREIGN KEY (content_block_id) REFERENCES content_blocks (id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS papers (
  id INT NOT NULL AUTO_INCREMENT,
  slug VARCHAR(64) NOT NULL,
  title VARCHAR(255) NOT NULL,
  source_pdf VARCHAR(255) NULL,
  dpi INT NULL,
  status CHAR(1) NOT NULL DEFAULT 'D' COMMENT 'D=draft A=active',
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_papers_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS questions (
  id INT NOT NULL AUTO_INCREMENT,
  paper_id INT NULL,
  stem_block_id INT NOT NULL,
  source_type CHAR(1) NOT NULL COMMENT 'S=school P=publisher A=author',
  qkind CHAR(2) NOT NULL DEFAULT 'MC' COMMENT 'MC|SQ|LQ',
  level VARCHAR(32) NULL,
  marks INT NULL,
  topic_id INT NULL,
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY idx_questions_paper (paper_id),
  KEY idx_questions_stem (stem_block_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- Keep the live comment when questions already existed. No CHECK is added.
SET @questions_source_type_exists := (
  SELECT COUNT(*) FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'questions'
    AND COLUMN_NAME = 'source_type'
);
SET @questions_source_type_sql := IF(
  @questions_source_type_exists = 1,
  'ALTER TABLE questions MODIFY COLUMN source_type CHAR(1) NOT NULL COMMENT ''S=school P=publisher A=author''',
  'SELECT 1'
);
PREPARE questions_source_type_stmt FROM @questions_source_type_sql;
EXECUTE questions_source_type_stmt;
DEALLOCATE PREPARE questions_source_type_stmt;

CREATE TABLE IF NOT EXISTS content_pages (
  id INT NOT NULL AUTO_INCREMENT,
  slug VARCHAR(64) NOT NULL,
  title VARCHAR(255) NOT NULL,
  kind VARCHAR(16) NOT NULL DEFAULT 'note' COMMENT 'note|web|app',
  status CHAR(1) NOT NULL DEFAULT 'D' COMMENT 'D=draft A=active',
  current_version_id INT NULL,
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_content_pages_slug (slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE IF NOT EXISTS content_page_versions (
  id INT NOT NULL AUTO_INCREMENT,
  page_id INT NOT NULL,
  version_no INT NOT NULL,
  note VARCHAR(255) NULL,
  status CHAR(1) NOT NULL DEFAULT 'D' COMMENT 'D=draft A=published',
  created TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_content_page_versions_page_no (page_id, version_no),
  CONSTRAINT fk_content_page_versions_page
    FOREIGN KEY (page_id) REFERENCES content_pages (id)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

SET @content_pages_version_fk_exists := (
  SELECT COUNT(*) FROM information_schema.TABLE_CONSTRAINTS
  WHERE CONSTRAINT_SCHEMA = DATABASE()
    AND TABLE_NAME = 'content_pages'
    AND CONSTRAINT_NAME = 'fk_content_pages_current_version'
);
SET @content_pages_version_fk_sql := IF(
  @content_pages_version_fk_exists = 0,
  'ALTER TABLE content_pages ADD CONSTRAINT fk_content_pages_current_version FOREIGN KEY (current_version_id) REFERENCES content_page_versions (id) ON DELETE SET NULL',
  'SELECT 1'
);
PREPARE content_pages_version_fk_stmt FROM @content_pages_version_fk_sql;
EXECUTE content_pages_version_fk_stmt;
DEALLOCATE PREPARE content_pages_version_fk_stmt;

CREATE TABLE IF NOT EXISTS content_page_items (
  version_id INT NOT NULL,
  sortorder INT NOT NULL,
  content_block_id INT NOT NULL,
  revision_id INT NOT NULL,
  PRIMARY KEY (version_id, sortorder),
  KEY idx_content_page_items_block (content_block_id),
  KEY idx_content_page_items_revision (revision_id),
  CONSTRAINT fk_content_page_items_version
    FOREIGN KEY (version_id) REFERENCES content_page_versions (id)
    ON DELETE CASCADE,
  CONSTRAINT fk_content_page_items_block
    FOREIGN KEY (content_block_id) REFERENCES content_blocks (id)
    ON DELETE RESTRICT,
  CONSTRAINT fk_content_page_items_revision
    FOREIGN KEY (revision_id) REFERENCES content_block_revisions (id)
    ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
