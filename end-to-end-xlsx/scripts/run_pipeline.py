#!/usr/bin/env python3
"""Build the verified nine-XLSX Fitbase delivery from a restored SQL database."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import traceback
from datetime import datetime
from importlib.metadata import PackageNotFoundError, version
from pathlib import Path
from types import ModuleType
from typing import Any, Sequence

import openpyxl
import yaml

from database import ConnectionSettings, DatabaseClient, find_dbo_source_tables


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
SQL = ROOT / "sql"
CONFIG = ROOT / "config"
TEMPLATES = ROOT / "templates"

STEPS = [
    "preflight",
    "owner_sql",
    "owner_export",
    "reclassify",
    "main_xlsx",
    "membership_sql",
    "membership_export",
    "membership_xlsx",
    "services_sql",
    "services_export",
    "services_xlsx",
    "problem_xlsx",
    "delivery",
    "validate",
]

STAGE_TABLES = [
    "staging_run_metadata",
    "stg_clients",
    "stg_client_contacts",
    "stg_products",
    "stg_membership_owner_changes",
    "stg_subscriptions_all",
    "stg_sales_all",
    "stg_plastic_cards",
    "client_history_summary",
    "subscription_candidates_ranked",
    "selected_subscriptions",
    "selected_cards",
    "final_funnel_clients",
]

ORDER_BY = {
    "staging_run_metadata": "cutoff_date",
    "stg_clients": "client_ref",
    "stg_client_contacts": "client_ref, contact_type, raw_value",
    "stg_products": "product_class, needs_manual_review DESC, observed_clients DESC, product_name",
    "stg_membership_owner_changes": "membership_ref, owner_change_rank, owner_change_datetime, owner_change_ref",
    "stg_subscriptions_all": "client_ref, is_full_subscription DESC, end_date DESC, start_date DESC, subscription_ref",
    "stg_sales_all": "client_ref, sale_date, sale_ref",
    "stg_plastic_cards": "client_ref, is_unmarked DESC, issue_date DESC, card_ref",
    "client_history_summary": "client_ref",
    "subscription_candidates_ranked": "client_ref, candidate_for_funnel, rank_number, subscription_ref",
    "selected_subscriptions": "client_ref, selected_for_funnel",
    "selected_cards": "client_ref",
    "final_funnel_clients": "funnel, funnel_step, client_id, client_ref",
}


def as_abs(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def load_python_module(path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(module_name, path)
    if spec is None or spec.loader is None:
        raise ImportError(path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module


def sql_string(value: str) -> str:
    return value.replace("'", "''")


def sql_bracket_value(value: str) -> str:
    return value.replace("]", "]]")


def safe_path_component(value: Any, field: str) -> str:
    text = str(value)
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", text) or text in {".", ".."}:
        raise ValueError(f"{field} must be a single safe path component, got {text!r}")
    return text


def installed_version(distribution: str) -> str:
    try:
        return version(distribution)
    except PackageNotFoundError:
        return "unknown"


class Pipeline:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.config_path = as_abs(args.config)
        self.config = yaml.safe_load(self.config_path.read_text(encoding="utf-8"))
        self.run_config: dict[str, Any] = self.config["run"]
        self.sql_config: dict[str, Any] = self.config["sql"]
        self.validation_config: dict[str, Any] = self.config["validation"]
        self.backup_config: dict[str, Any] = self.config["backup"]
        self._apply_backup_cutoff_contract()

        for key, override in [
            ("server", args.server),
            ("port", args.port),
            ("database", args.database),
            ("user", args.user),
            ("password_env", args.password_env),
        ]:
            if override not in (None, ""):
                self.sql_config[key] = override

        password = self._read_password()
        tls_ca_file = str(self.sql_config.get("tls_ca_file", ""))
        if tls_ca_file:
            tls_ca_file = str(as_abs(tls_ca_file))
        self.connection_settings = ConnectionSettings(
            server=str(self.sql_config["server"]),
            port=int(self.sql_config["port"]),
            database=str(self.sql_config["database"]),
            user=str(self.sql_config["user"]),
            password=password,
            login_timeout_seconds=int(self.sql_config.get("login_timeout_seconds", 30)),
            query_timeout_seconds=int(self.sql_config.get("query_timeout_seconds", 0)),
            encrypt_login=bool(self.sql_config.get("encrypt_login", True)),
            tls_ca_file=tls_ca_file,
            tls_validate_host=bool(self.sql_config.get("tls_validate_host", True)),
        )

        self.date_stamp = safe_path_component(
            self.run_config["date_stamp"], "run.date_stamp"
        )
        work_name = safe_path_component(self.run_config["work_name"], "run.work_name")
        delivery_name = safe_path_component(
            self.run_config["delivery_name"], "run.delivery_name"
        )
        self.work_root = ROOT / "work" / work_name
        self.raw_root = self.work_root / "raw"
        self.owner_root = self.work_root / "owner"
        self.imports_root = self.work_root / "imports"
        self.reports_root = self.work_root / "reports"
        self.logs_root = ROOT / "logs" / work_name
        self.delivery_root = ROOT / "output" / delivery_name
        self.pipeline_log = self.logs_root / "pipeline.log"
        self.status_path = self.work_root / "status.json"
        if self.args.resume and self.status_path.is_file():
            self.status = json.loads(self.status_path.read_text(encoding="utf-8"))
            self.status.setdefault("resumed_at", []).append(
                datetime.now().isoformat(timespec="seconds")
            )
            self.status.pop("finished_at", None)
            self.status.pop("failed_at", None)
            self.status.pop("traceback", None)
        else:
            self.status = {
                "started_at": datetime.now().isoformat(timespec="seconds"),
                "config": str(self.config_path),
                "database": {
                    "server": self.connection_settings.server,
                    "port": self.connection_settings.port,
                    "database": self.connection_settings.database,
                    "user": self.connection_settings.user,
                },
                "cutoff_contract": {
                    "source": "backup.backup_finish_at",
                    "backup_finish_at": self.run_config["backup_finish_at"],
                    "cutoff_at": self.run_config["cutoff_at"],
                    "cutoff_date": self.run_config["cutoff_date"],
                    "date_stamp": self.run_config["date_stamp"],
                },
                "completed_steps": [],
                "row_counts": {},
                "cutoff_checks": {},
            }

    def _apply_backup_cutoff_contract(self) -> None:
        """Derive every export cutoff from RESTORE HEADERONLY.BackupFinishDate."""

        raw_finish = str(self.backup_config.get("backup_finish_at", "")).strip()
        try:
            backup_finish = datetime.strptime(raw_finish, "%Y-%m-%d %H:%M:%S")
        except ValueError as exc:
            raise ValueError(
                "backup.backup_finish_at must be RESTORE HEADERONLY.BackupFinishDate "
                "in YYYY-MM-DD HH:MM:SS format"
            ) from exc

        canonical = {
            "backup_finish_at": backup_finish.strftime("%Y-%m-%d %H:%M:%S"),
            "cutoff_at": backup_finish.strftime("%Y-%m-%d %H:%M:%S"),
            "cutoff_date": backup_finish.strftime("%Y-%m-%d"),
            "date_stamp": backup_finish.strftime("%Y%m%d"),
        }
        for field, expected in canonical.items():
            configured = str(self.run_config.get(field, expected)).strip()
            if configured != expected:
                raise ValueError(
                    f"run.{field}={configured!r} does not match "
                    f"backup.backup_finish_at-derived value {expected!r}"
                )
            self.run_config[field] = expected

        for legacy_field in ("membership_cutoff_at", "services_cutoff_at"):
            if legacy_field not in self.run_config:
                continue
            configured = str(self.run_config[legacy_field]).strip()
            if configured != canonical["cutoff_at"]:
                raise ValueError(
                    f"run.{legacy_field}={configured!r} does not match the single "
                    f"backup cutoff {canonical['cutoff_at']!r}"
                )

    def _record_cutoff_check(self, name: str, values: dict[str, Any]) -> None:
        self.status.setdefault("cutoff_checks", {})[name] = values
        self._write_status()

    def _check_owner_cutoff(self, db: DatabaseClient) -> None:
        rows = db.query_rows(
            """
            SELECT
                CONVERT(varchar(10), cutoff_date, 120),
                CONVERT(varchar(19), cutoff_at, 120),
                CONVERT(varchar(19), backup_finish_at, 120)
            FROM fitbase_part2.staging_run_metadata
            """
        )
        expected = (
            self.run_config["cutoff_date"],
            self.run_config["cutoff_at"],
            self.run_config["backup_finish_at"],
        )
        normalized = [tuple(str(value) for value in row) for row in rows]
        if len(normalized) != 1 or normalized[0] != expected:
            raise RuntimeError(
                "owner staging cutoff mismatch: "
                f"actual={normalized!r}, expected={[expected]!r}"
            )
        self._record_cutoff_check(
            "owner_stage",
            {
                "rows": 1,
                "cutoff_date": normalized[0][0],
                "cutoff_at": normalized[0][1],
                "backup_finish_at": normalized[0][2],
                "verdict": "PASS",
            },
        )

    def _check_fact_cutoff(
        self, db: DatabaseClient, *, table: str, check_name: str
    ) -> None:
        datetime_columns = {
            "membership_import_facts": ("sale_datetime", "matched_payment_datetime"),
            "services_import_facts": ("sale_datetime", "payment_datetime"),
        }
        if table not in datetime_columns:
            raise ValueError(f"Unsupported cutoff-check table: {table}")
        sale_column, payment_column = datetime_columns[table]
        row = db.query_rows(
            f"""
            SELECT
                COUNT_BIG(*),
                COUNT_BIG(cutoff_at),
                CONVERT(varchar(19), MIN(cutoff_at), 120),
                CONVERT(varchar(19), MAX(cutoff_at), 120),
                CONVERT(varchar(19), MAX({sale_column}), 120),
                CONVERT(varchar(19), MAX({payment_column}), 120)
            FROM fitbase_part2.{table}
            """
        )[0]
        count = int(row[0])
        non_null_cutoff_count = int(row[1])
        minimum = str(row[2] or "")
        maximum = str(row[3] or "")
        maximum_sale = str(row[4] or "")
        maximum_payment = str(row[5] or "")
        expected = str(self.run_config["cutoff_at"])
        if (
            count <= 0
            or non_null_cutoff_count != count
            or minimum != expected
            or maximum != expected
            or (maximum_sale and maximum_sale > expected)
            or (maximum_payment and maximum_payment > expected)
        ):
            raise RuntimeError(
                f"{check_name} cutoff mismatch: rows={count}, min={minimum!r}, "
                f"max={maximum!r}, max_sale={maximum_sale!r}, "
                f"max_payment={maximum_payment!r}, expected={expected!r}"
            )
        self._record_cutoff_check(
            check_name,
            {
                "rows": count,
                "non_null_cutoff_rows": non_null_cutoff_count,
                "minimum_cutoff_at": minimum,
                "maximum_cutoff_at": maximum,
                "maximum_sale_datetime": maximum_sale,
                "maximum_payment_datetime": maximum_payment,
                "expected_cutoff_at": expected,
                "verdict": "PASS",
            },
        )

    def _read_password(self) -> str:
        if self.args.password_file:
            value = (
                Path(self.args.password_file)
                .expanduser()
                .read_text(encoding="utf-8")
                .strip()
            )
            if not value:
                raise ValueError("Password file is empty")
            return value
        env_name = str(self.sql_config["password_env"])
        value = os.environ.get(env_name, "")
        if not value:
            raise ValueError(
                f"SQL password is missing. Set environment variable {env_name} "
                "or pass --password-file."
            )
        return value

    def prepare_directories(self) -> None:
        if not self.args.resume:
            shutil.rmtree(self.work_root, ignore_errors=True)
            shutil.rmtree(self.logs_root, ignore_errors=True)
            if self.delivery_root.exists():
                for path in self.delivery_root.glob("*.xlsx"):
                    path.unlink()
        for path in [
            self.raw_root / "staging",
            self.raw_root / "reports",
            self.owner_root / "staging",
            self.owner_root / "reports",
            self.owner_root / "csv",
            self.imports_root / "staging",
            self.imports_root / "reports",
            self.reports_root,
            self.logs_root,
            self.delivery_root,
        ]:
            path.mkdir(parents=True, exist_ok=True)
        self._write_status()

    def log(self, message: str) -> None:
        timestamp = datetime.now().isoformat(timespec="seconds")
        line = f"[{timestamp}] {message}"
        print(line, flush=True)
        self.pipeline_log.parent.mkdir(parents=True, exist_ok=True)
        with self.pipeline_log.open("a", encoding="utf-8") as handle:
            handle.write(line + "\n")

    def _write_status(self) -> None:
        self.status_path.parent.mkdir(parents=True, exist_ok=True)
        self.status_path.write_text(
            json.dumps(self.status, ensure_ascii=False, indent=2, default=str) + "\n",
            encoding="utf-8",
        )

    def mark_complete(self, step: str) -> None:
        self.status["completed_steps"].append(step)
        self.status["last_completed_at"] = datetime.now().isoformat(timespec="seconds")
        self._write_status()

    def run_command(
        self,
        step: str,
        command: Sequence[str | Path],
        *,
        env: dict[str, str] | None = None,
    ) -> None:
        command_text = [str(item) for item in command]
        log_path = self.logs_root / f"{step}.log"
        self.log(f"command {step}: {' '.join(command_text)}")
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        process = subprocess.run(
            command_text,
            cwd=ROOT,
            env=merged_env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            check=False,
        )
        log_path.write_text(process.stdout, encoding="utf-8")
        if process.returncode != 0:
            raise RuntimeError(
                f"Step {step} failed with exit code {process.returncode}; see {log_path}"
            )
        last_lines = [line for line in process.stdout.splitlines() if line.strip()][-4:]
        for line in last_lines:
            self.log(f"{step}: {line}")

    def preflight(self, db: DatabaseClient) -> None:
        row = db.query_rows(
            """
            SELECT
                DB_NAME() AS database_name,
                d.state_desc,
                d.compatibility_level,
                (SELECT COUNT(*)
                 FROM sys.tables AS t
                 JOIN sys.schemas AS s ON s.schema_id = t.schema_id
                 WHERE t.is_ms_shipped = 0 AND s.name = N'dbo') AS dbo_user_tables,
                @@VERSION AS sql_version
            FROM sys.databases AS d
            WHERE d.name = DB_NAME()
            """
        )[0]
        database_name, state_desc, compatibility_level, table_count, sql_version = row
        expected = yaml.safe_load(
            as_abs(self.validation_config["expected_manifest"]).read_text(
                encoding="utf-8"
            )
        )
        errors: list[str] = []
        expected_backup = expected.get("backup", {})
        expected_finish = str(expected_backup.get("backup_finish_at", "")).strip()
        if expected_finish != str(self.run_config["backup_finish_at"]):
            errors.append(
                "Expected manifest backup_finish_at is "
                f"{expected_finish!r}, configured backup finish is "
                f"{self.run_config['backup_finish_at']!r}"
            )
        for field in ("file_name", "size_bytes", "sha256"):
            configured = str(self.backup_config.get(field, "")).strip()
            reference = str(expected_backup.get(field, "")).strip()
            if configured != reference:
                errors.append(
                    f"Backup {field} mismatch: config={configured!r}, "
                    f"expected_manifest={reference!r}"
                )
        if str(database_name) != self.connection_settings.database:
            errors.append(
                f"Connected database is {database_name}, expected {self.connection_settings.database}"
            )
        if str(state_desc) != "ONLINE":
            errors.append(f"Database state is {state_desc}, expected ONLINE")
        if int(table_count) < int(expected["database"]["minimum_source_tables"]):
            errors.append(
                f"dbo source table count is {table_count}, expected at least "
                f"{expected['database']['minimum_source_tables']}"
            )
        if int(compatibility_level) != int(expected["database"]["compatibility_level"]):
            errors.append(
                f"compatibility_level is {compatibility_level}, expected "
                f"{expected['database']['compatibility_level']}"
            )

        sql_paths = [
            SQL / "part2_03_build_three_funnel_staging.sql",
            SQL / "31_build_membership_import_staging.sql",
            SQL / "54_build_services_import_staging.sql",
        ]
        required_tables = find_dbo_source_tables(sql_paths)
        missing = []
        for table in required_tables:
            exists = db.query_scalar(
                "SELECT CASE WHEN OBJECT_ID(%s, N'U') IS NULL THEN 0 ELSE 1 END",
                (f"dbo.{table}",),
            )
            if int(exists or 0) != 1:
                missing.append(table)
        if missing:
            errors.append(f"Missing required 1C source tables: {', '.join(missing)}")

        report = [
            "# Database preflight",
            "",
            f"- database: `{database_name}`",
            f"- state: `{state_desc}`",
            f"- compatibility level: `{compatibility_level}`",
            f"- dbo source tables: `{table_count}`",
            f"- required source tables checked: `{len(required_tables)}`",
            f"- missing required tables: `{len(missing)}`",
            "",
            "## SQL Server",
            "",
            "```text",
            str(sql_version),
            "```",
            "",
            "## Errors",
            "",
            *([f"- {error}" for error in errors] or ["- none"]),
            "",
        ]
        (self.reports_root / "database_preflight.md").write_text(
            "\n".join(report), encoding="utf-8"
        )
        if errors:
            raise RuntimeError("Database preflight failed: " + "; ".join(errors))

    def owner_sql(self, db: DatabaseClient) -> None:
        variables = {
            "database_name": sql_bracket_value(self.connection_settings.database),
            "cutoff_date": sql_string(str(self.run_config["cutoff_date"])),
            "cutoff_at": sql_string(str(self.run_config["cutoff_at"])),
            "backup_finish_at": sql_string(str(self.run_config["backup_finish_at"])),
            "output_run_label": sql_string(str(self.run_config["work_name"])),
        }
        db.execute_script(
            SQL / "part2_03_build_three_funnel_staging.sql",
            variables=variables,
            log_path=self.logs_root / "owner_sql.log",
        )
        self._check_owner_cutoff(db)

    def owner_export(self, db: DatabaseClient) -> None:
        log_path = self.logs_root / "owner_export.log"
        row_counts: dict[str, int] = {}
        with log_path.open("w", encoding="utf-8") as log:
            for table in STAGE_TABLES:
                output_path = self.raw_root / "staging" / f"{table}.csv"
                count = db.export_table_csv(
                    schema="fitbase_part2",
                    table=table,
                    order_by=ORDER_BY[table],
                    output_path=output_path,
                )
                row_counts[table] = count
                log.write(f"{table}\t{count}\t{output_path}\n")
                log.flush()
                self.log(f"owner_export: {table} rows={count}")
        self.status["row_counts"]["owner_stage"] = row_counts

    def reclassify(self) -> None:
        self.run_command(
            "reclassify",
            [
                sys.executable,
                SCRIPTS / "16_reclassify_part2_from_csv.py",
                "--cutoff-date",
                str(self.run_config["cutoff_date"]),
                "--cutoff-at",
                str(self.run_config["cutoff_at"]),
                "--source-stage-dir",
                self.raw_root / "staging",
                "--source-reports-dir",
                self.raw_root / "reports",
                "--output-stage-dir",
                self.owner_root / "staging",
                "--output-reports-dir",
                self.owner_root / "reports",
                "--decisions",
                CONFIG / "product_reclassification_decisions.csv",
            ],
        )

    def main_xlsx(self) -> None:
        for stale in self.owner_root.glob("*.xlsx"):
            stale.unlink()
        common = [
            "--cutoff-date",
            str(self.run_config["cutoff_date"]),
            "--date-stamp",
            self.date_stamp,
            "--stage-dir",
            self.owner_root / "staging",
            "--output-dir",
            self.owner_root,
            "--reports-dir",
            self.owner_root / "reports",
            "--main-template",
            TEMPLATES / "import_zayavki.xlsx",
            "--cards-template",
            TEMPLATES / "plastic_cards.xlsx",
            "--branches-config",
            CONFIG / "branches_by_club.yml",
            "--main-require-phone-for-new-applications",
            "--main-transfer-new-applications-to-memberships",
            "--cards-funnel-filter",
            "Действующие клиенты",
            "--dedupe-by-phone-keep-latest-subscription",
        ]
        self.run_command(
            "main_xlsx_build",
            [
                sys.executable,
                SCRIPTS / "17_build_part2_combined_xlsx.py",
                *common,
                "--csv-dir",
                self.owner_root / "csv",
                "--managers-config",
                CONFIG / "managers_by_club.yml",
                "--fitbase-label-mode",
                "customer_20260520_single_stage",
            ],
        )
        self.run_command(
            "main_xlsx_validate",
            [
                sys.executable,
                SCRIPTS / "18_validate_combined_single_stage_outputs.py",
                *common,
            ],
        )
        for stem in ["import_zayavki", "plastic_cards"]:
            source = (
                self.owner_root
                / f"fitbase_active_clients_{stem}_{self.date_stamp}__all_funnels.xlsx"
            )
            destination = (
                self.owner_root
                / f"fitbase_active_clients_{stem}_{self.date_stamp}_all_funnels.xlsx"
            )
            source.replace(destination)

    def membership_sql(self, db: DatabaseClient) -> None:
        db.execute_script(
            SQL / "31_build_membership_import_staging.sql",
            variables={
                "cutoff_at": sql_string(str(self.run_config["cutoff_at"]))
            },
            log_path=self.logs_root / "membership_sql.log",
        )
        self._check_fact_cutoff(
            db,
            table="membership_import_facts",
            check_name="membership_facts",
        )

    def membership_export(self, db: DatabaseClient) -> None:
        module = load_python_module(
            SCRIPTS / "19_build_membership_import_xlsx.py", "membership_builder_fields"
        )
        output_path = self.imports_root / "staging" / "membership_import_facts.tsv"
        count, columns = db.export_query_tsv(
            query_path=SQL / "export_membership_import_facts.sql",
            output_path=output_path,
            expected_columns=module.FACT_FIELDS,
        )
        self.status["row_counts"]["membership_facts"] = count
        (self.logs_root / "membership_export.log").write_text(
            f"rows={count}\ncolumns={len(columns)}\noutput={output_path}\n",
            encoding="utf-8",
        )
        self.log(f"membership_export: rows={count}")

    def membership_xlsx(self) -> None:
        common = [
            "--source-output-dir",
            self.owner_root,
            "--output-dir",
            self.imports_root,
            "--date-stamp",
            self.date_stamp,
        ]
        self.run_command(
            "membership_xlsx_build",
            [
                sys.executable,
                SCRIPTS / "19_build_membership_import_xlsx.py",
                *common,
                "--facts-tsv",
                self.imports_root / "staging" / "membership_import_facts.tsv",
                "--client-template",
                TEMPLATES / "membership_clients.xlsx",
                "--membership-template",
                TEMPLATES / "membership_templates.xlsx",
            ],
        )
        self.run_command(
            "membership_xlsx_validate",
            [
                sys.executable,
                SCRIPTS / "20_validate_membership_import_xlsx.py",
                *common,
            ],
        )

    def services_sql(self, db: DatabaseClient) -> None:
        db.execute_script(
            SQL / "54_build_services_import_staging.sql",
            variables={
                "cutoff_at": sql_string(str(self.run_config["cutoff_at"]))
            },
            log_path=self.logs_root / "services_sql.log",
        )
        self._check_fact_cutoff(
            db,
            table="services_import_facts",
            check_name="services_facts",
        )

    def services_export(self, db: DatabaseClient) -> None:
        module = load_python_module(
            SCRIPTS / "23_build_services_import_xlsx.py", "services_builder_fields"
        )
        output_path = self.imports_root / "staging" / "services_import_facts.tsv"
        count, columns = db.export_query_tsv(
            query_path=SQL / "export_services_import_facts.sql",
            output_path=output_path,
            expected_columns=module.FACT_FIELDS,
        )
        self.status["row_counts"]["services_facts"] = count
        (self.logs_root / "services_export.log").write_text(
            f"rows={count}\ncolumns={len(columns)}\noutput={output_path}\n",
            encoding="utf-8",
        )
        self.log(f"services_export: rows={count}")

    def services_xlsx(self) -> None:
        common = [
            "--source-output-dir",
            self.owner_root,
            "--output-dir",
            self.imports_root,
            "--date-stamp",
            self.date_stamp,
            "--services-list",
            TEMPLATES / "services_required.xlsx",
        ]
        self.run_command(
            "services_xlsx_build",
            [
                sys.executable,
                SCRIPTS / "23_build_services_import_xlsx.py",
                *common,
                "--client-template",
                TEMPLATES / "service_clients.xlsx",
                "--template-template",
                TEMPLATES / "service_templates.xlsx",
            ],
        )
        self.run_command(
            "services_xlsx_validate",
            [sys.executable, SCRIPTS / "24_validate_services_import_xlsx.py", *common],
        )

    def problem_xlsx(self) -> None:
        for stale in self.imports_root.glob(
            f"active_problem_*_cases_{self.date_stamp}.xlsx"
        ):
            stale.unlink()
        self.run_command(
            "problem_xlsx",
            [sys.executable, SCRIPTS / "36_build_active_problem_case_workbooks.py"],
            env={
                "ACTIVE_PROBLEM_OUTPUT_DIR": str(self.imports_root),
                "ACTIVE_PROBLEM_DATE_STAMP": self.date_stamp,
                "ACTIVE_PROBLEM_CUTOFF_DATE": str(self.run_config["cutoff_date"]),
            },
        )

    def delivery(self) -> None:
        self.run_command(
            "delivery",
            [
                sys.executable,
                SCRIPTS / "build_delivery.py",
                "--owner-dir",
                self.owner_root,
                "--imports-dir",
                self.imports_root,
                "--output-dir",
                self.delivery_root,
                "--date-stamp",
                self.date_stamp,
                "--report",
                self.reports_root / "delivery_build.md",
                "--membership-template",
                TEMPLATES / "membership_clients.xlsx",
            ],
        )

    def validate(self) -> None:
        command: list[str | Path] = [
            sys.executable,
            SCRIPTS / "validate_delivery.py",
            "--output-dir",
            self.delivery_root,
            "--expected",
            as_abs(self.validation_config["expected_manifest"]),
            "--report",
            self.reports_root / "validation_report.md",
            "--json-report",
            self.reports_root / "validation_report.json",
        ]
        enforce = (
            bool(self.validation_config.get("enforce_reference_counts", True))
            and not self.args.skip_reference_counts
        )
        if enforce:
            command.append("--enforce-reference-counts")
        self.run_command("delivery_validate", command)

    def run(self) -> None:
        self.prepare_directories()
        start_index = STEPS.index(self.args.start_at)
        stop_index = STEPS.index(self.args.stop_after)
        if stop_index < start_index:
            raise ValueError("--stop-after must not precede --start-at")

        db_steps = {
            "preflight",
            "owner_sql",
            "owner_export",
            "membership_sql",
            "membership_export",
            "services_sql",
            "services_export",
        }
        db: DatabaseClient | None = None
        try:
            for index, step in enumerate(STEPS):
                if index < start_index or index > stop_index:
                    continue
                self.log(f"START step={step}")
                if step in db_steps and db is None:
                    db = DatabaseClient(self.connection_settings)
                if step == "preflight":
                    self.preflight(db)
                elif step == "owner_sql":
                    self.owner_sql(db)
                elif step == "owner_export":
                    self.owner_export(db)
                elif step == "reclassify":
                    self.reclassify()
                elif step == "main_xlsx":
                    self.main_xlsx()
                elif step == "membership_sql":
                    self.membership_sql(db)
                elif step == "membership_export":
                    self.membership_export(db)
                elif step == "membership_xlsx":
                    self.membership_xlsx()
                elif step == "services_sql":
                    self.services_sql(db)
                elif step == "services_export":
                    self.services_export(db)
                elif step == "services_xlsx":
                    self.services_xlsx()
                elif step == "problem_xlsx":
                    self.problem_xlsx()
                elif step == "delivery":
                    self.delivery()
                elif step == "validate":
                    self.validate()
                self.mark_complete(step)
                self.log(f"DONE step={step}")
        except Exception:
            self.status["failed_at"] = datetime.now().isoformat(timespec="seconds")
            self.status["traceback"] = traceback.format_exc()
            self._write_status()
            self.log(f"FAILED\n{self.status['traceback']}")
            raise
        finally:
            if db is not None:
                db.connection.close()

        self.status["finished_at"] = datetime.now().isoformat(timespec="seconds")
        self.status["delivery"] = str(self.delivery_root)
        self.status["versions"] = {
            "python": sys.version.split()[0],
            "openpyxl": openpyxl.__version__,
            "python_tds": installed_version("python-tds"),
            "pyyaml": yaml.__version__,
        }
        self._write_status()
        if stop_index == len(STEPS) - 1:
            self.log(f"PIPELINE PASS delivery={self.delivery_root}")
        else:
            self.log(f"PIPELINE STOPPED stop_after={self.args.stop_after}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", default="config/pipeline.yml")
    parser.add_argument("--server")
    parser.add_argument("--port", type=int)
    parser.add_argument("--database")
    parser.add_argument("--user")
    parser.add_argument("--password-env")
    parser.add_argument(
        "--password-file", help="Read the SQL password from this local file"
    )
    parser.add_argument("--start-at", choices=STEPS, default=STEPS[0])
    parser.add_argument("--stop-after", choices=STEPS, default=STEPS[-1])
    parser.add_argument(
        "--resume",
        action="store_true",
        help="Keep existing work/log files when starting at a later step",
    )
    parser.add_argument(
        "--skip-reference-counts",
        action="store_true",
        help="Validate structure and invariants but do not require exact 20260630 row counts",
    )
    return parser.parse_args()


if __name__ == "__main__":
    Pipeline(parse_args()).run()
