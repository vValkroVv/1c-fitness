#!/usr/bin/env python3
"""Independently audit saved September imports without modifying workbooks.

The June delivery defines layout and the accepted explicit template attributes. Counts and values are reconciled against
this run's staging exports, including the single separately delivered contract.
No production transformation or validation function is imported or executed.
"""

from __future__ import annotations

import argparse
import ast
import csv
import hashlib
import json
import re
from collections import Counter, defaultdict
from datetime import date, datetime, timedelta
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any
from xml.etree import ElementTree
from zipfile import ZipFile

from openpyxl import load_workbook

ROOT = Path(__file__).resolve().parents[1]
POOL = ["Пеуна Анастасия Ивановна", "Пилия Анастасия Артуровна", "Ефремова Алена"]
BRANCHES = {
    "Коммунальная, 20": "Фитнес Империя (Гоголевский)",
    "Лососинское шоссе, 26": "Фитнес Империя (Столица)",
    "Промышленная, 10": "Фитнес Империя (Промышленная)",
    "Ровио, 3": "Фитнес Империя (Ровио)",
    "Карельский (закрыт)": "Фитнес Империя (Ровио)",
}
LABELS = {
    "Действующие клиенты": ("Действующие абонементы", "Все действующие абонементы"),
    "Реактивация": ("Реактивация", "Закрытые годовые абонементы"),
    "Новые заявки": ("новые заявки", "неразобранные"),
}
NUMERIC = {"budget", "price", "amount_of_payments", "amount_of_payment", "payment_left",
           "duration", "freeze", "guests", "visits_left", "visits", "count"}


def text(value: Any) -> str:
    return "" if value is None else str(value).strip()


def same_timestamp(value: Any, expected: str) -> bool:
    """SQL datetime2 may serialize zero fractional seconds; never round a value."""
    return bool(re.fullmatch(re.escape(expected) + r"(?:\.0{1,7})?", text(value)))


def normalized(value: Any, column: str = "") -> str:
    if value is None or value == "":
        return ""
    if isinstance(value, (datetime, date)):
        return value.strftime("%Y-%m-%d")
    raw = text(value)
    if column.endswith("_date"):
        for fmt in ("%Y-%m-%d", "%d.%m.%Y"):
            try:
                return datetime.strptime(raw[:10], fmt).strftime("%Y-%m-%d")
            except ValueError:
                pass
    if column in NUMERIC:
        try:
            return str(Decimal(raw.replace(",", ".")).normalize())
        except InvalidOperation:
            pass
    return raw


def row_key(row: dict[str, Any], headers: list[str]) -> tuple[str, ...]:
    return tuple(normalized(row.get(column), column) for column in headers)


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            result.update(chunk)
    return result.hexdigest()


def csv_rows(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def phones(value: Any) -> set[str]:
    result = set()
    for token in re.split(r"[,;]\s*", text(value)):
        digits = re.sub(r"\D", "", token)
        if len(digits) == 10:
            result.add("7" + digits)
        elif len(digits) == 11 and digits[0] in "78":
            result.add("7" + digits[1:])
    return result


def workbook(path: Path, header_count: int, *, rows: bool = True) -> dict[str, Any]:
    book = load_workbook(path, read_only=True, data_only=False)
    result: dict[str, Any] = {"path": str(path), "sheets": [], "data": []}
    try:
        for sheet in book:
            records = sheet.iter_rows()
            header_cells = [next(records) for _ in range(header_count)]
            headers = [[cell.value for cell in row] for row in header_cells]
            info: dict[str, Any] = {
                "name": sheet.title, "rows": sheet.max_row, "columns": sheet.max_column,
                "headers": headers, "header_formats": [[cell.number_format for cell in row] for row in header_cells],
                "formulas": 0, "error_cells": 0, "blank_rows": 0,
            }
            if rows:
                for record in records:
                    values = [cell.value for cell in record]
                    info["formulas"] += sum(cell.data_type == "f" for cell in record)
                    info["error_cells"] += sum(cell.data_type == "e" for cell in record)
                    info["blank_rows"] += int(not any(value not in (None, "") for value in values))
                    result["data"].append(dict(zip(headers[0], values)))
            result["sheets"].append(info)
    finally:
        book.close()
    return result


def layout(path: Path) -> dict[str, Any]:
    """Inspect saved widths, header heights and freeze panes without loading cells."""
    namespace = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"
    result = {}
    with ZipFile(path) as archive:
        for name in archive.namelist():
            if not re.fullmatch(r"xl/worksheets/sheet\d+\.xml", name):
                continue
            info: dict[str, Any] = {"columns": [], "header_rows": [], "panes": []}
            with archive.open(name) as handle:
                for _, element in ElementTree.iterparse(handle, events=("start",)):
                    tag = element.tag.removeprefix(namespace)
                    if tag == "col":
                        info["columns"].append(element.attrib)
                    elif tag == "pane":
                        info["panes"].append(element.attrib)
                    elif tag == "row":
                        if int(element.attrib["r"]) > 2:
                            break
                        info["header_rows"].append(element.attrib)
            result[name] = info
    return result


class Audit:
    def __init__(self) -> None:
        self.checks: list[dict[str, Any]] = []
        self.details: dict[str, Any] = {}
        self.warnings: list[str] = []

    def check(self, name: str, passed: bool, **facts: Any) -> None:
        self.checks.append({"check": name, "pass": bool(passed), **facts})
        if not passed:
            print(f"FAIL: {name}", flush=True)

    def compare_rows(self, name: str, actual: list[dict], expected: list[dict], headers: list[str]) -> None:
        actual_counter = Counter(row_key(row, headers) for row in actual)
        expected_counter = Counter(row_key(row, headers) for row in expected)
        missing, unexpected = expected_counter - actual_counter, actual_counter - expected_counter
        self.check(name, not missing and not unexpected, actual_rows=len(actual), expected_rows=len(expected),
                   missing_rows=sum(missing.values()), unexpected_rows=sum(unexpected.values()))


def fact_fields(path: Path) -> list[str]:
    """Read the declared TSV schema only; do not run a production module."""
    for node in ast.parse(path.read_text(encoding="utf-8")).body:
        if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "FACT_FIELDS" for target in node.targets):
            return ast.literal_eval(node.value)
    raise ValueError(f"FACT_FIELDS not found: {path}")


def audit_canonical_templates(audit: Audit, baseline: Path, current: dict[str, Any]) -> None:
    """Check explicit decisions; single-source template changes remain evidence."""
    decisions = csv_rows(ROOT / "end-to-end-xlsx/config/membership_template_canonicalization.csv")
    actual = {text(row["name"]): row for row in current["data"]}
    old_path = next(baseline.glob("fitbase_import_shablony_abonementov_*.xlsx"))
    previous = {text(row["name"]): row for row in workbook(old_path, 2)["data"]}
    fields = ["branches_access", "price", "duration", "visits", "freeze"]
    selected = [row for row in decisions if text(row["canonical_name"]) in actual]
    mismatches = [row["canonical_name"] for row in selected if
                  row_key(actual[row["canonical_name"]], fields) != row_key(row, fields)]
    audit.check("Шаблоны: все явные canonical attrs сохранены", not mismatches,
                configured=len(decisions), delivered=len(selected), mismatched_names=mismatches)
    common = [row["canonical_name"] for row in selected if row["canonical_name"] in previous]
    changed = [name for name in common if row_key(actual[name], fields) != row_key(previous[name], fields)]
    audit.check("Шаблоны: общие явные решения совпадают с принятой июньской поставкой",
                not changed, common_templates=len(common), mismatched_names=changed)
    configured_names = {row["canonical_name"] for row in decisions}
    unconfigured_changes = []
    for name in sorted((actual.keys() & previous.keys()) - configured_names):
        differences = {field: {"june": normalized(previous[name].get(field), field),
                               "september": normalized(actual[name].get(field), field)}
                       for field in fields if normalized(previous[name].get(field), field) !=
                       normalized(actual[name].get(field), field)}
        if differences:
            unconfigured_changes.append({"name": name, "differences": differences})
    audit.details["canonical_templates"] = {
        "configured": len(decisions), "delivered": len(selected), "common_with_june": len(common),
        "new_configured_names": sorted(row["canonical_name"] for row in selected
                                       if row["canonical_name"] not in previous),
        "unconfigured_source_changes": unconfigured_changes,
    }


def audit_facts(audit: Audit, work: Path, cutoff: str) -> None:
    specifications = [
        ("membership", "19_build_membership_import_xlsx.py", ["sale_datetime", "financial_sale_document_datetime", "matched_payment_datetime", "financial_register_last_movement_datetime"]),
        ("services", "23_build_services_import_xlsx.py", ["sale_datetime", "payment_datetime", "service_doc_datetime"]),
    ]
    for kind, script, timestamp_fields in specifications:
        path = work / f"imports/staging/{kind}_import_facts.tsv"
        fields = fact_fields(ROOT / "end-to-end-xlsx/scripts" / script)
        total = 0
        wrong_cutoff = 0
        future = Counter()
        maxima: dict[str, str] = {}
        with path.open(encoding="utf-16", newline="") as handle:
            for values in csv.reader(handle, delimiter="\t"):
                if not values:
                    continue
                if len(values) != len(fields):
                    raise ValueError(f"{path}: TSV width {len(values)} != {len(fields)}")
                row = dict(zip(fields, values))
                total += 1
                wrong_cutoff += row["cutoff_at"] != cutoff
                for field in timestamp_fields:
                    value = row.get(field, "")
                    if value:
                        maxima[field] = max(maxima.get(field, ""), value)
                        future[field] += int(value > cutoff)
        audit.check(f"{kind}: каждый SQL fact имеет единый cutoff", total > 0 and wrong_cutoff == 0, rows=total, mismatches=wrong_cutoff)
        audit.check(f"{kind}: операции не позже cutoff", not any(future.values()), future_rows=dict(future), maximum_source_datetimes=maxima)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--run-name", default="20260921_final")
    parser.add_argument("--delivery", type=Path, default=ROOT / "output/20260921_final_delivery")
    parser.add_argument("--baseline", type=Path, default=ROOT / "output/20260630_delivery_funnel_labels_20260820")
    parser.add_argument("--output", type=Path, default=ROOT / "output/20260921_delivery_audit")
    parser.add_argument("--expected-cutoff", default="2026-09-21 20:12:12")
    parser.add_argument("--report", type=Path, default=ROOT / "docs/20260921_delivery_double_check.md")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    work = ROOT / "end-to-end-xlsx/work" / args.run_name
    audit = Audit()
    manifest = json.loads((args.delivery / "reports/delivery_manifest.json").read_text())
    cutoff = manifest["cutoff_contract"]["cutoff_at"]
    backup_finish = manifest["cutoff_contract"]["backup_finish_at"]
    stamp = manifest["cutoff_contract"]["date_stamp"]
    audit.check("Фактическое время backup", backup_finish == "2026-09-20 20:12:12", actual=backup_finish)
    audit.check("Согласованный единый срез", cutoff == args.expected_cutoff, actual=cutoff, expected=args.expected_cutoff)
    cutoff_day = datetime.fromisoformat(args.expected_cutoff).date().isoformat()
    previous_day = (datetime.fromisoformat(args.expected_cutoff) - timedelta(days=1)).date().isoformat()
    audit.check("READY и manifest имеют PASS", "PASS" in (args.delivery / "READY.txt").read_text() and manifest["verdict"] == "PASS")
    actual_files = {path.name for path in args.delivery.iterdir() if path.suffix in {".xlsx", ".zip"}}
    audit.check("Manifest охватывает все передаваемые файлы", actual_files == {entry["name"] for entry in manifest["files"]}, files=len(actual_files))
    for entry in manifest["files"]:
        path = args.delivery / entry["name"]
        audit.check(f"SHA-256 и размер: {path.name}", path.stat().st_size == entry["size_bytes"] and digest(path) == entry["sha256"])

    books: dict[str, dict] = {}
    counts = []
    for old in sorted(args.baseline.glob("*.xlsx")):
        name = old.name.replace("20260630", stamp)
        header_count = 1 if "plastic_cards" in name or name.startswith("problem_") else 2
        baseline = workbook(old, header_count, rows=False)
        current = workbook(args.delivery / name, header_count)
        books[name] = current
        a, b = current["sheets"], baseline["sheets"]
        audit.check(f"Структура и заголовки как в июне: {name}", len(a) == len(b) and all(
            left["name"] == right["name"] and left["columns"] == right["columns"] and left["headers"] == right["headers"]
            for left, right in zip(a, b)))
        if any(left["header_formats"] != right["header_formats"] for left, right in zip(a, b)):
            audit.warnings.append(f"{name}: числовой формат заголовков отличается от июня; проверяется визуально.")
        if layout(old) != layout(args.delivery / name):
            audit.warnings.append(f"{name}: ширины столбцов, высоты первых строк или закрепление областей отличаются от июня; требуется просмотр.")
        audit.check(f"Нет формул, Excel-ошибок и пустых строк: {name}", all(not sheet[field] for sheet in a for field in ("formulas", "error_cells", "blank_rows")))
        counts.append({"file": name, "june_rows": sum(item["rows"] - header_count for item in b), "september_rows": len(current["data"]), "columns": a[0]["columns"], "sheets": [item["name"] for item in a]})
        print(f"Read {name}: {len(current['data'])} rows", flush=True)
    audit.check("Ровно семь ожидаемых XLSX", set(books) == {path.name for path in args.delivery.glob("*.xlsx")} and len(books) == 7)
    audit.details["file_counts"] = counts

    def book(prefix: str) -> dict:
        return next(value for name, value in books.items() if name.startswith(prefix))

    applications = book("fitbase_active_clients_import_zayavki_")["data"]
    memberships_book = book("fitbase_import_abonementy_clientov_")
    memberships = memberships_book["data"]
    problems = book("problem_4_")["data"]
    services = book("fitbase_import_uslugi_clientov_")["data"]
    headers = memberships_book["sheets"][0]["headers"][0]
    all_memberships = memberships + problems
    audit.check("problem4 содержит только договор 151350", len(problems) == 1 and text(problems[0]["contract_id"]) == "00000151350")

    managers: dict[str, set[str]] = defaultdict(set)
    for kind, rows, id_column in [("Заявки", applications, "client_id"), ("Абонементы и problem4", all_memberships, "contract_id"), ("Услуги", services, "service_id")]:
        ids = [text(row[id_column]) for row in rows if text(row[id_column])]
        audit.check(f"{kind}: уникальные {id_column}", len(ids) == len(set(ids)), rows_with_id=len(ids), unique_ids=len(set(ids)))
        wrong = 0
        for row in rows:
            client = text(row["client_id"])
            manager = text(row["manager"])
            expected = POOL[int.from_bytes(hashlib.sha256(client.encode()).digest(), "big") % 3]
            wrong += manager != expected
            managers[client].add(manager)
        audit.check(f"{kind}: детерминированный общий пул менеджеров", wrong == 0, checked_rows=len(rows), mismatches=wrong)
        audit.check(f"{kind}: только допустимые филиалы", all(row["филиал"] in BRANCHES.values() for row in rows))
        audit.details[f"{kind}: managers"] = dict(Counter(row["manager"] for row in rows))
    audit.check("Менеджер каждого клиента одинаков во всех слоях", all(len(values) == 1 for values in managers.values()), clients=len(managers))
    phone_to_ids: dict[str, set[str]] = defaultdict(set)
    for row in applications:
        for phone in phones(row["phone"]):
            phone_to_ids[phone].add(text(row["client_id"]))
    audit.check("Нет повторов нормализованных телефонов заявок", all(len(ids) == 1 for ids in phone_to_ids.values()), duplicate_phones=sum(len(ids) > 1 for ids in phone_to_ids.values()))
    audit.details["application_phone_coverage"] = {"empty": sum(not text(row["phone"]) for row in applications), "nonempty_without_valid_phone": sum(bool(text(row["phone"])) and not phones(row["phone"]) for row in applications), "multiple_valid_phones": sum(len(phones(row["phone"])) > 1 for row in applications)}
    coverage = audit.details["application_phone_coverage"]
    if coverage["empty"] or coverage["nonempty_without_valid_phone"]:
        audit.warnings.append(f"Заявки сохраняют согласованные исключения телефонов: пустых {coverage['empty']}, непустых без валидного номера {coverage['nonempty_without_valid_phone']}. Это не ошибка XLSX; такие телефоны не подходят для фото.")
    audit.details["funnels"] = dict(Counter(row["funnel"] for row in applications))
    audit.check("Согласованные подписи воронок", all((row["funnel"], row["funnel_step"]) in LABELS.values() for row in applications))

    for kind, rows, field, prefix in [("Абонементы", all_memberships, "contract_name", "fitbase_import_shablony_abonementov_"), ("Услуги", services, "service_name", "fitbase_import_shablony_uslug_")]:
        templates = book(prefix)["data"]
        names = {text(row["name"]) for row in templates}
        used = {text(row[field]) for row in rows if text(row[field])}
        audit.check(f"{kind}: все названия есть в шаблонах", used <= names, missing_names=sorted(used - names), templates=len(names))
        audit.check(f"{kind}: имена шаблонов уникальны", len(names) == len(templates))

    audit_canonical_templates(audit, args.baseline, book("fitbase_import_shablony_abonementov_"))
    source_memberships = csv_rows(work / "imports/staging/membership_import_rows.csv")
    audit.compare_rows("Все ячейки main + problem4 совпадают с полным staging без потерь", all_memberships, source_memberships, headers)
    money = {}
    for field in ("price", "amount_of_payments", "payment_left"):
        current_total = sum((Decimal(normalized(row[field], field) or "0") for row in all_memberships), Decimal(0))
        source_total = sum((Decimal(normalized(row[field], field) or "0") for row in source_memberships), Decimal(0))
        audit.check(f"Абонементы: сумма {field} совпадает с staging", current_total == source_total, delivery=str(current_total), source=str(source_total))
        money[field] = str(current_total)
    audit.details["membership_totals"] = money
    for name, current in books.items():
        if name.startswith("fitbase_import_") and "abonementy_clientov" not in name:
            audit.check(f"Финальная копия совпадает с проверенным imports: {name}", digest(args.delivery / name) == digest(work / "imports" / name))

    owner_rows = csv_rows(work / "owner/csv/final_funnel_clients.csv")
    owner = {row["client_id"]: row for row in owner_rows}
    removed = {row["client_id"] for row in csv_rows(work / "owner/reports/phone_deduplication_removed_clients.csv")}
    refusers = {row["client_id"] for row in csv_rows(work / "owner/csv/new_application_refusers.csv")}
    wanted = {row["client_id"] for row in owner_rows if not (row["funnel"] == "Новые заявки" and not row["phones"].strip())} - removed - refusers
    audit.check("Все ожидаемые заявки переданы после известных исключений", {text(row["client_id"]) for row in applications} == wanted, expected=len(wanted), actual=len(applications), removed_phone_duplicates=len(removed), transferred_refusers=len(refusers))
    audit.check("Все отказники присутствуют в абонементах", refusers <= {text(row["client_id"]) for row in all_memberships if row["tag"] == "отказники"})
    expected_applications = []
    for client in wanted:
        source = owner[client]
        expected_applications.append({**source, "phone": source["phones"], "funnel": LABELS[source["funnel"]][0], "funnel_step": LABELS[source["funnel"]][1], "филиал": BRANCHES[source["normalized_club"]]})
    application_headers = book("fitbase_active_clients_import_zayavki_")["sheets"][0]["headers"][0]
    audit.compare_rows("Все поля заявок совпадают с актуальным owner CSV", applications, expected_applications, application_headers)
    expected_cards = [{"телефон": row["phones"], "фио": row["client_fio"], "номер пластиковой карты": row["selected_card_number"]} for row in owner_rows if row["client_id"] in wanted and row["funnel"] == "Действующие клиенты"]
    audit.compare_rows("Карты соответствуют только передаваемым действующим клиентам", book("fitbase_active_clients_plastic_cards_")["data"], expected_cards, ["телефон", "фио", "номер пластиковой карты"])

    boundary = []
    app_by_id = {text(row["client_id"]): row for row in applications}
    for row in owner_rows:
        end = row["selected_subscription_end_date"][:10]
        if end in {previous_day, cutoff_day}:
            boundary.append({"client_id": row["client_id"], "end_date": end, "internal_funnel": row["funnel"], "delivered_funnel": app_by_id.get(row["client_id"], {}).get("funnel", ""), "excluded_by_phone_dedup": row["client_id"] in removed})
    audit.check(f"Граница {previous_day}/{cutoff_day}: предыдущий день истёк, текущий действует", all(row["internal_funnel"] == ("Реактивация" if row["end_date"] == previous_day else "Действующие клиенты") for row in boundary), checked_clients=len(boundary))
    audit.details["boundary_clients"] = boundary
    for relative in ("raw/staging/staging_run_metadata.csv", "owner/staging/staging_run_metadata.csv"):
        rows = csv_rows(work / relative)
        audit.check(f"Единый cutoff: {relative}", len(rows) == 1 and all(
            same_timestamp(row["cutoff_at"], cutoff)
            and same_timestamp(row["backup_finish_at"], backup_finish)
            and row["cutoff_date"] == cutoff[:10]
            and row["output_run_label"] == args.run_name for row in rows))
    audit.check("Каждый клиент owner имеет дату единого среза", all(row["cutoff_date"] == cutoff[:10] for row in owner_rows))
    audit_facts(audit, work, cutoff)
    end_audit = csv_rows(work / "imports/reports/services_end_dates_audit.csv")
    audit.details["services_end_date_sources"] = dict(Counter(row["end_date_source"] for row in end_audit))
    audit.compare_rows("Даты каждой услуги совпадают с поштучным аудитом источника", services, end_audit, ["service_id", "client_id", "create_date", "activation_date", "end_date"])
    audit.compare_rows("Цена и остатки каждой услуги совпадают с поштучным аудитом", services, end_audit, ["service_id", "price", "visits_left"])
    audit.details["service_totals"] = {
        field: str(sum((Decimal(normalized(row[field], field) or "0") for row in services), Decimal(0)))
        for field in ("price", "amount_of_payment", "payment_left", "visits_left")
    }
    audit.details["service_boundary_rows"] = [
        {field: row[field] for field in ("service_id", "client_id", "create_date", "activation_date", "end_date", "row_kind", "date_state", "is_active_by_balance", "is_active_by_date", "is_active_on_cutoff")}
        for row in end_audit if any(row[field][:10] in {previous_day, cutoff_day} for field in ("create_date", "activation_date", "end_date"))
    ]

    failures = [check for check in audit.checks if not check["pass"]]
    result = {"verdict": "FAIL" if failures else "PASS", "delivery": str(args.delivery), "baseline": str(args.baseline), "cutoff_at": cutoff, "backup_finish_at": backup_finish, "checks": audit.checks, "warnings": audit.warnings, "details": audit.details}
    (args.output / "audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")
    lines = ["# Независимая проверка сентябрьской поставки", "", f"Результат: **{result['verdict']}**. Проверок: {len(audit.checks)}, ошибок: {len(failures)}.", "", f"Backup завершён: `{backup_finish}`. Единый срез: `{cutoff}`.", "", "Июньская поставка использована для проверки структуры, заголовков и сохранения явно закреплённых параметров шаблонов. Числа строк сентября сверены с текущей выгрузкой, а не с июньскими количествами.", "", "| Файл | Июнь | Сентябрь | Столбцов |", "| --- | ---: | ---: | ---: |"]
    lines += [f"| {row['file']} | {row['june_rows']} | {row['september_rows']} | {row['columns']} |" for row in counts]
    lines += ["", "Проверены все строки и листы, ID, телефоны, детерминированный менеджер каждого клиента во всех слоях, филиалы, подписи воронок, связи с шаблонами, полное разделение main/problem4, суммы и даты staging, а также SHA-256 передаваемых файлов.", "", f"Граница окончания абонементов {previous_day}/{cutoff_day}: {len(boundary)} клиентов. Данные примеров: `{args.output / 'audit.json'}`.", "", "| Контроль | Результат |", "| --- | --- |"]
    lines += [f"| {item['check']} | {'PASS' if item['pass'] else 'FAIL'} |" for item in audit.checks]
    lines += ["", "Предупреждения (не ошибки):"]
    lines += [f"- {warning}" for warning in audit.warnings] or ["- Нет."]
    lines += ["", "Сверка CSV/TSV доказывает сохранность текущей выгрузки. Независимая проверка исходной SQL-базы выполняется отдельно; этот скрипт не утверждает правильность SQL только на основании совпадения с CSV.", ""]
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text("\n".join(lines), encoding="utf-8")
    print(f"{result['verdict']}: {len(audit.checks)} checks, {len(failures)} failures", flush=True)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
