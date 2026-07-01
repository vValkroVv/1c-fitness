#!/usr/bin/env python3
"""Build a current-final report for price=0 direct rows linked to refund docs."""

from __future__ import annotations

import csv
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOG_PATH = ROOT / "logs/new-changes/prolem_2/70_zero_direct_refund_block_wide_probe.txt"
AUDIT_CSV = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_payment_type_kept_audit.csv"
)
ROWS_CSV = ROOT / "output/20251115_0800_fix_owner_new_import/staging/membership_import_rows.csv"
OUT_DETAIL = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_audit.csv"
)
OUT_SUMMARY = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_summary.csv"
)
OUT_APPLIED = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_applied_overrides.csv"
)
OUT_APPLIED_SUMMARY = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_applied_overrides_summary.csv"
)

REFUND_HEADER = [
    "document_number",
    "client_id",
    "effective_client_fio",
    "subscription_name",
    "product_class",
    "sale_datetime",
    "start_date",
    "end_date",
    "is_active_on_cutoff",
    "matched_payment_amount",
    "matched_payment_method",
    "matched_payment_operation",
    "sale_doc_number",
    "sale_doc_ref",
    "refund_number",
    "refund_ref",
    "refund_datetime",
    "refund_posted",
    "refund_marked",
    "refund_sale_match_column",
    "refund_amount_548",
    "refund_amount_549",
    "refund_comment_551",
    "refund_text_5909",
    "refund_text_7770",
]


def read_csv_dicts(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def parse_refund_log() -> list[dict[str, str]]:
    text = LOG_PATH.read_text(encoding="utf-8-sig", errors="replace").replace("\x00", "")
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    header_line = "|".join(REFUND_HEADER)
    try:
        header_index = lines.index(header_line)
    except ValueError as exc:
        raise RuntimeError(f"Refund detail section not found in {LOG_PATH}") from exc

    rows: list[dict[str, str]] = []
    for line in lines[header_index + 2 :]:
        parts = line.split("|")
        if len(parts) != len(REFUND_HEADER):
            continue
        rows.append(dict(zip(REFUND_HEADER, parts, strict=True)))
    return rows


def money_sum(values: list[str]) -> str:
    total = sum((Decimal(value or "0") for value in values), Decimal("0"))
    return f"{total:.2f}"


def decimal_value(value: str) -> Decimal:
    if value in (None, ""):
        return Decimal("0")
    return Decimal(str(value).strip().replace(",", "."))


def main() -> None:
    audit_rows = read_csv_dicts(AUDIT_CSV)
    row_by_contract = {row["contract_id"]: row for row in read_csv_dicts(ROWS_CSV)}

    refund_rows = parse_refund_log()
    refund_by_contract: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in refund_rows:
        refund_by_contract[row["document_number"]].append(row)

    detail_rows: list[dict[str, str]] = []
    for row in audit_rows:
        contract_id = row["contract_id"]
        refunds = refund_by_contract.get(contract_id, [])
        current_row = row_by_contract.get(contract_id, {})
        staged_refund_count = int(decimal_value(current_row.get("_document131_refund_count", "0")))
        staged_posted_refund_count = int(
            decimal_value(current_row.get("_document131_posted_unmarked_refund_count", "0"))
        )
        posted_unmarked = [
            refund for refund in refunds if refund["refund_posted"] == "0x01" and refund["refund_marked"] == "0x00"
        ]
        marked_or_unposted = [
            refund for refund in refunds if not (refund["refund_posted"] == "0x01" and refund["refund_marked"] == "0x00")
        ]
        has_refunds = bool(refunds) or staged_refund_count > 0
        detail_rows.append(
            {
                **row,
                "has_document131_refund": "1" if has_refunds else "0",
                "document131_refund_count": str(max(len(refunds), staged_refund_count)),
                "document131_posted_unmarked_refund_count": str(
                    max(len(posted_unmarked), staged_posted_refund_count)
                ),
                "document131_marked_or_unposted_refund_count": str(len(marked_or_unposted)),
                "document131_refund_numbers": ";".join(refund["refund_number"] for refund in refunds),
                "document131_refund_refs": ";".join(refund["refund_ref"] for refund in refunds),
                "document131_refund_datetimes": ";".join(refund["refund_datetime"] for refund in refunds),
                "document131_refund_amount_548_sum": money_sum(
                    [refund["refund_amount_548"] for refund in posted_unmarked]
                ),
                "document131_refund_amount_549_sum": money_sum(
                    [refund["refund_amount_549"] for refund in posted_unmarked]
                ),
                "document131_refund_match_columns": ";".join(
                    sorted({refund["refund_sale_match_column"] for refund in refunds})
                ),
            }
        )

    OUT_DETAIL.parent.mkdir(parents=True, exist_ok=True)
    with OUT_DETAIL.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(detail_rows[0].keys()))
        writer.writeheader()
        writer.writerows(detail_rows)

    summary_rows: list[dict[str, str]] = []
    for (risk_group, active, has_refund), count in sorted(
        Counter(
            (
                row["risk_group"],
                row["is_active_on_cutoff"],
                row["has_document131_refund"],
            )
            for row in detail_rows
        ).items()
    ):
        summary_rows.append(
            {
                "risk_group": risk_group,
                "is_active_on_cutoff": active,
                "has_document131_refund": has_refund,
                "rows_count": str(count),
                "posted_unmarked_refund_rows": str(
                    sum(
                        detail["document131_posted_unmarked_refund_count"] != "0"
                        for detail in detail_rows
                        if detail["risk_group"] == risk_group
                        and detail["is_active_on_cutoff"] == active
                        and detail["has_document131_refund"] == has_refund
                    )
                ),
            }
        )

    with OUT_SUMMARY.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "risk_group",
                "is_active_on_cutoff",
                "has_document131_refund",
                "rows_count",
                "posted_unmarked_refund_rows",
            ],
        )
        writer.writeheader()
        writer.writerows(summary_rows)

    applied_rows = [
        row
        for row in row_by_contract.values()
        if row.get("_business_override")
        in {
            "business_historical_document131_refund_zero_direct_blank_payment",
            "business_direct_free_site_week_sale_line_zero_blank_payment",
        }
    ]
    applied_headers = [
        "contract_id",
        "client_id",
        "client_fio",
        "contract_name",
        "payment_date",
        "activation_date",
        "end_date",
        "price",
        "amount_of_payments",
        "payment_left",
        "type_of_payment",
        "_payment_method_raw",
        "_payment_match_source",
        "_business_override",
        "_membership_sale_line_amount",
        "_membership_sale_line_count",
        "_document131_refund_count",
        "_document131_posted_unmarked_refund_count",
    ]
    with OUT_APPLIED.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=applied_headers)
        writer.writeheader()
        writer.writerows({header: row.get(header, "") for header in applied_headers} for row in applied_rows)

    applied_summary_rows = [
        {
            "business_override": override,
            "rows_count": str(count),
        }
        for override, count in sorted(Counter(row["_business_override"] for row in applied_rows).items())
    ]
    with OUT_APPLIED_SUMMARY.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=["business_override", "rows_count"])
        writer.writeheader()
        writer.writerows(applied_summary_rows)

    final_refund_docs = {row["contract_id"] for row in detail_rows if row["has_document131_refund"] == "1"}
    posted_unmarked_docs = {
        row["contract_id"] for row in detail_rows if row["document131_posted_unmarked_refund_count"] != "0"
    }
    print(OUT_DETAIL)
    print(OUT_SUMMARY)
    print(OUT_APPLIED)
    print(OUT_APPLIED_SUMMARY)
    print(
        f"final_rows={len(audit_rows)} "
        f"with_document131_refund={len(final_refund_docs)} "
        f"with_posted_unmarked_refund={len(posted_unmarked_docs)} "
        f"applied_overrides={len(applied_rows)}"
    )


if __name__ == "__main__":
    main()
