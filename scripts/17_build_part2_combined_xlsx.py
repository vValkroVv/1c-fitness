#!/usr/bin/env python3
"""Build one combined Part 2 XLSX pair for all three funnels.

The three-funnel builder intentionally produces separate files per funnel.
This helper keeps the same templates, columns, styles, manager assignment, and
row ordering, but writes all final rows into one clients workbook and one cards
workbook.
"""

from __future__ import annotations

import argparse
import csv
import copy
import importlib.util
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THREE_FUNNEL_BUILDER = ROOT / "scripts" / "12_build_part2_three_funnel_xlsx.py"
CUSTOMER_SINGLE_STAGE_MODE = "customer_20260520_single_stage"
FITBASE_LABELS = {
    "Новые заявки": ("новые заявки", "неразобранные"),
    "Действующие клиенты": ("Действующие абонементы", "Все действующие абонементы"),
    "Реактивация": ("Реактивация(годовые абонементы)", "Все закрытые абонементы"),
}


def load_three_funnel_builder():
    spec = importlib.util.spec_from_file_location("part2_three_funnel_builder", THREE_FUNNEL_BUILDER)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Cannot load builder module: {THREE_FUNNEL_BUILDER}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def as_abs(path: str | Path) -> Path:
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def apply_fitbase_labels(rows: list[dict[str, str]], label_mode: str) -> list[dict[str, str]]:
    if label_mode in {"", "internal"}:
        return [dict(row) for row in rows]
    if label_mode != CUSTOMER_SINGLE_STAGE_MODE:
        raise ValueError(f"Unknown --fitbase-label-mode: {label_mode}")

    mapped_rows: list[dict[str, str]] = []
    for row in rows:
        item = copy.deepcopy(row)
        try:
            item["funnel"], item["funnel_step"] = FITBASE_LABELS[row.get("funnel", "")]
        except KeyError as exc:
            raise ValueError(f"Cannot map funnel to Fitbase label: {row.get('funnel', '')!r}") from exc
        mapped_rows.append(item)
    return mapped_rows


def write_single_stage_reports(reports_dir: Path, rows: list[dict[str, str]]) -> None:
    funnel_counts = Counter(row.get("funnel", "") for row in rows)
    stage_counts = Counter((row.get("funnel", ""), row.get("funnel_step", "")) for row in rows)
    write_csv(
        reports_dir / "fitbase_funnel_distribution.csv",
        [{"funnel": funnel, "clients": count} for funnel, count in funnel_counts.most_common()],
        ["funnel", "clients"],
    )
    write_csv(
        reports_dir / "single_stage_distribution.csv",
        [
            {"funnel": funnel, "funnel_step": step, "clients": count}
            for (funnel, step), count in stage_counts.most_common()
        ],
        ["funnel", "funnel_step", "clients"],
    )


def build_combined(args: argparse.Namespace) -> None:
    builder = load_three_funnel_builder()

    cutoff_date = args.cutoff_date
    date_stamp = args.date_stamp or cutoff_date.replace("-", "")
    stage_dir = as_abs(args.stage_dir)
    output_dir = as_abs(args.output_dir)
    reports_dir = as_abs(args.reports_dir) if args.reports_dir else stage_dir.parent / "reports"
    csv_dir = as_abs(args.csv_dir) if args.csv_dir else stage_dir.parent / "csv"
    main_template = as_abs(args.main_template)
    cards_template = as_abs(args.cards_template)
    managers_config = as_abs(args.managers_config)

    output_dir.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(parents=True, exist_ok=True)
    csv_dir.mkdir(parents=True, exist_ok=True)

    rows = builder.read_csv(stage_dir / "final_funnel_clients.csv")
    managers_by_club = builder.load_managers(managers_config)
    builder.assign_managers(rows, managers_by_club)
    rows = builder.sort_rows(rows)
    builder.write_csv(stage_dir / "final_funnel_clients.csv", rows, builder.FINAL_FUNNEL_FIELDS)
    builder.write_reports(rows=rows, stage_dir=stage_dir, output_dir=output_dir, reports_dir=reports_dir, csv_dir=csv_dir)
    fitbase_rows = apply_fitbase_labels(rows, args.fitbase_label_mode)
    fitbase_rows = builder.sort_rows(fitbase_rows)
    write_single_stage_reports(reports_dir, fitbase_rows)

    main_xlsx = output_dir / f"fitbase_active_clients_import_zayavki_{date_stamp}__all_funnels.xlsx"
    cards_xlsx = output_dir / f"fitbase_active_clients_plastic_cards_{date_stamp}__all_funnels.xlsx"

    builder.write_main_xlsx(main_template, main_xlsx, fitbase_rows)
    builder.write_cards_xlsx(cards_template, cards_xlsx, fitbase_rows)

    print(f"combined_rows={len(fitbase_rows)}")
    print(f"combined_main={main_xlsx.relative_to(ROOT)}")
    print(f"combined_cards={cards_xlsx.relative_to(ROOT)}")
    print(f"reports_dir={reports_dir.relative_to(ROOT)}")
    print(f"csv_dir={csv_dir.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff-date", default="2026-04-29")
    parser.add_argument("--date-stamp", default="")
    parser.add_argument("--stage-dir", default=str(ROOT / "output" / "part2_20260429_final" / "staging"))
    parser.add_argument("--output-dir", default=str(ROOT / "output" / "part2_20260429_final_combined"))
    parser.add_argument("--reports-dir", default="")
    parser.add_argument("--csv-dir", default="")
    parser.add_argument("--main-template", default=str(ROOT / "task-desc" / "Копия Импорт_заявки.xlsx"))
    parser.add_argument("--cards-template", default=str(ROOT / "task-desc" / "Пластиковая карта.xlsx"))
    parser.add_argument("--managers-config", default=str(ROOT / "config" / "managers_by_club.yml"))
    parser.add_argument("--fitbase-label-mode", default="internal")
    return parser.parse_args()


def main() -> None:
    build_combined(parse_args())


if __name__ == "__main__":
    main()
