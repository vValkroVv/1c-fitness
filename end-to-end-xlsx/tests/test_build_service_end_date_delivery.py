from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

from openpyxl import Workbook


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "build_service_end_date_delivery.py"
SPEC = importlib.util.spec_from_file_location(
    "service_end_date_delivery_builder", MODULE_PATH
)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = builder
SPEC.loader.exec_module(builder)


def workbook(path: Path, *, fio: str, end_date: date | None) -> None:
    book = Workbook()
    sheet = book.active
    sheet.title = "Импорт_услуги"
    sheet.append(["service_id", "client_id", "client_fio", "end_date"])
    sheet.append(["Номер", "Клиент", "ФИО", "Дата окончания"])
    sheet.append(["SERVICE", "CLIENT", fio, end_date])
    book.save(path)
    book.close()


class TargetedDeliveryValidationTests(unittest.TestCase):
    def test_only_end_date_change_is_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            old_path = Path(directory) / "old.xlsx"
            new_path = Path(directory) / "new.xlsx"
            workbook(old_path, fio="Тестовый Клиент", end_date=None)
            workbook(
                new_path,
                fio="Тестовый Клиент",
                end_date=date(2026, 7, 28),
            )
            result = builder.validate_targeted_change(old_path, new_path)
        self.assertEqual(result["rows"], 1)
        self.assertEqual(result["changed_cells"], 1)
        self.assertEqual(result["blank_end_dates"], 0)

    def test_non_end_date_change_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            old_path = Path(directory) / "old.xlsx"
            new_path = Path(directory) / "new.xlsx"
            workbook(old_path, fio="Тестовый Клиент", end_date=None)
            workbook(
                new_path,
                fio="Другой Клиент",
                end_date=date(2026, 7, 28),
            )
            with self.assertRaisesRegex(ValueError, "non-authorized cell"):
                builder.validate_targeted_change(old_path, new_path)

    def test_blank_end_date_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            old_path = Path(directory) / "old.xlsx"
            new_path = Path(directory) / "new.xlsx"
            workbook(old_path, fio="Тестовый Клиент", end_date=None)
            workbook(new_path, fio="Тестовый Клиент", end_date=None)
            with self.assertRaisesRegex(ValueError, "blank end dates|no end-date"):
                builder.validate_targeted_change(old_path, new_path)


if __name__ == "__main__":
    unittest.main()
