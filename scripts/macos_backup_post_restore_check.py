#!/usr/bin/env python3
from pathlib import Path
import pymssql


ROOT = Path(__file__).resolve().parents[1]
ENV_FILE = ROOT / "tmp" / "macos-backup" / "mssql-fitness-macos.env"
DB_NAME = "FitnessRestored_20260523_macos"


def read_password() -> str:
    for line in ENV_FILE.read_text().splitlines():
        if line.startswith("MSSQL_SA_PASSWORD="):
            return line.split("=", 1)[1]
    raise RuntimeError(f"MSSQL_SA_PASSWORD not found in {ENV_FILE}")


def scalar(cursor, sql: str):
    cursor.execute(sql)
    row = cursor.fetchone()
    return row[0] if row else None


def main() -> None:
    password = read_password()
    with pymssql.connect(
        server="127.0.0.1",
        port=11433,
        user="sa",
        password=password,
        database="master",
        login_timeout=30,
        timeout=120,
        tds_version="7.4",
    ) as conn:
        cursor = conn.cursor()
        cursor.execute(
            """
SELECT name, state_desc, recovery_model_desc, compatibility_level
FROM sys.databases
WHERE name = %s
""",
            (DB_NAME,),
        )
        db_row = cursor.fetchone()
        print("database\tstate_desc\trecovery_model_desc\tcompatibility_level")
        print("\t".join(str(value) for value in db_row))

        user_tables = scalar(
            cursor,
            f"""
SELECT COUNT(*)
FROM [{DB_NAME}].sys.tables
WHERE is_ms_shipped = 0
""",
        )
        user_columns = scalar(
            cursor,
            f"""
SELECT COUNT(*)
FROM [{DB_NAME}].sys.columns AS c
JOIN [{DB_NAME}].sys.tables AS t
    ON t.object_id = c.object_id
WHERE t.is_ms_shipped = 0
""",
        )
        print("metric\tvalue")
        print(f"user_tables\t{user_tables}")
        print(f"user_columns\t{user_columns}")


if __name__ == "__main__":
    main()
