#!/usr/bin/env python3
"""Extract customer checked-file decisions for Part 2 reports."""

from __future__ import annotations

import argparse
import csv
import re
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path
from typing import Iterable

from openpyxl import load_workbook


ROOT = Path(__file__).resolve().parents[1]


def as_abs(path: str | Path) -> Path:
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


def cell_value(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, datetime):
        return value.date().isoformat()
    if isinstance(value, date):
        return value.isoformat()
    return str(value).strip()


def read_rows(path: Path, min_cols: int) -> list[list[str]]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    rows: list[list[str]] = []
    for row in ws.iter_rows(min_row=3, values_only=True):
        values = [cell_value(value) for value in row[:min_cols]]
        if any(values[:3]):
            rows.append(values)
    wb.close()
    return rows


def read_card_rows(path: Path) -> list[list[str]]:
    wb = load_workbook(path, read_only=True, data_only=True)
    ws = wb.active
    rows: list[list[str]] = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        values = [cell_value(value) for value in row[:4]]
        if any(values[:3]):
            rows.append(values)
    wb.close()
    return rows


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def normalize_fio(value: str) -> str:
    return " ".join((value or "").lower().split())


def normalize_phone_token(value: str) -> str:
    digits = re.sub(r"\D", "", value or "")
    if len(digits) == 11 and digits.startswith("8"):
        return "7" + digits[1:]
    if len(digits) == 10:
        return "7" + digits
    return digits


def normalize_phones(value: str) -> str:
    phones = []
    for part in (value or "").split(","):
        phone = normalize_phone_token(part)
        if phone and phone not in phones:
            phones.append(phone)
    return ",".join(sorted(phones))


def build_card_rule_map(detail_path: Path) -> dict[tuple[str, str], dict[str, str]]:
    rows = read_csv(detail_path)
    grouped: defaultdict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for row in rows:
        key = (normalize_fio(row.get("client_fio", "")), normalize_phones(row.get("phones", "")))
        if key[0] or key[1]:
            grouped[key].append(row)
    result: dict[tuple[str, str], dict[str, str]] = {}
    for key, items in grouped.items():
        selected = sorted(
            items,
            key=lambda row: (row.get("issue_date", ""), row.get("card_ref", "")),
            reverse=True,
        )[0]
        result[key] = selected
    return result


def classify_subscription_comment(comment: str) -> str:
    lowered = comment.lower()
    flags = []
    if "ошиб" in lowered or "невер" in lowered:
        flags.append("system_or_operator_error")
    if "владел" in lowered:
        flags.append("owner_change")
    if "модифик" in lowered:
        flags.append("modifier")
    if "удален" in lowered or "удаление" in lowered:
        flags.append("marked_for_deletion")
    if "одно действующее" in lowered:
        flags.append("single_active_confirmed")
    return ";".join(flags) or "comment_only"


def review(args: argparse.Namespace) -> None:
    checked_dir = as_abs(args.checked_dir)
    reports_dir = as_abs(args.reports_dir)
    reports_dir.mkdir(parents=True, exist_ok=True)

    sub_path = checked_dir / "fitbase_active_clients_import_zayavki_20260429__05_tolko_neskolko_abonementov(проверено).xlsx"
    phone_path = checked_dir / "fitbase_active_clients_import_zayavki_20260429__07_tolko_net_telefona(проверено).xlsx"
    card_path = checked_dir / "fitbase_active_clients_plastic_cards_20260429__02_tolko_neskolko_kart (проверено).xlsx"

    subscription_rows = []
    for values in read_rows(sub_path, 13):
        subscription_rows.append(
            {
                "client_id": values[0],
                "phone": values[1],
                "client_fio": values[2],
                "checked_sale_date": values[9] if len(values) > 9 else "",
                "checked_start_date": values[10] if len(values) > 10 else "",
                "checked_end_date": values[11] if len(values) > 11 else "",
                "comment": values[12] if len(values) > 12 else "",
                "decision_flags": classify_subscription_comment(values[12] if len(values) > 12 else ""),
            }
        )
    write_csv(
        reports_dir / "checked_subscription_decisions.csv",
        subscription_rows,
        [
            "client_id",
            "phone",
            "client_fio",
            "checked_sale_date",
            "checked_start_date",
            "checked_end_date",
            "comment",
            "decision_flags",
        ],
    )

    missing_phone_rows = []
    for values in read_rows(phone_path, 10):
        missing_phone_rows.append(
            {
                "client_id": values[0],
                "phone": values[1],
                "client_fio": values[2],
                "checked_phone_comment": values[9] if len(values) > 9 else "",
                "confirmed_missing_phone": "1" if (values[9] if len(values) > 9 else "").lower() == "нет" else "0",
            }
        )
    write_csv(
        reports_dir / "checked_missing_phone_confirmations.csv",
        missing_phone_rows,
        ["client_id", "phone", "client_fio", "checked_phone_comment", "confirmed_missing_phone"],
    )

    rule_map = build_card_rule_map(as_abs(args.previous_multiple_cards_detail))
    card_decision_rows = []
    for phone, fio, card_list, checked_selected in read_card_rows(card_path):
        key = (normalize_fio(fio), normalize_phones(phone))
        rule = rule_map.get(key, {})
        rule_selected = rule.get("plastic_card_number", "")
        if checked_selected:
            match_status = "matches_rule" if checked_selected == rule_selected else "differs_from_rule"
        else:
            match_status = "no_checked_selection"
        card_decision_rows.append(
            {
                "phone": phone,
                "client_fio": fio,
                "all_cards_from_checked_file": card_list,
                "checked_selected_card": checked_selected,
                "rule_selected_card": rule_selected,
                "rule_selected_card_ref": rule.get("card_ref", ""),
                "rule_selected_issue_date": rule.get("issue_date", ""),
                "selection_rule": "issue_date DESC, card_ref DESC",
                "match_status": match_status,
            }
        )
    write_csv(
        reports_dir / "checked_card_decisions.csv",
        card_decision_rows,
        [
            "phone",
            "client_fio",
            "all_cards_from_checked_file",
            "checked_selected_card",
            "rule_selected_card",
            "rule_selected_card_ref",
            "rule_selected_issue_date",
            "selection_rule",
            "match_status",
        ],
    )

    summary_lines = [
        "# Checked Files Review Summary",
        "",
        f"reviewed_at: `{datetime.now().isoformat(timespec='seconds')}`",
        "",
        "## Files",
        "",
        f"- `{sub_path.relative_to(ROOT)}`",
        f"- `{phone_path.relative_to(ROOT)}`",
        f"- `{card_path.relative_to(ROOT)}`",
        "",
        "## Counts",
        "",
        f"- subscription checked rows: `{len(subscription_rows)}`",
        f"- missing-phone checked rows: `{len(missing_phone_rows)}`",
        f"- card checked rows: `{len(card_decision_rows)}`",
        f"- card rows with checked selected card: `{sum(1 for row in card_decision_rows if row['checked_selected_card'])}`",
        f"- checked selected cards matching rule: `{sum(1 for row in card_decision_rows if row['match_status'] == 'matches_rule')}`",
        f"- checked selected cards differing from rule: `{sum(1 for row in card_decision_rows if row['match_status'] == 'differs_from_rule')}`",
        "",
        "## Decision",
        "",
        "Checked-file notes were extracted into CSV reports. Missing-phone confirmations are treated as authoritative report-only rows; the pipeline does not try to auto-fill those phones from backup data.",
        "",
    ]
    (reports_dir / "checked_review_summary.md").write_text("\n".join(summary_lines), encoding="utf-8")
    print(f"subscription_rows={len(subscription_rows)}")
    print(f"missing_phone_rows={len(missing_phone_rows)}")
    print(f"card_rows={len(card_decision_rows)}")
    print(f"summary={(reports_dir / 'checked_review_summary.md').relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--checked-dir", default=str(ROOT / "output" / "splits" / "checked"))
    parser.add_argument("--reports-dir", default=str(ROOT / "output" / "part2_20260429" / "reports"))
    parser.add_argument("--previous-multiple-cards-detail", default=str(ROOT / "output" / "multiple_cards_detail.csv"))
    return parser.parse_args()


def main() -> None:
    review(parse_args())


if __name__ == "__main__":
    main()
