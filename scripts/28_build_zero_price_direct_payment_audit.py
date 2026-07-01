#!/usr/bin/env python3
"""Build audit CSVs for price=0 rows with direct matched payment kept as type."""

from __future__ import annotations

import csv
import importlib.util
import sys
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "output/20251115_0800_fix_owner_new_import/reports"
ROWS_CSV = ROOT / "output/20251115_0800_fix_owner_new_import/staging/membership_import_rows.csv"
FACTS_TSV = ROOT / "output/20251115_0800_fix_owner_new_import/staging/membership_import_facts.tsv"
DETAIL_CSV = OUT_DIR / "zero_price_direct_payment_type_kept_audit.csv"
SUMMARY_CSV = OUT_DIR / "zero_price_direct_payment_type_kept_summary.csv"


def load_membership_builder():
    spec = importlib.util.spec_from_file_location(
        "membership_builder", ROOT / "scripts/19_build_membership_import_xlsx.py"
    )
    if spec is None or spec.loader is None:
        raise RuntimeError("Cannot load membership builder")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def zero_direct_group(row: dict[str, str], fact: dict[str, str]) -> str:
    product_class = fact.get("product_class", "")
    name = (row.get("contract_name") or "").lower()
    start_date = fact.get("start_date", "")
    end_date = fact.get("end_date", "")
    active = fact.get("is_active_on_cutoff") == "1"

    if product_class == "trial_or_guest":
        if "недел" in name or "2 недели" in name:
            return "trial_week_direct_zero"
        return "trial_other_direct_zero"
    if product_class == "full_subscription" and start_date == "2001-01-01" and end_date == "2001-01-01":
        return "full_service_dates_2001"
    if product_class == "full_subscription" and active:
        return "full_active_zero_direct"
    if product_class == "full_subscription":
        return "full_finished_normal_dates_zero_direct"
    return product_class or "unknown_review_required"


def main() -> None:
    builder = load_membership_builder()
    facts = builder.read_facts(FACTS_TSV)
    fact_by_doc = {fact["document_number"]: fact for fact in facts}

    detail_rows: list[dict[str, Any]] = []
    for row in read_rows(ROWS_CSV):
        if row.get("price") != "0":
            continue
        if not row.get("type_of_payment"):
            continue
        if not (row.get("_payment_match_source") or "").startswith("direct"):
            continue
        fact = fact_by_doc.get(row["contract_id"], {})
        detail_rows.append(
            {
                "risk_group": zero_direct_group(row, fact),
                "contract_id": row.get("contract_id", ""),
                "client_id": row.get("client_id", ""),
                "client_fio": row.get("client_fio", ""),
                "contract_name": row.get("contract_name", ""),
                "product_class": fact.get("product_class", row.get("_product_class", "")),
                "is_active_on_cutoff": fact.get("is_active_on_cutoff", ""),
                "is_finished_before_cutoff": fact.get("is_finished_before_cutoff", ""),
                "status": fact.get("status", "") or "blank",
                "sale_datetime": fact.get("sale_datetime", ""),
                "start_date": fact.get("start_date", row.get("activation_date", "")),
                "end_date": fact.get("end_date", row.get("end_date", "")),
                "duration_days": fact.get("duration_days", ""),
                "price": row.get("price", ""),
                "amount_of_payments": row.get("amount_of_payments", ""),
                "payment_left": row.get("payment_left", ""),
                "type_of_payment": row.get("type_of_payment", ""),
                "matched_payment_amount": fact.get("matched_payment_amount", ""),
                "matched_payment_method": fact.get("matched_payment_method", row.get("_payment_method_raw", "")),
                "matched_payment_operation": fact.get("matched_payment_operation", ""),
                "matched_payment_ref": fact.get("matched_payment_ref", ""),
                "matched_payment_match_source": fact.get("matched_payment_match_source", row.get("_payment_match_source", "")),
                "rg_price": fact.get("rg_price", ""),
                "rg_paid_candidate": fact.get("rg_paid_candidate", ""),
                "rg_payment_count_candidate": fact.get("rg_payment_count_candidate", ""),
            }
        )

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    detail_headers = list(detail_rows[0].keys()) if detail_rows else []
    with DETAIL_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=detail_headers)
        writer.writeheader()
        writer.writerows(detail_rows)

    group_counts = Counter(row["risk_group"] for row in detail_rows)
    active_counts = Counter(row["risk_group"] for row in detail_rows if row["is_active_on_cutoff"] == "1")
    summary_rows = [
        {
            "risk_group": group,
            "rows_count": group_counts[group],
            "active_rows_count": active_counts[group],
        }
        for group in sorted(group_counts)
    ]
    with SUMMARY_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["risk_group", "rows_count", "active_rows_count"])
        writer.writeheader()
        writer.writerows(summary_rows)

    print(DETAIL_CSV)
    print(SUMMARY_CSV)


if __name__ == "__main__":
    main()
