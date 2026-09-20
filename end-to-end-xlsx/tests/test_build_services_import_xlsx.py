from __future__ import annotations

import importlib.util
import sys
import unittest
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "23_build_services_import_xlsx.py"
SPEC = importlib.util.spec_from_file_location("services_import_builder", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = builder
SPEC.loader.exec_module(builder)

VALIDATOR_SPEC = importlib.util.spec_from_file_location(
    "services_import_validator", ROOT / "scripts" / "24_validate_services_import_xlsx.py"
)
assert VALIDATOR_SPEC is not None and VALIDATOR_SPEC.loader is not None
validator = importlib.util.module_from_spec(VALIDATOR_SPEC)
sys.modules[VALIDATOR_SPEC.name] = validator
VALIDATOR_SPEC.loader.exec_module(validator)


def source(
    client_id: str = "CLIENT",
    funnel: str = builder.ACTIVE_MEMBERSHIP_FUNNEL,
) -> builder.SourceClient:
    return builder.SourceClient(
        client_id=client_id,
        phone="79990000000",
        client_fio="Тестовый Клиент",
        create_date=date(2024, 1, 1),
        manager="Менеджер",
        branch="Фитнес Империя (Гоголевский)",
        funnel=funnel,
        funnel_step="Продление",
    )


def fact(
    *,
    service_id: str,
    sale_date: str,
    start_date: str,
    end_date: str,
    active_on_cutoff: str,
    active_by_date: str,
    linked: bool = True,
    register_start_date: str | None = None,
) -> dict[str, str]:
    return {
        "service_name": "Пакет 8",
        "sale_doc_ref": f"SALE-{service_id}",
        "sale_line_id": f"LINE-{service_id}",
        "sale_datetime": f"{sale_date} 10:00:00",
        "sale_date": sale_date,
        "sale_client_id": "CLIENT",
        "sale_client_fio": "Тестовый Клиент",
        "sale_client_phone": "79990000000",
        "sale_branch": "Фитнес Империя (Гоголевский)",
        "sale_branch_raw": "Гоголевский",
        "sale_branch_source": "test",
        "linked_service_doc_ref": f"REF-{service_id}" if linked else "",
        "service_doc_number": service_id if linked else "",
        "service_doc_holder_id": "CLIENT" if linked else "",
        "service_doc_holder_fio": "Тестовый Клиент" if linked else "",
        "service_start_date": start_date,
        "service_register_start_date": (
            start_date if register_start_date is None else register_start_date
        ),
        "service_end_date": end_date,
        "line_quantity": "1",
        "line_total_amount": "1000",
        "rg_price": "1000",
        "payment_datetime": f"{sale_date} 10:05:00",
        "payment_method": "Эквайринг",
        "is_active_by_balance": active_on_cutoff,
        "is_active_by_date": active_by_date,
        "is_active_on_cutoff": active_on_cutoff,
        "rg3336_signed_balance": "8" if active_on_cutoff == "1" else "0",
    }


class ServiceEndDateTests(unittest.TestCase):
    def build_one(self, current_fact: dict[str, str]):
        rows, _, uncertainties, _, _ = builder.build_rows(
            {"CLIENT": source()},
            ["Пакет 8"],
            [current_fact],
        )
        self.assertEqual(len(rows), 1)
        return rows[0], uncertainties

    def test_real_register_dates_are_exported(self) -> None:
        row, _ = self.build_one(
            fact(
                service_id="00000068326",
                sale_date="2020-03-24",
                start_date="2020-03-24",
                end_date="2020-07-28",
                active_on_cutoff="1",
                active_by_date="0",
            )
        )
        self.assertEqual(row["activation_date"], date(2020, 3, 24))
        self.assertEqual(row["end_date"], date(2020, 7, 28))
        self.assertEqual(
            row["_end_date_source"], builder.REGISTER_END_DATE_SOURCE
        )

    def test_unactivated_balance_row_gets_audited_end_fallback(self) -> None:
        row, uncertainties = self.build_one(
            fact(
                service_id="00000152206",
                sale_date="2026-06-25",
                start_date="",
                end_date="",
                active_on_cutoff="1",
                active_by_date="0",
            )
        )
        self.assertIsNone(row["activation_date"])
        self.assertEqual(row["end_date"], date(2026, 6, 25))
        self.assertEqual(
            row["_activation_date_source"], "not_activated_in_register"
        )
        self.assertEqual(
            row["_end_date_source"], builder.SALE_DATE_FALLBACK_SOURCE
        )
        self.assertTrue(
            any(
                item["issue_type"] == "service_end_date_sale_date_fallback"
                for item in uncertainties
            )
        )

    def test_register_start_does_not_overwrite_accepted_blank_activation(self) -> None:
        row, _ = self.build_one(
            fact(
                service_id="LIVE",
                sale_date="2026-06-01",
                start_date="",
                register_start_date="2026-06-02",
                end_date="2026-07-01",
                active_on_cutoff="1",
                active_by_date="1",
            )
        )
        self.assertIsNone(row["activation_date"])
        self.assertEqual(
            row["_activation_date_source"],
            builder.PRESERVED_BLANK_ACTIVATION_SOURCE,
        )
        self.assertEqual(row["_register_start_date"], date(2026, 6, 2))

    def test_historical_direct_sale_keeps_zero_visits_and_gets_end_date(self) -> None:
        row, _ = self.build_one(
            fact(
                service_id="DIRECT",
                sale_date="2022-02-03",
                start_date="",
                end_date="",
                active_on_cutoff="0",
                active_by_date="0",
                linked=False,
            )
        )
        self.assertEqual(row["_row_kind"], "historical_fallback")
        self.assertEqual(row["activation_date"], date(2022, 2, 3))
        self.assertEqual(row["end_date"], date(2022, 2, 3))
        self.assertEqual(row["visits_left"], 0)


class ServiceManagerTests(unittest.TestCase):
    POOL = ["Пеуна Анастасия Ивановна", "Пилия Анастасия Артуровна", "Ефремова Алена"]

    def outside_fact(self):
        return fact(
            service_id="SERVICE_ONLY", sale_date="2022-02-03", start_date="", end_date="",
            active_on_cutoff="0", active_by_date="0", linked=False,
        )

    def test_service_only_client_keeps_row_and_all_fields_except_manager(self):
        current = self.outside_fact()
        previous, *_ = builder.build_rows({}, ["Пакет 8"], [current])
        rows, *_ = builder.build_rows({}, ["Пакет 8"], [current], manager_pools={"*": self.POOL})
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["manager"], builder.manager_tools().stable_manager("CLIENT", self.POOL))
        self.assertEqual(rows[0]["_outside_import_zayavki"], "1")
        self.assertEqual(rows[0]["phone"], "79990000000")
        self.assertEqual({key: value for key, value in rows[0].items() if key != "manager"},
                         {key: value for key, value in previous[0].items() if key != "manager"})
        for branch in ("Гоголевский", "Ровио", "", "Неизвестный клуб"):
            changed = {**current, "sale_branch": branch, "sale_branch_raw": branch}
            assigned = builder.source_client_for_fact(changed, {}, {"*": self.POOL})
            self.assertEqual(assigned.manager, rows[0]["manager"])

    def test_existing_client_assignment_is_shared_with_main_workbook(self):
        current = self.outside_fact()
        manager = builder.manager_tools().stable_manager("CLIENT", self.POOL)
        original = source()
        existing = builder.SourceClient(**{**original.__dict__, "manager": manager})
        selected = builder.source_client_for_fact(current, {"CLIENT": existing}, {"*": self.POOL})
        self.assertIs(selected, existing)
        rows, *_ = builder.build_rows({"CLIENT": existing}, ["Пакет 8"], [current], manager_pools={"*": self.POOL})
        values = [tuple(row.get(header) for header in builder.CLIENT_HEADERS) for row in rows]
        self.assertEqual(validator.manager_validation_errors(values, {"*": self.POOL}, {"CLIENT": manager}), [])

    def test_validator_rejects_placeholder_and_wrong_valid_pool_member(self):
        rows, *_ = builder.build_rows({}, ["Пакет 8"], [self.outside_fact()], manager_pools={"*": self.POOL})
        original = rows[0]
        values = [tuple(original.get(header) for header in builder.CLIENT_HEADERS)]
        self.assertEqual(validator.manager_validation_errors(values, {"*": self.POOL}, {}), [])
        for wrong in ("УТОЧНИТЬ: вне import_заявки", next(name for name in self.POOL if name != original["manager"])):
            changed = {**original, "manager": wrong}
            values = [tuple(changed.get(header) for header in builder.CLIENT_HEADERS)]
            errors = validator.manager_validation_errors(values, {"*": self.POOL}, {})
            self.assertTrue(any("global client-ID assignment" in error for error in errors))

    def test_historical_club_config_keeps_service_only_fallback(self):
        historical = {"Гоголевский": ["Исторический менеджер"]}
        assigned = builder.source_client_for_fact(self.outside_fact(), {}, historical)
        self.assertEqual(assigned.manager, "УТОЧНИТЬ: вне import_заявки")


if __name__ == "__main__":
    unittest.main()
