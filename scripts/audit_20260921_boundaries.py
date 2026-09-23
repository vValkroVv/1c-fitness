#!/usr/bin/env python3
"""Read-only SQL audit of the agreed September 21 migration snapshot.

Run only after the final migration has finished building its SQL staging.
All database commands are SELECT queries. Evidence is written to separate files.
"""

from __future__ import annotations

import argparse
import csv
from datetime import datetime, timedelta
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "end-to-end-xlsx"
sys.path[:0] = [str(PACKAGE / "scripts"), str(ROOT / "scripts")]

import yaml

from database import ConnectionSettings, DatabaseClient
from prepare_backup import verify_restored_backup
from run_fitbase_migration import read_sql_password

FINISH = "2026-09-20 20:12:12"
CUTOFF = "2026-09-21 20:12:12"


def real_time(column: str) -> str:
    return f"CASE WHEN {column} > '3000-01-01' THEN DATEADD(year,-2000,{column}) ELSE {column} END"


def queries(finish: str = FINISH, cutoff: str = CUTOFF) -> dict[str, str]:
    FINISH, CUTOFF = finish, cutoff
    finish_day, cutoff_day = FINISH[:10], CUTOFF[:10]
    previous_day = (datetime.fromisoformat(CUTOFF) - timedelta(days=1)).date().isoformat()
    result = {
        "owner_metadata": "SELECT cutoff_date, cutoff_at, backup_finish_at, built_at FROM fitbase_part2.staging_run_metadata",
        "layer_timestamps": "\nUNION ALL\n".join(
            f"SELECT '{table}' AS layer, COUNT_BIG(*) AS rows_count, COUNT_BIG({column}) AS stamped_rows, "
            f"CONVERT(varchar(19),MIN({column}),120) AS minimum, CONVERT(varchar(19),MAX({column}),120) AS maximum "
            f"FROM fitbase_part2.{table}"
            for table, column in (("final_funnel_clients", "cutoff_date"), ("membership_import_facts", "cutoff_at"), ("services_import_facts", "cutoff_at"))
        ),
    }
    source_events = "\nUNION ALL\n".join(
        f"SELECT '{table}' AS source, _Number AS document_number, {real_time('_Date_Time')} AS event_at, "
        "CASE WHEN _Posted=0x01 AND _Marked=0x00 THEN 1 ELSE 0 END AS posted_unmarked "
        f"FROM dbo.{table}"
        for table in ("_Document163", "_Document154", "_Document152", "_Document138")
    )
    result["source_document_boundaries"] = f"""
WITH events AS ({source_events})
SELECT source, COUNT_BIG(*) AS total_documents,
 SUM(CASE WHEN event_at>'{FINISH}' AND event_at<='{CUTOFF}' THEN 1 ELSE 0 END) AS between_finish_and_cutoff,
 SUM(CASE WHEN event_at>'{FINISH}' AND event_at<='{CUTOFF}' AND posted_unmarked=1 THEN 1 ELSE 0 END) AS posted_between_finish_and_cutoff,
 SUM(CASE WHEN event_at>'{CUTOFF}' THEN 1 ELSE 0 END) AS after_cutoff,
 SUM(CASE WHEN event_at='{CUTOFF}' THEN 1 ELSE 0 END) AS exactly_at_cutoff,
 MIN(CASE WHEN event_at>'{FINISH}' THEN event_at END) AS first_after_finish,
 MAX(event_at) AS latest_source_document
FROM events GROUP BY source ORDER BY source
"""
    result["source_boundary_document_examples"] = f"""
WITH events AS ({source_events}), ranked AS (
 SELECT *, ROW_NUMBER() OVER (PARTITION BY source,
  CASE WHEN event_at<='{CUTOFF}' THEN 'included_interval' ELSE 'after_cutoff' END
  ORDER BY event_at, document_number) AS rn
 FROM events WHERE event_at>'{FINISH}'
)
SELECT source, document_number, event_at, posted_unmarked,
 CASE WHEN event_at<='{CUTOFF}' THEN 'included_interval' ELSE 'after_cutoff' END AS interval
FROM ranked WHERE rn<=8 ORDER BY source, event_at, document_number
"""
    fact_columns = {
        "membership_import_facts": ("sale_datetime", "owner_change_datetime", "matched_payment_datetime", "financial_sale_document_datetime", "financial_register_last_movement_datetime"),
        "services_import_facts": ("sale_datetime", "service_doc_datetime", "payment_datetime"),
    }
    result["fact_event_boundaries"] = "\nUNION ALL\n".join(
        f"SELECT '{table}' AS layer, '{column}' AS event_column, COUNT_BIG({column}) AS present_rows, "
        f"SUM(CASE WHEN {column}>'{FINISH}' AND {column}<='{CUTOFF}' THEN 1 ELSE 0 END) AS between_finish_and_cutoff, "
        f"SUM(CASE WHEN {column}>'{CUTOFF}' THEN 1 ELSE 0 END) AS after_cutoff, "
        f"MAX({column}) AS latest_event FROM fitbase_part2.{table}"
        for table, columns in fact_columns.items() for column in columns
    )
    result["membership_end_boundaries"] = f"""
SELECT end_date, is_full_subscription, is_active_on_cutoff, is_finished_before_cutoff,
 COUNT_BIG(*) AS contract_rows, COUNT(DISTINCT client_id) AS unique_clients
FROM fitbase_part2.membership_import_facts
WHERE end_date IN ('{previous_day}','{cutoff_day}')
GROUP BY end_date,is_full_subscription,is_active_on_cutoff,is_finished_before_cutoff
ORDER BY end_date,is_full_subscription,is_active_on_cutoff
"""
    result["membership_boundary_examples"] = f"""
WITH ranked AS (
 SELECT m.document_number, m.client_id, m.subscription_ref, m.sale_datetime,
  m.start_date, m.end_date, m.is_active_on_cutoff, m.is_finished_before_cutoff,
  c.funnel AS sql_funnel,
  ROW_NUMBER() OVER (PARTITION BY m.end_date ORDER BY m.document_number,m.subscription_ref) AS rn
 FROM fitbase_part2.membership_import_facts AS m
 LEFT JOIN fitbase_part2.final_funnel_clients AS c ON c.client_ref=m.client_ref
 WHERE m.is_full_subscription=1 AND m.end_date IN ('{previous_day}','{cutoff_day}')
)
SELECT document_number,client_id,subscription_ref,sale_datetime,start_date,end_date,
 is_active_on_cutoff,is_finished_before_cutoff,sql_funnel
FROM ranked WHERE rn<=8 ORDER BY end_date,document_number
"""
    result["client_boundary_transition_candidates"] = f"""
WITH states AS (
 SELECT client_ref, client_id,
 MAX(CASE WHEN sale_datetime<='{FINISH}' AND end_date>='{finish_day}' THEN 1 ELSE 0 END) AS active_at_finish,
 MAX(CASE WHEN sale_datetime<='{CUTOFF}' AND end_date>='{cutoff_day}' THEN 1 ELSE 0 END) AS active_at_cutoff,
 MAX(end_date) AS last_end_date
 FROM fitbase_part2.stg_subscriptions_all WHERE is_full_subscription=1
 GROUP BY client_ref,client_id
)
SELECT s.client_id,s.active_at_finish,s.active_at_cutoff,s.last_end_date,c.funnel AS sql_funnel
FROM states AS s LEFT JOIN fitbase_part2.final_funnel_clients AS c ON c.client_ref=s.client_ref
WHERE s.active_at_finish<>s.active_at_cutoff ORDER BY s.client_id
"""
    result["service_boundary_examples"] = f"""
SELECT TOP (30) sale_line_id,sale_client_id,service_doc_number,sale_datetime,
 service_doc_datetime,payment_datetime,service_start_date,service_register_start_date,
 service_end_date,is_active_on_cutoff,is_active_by_date,is_active_by_balance,rg3336_signed_balance
FROM fitbase_part2.services_import_facts
WHERE service_end_date IN ('{previous_day}','{cutoff_day}')
 OR service_register_start_date IN ('{previous_day}','{cutoff_day}')
 OR sale_datetime>'{FINISH}' OR service_doc_datetime>'{FINISH}' OR payment_datetime>'{FINISH}'
ORDER BY service_end_date,sale_line_id
"""
    result["future_service_documents"] = f"""
SELECT sale_line_id,sale_client_id,service_doc_number,sale_datetime,service_doc_datetime,
 service_end_date,is_active_on_cutoff,is_active_by_date,is_active_by_balance
FROM fitbase_part2.services_import_facts WHERE service_doc_datetime>'{CUTOFF}'
ORDER BY service_doc_datetime,sale_line_id
"""
    result["future_membership_exclusion"] = f"""
SELECT d._Number AS document_number, {real_time('d._Date_Time')} AS original_document_datetime,
 (SELECT COUNT_BIG(*) FROM fitbase_part2.stg_subscriptions_all AS s
  WHERE s.subscription_ref=CONVERT(varchar(32),d._IDRRef,2)) AS owner_staging_rows,
 (SELECT COUNT_BIG(*) FROM fitbase_part2.membership_import_facts AS m
  WHERE m.subscription_ref=CONVERT(varchar(32),d._IDRRef,2)) AS membership_staging_rows
FROM dbo._Document163 AS d WHERE {real_time('d._Date_Time')}>'{CUTOFF}'
ORDER BY d._Date_Time,d._Number
"""
    # Recalculate register balances directly from the source, including the
    # ignored future portion in separate columns so its exclusion is visible.
    result["service_register_cutoff_balances"] = f"""
WITH scope AS (
 SELECT DISTINCT linked_service_doc_ref FROM fitbase_part2.services_import_facts
 WHERE linked_service_doc_ref IS NOT NULL
), movements AS (
 SELECT scope.linked_service_doc_ref,{real_time('r._Period')} AS period_at,
  CASE WHEN r._RecordKind=0 THEN CAST(r._Fld3339 AS decimal(15,3))
       WHEN r._RecordKind=1 THEN -CAST(r._Fld3339 AS decimal(15,3)) ELSE 0 END AS quantity
 FROM scope JOIN dbo._AccumRg3336 AS r
  ON r._Fld3337_RRRef=CONVERT(binary(16),scope.linked_service_doc_ref,2)
 WHERE r._Active=0x01 AND r._Fld3339<>0
), balances AS (
 SELECT linked_service_doc_ref,
  SUM(CASE WHEN period_at<='{CUTOFF}' THEN quantity ELSE 0 END) AS expected_at_cutoff,
  SUM(CASE WHEN period_at>'{CUTOFF}' THEN quantity ELSE 0 END) AS excluded_future_balance,
  SUM(CASE WHEN period_at>'{CUTOFF}' THEN 1 ELSE 0 END) AS excluded_future_rows,
  MAX(period_at) AS latest_register_movement
 FROM movements GROUP BY linked_service_doc_ref
)
SELECT s.sale_line_id,s.service_doc_number,s.linked_service_doc_ref,
 s.rg3336_signed_balance AS actual_staging_balance,
 COALESCE(b.expected_at_cutoff,0) AS expected_at_cutoff,
 COALESCE(b.excluded_future_balance,0) AS excluded_future_balance,
 COALESCE(b.excluded_future_rows,0) AS excluded_future_rows,b.latest_register_movement
FROM fitbase_part2.services_import_facts AS s
LEFT JOIN balances AS b ON b.linked_service_doc_ref=s.linked_service_doc_ref
ORDER BY s.sale_line_id
"""
    result["membership_register_cutoff_balances"] = f"""
WITH named AS (
 SELECT *, CASE
  WHEN LOWER(subscription_name) LIKE N'%субаренд%'
   AND LOWER(subscription_name) NOT LIKE N'%безлимит%' THEN 'subrent'
  WHEN LOWER(subscription_name) LIKE N'%сайкл%'
   AND LOWER(subscription_name) NOT LIKE N'%безлимит%'
   AND (LOWER(subscription_name) LIKE N'%8 пос%' OR LOWER(subscription_name) LIKE N'%12 пос%') THEN 'cycle'
 END AS dimension_rule
 FROM fitbase_part2.membership_import_facts
), scope AS (
 SELECT * FROM named WHERE dimension_rule IS NOT NULL
), movements AS (
 SELECT s.subscription_ref,{real_time('r._Period')} AS period_at,r._RecordKind,
  CAST(r._Fld3339 AS decimal(15,3)) AS raw_quantity,
  CASE WHEN r._RecordKind=0 THEN CAST(r._Fld3339 AS decimal(15,3))
       WHEN r._RecordKind=1 THEN -CAST(r._Fld3339 AS decimal(15,3)) ELSE 0 END AS quantity
 FROM scope AS s JOIN dbo._AccumRg3336 AS r
  ON r._Fld3337_RRRef=CONVERT(binary(16),s.subscription_ref,2)
 WHERE r._Active=0x01 AND r._Fld3339<>0
 AND ((s.dimension_rule='subrent' AND r._Fld3338_TYPE=0x01 AND r._Fld3338_RTRef=0x00000000
       AND r._Fld3338_RRRef=0x00000000000000000000000000000000)
   OR (s.dimension_rule='cycle' AND r._Fld3338_TYPE=0x08 AND r._Fld3338_RTRef=0x00000048
       AND r._Fld3338_RRRef=0xAA9EA4BF01266AD311E8C6D3BB763918))
), balances AS (
 SELECT subscription_ref,
  SUM(CASE WHEN period_at<='{CUTOFF}' THEN quantity ELSE 0 END) AS expected_at_cutoff,
  SUM(CASE WHEN period_at<='{CUTOFF}' AND _RecordKind=0 THEN raw_quantity ELSE 0 END) AS expected_receipt,
  SUM(CASE WHEN period_at<='{CUTOFF}' AND _RecordKind=1 THEN raw_quantity ELSE 0 END) AS expected_expense,
  SUM(CASE WHEN period_at>'{CUTOFF}' THEN quantity ELSE 0 END) AS excluded_future_balance,
  SUM(CASE WHEN period_at>'{CUTOFF}' THEN 1 ELSE 0 END) AS excluded_future_rows,
  MAX(period_at) AS latest_register_movement
 FROM movements GROUP BY subscription_ref
)
SELECT s.document_number,s.client_id,s.subscription_ref,s.dimension_rule,
 s.subrent_rg3336_signed_balance AS actual_staging_balance,
 COALESCE(b.expected_at_cutoff,0) AS expected_at_cutoff,
 s.subrent_rg3336_receipt_qty AS actual_receipt,COALESCE(b.expected_receipt,0) AS expected_receipt,
 s.subrent_rg3336_expense_qty AS actual_expense,COALESCE(b.expected_expense,0) AS expected_expense,
 COALESCE(b.excluded_future_balance,0) AS excluded_future_balance,
 COALESCE(b.excluded_future_rows,0) AS excluded_future_rows,b.latest_register_movement
FROM scope AS s LEFT JOIN balances AS b ON b.subscription_ref=s.subscription_ref
ORDER BY s.document_number
"""
    membership_match = f"""
SELECT 1 FROM dbo._Document163 AS d JOIN dbo._InfoRg3060 AS r ON r._Fld3061RRef=d._IDRRef
WHERE d._IDRRef=CONVERT(binary(16),m.subscription_ref,2)
 AND m.sale_datetime={real_time('d._Date_Time')}
 AND m.start_date=CONVERT(date,{real_time('r._Fld3063')})
 AND m.end_date=CONVERT(date,{real_time('r._Fld3064')})
"""
    service_sale_match = f"""
SELECT 1 FROM dbo._Document154 AS d WHERE d._IDRRef=CONVERT(binary(16),s.sale_doc_ref,2)
AND s.sale_datetime={real_time('d._Date_Time')}
"""
    service_document_match = f"""
SELECT 1 FROM dbo._Document163 AS d WHERE d._IDRRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND s.service_doc_datetime={real_time('d._Date_Time')}
"""
    service_start_match = f"""
SELECT 1 FROM dbo._Document163 AS d WHERE d._IDRRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND (s.service_start_date=CONVERT(date,{real_time('d._Fld1450')})
 OR (s.service_start_date IS NULL AND CONVERT(date,{real_time('d._Fld1450')})<='2001-01-02'))
"""
    service_register_start_match = f"""
SELECT 1 FROM dbo._InfoRg3060 AS r WHERE r._Fld3061RRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND (s.service_register_start_date=CONVERT(date,{real_time('r._Fld3063')})
 OR (s.service_register_start_date IS NULL AND CONVERT(date,{real_time('r._Fld3063')})<='2001-01-02'))
"""
    service_end_match = f"""
SELECT 1 FROM dbo._InfoRg3060 AS r WHERE r._Fld3061RRef=CONVERT(binary(16),s.linked_service_doc_ref,2)
AND (s.service_end_date=CONVERT(date,{real_time('r._Fld3064')})
 OR (s.service_end_date IS NULL AND CONVERT(date,{real_time('r._Fld3064')})<='2001-01-02'))
"""
    result["source_date_equality"] = f"""
SELECT 'membership_sale_start_end' AS check_name,COUNT_BIG(*) AS checked_rows,
 (SELECT COUNT_BIG(*) FROM fitbase_part2.membership_import_facts AS m WHERE NOT EXISTS ({membership_match})) AS mismatched_rows
FROM fitbase_part2.membership_import_facts
UNION ALL
SELECT 'service_sale',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE NOT EXISTS ({service_sale_match}))
FROM fitbase_part2.services_import_facts
UNION ALL
SELECT 'service_document',COUNT_BIG(service_doc_datetime),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE service_doc_datetime IS NOT NULL AND NOT EXISTS ({service_document_match}))
FROM fitbase_part2.services_import_facts
UNION ALL
SELECT 'service_document_start',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE linked_service_doc_ref IS NOT NULL AND NOT EXISTS ({service_start_match}))
FROM fitbase_part2.services_import_facts WHERE linked_service_doc_ref IS NOT NULL
UNION ALL
SELECT 'service_register_start',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE linked_service_doc_ref IS NOT NULL AND NOT EXISTS ({service_register_start_match}))
FROM fitbase_part2.services_import_facts WHERE linked_service_doc_ref IS NOT NULL
UNION ALL
SELECT 'service_real_end_date',COUNT_BIG(*),
 (SELECT COUNT_BIG(*) FROM fitbase_part2.services_import_facts AS s WHERE linked_service_doc_ref IS NOT NULL AND NOT EXISTS ({service_end_match}))
FROM fitbase_part2.services_import_facts WHERE linked_service_doc_ref IS NOT NULL
"""
    result["problem4_source_dates"] = f"""
SELECT m.document_number,m.client_id,m.sale_datetime,m.start_date,m.end_date,m.cutoff_at,
 {real_time('d._Date_Time')} AS original_document_datetime,
 CONVERT(date,{real_time('r._Fld3063')}) AS original_start_date,
 CONVERT(date,{real_time('r._Fld3064')}) AS original_end_date
FROM fitbase_part2.membership_import_facts AS m
JOIN dbo._Document163 AS d ON d._IDRRef=CONVERT(binary(16),m.subscription_ref,2)
JOIN dbo._InfoRg3060 AS r ON r._Fld3061RRef=d._IDRRef
WHERE TRY_CONVERT(bigint,m.document_number)=151350
"""
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path, default=PACKAGE / "work/prepared/20260921_final/pipeline.yml")
    parser.add_argument("--port", type=int, default=11435)
    parser.add_argument("--expected-cutoff", default=CUTOFF)
    parser.add_argument("--output", type=Path, default=ROOT / "output/20260921_boundary_audit")
    parser.add_argument("--log", type=Path, default=ROOT / "logs/20260921_cutoff_boundary_audit.log")
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text(encoding="utf-8"))
    cutoff = datetime.fromisoformat(args.expected_cutoff).strftime("%Y-%m-%d %H:%M:%S")
    if cutoff != args.expected_cutoff or config["run"]["cutoff_at"] != cutoff or config["backup"]["backup_finish_at"] != FINISH:
        raise ValueError("Configuration differs from the agreed September boundary audit")
    output = args.output
    output.mkdir(parents=True, exist_ok=True)
    log_path = args.log
    log_path.parent.mkdir(parents=True, exist_ok=True)
    settings = ConnectionSettings(
        server="127.0.0.1", port=args.port, database=config["sql"]["database"], user="sa",
        password=read_sql_password(ROOT / "tmp/macos-backup/mssql-fitness-macos.env"),
        query_timeout_seconds=180,
    )
    evidence = {"started_at": datetime.now().isoformat(timespec="seconds"), "cutoff_at": cutoff, "backup_finish_at": FINISH, "queries": {}}
    with log_path.open("w", encoding="utf-8") as log, DatabaseClient(settings) as db:
        evidence["restored_backup"] = verify_restored_backup(db, settings.database, config["backup"])
        for name, sql in queries(FINISH, cutoff).items():
            (output / f"{name}.sql").write_text(sql.strip() + ";\n", encoding="utf-8")
            log.write(f"START {name}\n")
            log.flush()
            with db.connection.cursor() as cursor:
                cursor.execute(sql)
                fields = [column[0] for column in cursor.description]
                rows = [dict(zip(fields, row, strict=True)) for row in cursor.fetchall()]
            evidence["queries"][name] = rows
            with (output / f"{name}.csv").open("w", encoding="utf-8-sig", newline="") as handle:
                writer = csv.DictWriter(handle, fieldnames=fields)
                writer.writeheader()
                writer.writerows(rows)
            log.write(f"DONE {name} rows={len(rows)}\n")
            log.flush()
            print(f"{name}: {len(rows)} evidence rows", flush=True)
    q = evidence["queries"]
    errors = []
    metadata = q["owner_metadata"]
    if (len(metadata) != 1 or str(metadata[0]["cutoff_at"]) != cutoff
            or str(metadata[0]["cutoff_date"]) != cutoff[:10]
            or str(metadata[0]["backup_finish_at"]) != FINISH):
        errors.append("Owner metadata does not match the agreed timestamps")
    for row in q["layer_timestamps"]:
        expected = cutoff[:10] if row["layer"] == "final_funnel_clients" else cutoff
        if row["rows_count"] <= 0 or row["rows_count"] != row["stamped_rows"] or row["minimum"] != expected or row["maximum"] != expected:
            errors.append(f"Layer timestamp mismatch: {row['layer']}")
    for row in q["fact_event_boundaries"]:
        if row["after_cutoff"]:
            errors.append(f"Future event: {row['layer']}.{row['event_column']}={row['after_cutoff']}")
    for row in q["source_date_equality"]:
        if row["mismatched_rows"]:
            errors.append(f"Original source date mismatch: {row['check_name']}={row['mismatched_rows']}")
    for row in q["future_membership_exclusion"]:
        if row["owner_staging_rows"] or row["membership_staging_rows"]:
            errors.append(f"Future membership included: {row['document_number']}")
    balance_mismatches = sum(row["actual_staging_balance"] != row["expected_at_cutoff"] for row in q["service_register_cutoff_balances"])
    if balance_mismatches:
        errors.append(f"Service register balances differ from cutoff-filtered source: {balance_mismatches}")
    membership_balance_mismatches = sum(
        row["actual_staging_balance"] != row["expected_at_cutoff"]
        or row["actual_receipt"] != row["expected_receipt"]
        or row["actual_expense"] != row["expected_expense"]
        for row in q["membership_register_cutoff_balances"]
    )
    if membership_balance_mismatches:
        errors.append(f"Membership register balances differ from cutoff-filtered source/dimension: {membership_balance_mismatches}")
    for row in q["membership_end_boundaries"]:
        if row["is_full_subscription"]:
            expected_active = int(str(row["end_date"]) == cutoff[:10])
            if row["is_active_on_cutoff"] != expected_active or row["is_finished_before_cutoff"] != 1-expected_active:
                errors.append(f"Membership end-day rule mismatch: {row['end_date']}")
    evidence.update({"finished_at": datetime.now().isoformat(timespec="seconds"), "status": "PASS" if not errors else "FAIL", "errors": errors})
    (output / "audit.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")
    print(json.dumps({"status": evidence["status"], "errors": errors}, ensure_ascii=False), flush=True)
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
