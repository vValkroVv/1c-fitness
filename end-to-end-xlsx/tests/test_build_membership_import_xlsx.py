from __future__ import annotations

import importlib.util
import csv
import sys
import tempfile
import unittest
from dataclasses import replace
from datetime import date
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "19_build_membership_import_xlsx.py"
SPEC = importlib.util.spec_from_file_location("membership_import_builder", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
builder = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = builder
SPEC.loader.exec_module(builder)


def fact(
    *,
    client_id: str,
    contract_id: str,
    name: str,
    sale_date: str,
    duration_days: str,
    price: str,
    visit_limit: str = "0",
    receipt: str = "0",
    expense: str = "0",
    balance: str = "0",
    active: str = "0",
    finished: str = "0",
    case_group: str = "",
) -> dict[str, str]:
    return {
        "client_id": client_id,
        "effective_client_fio": "Тестовый Клиент",
        "subscription_ref": f"REF{contract_id}",
        "document_number": contract_id,
        "subscription_name": name,
        "product_ref": "PRODUCT",
        "product_class": "full_subscription",
        "is_full_subscription": "1",
        "is_trial_or_guest": "0",
        "is_subrent": "1" if "субаренд" in name.lower() else "0",
        "is_limited_subrent": (
            "1"
            if "субаренд" in name.lower() and "безлимит" not in name.lower()
            else "0"
        ),
        "sale_date": sale_date,
        "sale_datetime": f"{sale_date} 10:00:00",
        "start_date": sale_date,
        "end_date": "2027-06-01",
        "duration_days": duration_days,
        "doc_duration_value": duration_days,
        "status": "",
        "is_active_on_cutoff": active,
        "is_finished_before_cutoff": finished,
        "rg_duration_days": duration_days,
        "rg_freeze_days": "0",
        "rg_price": price,
        "rg_paid_candidate": "0",
        "membership_sale_line_amount": price,
        "membership_sale_line_count": "1",
        "membership_sale_nonzero_line_count": "1" if price != "0" else "0",
        "financial_sale_document_count": "1",
        "financial_sale_membership_count": "1",
        "financial_sale_total_line_count": "1",
        "financial_sale_nonzero_line_count": "1" if price != "0" else "0",
        "financial_sale_total_line_amount": price,
        "financial_sale_document_number": "SALE",
        "financial_sale_document_datetime": f"{sale_date} 10:00:00",
        "financial_sale_document_ref": "SALE_REF",
        "financial_register_allocation_unambiguous": "0",
        "financial_register_row_count": "0",
        "financial_register_charge_sum": "0",
        "financial_register_payment_sum": "0",
        "financial_register_signed_debt": "0",
        "financial_register_charge_row_count": "0",
        "financial_register_payment_row_count": "0",
        "financial_register_last_movement_datetime": "",
        "matched_payment_ref": "PAYMENT",
        "matched_payment_method": "Эквайринг",
        "matched_payment_match_source": "direct_test",
        "matched_payment_operation": "Оплата от клиента",
        "matched_payment_amount": price,
        "sale_branch": "Фитнес Империя (Гоголевский)",
        "subrent_visit_limit": visit_limit,
        "subrent_active_by_dates_on_cutoff": active,
        "subrent_finished_by_dates_before_cutoff": finished,
        "subrent_rg3336_receipt_qty": receipt,
        "subrent_rg3336_expense_qty": expense,
        "subrent_rg3336_signed_balance": balance,
        "subrent_rg3336_case_group": case_group,
        "cutoff_at": "2026-06-30 23:27:03",
    }


def source(client_id: str, first_sale: date = date(2024, 11, 12)):
    return builder.SourceClient(
        client_id=client_id,
        phone="79990000000",
        client_fio="Тестовый Клиент",
        create_date=first_sale,
        manager="Менеджер",
        branch="Фитнес Империя (Гоголевский)",
    )


class VisitLimitTests(unittest.TestCase):
    def test_parser_supports_short_and_full_russian_forms(self) -> None:
        for text in (
            "12 пос",
            "12 пос.",
            "12 посещ",
            "12 посещ.",
            "12 посещение",
            "12 посещения",
            "12 посещений",
        ):
            with self.subTest(text=text):
                self.assertEqual(builder.parse_template_visits(text), 12)
        self.assertIsNone(builder.parse_template_visits("после 12 дней"))

    def test_all_active_cycle_regression_balances(self) -> None:
        expected = {
            "00000138687": (8, 2),
            "00000141600": (12, 3),
            "00000144782": (8, 3),
            "00000144816": (12, 0),
            "00000145361": (12, 2),
            "00000147786": (12, 6),
            "00000147787": (12, 5),
            "00000151241": (12, 7),
        }
        for contract_id, (limit, remaining) in expected.items():
            current_fact = fact(
                client_id="CYCLE",
                contract_id=contract_id,
                name=f"АБОНЕМЕНТ САЙКЛ {limit} пос без клубной карты",
                sale_date="2026-06-02",
                duration_days="365",
                price="6450",
                visit_limit=str(limit),
                receipt=str(limit),
                expense=str(limit - remaining),
                balance=str(remaining),
                active="1",
                case_group="clean_register_balance",
            )
            with self.subTest(contract_id=contract_id):
                value, value_source, issue = builder.compute_visits_left(
                    current_fact, current_fact["subscription_name"]
                )
                self.assertEqual(value, remaining)
                self.assertEqual(value_source, "rg3336_correct_dimension_balance")
                self.assertEqual(issue, "")

    def test_expired_cycle_is_zero_even_for_legacy_dimension(self) -> None:
        expired = fact(
            client_id="CYCLE",
            contract_id="OLD",
            name="АБОНЕМЕНТ САЙКЛ 12 пос без клубной карты",
            sale_date="2024-01-01",
            duration_days="90",
            price="6450",
            finished="1",
        )
        value, value_source, issue = builder.compute_visits_left(
            expired, expired["subscription_name"]
        )
        self.assertEqual(value, 0)
        self.assertEqual(
            value_source, "business_expired_visit_limited_zero_visits_left"
        )
        self.assertEqual(issue, "")

    def test_active_cycle_without_selected_register_dimension_is_not_zeroed(
        self,
    ) -> None:
        missing = fact(
            client_id="CYCLE",
            contract_id="MISSING",
            name="АБОНЕМЕНТ САЙКЛ 12 пос без клубной карты",
            sale_date="2026-06-02",
            duration_days="365",
            price="6450",
            visit_limit="12",
            active="1",
            case_group="no_register_movements",
        )
        value, value_source, issue = builder.compute_visits_left(
            missing, missing["subscription_name"]
        )
        self.assertIsNone(value)
        self.assertEqual(value_source, "rg3336_visit_limited_balance_missing")
        self.assertIn("no usable register balance", issue)


class MembershipBuildTests(unittest.TestCase):
    def test_money_uses_register_payment_and_debt_independently(self) -> None:
        current_fact = fact(
            client_id="DEBT",
            contract_id="00000151758",
            name="Абонемент",
            sale_date="2026-06-14",
            duration_days="365",
            price="10990",
        )
        current_fact.update(
            {
                "rg_paid_candidate": "2747",
                "financial_register_allocation_unambiguous": "1",
                "financial_register_row_count": "3",
                "financial_register_charge_sum": "10990",
                "financial_register_payment_sum": "8243",
                "financial_register_signed_debt": "2747",
            }
        )
        price, paid, debt, source_name = builder.compute_money(current_fact)
        self.assertEqual((price, paid, debt), (10990, 8243, 2747))
        self.assertIn("accumrg3305_sale_balance", source_name)

    def test_money_keeps_register_correction_out_of_sold_amount(self) -> None:
        current_fact = fact(
            client_id="CORRECTION",
            contract_id="00000148035",
            name="Абонемент",
            sale_date="2026-03-13",
            duration_days="365",
            price="11990",
        )
        current_fact.update(
            {
                "rg_paid_candidate": "3997.11",
                "financial_register_allocation_unambiguous": "1",
                "financial_register_row_count": "3",
                "financial_register_charge_sum": "8993",
                "financial_register_payment_sum": "5995",
                "financial_register_signed_debt": "2998",
            }
        )
        self.assertEqual(
            builder.compute_money(current_fact)[:3],
            (11990, 5995, 2998),
        )

    def test_money_treats_fld3072_as_debt_when_register_is_ambiguous(self) -> None:
        current_fact = fact(
            client_id="LEGACY",
            contract_id="LEGACY",
            name="Абонемент",
            sale_date="2020-01-01",
            duration_days="365",
            price="11000",
        )
        current_fact.update(
            {
                "rg_paid_candidate": "6000",
                "financial_register_allocation_unambiguous": "0",
                "financial_register_row_count": "1",
                "financial_sale_membership_count": "2",
            }
        )
        price, paid, debt, source_name = builder.compute_money(current_fact)
        self.assertEqual((price, paid, debt), (11000, 5000, 6000))
        self.assertIn("fld3072_debt_fallback", source_name)

    def test_money_uses_sale_line_when_information_price_is_zero(self) -> None:
        current_fact = fact(
            client_id="ZERO_INFO",
            contract_id="ZERO_INFO",
            name="Абонемент",
            sale_date="2026-02-01",
            duration_days="365",
            price="0",
        )
        current_fact.update(
            {
                "membership_sale_line_amount": "11990",
                "financial_register_allocation_unambiguous": "1",
                "financial_register_row_count": "2",
                "financial_register_charge_sum": "11990",
                "financial_register_payment_sum": "11990",
                "financial_register_signed_debt": "0",
            }
        )
        self.assertEqual(
            builder.compute_money(current_fact)[:3],
            (11990, 11990, 0),
        )
        self.assertEqual(
            builder.business_zero_override_reason(current_fact, Decimal("11990")),
            "",
        )

    def test_historical_refund_override_still_uses_zero_info_price(self) -> None:
        current_fact = fact(
            client_id="REFUND",
            contract_id="REFUND",
            name="Абонемент",
            sale_date="2020-02-01",
            duration_days="365",
            price="0",
        )
        current_fact.update(
            {
                "membership_sale_line_amount": "11990",
                "matched_payment_match_source": "direct_test",
                "document131_posted_unmarked_refund_count": "1",
                "is_active_on_cutoff": "0",
            }
        )
        self.assertEqual(
            builder.business_zero_override_reason(current_fact, Decimal("11990")),
            "business_historical_document131_refund_zero_direct_blank_payment",
        )

    def test_ponedelnik_sale_date_and_cycle_fields(self) -> None:
        current_fact = fact(
            client_id="PONEDELNIK",
            contract_id="00000151241",
            name="АБОНЕМЕНТ САЙКЛ 12 пос без клубной карты",
            sale_date="2026-06-02",
            duration_days="365",
            price="6450",
            visit_limit="12",
            receipt="12",
            expense="5",
            balance="7",
            active="1",
            case_group="clean_register_balance",
        )
        rows, templates, _, _, _ = builder.build_rows(
            {"PONEDELNIK": source("PONEDELNIK")},
            {},
            [current_fact],
            {},
        )
        self.assertEqual(rows[0]["create_date"], date(2026, 6, 2))
        self.assertEqual(rows[0]["payment_date"], date(2026, 6, 2))
        self.assertEqual(rows[0]["visits_left"], 7)
        self.assertEqual(templates[0]["visits"], 12)

    def shuleyko_facts(self) -> list[dict[str, str]]:
        current = fact(
            client_id="SHULEYKO",
            contract_id="00000140663",
            name="Абонемент УЛЬТРА 12 месяцев СПЕЦПРЕДЛОЖЕНИЕ",
            sale_date="2025-09-23",
            duration_days="365",
            price="12990",
            active="1",
        )
        later_variant = fact(
            client_id="SHULEYKO",
            contract_id="00000148508",
            name="Абонемент УЛЬТРА 12 месяцев СПЕЦПРЕДЛОЖЕНИЕ",
            sale_date="2026-03-25",
            duration_days="457",
            price="0",
            active="1",
        )
        return [current, later_variant]

    def test_shuleyko_uses_explicit_template_decision(self) -> None:
        decision = builder.TemplateCanonicalization(
            canonical_name="Абонемент УЛЬТРА 12 месяцев СПЕЦПРЕДЛОЖЕНИЕ",
            branches_access="Продажа",
            price=12990,
            duration=12,
            visits=None,
            freeze=None,
            source_contract_id="00000140663",
            decision_basis="manager_case_shuleyko_140663",
            review_status="manager_evidence_confirmed",
            note="test",
        )
        rows, templates, uncertainties, _, _ = builder.build_rows(
            {"SHULEYKO": source("SHULEYKO", date(2023, 8, 31))},
            {},
            self.shuleyko_facts(),
            {decision.normalized_name: decision},
        )
        row_140663 = next(row for row in rows if row["contract_id"] == "00000140663")
        self.assertEqual(row_140663["create_date"], date(2025, 9, 23))
        self.assertEqual(templates[0]["price"], 12990)
        self.assertEqual(templates[0]["duration"], 12)
        self.assertTrue(
            any(
                item["issue_type"] == "template_variants_canonicalized_by_config"
                for item in uncertainties
            )
        )

    def test_unconfigured_template_conflict_fails_fast(self) -> None:
        with self.assertRaisesRegex(
            ValueError, "Unresolved membership template conflict"
        ):
            builder.build_rows(
                {"SHULEYKO": source("SHULEYKO", date(2023, 8, 31))},
                {},
                self.shuleyko_facts(),
                {},
            )

    def test_checked_in_config_has_all_current_conflicts(self) -> None:
        decisions = builder.read_template_canonicalizations(
            ROOT / "config" / "membership_template_canonicalization.csv"
        )
        self.assertGreaterEqual(len(decisions), 93)
        self.assertIn(
            builder.normalize_key("Абонемент УЛЬТРА 12 месяцев СПЕЦПРЕДЛОЖЕНИЕ"),
            decisions,
        )


class HistoricalTemplateTests(unittest.TestCase):
    def decision(self, **changes):
        return replace(
            builder.TemplateCanonicalization(
                canonical_name="Тестовый абонемент",
                branches_access="Продажа",
                price=12990,
                duration=12,
                visits=None,
                freeze=30,
                source_contract_id="SOURCE",
                decision_basis="accepted_june_delivery",
                review_status="accepted_delivery_preserved",
                note="Historical template confirmed against the accepted workbook",
            ),
            **changes,
        )

    def current_fact(self, contract_id="SOURCE", *, duration_days="457", freeze="5", price="14990"):
        current = fact(
            client_id="CLIENT",
            contract_id=contract_id,
            name="Тестовый абонемент",
            sale_date="2025-09-23",
            duration_days=duration_days,
            price=price,
            active="1",
        )
        current["rg_freeze_days"] = freeze
        return current

    def build(self, facts, decision):
        return builder.build_rows(
            {"CLIENT": source("CLIENT")},
            {},
            facts,
            {decision.normalized_name: decision},
        )

    def test_absent_variant_is_rejected_by_default(self) -> None:
        decision = self.decision()
        self.assertFalse(decision.allow_historical_variant)
        with self.assertRaisesRegex(ValueError, "variant is not present in staging"):
            self.build([self.current_fact()], decision)

    def test_changed_source_is_rejected_even_when_variant_still_exists(self) -> None:
        with self.assertRaisesRegex(ValueError, "source contract no longer has"):
            self.build(
                [
                    self.current_fact(),
                    self.current_fact("OTHER", duration_days="365", freeze="30", price="12990"),
                ],
                self.decision(),
            )

    def test_historical_opt_in_preserves_template_and_current_client_values(self) -> None:
        decision = self.decision(allow_historical_variant=True)
        rows, templates, uncertainties, _, counters = self.build(
            [self.current_fact()], decision
        )
        self.assertEqual(builder.template_variant(templates[0]), decision.variant)
        self.assertEqual((rows[0]["duration"], rows[0]["freeze"], rows[0]["price"]), (15, 5, 14990))
        self.assertEqual(rows[0]["amount_of_payments"], 14990)
        self.assertEqual(rows[0]["create_date"], date(2025, 9, 23))
        issue_type = "configured_historical_template_variant_preserved"
        self.assertEqual(counters["template_canonicalization"][issue_type], 1)
        issue = next(item for item in uncertainties if item["issue_type"] == issue_type)
        self.assertEqual(issue["contract_id"], "SOURCE")
        for detail in (
            "allow_historical_variant=1",
            "configured=(12990, 12, None, 30, 'Продажа')",
            "observed=",
            "(14990, 15, None, 5, 'Продажа')",
            "source_contract_id='SOURCE'",
            "source_observed=",
            "decision_basis=accepted_june_delivery",
        ):
            self.assertIn(detail, issue["details"])

    def test_historical_opt_in_also_audits_source_change_with_matching_variant(self) -> None:
        rows, templates, _, _, counters = self.build(
            [
                self.current_fact(),
                self.current_fact("OTHER", duration_days="365", freeze="30", price="12990"),
            ],
            self.decision(allow_historical_variant=True),
        )
        self.assertEqual(len(rows), 2)
        self.assertEqual(templates[0]["freeze"], 30)
        self.assertEqual(
            counters["template_canonicalization"]["configured_historical_template_variant_preserved"],
            1,
        )

    def test_historical_opt_in_with_unchanged_variant_needs_no_exception(self) -> None:
        _, _, uncertainties, _, counters = self.build(
            [self.current_fact(duration_days="365", freeze="30", price="12990")],
            self.decision(allow_historical_variant=True),
        )
        self.assertEqual(
            counters["template_canonicalization"]["configured_historical_template_variant_preserved"],
            0,
        )
        self.assertFalse(any(
            issue["issue_type"] == "configured_historical_template_variant_preserved"
            for issue in uncertainties
        ))

    def test_price_only_exception_does_not_require_historical_opt_in(self) -> None:
        rows, templates, uncertainties, _, counters = self.build(
            [self.current_fact(duration_days="365", freeze="30")],
            self.decision(),
        )
        self.assertEqual(rows[0]["price"], 14990)
        self.assertEqual(templates[0]["price"], 12990)
        issue_type = "configured_template_price_preserved_after_transaction_rebuild"
        self.assertEqual(counters["template_canonicalization"][issue_type], 1)
        self.assertTrue(any(issue["issue_type"] == issue_type for issue in uncertainties))
        self.assertEqual(
            counters["template_canonicalization"]["configured_historical_template_variant_preserved"],
            0,
        )

    def test_missing_source_with_present_variant_keeps_existing_behavior(self) -> None:
        _, templates, _, _, counters = self.build(
            [self.current_fact("OTHER", duration_days="365", freeze="30", price="12990")],
            self.decision(),
        )
        self.assertEqual(builder.template_variant(templates[0]), self.decision().variant)
        self.assertEqual(counters["template_canonicalization"]["configured_source_contract_absent"], 1)

    def read_config(self, flag):
        row = {
            "canonical_name": "Тестовый абонемент",
            "branches_access": "Продажа",
            "price": "12990",
            "duration": "12",
            "visits": "",
            "freeze": "30",
            "source_contract_id": "SOURCE",
            "decision_basis": "accepted_june_delivery",
            "review_status": "accepted_delivery_preserved",
            "note": "test",
        }
        if flag is not None:
            row["allow_historical_variant"] = flag
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "decisions.csv"
            with path.open("w", encoding="utf-8", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(row))
                writer.writeheader()
                writer.writerow(row)
            return next(iter(builder.read_template_canonicalizations(path).values()))

    def test_historical_flag_is_optional_and_strict(self) -> None:
        for flag, expected in ((None, False), ("", False), ("0", False), ("1", True)):
            with self.subTest(flag=flag):
                self.assertIs(self.read_config(flag).allow_historical_variant, expected)
        for flag in ("true", "false", "yes", "2", "1.0"):
            with self.subTest(flag=flag):
                with self.assertRaisesRegex(ValueError, "invalid allow_historical_variant"):
                    self.read_config(flag)


if __name__ == "__main__":
    unittest.main()
