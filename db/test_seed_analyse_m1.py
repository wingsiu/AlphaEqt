#!/usr/bin/env python3
"""Verify M1 Analyse parsing keeps the topic numbers from analyse.xlsx."""

from __future__ import annotations

import importlib.util
import re
import sys
import unittest
import warnings
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.utils import get_column_letter

ROOT = Path(__file__).resolve().parent
FIXTURE = ROOT / "fixtures" / "M1" / "analyse.xlsx"


def load_seeder():
    spec = importlib.util.spec_from_file_location("seed_analyse_m1", ROOT / "seed_analyse_m1.py")
    if spec is None or spec.loader is None:
        raise RuntimeError("could not load seed_analyse_m1.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class SeedAnalyseM1Test(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = load_seeder()
        cls.mapping = cls.mod.load_m1_workbook(FIXTURE)

    def test_fixture_exists(self):
        self.assertTrue(FIXTURE.is_file())

    def test_topic_numbers_match_excel_codes(self):
        codes = [unit.code for unit in self.mapping.units]
        self.assertEqual(codes, list(range(1, 17)))
        by_code = {unit.code: unit for unit in self.mapping.units}
        self.assertEqual(by_code[1].short_name, "binomial")
        self.assertEqual(by_code[1].name, "Binomial")
        self.assertEqual(by_code[3].short_name, "limit")
        self.assertEqual(by_code[3].name, "limits")
        self.assertEqual(by_code[5].name, "Application of Differentiation(1)")
        self.assertIsNone(by_code[13].short_name)
        self.assertIsNone(by_code[13].name)
        self.assertIsNone(by_code[15].name)
        self.assertIsNone(by_code[16].short_name)

    def test_grid_counts_and_cell_order(self):
        self.assertEqual(len(self.mapping.questions), 448)
        links = sum(len(question.unit_codes) for question in self.mapping.questions)
        self.assertEqual(links, 498)
        self.assertEqual(self.mapping.errors, ())

        def find(year_key: str, question_no: int):
            matches = [
                question
                for question in self.mapping.questions
                if question.year_key == year_key and question.question_no == question_no
            ]
            self.assertEqual(len(matches), 1)
            return matches[0]

        self.assertEqual(find("94", 1).unit_codes, (12,))
        self.assertEqual(find("94", 1).source_column, "B")
        self.assertEqual(find("00", 1).year_label, "00")
        self.assertEqual(find("00", 1).unit_codes, (6,))
        self.assertEqual(find("09", 8).raw_cell, "4, 7")
        self.assertEqual(find("09", 8).unit_codes, (4, 7))
        self.assertEqual(find("25", 1).unit_codes, (10, 12))
        self.assertEqual(find("SP", 14).unit_codes, (12,))
        self.assertEqual(find("12#T", 2).unit_codes, (4,))
        self.assertEqual(find("12#U", 2).unit_codes, (8,))
        self.assertEqual(find("12#T", 2).year_label, "12")
        self.assertEqual(find("12#T", 2).label_occurrence, 1)
        self.assertEqual(find("12#U", 2).label_occurrence, 2)
        self.assertEqual(find("26", 1).unit_codes, (10,))

    def test_every_grid_cell_uses_the_excel_topic_numbers(self):
        with warnings.catch_warnings():
            warnings.filterwarnings(
                "ignore",
                message="Unknown extension is not supported and will be removed",
                category=UserWarning,
            )
            workbook = load_workbook(FIXTURE, data_only=False)
        sheet = workbook["Sheet1"]
        try:
            headers = {}
            counts = {}
            for column in range(2, sheet.max_column + 1):
                value = sheet.cell(1, column).value
                if value is None:
                    continue
                label = str(value).strip() if not isinstance(value, int) else str(value)
                counts[label] = counts.get(label, 0) + 1
                headers[column] = (get_column_letter(column), label, counts[label])
            seen = 0
            for row in range(2, 16):
                question_no = int(sheet.cell(row, 1).value)
                for column, (letter, label, occurrence) in headers.items():
                    value = sheet.cell(row, column).value
                    if value is None:
                        continue
                    raw = str(value).strip() if not isinstance(value, int) else str(value)
                    expected = tuple(int(part) for part in re.split(r"\s*,\s*", raw))
                    year_key = label if counts[label] == 1 else f"{label}#{letter}"
                    match = next(
                        question
                        for question in self.mapping.questions
                        if question.year_key == year_key and question.question_no == question_no
                    )
                    self.assertEqual(match.unit_codes, expected)
                    self.assertEqual(match.raw_cell, raw)
                    self.assertEqual(match.label_occurrence, occurrence)
                    self.assertEqual(match.source_column, letter)
                    seen += 1
            self.assertEqual(seen, len(self.mapping.questions))
        finally:
            workbook.close()

    def test_empty_sheets_are_skipped(self):
        messages = [notice.message for notice in self.mapping.notices]
        self.assertTrue(any(message.startswith("Sheet2:") for message in messages))
        self.assertTrue(any(message.startswith("Sheet3:") for message in messages))
        sheets = {question.sheet_name for question in self.mapping.questions}
        self.assertEqual(sheets, {"Sheet1"})

    def test_sql_uses_excel_codes_and_skips_core_tables(self):
        sql = self.mod.render_sql(self.mapping)
        self.assertIn("(1, 'binomial', 'Binomial')", sql)
        self.assertIn("(13, NULL, NULL)", sql)
        self.assertIn("(15, NULL, NULL)", sql)
        self.assertIn("'12#T'", sql)
        self.assertIn("'12#U'", sql)
        self.assertIn("'00'", sql)
        self.assertNotIn("2000", sql)
        for name in (
            "analyse_mc",
            "analyse_mc_units",
            "analyse_sq",
            "analyse_sq_units",
            "analyse_units",
            "analyse_unit_qtypes",
        ):
            self.assertNotRegex(sql, rf"\b{name}\b")

    def test_schema_does_not_create_core_tables(self):
        schema = (ROOT / "analyse_m1_schema.sql").read_text(encoding="utf-8")
        self.assertIn("CREATE TABLE IF NOT EXISTS analyse_m1_units", schema)
        self.assertIn("CREATE TABLE IF NOT EXISTS analyse_m1_sq", schema)
        self.assertIn("CREATE TABLE IF NOT EXISTS analyse_m1_sq_units", schema)
        for name in (
            "analyse_mc",
            "analyse_mc_units",
            "analyse_sq",
            "analyse_sq_units",
            "analyse_units",
            "analyse_unit_qtypes",
        ):
            self.assertNotIn(f"CREATE TABLE IF NOT EXISTS {name}", schema)

    def test_resolve_prefers_explicit_path(self):
        resolved = self.mod.resolve_xlsx(str(FIXTURE), None)
        self.assertEqual(resolved, FIXTURE)


if __name__ == "__main__":
    unittest.main()
