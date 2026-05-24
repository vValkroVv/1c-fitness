#!/usr/bin/env python3
"""Build one combined Part 2 XLSX pair for all three funnels.

The three-funnel builder intentionally produces separate files per funnel.
This helper keeps the same templates, columns, styles, manager assignment, and
row ordering, but writes all final rows into one clients workbook and one cards
workbook.
"""

from __future__ import annotations

import argparse
import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THREE_FUNNEL_BUILDER = ROOT / "scripts" / "12_build_part2_three_funnel_xlsx.py"


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


def build_combined(args: argparse.Namespace) -> None:
    builder = load_three_funnel_builder()

    cutoff_date = args.cutoff_date
    date_stamp = args.date_stamp or cutoff_date.replace("-", "")
    stage_dir = as_abs(args.stage_dir)
    output_dir = as_abs(args.output_dir)
    main_template = as_abs(args.main_template)
    cards_template = as_abs(args.cards_template)
    managers_config = as_abs(args.managers_config)

    output_dir.mkdir(parents=True, exist_ok=True)

    rows = builder.read_csv(stage_dir / "final_funnel_clients.csv")
    managers_by_club = builder.load_managers(managers_config)
    builder.assign_managers(rows, managers_by_club)
    rows = builder.sort_rows(rows)

    main_xlsx = output_dir / f"fitbase_active_clients_import_zayavki_{date_stamp}__all_funnels.xlsx"
    cards_xlsx = output_dir / f"fitbase_active_clients_plastic_cards_{date_stamp}__all_funnels.xlsx"

    builder.write_main_xlsx(main_template, main_xlsx, rows)
    builder.write_cards_xlsx(cards_template, cards_xlsx, rows)

    print(f"combined_rows={len(rows)}")
    print(f"combined_main={main_xlsx.relative_to(ROOT)}")
    print(f"combined_cards={cards_xlsx.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff-date", default="2026-04-29")
    parser.add_argument("--date-stamp", default="")
    parser.add_argument("--stage-dir", default=str(ROOT / "output" / "part2_20260429_final" / "staging"))
    parser.add_argument("--output-dir", default=str(ROOT / "output" / "part2_20260429_final_combined"))
    parser.add_argument("--main-template", default=str(ROOT / "task-desc" / "Копия Импорт_заявки.xlsx"))
    parser.add_argument("--cards-template", default=str(ROOT / "task-desc" / "Пластиковая карта.xlsx"))
    parser.add_argument("--managers-config", default=str(ROOT / "config" / "managers_by_club.yml"))
    return parser.parse_args()


def main() -> None:
    build_combined(parse_args())


if __name__ == "__main__":
    main()
