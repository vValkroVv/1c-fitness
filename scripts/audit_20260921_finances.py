#!/usr/bin/env python3
"""Reconcile every membership fact to an independent raw-register aggregation.

Read-only: reconstruct sale links from source documents, aggregate the whole
accounting register by sale first, then compare with the exported staging.
No production financial transformation is called.
"""

import argparse
from datetime import datetime
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "end-to-end-xlsx/scripts"), str(ROOT / "scripts")]
from database import ConnectionSettings, DatabaseClient
from prepare_backup import query_dicts
from run_fitbase_migration import read_sql_password

QUERY = """
WITH links AS (
 SELECT DISTINCT m.subscription_ref, sale._IDRRef AS sale_ref
 FROM fitbase_part2.membership_import_facts m
 JOIN dbo._Document154_VT1137 line
  ON line._Fld1148_RTRef=0x000000A3
  AND line._Fld1148_RRRef=CONVERT(binary(16),m.subscription_ref,2)
 JOIN dbo._Document154 sale ON sale._IDRRef=line._Document154_IDRRef
 WHERE sale._Posted=0x01 AND sale._Marked=0x00
 AND CASE WHEN sale._Date_Time>'30000101' THEN DATEADD(year,-2000,sale._Date_Time)
     ELSE sale._Date_Time END <= '2026-09-21T20:12:12'
), by_sale AS (
 SELECT _Fld3308_RRRef AS sale_ref, COUNT_BIG(*) AS movements,
 SUM(CASE WHEN _RecordKind=1 THEN CAST(_Fld3311 AS decimal(15,2)) ELSE 0 END) AS charge,
 SUM(CASE WHEN _RecordKind=0 THEN CAST(_Fld3311 AS decimal(15,2)) ELSE 0 END) AS paid,
 SUM(CASE WHEN _RecordKind=1 THEN CAST(_Fld3311 AS decimal(15,2))
          WHEN _RecordKind=0 THEN -CAST(_Fld3311 AS decimal(15,2)) ELSE 0 END) AS debt
 FROM dbo._AccumRg3305
 WHERE _Active=0x01 AND _Fld3308_RTRef=0x0000009A
 AND CASE WHEN _Period>'30000101' THEN DATEADD(year,-2000,_Period)
     ELSE _Period END <= '2026-09-21T20:12:12'
 GROUP BY _Fld3308_RRRef
), by_membership AS (
 SELECT links.subscription_ref, SUM(COALESCE(s.movements,0)) AS movements,
 SUM(COALESCE(s.charge,0)) AS charge,SUM(COALESCE(s.paid,0)) AS paid,
 SUM(COALESCE(s.debt,0)) AS debt
 FROM links LEFT JOIN by_sale s ON s.sale_ref=links.sale_ref
 GROUP BY links.subscription_ref
)
SELECT COUNT_BIG(*) AS checked_facts,
 SUM(CASE WHEN m.financial_register_row_count<>COALESCE(r.movements,0) THEN 1 ELSE 0 END) AS movement_count_mismatches,
 SUM(CASE WHEN m.financial_register_charge_sum<>COALESCE(r.charge,0) THEN 1 ELSE 0 END) AS charge_mismatches,
 SUM(CASE WHEN m.financial_register_payment_sum<>COALESCE(r.paid,0) THEN 1 ELSE 0 END) AS paid_mismatches,
 SUM(CASE WHEN m.financial_register_signed_debt<>COALESCE(r.debt,0) THEN 1 ELSE 0 END) AS debt_mismatches,
 SUM(CASE WHEN m.financial_register_allocation_unambiguous=1 AND m.financial_register_row_count>0 THEN 1 ELSE 0 END) AS unambiguous_with_register,
 SUM(CASE WHEN m.financial_register_allocation_unambiguous=1 AND m.financial_register_signed_debt<0 THEN 1 ELSE 0 END) AS negative_register_debt_cases
FROM fitbase_part2.membership_import_facts m
LEFT JOIN by_membership r ON r.subscription_ref=m.subscription_ref
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff", default="2026-09-21 20:12:12")
    parser.add_argument("--output", type=Path, default=ROOT / "output/20260921_financial_audit")
    parser.add_argument("--database", default="FitnessRestored_20260630_macos")
    parser.add_argument("--port", type=int, default=11435)
    args = parser.parse_args()
    cutoff = datetime.fromisoformat(args.cutoff).strftime("%Y-%m-%d %H:%M:%S")
    if cutoff != args.cutoff:
        raise ValueError("Expected a SQL-local timestamp with second precision")
    query = QUERY.replace("2026-09-21T20:12:12", cutoff.replace(" ", "T"))
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    (output / "source_reconciliation.sql").write_text(query, encoding="utf-8")
    password = read_sql_password(ROOT / "tmp/macos-backup/mssql-fitness-macos.env")
    with DatabaseClient(ConnectionSettings(
        server="127.0.0.1", port=args.port, database=args.database,
        user="sa", password=password, query_timeout_seconds=600,
    )) as db:
        staging_cutoffs = query_dicts(db, "SELECT DISTINCT cutoff_at FROM fitbase_part2.membership_import_facts")
        if len(staging_cutoffs) != 1 or str(staging_cutoffs[0]["cutoff_at"]) != cutoff:
            raise ValueError("Staging does not have the requested cutoff")
        result = query_dicts(db, query)[0]
    result["status"] = "PASS" if result["checked_facts"] > 0 and not any(
        value for name, value in result.items() if name.endswith("_mismatches")
    ) else "FAIL"
    result["cutoff_at"] = cutoff
    (output / "source_reconciliation.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8"
    )
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return 0 if result["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
