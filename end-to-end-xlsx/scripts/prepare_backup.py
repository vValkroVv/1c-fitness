#!/usr/bin/env python3
"""Inspect a real SQL backup and prepare a dated Fitbase pipeline configuration.

The source backup timestamp remains provenance. The requested effective time
controls the export snapshot. Replacing a local restore requires an explicit flag.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
from datetime import datetime, timedelta
from pathlib import Path, PurePosixPath
from typing import Any, Sequence

import yaml

from database import ConnectionSettings, DatabaseClient, quote_identifier
from cutoff_contract import parse_timestamp


ROOT = Path(__file__).resolve().parents[1]
ACCEPTED_MANIFEST = ROOT / "reference/expected_20260630_register_debts.yml"
TIME_FORMAT = "%Y-%m-%d %H:%M:%S"
RESTORE_MARGIN_BYTES = 2 * 1024**3


def safe_component(value: str, label: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", value) or value in {".", ".."}:
        raise ValueError(f"{label} must be a single safe path component")
    return value


def timestamp(value: Any) -> datetime:
    if isinstance(value, datetime):
        result = value
    else:
        result = parse_timestamp(value, "timestamp")
    if result.tzinfo is not None or result.microsecond:
        raise ValueError("Use the backup's local SQL time with second precision and no timezone")
    return result


def effective_timestamp(
    backup_finish: datetime,
    effective_at: str | None,
    effective_offset_days: int | None,
) -> datetime:
    if effective_at is not None and effective_offset_days is not None:
        raise ValueError("effective_at and effective_offset_days are mutually exclusive")
    if effective_at is not None:
        return timestamp(effective_at)
    return backup_finish + timedelta(days=effective_offset_days or 0)


def select_backup_header(headers: list[dict[str, Any]], position: int) -> dict[str, Any]:
    if position < 1:
        raise ValueError("backup position must be positive")
    matches = [row for row in headers if int(row.get("Position", 0)) == position]
    if len(matches) != 1:
        raise ValueError(f"Expected one backup set at position {position}, found {len(matches)}")
    header = matches[0]
    if int(header.get("BackupType", 0)) != 1:
        raise ValueError("Only a full database backup is supported")
    if any(bool(header.get(key)) for key in ("IsDamaged", "IsSnapshot", "HasIncompleteMetaData")):
        raise ValueError("Damaged, snapshot, or incomplete-metadata backups are unsupported")
    if not header.get("DatabaseName") or not header.get("BackupSetGUID"):
        raise ValueError("Backup header lacks DatabaseName or BackupSetGUID")
    timestamp(header["BackupFinishDate"])
    return header


def query_dicts(
    db: DatabaseClient, sql: str, parameters: Sequence[Any] = ()
) -> list[dict[str, Any]]:
    """Drain all result sets, so late VERIFY/RESTORE errors cannot be missed."""
    rows: list[dict[str, Any]] = []
    with db.connection.cursor() as cursor:
        cursor.execute(sql, tuple(parameters))
        while True:
            if cursor.description:
                columns = [column[0] for column in cursor.description]
                rows.extend(dict(zip(columns, row, strict=True)) for row in cursor.fetchall())
            if not cursor.nextset():
                break
    return rows


def verify_restored_backup(
    db: DatabaseClient, database: str, backup: dict[str, Any]
) -> dict[str, Any]:
    """Verify the latest restore, not an older matching restore in msdb history."""
    rows = query_dicts(
        db,
        """
        SELECT TOP (1)
            d.name AS restored_database, d.state_desc, d.compatibility_level,
            history.restore_history_id, history.restore_date, history.restore_type,
            history.recovery, source.database_name AS database_name_in_backup,
            source.backup_finish_date AS backup_finish_at,
            CONVERT(varchar(36), source.backup_set_uuid) AS backup_set_uuid,
            source.position AS backup_position
        FROM sys.databases AS d
        LEFT JOIN msdb.dbo.restorehistory AS history
          ON history.destination_database_name = d.name
        LEFT JOIN msdb.dbo.backupset AS source
          ON source.backup_set_id = history.backup_set_id
        WHERE d.name = %s
        ORDER BY history.restore_history_id DESC
        """,
        (database,),
    )
    if not rows or not rows[0].get("restore_history_id"):
        raise RuntimeError(f"Cannot verify latest restore provenance in msdb for {database}")
    observed = rows[0]
    if observed["state_desc"] != "ONLINE" or observed["restore_type"] != "D":
        raise RuntimeError("Expected an ONLINE database whose latest restore is the full database backup")
    comparisons = {
        "database_name_in_backup": str(backup["database_name_in_backup"]),
        "backup_finish_at": timestamp(backup["backup_finish_at"]).strftime(TIME_FORMAT),
        "backup_set_uuid": str(backup["backup_set_uuid"]).lower(),
        "backup_position": str(backup.get("position", 1)),
    }
    for key, expected in comparisons.items():
        value = observed.get(key)
        actual = timestamp(value).strftime(TIME_FORMAT) if key == "backup_finish_at" else str(value)
        if key == "backup_set_uuid":
            actual = actual.lower()
        if actual != expected:
            raise RuntimeError(f"Restored backup {key} differs: observed={actual!r}, expected={expected!r}")
    return observed


def restore_moves(
    filelist: list[dict[str, Any]], database: str, restore_sql_dir: str
) -> list[dict[str, Any]]:
    safe_component(database, "database")
    directory = PurePosixPath(restore_sql_dir)
    if not directory.is_absolute() or ".." in directory.parts:
        raise ValueError("restore-sql-dir must be an absolute server path without '..'")
    moves: list[dict[str, Any]] = []
    seen_ids: set[int] = set()
    for row in filelist:
        if row.get("IsPresent") in (False, 0):
            continue
        kind = str(row["Type"])
        if kind not in {"D", "L"}:
            raise ValueError(f"Unsupported restore file type {kind!r}; inspect FILELISTONLY")
        file_id = int(row["FileId"])
        if file_id <= 0 or file_id in seen_ids:
            raise ValueError("FILELISTONLY has invalid or duplicate FileId")
        seen_ids.add(file_id)
        suffix = ".ldf" if kind == "L" else (".mdf" if not any(m["type"] == "D" for m in moves) else ".ndf")
        size = int(row["Size"])
        if size <= 0 or not row.get("LogicalName"):
            raise ValueError("FILELISTONLY has an empty logical name or non-positive size")
        moves.append({
            "logical_name": str(row["LogicalName"]),
            "server_path": str(directory / f"{database}_{file_id}{suffix}"),
            "size_bytes": size,
            "type": kind,
        })
    if {move["type"] for move in moves} != {"D", "L"}:
        raise ValueError("A complete D/L file list is required")
    return moves


def restore_sql(database: str, sql_path: str, position: int, moves: list[dict[str, Any]], *, replace_existing: bool = False) -> tuple[str, list[Any]]:
    if position < 1 or not moves:
        raise ValueError("Restore requires a positive backup position and file moves")
    options = ["FILE = %s", *("MOVE %s TO %s" for _ in moves), "RECOVERY", "STATS = 5"]
    if replace_existing:
        options.append("REPLACE")
    parameters: list[Any] = [sql_path, position]
    for move in moves:
        parameters.extend([move["logical_name"], move["server_path"]])
    statement = f"RESTORE DATABASE {quote_identifier(database)} FROM DISK = %s WITH " + ", ".join(options)
    return statement, parameters


def replacement_moves(
    requested: list[dict[str, Any]], existing_files: list[dict[str, Any]], restore_sql_dir: str
) -> tuple[list[dict[str, Any]], int]:
    """Reuse allocated files only when all logical names and types still agree."""
    by_name = {str(row["logical_name"]): row for row in existing_files}
    if len(by_name) != len(existing_files) or set(by_name) != {move["logical_name"] for move in requested}:
        raise ValueError("Replacement requires exactly the same logical files as the existing database")
    moves = []
    growth = 0
    for requested_move in requested:
        current = by_name[requested_move["logical_name"]]
        path = PurePosixPath(str(current["server_path"]))
        if path.parent != PurePosixPath(restore_sql_dir) or ".." in path.parts:
            raise ValueError("Existing database files must all be directly inside restore-sql-dir")
        if current["type"] != requested_move["type"]:
            raise ValueError("Existing and new backup logical-file types differ")
        growth += max(0, int(requested_move["size_bytes"]) - int(current["size_bytes"]))
        moves.append(dict(requested_move, server_path=str(path)))
    return moves, growth


def inspect_replacement(
    db: DatabaseClient, database: str, server: str,
    moves: list[dict[str, Any]], restore_sql_dir: str,
) -> tuple[list[dict[str, Any]], int, dict[str, Any]]:
    if server.lower() not in {"127.0.0.1", "localhost", "::1"}:
        raise ValueError("--replace-existing is restricted to a local SQL runtime")
    if not database.startswith(("FitnessRestored_", "FitbasePrepareSmoke_")):
        raise ValueError("--replace-existing accepts only FitnessRestored_* or FitbasePrepareSmoke_* databases")
    history = query_dicts(db, """
        SELECT TOP (1) d.name AS restored_database, d.state_desc,
            h.restore_history_id, h.restore_date, h.restore_type, h.recovery,
            b.database_name AS database_name_in_backup,
            b.backup_finish_date AS backup_finish_at,
            CONVERT(varchar(36), b.backup_set_uuid) AS backup_set_uuid
        FROM sys.databases AS d
        LEFT JOIN msdb.dbo.restorehistory AS h ON h.destination_database_name=d.name
        LEFT JOIN msdb.dbo.backupset AS b ON b.backup_set_id=h.backup_set_id
        WHERE d.name=%s ORDER BY h.restore_history_id DESC
        """, (database,))
    if not history or history[0].get("state_desc") != "ONLINE" or history[0].get("restore_type") != "D" or not history[0].get("recovery") or not history[0].get("backup_set_uuid"):
        raise RuntimeError("Replacement target must be ONLINE and have verifiable completed full-restore history")
    sessions = int(db.query_scalar("SELECT COUNT(*) FROM sys.dm_exec_sessions WHERE is_user_process=1 AND database_id=DB_ID(%s) AND session_id<>@@SPID", (database,)) or 0)
    if sessions:
        raise RuntimeError(f"Replacement target has {sessions} active user sessions; close them before retrying")
    existing_files = query_dicts(db, """
        SELECT name AS logical_name, physical_name AS server_path,
            CONVERT(bigint,size)*8192 AS size_bytes,
            CASE type WHEN 0 THEN 'D' WHEN 1 THEN 'L' ELSE '?' END AS type
        FROM sys.master_files WHERE database_id=DB_ID(%s) ORDER BY file_id
        """, (database,))
    reused_moves, growth = replacement_moves(moves, existing_files, restore_sql_dir)
    return reused_moves, growth, {"previous_restore": history[0], "previous_files": existing_files, "required_growth_bytes": growth}


def new_expected_manifest(
    backup: dict[str, Any], effective: datetime, run_name: str, problem4_contract_id: str
) -> dict[str, Any]:
    """Keep accepted shape/rules while removing historical row-count assertions."""
    accepted = yaml.safe_load(ACCEPTED_MANIFEST.read_text(encoding="utf-8"))
    date_stamp = effective.strftime("%Y%m%d")
    files = {}
    for old_name, old_spec in accepted["files"].items():
        if old_name.startswith("problem_"):
            continue
        spec = {key: value for key, value in old_spec.items() if key not in {"data_rows", "contract_ids"}}
        files[old_name.replace("20260630", date_stamp)] = spec
    contracts: list[str] = []
    if problem4_contract_id:
        if not problem4_contract_id.isdigit():
            raise ValueError("problem4-contract-id must contain digits only")
        contract = problem4_contract_id.zfill(11)
        short = contract.lstrip("0") or "0"
        contracts = [contract]
        files[f"problem_4_subrent_visits_left_contract_{short}_1_case_{date_stamp}.xlsx"] = {
            "columns": 22, "header_rows": 1, "contract_ids": contracts,
        }
    return {
        "backup": {key: backup[key] for key in ("file_name", "size_bytes", "sha256", "database_name_in_backup", "backup_finish_at", "backup_set_uuid", "position")},
        "database": accepted["database"],
        "delivery": {"run_id": f"{run_name}_delivery", "effective_at": effective.strftime(TIME_FORMAT)},
        "files": files,
        "problem_contracts": {"unique_total": len(contracts), "removed_from_clean_membership": len(contracts)},
        "allowed_branches": accepted["allowed_branches"],
    }


def relative_to_package(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def file_identity(path: Path) -> tuple[int, str]:
    before = path.stat()
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            digest.update(chunk)
    after = path.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise RuntimeError("Backup changed while hashing; wait for the download to complete")
    if after.st_size == 0:
        raise ValueError("Backup file is empty")
    return after.st_size, digest.hexdigest()


def write_json(path: Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")


def prepare(args: argparse.Namespace) -> Path:
    run_name = safe_component(args.run_name, "run-name")
    if run_name == "prepared":
        raise ValueError("run-name 'prepared' is reserved for preparation metadata")
    safe_component(args.database, "database")
    if args.replace_existing and not args.restore:
        raise ValueError("--replace-existing requires --restore")
    backup_file = Path(args.backup_file).expanduser().resolve(strict=True)
    sql_path = PurePosixPath(args.backup_sql_path)
    if not sql_path.is_absolute() or ".." in sql_path.parts or sql_path.name != backup_file.name:
        raise ValueError("backup-sql-path must be absolute and identify the same filename as backup-file")
    output_dir = ROOT / "work" / "prepared" / run_name
    output_dir.mkdir(parents=True, exist_ok=False)
    audit_path = output_dir / "backup_metadata.json"
    audit: dict[str, Any] = {"started_at": datetime.now().isoformat(timespec="seconds"), "status": "STARTED"}
    write_json(audit_path, audit)
    try:
        password = os.environ.get(args.password_env, "")
        if not password:
            raise ValueError(f"SQL password environment variable is empty: {args.password_env}")
        print(f"Hashing {backup_file.name}", flush=True)
        size, digest = file_identity(backup_file)
        initial_stat = backup_file.stat()
        settings = ConnectionSettings(
            server=args.server, port=args.port, database="master", user=args.user,
            password=password, encrypt_login=not args.disable_login_encryption,
        )
        with DatabaseClient(settings) as db:
            print("Reading RESTORE HEADERONLY and FILELISTONLY", flush=True)
            headers = query_dicts(db, "RESTORE HEADERONLY FROM DISK = %s", (str(sql_path),))
            header = select_backup_header(headers, args.backup_position)
            filelist = query_dicts(db, "RESTORE FILELISTONLY FROM DISK = %s WITH FILE = %s", (str(sql_path), args.backup_position))
            moves = restore_moves(filelist, args.database, args.restore_sql_dir)
            finish = timestamp(header["BackupFinishDate"])
            effective = effective_timestamp(finish, args.effective_at, args.effective_offset_days)
            backup = {
                "file_name": backup_file.name, "source_path": str(backup_file),
                "sql_path": str(sql_path), "size_bytes": size, "sha256": digest,
                "database_name_in_backup": str(header["DatabaseName"]),
                "backup_finish_at": finish.strftime(TIME_FORMAT),
                "backup_set_uuid": str(header["BackupSetGUID"]),
                "position": args.backup_position,
                "header_metadata_path": relative_to_package(audit_path),
            }
            audit.update({"backup": backup, "headers": headers, "selected_header": header, "filelist": filelist, "restore_moves": moves, "effective_at": effective.strftime(TIME_FORMAT)})
            required_bytes = sum(move["size_bytes"] for move in moves) + RESTORE_MARGIN_BYTES
            audit["restore_required_bytes_including_margin"] = required_bytes
            if args.restore_host_dir:
                restore_host_dir = Path(args.restore_host_dir).expanduser().resolve(strict=True)
                audit["restore_host_dir"] = str(restore_host_dir)
                audit["restore_available_bytes"] = shutil.disk_usage(restore_host_dir).free
            elif args.restore:
                raise ValueError("--restore requires --restore-host-dir for a checked local mount corresponding to --restore-sql-dir")
            write_json(audit_path, audit)
            print("Running RESTORE VERIFYONLY", flush=True)
            checksum_option = ", CHECKSUM" if bool(header.get("HasBackupChecksums")) else ""
            query_dicts(db, "RESTORE VERIFYONLY FROM DISK = %s WITH FILE = %s" + checksum_option, (str(sql_path), args.backup_position))
            audit["verifyonly"] = "PASS"
            write_json(audit_path, audit)
            exists = bool(db.query_scalar("SELECT CASE WHEN DB_ID(%s) IS NULL THEN 0 ELSE 1 END", (args.database,)))
            if args.restore:
                if exists and not args.replace_existing:
                    raise RuntimeError(f"Refusing to replace existing database {args.database}; use a new name or --use-existing for this same backup")
                if args.replace_existing:
                    if not exists:
                        raise RuntimeError("--replace-existing requires an existing restored database")
                    moves, growth, replacement = inspect_replacement(db, args.database, args.server, moves, args.restore_sql_dir)
                    required_bytes = growth + RESTORE_MARGIN_BYTES
                    audit["replacement"] = replacement
                    audit["restore_moves"] = moves
                    audit["restore_required_bytes_including_margin"] = required_bytes
                else:
                    for move in moves:
                        if db.query_scalar("SELECT COUNT(*) FROM sys.master_files WHERE physical_name = %s", (move["server_path"],)):
                            raise RuntimeError(f"Restore target is already registered to a database: {move['server_path']}")
                        presence = query_dicts(db, "SELECT file_exists, file_is_a_directory, parent_directory_exists FROM sys.dm_os_file_exists(%s)", (move["server_path"],))
                        if not presence or not presence[0]["parent_directory_exists"]:
                            raise RuntimeError(f"Restore target parent directory is unavailable: {move['server_path']}")
                        if presence[0]["file_exists"] or presence[0]["file_is_a_directory"]:
                            raise RuntimeError(f"Restore target already exists: {move['server_path']}")
                audit["restore_available_bytes"] = shutil.disk_usage(restore_host_dir).free
                if audit["restore_available_bytes"] < required_bytes:
                    raise RuntimeError(f"Insufficient restore disk space: need {required_bytes} bytes including margin, available {audit['restore_available_bytes']}")
                observed_stat = backup_file.stat()
                if (initial_stat.st_size, initial_stat.st_mtime_ns) != (observed_stat.st_size, observed_stat.st_mtime_ns):
                    raise RuntimeError("Backup changed before restore")
                write_json(audit_path, audit)
                statement, parameters = restore_sql(args.database, str(sql_path), args.backup_position, moves, replace_existing=args.replace_existing)
                print(f"Restoring {'replacement of local' if args.replace_existing else 'new'} database {args.database}", flush=True)
                if args.replace_existing:
                    query_dicts(db, f"ALTER DATABASE {quote_identifier(args.database)} SET SINGLE_USER WITH ROLLBACK IMMEDIATE")
                try:
                    query_dicts(db, statement, parameters)
                finally:
                    if args.replace_existing:
                        # Preserve the restore exception if SQL cannot yet bring a
                        # failed restore back online; the audit retains that state.
                        try:
                            query_dicts(db, f"ALTER DATABASE {quote_identifier(args.database)} SET MULTI_USER")
                        except Exception as recovery_error:
                            audit["multi_user_restore_error"] = str(recovery_error)
                if "multi_user_restore_error" in audit:
                    raise RuntimeError("Restore did not return the database to MULTI_USER; inspect backup_metadata.json")
                query_dicts(db, f"ALTER DATABASE {quote_identifier(args.database)} SET RECOVERY SIMPLE")
                audit["restored_database"] = verify_restored_backup(db, args.database, backup)
            elif args.use_existing:
                audit["restored_database"] = verify_restored_backup(db, args.database, backup)
            else:
                audit["database_ready"] = False
            if args.restore or args.use_existing:
                audit["database_ready"] = True

        final_stat = backup_file.stat()
        if (initial_stat.st_size, initial_stat.st_mtime_ns) != (final_stat.st_size, final_stat.st_mtime_ns):
            raise RuntimeError("Backup changed during SQL checks")
        expected_path = output_dir / "expected.yml"
        expected = new_expected_manifest(backup, effective, run_name, args.problem4_contract_id)
        expected["database"]["compatibility_level"] = int(header["CompatibilityLevel"])
        expected_path.write_text(yaml.safe_dump(expected, allow_unicode=True, sort_keys=False), encoding="utf-8")
        config = {
            "run": {
                "effective_at": effective.strftime(TIME_FORMAT),
                "cutoff_at": effective.strftime(TIME_FORMAT),
                "cutoff_date": effective.strftime("%Y-%m-%d"),
                "date_stamp": effective.strftime("%Y%m%d"),
                "backup_finish_at": finish.strftime(TIME_FORMAT),
                "work_name": run_name, "delivery_name": f"{run_name}_delivery",
            },
            "sql": {
                "server": args.server, "port": args.port, "database": args.database,
                "user": args.user, "password_env": args.password_env,
                "login_timeout_seconds": 30, "query_timeout_seconds": 0,
                "encrypt_login": not args.disable_login_encryption,
                "tls_ca_file": "", "tls_validate_host": True,
            },
            "validation": {"expected_manifest": relative_to_package(expected_path), "enforce_reference_counts": False},
            "delivery": {"output_base": "../output", "financial_problem_groups_resolved": True, "problem4_contract_id": args.problem4_contract_id},
            "photos": {"enabled": True, "container": args.photos_container},
            "backup": backup,
        }
        config_path = output_dir / "pipeline.yml"
        config_path.write_text(yaml.safe_dump(config, allow_unicode=True, sort_keys=False), encoding="utf-8")
        audit.update({"status": "PASS", "finished_at": datetime.now().isoformat(timespec="seconds"), "config_path": relative_to_package(config_path)})
        write_json(audit_path, audit)
        print(f"Prepared config: {config_path}\nBackup finished: {finish.strftime(TIME_FORMAT)}\nEffective snapshot: {effective.strftime(TIME_FORMAT)}", flush=True)
        return config_path
    except Exception as exc:
        audit.update({"status": "FAILED", "error": str(exc), "failed_at": datetime.now().isoformat(timespec="seconds")})
        write_json(audit_path, audit)
        raise


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backup-file", required=True, help="Fully downloaded host .bak path")
    parser.add_argument("--backup-sql-path", required=True, help="Same file mounted inside SQL Server, for example /backup/Fitnes.bak")
    parser.add_argument("--backup-position", type=int, default=1)
    parser.add_argument("--database", required=True)
    parser.add_argument("--server", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=11434)
    parser.add_argument("--user", default="sa")
    parser.add_argument("--password-env", default="FITNESS_SQL_PASSWORD")
    parser.add_argument("--disable-login-encryption", action="store_true")
    parser.add_argument("--run-name", required=True, help="Unique new run name; preparation output is immutable")
    effective = parser.add_mutually_exclusive_group()
    effective.add_argument("--effective-at", help="SQL local timestamp, YYYY-MM-DD HH:MM:SS")
    effective.add_argument("--effective-offset-days", type=int, help="Calendar day offset from true BackupFinishDate; default 0")
    restore = parser.add_mutually_exclusive_group()
    restore.add_argument("--restore", action="store_true", help="Restore a new database, or explicitly replace a guarded local restore with --replace-existing")
    restore.add_argument("--use-existing", action="store_true", help="Verify latest msdb restore identity for the existing database")
    parser.add_argument("--restore-sql-dir", default="/restoredata")
    parser.add_argument("--replace-existing", action="store_true", help="Explicitly replace a local FitnessRestored_* database after provenance/session/file checks; requires --restore")
    parser.add_argument("--restore-host-dir", help="Existing local host directory mounted as restore-sql-dir; required for --restore")
    parser.add_argument("--photos-container", default="mssql-fitness-2022", help="Existing SQL container used to stream client photos")
    parser.add_argument("--problem4-contract-id", default="151350", help="Carry the accepted isolated visits-left case; empty string means no isolation")
    return parser.parse_args()


if __name__ == "__main__":
    prepare(parse_args())
