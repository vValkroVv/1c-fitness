#!/usr/bin/env python3
"""Assemble the six clean XLSX files and three separate problem XLSX files."""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.utils import get_column_letter


ROOT = Path(__file__).resolve().parents[1]


def as_abs(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def one_match(directory: Path, pattern: str) -> Path:
    matches = sorted(directory.glob(pattern))
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one {pattern!r} in {directory}, found {len(matches)}"
        )
    return matches[0]


def read_problem_contracts(path: Path) -> set[str]:
    workbook = load_workbook(path, read_only=True, data_only=True)
    worksheet = workbook.active
    headers = [
        str(value or "")
        for value in next(worksheet.iter_rows(min_row=1, max_row=1, values_only=True))
    ]
    if "contract_id" not in headers:
        workbook.close()
        raise RuntimeError(f"No contract_id column in {path}")
    contract_index = headers.index("contract_id")
    contracts = {
        str(row[contract_index] or "").strip()
        for row in worksheet.iter_rows(min_row=2, values_only=True)
        if str(row[contract_index] or "").strip()
    }
    workbook.close()
    return contracts


def filter_membership_workbook(
    source: Path,
    destination: Path,
    problem_ids: set[str],
    template_path: Path,
) -> int:
    """Rewrite the large workbook once while excluding problem contracts.

    Calling Worksheet.delete_rows for 223 scattered rows repeatedly shifts
    millions of cells.  A streaming source plus the original template keeps
    the same workbook structure and makes runtime linear in the row count.
    """

    source_workbook = load_workbook(source, read_only=True, data_only=False)
    source_sheet = source_workbook.active
    headers = [
        str(value or "")
        for value in next(
            source_sheet.iter_rows(min_row=1, max_row=1, values_only=True)
        )
    ]
    if "contract_id" not in headers:
        source_workbook.close()
        raise RuntimeError(f"No contract_id column in {source}")
    contract_index = headers.index("contract_id")

    target_workbook = load_workbook(template_path)
    target_sheet = target_workbook.active
    width = len(headers)
    if target_sheet.max_column > width:
        target_sheet.delete_cols(width + 1, target_sheet.max_column - width)
    number_formats = [
        target_sheet.cell(3, column).number_format for column in range(1, width + 1)
    ]
    if target_sheet.max_row >= 3:
        target_sheet.delete_rows(3, target_sheet.max_row - 2)

    source_russian_headers = next(
        source_sheet.iter_rows(min_row=2, max_row=2, values_only=True)
    )
    for column, value in enumerate(headers, start=1):
        target_sheet.cell(1, column).value = value
        target_sheet.cell(2, column).value = source_russian_headers[column - 1]

    date_headers = {"create_date", "payment_date", "activation_date", "end_date"}
    money_headers = {"price", "amount_of_payments", "payment_left"}
    format_columns: dict[int, str] = {}
    for column, header in enumerate(headers, start=1):
        if header in date_headers:
            format_columns[column] = "yyyy-mm-dd"
        elif header in money_headers:
            format_columns[column] = "#,##0.00"
        elif number_formats[column - 1] and number_formats[column - 1] != "General":
            format_columns[column] = number_formats[column - 1]

    found: set[str] = set()
    removed = 0
    target_row = 2
    for values in source_sheet.iter_rows(min_row=3, values_only=True):
        contract_id = str(values[contract_index] or "").strip()
        if contract_id in problem_ids:
            found.add(contract_id)
            removed += 1
            continue
        target_sheet.append(list(values[:width]))
        target_row += 1
        for column, number_format in format_columns.items():
            target_sheet.cell(target_row, column).number_format = number_format

    missing = sorted(problem_ids - found)
    if missing:
        source_workbook.close()
        target_workbook.close()
        raise RuntimeError(
            f"Problem contract_id values not found in full membership workbook: {missing[:10]}"
        )
    if removed != len(problem_ids):
        source_workbook.close()
        target_workbook.close()
        raise RuntimeError(
            "A problem contract_id occurs more than once in the full membership workbook: "
            f"rows={removed}, unique={len(problem_ids)}"
        )

    target_sheet.freeze_panes = "A3"
    for column in range(1, width + 1):
        letter = get_column_letter(column)
        current_width = target_sheet.column_dimensions[letter].width or 12
        target_sheet.column_dimensions[letter].width = min(max(current_width, 12), 34)
    destination.parent.mkdir(parents=True, exist_ok=True)
    target_workbook.save(destination)
    source_workbook.close()
    target_workbook.close()
    return removed


def build(args: argparse.Namespace) -> None:
    owner_dir = as_abs(args.owner_dir)
    imports_dir = as_abs(args.imports_dir)
    output_dir = as_abs(args.output_dir)
    report_path = as_abs(args.report)
    membership_template = as_abs(args.membership_template)
    date_stamp = args.date_stamp

    output_dir.mkdir(parents=True, exist_ok=True)
    for stale in output_dir.glob("*.xlsx"):
        stale.unlink()

    main_name = f"fitbase_active_clients_import_zayavki_{date_stamp}_all_funnels.xlsx"
    cards_name = f"fitbase_active_clients_plastic_cards_{date_stamp}_all_funnels.xlsx"
    membership_name = f"fitbase_import_abonementy_clientov_{date_stamp}.xlsx"
    membership_templates_name = f"fitbase_import_shablony_abonementov_{date_stamp}.xlsx"
    services_name = f"fitbase_import_uslugi_clientov_{date_stamp}.xlsx"
    service_templates_name = f"fitbase_import_shablony_uslug_{date_stamp}.xlsx"

    static_sources = {
        main_name: owner_dir / main_name,
        cards_name: owner_dir / cards_name,
        membership_templates_name: imports_dir / membership_templates_name,
        services_name: imports_dir / services_name,
        service_templates_name: imports_dir / service_templates_name,
    }
    for name, source in static_sources.items():
        if not source.is_file():
            raise FileNotFoundError(source)
        shutil.copy2(source, output_dir / name)

    problem_sources = [
        one_match(
            imports_dir, f"active_problem_1_no_payment_cash_*_cases_{date_stamp}.xlsx"
        ),
        one_match(
            imports_dir,
            f"active_problem_2_zero_price_direct_full_*_cases_{date_stamp}.xlsx",
        ),
        one_match(
            imports_dir,
            f"active_problem_3_non_named_payment_left_*_cases_{date_stamp}.xlsx",
        ),
    ]
    problem_sets = [read_problem_contracts(path) for path in problem_sources]
    problem_ids = set().union(*problem_sets)
    summed = sum(len(values) for values in problem_sets)
    if len(problem_ids) != summed:
        raise RuntimeError(
            f"A contract_id belongs to more than one problem group: summed={summed}, union={len(problem_ids)}"
        )

    for source in problem_sources:
        output_name = source.name.removeprefix("active_")
        shutil.copy2(source, output_dir / output_name)

    full_membership = imports_dir / membership_name
    if not full_membership.is_file():
        raise FileNotFoundError(full_membership)
    removed = filter_membership_workbook(
        full_membership,
        output_dir / membership_name,
        problem_ids,
        membership_template,
    )

    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        "\n".join(
            [
                "# Delivery build",
                "",
                f"- date stamp: `{date_stamp}`",
                f"- output: `{output_dir}`",
                "- clean XLSX: `6`",
                "- problem XLSX: `3`",
                f"- unique problem contract_id: `{len(problem_ids)}`",
                f"- rows removed from clean membership XLSX: `{removed}`",
                "",
                "## Problem groups",
                "",
                *[
                    f"- `{path.name}`: `{len(values)}`"
                    for path, values in zip(problem_sources, problem_sets, strict=True)
                ],
                "",
            ]
        ),
        encoding="utf-8",
    )
    print(f"delivery_dir={output_dir}")
    print(f"problem_contract_ids={len(problem_ids)}")
    print(f"membership_rows_removed={removed}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--owner-dir", required=True)
    parser.add_argument("--imports-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--date-stamp", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--membership-template", required=True)
    return parser.parse_args()


if __name__ == "__main__":
    build(parse_args())
