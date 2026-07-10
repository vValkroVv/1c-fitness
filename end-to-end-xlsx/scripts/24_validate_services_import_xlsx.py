#!/usr/bin/env python3
"""Validate generated Fitbase services import XLSX files."""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from pathlib import Path
from typing import Any

from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parents[1]
DATE_STAMP = "20260630"
CLIENT_HEADERS = [
    "service_id",
    "client_id",
    "phone",
    "client_fio",
    "service_name",
    "create_date",
    "payment_date",
    "activation_date",
    "end_date",
    "count",
    "visits_left",
    "price",
    "amount_of_payment",
    "payment_left",
    "type_of_payment",
    "manager",
    "филиал",
]
ALLOWED_BRANCHES = {
    "Фитнес Империя (Гоголевский)",
    "Фитнес Империя (Промышленная)",
    "Фитнес Империя (Ровио)",
    "Фитнес Империя (Столица)",
}
TEMPLATE_HEADERS = [
    "name",
    "price",
    "duration",
    "visits",
    "do_enter",
    "first_visit_activation",
    "archive",
    "category",
    "legal_entity",
]


def as_abs(path: str | Path) -> Path:
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


def iter_data_rows(path: Path, width: int) -> tuple[list[Any], list[tuple[Any, ...]]]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    rows_iter = ws.iter_rows(min_row=1, values_only=True)
    headers = list(next(rows_iter)[:width])
    next(rows_iter, None)
    rows = [tuple(row[:width]) for row in rows_iter if any(value not in (None, "") for value in row[:width])]
    wb.close()
    return headers, rows


def read_service_names(path: Path) -> list[str]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    names = [str(row[0] or "").strip() for row in ws.iter_rows(values_only=True) if str(row[0] or "").strip()]
    wb.close()
    return names


def read_source_client_ids(path: Path) -> set[str]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    headers = list(next(ws.iter_rows(min_row=1, max_row=1, values_only=True)))
    client_col = headers.index("client_id")
    ids = {
        str(row[client_col]).strip()
        for row in ws.iter_rows(min_row=3, values_only=True)
        if row[client_col] not in (None, "")
    }
    wb.close()
    return ids


def blank(value: Any) -> bool:
    return value is None or value == ""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-output-dir", default="work/20260630/owner")
    parser.add_argument("--output-dir", default="work/20260630/imports")
    parser.add_argument("--date-stamp", default=DATE_STAMP)
    parser.add_argument("--services-list", default="templates/services_required.xlsx")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_output_dir = as_abs(args.source_output_dir)
    output_dir = as_abs(args.output_dir)
    source_clients_xlsx = source_output_dir / f"fitbase_active_clients_import_zayavki_{args.date_stamp}_all_funnels.xlsx"
    client_xlsx = output_dir / f"fitbase_import_uslugi_clientov_{args.date_stamp}.xlsx"
    template_xlsx = output_dir / f"fitbase_import_shablony_uslug_{args.date_stamp}.xlsx"
    coverage_path = output_dir / "reports" / "services_coverage_report.csv"

    service_names = read_service_names(as_abs(args.services_list))
    source_client_ids = read_source_client_ids(source_clients_xlsx)
    client_headers, client_rows = iter_data_rows(client_xlsx, len(CLIENT_HEADERS))
    template_headers, template_rows = iter_data_rows(template_xlsx, len(TEMPLATE_HEADERS))

    errors: list[str] = []
    warnings: list[str] = []
    if client_headers != CLIENT_HEADERS:
        errors.append(f"client headers mismatch: {client_headers}")
    if template_headers != TEMPLATE_HEADERS:
        errors.append(f"template headers mismatch: {template_headers}")

    allowed_services = set(service_names)
    template_names = [str(row[0]).strip() for row in template_rows]
    if template_names != service_names:
        errors.append("template service list does not exactly match required 51 services in order")

    client_service_names = {str(row[4]).strip() for row in client_rows}
    outside_services = client_service_names - allowed_services
    if outside_services:
        errors.append(f"client rows outside required service list: {len(outside_services)}")

    client_ids = {str(row[1]).strip() for row in client_rows}
    outside_clients = client_ids - source_client_ids
    if outside_clients:
        warnings.append(f"client rows outside final import_zayavki: {len(outside_clients)}")

    service_ids = [str(row[0]).strip() for row in client_rows]
    duplicated_service_ids = [item for item, count in Counter(service_ids).items() if item and count > 1]
    if duplicated_service_ids:
        errors.append(f"duplicate service_id values: {len(duplicated_service_ids)}")

    required_indexes = {
        "service_id": 0,
        "client_id": 1,
        "client_fio": 3,
        "service_name": 4,
        "create_date": 5,
        "payment_date": 6,
        "price": 11,
        "amount_of_payment": 12,
        "payment_left": 13,
        "manager": 15,
        "филиал": 16,
    }
    blanks = Counter()
    for row in client_rows:
        for field, idx in required_indexes.items():
            if blank(row[idx]):
                blanks[field] += 1
    if blanks:
        errors.append(f"required blanks: {dict(blanks)}")

    payment_type_counts = Counter(str(row[14] or "blank") for row in client_rows)
    branch_counts = Counter(str(row[16] or "blank") for row in client_rows)
    invalid_branches = sorted(branch for branch in branch_counts if branch not in ALLOWED_BRANCHES)
    if invalid_branches:
        errors.append(f"invalid branch values: {invalid_branches}")
    blank_payment_positive = 0
    for row in client_rows:
        if row[14] in (None, "") and (row[11] or 0) > 0:
            blank_payment_positive += 1
    if blank_payment_positive:
        warnings.append(f"positive-price rows with blank payment type: {blank_payment_positive}")

    coverage_missing_selected = []
    if coverage_path.exists():
        with coverage_path.open("r", encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                if int(row.get("selected_rows") or 0) == 0:
                    coverage_missing_selected.append(row.get("service_name", ""))
    if coverage_missing_selected:
        warnings.append(f"services without client rows, template only: {len(coverage_missing_selected)}")

    report = [
        "# Services import XLSX validation",
        "",
        f"- client rows: {len(client_rows)}",
        f"- template rows: {len(template_rows)}",
        f"- required services: {len(service_names)}",
        f"- services represented in client rows: {len(client_service_names)}",
        f"- source final clients: {len(source_client_ids)}",
        f"- row clients: {len(client_ids)}",
        f"- duplicate service_id values: {len(duplicated_service_ids)}",
        f"- payment types: {dict(payment_type_counts)}",
        f"- branches: {dict(branch_counts)}",
        f"- template-only services: {len(coverage_missing_selected)}",
        f"- status: {'PASS' if not errors else 'FAIL'}",
        "",
        "## Errors",
        "",
    ]
    report.extend(f"- {item}" for item in errors)
    if not errors:
        report.append("- none")
    report.extend(["", "## Warnings", ""])
    report.extend(f"- {item}" for item in warnings)
    if not warnings:
        report.append("- none")

    reports_dir = output_dir / "reports"
    reports_dir.mkdir(parents=True, exist_ok=True)
    (reports_dir / "services_validation_report.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    print("\n".join(report))
    return 1 if errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
