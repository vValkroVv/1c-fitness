#!/usr/bin/env python3
"""Compare active clients from restored SQL backup with manager CSV export."""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import os
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import date, datetime
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
SQL_SCRIPT = ROOT / "sql" / "05_export_active_clients_snapshot.sql"
SQLCMD = ROOT / "scripts" / "sqlcmd.sh"

LENGTH_BUCKETS = [
    "00_unknown",
    "01_up_to_2_weeks",
    "02_1_month",
    "03_2_months",
    "04_3_months",
    "05_4_5_months",
    "06_6_months",
    "07_9_months",
    "08_12_months",
    "09_13_15_months",
    "10_16_18_months",
    "11_19_24_months",
    "12_24_plus_months",
]

SQL_FIELDS = [
    "client_ref_hex",
    "client_code",
    "client_name",
    "client_phone",
    "in_target_segment",
    "in_chk_kk_segment",
    "has_active_duration_30",
    "doc_date",
    "start_date",
    "valid_until",
    "duration_days",
    "calc_duration_days",
    "product_code",
    "product_name",
    "status_name",
]

SUMMARY_METRICS = [
    "snapshot_date",
    "csv_active_rows",
    "csv_active_unique_clients",
    "csv_active_unique_phones",
    "sql_active_unique_clients",
    "sql_active_unique_phones",
    "sql_active_duration_30_plus_clients",
    "sql_active_in_target_segment_clients",
    "sql_active_in_chk_kk_segment_clients",
    "csv_clients_with_sql_phone_match",
    "sql_clients_with_csv_phone_match",
    "csv_clients_with_sql_phone_and_name_match",
    "sql_clients_with_csv_phone_and_name_match",
    "sql_minus_csv_unique_clients",
]


@dataclass
class CsvClient:
    key: str
    name: str
    name_norm: str
    phones: set[str]
    product_name: str
    sale_date: date
    valid_to: date
    duration_days: int | None
    club: str


@dataclass
class SqlClient:
    client_ref_hex: str
    client_code: str
    name: str
    name_norm: str
    phones: set[str]
    in_target_segment: bool
    in_chk_kk_segment: bool
    has_active_duration_30: bool
    product_name: str
    start_date: date | None
    valid_until: date | None
    duration_days: int | None
    calc_duration_days: int | None
    status_name: str


def normalize_name(value: str) -> str:
    value = (value or "").casefold().replace("ё", "е")
    value = re.sub(r"[^0-9a-zа-я]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def normalize_phones(value: str) -> set[str]:
    phones: set[str] = set()
    for part in re.split(r"[,;/]+", value or ""):
        digits = re.sub(r"\D", "", part)
        if len(digits) < 10:
            continue
        if len(digits) == 11 and digits[0] in {"7", "8"}:
            digits = digits[1:]
        elif len(digits) > 10:
            digits = digits[-10:]
        if len(digits) == 10:
            phones.add(digits)
    return phones


def parse_date(value: str) -> date | None:
    value = (value or "").strip()
    if not value:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d"):
        try:
            return datetime.strptime(value[:19], fmt).date()
        except ValueError:
            pass
    return datetime.fromisoformat(value).date()


def parse_int(value: str) -> int | None:
    value = (value or "").strip()
    if not value:
        return None
    try:
        return int(float(value))
    except ValueError:
        return None


def is_membership_product(product_name: str) -> bool:
    name = (product_name or "").casefold().replace("ё", "е")
    tokens = ("абонемент", "мульти", "ультра", "членств")
    return any(token in name for token in tokens)


def length_bucket(days: int | None) -> str:
    if days is None or days <= 0:
        return "00_unknown"
    if days <= 16:
        return "01_up_to_2_weeks"
    if days <= 45:
        return "02_1_month"
    if days <= 75:
        return "03_2_months"
    if days <= 120:
        return "04_3_months"
    if days <= 165:
        return "05_4_5_months"
    if days <= 230:
        return "06_6_months"
    if days <= 320:
        return "07_9_months"
    if days <= 410:
        return "08_12_months"
    if days <= 500:
        return "09_13_15_months"
    if days <= 590:
        return "10_16_18_months"
    if days <= 760:
        return "11_19_24_months"
    return "12_24_plus_months"


def client_key(name_norm: str, phones: set[str], fallback: str) -> str:
    if phones:
        return f"phone_name:{sorted(phones)[0]}:{name_norm}"
    return f"name:{name_norm}:{fallback}"


def load_csv_clients(csv_path: Path, snapshot: date) -> tuple[list[dict[str, str]], dict[str, CsvClient]]:
    active_rows: list[dict[str, str]] = []
    clients: dict[str, CsvClient] = {}

    with csv_path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            product_name = row.get("product_name", "")
            if not is_membership_product(product_name):
                continue

            sale_date = parse_date(row.get("sale_datetime", ""))
            valid_to = parse_date(row.get("valid_to", ""))
            if sale_date is None or valid_to is None:
                continue
            if sale_date > snapshot or valid_to < snapshot:
                continue

            active_rows.append(row)
            phones = normalize_phones(row.get("phone", ""))
            name = row.get("client_name", "").strip()
            name_norm = normalize_name(name)
            key = client_key(name_norm, phones, row.get("birth_date", ""))
            duration_days = (valid_to - sale_date).days + 1
            candidate = CsvClient(
                key=key,
                name=name,
                name_norm=name_norm,
                phones=phones,
                product_name=product_name,
                sale_date=sale_date,
                valid_to=valid_to,
                duration_days=duration_days,
                club=row.get("club", ""),
            )
            previous = clients.get(key)
            if previous is None or (candidate.valid_to, candidate.sale_date) > (previous.valid_to, previous.sale_date):
                clients[key] = candidate

    return active_rows, clients


def run_sql_export(snapshot: date, logs_dir: Path, tmp_dir: Path) -> list[dict[str, str]]:
    logs_dir.mkdir(parents=True, exist_ok=True)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    log_path = logs_dir / f"step12_gym_sales_compare_{snapshot.isoformat()}_sql_export.txt"
    cleaned_path = tmp_dir / f"active_sql_clients_{snapshot.isoformat()}.psv"
    generated_sql = ROOT / "sql" / f".tmp_active_clients_snapshot_{snapshot.isoformat()}_{os.getpid()}.sql"
    generated_sql.write_text(
        SQL_SCRIPT.read_text(encoding="utf-8").replace("$(snapshot_date)", snapshot.isoformat()),
        encoding="utf-8",
    )

    cmd = [
        str(SQLCMD),
        "-d",
        "FitnessRestored",
        "-h",
        "-1",
        "-W",
        "-s",
        "|",
        "-i",
        f"/sql/{generated_sql.name}",
    ]
    try:
        proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
        log_path.write_text(proc.stdout + proc.stderr, encoding="utf-8")
        if proc.returncode != 0:
            raise RuntimeError(f"SQL export failed with exit code {proc.returncode}; see {log_path}")
    finally:
        generated_sql.unlink(missing_ok=True)

    lines = []
    for raw_line in proc.stdout.replace("\x00", "").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("mesg:") or line.startswith("Changed database context"):
            continue
        if line.startswith("(") and "rows affected" in line:
            continue
        lines.append(line)

    cleaned_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    reader = csv.DictReader(lines, delimiter="|", fieldnames=SQL_FIELDS)
    return list(reader)


def load_sql_clients(rows: Iterable[dict[str, str]]) -> dict[str, SqlClient]:
    clients: dict[str, SqlClient] = {}
    for row in rows:
        ref = row.get("client_ref_hex", "").strip()
        if not ref or ref == "client_ref_hex":
            continue
        name = row.get("client_name", "").strip()
        duration = parse_int(row.get("duration_days", ""))
        calc_duration = parse_int(row.get("calc_duration_days", ""))
        clients[ref] = SqlClient(
            client_ref_hex=ref,
            client_code=row.get("client_code", "").strip(),
            name=name,
            name_norm=normalize_name(name),
            phones=normalize_phones(row.get("client_phone", "")),
            in_target_segment=row.get("in_target_segment") == "1",
            in_chk_kk_segment=row.get("in_chk_kk_segment") == "1",
            has_active_duration_30=row.get("has_active_duration_30") == "1",
            product_name=row.get("product_name", ""),
            start_date=parse_date(row.get("start_date", "")),
            valid_until=parse_date(row.get("valid_until", "")),
            duration_days=duration,
            calc_duration_days=calc_duration,
            status_name=row.get("status_name", ""),
        )
    return clients


def phone_set(clients: Iterable[CsvClient | SqlClient]) -> set[str]:
    return {phone for client in clients for phone in client.phones}


def phone_name_set(clients: Iterable[CsvClient | SqlClient]) -> set[tuple[str, str]]:
    return {(phone, client.name_norm) for client in clients for phone in client.phones if client.name_norm}


def count_with_phone_match(clients: Iterable[CsvClient | SqlClient], other_phones: set[str]) -> int:
    return sum(1 for client in clients if client.phones & other_phones)


def count_with_phone_name_match(
    clients: Iterable[CsvClient | SqlClient],
    other_phone_names: set[tuple[str, str]],
) -> int:
    return sum(
        1
        for client in clients
        if any((phone, client.name_norm) in other_phone_names for phone in client.phones)
    )


def build_summary_rows(
    snapshot: date,
    csv_rows: list[dict[str, str]],
    csv_clients: dict[str, CsvClient],
    sql_clients: dict[str, SqlClient],
) -> list[tuple[str, str | int]]:
    csv_values = list(csv_clients.values())
    sql_values = list(sql_clients.values())
    csv_phones = phone_set(csv_values)
    sql_phones = phone_set(sql_values)
    csv_phone_names = phone_name_set(csv_values)
    sql_phone_names = phone_name_set(sql_values)

    rows = [
        ("snapshot_date", snapshot.isoformat()),
        ("csv_active_rows", len(csv_rows)),
        ("csv_active_unique_clients", len(csv_clients)),
        ("csv_active_unique_phones", len(csv_phones)),
        ("sql_active_unique_clients", len(sql_clients)),
        ("sql_active_unique_phones", len(sql_phones)),
        ("sql_active_duration_30_plus_clients", sum(c.has_active_duration_30 for c in sql_values)),
        ("sql_active_in_target_segment_clients", sum(c.in_target_segment for c in sql_values)),
        ("sql_active_in_chk_kk_segment_clients", sum(c.in_chk_kk_segment for c in sql_values)),
        ("csv_clients_with_sql_phone_match", count_with_phone_match(csv_values, sql_phones)),
        ("sql_clients_with_csv_phone_match", count_with_phone_match(sql_values, csv_phones)),
        ("csv_clients_with_sql_phone_and_name_match", count_with_phone_name_match(csv_values, sql_phone_names)),
        ("sql_clients_with_csv_phone_and_name_match", count_with_phone_name_match(sql_values, csv_phone_names)),
        ("sql_minus_csv_unique_clients", len(sql_clients) - len(csv_clients)),
    ]
    return rows


def write_summary(path: Path, rows: list[tuple[str, str | int]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["metric", "value"])
        writer.writerows(rows)


def write_combined_summary(path: Path, summaries: list[list[tuple[str, str | int]]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(SUMMARY_METRICS)
        for summary in summaries:
            metrics = dict(summary)
            writer.writerow([metrics.get(metric, "") for metric in SUMMARY_METRICS])


def bucket_counts_csv(clients: Iterable[CsvClient]) -> Counter[str]:
    return Counter(length_bucket(client.duration_days) for client in clients)


def bucket_counts_sql(clients: Iterable[SqlClient]) -> Counter[str]:
    counts: Counter[str] = Counter()
    for client in clients:
        days = client.calc_duration_days if client.calc_duration_days and client.calc_duration_days > 0 else client.duration_days
        counts[length_bucket(days)] += 1
    return counts


def write_length_breakdown(
    path: Path,
    csv_clients: dict[str, CsvClient],
    sql_clients: dict[str, SqlClient],
) -> None:
    csv_counts = bucket_counts_csv(csv_clients.values())
    sql_counts = bucket_counts_sql(sql_clients.values())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["length_bucket", "csv_clients", "sql_clients", "sql_minus_csv"])
        for bucket in LENGTH_BUCKETS:
            writer.writerow([bucket, csv_counts[bucket], sql_counts[bucket], sql_counts[bucket] - csv_counts[bucket]])


def write_top_products(
    path: Path,
    csv_clients: dict[str, CsvClient],
    sql_clients: dict[str, SqlClient],
) -> None:
    counters: dict[tuple[str, str], Counter[str]] = defaultdict(Counter)
    for client in csv_clients.values():
        counters[("csv", length_bucket(client.duration_days))][client.product_name] += 1
    for client in sql_clients.values():
        days = client.calc_duration_days if client.calc_duration_days and client.calc_duration_days > 0 else client.duration_days
        counters[("sql", length_bucket(days))][client.product_name] += 1

    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["source", "length_bucket", "product_name", "clients"])
        for (source, bucket), counter in sorted(counters.items()):
            for product_name, count in counter.most_common(15):
                writer.writerow([source, bucket, product_name, count])


def write_overlap_breakdown(
    path: Path,
    csv_clients: dict[str, CsvClient],
    sql_clients: dict[str, SqlClient],
) -> None:
    sql_phones = phone_set(sql_clients.values())
    csv_phones = phone_set(csv_clients.values())
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["source", "length_bucket", "clients", "clients_with_phone_match_in_other_source"])
        csv_by_bucket: dict[str, list[CsvClient]] = defaultdict(list)
        sql_by_bucket: dict[str, list[SqlClient]] = defaultdict(list)
        for client in csv_clients.values():
            csv_by_bucket[length_bucket(client.duration_days)].append(client)
        for client in sql_clients.values():
            days = client.calc_duration_days if client.calc_duration_days and client.calc_duration_days > 0 else client.duration_days
            sql_by_bucket[length_bucket(days)].append(client)
        for bucket in LENGTH_BUCKETS:
            csv_bucket = csv_by_bucket.get(bucket, [])
            sql_bucket = sql_by_bucket.get(bucket, [])
            writer.writerow([
                "csv",
                bucket,
                len(csv_bucket),
                count_with_phone_match(csv_bucket, sql_phones),
            ])
            writer.writerow([
                "sql",
                bucket,
                len(sql_bucket),
                count_with_phone_match(sql_bucket, csv_phones),
            ])


def run_snapshot(
    snapshot: date,
    csv_path: Path,
    output_dir: Path,
    logs_dir: Path,
    tmp_dir: Path,
) -> list[tuple[str, str | int]]:
    csv_rows, csv_clients = load_csv_clients(csv_path, snapshot)
    sql_rows = run_sql_export(snapshot, logs_dir, tmp_dir)
    sql_clients = load_sql_clients(sql_rows)

    suffix = snapshot.isoformat()
    summary_rows = build_summary_rows(snapshot, csv_rows, csv_clients, sql_clients)
    write_summary(output_dir / f"active_compare_{suffix}_summary.csv", summary_rows)
    write_length_breakdown(
        output_dir / f"active_compare_{suffix}_length_breakdown.csv",
        csv_clients,
        sql_clients,
    )
    write_overlap_breakdown(
        output_dir / f"active_compare_{suffix}_overlap_by_length.csv",
        csv_clients,
        sql_clients,
    )
    write_top_products(
        output_dir / f"active_compare_{suffix}_top_products.csv",
        csv_clients,
        sql_clients,
    )

    print(f"snapshot_date={suffix}")
    print(f"csv_active_rows={len(csv_rows)}")
    print(f"csv_active_unique_clients={len(csv_clients)}")
    print(f"sql_active_unique_clients={len(sql_clients)}")
    print(f"sql_minus_csv_unique_clients={len(sql_clients) - len(csv_clients)}")
    print(f"wrote=output/active_compare_{suffix}_*.csv")
    return summary_rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--snapshot-date",
        action="append",
        dest="snapshot_dates",
        help="Snapshot date in YYYY-MM-DD format. Can be passed multiple times.",
    )
    parser.add_argument("--csv", default=str(ROOT / "data" / "gym_sales.csv"))
    parser.add_argument("--output-dir", default=str(ROOT / "output"))
    parser.add_argument("--logs-dir", default=str(ROOT / "logs"))
    parser.add_argument("--tmp-dir", default=str(ROOT / "tmp"))
    parser.add_argument("--combined-summary-name", default="active_compare_snapshots_summary.csv")
    args = parser.parse_args()

    snapshot_values = args.snapshot_dates or ["2025-08-31"]
    snapshots = [datetime.strptime(value, "%Y-%m-%d").date() for value in snapshot_values]
    csv_path = Path(args.csv)
    output_dir = Path(args.output_dir)
    logs_dir = Path(args.logs_dir)
    tmp_dir = Path(args.tmp_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    summaries = [run_snapshot(snapshot, csv_path, output_dir, logs_dir, tmp_dir) for snapshot in snapshots]
    if len(summaries) > 1:
        combined_path = output_dir / args.combined_summary_name
        write_combined_summary(combined_path, summaries)
        print(f"wrote={combined_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
