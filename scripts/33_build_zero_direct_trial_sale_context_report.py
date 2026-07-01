#!/usr/bin/env python3
"""Build a compact report for zero-price weekly/trial rows with direct payments."""

from __future__ import annotations

import csv
from collections import Counter
from decimal import Decimal, InvalidOperation
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT / "logs/new-changes/prolem_2/71_zero_direct_trial_sale_context.txt"
ROWS_CSV = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/staging/membership_import_rows.csv"
)
OUT_DETAIL = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_audit.csv"
)
OUT_SUMMARY = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_summary.csv"
)

SECTIONS = [
    "01 target facts",
    "02 target sale docs",
    "03 all Document154 sale lines in target sale docs",
    "04 payments linked to target sale docs",
    "05 same-client memberships near target dates",
]


def read_sql_log() -> str:
    return LOG_PATH.read_bytes().decode("utf-8-sig", "replace").replace("\x00", "")


def split_sections(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for index, header in enumerate(SECTIONS):
        start = text.find(header)
        if start == -1:
            raise RuntimeError(f"Section {header!r} not found in {LOG_PATH}")
        end = text.find(SECTIONS[index + 1], start) if index + 1 < len(SECTIONS) else len(text)
        result[header] = text[start + len(header) : end].strip("\n")
    return result


def parse_section(section_text: str) -> list[dict[str, str]]:
    lines = [line.rstrip("\r") for line in section_text.splitlines() if line.strip()]
    lines = [line for line in lines if not line.startswith("(") and not line.startswith("Changed database")]
    if not lines:
        return []

    headers = [part.strip() for part in lines[0].split("|")]
    rows: list[dict[str, str]] = []
    for line in lines[1:]:
        parts = [part.strip() for part in line.split("|")]
        if all(part and set(part) <= {"-", " "} for part in parts):
            continue
        if len(parts) != len(headers):
            continue
        rows.append(dict(zip(headers, parts, strict=True)))
    return rows


def read_csv_dicts(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def dec(value: str) -> Decimal:
    value = (value or "").strip()
    if value in {"", "NULL"}:
        return Decimal("0")
    try:
        return Decimal(value)
    except InvalidOperation:
        return Decimal(value.replace(",", "."))


def money(value: Decimal) -> str:
    return f"{value:.2f}"


def join_unique(values: list[str]) -> str:
    cleaned = [value for value in values if value and value != "NULL"]
    return "; ".join(dict.fromkeys(cleaned))


def conclusion_for(row: dict[str, str], target_line_sum: Decimal, other_products: str, has_refund: bool) -> tuple[str, str]:
    name = row["subscription_name"]
    if name == "Абонемент НЕДЕЛЯ САЙТ" and target_line_sum == 0:
        return (
            "free_site_week_confirmed_by_1c_sale_line",
            "clear_type_of_payment_for_site_week_after_business_confirmation",
        )
    if "Неделя Фитнес" in name and target_line_sum == 0:
        return (
            "target_week_line_zero_but_payment_is_on_doplata",
            "business_review_before_mass_rule",
        )
    if has_refund:
        return (
            "not_free_week_target_line_positive_document131_refund_exists",
            "handle_by_document131_refund_rule",
        )
    return (
        "review_required",
        "manual_review",
    )


def main() -> None:
    parsed = {name: parse_section(text) for name, text in split_sections(read_sql_log()).items()}
    facts = {row["document_number"]: row for row in parsed["01 target facts"]}
    if len(facts) != 7:
        raise RuntimeError(f"Expected 7 target facts, got {len(facts)}")

    sale_lines_by_contract: dict[str, list[dict[str, str]]] = {contract_id: [] for contract_id in facts}
    for row in parsed["03 all Document154 sale lines in target sale docs"]:
        sale_lines_by_contract.setdefault(row["target_contract_id"], []).append(row)

    payments_by_contract: dict[str, list[dict[str, str]]] = {contract_id: [] for contract_id in facts}
    for row in parsed["04 payments linked to target sale docs"]:
        payments_by_contract.setdefault(row["target_contract_id"], []).append(row)

    nearby_by_contract: dict[str, list[dict[str, str]]] = {contract_id: [] for contract_id in facts}
    for row in parsed["05 same-client memberships near target dates"]:
        nearby_by_contract.setdefault(row["target_contract_id"], []).append(row)

    current_rows_by_contract = {row["contract_id"]: row for row in read_csv_dicts(ROWS_CSV)}

    detail_rows: list[dict[str, str]] = []
    for contract_id in sorted(facts):
        fact = facts[contract_id]
        sale_lines = sale_lines_by_contract.get(contract_id, [])
        target_lines = [row for row in sale_lines if row["is_target_membership_line"] == "1"]
        other_lines = [row for row in sale_lines if row["is_target_membership_line"] != "1"]
        payments = payments_by_contract.get(contract_id, [])
        nearby = [row for row in nearby_by_contract.get(contract_id, []) if row["document_number"] != contract_id]
        nearby_positive = [
            row
            for row in nearby
            if dec(row["rg_price"]) > 0 or dec(row["matched_payment_amount"]) > 0
        ]
        current_row = current_rows_by_contract.get(contract_id, {})
        has_refund = dec(current_row.get("_document131_posted_unmarked_refund_count", "0")) > 0

        target_line_sum = sum((dec(row["amount_1160"]) for row in target_lines), Decimal("0"))
        other_line_sum = sum((dec(row["amount_1160"]) for row in other_lines), Decimal("0"))
        payment_line_sum = sum((dec(row["payment_line_amount"]) for row in payments), Decimal("0"))
        other_products = join_unique(
            [
                (
                    f"{row['line_product']} -> {row['linked_membership_number']}"
                    if row.get("linked_membership_number") not in {"", "NULL"}
                    else row["line_product"]
                )
                for row in other_lines
            ]
        )
        conclusion, proposed_action = conclusion_for(fact, target_line_sum, other_products, has_refund)

        detail_rows.append(
            {
                "contract_id": contract_id,
                "client_id": fact["client_id"],
                "client_fio": fact["effective_client_fio"],
                "contract_name": fact["subscription_name"],
                "status": "" if fact["status"] == "NULL" else fact["status"],
                "sale_datetime": fact["sale_datetime"],
                "start_date": fact["start_date"],
                "end_date": fact["end_date"],
                "matched_payment_amount": money(dec(fact["matched_payment_amount"])),
                "matched_payment_method": fact["matched_payment_method"],
                "target_sale_line_amount": money(target_line_sum),
                "target_sale_line_count": str(len(target_lines)),
                "other_sale_line_count": str(len(other_lines)),
                "other_sale_line_amount": money(other_line_sum),
                "other_sale_line_products": other_products,
                "payment_line_amount_sum": money(payment_line_sum),
                "payment_numbers": join_unique([row["payment_number"] for row in payments]),
                "payment_methods": join_unique([row["payment_method"] for row in payments]),
                "nearby_other_memberships_count": str(len(nearby)),
                "nearby_positive_other_memberships_count": str(len(nearby_positive)),
                "nearby_positive_other_memberships": join_unique(
                    [f"{row['document_number']} {row['subscription_name']}" for row in nearby_positive]
                ),
                "has_document131_refund": "1" if has_refund else "0",
                "document131_refund_numbers": "",
                "conclusion": conclusion,
                "proposed_action": proposed_action,
            }
        )

    OUT_DETAIL.parent.mkdir(parents=True, exist_ok=True)
    with OUT_DETAIL.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(detail_rows[0].keys()))
        writer.writeheader()
        writer.writerows(detail_rows)

    summary_rows = [
        {"conclusion": conclusion, "rows_count": str(count)}
        for conclusion, count in sorted(Counter(row["conclusion"] for row in detail_rows).items())
    ]
    with OUT_SUMMARY.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["conclusion", "rows_count"])
        writer.writeheader()
        writer.writerows(summary_rows)

    print(OUT_DETAIL)
    print(OUT_SUMMARY)
    print(f"trial_week_rows={len(detail_rows)}")


if __name__ == "__main__":
    main()
