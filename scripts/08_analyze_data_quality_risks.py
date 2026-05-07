#!/usr/bin/env python3
"""Create detailed data-quality risk reports for final Fitbase exports."""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CUTOFF_DATE = "2026-04-29"
DEFAULT_DATE_STAMP = DEFAULT_CUTOFF_DATE.replace("-", "")
DEFAULT_STAGING_DIR = ROOT / "output" / f"staging_{DEFAULT_CUTOFF_DATE}"
DEFAULT_OUTPUT_DIR = ROOT / "output"
DEFAULT_FINAL_CLIENTS = ROOT / "output" / f"final_active_clients_{DEFAULT_DATE_STAMP}.csv"
DEFAULT_GYM_SALES = ROOT / "data" / "gym_sales.csv"


def read_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def normalized_fio(value: str | None) -> str:
    return " ".join((value or "").strip().lower().split())


def normalized_fio_without_employee(value: str | None) -> str:
    stripped = re.sub(r"\s*\(сотрудник\)\s*", " ", value or "", flags=re.IGNORECASE)
    return normalized_fio(stripped)


def split_raw_values(value: str | None) -> list[str]:
    result: list[str] = []
    for part in (value or "").split(","):
        item = part.strip()
        if item and item not in result:
            result.append(item)
    return result


def parse_date(value: str | None) -> date | None:
    if not value:
        return None
    return datetime.strptime(value, "%Y-%m-%d").date()


def int_value(value: object, default: int = 0) -> int:
    try:
        if value in (None, ""):
            return default
        return int(str(value))
    except ValueError:
        return default


def funnel_step(days_to_end: int, has_booking: bool = False) -> str:
    if has_booking:
        return "Бронь"
    if 31 <= days_to_end <= 60:
        return "60-31 день до окончания"
    if 8 <= days_to_end <= 30:
        return "30-8 дней до окончания"
    if 0 <= days_to_end <= 7:
        return "7-0 день до окончания"
    return "Действующие клиенты"


def duration_bin(days: int) -> str:
    if days < 30:
        return "<30"
    if days <= 60:
        return "30-60"
    if days <= 180:
        return "61-180"
    if days <= 365:
        return "181-365"
    if days <= 450:
        return "366-450"
    return "451+"


def build_gym_sales_phone_index(gym_sales_path: Path) -> dict[str, list[str]]:
    index: defaultdict[str, list[str]] = defaultdict(list)
    for row in read_csv(gym_sales_path):
        fio = normalized_fio(row.get("client_name"))
        phone = (row.get("phone") or "").strip()
        if fio and phone and phone not in index[fio]:
            index[fio].append(phone)
    return dict(index)


def build_missing_phone_recovery_rows(
    final_rows: list[dict[str, str]], gym_sales_path: Path
) -> list[dict[str, object]]:
    gym_index = build_gym_sales_phone_index(gym_sales_path)
    report_rows: list[dict[str, object]] = []
    for row in final_rows:
        if (row.get("phones") or "").strip():
            continue
        exact_key = normalized_fio(row.get("client_fio"))
        stripped_key = normalized_fio_without_employee(row.get("client_fio"))
        phones = gym_index.get(exact_key, [])
        match_type = "exact_fio" if phones else ""
        if not phones and stripped_key != exact_key:
            phones = gym_index.get(stripped_key, [])
            match_type = "fio_without_employee_marker" if phones else ""
        report_rows.append(
            {
                "client_ref": row.get("client_ref", ""),
                "client_id": row.get("client_id", ""),
                "client_fio": row.get("client_fio", ""),
                "create_date": row.get("create_date", ""),
                "funnel_step": row.get("funnel_step", ""),
                "gym_sales_match_type": match_type or "not_found",
                "gym_sales_phones": ", ".join(phones),
            }
        )
    return report_rows


def build_multiple_subscription_reports(
    final_rows: list[dict[str, str]],
    subscriptions: list[dict[str, str]],
    cutoff: date,
) -> tuple[list[dict[str, object]], list[dict[str, object]], Counter[str], Counter[tuple[str, str]]]:
    client_by_ref = {row["client_ref"]: row for row in final_rows}
    multi_refs = {
        row["client_ref"]
        for row in final_rows
        if int_value(row.get("active_subscription_count")) > 1
    }
    active_by_client: defaultdict[str, list[dict[str, str]]] = defaultdict(list)
    for row in subscriptions:
        if row.get("is_active") == "1" and row.get("client_ref") in multi_refs:
            active_by_client[row["client_ref"]].append(row)

    detail_rows: list[dict[str, object]] = []
    summary_rows: list[dict[str, object]] = []
    duration_bins: Counter[str] = Counter()
    stage_change_counter: Counter[tuple[str, str]] = Counter()

    for client_ref, rows in sorted(active_by_client.items()):
        client = client_by_ref[client_ref]
        rows = sorted(
            rows,
            key=lambda row: (
                parse_date(row.get("end_date")) or date.min,
                parse_date(row.get("start_date")) or date.min,
                row.get("subscription_ref", ""),
            ),
        )
        earliest = rows[0]
        latest = rows[-1]
        has_booking = client.get("has_active_booking") == "1"
        earliest_days = ((parse_date(earliest["end_date"]) or cutoff) - cutoff).days
        latest_days = ((parse_date(latest["end_date"]) or cutoff) - cutoff).days
        earliest_step = funnel_step(earliest_days, has_booking)
        latest_step = funnel_step(latest_days, has_booking)
        if earliest_step != latest_step:
            stage_change_counter[(earliest_step, latest_step)] += 1

        selected_ref = client.get("active_subscription_ref", "")
        short_rows = sum(1 for row in rows if row.get("is_short_duration_active") == "1")
        for row in rows:
            duration_days = int_value(row.get("duration_days"))
            duration_bins[duration_bin(duration_days)] += 1
            end_date = parse_date(row.get("end_date"))
            days_to_end = ((end_date or cutoff) - cutoff).days
            detail_rows.append(
                {
                    "client_ref": client_ref,
                    "client_id": client.get("client_id", ""),
                    "client_fio": client.get("client_fio", ""),
                    "phones": client.get("phones", ""),
                    "active_subscription_count": client.get("active_subscription_count", ""),
                    "subscription_ref": row.get("subscription_ref", ""),
                    "subscription_name": row.get("subscription_name", ""),
                    "sale_date": row.get("sale_date", ""),
                    "start_date": row.get("start_date", ""),
                    "end_date": row.get("end_date", ""),
                    "days_to_end": days_to_end,
                    "duration_days": duration_days,
                    "duration_bin": duration_bin(duration_days),
                    "is_short_duration_active": row.get("is_short_duration_active", ""),
                    "status": row.get("status", ""),
                    "client_role_source": row.get("client_role_source", ""),
                    "is_selected_in_export": "1" if row.get("subscription_ref") == selected_ref else "0",
                }
            )

        summary_rows.append(
            {
                "client_ref": client_ref,
                "client_id": client.get("client_id", ""),
                "client_fio": client.get("client_fio", ""),
                "phones": client.get("phones", ""),
                "active_subscription_count": len(rows),
                "short_active_subscription_rows": short_rows,
                "earliest_end_date": earliest.get("end_date", ""),
                "earliest_days_to_end": earliest_days,
                "earliest_funnel_step": earliest_step,
                "earliest_subscription_name": earliest.get("subscription_name", ""),
                "latest_end_date": latest.get("end_date", ""),
                "latest_days_to_end": latest_days,
                "latest_funnel_step": latest_step,
                "latest_subscription_name": latest.get("subscription_name", ""),
                "selected_subscription_ref": selected_ref,
                "selected_subscription_name": client.get("active_subscription_name", ""),
                "selected_end_date": client.get("active_subscription_end_date", ""),
                "selected_funnel_step": client.get("funnel_step", ""),
                "stage_would_change_if_earliest_end_used": "1" if earliest_step != latest_step else "0",
                "end_spread_days": latest_days - earliest_days,
            }
        )

    return detail_rows, summary_rows, duration_bins, stage_change_counter


def build_card_reports(
    final_rows: list[dict[str, str]],
    cards: list[dict[str, str]],
    cutoff: date,
) -> tuple[list[dict[str, object]], list[dict[str, object]], list[dict[str, object]], Counter[str]]:
    client_by_ref = {row["client_ref"]: row for row in final_rows}
    multi_refs = {
        row["client_ref"]
        for row in final_rows
        if int_value(row.get("active_card_count")) > 1
    }

    detail_rows: list[dict[str, object]] = []
    anomaly_rows: list[dict[str, object]] = []
    tie_rows: list[dict[str, object]] = []
    issue_year_counter: Counter[str] = Counter()
    active_numbered_by_client: defaultdict[str, list[dict[str, str]]] = defaultdict(list)

    for row in cards:
        client_ref = row.get("client_ref", "")
        if client_ref not in client_by_ref:
            continue
        client = client_by_ref[client_ref]
        issue_date = parse_date(row.get("issue_date"))
        if row.get("is_unmarked") == "1" and row.get("plastic_card_number"):
            issue_year_counter[row.get("issue_date", "")[:4]] += 1
            active_numbered_by_client[client_ref].append(row)
        exported_card_numbers = set(split_raw_values(client.get("plastic_card_number")))
        is_included = row.get("plastic_card_number") in exported_card_numbers
        is_future = bool(issue_date and issue_date > cutoff)
        common = {
            "client_ref": client_ref,
            "client_id": client.get("client_id", ""),
            "client_fio": client.get("client_fio", ""),
            "phones": client.get("phones", ""),
            "active_card_count": client.get("active_card_count", ""),
            "card_ref": row.get("card_ref", ""),
            "plastic_card_number": row.get("plastic_card_number", ""),
            "card_status": row.get("card_status", ""),
            "is_unmarked": row.get("is_unmarked", ""),
            "issue_date": row.get("issue_date", ""),
            "is_included_in_export": "1" if is_included else "0",
            "issue_date_after_cutoff": "1" if is_future else "0",
        }
        if client_ref in multi_refs:
            detail_rows.append(common)
        if is_future and row.get("is_unmarked") == "1" and row.get("plastic_card_number"):
            anomaly_rows.append(
                {
                    **common,
                    "risk": "unmarked card issue_date is after cutoff_date",
                }
            )

    for client_ref, rows in sorted(active_numbered_by_client.items()):
        if len(rows) <= 1:
            continue
        max_issue_date = max(row.get("issue_date", "") for row in rows)
        tied_rows = [row for row in rows if row.get("issue_date", "") == max_issue_date]
        if len(tied_rows) <= 1:
            continue
        client = client_by_ref[client_ref]
        tie_rows.append(
            {
                "client_ref": client_ref,
                "client_id": client.get("client_id", ""),
                "client_fio": client.get("client_fio", ""),
                "phones": client.get("phones", ""),
                "active_card_count": client.get("active_card_count", ""),
                "max_issue_date": max_issue_date,
                "cards_on_max_issue_date": len(tied_rows),
                "exported_card_numbers": client.get("plastic_card_number", ""),
                "tied_card_numbers": ", ".join(row.get("plastic_card_number", "") for row in tied_rows),
                "tied_card_refs": ", ".join(row.get("card_ref", "") for row in tied_rows),
            }
        )

    return detail_rows, anomaly_rows, tie_rows, issue_year_counter


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff-date", default=DEFAULT_CUTOFF_DATE)
    parser.add_argument("--staging-dir", default=str(DEFAULT_STAGING_DIR))
    parser.add_argument("--output-dir", default=str(DEFAULT_OUTPUT_DIR))
    parser.add_argument("--final-clients", default=str(DEFAULT_FINAL_CLIENTS))
    parser.add_argument("--gym-sales", default=str(DEFAULT_GYM_SALES))
    args = parser.parse_args()

    cutoff = parse_date(args.cutoff_date)
    if cutoff is None:
        raise ValueError("--cutoff-date is required")
    staging_dir = Path(args.staging_dir)
    output_dir = Path(args.output_dir)

    final_rows = read_csv(Path(args.final_clients))
    subscriptions = read_csv(staging_dir / "stg_subscriptions.csv")
    cards = read_csv(staging_dir / "stg_plastic_cards.csv")

    missing_phone_recovery = build_missing_phone_recovery_rows(final_rows, Path(args.gym_sales))
    sub_detail, sub_summary, duration_bins, stage_changes = build_multiple_subscription_reports(
        final_rows, subscriptions, cutoff
    )
    card_detail, card_anomalies, card_ties, card_issue_years = build_card_reports(final_rows, cards, cutoff)

    write_csv(
        output_dir / "missing_phone_recovery_candidates.csv",
        missing_phone_recovery,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "create_date",
            "funnel_step",
            "gym_sales_match_type",
            "gym_sales_phones",
        ],
    )
    write_csv(
        output_dir / "multiple_active_subscriptions_detail.csv",
        sub_detail,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "phones",
            "active_subscription_count",
            "subscription_ref",
            "subscription_name",
            "sale_date",
            "start_date",
            "end_date",
            "days_to_end",
            "duration_days",
            "duration_bin",
            "is_short_duration_active",
            "status",
            "client_role_source",
            "is_selected_in_export",
        ],
    )
    write_csv(
        output_dir / "multiple_active_subscriptions_client_summary.csv",
        sub_summary,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "phones",
            "active_subscription_count",
            "short_active_subscription_rows",
            "earliest_end_date",
            "earliest_days_to_end",
            "earliest_funnel_step",
            "earliest_subscription_name",
            "latest_end_date",
            "latest_days_to_end",
            "latest_funnel_step",
            "latest_subscription_name",
            "selected_subscription_ref",
            "selected_subscription_name",
            "selected_end_date",
            "selected_funnel_step",
            "stage_would_change_if_earliest_end_used",
            "end_spread_days",
        ],
    )
    write_csv(
        output_dir / "multiple_active_subscription_duration_bins.csv",
        [{"duration_bin": key, "active_subscription_rows": value} for key, value in duration_bins.most_common()],
        ["duration_bin", "active_subscription_rows"],
    )
    write_csv(
        output_dir / "multiple_active_subscription_stage_change.csv",
        [
            {"earliest_funnel_step": old, "latest_funnel_step": new, "clients": count}
            for (old, new), count in stage_changes.most_common()
        ],
        ["earliest_funnel_step", "latest_funnel_step", "clients"],
    )
    write_csv(
        output_dir / "multiple_cards_detail.csv",
        card_detail,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "phones",
            "active_card_count",
            "card_ref",
            "plastic_card_number",
            "card_status",
            "is_unmarked",
            "issue_date",
            "is_included_in_export",
            "issue_date_after_cutoff",
        ],
    )
    write_csv(
        output_dir / "plastic_cards_anomalies.csv",
        card_anomalies,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "phones",
            "active_card_count",
            "card_ref",
            "plastic_card_number",
            "card_status",
            "is_unmarked",
            "issue_date",
            "is_included_in_export",
            "issue_date_after_cutoff",
            "risk",
        ],
    )
    write_csv(
        output_dir / "plastic_cards_ordering_ties.csv",
        card_ties,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "phones",
            "active_card_count",
            "max_issue_date",
            "cards_on_max_issue_date",
            "exported_card_numbers",
            "tied_card_numbers",
            "tied_card_refs",
        ],
    )
    write_csv(
        output_dir / "plastic_card_issue_year_distribution.csv",
        [{"issue_year": key, "active_card_rows": value} for key, value in card_issue_years.most_common()],
        ["issue_year", "active_card_rows"],
    )

    summary_rows = [
        {"metric": "final_clients", "value": len(final_rows)},
        {"metric": "missing_phone_clients", "value": len(missing_phone_recovery)},
        {
            "metric": "missing_phone_clients_with_gym_sales_exact_or_stripped_match",
            "value": sum(1 for row in missing_phone_recovery if row["gym_sales_match_type"] != "not_found"),
        },
        {"metric": "multiple_active_subscription_clients", "value": len(sub_summary)},
        {"metric": "multiple_active_subscription_rows", "value": len(sub_detail)},
        {
            "metric": "multiple_active_subscription_clients_where_stage_changes_if_earliest_used",
            "value": sum(1 for row in sub_summary if row["stage_would_change_if_earliest_end_used"] == "1"),
        },
        {
            "metric": "short_subscription_rows_among_multiple_active",
            "value": sum(1 for row in sub_detail if row["is_short_duration_active"] == "1"),
        },
        {"metric": "multiple_card_detail_rows", "value": len(card_detail)},
        {"metric": "plastic_card_future_issue_date_anomalies", "value": len(card_anomalies)},
        {"metric": "plastic_card_ordering_tie_clients", "value": len(card_ties)},
    ]
    write_csv(output_dir / "data_quality_risk_summary.csv", summary_rows, ["metric", "value"])

    print(f"missing_phone_recovery_rows={len(missing_phone_recovery)}")
    print(f"multiple_active_subscription_clients={len(sub_summary)}")
    print(f"multiple_active_subscription_rows={len(sub_detail)}")
    print(
        "stage_change_if_earliest_used="
        f"{sum(1 for row in sub_summary if row['stage_would_change_if_earliest_end_used'] == '1')}"
    )
    print(f"multiple_cards_detail_rows={len(card_detail)}")
    print(f"plastic_card_future_issue_date_anomalies={len(card_anomalies)}")
    print(f"plastic_card_ordering_tie_clients={len(card_ties)}")
    print(f"wrote={output_dir}")


if __name__ == "__main__":
    main()
