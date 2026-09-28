#!/usr/bin/env python3
"""Export additional, explicitly classified service sale lines for the delta."""

from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "end-to-end-xlsx"
REPORTS = ROOT / "output/20260923_delta_from_20260920/reports/imports"
NEW = PACKAGE / "work/20260923_restore_verified"
TABLE = "fitbase_part2.services_import_facts_delta_extended"
OLD_CUTOFF = "2026-09-20 20:12:12"
NEW_CUTOFF = "2026-09-23 23:36:39"
EXTRA_NAMES = [
    "Биоимпедансометрия (анализ состава тела)",
    "Гостевой визит",
    "Аренда шкафа 1 месяц",
    "Аренда шкафа 6 месяцев",
    "Аренда шкафа 12 месяцев",
    "Аренда рекламного места сроком на 2 месяца",
    "Заморозка абонемента 3 месяца",
    "Переоформление платное",
    "График посещений",
]


def database_module():
    spec = importlib.util.spec_from_file_location("delta_service_database", PACKAGE / "scripts/database.py")
    obj = importlib.util.module_from_spec(spec)
    import sys
    sys.modules[spec.name] = obj
    spec.loader.exec_module(obj)
    return obj


def password():
    if os.getenv("FITNESS_SQL_PASSWORD"):
        return os.environ["FITNESS_SQL_PASSWORD"]
    env = ROOT / "tmp/macos-backup/mssql-fitness-macos.env"
    for line in env.read_text().splitlines():
        key, _, value = line.partition("=")
        if key.strip() == "MSSQL_SA_PASSWORD":
            return value.strip().strip('"').strip("'")
    raise RuntimeError("SQL password not available")


def main():
    REPORTS.mkdir(parents=True, exist_ok=True)
    sql = (PACKAGE / "sql/54_build_services_import_staging.sql").read_text()
    begin = sql.index("INSERT INTO #service_list (service_order, service_name)")
    end = sql.index("\n\nSELECT", begin)
    values = ",\n".join(f"({i}, N'{name.replace(chr(39), chr(39) * 2)}')" for i, name in enumerate(EXTRA_NAMES, 52))
    sql = sql[:begin] + "INSERT INTO #service_list (service_order, service_name)\nVALUES\n" + values + ";" + sql[end:]
    sql = sql.replace("fitbase_part2.services_import_facts", TABLE)
    needle = "      END <= @cutoff_at;"
    replacement = "      END <= @cutoff_at\n  AND CASE WHEN d._Date_Time > '3000-01-01' THEN DATEADD(year, -2000, d._Date_Time) ELSE d._Date_Time END > '" + OLD_CUTOFF + "';"
    if sql.count(needle) != 1:
        raise RuntimeError("Source SQL date predicate changed")
    sql = sql.replace(needle, replacement)
    stage_sql = REPORTS / "extra_services_staging.sql"
    stage_sql.write_text(sql)
    export = (PACKAGE / "sql/export_services_import_facts.sql").read_text().replace("fitbase_part2.services_import_facts", TABLE)
    export_sql = REPORTS / "extra_services_export.sql"
    export_sql.write_text(export)
    status = json.loads((NEW / "status.json").read_text())
    if status["cutoff_contract"]["cutoff_at"] != NEW_CUTOFF:
        raise RuntimeError("New cutoff mismatch")
    db = database_module()
    cfg = status["database"]
    settings = db.ConnectionSettings(server=cfg["server"], port=int(cfg["port"]), database=cfg["database"], user=cfg["user"], password=password(), encrypt_login=False)
    with db.DatabaseClient(settings) as conn:
        conn.execute_script(stage_sql, variables={"cutoff_at": NEW_CUTOFF}, log_path=REPORTS / "extra_services_staging.log")
        count, columns = conn.export_query_tsv(query_path=export_sql, output_path=REPORTS / "extra_services_import_facts.tsv")
    (REPORTS / "extra_services_export_result.json").write_text(json.dumps({"rows": count, "columns": len(columns), "extra_names": EXTRA_NAMES}, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"rows": count, "columns": len(columns)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
