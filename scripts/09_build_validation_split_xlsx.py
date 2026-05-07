#!/usr/bin/env python3
"""Split final active-client XLSX exports into mutually exclusive validation groups."""

from __future__ import annotations

import argparse
import csv
import shutil
from dataclasses import dataclass
from pathlib import Path

from build_fitbase_xlsx import DEFAULT_CARDS_TEMPLATE, DEFAULT_MAIN_TEMPLATE, ROOT, write_cards_xlsx, write_main_xlsx


DEFAULT_DATE_STAMP = "20260429"
DEFAULT_FINAL_CLIENTS = ROOT / "output" / f"final_active_clients_{DEFAULT_DATE_STAMP}.csv"
DEFAULT_SPLITS_DIR = ROOT / "output" / "splits"


@dataclass(frozen=True)
class SplitGroup:
    order: int
    key: str
    title: str
    validation_status: str
    expected_rows: int

    @property
    def folder_name(self) -> str:
        return f"{self.order:02d}_{self.key}"

    @property
    def main_file_name(self) -> str:
        return f"fitbase_active_clients_import_zayavki_{DEFAULT_DATE_STAMP}__{self.folder_name}.xlsx"

    @property
    def cards_file_name(self) -> str:
        return f"fitbase_active_clients_plastic_cards_{DEFAULT_DATE_STAMP}__{self.folder_name}.xlsx"


SPLIT_GROUPS = [
    SplitGroup(1, "ok", "ok", "ok", 2885),
    SplitGroup(2, "tolko_neskolko_kart", "только несколько карт", "multiple_plastic_cards;", 7201),
    SplitGroup(
        3,
        "neskolko_abonementov_i_neskolko_kart",
        "несколько абонементов + несколько карт",
        "multiple_active_subscriptions;multiple_plastic_cards;",
        366,
    ),
    SplitGroup(4, "tolko_net_karty", "только нет карты", "missing_plastic_card;", 228),
    SplitGroup(
        5,
        "tolko_neskolko_abonementov",
        "только несколько абонементов",
        "multiple_active_subscriptions;",
        92,
    ),
    SplitGroup(
        6,
        "neskolko_abonementov_i_net_karty",
        "несколько абонементов + нет карты",
        "multiple_active_subscriptions;missing_plastic_card;",
        13,
    ),
    SplitGroup(7, "tolko_net_telefona", "только нет телефона", "missing_phone;", 6),
    SplitGroup(
        8,
        "net_telefona_i_neskolko_kart",
        "нет телефона + несколько карт",
        "missing_phone;multiple_plastic_cards;",
        3,
    ),
    SplitGroup(
        9,
        "net_telefona_i_net_karty",
        "нет телефона + нет карты",
        "missing_phone;missing_plastic_card;",
        2,
    ),
]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_summary_csv(path: Path, rows: list[dict[str, object]]) -> None:
    fieldnames = [
        "order",
        "group_key",
        "group_title",
        "validation_status",
        "expected_rows",
        "actual_rows",
        "directory",
        "main_xlsx_file",
        "cards_xlsx_file",
    ]
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def write_readme(path: Path, summary_rows: list[dict[str, object]], total_rows: int) -> None:
    lines = [
        "# Fitbase Active Clients Splits",
        "",
        "Source:",
        "",
        "```text",
        "output/fitbase_active_clients_import_zayavki_20260429.xlsx",
        "output/final_active_clients_20260429.csv",
        "```",
        "",
        "Each group directory contains two XLSX files:",
        "",
        "- main Fitbase import file with the same 9-column structure as `fitbase_active_clients_import_zayavki_20260429.xlsx`;",
        "- plastic-card file with the same 3-column structure as `fitbase_active_clients_plastic_cards_20260429.xlsx`.",
        "",
        "| # | Group | Rows | Main XLSX | Cards XLSX |",
        "|---:|---|---:|---|---|",
    ]
    for row in summary_rows:
        lines.append(
            f"| {row['order']} | {row['group_title']} | {row['actual_rows']} | `{row['main_xlsx_file']}` | `{row['cards_xlsx_file']}` |"
        )
    lines.extend(
        [
            "",
            f"Total rows across split files: `{total_rows}`.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def build_splits(args: argparse.Namespace) -> None:
    final_clients = Path(args.final_clients)
    splits_dir = Path(args.splits_dir)
    main_template = Path(args.main_template)
    cards_template = Path(args.cards_template)

    rows = read_csv(final_clients)
    by_status: dict[str, list[dict[str, str]]] = {}
    for row in rows:
        by_status.setdefault(row.get("validation_status", ""), []).append(row)

    known_statuses = {group.validation_status for group in SPLIT_GROUPS}
    unknown_statuses = sorted(set(by_status) - known_statuses)
    if unknown_statuses:
        raise ValueError(f"Unexpected validation_status values: {unknown_statuses}")

    if splits_dir.exists():
        shutil.rmtree(splits_dir)
    splits_dir.mkdir(parents=True, exist_ok=True)

    summary_rows: list[dict[str, object]] = []
    total_rows = 0

    for group in SPLIT_GROUPS:
        group_rows = by_status.get(group.validation_status, [])
        actual_rows = len(group_rows)
        if actual_rows != group.expected_rows:
            raise ValueError(
                f"{group.title}: expected {group.expected_rows} rows, got {actual_rows}"
            )

        group_dir = splits_dir / group.folder_name
        group_dir.mkdir(parents=True, exist_ok=True)
        main_xlsx_path = group_dir / group.main_file_name
        cards_xlsx_path = group_dir / group.cards_file_name
        write_main_xlsx(main_template, main_xlsx_path, group_rows)
        write_cards_xlsx(cards_template, cards_xlsx_path, group_rows)

        summary_rows.append(
            {
                "order": group.order,
                "group_key": group.key,
                "group_title": group.title,
                "validation_status": group.validation_status,
                "expected_rows": group.expected_rows,
                "actual_rows": actual_rows,
                "directory": str(group_dir.relative_to(ROOT)),
                "main_xlsx_file": str(main_xlsx_path.relative_to(ROOT)),
                "cards_xlsx_file": str(cards_xlsx_path.relative_to(ROOT)),
            }
        )
        total_rows += actual_rows
        print(f"{group.folder_name}={actual_rows}")

    if total_rows != len(rows):
        raise ValueError(f"Split rows total {total_rows} != source rows {len(rows)}")

    write_summary_csv(splits_dir / "split_summary.csv", summary_rows)
    write_readme(splits_dir / "README.md", summary_rows, total_rows)
    print(f"total_rows={total_rows}")
    print(f"wrote={splits_dir.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--final-clients", default=str(DEFAULT_FINAL_CLIENTS))
    parser.add_argument("--splits-dir", default=str(DEFAULT_SPLITS_DIR))
    parser.add_argument("--main-template", default=str(DEFAULT_MAIN_TEMPLATE))
    parser.add_argument("--cards-template", default=str(DEFAULT_CARDS_TEMPLATE))
    return parser.parse_args()


def main() -> None:
    build_splits(parse_args())


if __name__ == "__main__":
    main()
