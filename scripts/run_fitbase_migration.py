#!/usr/bin/env python3
"""Prepare the actual backup and run the complete verified XLSX + photo delivery.

All unconsumed arguments are passed to prepare_backup.py; use --help for its
options. The local SQL password is loaded without printing or shell evaluation.
"""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "end-to-end-xlsx"


def read_sql_password(path: Path) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if separator and key.strip() == "MSSQL_SA_PASSWORD":
            value = value.strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            if value:
                return value
    raise ValueError(f"No MSSQL_SA_PASSWORD in local environment file: {path}")


def main() -> int:
    python = PACKAGE / ".venv" / "bin" / "python"
    # Use the same pinned environment for backup preparation and the pipeline.
    if Path(sys.prefix).resolve() != (PACKAGE / ".venv").resolve():
        if not python.is_file():
            raise RuntimeError("Create end-to-end-xlsx/.venv and install end-to-end-xlsx/requirements.txt first")
        os.execv(str(python), [str(python), str(Path(__file__).resolve()), *sys.argv[1:]])
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--env-file", type=Path, default=ROOT / "tmp/macos-backup/mssql-fitness-macos.env")
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--resume-config", type=Path)
    parser.add_argument("--start-at", default=None)
    options, remaining = parser.parse_known_args()
    sys.path.insert(0, str(PACKAGE / "scripts"))
    if options.resume_config:
        if remaining or options.prepare_only or not options.start_at:
            raise ValueError("Resume requires --resume-config and --start-at, without backup preparation options")
        import yaml
        config_path = options.resume_config.expanduser().resolve(strict=True)
        config = yaml.safe_load(config_path.read_text(encoding="utf-8"))
        env_name = config["sql"]["password_env"]
        if not os.environ.get(env_name):
            os.environ[env_name] = read_sql_password(options.env_file)
        return subprocess.call([
            sys.executable, str(PACKAGE / "scripts/run_pipeline.py"), "--config", str(config_path),
            "--resume", "--start-at", options.start_at,
        ], cwd=ROOT)
    if options.start_at:
        raise ValueError("--start-at requires --resume-config")
    if "--help" in remaining or "-h" in remaining:
        print("Wrapper options: --env-file PATH, --prepare-only, or --resume-config PATH --start-at STEP\n", flush=True)
    import prepare_backup
    sys.argv = [str(PACKAGE / "scripts" / "prepare_backup.py"), *remaining]
    args = prepare_backup.parse_args()
    if not os.environ.get(args.password_env):
        os.environ[args.password_env] = read_sql_password(options.env_file)
    if not options.prepare_only and not (args.restore or args.use_existing):
        raise ValueError("Choose --restore or --use-existing for a full run, or --prepare-only for inspection")
    config_path = prepare_backup.prepare(args)
    if options.prepare_only:
        return 0
    return subprocess.call([
        sys.executable, str(PACKAGE / "scripts/run_pipeline.py"), "--config", str(config_path)
    ], cwd=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
