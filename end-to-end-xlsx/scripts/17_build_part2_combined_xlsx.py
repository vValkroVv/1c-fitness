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
import re
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
THREE_FUNNEL_BUILDER = ROOT / "scripts" / "12_build_part2_three_funnel_xlsx.py"
CUSTOMER_SINGLE_STAGE_MODE = "customer_20260520_single_stage"
FITBASE_LABELS = {
    "Новые заявки": ("новые заявки", "неразобранные"),
    "Действующие клиенты": ("Действующие абонементы", "Все действующие абонементы"),
    "Реактивация": ("Реактивация(годовые абонементы)", "Все закрытые абонементы"),
}
PHONE_SPLIT_RE = re.compile(r"[,;]\s*")
NEW_APPLICATION_REFUSER_FIELDS = [
    "client_ref",
    "client_id",
    "phone",
    "client_fio",
    "email",
    "funnel",
    "funnel_step",
    "budget",
    "create_date",
    "manager",
    "branch",
    "normalized_club",
    "club_source",
    "selected_card_number",
    "selected_card_ref",
    "selected_subscription_ref",
    "selected_subscription_name",
    "selected_subscription_start_date",
    "selected_subscription_end_date",
    "selected_subscription_sale_date",
    "selection_reason",
    "cutoff_date",
]


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


def has_phone(row: dict[str, str]) -> bool:
    return bool((row.get("phones") or "").strip())


def parse_date(value: str | None) -> date:
    if not value:
        return date.min
    try:
        return datetime.strptime(str(value)[:10], "%Y-%m-%d").date()
    except ValueError:
        return date.min


def int_client_id(value: str | None) -> int:
    digits = re.sub(r"\D+", "", value or "")
    return int(digits) if digits else 0


def normalize_phone_token(value: str) -> str:
    digits = re.sub(r"\D+", "", value or "")
    if len(digits) == 11 and digits[0] in {"7", "8"}:
        return "7" + digits[1:]
    if len(digits) == 10:
        return "7" + digits
    return ""


def normalize_phones(value: str) -> list[str]:
    phones: list[str] = []
    for part in PHONE_SPLIT_RE.split(value or ""):
        phone = normalize_phone_token(part)
        if phone and phone not in phones:
            phones.append(phone)
    return phones


def phone_dedupe_score(row: dict[str, str]) -> tuple[object, ...]:
    subscription_sale_date = parse_date(row.get("selected_subscription_sale_date"))
    subscription_end_date = parse_date(row.get("selected_subscription_end_date"))
    subscription_start_date = parse_date(row.get("selected_subscription_start_date"))
    create_date = parse_date(row.get("create_date"))
    has_subscription = int(
        bool(row.get("selected_subscription_ref"))
        or subscription_sale_date != date.min
        or subscription_end_date != date.min
    )
    funnel_priority = {
        "Действующие клиенты": 2,
        "Реактивация": 1,
        "Новые заявки": 0,
    }.get(row.get("funnel", ""), 0)
    has_card = int(bool((row.get("selected_card_number") or "").strip()))
    return (
        has_subscription,
        subscription_sale_date,
        subscription_end_date,
        subscription_start_date,
        funnel_priority,
        has_card,
        create_date,
        int_client_id(row.get("client_id")),
    )


def phone_component_key(row: dict[str, str]) -> tuple[object, ...]:
    phones = normalize_phones(row.get("phones", ""))
    return (min(phones) if phones else "", row.get("client_id", ""), row.get("client_ref", ""))


def dedupe_by_phone_keep_latest_subscription(
    rows: list[dict[str, str]],
) -> tuple[list[dict[str, str]], list[dict[str, object]]]:
    """Keep one export row per connected normalized-phone component.

    A component can contain more than one phone when a row has several phone
    values and each value links to other rows. The winner is the row with the
    latest purchased/selected subscription; rows without subscriptions are only
    used as a fallback when a phone component has no subscription at all.
    """

    phone_to_indexes: dict[str, list[int]] = defaultdict(list)
    for index, row in enumerate(rows):
        for phone in normalize_phones(row.get("phones", "")):
            phone_to_indexes[phone].append(index)

    parent = list(range(len(rows)))

    def find(index: int) -> int:
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left: int, right: int) -> None:
        left_root = find(left)
        right_root = find(right)
        if left_root != right_root:
            parent[right_root] = left_root

    for indexes in phone_to_indexes.values():
        if len(indexes) < 2:
            continue
        first = indexes[0]
        for index in indexes[1:]:
            union(first, index)

    components: dict[int, list[int]] = defaultdict(list)
    for index in range(len(rows)):
        components[find(index)].append(index)

    kept_indexes: set[int] = set()
    removed_rows: list[dict[str, object]] = []
    for component_indexes in components.values():
        if len(component_indexes) == 1:
            kept_indexes.add(component_indexes[0])
            continue
        winner_index = max(component_indexes, key=lambda index: phone_dedupe_score(rows[index]))
        winner = rows[winner_index]
        kept_indexes.add(winner_index)
        component_phones = sorted(
            {
                phone
                for index in component_indexes
                for phone in normalize_phones(rows[index].get("phones", ""))
            }
        )
        for index in component_indexes:
            if index == winner_index:
                continue
            removed = rows[index]
            removed_rows.append(
                {
                    "client_ref": removed.get("client_ref", ""),
                    "client_id": removed.get("client_id", ""),
                    "client_fio": removed.get("client_fio", ""),
                    "phones": removed.get("phones", ""),
                    "normalized_phone_component": ";".join(component_phones),
                    "funnel": removed.get("funnel", ""),
                    "funnel_step": removed.get("funnel_step", ""),
                    "selected_subscription_ref": removed.get("selected_subscription_ref", ""),
                    "selected_subscription_name": removed.get("selected_subscription_name", ""),
                    "selected_subscription_sale_date": removed.get("selected_subscription_sale_date", ""),
                    "selected_subscription_end_date": removed.get("selected_subscription_end_date", ""),
                    "create_date": removed.get("create_date", ""),
                    "winner_client_ref": winner.get("client_ref", ""),
                    "winner_client_id": winner.get("client_id", ""),
                    "winner_client_fio": winner.get("client_fio", ""),
                    "winner_funnel": winner.get("funnel", ""),
                    "winner_funnel_step": winner.get("funnel_step", ""),
                    "winner_selected_subscription_ref": winner.get("selected_subscription_ref", ""),
                    "winner_selected_subscription_name": winner.get("selected_subscription_name", ""),
                    "winner_selected_subscription_sale_date": winner.get("selected_subscription_sale_date", ""),
                    "winner_selected_subscription_end_date": winner.get("selected_subscription_end_date", ""),
                    "winner_create_date": winner.get("create_date", ""),
                    "dedupe_reason": "same normalized phone component; kept latest purchased subscription",
                }
            )

    deduped_rows = [dict(row) for index, row in enumerate(rows) if index in kept_indexes]
    return sorted(deduped_rows, key=phone_component_key), removed_rows


def filter_main_export_rows(
    rows: list[dict[str, str]],
    require_phone_for_new_applications: bool,
) -> list[dict[str, str]]:
    if not require_phone_for_new_applications:
        return [dict(row) for row in rows]
    return [
        dict(row)
        for row in rows
        if row.get("funnel") != "Новые заявки" or has_phone(row)
    ]


def is_new_application_refuser(row: dict[str, str]) -> bool:
    return row.get("funnel") == "Новые заявки" and row.get("funnel_step") == "Неразобранные"


def split_new_application_refusers(
    rows: list[dict[str, str]],
    transfer_new_applications_to_memberships: bool,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    if not transfer_new_applications_to_memberships:
        return [dict(row) for row in rows], []
    kept_rows: list[dict[str, str]] = []
    refuser_rows: list[dict[str, str]] = []
    for row in rows:
        if is_new_application_refuser(row):
            refuser_rows.append(dict(row))
        else:
            kept_rows.append(dict(row))
    return kept_rows, refuser_rows


def refuser_export_row(row: dict[str, str]) -> dict[str, str]:
    return {
        "client_ref": row.get("client_ref", ""),
        "client_id": row.get("client_id", ""),
        "phone": row.get("phones", ""),
        "client_fio": row.get("client_fio", ""),
        "email": row.get("email", ""),
        "funnel": row.get("funnel", ""),
        "funnel_step": row.get("funnel_step", ""),
        "budget": row.get("budget", ""),
        "create_date": row.get("create_date", ""),
        "manager": row.get("manager", ""),
        "branch": row.get("branch", ""),
        "normalized_club": row.get("normalized_club", ""),
        "club_source": row.get("club_source", ""),
        "selected_card_number": row.get("selected_card_number", ""),
        "selected_card_ref": row.get("selected_card_ref", ""),
        "selected_subscription_ref": row.get("selected_subscription_ref", ""),
        "selected_subscription_name": row.get("selected_subscription_name", ""),
        "selected_subscription_start_date": row.get("selected_subscription_start_date", ""),
        "selected_subscription_end_date": row.get("selected_subscription_end_date", ""),
        "selected_subscription_sale_date": row.get("selected_subscription_sale_date", ""),
        "selection_reason": row.get("selection_reason", ""),
        "cutoff_date": row.get("cutoff_date", ""),
    }


def write_new_application_refusers(csv_dir: Path, rows: list[dict[str, str]]) -> None:
    write_csv(
        csv_dir / "new_application_refusers.csv",
        [refuser_export_row(row) for row in rows],
        NEW_APPLICATION_REFUSER_FIELDS,
    )


def filter_cards_export_rows(rows: list[dict[str, str]], funnel_filter: str) -> list[dict[str, str]]:
    if not funnel_filter:
        return [dict(row) for row in rows]
    known_funnels = {row.get("funnel", "") for row in rows}
    if funnel_filter not in known_funnels:
        raise ValueError(f"Unknown --cards-funnel-filter {funnel_filter!r}; known funnels: {sorted(known_funnels)}")
    return [dict(row) for row in rows if row.get("funnel") == funnel_filter]


def write_single_stage_reports(reports_dir: Path, rows: list[dict[str, str]]) -> None:
    funnel_counts = Counter(row.get("funnel", "") for row in rows)
    stage_counts = Counter((row.get("funnel", ""), row.get("funnel_step", "")) for row in rows)
    branch_counts = Counter(row.get("branch", "") for row in rows)
    branch_by_club_counts = Counter((row.get("normalized_club", ""), row.get("branch", "")) for row in rows)
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
    write_csv(
        reports_dir / "branch_distribution.csv",
        [{"branch": branch, "clients": count} for branch, count in branch_counts.most_common()],
        ["branch", "clients"],
    )
    write_csv(
        reports_dir / "branch_distribution_by_club.csv",
        [
            {"normalized_club": club, "branch": branch, "clients": count}
            for (club, branch), count in branch_by_club_counts.most_common()
        ],
        ["normalized_club", "branch", "clients"],
    )


def write_export_filter_reports(
    reports_dir: Path,
    source_rows: list[dict[str, str]],
    main_rows: list[dict[str, str]],
    cards_rows: list[dict[str, str]],
    require_phone_for_new_applications: bool,
    transfer_new_applications_to_memberships: bool,
    transferred_new_application_rows: list[dict[str, str]],
    cards_funnel_filter: str,
    phone_deduplication_applied: bool,
    phone_deduplication_removed_rows: list[dict[str, object]],
) -> None:
    source_by_funnel = Counter(row.get("funnel", "") for row in source_rows)
    main_by_funnel = Counter(row.get("funnel", "") for row in main_rows)
    cards_by_funnel = Counter(row.get("funnel", "") for row in cards_rows)
    missing_phone_by_funnel = Counter(row.get("funnel", "") for row in source_rows if not has_phone(row))
    main_excluded_refs = {row.get("client_ref", "") for row in source_rows} - {
        row.get("client_ref", "") for row in main_rows
    }
    cards_excluded_refs = {row.get("client_ref", "") for row in source_rows} - {
        row.get("client_ref", "") for row in cards_rows
    }
    new_applications_without_phone_count = sum(
        1
        for row in source_rows
        if row.get("funnel") == "Новые заявки" and not has_phone(row)
    )

    summary_rows = [
        {"metric": "source_stage_clients", "value": len(source_rows)},
        {"metric": "main_xlsx_clients", "value": len(main_rows)},
        {"metric": "cards_xlsx_clients", "value": len(cards_rows)},
        {"metric": "main_excluded_total", "value": len(main_excluded_refs)},
        {
            "metric": "main_rule_new_applications_require_phone",
            "value": "1" if require_phone_for_new_applications else "0",
        },
        {
            "metric": "main_rule_new_applications_to_memberships",
            "value": "1" if transfer_new_applications_to_memberships else "0",
        },
        {
            "metric": "main_excluded_new_applications_without_phone",
            "value": new_applications_without_phone_count,
        },
        {
            "metric": "main_transferred_new_applications_to_memberships",
            "value": len(transferred_new_application_rows),
        },
        {"metric": "cards_funnel_filter", "value": cards_funnel_filter or "all"},
        {"metric": "cards_excluded_not_matching_filter", "value": len(cards_excluded_refs)},
        {"metric": "phone_deduplication_applied", "value": "1" if phone_deduplication_applied else "0"},
        {"metric": "phone_deduplication_removed_clients", "value": len(phone_deduplication_removed_rows)},
    ]
    write_csv(reports_dir / "export_filter_summary.csv", summary_rows, ["metric", "value"])

    all_funnels = sorted(set(source_by_funnel) | set(main_by_funnel) | set(cards_by_funnel))
    write_csv(
        reports_dir / "export_filter_funnel_distribution.csv",
        [
            {
                "funnel": funnel,
                "source_stage_clients": source_by_funnel.get(funnel, 0),
                "source_missing_phone_clients": missing_phone_by_funnel.get(funnel, 0),
                "main_xlsx_clients": main_by_funnel.get(funnel, 0),
                "cards_xlsx_clients": cards_by_funnel.get(funnel, 0),
            }
            for funnel in all_funnels
        ],
        [
            "funnel",
            "source_stage_clients",
            "source_missing_phone_clients",
            "main_xlsx_clients",
            "cards_xlsx_clients",
        ],
    )

    lines = [
        "# Final XLSX export filters",
        "",
        "These rules are applied only when writing the final Fitbase XLSX files.",
        "The source `final_funnel_clients.csv` remains complete for audit and reports.",
        "",
        "## Applied rules",
        "",
        (
            "- Main `import_заявки` XLSX: `Новые заявки` rows without a phone are excluded."
            if require_phone_for_new_applications
            else "- Main `import_заявки` XLSX: no phone-based new-application filter."
        ),
        (
            "- Main `import_заявки` XLSX: final `Новые заявки / Неразобранные` rows "
            "are moved to the membership import with tag `отказники`."
            if transfer_new_applications_to_memberships
            else "- Main `import_заявки` XLSX: final `Новые заявки / Неразобранные` rows stay in requests."
        ),
        (
            f"- Plastic-card XLSX: only internal funnel `{cards_funnel_filter}` is exported."
            if cards_funnel_filter
            else "- Plastic-card XLSX: all funnels are exported."
        ),
        "",
        "## Counts",
        "",
        f"- source_stage_clients: `{len(source_rows)}`",
        f"- main_xlsx_clients: `{len(main_rows)}`",
        f"- cards_xlsx_clients: `{len(cards_rows)}`",
        f"- main_excluded_total: `{len(main_excluded_refs)}`",
        f"- main_excluded_new_applications_without_phone: `{new_applications_without_phone_count}`",
        f"- main_transferred_new_applications_to_memberships: `{len(transferred_new_application_rows)}`",
        f"- cards_excluded_not_matching_filter: `{len(cards_excluded_refs)}`",
        f"- phone_deduplication_removed_clients: `{len(phone_deduplication_removed_rows)}`",
        "",
        "## Distribution",
        "",
    ]
    for funnel in all_funnels:
        lines.append(
            f"- `{funnel}`: source `{source_by_funnel.get(funnel, 0)}`, "
            f"missing phone `{missing_phone_by_funnel.get(funnel, 0)}`, "
            f"main XLSX `{main_by_funnel.get(funnel, 0)}`, "
            f"cards XLSX `{cards_by_funnel.get(funnel, 0)}`"
        )
    lines.append("")
    (reports_dir / "export_filter_rules.md").write_text("\n".join(lines), encoding="utf-8")

    write_csv(
        reports_dir / "phone_deduplication_removed_clients.csv",
        phone_deduplication_removed_rows,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "phones",
            "normalized_phone_component",
            "funnel",
            "funnel_step",
            "selected_subscription_ref",
            "selected_subscription_name",
            "selected_subscription_sale_date",
            "selected_subscription_end_date",
            "create_date",
            "winner_client_ref",
            "winner_client_id",
            "winner_client_fio",
            "winner_funnel",
            "winner_funnel_step",
            "winner_selected_subscription_ref",
            "winner_selected_subscription_name",
            "winner_selected_subscription_sale_date",
            "winner_selected_subscription_end_date",
            "winner_create_date",
            "dedupe_reason",
        ],
    )
    removed_by_funnel = Counter(str(row.get("funnel", "")) for row in phone_deduplication_removed_rows)
    winner_by_funnel = Counter(str(row.get("winner_funnel", "")) for row in phone_deduplication_removed_rows)
    write_csv(
        reports_dir / "phone_deduplication_summary.csv",
        [
            {"metric": "phone_deduplication_applied", "value": "1" if phone_deduplication_applied else "0"},
            {"metric": "removed_clients", "value": len(phone_deduplication_removed_rows)},
            *[
                {"metric": f"removed_from_{funnel}", "value": count}
                for funnel, count in removed_by_funnel.most_common()
            ],
            *[
                {"metric": f"winner_in_{funnel}", "value": count}
                for funnel, count in winner_by_funnel.most_common()
            ],
        ],
        ["metric", "value"],
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
    branches_config = as_abs(args.branches_config)

    output_dir.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(parents=True, exist_ok=True)
    csv_dir.mkdir(parents=True, exist_ok=True)

    rows = builder.read_csv(stage_dir / "final_funnel_clients.csv")
    managers_by_club = builder.load_managers(managers_config)
    branches_by_club = builder.load_branches(branches_config)
    builder.assign_managers(rows, managers_by_club)
    builder.assign_branches(rows, branches_by_club)
    rows = builder.sort_rows(rows)
    builder.write_csv(stage_dir / "final_funnel_clients.csv", rows, builder.FINAL_FUNNEL_FIELDS)
    builder.write_reports(rows=rows, stage_dir=stage_dir, output_dir=output_dir, reports_dir=reports_dir, csv_dir=csv_dir)
    main_rows = filter_main_export_rows(rows, args.main_require_phone_for_new_applications)
    phone_deduplication_removed_rows: list[dict[str, object]] = []
    if args.dedupe_by_phone_keep_latest_subscription:
        main_rows, phone_deduplication_removed_rows = dedupe_by_phone_keep_latest_subscription(main_rows)
    main_rows, new_application_refuser_rows = split_new_application_refusers(
        main_rows,
        args.main_transfer_new_applications_to_memberships,
    )
    write_new_application_refusers(csv_dir, new_application_refuser_rows)
    cards_rows = filter_cards_export_rows(
        main_rows if args.dedupe_by_phone_keep_latest_subscription or args.main_transfer_new_applications_to_memberships else rows,
        args.cards_funnel_filter,
    )
    write_export_filter_reports(
        reports_dir=reports_dir,
        source_rows=rows,
        main_rows=main_rows,
        cards_rows=cards_rows,
        require_phone_for_new_applications=args.main_require_phone_for_new_applications,
        transfer_new_applications_to_memberships=args.main_transfer_new_applications_to_memberships,
        transferred_new_application_rows=new_application_refuser_rows,
        cards_funnel_filter=args.cards_funnel_filter,
        phone_deduplication_applied=args.dedupe_by_phone_keep_latest_subscription,
        phone_deduplication_removed_rows=phone_deduplication_removed_rows,
    )

    fitbase_main_rows = apply_fitbase_labels(main_rows, args.fitbase_label_mode)
    fitbase_main_rows = builder.sort_rows(fitbase_main_rows)
    fitbase_card_rows = apply_fitbase_labels(cards_rows, args.fitbase_label_mode)
    fitbase_card_rows = builder.sort_rows(fitbase_card_rows)
    write_single_stage_reports(reports_dir, fitbase_main_rows)

    main_xlsx = output_dir / f"fitbase_active_clients_import_zayavki_{date_stamp}__all_funnels.xlsx"
    cards_xlsx = output_dir / f"fitbase_active_clients_plastic_cards_{date_stamp}__all_funnels.xlsx"

    builder.write_main_xlsx(main_template, main_xlsx, fitbase_main_rows)
    builder.write_cards_xlsx(cards_template, cards_xlsx, fitbase_card_rows)

    print(f"source_rows={len(rows)}")
    print(f"main_xlsx_rows={len(fitbase_main_rows)}")
    print(f"cards_xlsx_rows={len(fitbase_card_rows)}")
    print(f"phone_deduplication_removed_rows={len(phone_deduplication_removed_rows)}")
    print(f"new_application_refuser_rows={len(new_application_refuser_rows)}")
    print(f"combined_main={main_xlsx.relative_to(ROOT)}")
    print(f"combined_cards={cards_xlsx.relative_to(ROOT)}")
    print(f"reports_dir={reports_dir.relative_to(ROOT)}")
    print(f"csv_dir={csv_dir.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff-date", default="2026-06-30")
    parser.add_argument("--date-stamp", default="20260630")
    parser.add_argument("--stage-dir", default=str(ROOT / "work" / "20260630" / "owner" / "staging"))
    parser.add_argument("--output-dir", default=str(ROOT / "work" / "20260630" / "owner"))
    parser.add_argument("--reports-dir", default="")
    parser.add_argument("--csv-dir", default="")
    parser.add_argument("--main-template", default=str(ROOT / "templates" / "import_zayavki.xlsx"))
    parser.add_argument("--cards-template", default=str(ROOT / "templates" / "plastic_cards.xlsx"))
    parser.add_argument("--managers-config", default=str(ROOT / "config" / "managers_by_club.yml"))
    parser.add_argument("--branches-config", default=str(ROOT / "config" / "branches_by_club.yml"))
    parser.add_argument("--fitbase-label-mode", default="internal")
    parser.add_argument(
        "--main-require-phone-for-new-applications",
        action="store_true",
        help="Exclude internal `Новые заявки` rows without phone from the main import XLSX.",
    )
    parser.add_argument(
        "--main-transfer-new-applications-to-memberships",
        action="store_true",
        help="Move final internal `Новые заявки / Неразобранные` rows out of requests into the membership tag import.",
    )
    parser.add_argument(
        "--cards-funnel-filter",
        default="",
        help="If set, export only this internal funnel to the plastic-card XLSX.",
    )
    parser.add_argument(
        "--dedupe-by-phone-keep-latest-subscription",
        action="store_true",
        help="Keep only one final main-export client per normalized phone component.",
    )
    return parser.parse_args()


def main() -> None:
    build_combined(parse_args())


if __name__ == "__main__":
    main()
