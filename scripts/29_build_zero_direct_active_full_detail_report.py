#!/usr/bin/env python3
"""Build a clean CSV report for active full price=0 rows with direct payment."""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_LOG = ROOT / "logs/new-changes/prolem_2/68_zero_direct_active_full_scale.txt"
OUT_CSV = (
    ROOT
    / "output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_active_full_44_detail.csv"
)

SOURCE_HEADER = [
    "document_number",
    "client_id",
    "effective_client_fio",
    "subscription_name",
    "sale_datetime",
    "start_date",
    "end_date",
    "status_name",
    "matched_payment_amount",
    "matched_payment_method",
    "visit_docs",
    "sale_line_sum",
    "is_selected_subscription",
    "selected_subscription_name",
]

OUT_HEADER = [
    "contract_id",
    "client_id",
    "client_fio",
    "contract_name",
    "sale_datetime",
    "start_date",
    "end_date",
    "status",
    "matched_payment_amount",
    "matched_payment_method",
    "visit_docs",
    "sale_line_sum",
    "is_selected_subscription",
    "selected_subscription_name",
    "decision_needed",
]


def read_detail_rows() -> list[dict[str, str]]:
    text = SOURCE_LOG.read_text(encoding="utf-8-sig", errors="replace").replace("\x00", "")
    lines = [line.strip() for line in text.splitlines() if line.strip()]

    try:
        header_index = lines.index("|".join(SOURCE_HEADER))
    except ValueError as exc:
        raise RuntimeError(f"Detail header not found in {SOURCE_LOG}") from exc

    rows: list[dict[str, str]] = []
    for line in lines[header_index + 2 :]:
        if set(line) <= {"-", "|"}:
            continue
        parts = line.split("|")
        if len(parts) != len(SOURCE_HEADER):
            continue
        source = dict(zip(SOURCE_HEADER, parts, strict=True))
        rows.append(
            {
                "contract_id": source["document_number"],
                "client_id": source["client_id"],
                "client_fio": source["effective_client_fio"],
                "contract_name": source["subscription_name"],
                "sale_datetime": source["sale_datetime"],
                "start_date": source["start_date"],
                "end_date": source["end_date"],
                "status": source["status_name"],
                "matched_payment_amount": source["matched_payment_amount"],
                "matched_payment_method": source["matched_payment_method"],
                "visit_docs": source["visit_docs"],
                "sale_line_sum": source["sale_line_sum"],
                "is_selected_subscription": source["is_selected_subscription"],
                "selected_subscription_name": source["selected_subscription_name"],
                "decision_needed": "restore_price_from_sale_line_sum_or_confirm_keep_zero",
            }
        )

    if len(rows) != 44:
        raise RuntimeError(f"Expected 44 active rows, got {len(rows)} from {SOURCE_LOG}")

    with_visits = sum(int(row["visit_docs"]) > 0 for row in rows)
    positive_sales = sum(float(row["sale_line_sum"]) > 0 for row in rows)
    positive_payments = sum(float(row["matched_payment_amount"]) > 0 for row in rows)
    selected = sum(row["is_selected_subscription"] == "1" for row in rows)
    if (with_visits, positive_sales, positive_payments, selected) != (43, 44, 44, 43):
        raise RuntimeError(
            "Unexpected active summary: "
            f"with_visits={with_visits}, positive_sales={positive_sales}, "
            f"positive_payments={positive_payments}, selected={selected}"
        )

    return rows


def main() -> None:
    rows = read_detail_rows()
    OUT_CSV.parent.mkdir(parents=True, exist_ok=True)
    with OUT_CSV.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUT_HEADER)
        writer.writeheader()
        writer.writerows(rows)

    print(OUT_CSV)
    print("rows=44 with_visits=43 positive_sales=44 positive_payments=44 selected=43")


if __name__ == "__main__":
    main()
