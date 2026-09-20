from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from openpyxl import Workbook


ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


delivery_builder = load_module(
    "funnel_label_delivery_builder",
    ROOT / "scripts" / "build_funnel_label_delivery.py",
)
combined_builder = load_module(
    "part2_combined_builder_for_label_test",
    ROOT / "scripts" / "17_build_part2_combined_xlsx.py",
)


def owner_workbook(
    path: Path,
    *,
    funnel: str,
    funnel_step: str,
    active_fio: str = "Активный Клиент",
) -> None:
    workbook = Workbook()
    sheet = workbook.active
    sheet.title = "Лист1"
    sheet.append(["client_id", "client_fio", "funnel", "funnel_step"])
    sheet.append(
        [
            "Внутренний номер клиента ",
            "ФИО клиента *",
            "Воронка *",
            "Этап воронки *",
        ]
    )
    sheet.append(
        [
            "000000001",
            active_fio,
            "Действующие абонементы",
            "Все действующие абонементы",
        ]
    )
    sheet.append(["000000002", "Клиент Реактивации", funnel, funnel_step])
    workbook.save(path)
    workbook.close()


class FunnelLabelAlgorithmTests(unittest.TestCase):
    def test_combined_builder_uses_customer_requested_labels(self) -> None:
        self.assertEqual(
            combined_builder.FITBASE_LABELS["Реактивация"],
            ("Реактивация", "Закрытые годовые абонементы"),
        )
        mapped = combined_builder.apply_fitbase_labels(
            [{"funnel": "Реактивация", "funnel_step": "30-59 дней"}],
            combined_builder.CUSTOMER_SINGLE_STAGE_MODE,
        )
        self.assertEqual(
            (mapped[0]["funnel"], mapped[0]["funnel_step"]),
            ("Реактивация", "Закрытые годовые абонементы"),
        )


class TargetedDeliveryValidationTests(unittest.TestCase):
    def test_only_two_requested_label_changes_are_allowed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            old_path = Path(directory) / "old.xlsx"
            new_path = Path(directory) / "new.xlsx"
            owner_workbook(
                old_path,
                funnel=delivery_builder.OLD_FUNNEL,
                funnel_step=delivery_builder.OLD_STEP,
            )
            owner_workbook(
                new_path,
                funnel=delivery_builder.NEW_FUNNEL,
                funnel_step=delivery_builder.NEW_STEP,
            )
            result = delivery_builder.validate_targeted_change(old_path, new_path)
        self.assertEqual(result["rows"], 2)
        self.assertEqual(result["reactivation_rows"], 1)
        self.assertEqual(result["changed_rows"], 1)
        self.assertEqual(result["changed_cells"], 2)

    def test_non_label_change_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            old_path = Path(directory) / "old.xlsx"
            new_path = Path(directory) / "new.xlsx"
            owner_workbook(
                old_path,
                funnel=delivery_builder.OLD_FUNNEL,
                funnel_step=delivery_builder.OLD_STEP,
            )
            owner_workbook(
                new_path,
                funnel=delivery_builder.NEW_FUNNEL,
                funnel_step=delivery_builder.NEW_STEP,
                active_fio="Изменённый Активный Клиент",
            )
            with self.assertRaisesRegex(ValueError, "non-authorized cell"):
                delivery_builder.validate_targeted_change(old_path, new_path)

    def test_partial_label_replacement_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            old_path = Path(directory) / "old.xlsx"
            new_path = Path(directory) / "new.xlsx"
            owner_workbook(
                old_path,
                funnel=delivery_builder.OLD_FUNNEL,
                funnel_step=delivery_builder.OLD_STEP,
            )
            owner_workbook(
                new_path,
                funnel=delivery_builder.NEW_FUNNEL,
                funnel_step=delivery_builder.OLD_STEP,
            )
            with self.assertRaisesRegex(ValueError, "not replaced exactly"):
                delivery_builder.validate_targeted_change(old_path, new_path)


if __name__ == "__main__":
    unittest.main()
