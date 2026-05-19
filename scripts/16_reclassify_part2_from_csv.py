#!/usr/bin/env python3
"""Recompute Part 2 funnels from staging CSVs after product reclassification.

This script is intentionally SQL-free. It starts from the stage CSVs produced by
`scripts/11_export_part2_stage.py`, applies product-class decisions from a CSV,
and rewrites the derived stage tables that drive XLSX generation.
"""

from __future__ import annotations

import argparse
import csv
import shutil
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ALLOWED_CLASSES = {"full_subscription", "trial_or_guest", "other_sale", "unknown_review_required"}
FINAL_FUNNEL_FIELDS = [
    "client_ref",
    "client_id",
    "client_fio",
    "phones",
    "email",
    "funnel",
    "funnel_step",
    "budget",
    "create_date",
    "create_date_source",
    "manager",
    "normalized_club",
    "club_source",
    "selected_subscription_ref",
    "selected_subscription_name",
    "selected_subscription_start_date",
    "selected_subscription_end_date",
    "selected_subscription_sale_date",
    "days_to_end",
    "days_since_end",
    "selected_card_number",
    "selected_card_ref",
    "active_full_subscription_count",
    "finished_full_subscription_count",
    "full_subscription_count",
    "trial_or_guest_sale_count",
    "selection_reason",
    "validation_status",
    "cutoff_date",
]


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
        for row in rows:
            writer.writerow({field: row.get(field, "") for field in fieldnames})


def int_value(value: object, default: int = 0) -> int:
    try:
        if value in ("", None):
            return default
        return int(float(str(value)))
    except ValueError:
        return default


def parse_date(value: str | None) -> date | None:
    if not value:
        return None
    return datetime.strptime(value[:10], "%Y-%m-%d").date()


def date_key(value: str | None) -> date:
    return parse_date(value) or date.min


def date_le(left: str | None, right: date) -> bool:
    parsed = parse_date(left)
    return bool(parsed and parsed <= right)


def date_ge(left: str | None, right: date) -> bool:
    parsed = parse_date(left)
    return bool(parsed and parsed >= right)


def date_lt(left: str | None, right: date) -> bool:
    parsed = parse_date(left)
    return bool(parsed and parsed < right)


def days_between(left: str | None, right: date) -> str:
    parsed = parse_date(left)
    return str((parsed - right).days) if parsed else ""


def coalesce(*values: str | None) -> str:
    for value in values:
        if value not in (None, ""):
            return str(value)
    return ""


def load_decisions(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}

    decisions: dict[str, dict[str, str]] = {}
    for row in read_csv(path):
        approved = (row.get("approved_product_class") or row.get("new_product_class") or "").strip()
        if not approved or approved.lower() in {"keep", "current"}:
            continue
        if approved not in ALLOWED_CLASSES:
            raise ValueError(
                f"Invalid approved_product_class={approved!r} for product_code={row.get('product_code', '')}. "
                f"Allowed: {', '.join(sorted(ALLOWED_CLASSES))}"
            )
        product_ref = (row.get("product_ref") or "").strip()
        product_code = (row.get("product_code") or "").strip()
        if not product_ref and not product_code:
            raise ValueError(f"Decision row has no product_ref/product_code: {row}")
        key = product_ref or f"code:{product_code}"
        if key in decisions and decisions[key]["approved_product_class"] != approved:
            raise ValueError(f"Conflicting decisions for {key}")
        decisions[key] = {**row, "approved_product_class": approved}
    return decisions


def decision_for_product(product: dict[str, str], decisions: dict[str, dict[str, str]]) -> dict[str, str] | None:
    return decisions.get(product.get("product_ref", "")) or decisions.get(f"code:{product.get('product_code', '')}")


def write_decision_template(source_reports_dir: Path, output_path: Path) -> None:
    review_path = source_reports_dir / "product_classification_review_report.csv"
    if not review_path.exists():
        raise FileNotFoundError(f"Missing review report: {review_path}")
    rows = read_csv(review_path)
    bucket_order = {
        "unknown_review_required": 0,
        "other_sale": 1,
        "full_subscription": 2,
    }
    rows.sort(
        key=lambda row: (
            bucket_order.get(row.get("auto_classification", ""), 9),
            -int_value(row.get("observed_clients")),
            row.get("product_name", ""),
        )
    )
    output_rows = []
    for row in rows:
        current_class = row.get("auto_classification", "")
        if current_class == "unknown_review_required":
            decision_bucket = "needs_business_decision_can_change_funnels"
        elif current_class == "other_sale":
            decision_bucket = "review_other_sale_usually_no_funnel_effect"
        else:
            decision_bucket = "optional_full_subscription_review"
        output_rows.append(
            {
                "product_ref": row.get("product_ref", ""),
                "product_code": row.get("product_code", ""),
                "product_name": row.get("product_name", ""),
                "current_product_class": current_class,
                "decision_bucket": decision_bucket,
                "approved_product_class": "",
                "decision_note": "",
                "observed_clients": row.get("observed_clients", ""),
                "observed_sales": row.get("observed_sales", ""),
                "observed_subscription_rows": row.get("observed_subscription_rows", ""),
                "min_duration_days": row.get("min_duration_days", ""),
                "max_duration_days": row.get("max_duration_days", ""),
                "review_reason": row.get("review_reason", ""),
                "recommended_action": row.get("recommended_action", ""),
            }
        )
    write_csv(
        output_path,
        output_rows,
        [
            "product_ref",
            "product_code",
            "product_name",
            "current_product_class",
            "decision_bucket",
            "approved_product_class",
            "decision_note",
            "observed_clients",
            "observed_sales",
            "observed_subscription_rows",
            "min_duration_days",
            "max_duration_days",
            "review_reason",
            "recommended_action",
        ],
    )


def reclassify_products(
    products: list[dict[str, str]],
    decisions: dict[str, dict[str, str]],
) -> tuple[list[dict[str, str]], dict[str, str], list[dict[str, str]]]:
    product_class_by_ref: dict[str, str] = {}
    applied_rows: list[dict[str, str]] = []
    reclassified: list[dict[str, str]] = []

    for product in products:
        row = dict(product)
        old_class = row.get("product_class", "")
        decision = decision_for_product(row, decisions)
        new_class = decision["approved_product_class"] if decision else old_class
        note = (decision or {}).get("decision_note", "")

        if decision:
            row["product_class"] = new_class
            row["classification_reason"] = f"manual csv decision: {old_class} -> {new_class}" + (f"; {note}" if note else "")
            row["needs_manual_review"] = "1" if new_class == "unknown_review_required" else "0"
            applied_rows.append(
                {
                    "product_ref": row.get("product_ref", ""),
                    "product_code": row.get("product_code", ""),
                    "product_name": row.get("product_name", ""),
                    "old_product_class": old_class,
                    "new_product_class": new_class,
                    "decision_note": note,
                }
            )

        row["is_full_subscription_candidate"] = "1" if row.get("product_class") == "full_subscription" else "0"
        row["is_trial_or_guest_candidate"] = "1" if row.get("product_class") == "trial_or_guest" else "0"
        if row.get("product_class") == "unknown_review_required":
            row["needs_manual_review"] = "1"

        product_class_by_ref[row.get("product_ref", "")] = row.get("product_class", "")
        reclassified.append(row)

    return reclassified, product_class_by_ref, applied_rows


def reclassify_subscriptions(
    rows: list[dict[str, str]],
    product_class_by_ref: dict[str, str],
    cutoff: date,
) -> list[dict[str, str]]:
    output = []
    for row in rows:
        item = dict(row)
        product_class = product_class_by_ref.get(item.get("product_ref", ""), item.get("product_class", "other_sale"))
        item["product_class"] = product_class
        item["is_full_subscription"] = "1" if product_class == "full_subscription" else "0"
        item["is_trial_or_guest"] = "1" if product_class == "trial_or_guest" else "0"
        is_full = product_class == "full_subscription"
        item["is_active_on_cutoff"] = "1" if is_full and date_le(item.get("sale_date"), cutoff) and date_ge(item.get("end_date"), cutoff) else "0"
        item["is_finished_before_cutoff"] = "1" if is_full and date_le(item.get("sale_date"), cutoff) and date_lt(item.get("end_date"), cutoff) else "0"
        item["days_to_end"] = days_between(item.get("end_date"), cutoff)
        end = parse_date(item.get("end_date"))
        item["days_since_end"] = str((cutoff - end).days) if end else ""
        output.append(item)
    return output


def reclassify_sales(rows: list[dict[str, str]], product_class_by_ref: dict[str, str]) -> list[dict[str, str]]:
    output = []
    for row in rows:
        item = dict(row)
        product_ref = item.get("product_ref", "")
        if product_ref:
            item["product_class"] = product_class_by_ref.get(product_ref, item.get("product_class", "other_sale"))
        else:
            item["product_class"] = item.get("product_class") or "other_sale"
        output.append(item)
    return output


def build_client_history(
    old_history_rows: list[dict[str, str]],
    sales: list[dict[str, str]],
    subscriptions: list[dict[str, str]],
    cutoff: date,
) -> list[dict[str, str]]:
    sales_by_client: defaultdict[str, list[dict[str, str]]] = defaultdict(list)
    for sale in sales:
        if date_le(sale.get("sale_date"), cutoff):
            sales_by_client[sale.get("client_ref", "")].append(sale)

    subs_by_client: defaultdict[str, list[dict[str, str]]] = defaultdict(list)
    for sub in subscriptions:
        if date_le(sub.get("sale_date"), cutoff):
            subs_by_client[sub.get("client_ref", "")].append(sub)

    output = []
    for old in old_history_rows:
        client_ref = old.get("client_ref", "")
        client_sales = sales_by_client.get(client_ref, [])
        client_subs = subs_by_client.get(client_ref, [])
        first_sale = min((sale.get("sale_date", "") for sale in client_sales if sale.get("sale_date")), default="")
        first_trial = min(
            (sale.get("sale_date", "") for sale in client_sales if sale.get("product_class") == "trial_or_guest" and sale.get("sale_date")),
            default="",
        )
        first_non_full = min(
            (sale.get("sale_date", "") for sale in client_sales if sale.get("product_class") != "full_subscription" and sale.get("sale_date")),
            default="",
        )
        last_sale = max(
            client_sales,
            key=lambda sale: (date_key(sale.get("sale_date")), sale.get("sale_ref", "")),
            default={},
        )
        full_subs = [sub for sub in client_subs if sub.get("is_full_subscription") == "1"]
        active_full = [sub for sub in full_subs if sub.get("is_active_on_cutoff") == "1"]
        finished_full = [sub for sub in full_subs if sub.get("is_finished_before_cutoff") == "1"]
        trial_count = sum(1 for sale in client_sales if sale.get("product_class") == "trial_or_guest")

        row = dict(old)
        row.update(
            {
                "first_sale_date": first_sale,
                "first_sale_source": "first_sale" if first_sale else "",
                "has_any_sale": "1" if client_sales else "0",
                "has_any_full_subscription": "1" if full_subs else "0",
                "has_active_full_subscription": "1" if active_full else "0",
                "has_finished_full_subscription": "1" if finished_full else "0",
                "full_subscription_count": str(len(full_subs)),
                "active_full_subscription_count": str(len(active_full)),
                "finished_full_subscription_count": str(len(finished_full)),
                "trial_or_guest_sale_count": str(trial_count),
                "first_trial_or_guest_product_date": first_trial,
                "first_non_full_sale_date": first_non_full,
                "last_sale_date": last_sale.get("sale_date", ""),
                "last_sale_product_name": last_sale.get("product_name", ""),
                "last_sale_club": last_sale.get("normalized_club", ""),
                "last_sale_club_source": last_sale.get("club_source", ""),
            }
        )
        output.append(row)
    return output


def build_subscription_candidates(subscriptions: list[dict[str, str]]) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    groups: defaultdict[tuple[str, str], list[dict[str, str]]] = defaultdict(list)
    for sub in subscriptions:
        if sub.get("is_full_subscription") != "1" or not date_le(sub.get("sale_date"), date.max):
            continue
        candidate_for = ""
        if sub.get("is_active_on_cutoff") == "1":
            candidate_for = "active"
        elif sub.get("is_finished_before_cutoff") == "1":
            candidate_for = "reactivation"
        if candidate_for:
            groups[(sub.get("client_ref", ""), candidate_for)].append(sub)

    candidates: list[dict[str, str]] = []
    selected: list[dict[str, str]] = []
    for (client_ref, candidate_for), items in groups.items():
        ranked = sorted(
            items,
            key=lambda sub: (
                date_key(sub.get("end_date")),
                date_key(sub.get("start_date")),
                date_key(sub.get("sale_date")),
                sub.get("subscription_ref", ""),
            ),
            reverse=True,
        )
        candidate_count = len(ranked)
        for index, sub in enumerate(ranked, start=1):
            selected_flag = index == 1
            candidates.append(
                {
                    "client_ref": client_ref,
                    "client_id": sub.get("client_id", ""),
                    "subscription_ref": sub.get("subscription_ref", ""),
                    "candidate_for_funnel": candidate_for,
                    "rank_number": str(index),
                    "auto_rank_reason": "end_date DESC, start_date DESC, sale_date DESC, subscription_ref DESC",
                    "manual_override_applied": "0",
                    "selection_status": "selected" if selected_flag else "not_selected",
                    "selection_reason": "top-ranked candidate" if selected_flag else "lower-ranked candidate",
                    "candidate_count": str(candidate_count),
                }
            )
            if selected_flag:
                selected.append(
                    {
                        "client_ref": client_ref,
                        "selected_subscription_ref": sub.get("subscription_ref", ""),
                        "selected_for_funnel": candidate_for,
                        "selected_subscription_name": sub.get("subscription_name", ""),
                        "selected_sale_date": sub.get("sale_date", ""),
                        "selected_start_date": sub.get("start_date", ""),
                        "selected_end_date": sub.get("end_date", ""),
                        "selected_duration_days": sub.get("duration_days", ""),
                        "days_to_end": sub.get("days_to_end", ""),
                        "days_since_end": sub.get("days_since_end", ""),
                        "selected_raw_club": sub.get("raw_club", ""),
                        "selected_normalized_club": sub.get("normalized_club", ""),
                        "selected_club_source": sub.get("club_source", ""),
                        "selection_reason": "top-ranked candidate",
                        "manual_override_applied": "0",
                        "candidate_count": str(candidate_count),
                    }
                )
    candidates.sort(key=lambda row: (row["client_ref"], row["candidate_for_funnel"], int_value(row["rank_number"])))
    selected.sort(key=lambda row: (row["client_ref"], row["selected_for_funnel"]))
    return candidates, selected


def stage_for_active(days_to_end: str) -> str:
    days = int_value(days_to_end, -999999)
    if 31 <= days <= 60:
        return "60-31 день до окончания"
    if 8 <= days <= 30:
        return "30-8 дней до окончания"
    if 0 <= days <= 7:
        return "7-0 день до окончания"
    return "Действующие клиенты"


def stage_for_reactivation(days_since_end: str) -> str:
    days = int_value(days_since_end, 999999)
    if 1 <= days <= 6:
        return "1-6 дней"
    if 7 <= days <= 29:
        return "7-29 дней"
    if 30 <= days <= 59:
        return "30-59 дней"
    if 60 <= days <= 89:
        return "60-89 дней"
    return "более 90 дней"


def build_validation_status(row: dict[str, str], active_candidate_count: str, react_candidate_count: str, selected_card: dict[str, str]) -> str:
    status = []
    if not (row.get("client_fio") or "").strip():
        status.append("missing_fio")
    if not (row.get("phones") or "").strip():
        status.append("missing_phone")
    if not (row.get("normalized_club") or "").strip():
        status.append("missing_club")
    if not (selected_card.get("selected_card_number") or "").strip():
        status.append("missing_card")
    if row.get("funnel") == "Действующие клиенты" and int_value(active_candidate_count) > 1:
        status.append("multiple_active_subscriptions")
    if row.get("funnel") == "Реактивация" and int_value(react_candidate_count) > 1:
        status.append("multiple_finished_subscriptions")
    if int_value(selected_card.get("active_card_count")) > 1:
        status.append("multiple_cards")
    if row.get("funnel") == "Реактивация" and int_value(row.get("days_since_end"), 1) <= 0:
        status.append("reactivation_boundary_anomaly")
    if row.get("client_marked") == "1":
        status.append("client_marked")
    return ";".join(status) + (";" if status else "ok")


def build_final_rows(
    history_rows: list[dict[str, str]],
    selected_subscriptions: list[dict[str, str]],
    selected_cards: list[dict[str, str]],
    cutoff: date,
) -> list[dict[str, str]]:
    selected_by_client_funnel = {(row["client_ref"], row["selected_for_funnel"]): row for row in selected_subscriptions}
    cards_by_client = {row["client_ref"]: row for row in selected_cards}
    output = []

    for history in history_rows:
        has_active = history.get("has_active_full_subscription") == "1"
        has_any_full = history.get("has_any_full_subscription") == "1"
        funnel = "Действующие клиенты" if has_active else ("Реактивация" if has_any_full else "Новые заявки")
        active_sub = selected_by_client_funnel.get((history.get("client_ref", ""), "active"), {})
        react_sub = selected_by_client_funnel.get((history.get("client_ref", ""), "reactivation"), {})
        selected_card = cards_by_client.get(history.get("client_ref", ""), {})

        if funnel == "Действующие клиенты":
            selected_sub = active_sub
            funnel_step = stage_for_active(active_sub.get("days_to_end", ""))
            create_date = coalesce(history.get("first_sale_date"), active_sub.get("selected_sale_date"), history.get("client_created_at"), cutoff.isoformat())
            create_date_source = "first_sale" if history.get("first_sale_date") else ("selected_subscription_sale_date" if active_sub.get("selected_sale_date") else "client_created_at_fallback")
            normalized_club = active_sub.get("selected_normalized_club", "")
            club_source = active_sub.get("selected_club_source", "")
            days_to_end = active_sub.get("days_to_end", "")
            days_since_end = active_sub.get("days_since_end", "")
            selection_reason = active_sub.get("selection_reason", "")
        elif funnel == "Реактивация":
            selected_sub = react_sub
            funnel_step = stage_for_reactivation(react_sub.get("days_since_end", ""))
            create_date = coalesce(history.get("first_sale_date"), react_sub.get("selected_sale_date"), history.get("client_created_at"), cutoff.isoformat())
            create_date_source = "first_sale" if history.get("first_sale_date") else ("selected_subscription_sale_date" if react_sub.get("selected_sale_date") else "client_created_at_fallback")
            normalized_club = react_sub.get("selected_normalized_club", "")
            club_source = react_sub.get("selected_club_source", "")
            days_to_end = react_sub.get("days_to_end", "")
            days_since_end = react_sub.get("days_since_end", "")
            selection_reason = react_sub.get("selection_reason", "")
        else:
            selected_sub = {}
            funnel_step = "Неразобранные"
            if history.get("first_trial_or_guest_product_date"):
                create_date = history.get("first_trial_or_guest_product_date", "")
                create_date_source = "first_trial_or_guest_product"
            elif history.get("first_non_full_sale_date"):
                create_date = history.get("first_non_full_sale_date", "")
                create_date_source = "first_non_full_sale_requires_review"
            else:
                create_date = coalesce(history.get("client_created_at"), cutoff.isoformat())
                create_date_source = "client_created_at_no_sales"
            normalized_club = coalesce(history.get("last_sale_club"), history.get("client_normalized_club"), "Клуб не определен (fallback)")
            club_source = coalesce(history.get("last_sale_club_source"), history.get("client_club_source"), "fallback_no_sale_or_client_club")
            days_to_end = ""
            days_since_end = ""
            selection_reason = "no full subscription"

        row = {
            "client_ref": history.get("client_ref", ""),
            "client_id": history.get("client_id", ""),
            "client_fio": history.get("client_fio", ""),
            "phones": history.get("phones", ""),
            "email": history.get("email", ""),
            "funnel": funnel,
            "funnel_step": funnel_step,
            "budget": "0",
            "create_date": create_date,
            "create_date_source": create_date_source,
            "manager": "",
            "normalized_club": normalized_club,
            "club_source": club_source,
            "selected_subscription_ref": selected_sub.get("selected_subscription_ref", ""),
            "selected_subscription_name": selected_sub.get("selected_subscription_name", ""),
            "selected_subscription_start_date": selected_sub.get("selected_start_date", ""),
            "selected_subscription_end_date": selected_sub.get("selected_end_date", ""),
            "selected_subscription_sale_date": selected_sub.get("selected_sale_date", ""),
            "days_to_end": days_to_end,
            "days_since_end": days_since_end,
            "selected_card_number": selected_card.get("selected_card_number", ""),
            "selected_card_ref": selected_card.get("selected_card_ref", ""),
            "active_full_subscription_count": history.get("active_full_subscription_count", "0"),
            "finished_full_subscription_count": history.get("finished_full_subscription_count", "0"),
            "full_subscription_count": history.get("full_subscription_count", "0"),
            "trial_or_guest_sale_count": history.get("trial_or_guest_sale_count", "0"),
            "selection_reason": selection_reason,
            "cutoff_date": cutoff.isoformat(),
            "client_marked": history.get("client_marked", "0"),
        }
        row["validation_status"] = build_validation_status(
            row,
            active_sub.get("candidate_count", "0"),
            react_sub.get("candidate_count", "0"),
            selected_card,
        )
        output.append(row)
    return output


def write_product_reports(products: list[dict[str, str]], reports_dir: Path) -> None:
    observed = [
        row
        for row in products
        if int_value(row.get("observed_sale_rows")) > 0
        or int_value(row.get("observed_subscription_rows")) > 0
        or row.get("is_full_subscription_candidate") == "1"
        or row.get("is_trial_or_guest_candidate") == "1"
        or row.get("needs_manual_review") == "1"
    ]
    preflight_rows = []
    report_rows = []
    review_rows = []
    for row in observed:
        product_class = row.get("product_class", "")
        preflight_rows.append(
            {
                **row,
                "auto_classification": product_class,
                "is_unknown": "1" if product_class == "unknown_review_required" else "0",
                "observed_sales": row.get("observed_sale_rows", ""),
            }
        )
        report_rows.append(
            {
                **row,
                "is_full_subscription": "1" if product_class == "full_subscription" else "0",
                "is_trial_or_guest": "1" if product_class == "trial_or_guest" else "0",
                "observed_sales": row.get("observed_sale_rows", ""),
            }
        )
        needs_review = row.get("needs_manual_review") == "1" or product_class == "unknown_review_required"
        if needs_review:
            recommended = "keep_full_subscription_unless_customer_says_otherwise" if product_class == "full_subscription" and "замороз" in (row.get("product_name") or "").lower() else "manual_review"
            review_rows.append(
                {
                    **row,
                    "auto_classification": product_class,
                    "observed_sales": row.get("observed_sale_rows", ""),
                    "review_reason": row.get("classification_reason", ""),
                    "recommended_action": recommended,
                }
            )

    write_csv(
        reports_dir / "product_classification_preflight.csv",
        preflight_rows,
        [
            "product_ref",
            "product_code",
            "product_name",
            "auto_classification",
            "is_full_subscription_candidate",
            "is_trial_or_guest_candidate",
            "is_unknown",
            "observed_clients",
            "observed_sales",
            "observed_subscription_rows",
            "min_duration_days",
            "max_duration_days",
            "classification_reason",
            "needs_manual_review",
        ],
    )
    write_csv(
        reports_dir / "product_classification_report.csv",
        report_rows,
        [
            "product_ref",
            "product_code",
            "product_name",
            "product_class",
            "is_full_subscription",
            "is_trial_or_guest",
            "observed_clients",
            "observed_sales",
            "observed_subscription_rows",
            "min_duration_days",
            "max_duration_days",
            "classification_reason",
        ],
    )
    write_csv(
        reports_dir / "product_classification_review_report.csv",
        review_rows,
        [
            "product_ref",
            "product_code",
            "product_name",
            "observed_clients",
            "observed_sales",
            "observed_subscription_rows",
            "min_duration_days",
            "max_duration_days",
            "auto_classification",
            "review_reason",
            "recommended_action",
        ],
    )


def write_impact_report(
    reports_dir: Path,
    before_rows: list[dict[str, str]],
    after_rows: list[dict[str, str]],
    applied_rows: list[dict[str, str]],
) -> None:
    before_by_ref = {row["client_ref"]: row for row in before_rows}
    impact_rows = []
    for after in after_rows:
        before = before_by_ref.get(after.get("client_ref", ""), {})
        changed = []
        for field in ["funnel", "funnel_step", "selected_subscription_ref", "create_date_source", "normalized_club"]:
            if before.get(field, "") != after.get(field, ""):
                changed.append(field)
        if changed:
            impact_rows.append(
                {
                    "client_ref": after.get("client_ref", ""),
                    "client_id": after.get("client_id", ""),
                    "client_fio": after.get("client_fio", ""),
                    "before_funnel": before.get("funnel", ""),
                    "after_funnel": after.get("funnel", ""),
                    "before_step": before.get("funnel_step", ""),
                    "after_step": after.get("funnel_step", ""),
                    "before_subscription": before.get("selected_subscription_ref", ""),
                    "after_subscription": after.get("selected_subscription_ref", ""),
                    "changed_fields": ";".join(changed),
                }
            )

    write_csv(
        reports_dir / "product_reclassification_applied.csv",
        applied_rows,
        ["product_ref", "product_code", "product_name", "old_product_class", "new_product_class", "decision_note"],
    )
    write_csv(
        reports_dir / "product_reclassification_funnel_impact.csv",
        impact_rows,
        [
            "client_ref",
            "client_id",
            "client_fio",
            "before_funnel",
            "after_funnel",
            "before_step",
            "after_step",
            "before_subscription",
            "after_subscription",
            "changed_fields",
        ],
    )

    before_counts = Counter(row.get("funnel", "") for row in before_rows)
    after_counts = Counter(row.get("funnel", "") for row in after_rows)
    changed_funnel = sum(1 for row in impact_rows if "funnel" in row["changed_fields"].split(";"))
    lines = [
        "# Product Reclassification Impact",
        "",
        f"applied product decisions: `{len(applied_rows)}`",
        f"clients with any derived-field change: `{len(impact_rows)}`",
        f"clients with funnel change: `{changed_funnel}`",
        "",
        "## Funnel Counts",
        "",
        "| funnel | before | after | delta |",
        "| --- | ---: | ---: | ---: |",
    ]
    for funnel in sorted(set(before_counts) | set(after_counts)):
        lines.append(f"| {funnel} | {before_counts[funnel]} | {after_counts[funnel]} | {after_counts[funnel] - before_counts[funnel]} |")
    lines.append("")
    (reports_dir / "product_reclassification_impact.md").write_text("\n".join(lines), encoding="utf-8")


def copy_static_stage_files(source_stage_dir: Path, output_stage_dir: Path) -> None:
    for name in [
        "stg_clients.csv",
        "stg_client_contacts.csv",
        "stg_plastic_cards.csv",
        "selected_cards.csv",
        "staging_run_metadata.csv",
    ]:
        source = source_stage_dir / name
        if source.exists():
            shutil.copy2(source, output_stage_dir / name)


def copy_static_reports(source_reports_dir: Path, output_reports_dir: Path) -> None:
    for name in ["club_reference_candidates.csv", "club_link_candidates.csv"]:
        source = source_reports_dir / name
        if source.exists():
            shutil.copy2(source, output_reports_dir / name)


def reclassify(args: argparse.Namespace) -> None:
    cutoff = parse_date(args.cutoff_date)
    if cutoff is None:
        raise ValueError("--cutoff-date is required")

    source_stage_dir = as_abs(args.source_stage_dir)
    source_reports_dir = as_abs(args.source_reports_dir)
    output_stage_dir = as_abs(args.output_stage_dir)
    output_reports_dir = as_abs(args.output_reports_dir)
    decisions_path = as_abs(args.decisions)

    output_stage_dir.mkdir(parents=True, exist_ok=True)
    output_reports_dir.mkdir(parents=True, exist_ok=True)

    decisions = load_decisions(decisions_path)
    products = read_csv(source_stage_dir / "stg_products.csv")
    subscriptions = read_csv(source_stage_dir / "stg_subscriptions_all.csv")
    sales = read_csv(source_stage_dir / "stg_sales_all.csv")
    history = read_csv(source_stage_dir / "client_history_summary.csv")
    selected_cards = read_csv(source_stage_dir / "selected_cards.csv")
    before_final = read_csv(source_stage_dir / "final_funnel_clients.csv")

    products, product_class_by_ref, applied_rows = reclassify_products(products, decisions)
    subscriptions = reclassify_subscriptions(subscriptions, product_class_by_ref, cutoff)
    sales = reclassify_sales(sales, product_class_by_ref)
    history = build_client_history(history, sales, subscriptions, cutoff)
    candidates, selected_subscriptions = build_subscription_candidates(subscriptions)
    final_rows = build_final_rows(history, selected_subscriptions, selected_cards, cutoff)

    copy_static_stage_files(source_stage_dir, output_stage_dir)
    copy_static_reports(source_reports_dir, output_reports_dir)
    write_csv(output_stage_dir / "stg_products.csv", products, list(products[0].keys()))
    write_csv(output_stage_dir / "stg_subscriptions_all.csv", subscriptions, list(subscriptions[0].keys()))
    write_csv(output_stage_dir / "stg_sales_all.csv", sales, list(sales[0].keys()))
    write_csv(output_stage_dir / "client_history_summary.csv", history, list(history[0].keys()))
    write_csv(output_stage_dir / "subscription_candidates_ranked.csv", candidates, list(candidates[0].keys()) if candidates else [
        "client_ref",
        "client_id",
        "subscription_ref",
        "candidate_for_funnel",
        "rank_number",
        "auto_rank_reason",
        "manual_override_applied",
        "selection_status",
        "selection_reason",
        "candidate_count",
    ])
    write_csv(output_stage_dir / "selected_subscriptions.csv", selected_subscriptions, list(selected_subscriptions[0].keys()) if selected_subscriptions else [
        "client_ref",
        "selected_subscription_ref",
        "selected_for_funnel",
        "selected_subscription_name",
        "selected_sale_date",
        "selected_start_date",
        "selected_end_date",
        "selected_duration_days",
        "days_to_end",
        "days_since_end",
        "selected_raw_club",
        "selected_normalized_club",
        "selected_club_source",
        "selection_reason",
        "manual_override_applied",
        "candidate_count",
    ])
    write_csv(output_stage_dir / "final_funnel_clients.csv", final_rows, FINAL_FUNNEL_FIELDS)
    write_product_reports(products, output_reports_dir)
    write_impact_report(output_reports_dir, before_final, final_rows, applied_rows)

    unresolved = [
        row for row in products
        if row.get("product_class") == "unknown_review_required" or row.get("needs_manual_review") == "1"
    ]
    if args.fail_on_unresolved_review and unresolved:
        raise SystemExit(f"Unresolved product review rows remain: {len(unresolved)}")

    print(f"applied_product_decisions={len(applied_rows)}")
    print(f"unresolved_product_review_rows={len(unresolved)}")
    print(f"stage_dir={output_stage_dir.relative_to(ROOT)}")
    print(f"reports_dir={output_reports_dir.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff-date", default="2026-04-29")
    parser.add_argument("--source-stage-dir", default=str(ROOT / "output" / "part2_20260429" / "staging"))
    parser.add_argument("--source-reports-dir", default=str(ROOT / "output" / "part2_20260429" / "reports"))
    parser.add_argument("--output-stage-dir", default=str(ROOT / "output" / "part2_20260429_reclassified" / "staging"))
    parser.add_argument("--output-reports-dir", default=str(ROOT / "output" / "part2_20260429_reclassified" / "reports"))
    parser.add_argument("--decisions", default=str(ROOT / "config" / "product_reclassification_decisions.csv"))
    parser.add_argument("--write-decision-template", action="store_true")
    parser.add_argument("--fail-on-unresolved-review", action="store_true")
    args = parser.parse_args()
    if args.write_decision_template:
        write_decision_template(as_abs(args.source_reports_dir), as_abs(args.decisions))
        print(f"decision_template={as_abs(args.decisions).relative_to(ROOT)}")
        raise SystemExit(0)
    return args


def main() -> None:
    reclassify(parse_args())


if __name__ == "__main__":
    main()
