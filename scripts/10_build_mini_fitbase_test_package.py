#!/usr/bin/env python3
"""Build a small Fitbase mini-test XLSX package from final active clients."""

from __future__ import annotations

import argparse
import csv
from collections import defaultdict
from pathlib import Path

from build_fitbase_xlsx import (
    DEFAULT_CARDS_TEMPLATE,
    DEFAULT_MAIN_TEMPLATE,
    ROOT,
    write_cards_xlsx,
    write_main_xlsx,
)


DEFAULT_DATE_STAMP = "20260429"
DEFAULT_FINAL_CLIENTS = ROOT / "output" / f"final_active_clients_{DEFAULT_DATE_STAMP}.csv"
DEFAULT_OUTPUT_DIR = ROOT / "output"

STAGE_LIMIT = 10
EDGE_LIMIT = 5


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def int_value(value: object, default: int = 0) -> int:
    try:
        if value in (None, ""):
            return default
        return int(str(value))
    except ValueError:
        return default


def add_rows(
    selected: dict[str, dict[str, str]],
    source_rows: list[dict[str, str]],
    reason: str,
    reasons_by_ref: defaultdict[str, list[str]],
    limit: int,
) -> int:
    added = 0
    for row in source_rows:
        client_ref = row.get("client_ref", "")
        if not client_ref:
            continue
        if reason not in reasons_by_ref[client_ref]:
            reasons_by_ref[client_ref].append(reason)
        if client_ref not in selected:
            selected[client_ref] = row
            added += 1
        if added >= limit:
            break
    return added


def build_mini_rows(rows: list[dict[str, str]]) -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    selected: dict[str, dict[str, str]] = {}
    reasons_by_ref: defaultdict[str, list[str]] = defaultdict(list)
    sorted_rows = sorted(rows, key=lambda row: (row.get("funnel_step", ""), row.get("client_id", "")))

    by_stage: defaultdict[str, list[dict[str, str]]] = defaultdict(list)
    for row in sorted_rows:
        by_stage[row.get("funnel_step", "")].append(row)

    summary_rows: list[dict[str, object]] = []
    for stage in [
        "Бронь",
        "60-31 день до окончания",
        "30-8 дней до окончания",
        "7-0 день до окончания",
        "Действующие клиенты",
    ]:
        candidates = by_stage.get(stage, [])[:STAGE_LIMIT]
        add_rows(selected, candidates, f"stage:{stage}", reasons_by_ref, STAGE_LIMIT)
        summary_rows.append({"bucket": f"stage:{stage}", "available": len(by_stage.get(stage, [])), "selected": len(candidates)})

    edge_buckets: list[tuple[str, list[dict[str, str]]]] = [
        ("multiple_phones", [row for row in sorted_rows if "," in (row.get("phones") or "")]),
        ("has_email", [row for row in sorted_rows if (row.get("email") or "").strip()]),
        ("multiple_plastic_cards", [row for row in sorted_rows if int_value(row.get("active_card_count")) > 1]),
        ("missing_plastic_card", [row for row in sorted_rows if int_value(row.get("active_card_count")) == 0]),
        ("missing_phone", [row for row in sorted_rows if not (row.get("phones") or "").strip()]),
        (
            "multiple_active_subscriptions",
            [row for row in sorted_rows if int_value(row.get("active_subscription_count")) > 1],
        ),
        (
            "missing_first_sale_or_create_date",
            [row for row in sorted_rows if not row.get("first_sale_date") or not row.get("create_date")],
        ),
    ]

    for bucket, candidates in edge_buckets:
        selected_candidates = candidates[:EDGE_LIMIT]
        add_rows(selected, selected_candidates, bucket, reasons_by_ref, EDGE_LIMIT)
        summary_rows.append({"bucket": bucket, "available": len(candidates), "selected": len(selected_candidates)})

    mini_rows = sorted(selected.values(), key=lambda row: row.get("client_id", ""))
    reason_rows = [
        {
            "client_ref": row.get("client_ref", ""),
            "client_id": row.get("client_id", ""),
            "client_fio": row.get("client_fio", ""),
            "funnel_step": row.get("funnel_step", ""),
            "reasons": "; ".join(reasons_by_ref[row.get("client_ref", "")]),
        }
        for row in mini_rows
    ]
    summary_rows.append({"bucket": "total_unique_clients", "available": len(rows), "selected": len(mini_rows)})
    return mini_rows, summary_rows + reason_rows


def build_package(args: argparse.Namespace) -> None:
    final_clients = Path(args.final_clients)
    output_dir = Path(args.output_dir)
    date_stamp = args.date_stamp

    rows = read_csv(final_clients)
    mini_rows, summary_rows = build_mini_rows(rows)

    main_xlsx = output_dir / f"mini_fitbase_active_clients_import_zayavki_{date_stamp}.xlsx"
    cards_xlsx = output_dir / f"mini_fitbase_active_clients_plastic_cards_{date_stamp}.xlsx"
    summary_csv = output_dir / f"mini_fitbase_active_clients_summary_{date_stamp}.csv"

    write_main_xlsx(Path(args.main_template), main_xlsx, mini_rows)
    write_cards_xlsx(Path(args.cards_template), cards_xlsx, mini_rows)
    write_csv(
        summary_csv,
        summary_rows,
        ["bucket", "available", "selected", "client_ref", "client_id", "client_fio", "funnel_step", "reasons"],
    )

    print(f"mini_rows={len(mini_rows)}")
    print(f"main_xlsx={main_xlsx.relative_to(ROOT)}")
    print(f"cards_xlsx={cards_xlsx.relative_to(ROOT)}")
    print(f"summary_csv={summary_csv.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--date-stamp", default=DEFAULT_DATE_STAMP)
    parser.add_argument("--final-clients", default=str(DEFAULT_FINAL_CLIENTS))
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--main-template", default=str(DEFAULT_MAIN_TEMPLATE))
    parser.add_argument("--cards-template", default=str(DEFAULT_CARDS_TEMPLATE))
    return parser.parse_args()


def main() -> None:
    build_package(parse_args())


if __name__ == "__main__":
    main()
