#!/usr/bin/env python3
"""Build Fitbase staging tables in SQL and export them to CSV."""

from __future__ import annotations

import argparse
import csv
import os
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SQLCMD = ROOT / "scripts" / "sqlcmd.sh"
BUILD_SQL = ROOT / "sql" / "06_build_staging_tables.sql"
SQL_DIR = ROOT / "sql"

TABLES = [
    "staging_run_metadata",
    "stg_clients",
    "stg_client_contacts",
    "stg_subscriptions",
    "stg_sales",
    "stg_bookings",
    "stg_plastic_cards",
    "mart_active_clients",
]

DIAGNOSTIC_QUERIES = {
    "stage_distribution.csv": (
        ["funnel_step", "clients"],
        """
        SELECT funnel_step, COUNT_BIG(*) AS clients
        FROM fitbase_stg.mart_active_clients
        GROUP BY funnel_step
        ORDER BY clients DESC, funnel_step;
        """,
    ),
    "validation_status_distribution.csv": (
        ["validation_status", "clients"],
        """
        SELECT validation_status, COUNT_BIG(*) AS clients
        FROM fitbase_stg.mart_active_clients
        GROUP BY validation_status
        ORDER BY clients DESC, validation_status;
        """,
    ),
    "active_subscription_count_distribution.csv": (
        ["active_subscription_count", "clients"],
        """
        SELECT active_subscription_count, COUNT_BIG(*) AS clients
        FROM fitbase_stg.mart_active_clients
        GROUP BY active_subscription_count
        ORDER BY active_subscription_count;
        """,
    ),
    "active_card_count_distribution.csv": (
        ["active_card_count", "clients"],
        """
        SELECT active_card_count, COUNT_BIG(*) AS clients
        FROM fitbase_stg.mart_active_clients
        GROUP BY active_card_count
        ORDER BY active_card_count;
        """,
    ),
    "short_duration_active_distribution.csv": (
        ["is_short_duration_active", "clients"],
        """
        SELECT is_short_duration_active, COUNT_BIG(*) AS clients
        FROM fitbase_stg.mart_active_clients
        GROUP BY is_short_duration_active
        ORDER BY is_short_duration_active;
        """,
    ),
}

ORDER_BY = {
    "staging_run_metadata": "cutoff_date",
    "stg_clients": "client_ref",
    "stg_client_contacts": "client_ref, contact_type, raw_value",
    "stg_subscriptions": "client_ref, end_date DESC, start_date DESC, subscription_ref",
    "stg_sales": "client_ref, sale_date, sale_ref",
    "stg_bookings": "client_ref, booking_date, booking_ref",
    "stg_plastic_cards": "client_ref, is_unmarked DESC, issue_date DESC, card_ref",
    "mart_active_clients": "client_ref",
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


def run_sql_file(sql_path: Path, log_path: Path) -> None:
    cmd = [str(SQLCMD), "-d", "FitnessRestored", "-i", f"/sql/{sql_path.name}"]
    proc = subprocess.run(cmd, cwd=ROOT, text=True, capture_output=True, check=False)
    log_path.write_text(proc.stdout + proc.stderr, encoding="utf-8")
    if proc.returncode != 0:
        raise RuntimeError(f"SQL command failed with exit code {proc.returncode}; see {log_path}")


def render_build_sql(cutoff_date: str, backup_finish_at: str) -> Path:
    rendered = (
        BUILD_SQL.read_text(encoding="utf-8")
        .replace("$(cutoff_date)", cutoff_date)
        .replace("$(backup_finish_at)", backup_finish_at)
    )
    path = SQL_DIR / f".tmp_build_staging_{os.getpid()}.sql"
    path.write_text(rendered, encoding="utf-8")
    return path


def get_columns(table: str) -> list[str]:
    query = (
        "SET NOCOUNT ON; "
        "SELECT c.name "
        "FROM sys.columns AS c "
        f"WHERE c.object_id = OBJECT_ID(N'fitbase_stg.{table}') "
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
        + f"\nFROM fitbase_stg.{table}\n"
        + f"ORDER BY {ORDER_BY[table]};\n"
    )
    path = SQL_DIR / f".tmp_export_{table}_{os.getpid()}.sql"
    path.write_text(sql, encoding="utf-8")
    return path


def export_table(table: str, output_dir: Path, log_handle) -> int:
    columns = get_columns(table)
    sql_path = render_export_sql(table, columns)
    output_path = output_dir / f"{table}.csv"
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
                        f"{table}: skipped malformed line with {len(values)} fields; "
                        f"expected {len(columns)}\n"
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


def write_summary(output_dir: Path, row_counts: dict[str, int], cutoff_date: str, backup_finish_at: str) -> None:
    summary_path = output_dir / "staging_summary.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["metric", "value"])
        writer.writerow(["cutoff_date", cutoff_date])
        writer.writerow(["backup_finish_at", backup_finish_at])
        for table in TABLES:
            writer.writerow([f"{table}_rows", row_counts.get(table, 0)])


def export_diagnostic_query(file_name: str, columns: list[str], query: str, output_dir: Path) -> int:
    sql_path = SQL_DIR / f".tmp_diagnostic_{Path(file_name).stem}_{os.getpid()}.sql"
    sql_path.write_text("SET NOCOUNT ON;\n" + query.strip() + "\n", encoding="utf-8")
    output_path = output_dir / file_name
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
                values = line.split("\t")
                if len(values) != len(columns):
                    continue
                writer.writerow(values)
                row_count += 1
        return_code = proc.wait()
        if return_code != 0:
            raise RuntimeError(f"Diagnostic export failed for {file_name} with exit code {return_code}")
    finally:
        sql_path.unlink(missing_ok=True)
    return row_count


def export_diagnostics(output_dir: Path) -> dict[str, int]:
    counts: dict[str, int] = {}
    for file_name, (columns, query) in DIAGNOSTIC_QUERIES.items():
        counts[file_name] = export_diagnostic_query(file_name, columns, query, output_dir)
    return counts


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cutoff-date", default="2026-04-29")
    parser.add_argument("--backup-finish-at", default="2026-04-29 23:57:02")
    parser.add_argument("--output-dir", default=None)
    parser.add_argument("--logs-dir", default=str(ROOT / "logs"))
    parser.add_argument("--skip-build", action="store_true")
    parser.add_argument("--diagnostics-only", action="store_true")
    args = parser.parse_args()

    output_dir = Path(args.output_dir) if args.output_dir else ROOT / "output" / f"staging_{args.cutoff_date}"
    logs_dir = Path(args.logs_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    logs_dir.mkdir(parents=True, exist_ok=True)

    build_log = logs_dir / "step14_build_staging_tables.txt"
    export_log = logs_dir / "step14_export_staging_tables.txt"

    if not args.skip_build and not args.diagnostics_only:
        build_sql = render_build_sql(args.cutoff_date, args.backup_finish_at)
        try:
            run_sql_file(build_sql, build_log)
        finally:
            build_sql.unlink(missing_ok=True)

    row_counts: dict[str, int] = {}
    if not args.diagnostics_only:
        with export_log.open("w", encoding="utf-8") as log_handle:
            log_handle.write(f"cutoff_date={args.cutoff_date}\n")
            log_handle.write(f"backup_finish_at={args.backup_finish_at}\n")
            for table in TABLES:
                row_counts[table] = export_table(table, output_dir, log_handle)

        write_summary(output_dir, row_counts, args.cutoff_date, args.backup_finish_at)

    diagnostic_counts = export_diagnostics(output_dir)
    for table in TABLES:
        if table in row_counts:
            print(f"{table}_rows={row_counts[table]}")
    for file_name, rows in diagnostic_counts.items():
        print(f"{file_name}_rows={rows}")
    print(f"wrote={output_dir.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
