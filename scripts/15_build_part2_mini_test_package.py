#!/usr/bin/env python3
"""Build a mini-test XLSX package for Part 2 three-funnel outputs."""

from __future__ import annotations

import argparse
import csv
import importlib.util
from collections import defaultdict
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "12_build_part2_three_funnel_xlsx.py"

spec = importlib.util.spec_from_file_location("part2_build", BUILD_SCRIPT)
part2_build = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(part2_build)


def as_abs(path: str | Path) -> Path:
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def int_value(value: object, default: int = 0) -> int:
    try:
        if value in ("", None):
            return default
        return int(float(str(value)))
    except ValueError:
        return default


def add_rows(
    selected: dict[str, dict[str, str]],
    reasons: defaultdict[str, list[str]],
    candidates: list[dict[str, str]],
    reason: str,
    limit: int,
) -> int:
    added = 0
    for row in candidates:
        client_ref = row.get("client_ref", "")
        if not client_ref:
            continue
        if reason not in reasons[client_ref]:
            reasons[client_ref].append(reason)
        if client_ref not in selected:
            selected[client_ref] = row
            added += 1
        if added >= limit:
            break
    return added


def build_package(args: argparse.Namespace) -> None:
    source = as_abs(args.source)
    output_dir = as_abs(args.output_dir)
    main_template = as_abs(args.main_template)
    cards_template = as_abs(args.cards_template)
    output_dir.mkdir(parents=True, exist_ok=True)

    rows = sorted(read_csv(source), key=lambda row: (row.get("funnel", ""), row.get("funnel_step", ""), row.get("client_id", "")))
    selected: dict[str, dict[str, str]] = {}
    reasons: defaultdict[str, list[str]] = defaultdict(list)
    summary: list[dict[str, object]] = []

    buckets: list[tuple[str, list[dict[str, str]], int]] = []
    active_stages = [
        "60-31 день до окончания",
        "30-8 дней до окончания",
        "7-0 день до окончания",
        "Действующие клиенты",
    ]
    for stage in active_stages:
        candidates = [row for row in rows if row.get("funnel") == "Действующие клиенты" and row.get("funnel_step") == stage]
        buckets.append((f"active_stage:{stage}", candidates, 5))
    new_candidates = [row for row in rows if row.get("funnel") == "Новые заявки"]
    buckets.append(("new_applications", new_candidates, 5))
    for stage in ["1-6 дней", "7-29 дней", "30-59 дней", "60-89 дней", "более 90 дней"]:
        candidates = [row for row in rows if row.get("funnel") == "Реактивация" and row.get("funnel_step") == stage]
        buckets.append((f"reactivation_stage:{stage}", candidates, 5))

    edge_buckets = [
        ("missing_phone", [row for row in rows if not row.get("phones")], 5),
        ("missing_card", [row for row in rows if not row.get("selected_card_number")], 5),
        ("multiple_cards", [row for row in rows if "multiple_cards" in row.get("validation_status", "")], 5),
        (
            "multiple_subscriptions",
            [
                row
                for row in rows
                if int_value(row.get("active_full_subscription_count")) > 1
                or int_value(row.get("finished_full_subscription_count")) > 1
            ],
            5,
        ),
        ("empty_club", [row for row in rows if not row.get("normalized_club")], 5),
    ]
    buckets.extend(edge_buckets)

    for club in [
        "Коммунальная, 20",
        "Лососинское шоссе, 26",
        "Карельский (закрыт)",
        "Промышленная, 10",
        "Ровио, 3",
        "Клуб не определен (fallback)",
    ]:
        buckets.append((f"club:{club}", [row for row in rows if row.get("normalized_club") == club], 5))

    for bucket, candidates, limit in buckets:
        added = add_rows(selected, reasons, candidates, bucket, limit)
        summary.append({"bucket": bucket, "available": len(candidates), "selected_new": added})

    mini_rows = sorted(selected.values(), key=lambda row: row.get("client_id", ""))
    reason_rows = [
        {
            "client_ref": row.get("client_ref", ""),
            "client_id": row.get("client_id", ""),
            "client_fio": row.get("client_fio", ""),
            "funnel": row.get("funnel", ""),
            "funnel_step": row.get("funnel_step", ""),
            "normalized_club": row.get("normalized_club", ""),
            "reasons": "; ".join(reasons[row.get("client_ref", "")]),
        }
        for row in mini_rows
    ]
    summary.append({"bucket": "total_unique_clients", "available": len(rows), "selected_new": len(mini_rows)})

    main_xlsx = output_dir / "mini_fitbase_part2_import_zayavki_20260429.xlsx"
    cards_xlsx = output_dir / "mini_fitbase_part2_plastic_cards_20260429.xlsx"
    summary_csv = output_dir / "mini_fitbase_part2_summary_20260429.csv"
    selected_csv = output_dir / "mini_fitbase_part2_selected_clients_20260429.csv"

    part2_build.write_main_xlsx(main_template, main_xlsx, mini_rows)
    part2_build.write_cards_xlsx(cards_template, cards_xlsx, mini_rows)
    write_csv(summary_csv, summary, ["bucket", "available", "selected_new"])
    write_csv(
        selected_csv,
        reason_rows,
        ["client_ref", "client_id", "client_fio", "funnel", "funnel_step", "normalized_club", "reasons"],
    )

    print(f"mini_rows={len(mini_rows)}")
    print(f"main_xlsx={main_xlsx.relative_to(ROOT)}")
    print(f"cards_xlsx={cards_xlsx.relative_to(ROOT)}")
    print(f"summary_csv={summary_csv.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=str(ROOT / "output" / "part2_20260429" / "staging" / "final_funnel_clients.csv"))
    parser.add_argument("--output-dir", default=str(ROOT / "output" / "part2_20260429" / "mini_test"))
    parser.add_argument("--main-template", default=str(ROOT / "task-desc" / "Копия Импорт_заявки.xlsx"))
    parser.add_argument("--cards-template", default=str(ROOT / "task-desc" / "Пластиковая карта.xlsx"))
    return parser.parse_args()


def main() -> None:
    build_package(parse_args())


if __name__ == "__main__":
    main()
