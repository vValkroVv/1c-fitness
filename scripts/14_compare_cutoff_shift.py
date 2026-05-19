#!/usr/bin/env python3
"""Compare two Part 2 final_funnel_clients.csv files for cutoff shift analysis."""

from __future__ import annotations

import argparse
import csv
from collections import Counter
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


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


def count_missing(rows: list[dict[str, str]], field: str) -> int:
    return sum(1 for row in rows if not (row.get(field) or "").strip())


def compare(args: argparse.Namespace) -> None:
    base_path = as_abs(args.base_final)
    shift_path = as_abs(args.shift_final)
    output_path = as_abs(args.output)
    details_path = output_path.with_suffix(".csv")

    base_rows = read_csv(base_path)
    shift_rows = read_csv(shift_path)
    base_by_ref = {row["client_ref"]: row for row in base_rows}
    shift_by_ref = {row["client_ref"]: row for row in shift_rows}
    refs = sorted(set(base_by_ref) | set(shift_by_ref))

    changed_rows: list[dict[str, object]] = []
    changed_funnel = 0
    changed_stage = 0
    exited_active = 0
    entered_reactivation = 0
    entered_new = 0
    selected_subscription_changed = 0
    selected_card_changed = 0

    for ref in refs:
        base = base_by_ref.get(ref, {})
        shift = shift_by_ref.get(ref, {})
        if not base or not shift:
            change_type = "client_presence_changed"
        else:
            changes = []
            if base.get("funnel") != shift.get("funnel"):
                changed_funnel += 1
                changes.append("funnel")
                if base.get("funnel") == "Действующие клиенты" and shift.get("funnel") != "Действующие клиенты":
                    exited_active += 1
                if shift.get("funnel") == "Реактивация" and base.get("funnel") != "Реактивация":
                    entered_reactivation += 1
                if shift.get("funnel") == "Новые заявки" and base.get("funnel") != "Новые заявки":
                    entered_new += 1
            if base.get("funnel_step") != shift.get("funnel_step"):
                changed_stage += 1
                changes.append("stage")
            if base.get("selected_subscription_ref") != shift.get("selected_subscription_ref"):
                selected_subscription_changed += 1
                changes.append("selected_subscription")
            if base.get("selected_card_ref") != shift.get("selected_card_ref"):
                selected_card_changed += 1
                changes.append("selected_card")
            change_type = ";".join(changes)
        if not change_type:
            continue
        changed_rows.append(
            {
                "client_ref": ref,
                "client_id": (shift or base).get("client_id", ""),
                "client_fio": (shift or base).get("client_fio", ""),
                "base_funnel": base.get("funnel", ""),
                "shift_funnel": shift.get("funnel", ""),
                "base_step": base.get("funnel_step", ""),
                "shift_step": shift.get("funnel_step", ""),
                "base_subscription_ref": base.get("selected_subscription_ref", ""),
                "shift_subscription_ref": shift.get("selected_subscription_ref", ""),
                "base_card_ref": base.get("selected_card_ref", ""),
                "shift_card_ref": shift.get("selected_card_ref", ""),
                "change_type": change_type,
            }
        )

    write_csv(
        details_path,
        changed_rows,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "base_funnel",
            "shift_funnel",
            "base_step",
            "shift_step",
            "base_subscription_ref",
            "shift_subscription_ref",
            "base_card_ref",
            "shift_card_ref",
            "change_type",
        ],
    )

    lines = [
        "# Cutoff Shift Comparison",
        "",
        f"Run date: `{datetime.now().isoformat(timespec='seconds')}`",
        "Base cutoff: `2026-04-24` (Friday)",
        "Shift cutoff: `2026-04-27` (Monday)",
        "Backup available through: `2026-04-29 23:57:02`",
        "",
        "This is a recalculation on the same backup, not a new Monday backup. It can show how statuses change by cutoff date, but it cannot see documents created after the backup.",
        "",
        "## Funnel Counts",
        "",
        "| Funnel | Base | Shift | Delta |",
        "|---|---:|---:|---:|",
    ]
    base_funnels = Counter(row.get("funnel", "") for row in base_rows)
    shift_funnels = Counter(row.get("funnel", "") for row in shift_rows)
    for funnel in sorted(set(base_funnels) | set(shift_funnels)):
        lines.append(f"| {funnel} | {base_funnels[funnel]} | {shift_funnels[funnel]} | {shift_funnels[funnel] - base_funnels[funnel]} |")

    lines.extend(["", "## Stage Counts", "", "| Funnel / Stage | Base | Shift | Delta |", "|---|---:|---:|---:|"])
    base_stages = Counter((row.get("funnel", ""), row.get("funnel_step", "")) for row in base_rows)
    shift_stages = Counter((row.get("funnel", ""), row.get("funnel_step", "")) for row in shift_rows)
    for key in sorted(set(base_stages) | set(shift_stages)):
        label = f"{key[0]} / {key[1]}"
        lines.append(f"| {label} | {base_stages[key]} | {shift_stages[key]} | {shift_stages[key] - base_stages[key]} |")

    lines.extend(
        [
            "",
            "## Movement Summary",
            "",
            f"- clients changed funnel: `{changed_funnel}`",
            f"- clients changed stage: `{changed_stage}`",
            f"- clients exited active: `{exited_active}`",
            f"- clients entered reactivation: `{entered_reactivation}`",
            f"- clients entered new applications: `{entered_new}`",
            f"- clients changed selected subscription: `{selected_subscription_changed}`",
            f"- clients changed selected card: `{selected_card_changed}`",
            f"- detailed changed rows: `{details_path.relative_to(ROOT)}`",
            "",
            "## Missing Counts",
            "",
            "| Metric | Base | Shift | Delta |",
            "|---|---:|---:|---:|",
        ]
    )
    missing_metrics = [
        ("missing_phone", "phones"),
        ("missing_card", "selected_card_number"),
        ("missing_club", "normalized_club"),
        ("missing_manager", "manager"),
    ]
    for label, field in missing_metrics:
        base_count = count_missing(base_rows, field)
        shift_count = count_missing(shift_rows, field)
        lines.append(f"| {label} | {base_count} | {shift_count} | {shift_count - base_count} |")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"changed_rows={len(changed_rows)}")
    print(f"changed_funnel={changed_funnel}")
    print(f"changed_stage={changed_stage}")
    print(f"report={output_path.relative_to(ROOT)}")
    print(f"details={details_path.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-final", required=True)
    parser.add_argument("--shift-final", required=True)
    parser.add_argument("--output", required=True)
    return parser.parse_args()


def main() -> None:
    compare(parse_args())


if __name__ == "__main__":
    main()
