#!/usr/bin/env python3
"""Build and export Part 2 three-funnel SQL staging tables."""

from __future__ import annotations

import argparse
import csv
import os
import subprocess
from pathlib import Path
from typing import Iterable


ROOT = Path(__file__).resolve().parents[1]
SQLCMD = ROOT / "scripts" / "sqlcmd.sh"
SQL_DIR = ROOT / "sql"
BUILD_SQL = SQL_DIR / "part2_03_build_three_funnel_staging.sql"

STAGE_TABLES = [
    "staging_run_metadata",
    "stg_clients",
    "stg_client_contacts",
    "stg_products",
    "stg_subscriptions_all",
    "stg_sales_all",
    "stg_plastic_cards",
    "client_history_summary",
    "subscription_candidates_ranked",
    "selected_subscriptions",
    "selected_cards",
    "final_funnel_clients",
]

DISCOVERY_TABLES = [
    "club_reference_candidates",
    "club_link_candidates",
]

ORDER_BY = {
    "staging_run_metadata": "cutoff_date",
    "stg_clients": "client_ref",
    "stg_client_contacts": "client_ref, contact_type, raw_value",
    "stg_products": "product_class, needs_manual_review DESC, observed_clients DESC, product_name",
    "stg_subscriptions_all": "client_ref, is_full_subscription DESC, end_date DESC, start_date DESC, subscription_ref",
    "stg_sales_all": "client_ref, sale_date, sale_ref",
    "stg_plastic_cards": "client_ref, is_unmarked DESC, issue_date DESC, card_ref",
    "client_history_summary": "client_ref",
    "subscription_candidates_ranked": "client_ref, candidate_for_funnel, rank_number, subscription_ref",
    "selected_subscriptions": "client_ref, selected_for_funnel",
    "selected_cards": "client_ref",
    "final_funnel_clients": "funnel, funnel_step, client_id, client_ref",
    "club_reference_candidates": "table_name, normalized_club, description, ref_hex",
    "club_link_candidates": "matched_rows DESC, target_table, target_column",
}


def clean_sqlcmd_lines(text: str) -> list[str]:
    lines: list[str] = []
    for raw_line in text.replace("\x00", "").splitlines():
        line = raw_line.strip()
        if not line:
            continue
        if line.startswith("mesg:") or line.startswith("Changed database context"):
            continue
        if line.startswith("(") and "rows affected" in line:
            continue
        if set(line) <= {"-"}:
            continue
        lines.append(line)
    return lines


def render_build_sql(cutoff_date: str, backup_finish_at: str, output_run_label: str) -> Path:
    rendered = (
        BUILD_SQL.read_text(encoding="utf-8")
        .replace("$(cutoff_date)", cutoff_date)
        .replace("$(backup_finish_at)", backup_finish_at)
        .replace("$(output_run_label)", output_run_label)
    )
    path = SQL_DIR / f".tmp_part2_build_{os.getpid()}_{cutoff_date.replace('-', '')}.sql"
    path.write_text(rendered, encoding="utf-8")
    return path


def run_sql_file(sql_path: Path, log_path: Path) -> None:
    cmd = [str(SQLCMD), "-d", "FitnessRestored", "-i", f"/sql/{sql_path.name}"]
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    output = proc.stdout + proc.stderr
    log_path.write_text(output, encoding="utf-8")
    if proc.returncode != 0 or "\nMsg " in output or output.lstrip().startswith("Msg "):
        raise RuntimeError(f"SQL command failed with exit code {proc.returncode}; see {log_path}")


def object_exists(table: str) -> bool:
    query = (
        "SET NOCOUNT ON; "
        f"SELECT CASE WHEN OBJECT_ID(N'fitbase_part2.{table}') IS NULL THEN 0 ELSE 1 END;"
    )
    cmd = [str(SQLCMD), "-d", "FitnessRestored", "-h", "-1", "-W", "-Q", query]
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        return False
    lines = clean_sqlcmd_lines(proc.stdout + proc.stderr)
    return bool(lines and lines[-1] == "1")


def get_columns(table: str) -> list[str]:
    query = (
        "SET NOCOUNT ON; "
        "SELECT c.name "
        "FROM sys.columns AS c "
        f"WHERE c.object_id = OBJECT_ID(N'fitbase_part2.{table}') "
        "ORDER BY c.column_id;"
    )
    cmd = [str(SQLCMD), "-d", "FitnessRestored", "-h", "-1", "-W", "-s", "|", "-Q", query]
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"Could not read columns for {table}: {proc.stdout}{proc.stderr}")
    return clean_sqlcmd_lines(proc.stdout + proc.stderr)


def render_export_sql(table: str, columns: list[str]) -> Path:
    expressions = []
    for column in columns:
        quoted = f"[{column}]"
        expressions.append(
            "REPLACE(REPLACE(REPLACE("
            f"COALESCE(CONVERT(nvarchar(max), {quoted}), N''), "
            "CHAR(9), N' '), CHAR(13), N' '), CHAR(10), N' ')"
            f" AS {quoted}"
        )
    sql = (
        "SET NOCOUNT ON;\n"
        "SELECT\n    "
        + ",\n    ".join(expressions)
        + f"\nFROM fitbase_part2.{table}\n"
        + f"ORDER BY {ORDER_BY[table]};\n"
    )
    path = SQL_DIR / f".tmp_part2_export_{table}_{os.getpid()}.sql"
    path.write_text(sql, encoding="utf-8")
    return path


def export_table(table: str, output_path: Path, log_handle) -> int:
    columns = get_columns(table)
    sql_path = render_export_sql(table, columns)
    row_count = 0
    cmd = [
        str(SQLCMD),
        "-d",
        "FitnessRestored",
        "-h",
        "-1",
        "-W",
        "-s",
        "\t",
        "-i",
        f"/sql/{sql_path.name}",
    ]
    try:
        with output_path.open("w", newline="", encoding="utf-8") as csv_file:
            writer = csv.writer(csv_file, lineterminator="\n")
            writer.writerow(columns)
            proc = subprocess.Popen(
                cmd,
                cwd=ROOT,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
            )
            assert proc.stdout is not None
            for raw_line in proc.stdout:
                line = raw_line.replace("\x00", "").rstrip("\r\n")
                stripped = line.strip()
                if not stripped:
                    continue
                if stripped.startswith("mesg:") or stripped.startswith("Changed database context"):
                    continue
                if stripped.startswith("(") and "rows affected" in stripped:
                    continue
                if stripped.startswith("Msg "):
                    log_handle.write(f"{table}: {stripped}\n")
                    continue
                values = line.split("\t")
                if len(values) != len(columns):
                    log_handle.write(
                        f"{table}: skipped malformed line with {len(values)} fields; expected {len(columns)}\n"
                    )
                    continue
                writer.writerow(values)
                row_count += 1
        return_code = proc.wait()
        if return_code != 0:
            raise RuntimeError(f"Export failed for {table} with exit code {return_code}")
    finally:
        sql_path.unlink(missing_ok=True)

    log_handle.write(f"{table}: exported {row_count} rows to {output_path.relative_to(ROOT)}\n")
    return row_count


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: Iterable[dict[str, object]], fieldnames: list[str]) -> None:
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


def write_product_reports(staging_dir: Path, reports_dir: Path) -> None:
    rows = read_csv(staging_dir / "stg_products.csv")
    observed = [
        row
        for row in rows
        if int_value(row.get("observed_sale_rows")) > 0
        or int_value(row.get("observed_subscription_rows")) > 0
        or row.get("is_full_subscription_candidate") == "1"
        or row.get("is_trial_or_guest_candidate") == "1"
        or row.get("needs_manual_review") == "1"
    ]
    preflight_rows = []
    for row in observed:
        product_class = row.get("product_class", "")
        preflight_rows.append(
            {
                **row,
                "auto_classification": product_class,
                "is_unknown": "1" if product_class == "unknown_review_required" else "0",
            }
        )

    preflight_fields = [
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
    ]
    for row in preflight_rows:
        row["observed_sales"] = row.get("observed_sale_rows", "")
    write_csv(reports_dir / "product_classification_preflight.csv", preflight_rows, preflight_fields)

    report_fields = [
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
    ]
    report_rows = []
    for row in observed:
        report_rows.append(
            {
                **row,
                "is_full_subscription": "1" if row.get("product_class") == "full_subscription" else "0",
                "is_trial_or_guest": "1" if row.get("product_class") == "trial_or_guest" else "0",
                "observed_sales": row.get("observed_sale_rows", ""),
            }
        )
    write_csv(reports_dir / "product_classification_report.csv", report_rows, report_fields)

    review_rows = []
    for row in observed:
        product_class = row.get("product_class", "")
        needs_review = row.get("needs_manual_review") == "1" or product_class == "unknown_review_required"
        if not needs_review:
            continue
        review_reason = row.get("classification_reason", "")
        recommended_action = "manual_review"
        if product_class == "full_subscription" and "замороз" in (row.get("product_name") or "").lower():
            recommended_action = "keep_full_subscription_unless_customer_says_otherwise"
        review_rows.append(
            {
                **row,
                "auto_classification": product_class,
                "observed_sales": row.get("observed_sale_rows", ""),
                "review_reason": review_reason,
                "recommended_action": recommended_action,
            }
        )
    review_fields = [
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
    ]
    write_csv(reports_dir / "product_classification_review_report.csv", review_rows, review_fields)


def write_summary_doc(
    reports_dir: Path,
    row_counts: dict[str, int],
    cutoff_date: str,
    backup_finish_at: str,
    output_run_label: str,
) -> None:
    lines = [
        "# Part 2 stage export",
        "",
        f"cutoff_date: `{cutoff_date}`",
        f"backup_finish_at: `{backup_finish_at}`",
        f"output_run_label: `{output_run_label}`",
        "",
        "## Row counts",
        "",
    ]
    for table, count in row_counts.items():
        lines.append(f"- `{table}`: `{count}`")
    lines.append("")
    (reports_dir / "stage_export_summary.md").write_text("\n".join(lines), encoding="utf-8")


def build_and_export(args: argparse.Namespace) -> None:
    cutoff_date = args.cutoff_date
    output_dir = Path(args.output_dir)
    if not output_dir.is_absolute():
        output_dir = ROOT / output_dir
    reports_dir = Path(args.reports_dir) if args.reports_dir else output_dir.parent / "reports"
    if not reports_dir.is_absolute():
        reports_dir = ROOT / reports_dir
    logs_dir = Path(args.logs_dir)
    if not logs_dir.is_absolute():
        logs_dir = ROOT / logs_dir
    output_run_label = args.output_run_label or f"part2_{cutoff_date.replace('-', '')}"

    output_dir.mkdir(parents=True, exist_ok=True)
    reports_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    build_log = logs_dir / f"part2_03_build_three_funnel_staging_{cutoff_date.replace('-', '')}.txt"
    export_log = logs_dir / f"part2_03_export_stage_{cutoff_date.replace('-', '')}.txt"

    if not args.skip_build:
        rendered = render_build_sql(cutoff_date, args.backup_finish_at, output_run_label)
        try:
            run_sql_file(rendered, build_log)
        finally:
            rendered.unlink(missing_ok=True)

    row_counts: dict[str, int] = {}
    with export_log.open("w", encoding="utf-8") as log_handle:
        for table in STAGE_TABLES:
            row_counts[table] = export_table(table, output_dir / f"{table}.csv", log_handle)
        for table in DISCOVERY_TABLES:
            if object_exists(table):
                row_counts[table] = export_table(table, reports_dir / f"{table}.csv", log_handle)

    write_product_reports(output_dir, reports_dir)
    write_summary_doc(reports_dir, row_counts, cutoff_date, args.backup_finish_at, output_run_label)

    for table, count in row_counts.items():
        print(f"{table}_rows={count}")
    print(f"staging_dir={output_dir.relative_to(ROOT)}")
    print(f"reports_dir={reports_dir.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff-date", default="2026-04-29")
    parser.add_argument("--backup-finish-at", default="2026-04-29 23:57:02")
    parser.add_argument("--output-run-label", default="")
    parser.add_argument("--output-dir", default=str(ROOT / "output" / "part2_20260429" / "staging"))
    parser.add_argument("--reports-dir", default="")
    parser.add_argument("--logs-dir", default=str(ROOT / "logs"))
    parser.add_argument("--skip-build", action="store_true")
    return parser.parse_args()


def main() -> None:
    build_and_export(parse_args())


if __name__ == "__main__":
    main()
