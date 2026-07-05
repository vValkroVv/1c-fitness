#!/usr/bin/env python3
"""Compare the three new-changes problem areas on old and 20260630 exports."""

from __future__ import annotations

import csv
from collections import Counter, defaultdict
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parents[1]

OLD_OWNER_DIR = ROOT / "output/20251115_0800_fix_owner"
NEW_OWNER_DIR = ROOT / "output/20260630_fix_owner"
OLD_IMPORT_DIR = ROOT / "output/20251115_0800_fix_owner_new_import"
NEW_IMPORT_DIR = ROOT / "output/20260630_fix_owner_new_import"

OUTPUT_DIR = ROOT / "output/20260630_problem_status_analysis"
DOC_PATH = ROOT / "docs/new-backup-30-06/07_new_changes_problem_status.md"

OLD_CUTOFF_DATE = "2026-05-25"
OLD_CUTOFF_DATETIME = "2026-05-25 08:00:00"
NEW_CUTOFF_DATE = "2026-06-30"
NEW_CUTOFF_DATETIME = "2026-06-30 23:27:03"


@dataclass(frozen=True)
class ActiveProblemSpec:
    key: str
    title: str
    old_doc_count: int
    old_doc_clients: int
    predicate: Callable[[dict[str, str], str], bool]


def read_csv(path: Path, delimiter: str = ",") -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        return list(csv.DictReader(handle, delimiter=delimiter))


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def decimal_value(value: str | None) -> Decimal:
    text = (value or "").replace(" ", "").replace(",", ".").strip()
    if not text:
        return Decimal("0")
    try:
        return Decimal(text)
    except InvalidOperation:
        return Decimal("0")


def is_truthy(value: str | None) -> bool:
    return (value or "").strip().lower() in {"1", "true", "yes", "да"}


def is_not_finished(row: dict[str, str], cutoff_date: str) -> bool:
    return (row.get("end_date") or "") >= cutoff_date


def is_no_payment_cash_active(row: dict[str, str], cutoff_date: str) -> bool:
    return (
        row.get("_product_class") == "full_subscription"
        and is_not_finished(row, cutoff_date)
        and decimal_value(row.get("price")) > 0
        and (row.get("type_of_payment") or "") == "наличные"
        and not (row.get("_payment_match_source") or "").strip()
    )


def is_zero_price_direct_active_full(row: dict[str, str], cutoff_date: str) -> bool:
    return (
        row.get("_product_class") == "full_subscription"
        and (row.get("activation_date") or "") <= cutoff_date
        and is_not_finished(row, cutoff_date)
        and decimal_value(row.get("price")) == 0
        and (row.get("_payment_match_source") or "").startswith("direct_doc152")
        and decimal_value(row.get("_document131_posted_unmarked_refund_count")) == 0
        and bool((row.get("type_of_payment") or "").strip())
    )


def is_non_named_payment_left_active(row: dict[str, str], cutoff_date: str) -> bool:
    return (
        is_not_finished(row, cutoff_date)
        and decimal_value(row.get("payment_left")) > 0
        and "рассроч" not in (row.get("contract_name") or "").lower()
    )


ACTIVE_PROBLEMS = [
    ActiveProblemSpec(
        key="active_no_payment_cash",
        title="active full: price>0, платеж не найден, type_of_payment=наличные",
        old_doc_count=198,
        old_doc_clients=181,
        predicate=is_no_payment_cash_active,
    ),
    ActiveProblemSpec(
        key="active_zero_price_direct_full",
        title="active full: price=0, direct payment есть, возврата нет",
        old_doc_count=44,
        old_doc_clients=44,
        predicate=is_zero_price_direct_active_full,
    ),
    ActiveProblemSpec(
        key="active_non_named_payment_left",
        title="active/non-finished: payment_left>0 без слова рассрочка",
        old_doc_count=297,
        old_doc_clients=296,
        predicate=is_non_named_payment_left_active,
    ),
]


def selected(rows: list[dict[str, str]], spec: ActiveProblemSpec, cutoff_date: str) -> list[dict[str, str]]:
    return [row for row in rows if spec.predicate(row, cutoff_date)]


def classify_no_longer_problem(key: str, row: dict[str, str] | None, cutoff_date: str) -> str:
    if row is None:
        return "removed_from_new_membership_export"

    if key == "active_no_payment_cash":
        if row.get("_product_class") != "full_subscription":
            return "product_class_changed"
        if not is_not_finished(row, cutoff_date):
            return "ended_before_new_cutoff"
        if decimal_value(row.get("price")) <= 0:
            return "price_no_longer_positive"
        if (row.get("type_of_payment") or "") != "наличные":
            return "payment_type_changed"
        if (row.get("_payment_match_source") or "").strip():
            return "payment_match_found"
        return "other_condition_changed"

    if key == "active_zero_price_direct_full":
        if row.get("_product_class") != "full_subscription":
            return "product_class_changed"
        if (row.get("activation_date") or "") > cutoff_date:
            return "not_active_yet_on_new_cutoff"
        if not is_not_finished(row, cutoff_date):
            return "ended_before_new_cutoff"
        if decimal_value(row.get("price")) != 0:
            return "price_restored_or_changed"
        if not (row.get("_payment_match_source") or "").startswith("direct_doc152"):
            return "direct_payment_match_no_longer_present"
        if decimal_value(row.get("_document131_posted_unmarked_refund_count")) > 0:
            return "refund_document_found"
        if not (row.get("type_of_payment") or "").strip():
            return "payment_type_cleared"
        return "other_condition_changed"

    if key == "active_non_named_payment_left":
        if not is_not_finished(row, cutoff_date):
            return "ended_before_new_cutoff"
        if decimal_value(row.get("payment_left")) <= 0:
            return "payment_left_cleared"
        if "рассроч" in (row.get("contract_name") or "").lower():
            return "became_named_installment"
        return "other_condition_changed"

    return "unknown"


def membership_summary(rows: list[dict[str, str]], template_rows: list[dict[str, str]], excluded_rows: list[dict[str, str]], cutoff_date: str) -> dict[str, object]:
    clients = {row["client_id"] for row in rows}
    return {
        "rows": len(rows),
        "clients": len(clients),
        "templates": len(template_rows),
        "excluded_active_later_contact_full": sum(1 for row in excluded_rows if row.get("rule") == "exclude_active_later_contact_full"),
        "row_classes": Counter(row.get("_product_class") or "blank" for row in rows),
        "payment_types": Counter(row.get("type_of_payment") or "blank" for row in rows),
        "money_sources": Counter(row.get("_money_source") or "blank" for row in rows),
        "business_overrides": Counter(row.get("_business_override") or "blank" for row in rows if row.get("_business_override")),
        "visits_left_sources": Counter(row.get("_visits_left_source") or "blank" for row in rows),
        "limited_subrent_groups": Counter(row.get("_subrent_rg3336_case_group") or "blank" for row in rows if row.get("_is_limited_subrent") == "1"),
        "limited_subrent_rows": sum(1 for row in rows if row.get("_is_limited_subrent") == "1"),
        "limited_subrent_rg3336_balance_rows": sum(
            1
            for row in rows
            if row.get("_is_limited_subrent") == "1"
            and row.get("_visits_left_source") == "rg3336_correct_dimension_balance"
        ),
        "limited_subrent_not_finished_on_problem_cutoff": sum(
            1
            for row in rows
            if row.get("_is_limited_subrent") == "1" and is_not_finished(row, cutoff_date)
        ),
    }


def build_active_problem_analysis(old_rows: list[dict[str, str]], new_rows: list[dict[str, str]]) -> tuple[list[dict[str, object]], list[dict[str, object]]]:
    old_by_contract = {row["contract_id"]: row for row in old_rows}
    new_by_contract = {row["contract_id"]: row for row in new_rows}

    summary_rows: list[dict[str, object]] = []
    transition_rows: list[dict[str, object]] = []

    for spec in ACTIVE_PROBLEMS:
        old_problem_rows = selected(old_rows, spec, OLD_CUTOFF_DATE)
        new_problem_rows = selected(new_rows, spec, NEW_CUTOFF_DATE)
        old_problem_ids = {row["contract_id"] for row in old_problem_rows}
        new_problem_ids = {row["contract_id"] for row in new_problem_rows}

        old_transitions = Counter()
        for contract_id in sorted(old_problem_ids):
            new_row = new_by_contract.get(contract_id)
            if contract_id in new_problem_ids:
                status = "still_problem"
            else:
                status = classify_no_longer_problem(spec.key, new_row, NEW_CUTOFF_DATE)
            old_transitions[status] += 1
            transition_rows.append(
                {
                    "problem_key": spec.key,
                    "direction": "old_problem_to_new",
                    "contract_id": contract_id,
                    "client_id_old": old_by_contract[contract_id].get("client_id", ""),
                    "client_id_new": (new_row or {}).get("client_id", ""),
                    "client_fio_old": old_by_contract[contract_id].get("client_fio", ""),
                    "client_fio_new": (new_row or {}).get("client_fio", ""),
                    "contract_name_old": old_by_contract[contract_id].get("contract_name", ""),
                    "contract_name_new": (new_row or {}).get("contract_name", ""),
                    "status": status,
                    "price_old": old_by_contract[contract_id].get("price", ""),
                    "price_new": (new_row or {}).get("price", ""),
                    "amount_paid_old": old_by_contract[contract_id].get("amount_of_payments", ""),
                    "amount_paid_new": (new_row or {}).get("amount_of_payments", ""),
                    "payment_left_old": old_by_contract[contract_id].get("payment_left", ""),
                    "payment_left_new": (new_row or {}).get("payment_left", ""),
                    "payment_type_old": old_by_contract[contract_id].get("type_of_payment", ""),
                    "payment_type_new": (new_row or {}).get("type_of_payment", ""),
                    "payment_match_source_old": old_by_contract[contract_id].get("_payment_match_source", ""),
                    "payment_match_source_new": (new_row or {}).get("_payment_match_source", ""),
                    "end_date_old": old_by_contract[contract_id].get("end_date", ""),
                    "end_date_new": (new_row or {}).get("end_date", ""),
                }
            )

        new_origins = Counter()
        for contract_id in sorted(new_problem_ids):
            if contract_id in old_problem_ids:
                origin = "was_old_problem"
            elif contract_id in old_by_contract:
                origin = "existed_before_but_was_not_old_problem"
            else:
                origin = "new_contract_id_after_old_backup"
            new_origins[origin] += 1

        summary_rows.append(
            {
                "problem_key": spec.key,
                "problem_title": spec.title,
                "old_doc_rows": spec.old_doc_count,
                "old_recomputed_rows": len(old_problem_rows),
                "old_recomputed_clients": len({row["client_id"] for row in old_problem_rows}),
                "new_rows": len(new_problem_rows),
                "new_clients": len({row["client_id"] for row in new_problem_rows}),
                "row_delta": len(new_problem_rows) - len(old_problem_rows),
                "old_problem_still_problem": old_transitions["still_problem"],
                "old_problem_no_longer_problem": len(old_problem_rows) - old_transitions["still_problem"],
                "old_problem_removed_from_new_export": old_transitions["removed_from_new_membership_export"],
                "new_problem_from_old_problem": new_origins["was_old_problem"],
                "new_problem_existing_old_contract": new_origins["existed_before_but_was_not_old_problem"],
                "new_problem_new_contract_id": new_origins["new_contract_id_after_old_backup"],
                "old_transition_breakdown": "; ".join(f"{key}={value}" for key, value in sorted(old_transitions.items())),
                "new_origin_breakdown": "; ".join(f"{key}={value}" for key, value in sorted(new_origins.items())),
            }
        )

    return summary_rows, transition_rows


def owner_change_summary(base_dir: Path, cutoff_datetime: str) -> dict[str, object]:
    owner_rows = read_csv(base_dir / "staging/stg_membership_owner_changes.csv")
    subscription_rows = read_csv(base_dir / "staging/stg_subscriptions_all.csv")
    final_rows = read_csv(base_dir / "staging/final_funnel_clients.csv")

    by_membership = Counter(row.get("membership_ref", "") for row in owner_rows)
    effective_rows = [row for row in owner_rows if is_truthy(row.get("is_effective_owner_change_on_cutoff"))]
    sub_with_owner = [row for row in subscription_rows if (row.get("owner_change_ref") or "").strip()]
    sub_by_ref = {row.get("subscription_ref", ""): row for row in subscription_rows}
    selected_with_owner = [
        row
        for row in final_rows
        if (sub_by_ref.get(row.get("selected_subscription_ref", "")) or {}).get("owner_change_ref")
    ]

    date_buckets = Counter()
    for row in owner_rows:
        dt = row.get("owner_change_datetime") or ""
        if not dt:
            date_buckets["blank"] += 1
        elif dt <= OLD_CUTOFF_DATETIME:
            date_buckets["on_or_before_old_cutoff"] += 1
        elif dt <= cutoff_datetime:
            date_buckets["after_old_cutoff_to_current_cutoff"] += 1
        else:
            date_buckets["after_current_cutoff"] += 1

    return {
        "owner_rows": len(owner_rows),
        "effective_rows": len(effective_rows),
        "memberships_with_multiple_changes": sum(1 for _, count in by_membership.items() if count > 1),
        "subscriptions_with_owner_change": len(sub_with_owner),
        "selected_final_clients_with_owner_change": len(selected_with_owner),
        "date_buckets": date_buckets,
        "owner_refs": {row.get("owner_change_ref") for row in owner_rows if row.get("owner_change_ref")},
    }


def missing_old_owner_changes() -> list[dict[str, object]]:
    old_owner_rows = read_csv(OLD_OWNER_DIR / "staging/stg_membership_owner_changes.csv")
    new_owner_rows = read_csv(NEW_OWNER_DIR / "staging/stg_membership_owner_changes.csv")
    new_refs = {row.get("owner_change_ref") for row in new_owner_rows}

    new_subs = read_csv(NEW_OWNER_DIR / "staging/stg_subscriptions_all.csv")
    new_sub_by_ref = {row.get("subscription_ref", ""): row for row in new_subs}
    new_final = read_csv(NEW_OWNER_DIR / "staging/final_funnel_clients.csv")
    new_final_by_subscription = {row.get("selected_subscription_ref", ""): row for row in new_final}
    new_membership_rows = read_csv(NEW_IMPORT_DIR / "staging/membership_import_rows.csv")
    new_membership_by_subscription = {row.get("_subscription_ref", ""): row for row in new_membership_rows}

    missing = []
    for old in old_owner_rows:
        if old.get("owner_change_ref") in new_refs:
            continue

        membership_ref = old.get("membership_ref", "")
        new_sub = new_sub_by_ref.get(membership_ref, {})
        new_final_row = new_final_by_subscription.get(membership_ref, {})
        new_membership_row = new_membership_by_subscription.get(membership_ref, {})
        missing.append(
            {
                "owner_change_ref": old.get("owner_change_ref", ""),
                "owner_change_number": old.get("owner_change_number", ""),
                "owner_change_datetime": old.get("owner_change_datetime", ""),
                "membership_ref": membership_ref,
                "membership_number": old.get("membership_number", ""),
                "old_backup_old_client_id": old.get("old_client_id", ""),
                "old_backup_old_client_fio": old.get("old_client_fio", ""),
                "old_backup_new_client_id": old.get("new_client_id", ""),
                "old_backup_new_client_fio": old.get("new_client_fio", ""),
                "new_stage_effective_client_id": new_sub.get("effective_client_id", ""),
                "new_stage_effective_client_fio": new_sub.get("effective_client_fio", ""),
                "new_stage_owner_change_ref": new_sub.get("owner_change_ref", ""),
                "new_final_client_id": new_final_row.get("client_id", ""),
                "new_final_client_fio": new_final_row.get("client_fio", ""),
                "new_final_funnel": new_final_row.get("funnel", ""),
                "new_membership_client_id": new_membership_row.get("client_id", ""),
                "new_membership_client_fio": new_membership_row.get("client_fio", ""),
                "new_membership_contract_name": new_membership_row.get("contract_name", ""),
            }
        )
    return missing


def named_case_rows(base_dir: Path) -> list[dict[str, str]]:
    wanted = [
        "Успенский Леонид Владимирович",
        "Василевская Вера Михайловна",
        "Россиева София Сергеевна",
        "Натарьев Григорий Павлович",
        "Филюк Владислав Андреевич",
        "Бламберус Михаил Александрович",
    ]
    rows = read_csv(base_dir / "staging/final_funnel_clients.csv")
    by_name = defaultdict(list)
    for row in rows:
        by_name[row.get("client_fio", "")].append(row)

    result = []
    for name in wanted:
        matches = by_name.get(name, [])
        if not matches:
            result.append(
                {
                    "client_fio": name,
                    "status": "not_found",
                    "client_id": "",
                    "funnel": "",
                    "selected_subscription_name": "",
                    "selected_subscription_sale_date": "",
                    "selected_subscription_end_date": "",
                    "selected_card_number": "",
                }
            )
            continue
        row = matches[0]
        result.append(
            {
                "client_fio": name,
                "status": "found",
                "client_id": row.get("client_id", ""),
                "funnel": row.get("funnel", ""),
                "selected_subscription_name": row.get("selected_subscription_name", ""),
                "selected_subscription_sale_date": row.get("selected_subscription_sale_date", ""),
                "selected_subscription_end_date": row.get("selected_subscription_end_date", ""),
                "selected_card_number": row.get("selected_card_number", ""),
            }
        )
    return result


def services_summary(import_dir: Path) -> dict[str, object]:
    coverage = read_csv(import_dir / "reports/services_coverage_report.csv")
    active_rows = read_csv(import_dir / "reports/services_active_rows_audit.csv")
    return {
        "coverage": coverage,
        "selected_rows": sum(int(row.get("selected_rows") or 0) for row in coverage),
        "active_selected_rows": sum(int(row.get("selected_rows") or 0) for row in coverage if row.get("selected_kind") == "active"),
        "historical_selected_rows": sum(int(row.get("selected_rows") or 0) for row in coverage if row.get("selected_kind") == "historical_fallback"),
        "outside_selected_rows": sum(int(row.get("selected_outside_import_zayavki") or 0) for row in coverage),
        "template_only_services": [row.get("service_name", "") for row in coverage if row.get("selected_kind") == "template_only_no_final_client_rows"],
        "represented_services": sum(1 for row in coverage if int(row.get("selected_rows") or 0) > 0),
        "active_audit_rows": len(active_rows),
        "active_audit_clients": len({row.get("client_id") for row in active_rows}),
        "active_audit_service_counts": Counter(row.get("service_name") or "blank" for row in active_rows),
    }


def build_services_diff(old_coverage: list[dict[str, str]], new_coverage: list[dict[str, str]]) -> list[dict[str, object]]:
    old_by_name = {row["service_name"]: row for row in old_coverage}
    new_by_name = {row["service_name"]: row for row in new_coverage}
    fields = [
        "total_sale_rows",
        "final_client_sale_rows",
        "active_final_client_rows",
        "selected_rows",
        "selected_kind",
        "selected_outside_import_zayavki",
        "latest_sale_datetime",
    ]
    diff_rows = []
    for name in sorted(set(old_by_name) | set(new_by_name)):
        old = old_by_name.get(name, {})
        new = new_by_name.get(name, {})
        changed_fields = [field for field in fields if old.get(field, "") != new.get(field, "")]
        if not changed_fields:
            continue
        row: dict[str, object] = {"service_name": name, "changed_fields": "; ".join(changed_fields)}
        for field in fields:
            row[f"old_{field}"] = old.get(field, "")
            row[f"new_{field}"] = new.get(field, "")
        diff_rows.append(row)
    return diff_rows


def counter_table(counter: Counter, limit: int | None = None) -> str:
    items = counter.most_common(limit)
    if not items:
        return "нет"
    return ", ".join(f"`{key}`={value}" for key, value in items)


def md_table(headers: list[str], rows: list[list[object]]) -> str:
    lines = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        lines.append("| " + " | ".join(str(cell) for cell in row) + " |")
    return "\n".join(lines)


def render_markdown(
    old_owner: dict[str, object],
    new_owner: dict[str, object],
    old_named: list[dict[str, str]],
    new_named: list[dict[str, str]],
    old_membership: dict[str, object],
    new_membership: dict[str, object],
    active_problem_summary: list[dict[str, object]],
    missing_owner_changes: list[dict[str, object]],
    old_services: dict[str, object],
    new_services: dict[str, object],
    services_diff: list[dict[str, object]],
) -> str:
    old_owner_refs = old_owner["owner_refs"]
    new_owner_refs = new_owner["owner_refs"]
    retained_owner_refs = len(old_owner_refs & new_owner_refs)  # type: ignore[operator]

    active_rows = [
        [
            row["problem_title"],
            row["old_recomputed_rows"],
            row["new_rows"],
            row["row_delta"],
            row["old_problem_still_problem"],
            row["old_problem_no_longer_problem"],
            row["new_problem_new_contract_id"],
        ]
        for row in active_problem_summary
    ]

    named_rows = []
    old_by_name = {row["client_fio"]: row for row in old_named}
    new_by_name = {row["client_fio"]: row for row in new_named}
    for name in old_by_name:
        old = old_by_name[name]
        new = new_by_name[name]
        named_rows.append(
            [
                name,
                old["status"],
                old["funnel"] or "-",
                old["selected_subscription_name"] or "-",
                new["status"],
                new["funnel"] or "-",
                new["selected_subscription_name"] or "-",
            ]
        )

    service_selected_changes = [
        row
        for row in services_diff
        if row.get("old_selected_rows") != row.get("new_selected_rows")
        or row.get("old_selected_kind") != row.get("new_selected_kind")
    ]

    missing_owner_rows = [
        [
            row["owner_change_number"],
            row["owner_change_datetime"],
            row["membership_number"],
            row["old_backup_new_client_fio"],
            row["new_stage_effective_client_fio"],
            row["new_final_funnel"] or "-",
        ]
        for row in missing_owner_changes
    ]

    return f"""# Статус 3 проблем `new-changes` на backup 2026-06-30

Дата анализа: `2026-07-05`.

Сравнивались последняя рабочая сборка на старом backup/cutoff `2026-05-25 08:00`
и новая полная сборка из `data/Fitnes-30-06-26.bak` на cutoff
`2026-06-30 23:27:03`.

Важно: прошлые файлы в `docs/new-changes/` не менялись. Этот отчет фиксирует
только состояние тех же проблем на новых выгрузках.

Техническая оговорка по cutoff: owner-change / `import_заявки` пересобран на
`2026-06-30 23:27:03`. Текущий SQL импорта абонементов в коде все еще содержит
внутренний `@cutoff_at = '2026-05-25 08:00:00'`; active-problem XLSX и этот
срез открытых проблем отбирают активность уже по `2026-06-30`, как записано в
`docs/new-backup-30-06/01_run_commands.md`. Поэтому отчет ниже описывает
фактически произведенные новые выгрузки, а не меняет это поведение задним
числом.

## Короткий вывод

- Проблема 1, смена владельца: правило работает на новом backup. Источник
  owner-change вырос с `{old_owner["owner_rows"]}` до `{new_owner["owner_rows"]}`
  строк; named cases проходят, включая Россиеву Софию, которая теперь попадает
  в новый cutoff. При этом `{len(missing_owner_changes)}` старых owner-change
  документа отсутствуют в свежем backup и требуют бизнес-проверки как изменение
  исходных данных.
- Проблема 2, импорт абонементов: структура импорта и валидация остались
  корректными (`PASS`), но открытые платежно-ценовые слои изменились по-разному.
  `no-payment cash` почти ушел: `198 -> 3`. `payment_left` заметно снизился:
  `297 -> 179`. `zero-price direct active full` почти сохранился:
  `44 -> 41`.
- Проблема 3, импорт услуг: активный слой не поехал. Осталось `352` активные
  клиентские строки, те же `4` активных названия услуг, `51` шаблон и те же
  `7` template-only услуг. Единственное изменение в выбранных строках:
  `Сайкл разовое без клубной карты` получил `4` historical fallback строки
  вместо `5`.

## Проблема 1. Смена владельца

### Как было на старом backup

По `docs/new-changes/prolem_1/03_implementation_and_validation.md` старый
исправленный прогон имел:

- `stg_membership_owner_changes`: `{old_owner["owner_rows"]}` строк;
- effective owner-change строк: `{old_owner["effective_rows"]}`;
- `stg_subscriptions_all` с owner-change: `{old_owner["subscriptions_with_owner_change"]}`;
- финальная валидация заявок/карт: `PASS`.

Named-case результат был: Успенский и Василевская переехали в
`Действующие клиенты`, Россиева еще не попадала в cutoff, Бламберус не менялся.

### Как стало на backup 2026-06-30

{md_table(
        ["метрика", "старый backup", "новый backup", "дельта"],
        [
            ["owner-change source rows", old_owner["owner_rows"], new_owner["owner_rows"], int(new_owner["owner_rows"]) - int(old_owner["owner_rows"])],
            ["effective owner changes", old_owner["effective_rows"], new_owner["effective_rows"], int(new_owner["effective_rows"]) - int(old_owner["effective_rows"])],
            ["memberships with multiple changes", old_owner["memberships_with_multiple_changes"], new_owner["memberships_with_multiple_changes"], int(new_owner["memberships_with_multiple_changes"]) - int(old_owner["memberships_with_multiple_changes"])],
            ["subscriptions with owner_change", old_owner["subscriptions_with_owner_change"], new_owner["subscriptions_with_owner_change"], int(new_owner["subscriptions_with_owner_change"]) - int(old_owner["subscriptions_with_owner_change"])],
            ["selected final clients with owner_change subscription", old_owner["selected_final_clients_with_owner_change"], new_owner["selected_final_clients_with_owner_change"], int(new_owner["selected_final_clients_with_owner_change"]) - int(old_owner["selected_final_clients_with_owner_change"])],
        ],
    )}

Старые owner-change документы почти полностью сохраняются: `{retained_owner_refs}`
из `{len(old_owner_refs)}` старых `owner_change_ref` найдены в новом source-слое.
Не найдены `{len(missing_owner_changes)}` старые операции.

Разбивка новых owner-change по датам документа:

- на или до старого cutoff `2026-05-25 08:00`: {new_owner["date_buckets"].get("on_or_before_old_cutoff", 0)};
- после старого cutoff и до нового cutoff: {new_owner["date_buckets"].get("after_old_cutoff_to_current_cutoff", 0)};
- после нового cutoff: {new_owner["date_buckets"].get("after_current_cutoff", 0)}.

Named-case проверка:

{md_table(
        ["клиент", "старый статус", "старая воронка", "старое выбранное членство", "новый статус", "новая воронка", "новое выбранное членство"],
        named_rows,
    )}

Старые owner-change документы, отсутствующие в новом backup:

{md_table(
        ["документ", "дата", "membership", "ожидаемый новый владелец из старого backup", "новый effective owner", "новая воронка"],
        missing_owner_rows,
    ) if missing_owner_rows else "Не найдено отсутствующих старых owner-change документов."}

Вывод: логика проблемы 1 не откатилась массово. На новом backup стало
существенно больше операций смены владельца, правило `latest owner-change per
membership on cutoff` продолжает переносить выбранное членство на effective
owner, а named cases не откатились. Но две старые операции из прошлого backup
в свежем source отсутствуют; в новых выгрузках эти два membership снова
привязаны к исходным владельцам. Это выглядит как изменение/удаление данных в
1С, а не как сбой SQL-правила, и его нужно отдельно подтвердить у менеджеров.

## Проблема 2. Импорт абонементов

### Общий слой импорта

{md_table(
        ["метрика", "старый backup", "новый backup", "дельта"],
        [
            ["client membership rows", old_membership["rows"], new_membership["rows"], int(new_membership["rows"]) - int(old_membership["rows"])],
            ["clients with membership rows", old_membership["clients"], new_membership["clients"], int(new_membership["clients"]) - int(old_membership["clients"])],
            ["membership templates", old_membership["templates"], new_membership["templates"], int(new_membership["templates"]) - int(old_membership["templates"])],
            ["exclude_active_later_contact_full", old_membership["excluded_active_later_contact_full"], new_membership["excluded_active_later_contact_full"], int(new_membership["excluded_active_later_contact_full"]) - int(old_membership["excluded_active_later_contact_full"])],
            ["limited subrent rows", old_membership["limited_subrent_rows"], new_membership["limited_subrent_rows"], int(new_membership["limited_subrent_rows"]) - int(old_membership["limited_subrent_rows"])],
            ["limited subrent via rg3336 balance", old_membership["limited_subrent_rg3336_balance_rows"], new_membership["limited_subrent_rg3336_balance_rows"], int(new_membership["limited_subrent_rg3336_balance_rows"]) - int(old_membership["limited_subrent_rg3336_balance_rows"])],
            ["limited subrent not finished on active-problem cutoff", old_membership["limited_subrent_not_finished_on_problem_cutoff"], new_membership["limited_subrent_not_finished_on_problem_cutoff"], int(new_membership["limited_subrent_not_finished_on_problem_cutoff"]) - int(old_membership["limited_subrent_not_finished_on_problem_cutoff"])],
        ],
    )}

Row classes:

- старый backup: {counter_table(old_membership["row_classes"])}.
- новый backup: {counter_table(new_membership["row_classes"])}.

Payment types:

- старый backup: {counter_table(old_membership["payment_types"])}.
- новый backup: {counter_table(new_membership["payment_types"])}.

Visits-left источники:

- старый backup: {counter_table(old_membership["visits_left_sources"])}.
- новый backup: {counter_table(new_membership["visits_left_sources"])}.

Ограниченная субаренда осталась закрытым правилом для текущих файлов: строк
ограниченной субаренды стало `{old_membership["limited_subrent_rows"]} -> {new_membership["limited_subrent_rows"]}`,
а строк, где остаток взят из `rg3336_correct_dimension_balance`, стало
`{old_membership["limited_subrent_rg3336_balance_rows"]} -> {new_membership["limited_subrent_rg3336_balance_rows"]}`.
На active-problem cutoff `2026-06-30` таких незавершенных строк уже `0`, то
есть операционный риск действующих ограниченных субаренд в свежем срезе не
расширился.

### Три открытых активных платежно-ценовых слоя

{md_table(
        [
            "слой",
            "было rows",
            "стало rows",
            "дельта",
            "старые rows все еще проблема",
            "старые rows перестали быть проблемой",
            "новые contract_id",
        ],
        active_rows,
    )}

Построчные переходы сохранены в
`output/20260630_problem_status_analysis/active_problem_contract_transitions.csv`.

Ключевое разложение:

{chr(10).join(f"- `{row['problem_key']}`: {row['old_transition_breakdown']}; новые остатки: {row['new_origin_breakdown']}." for row in active_problem_summary)}

Вывод по словам менеджеров о правках:

- `no-payment cash`: исправлено массово. Было `198` активных строк, осталось
  `3`. Это самый сильный эффект новой базы.
- `zero-price direct active full`: почти не исправлено на уровне данных.
  Осталось `41` из `44` по масштабу. Этот слой все еще нужно держать как
  открытый риск цены/оплаты действующих клиентов.
- `non-named payment_left`: стало лучше, но проблема сохраняется. Было `297`,
  стало `179`. Часть долгов ушла, но остаток достаточно большой для отдельной
  проверки.

## Проблема 3. Импорт услуг

### Общая сводка

{md_table(
        ["метрика", "старый backup", "новый backup", "дельта"],
        [
            ["client service rows", old_services["selected_rows"], new_services["selected_rows"], int(new_services["selected_rows"]) - int(old_services["selected_rows"])],
            ["active service rows", old_services["active_selected_rows"], new_services["active_selected_rows"], int(new_services["active_selected_rows"]) - int(old_services["active_selected_rows"])],
            ["historical fallback rows", old_services["historical_selected_rows"], new_services["historical_selected_rows"], int(new_services["historical_selected_rows"]) - int(old_services["historical_selected_rows"])],
            ["outside import_zayavki fallback rows", old_services["outside_selected_rows"], new_services["outside_selected_rows"], int(new_services["outside_selected_rows"]) - int(old_services["outside_selected_rows"])],
            ["represented services", old_services["represented_services"], new_services["represented_services"], int(new_services["represented_services"]) - int(old_services["represented_services"])],
            ["template-only services", len(old_services["template_only_services"]), len(new_services["template_only_services"]), len(new_services["template_only_services"]) - len(old_services["template_only_services"])],
        ],
    )}

Активные услуги по audit-файлу:

- старый backup: rows `{old_services["active_audit_rows"]}`, clients
  `{old_services["active_audit_clients"]}`, services
  {counter_table(old_services["active_audit_service_counts"])}.
- новый backup: rows `{new_services["active_audit_rows"]}`, clients
  `{new_services["active_audit_clients"]}`, services
  {counter_table(new_services["active_audit_service_counts"])}.

Template-only список не изменился:

{chr(10).join(f"- `{name}`" for name in new_services["template_only_services"])}

Изменения в выбранных строках услуг:

{md_table(
        ["услуга", "старый selected_rows", "новый selected_rows", "старый kind", "новый kind"],
        [
            [
                row["service_name"],
                row["old_selected_rows"],
                row["new_selected_rows"],
                row["old_selected_kind"],
                row["new_selected_kind"],
            ]
            for row in service_selected_changes
        ],
    ) if service_selected_changes else "Выбранные строки по услугам не изменились."}

Вывод: проблема 3 не деградировала на новом backup. Активная часть полностью
стабильна, coverage по `51` услугам сохраняется, а единственная потеря строки
относится к historical fallback, не к активной услуге.

## Служебные файлы анализа

- `output/20260630_problem_status_analysis/active_problem_summary.csv`
- `output/20260630_problem_status_analysis/active_problem_contract_transitions.csv`
- `output/20260630_problem_status_analysis/owner_change_named_cases.csv`
- `output/20260630_problem_status_analysis/missing_old_owner_changes.csv`
- `output/20260630_problem_status_analysis/services_coverage_diff.csv`

"""


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    DOC_PATH.parent.mkdir(parents=True, exist_ok=True)

    old_membership_rows = read_csv(OLD_IMPORT_DIR / "staging/membership_import_rows.csv")
    new_membership_rows = read_csv(NEW_IMPORT_DIR / "staging/membership_import_rows.csv")
    old_template_rows = read_csv(OLD_IMPORT_DIR / "staging/membership_template_rows.csv")
    new_template_rows = read_csv(NEW_IMPORT_DIR / "staging/membership_template_rows.csv")
    old_excluded_rows = read_csv(OLD_IMPORT_DIR / "staging/membership_import_excluded_rows.csv")
    new_excluded_rows = read_csv(NEW_IMPORT_DIR / "staging/membership_import_excluded_rows.csv")

    old_membership = membership_summary(old_membership_rows, old_template_rows, old_excluded_rows, OLD_CUTOFF_DATE)
    new_membership = membership_summary(new_membership_rows, new_template_rows, new_excluded_rows, NEW_CUTOFF_DATE)

    active_summary, active_transitions = build_active_problem_analysis(old_membership_rows, new_membership_rows)

    old_owner = owner_change_summary(OLD_OWNER_DIR, OLD_CUTOFF_DATETIME)
    new_owner = owner_change_summary(NEW_OWNER_DIR, NEW_CUTOFF_DATETIME)
    missing_owner = missing_old_owner_changes()
    old_named = named_case_rows(OLD_OWNER_DIR)
    new_named = named_case_rows(NEW_OWNER_DIR)

    old_services = services_summary(OLD_IMPORT_DIR)
    new_services = services_summary(NEW_IMPORT_DIR)
    services_diff = build_services_diff(old_services["coverage"], new_services["coverage"])  # type: ignore[arg-type]

    write_csv(
        OUTPUT_DIR / "active_problem_summary.csv",
        active_summary,
        [
            "problem_key",
            "problem_title",
            "old_doc_rows",
            "old_recomputed_rows",
            "old_recomputed_clients",
            "new_rows",
            "new_clients",
            "row_delta",
            "old_problem_still_problem",
            "old_problem_no_longer_problem",
            "old_problem_removed_from_new_export",
            "new_problem_from_old_problem",
            "new_problem_existing_old_contract",
            "new_problem_new_contract_id",
            "old_transition_breakdown",
            "new_origin_breakdown",
        ],
    )
    write_csv(
        OUTPUT_DIR / "active_problem_contract_transitions.csv",
        active_transitions,
        [
            "problem_key",
            "direction",
            "contract_id",
            "client_id_old",
            "client_id_new",
            "client_fio_old",
            "client_fio_new",
            "contract_name_old",
            "contract_name_new",
            "status",
            "price_old",
            "price_new",
            "amount_paid_old",
            "amount_paid_new",
            "payment_left_old",
            "payment_left_new",
            "payment_type_old",
            "payment_type_new",
            "payment_match_source_old",
            "payment_match_source_new",
            "end_date_old",
            "end_date_new",
        ],
    )
    write_csv(
        OUTPUT_DIR / "owner_change_named_cases.csv",
        [
            {
                "client_fio": old["client_fio"],
                "old_status": old["status"],
                "old_funnel": old["funnel"],
                "old_subscription": old["selected_subscription_name"],
                "new_status": new["status"],
                "new_funnel": new["funnel"],
                "new_subscription": new["selected_subscription_name"],
            }
            for old, new in zip(old_named, new_named)
        ],
        [
            "client_fio",
            "old_status",
            "old_funnel",
            "old_subscription",
            "new_status",
            "new_funnel",
            "new_subscription",
        ],
    )
    write_csv(
        OUTPUT_DIR / "missing_old_owner_changes.csv",
        missing_owner,
        [
            "owner_change_ref",
            "owner_change_number",
            "owner_change_datetime",
            "membership_ref",
            "membership_number",
            "old_backup_old_client_id",
            "old_backup_old_client_fio",
            "old_backup_new_client_id",
            "old_backup_new_client_fio",
            "new_stage_effective_client_id",
            "new_stage_effective_client_fio",
            "new_stage_owner_change_ref",
            "new_final_client_id",
            "new_final_client_fio",
            "new_final_funnel",
            "new_membership_client_id",
            "new_membership_client_fio",
            "new_membership_contract_name",
        ],
    )

    service_diff_fields = [
        "service_name",
        "changed_fields",
        "old_total_sale_rows",
        "new_total_sale_rows",
        "old_final_client_sale_rows",
        "new_final_client_sale_rows",
        "old_active_final_client_rows",
        "new_active_final_client_rows",
        "old_selected_rows",
        "new_selected_rows",
        "old_selected_kind",
        "new_selected_kind",
        "old_selected_outside_import_zayavki",
        "new_selected_outside_import_zayavki",
        "old_latest_sale_datetime",
        "new_latest_sale_datetime",
    ]
    write_csv(OUTPUT_DIR / "services_coverage_diff.csv", services_diff, service_diff_fields)

    markdown = render_markdown(
        old_owner,
        new_owner,
        old_named,
        new_named,
        old_membership,
        new_membership,
        active_summary,
        missing_owner,
        old_services,
        new_services,
        services_diff,
    )
    DOC_PATH.write_text(markdown, encoding="utf-8")

    print(f"wrote {DOC_PATH.relative_to(ROOT)}")
    print(f"wrote {OUTPUT_DIR.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
