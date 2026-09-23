#!/usr/bin/env python3
"""Read-only source comparison of the restored June and September backups.

Only SELECT queries are sent to SQL Server. No staging objects are consulted.
Raw SQL, aggregate results, and timings remain local; no client details are read.
Use --section NAME to repeat only a failed or newly added section.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "output/20260921_source_audit"
LOG = ROOT / "logs"
JUNE = "FitnessRestored_20260630_original"
SEPT = "FitnessRestored_20260630_macos"
JUNE_CUTOFF = "4026-06-30T23:27:03"
SEPT_BACKUP = "4026-09-20T20:12:12"
SEPT_CUTOFF = "4026-09-21T20:12:12"


def run_query(name: str, body: str) -> list[dict]:
    OUT.mkdir(parents=True, exist_ok=True)
    LOG.mkdir(exist_ok=True)
    sql = "SET NOCOUNT ON; SET LOCK_TIMEOUT 60000;\n" + body.rstrip(";\n") + " FOR JSON PATH, INCLUDE_NULL_VALUES OPTION (MAXDOP 2);\n"
    (OUT / f"{name}.sql").write_text(sql)
    started = time.monotonic()
    env = {**os.environ, "SQLCMD_SERVER": "mssql-fitness-2022,1433"}
    result = subprocess.run(
        [str(ROOT / "scripts/macos_backup_sqlcmd.sh"), "-b",
         "-y", "0", "-w", "65535", "-d", "master", "-Q", sql],
        cwd=ROOT, env=env, capture_output=True, text=True, timeout=600,
    )
    (LOG / f"20260921_source_comparison_{name}.txt").write_text(result.stdout + result.stderr)
    result.check_returncode()
    # FOR JSON may be returned by sqlcmd in several output chunks.
    data = json.loads("".join(result.stdout.strip().splitlines()) or "[]")
    (OUT / f"{name}.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
    print(f"{name}: {len(data)} aggregate rows, {time.monotonic() - started:.1f}s", flush=True)
    return data


def schema_sql(db: str) -> str:
    return f"""SELECT t.name table_name,c.name column_name,c.column_id,c.system_type_id,
        c.max_length,c.precision,c.scale,c.is_nullable,c.collation_name
        FROM [{db}].sys.tables t JOIN [{db}].sys.columns c ON c.object_id=t.object_id
        JOIN [{db}].sys.schemas s ON s.schema_id=t.schema_id WHERE s.name='dbo'"""


def count_if(condition: str, label: str) -> str:
    return f"SUM(CONVERT(bigint,CASE WHEN {condition} THEN 1 ELSE 0 END)) [{label}]"


def identity_sql(table: str, keys: list[str], fields: list[str]) -> str:
    join = " AND ".join(f"j.[{k}]=s.[{k}]" for k in keys)
    first = keys[0]
    both = f"j.[{first}] IS NOT NULL AND s.[{first}] IS NOT NULL"
    expressions = [f"N'{table}' table_name", f"COUNT_BIG(j.[{first}]) june_rows",
                   f"COUNT_BIG(s.[{first}]) september_rows",
                   count_if(both, "retained"), count_if(f"s.[{first}] IS NULL", "removed"),
                   count_if(f"j.[{first}] IS NULL", "added")]
    for field in fields:
        # Binary comparison preserves case and trailing spaces in string fields.
        differs = (f"CONVERT(varbinary(max),j.[{field}])<>CONVERT(varbinary(max),s.[{field}]) "
                   f"OR (j.[{field}] IS NULL AND s.[{field}] IS NOT NULL) "
                   f"OR (j.[{field}] IS NOT NULL AND s.[{field}] IS NULL)")
        expressions.append(count_if(f"{both} AND ({differs})", f"changed{field}"))
    return ("SELECT " + ",\n".join(expressions)
            + f" FROM [{JUNE}].dbo.[{table}] j FULL JOIN [{SEPT}].dbo.[{table}] s ON {join}")


def build_queries() -> dict[str, str]:
    queries = {}
    queries["provenance"] = f"""SELECT d.name,d.state_desc,d.user_access_desc,
        h.restore_date,b.backup_start_date,b.backup_finish_date,b.backup_set_uuid,
        b.family_guid,b.database_name original_database
        FROM sys.databases d
        OUTER APPLY (SELECT TOP(1) restore_date,backup_set_id FROM msdb.dbo.restorehistory
          WHERE destination_database_name=d.name AND restore_type='D' ORDER BY restore_history_id DESC) h
        LEFT JOIN msdb.dbo.backupset b ON b.backup_set_id=h.backup_set_id
        WHERE d.name IN ('{JUNE}','{SEPT}') ORDER BY d.name"""
    queries["schema_differences"] = f"""WITH j AS ({schema_sql(JUNE)}),s AS ({schema_sql(SEPT)})
        SELECT COALESCE(j.table_name,s.table_name) table_name,COALESCE(j.column_name,s.column_name) column_name,
        CASE WHEN j.table_name IS NULL THEN 'added' WHEN s.table_name IS NULL THEN 'removed' ELSE 'changed' END kind
        FROM j FULL JOIN s ON j.table_name=s.table_name AND j.column_name=s.column_name
        WHERE j.table_name IS NULL OR s.table_name IS NULL
          OR EXISTS(SELECT j.column_id,j.system_type_id,j.max_length,j.precision,j.scale,j.is_nullable,j.collation_name
                    EXCEPT SELECT s.column_id,s.system_type_id,s.max_length,s.precision,s.scale,s.is_nullable,s.collation_name)
        ORDER BY table_name,column_name"""
    queries["schema_summary"] = f"""SELECT 'june' snapshot,COUNT(DISTINCT table_name) tables_count,COUNT_BIG(*) columns_count FROM ({schema_sql(JUNE)}) j
        UNION ALL SELECT 'september' snapshot,COUNT(DISTINCT table_name),COUNT_BIG(*) FROM ({schema_sql(SEPT)}) s"""
    counts = []
    for db, label in [(JUNE, "june"), (SEPT, "september")]:
        counts.append(f"""SELECT '{label}' snapshot,t.name table_name,SUM(p.row_count) rows_metadata
            FROM [{db}].sys.tables t JOIN [{db}].sys.schemas s ON s.schema_id=t.schema_id
            JOIN [{db}].sys.dm_db_partition_stats p ON p.object_id=t.object_id AND p.index_id IN (0,1)
            WHERE s.name='dbo' GROUP BY t.name""")
    queries["table_inventory"] = "SELECT * FROM (" + " UNION ALL ".join(counts) + ") q ORDER BY table_name,snapshot"
    specs = {
        "_Reference64": (["_IDRRef"], ["_Code", "_Description", "_Marked", "_Fld3822", "_Fld3832", "_Fld3831RRef"]),
        "_Reference59": (["_IDRRef"], ["_Code", "_Marked", "_Fld3750_RRRef", "_Fld3753", "_Fld3756", "_Fld3751"]),
        "_Reference72": (["_IDRRef"], ["_Code", "_Description", "_Marked"]),
        "_Reference105": (["_IDRRef"], ["_Code", "_Description", "_Marked"]),
        "_Reference5062": (["_IDRRef"], ["_Code", "_Description", "_Marked"]),
        "_Document163": (["_IDRRef"], ["_Number", "_Date_Time", "_Posted", "_Marked", "_Fld1446RRef", "_Fld9152RRef", "_Fld1447_RRRef", "_Fld1443RRef"]),
        "_Document154": (["_IDRRef"], ["_Number", "_Date_Time", "_Posted", "_Marked", "_Fld1119RRef", "_Fld1116RRef"]),
        "_Document152": (["_IDRRef"], ["_Number", "_Date_Time", "_Posted", "_Marked", "_Fld1080", "_Fld1057_RRRef", "_Fld1058RRef", "_Fld1074RRef"]),
        "_Document138": (["_IDRRef"], ["_Number", "_Date_Time", "_Posted", "_Marked"]),
        "_Document131": (["_IDRRef"], ["_Number", "_Date_Time", "_Posted", "_Marked"]),
        "_Document154_VT1137": (["_Document154_IDRRef", "_KeyField", "_Fld346"], ["_Fld1146RRef", "_Fld1148_RRRef", "_Fld1144", "_Fld1145", "_Fld1154", "_Fld1140", "_Fld1160"]),
        "_Document152_VT1083": (["_Document152_IDRRef", "_KeyField", "_Fld346"], ["_Fld1087_RRRef"]),
        "_InfoRg3060": (["_Fld3061RRef", "_Fld346"], ["_Fld3063", "_Fld3064", "_Fld5960RRef", "_Fld3070", "_Fld3072", "_Fld8007", "_Fld8008", "_Fld8009"]),
        "_AccumRg3305": (["_RecorderRRef", "_RecorderTRef", "_LineNo", "_Fld346"], ["_Period", "_Active", "_RecordKind", "_Fld3307_RRRef", "_Fld3308_RRRef", "_Fld3311", "_Fld3312"]),
        "_AccumRg3336": (["_RecorderRRef", "_RecorderTRef", "_LineNo", "_Fld346"], ["_Period", "_Active", "_RecordKind", "_Fld3337_RRRef", "_Fld3338_RRRef", "_Fld3339"]),
    }
    for table, (keys, fields) in specs.items():
        queries[f"identity{table}"] = identity_sql(table, keys, fields)
    for table in ["_Document163", "_Document154", "_Document152", "_Document138", "_Document131"]:
        queries[f"chronology{table}"] = f"""SELECT '{table}' table_name,COUNT_BIG(*) added_total,
            {count_if(f"s._Date_Time<='{JUNE_CUTOFF}'", 'added_at_or_before_june')},
            {count_if(f"s._Date_Time>'{JUNE_CUTOFF}' AND s._Date_Time<='{SEPT_BACKUP}'", 'added_between_backups')},
            {count_if(f"s._Date_Time>'{SEPT_BACKUP}' AND s._Date_Time<='{SEPT_CUTOFF}'", 'added_in_effective_day')},
            {count_if(f"s._Date_Time>'{SEPT_CUTOFF}'", 'added_after_effective_cutoff')},
            CONVERT(varchar(19),DATEADD(year,-2000,MIN(s._Date_Time)),126) added_min_date,
            CONVERT(varchar(19),DATEADD(year,-2000,MAX(s._Date_Time)),126) added_max_date
            FROM [{SEPT}].dbo.[{table}] s LEFT JOIN [{JUNE}].dbo.[{table}] j ON j._IDRRef=s._IDRRef
            WHERE j._IDRRef IS NULL"""
    for table, amount, active in [("_Document152", "_Fld1080", "_Posted=0x01 AND _Marked=0x00"),
                                  ("_AccumRg3305", "CASE WHEN _RecordKind=1 THEN _Fld3311 ELSE -_Fld3311 END", "_Active=0x01"),
                                  ("_AccumRg3336", "CASE WHEN _RecordKind=0 THEN _Fld3339 ELSE -_Fld3339 END", "_Active=0x01")]:
        date = "_Date_Time" if table.startswith("_Document") else "_Period"
        parts = []
        for db, label, cutoff in [(JUNE, "june_at_june", JUNE_CUTOFF), (SEPT, "september_at_june", JUNE_CUTOFF),
                                  (SEPT, "september_at_backup", SEPT_BACKUP), (SEPT, "september_at_effective", SEPT_CUTOFF)]:
            parts.append(f"SELECT '{label}' snapshot,COUNT_BIG(*) active_rows,SUM(CAST({amount} AS decimal(38,3))) signed_amount_or_quantity FROM [{db}].dbo.[{table}] WHERE {active} AND {date}<='{cutoff}'")
        queries[f"balances{table}"] = "SELECT * FROM (" + " UNION ALL ".join(parts) + ") q"
    parts = []
    for db, label in [(JUNE, "june"), (SEPT, "september")]:
        checks = {
            "client_code_duplicate_groups": f"SELECT COUNT_BIG(*) n FROM (SELECT _Code FROM [{db}].dbo._Reference64 GROUP BY _Code HAVING COUNT_BIG(*)>1) x",
            "contract_product_missing": f"SELECT COUNT_BIG(*) n FROM [{db}].dbo._Document163 d LEFT JOIN [{db}].dbo._Reference72 r ON r._IDRRef=d._Fld1446RRef WHERE d._Fld1446RRef<>0x00000000000000000000000000000000 AND r._IDRRef IS NULL",
            "contract_holder_missing": f"SELECT COUNT_BIG(*) n FROM [{db}].dbo._Document163 d LEFT JOIN [{db}].dbo._Reference64 r ON r._IDRRef=d._Fld9152RRef WHERE d._Fld9152RRef<>0x00000000000000000000000000000000 AND r._IDRRef IS NULL",
            "register_contract_missing": f"SELECT COUNT_BIG(*) n FROM [{db}].dbo._InfoRg3060 g LEFT JOIN [{db}].dbo._Document163 d ON d._IDRRef=g._Fld3061RRef WHERE d._IDRRef IS NULL",
            "sales_client_missing": f"SELECT COUNT_BIG(*) n FROM [{db}].dbo._Document154 d LEFT JOIN [{db}].dbo._Reference64 r ON r._IDRRef=d._Fld1119RRef WHERE d._Fld1119RRef<>0x00000000000000000000000000000000 AND r._IDRRef IS NULL",
            "sales_line_document_missing": f"SELECT COUNT_BIG(*) n FROM [{db}].dbo._Document154_VT1137 l LEFT JOIN [{db}].dbo._Document154 d ON d._IDRRef=l._Document154_IDRRef WHERE d._IDRRef IS NULL",
            "payment_line_document_missing": f"SELECT COUNT_BIG(*) n FROM [{db}].dbo._Document152_VT1083 l LEFT JOIN [{db}].dbo._Document152 d ON d._IDRRef=l._Document152_IDRRef WHERE d._IDRRef IS NULL",
            "card_client_missing": f"SELECT COUNT_BIG(*) n FROM [{db}].dbo._Reference59 d LEFT JOIN [{db}].dbo._Reference64 r ON r._IDRRef=d._Fld3750_RRRef WHERE d._Fld3750_RTRef=0x00000040 AND d._Fld3750_RRRef<>0x00000000000000000000000000000000 AND r._IDRRef IS NULL",
        }
        for name, query in checks.items():
            parts.append(f"SELECT '{label}' snapshot,'{name}' check_name,n FROM ({query}) a")
    queries["references"] = "SELECT * FROM (" + " UNION ALL ".join(parts) + ") q ORDER BY check_name,snapshot"
    queries["removed_sale_lines"] = f"""SELECT CONVERT(varchar(19),DATEADD(year,-2000,d._Date_Time),126) sale_date,
        CONVERT(int,d._Posted) june_posted,CONVERT(int,sd._Posted) september_posted,
        CONVERT(int,d._Marked) june_marked,CONVERT(int,sd._Marked) september_marked,
        l._Fld1144 old_quantity,l._Fld1160 old_unit_amount,
        (SELECT COUNT_BIG(*) FROM [{JUNE}].dbo._Document154_VT1137 x WHERE x._Document154_IDRRef=d._IDRRef) june_document_lines,
        (SELECT COUNT_BIG(*) FROM [{SEPT}].dbo._Document154_VT1137 x WHERE x._Document154_IDRRef=d._IDRRef) september_document_lines
        FROM [{JUNE}].dbo._Document154_VT1137 l
        LEFT JOIN [{SEPT}].dbo._Document154_VT1137 s
          ON l._Document154_IDRRef=s._Document154_IDRRef AND l._KeyField=s._KeyField AND l._Fld346=s._Fld346
        JOIN [{JUNE}].dbo._Document154 d ON d._IDRRef=l._Document154_IDRRef
        JOIN [{SEPT}].dbo._Document154 sd ON sd._IDRRef=d._IDRRef
        WHERE s._Document154_IDRRef IS NULL"""
    same_sale_fields = ["_Fld1146RRef", "_Fld1148_RRRef", "_Fld1144", "_Fld1145", "_Fld1154", "_Fld1140", "_Fld1160"]
    queries["rekeyed_sale_line_equivalence"] = f"""SELECT COUNT_BIG(*) replaced_lines,
        {count_if(' AND '.join('j.'+f+'=replacement.'+f for f in same_sale_fields),'same_product_contract_quantities_amounts')}
        FROM [{JUNE}].dbo._Document154_VT1137 j
        LEFT JOIN [{SEPT}].dbo._Document154_VT1137 oldkey
          ON j._Document154_IDRRef=oldkey._Document154_IDRRef AND j._KeyField=oldkey._KeyField AND j._Fld346=oldkey._Fld346
        JOIN [{SEPT}].dbo._Document154_VT1137 replacement ON replacement._Document154_IDRRef=j._Document154_IDRRef
        WHERE oldkey._Document154_IDRRef IS NULL"""
    queries["rekeyed_payment_line_equivalence"] = f"""SELECT COUNT_BIG(*) replaced_lines,
        {count_if('j._Fld1087_RRRef=replacement._Fld1087_RRRef','same_linked_sale')}
        FROM [{JUNE}].dbo._Document152_VT1083 j
        LEFT JOIN [{SEPT}].dbo._Document152_VT1083 oldkey
          ON j._Document152_IDRRef=oldkey._Document152_IDRRef AND j._KeyField=oldkey._KeyField AND j._Fld346=oldkey._Fld346
        JOIN [{SEPT}].dbo._Document152_VT1083 replacement ON replacement._Document152_IDRRef=j._Document152_IDRRef
        WHERE oldkey._Document152_IDRRef IS NULL"""
    queries["changed_contract_dates"] = f"""SELECT
        CONVERT(varchar(19),DATEADD(year,-2000,j._Date_Time),126) june_date,
        CONVERT(varchar(19),DATEADD(year,-2000,s._Date_Time),126) september_date,
        CONVERT(int,j._Posted) june_posted,CONVERT(int,s._Posted) september_posted,
        CONVERT(int,j._Marked) june_marked,CONVERT(int,s._Marked) september_marked
        FROM [{JUNE}].dbo._Document163 j JOIN [{SEPT}].dbo._Document163 s ON s._IDRRef=j._IDRRef
        WHERE j._Date_Time<>s._Date_Time"""
    queries["product_catalog_changes"] = f"""SELECT s._Code product_code,
        j._Description june_name,s._Description september_name,
        CASE WHEN j._IDRRef IS NULL THEN 'added' ELSE 'renamed' END change_kind,
        (SELECT COUNT_BIG(*) FROM [{SEPT}].dbo._Document163 d WHERE d._Fld1446RRef=s._IDRRef) september_contract_count
        FROM [{SEPT}].dbo._Reference72 s LEFT JOIN [{JUNE}].dbo._Reference72 j ON j._IDRRef=s._IDRRef
        WHERE j._IDRRef IS NULL OR CONVERT(varbinary(max),j._Description)<>CONVERT(varbinary(max),s._Description)
        ORDER BY change_kind,s._Code"""
    queries["future_contracts"] = f"""SELECT _Number contract_number,CONVERT(varchar(32),_IDRRef,2) contract_ref,
        CONVERT(varchar(19),DATEADD(year,-2000,_Date_Time),126) sale_date,
        CONVERT(int,_Posted) posted,CONVERT(int,_Marked) marked
        FROM [{SEPT}].dbo._Document163 WHERE _Date_Time>'{SEPT_CUTOFF}' ORDER BY _Date_Time"""
    movement_groups = []
    for db, label in [(JUNE, "june"), (SEPT, "september")]:
        movement_groups.append(f"""SELECT '{label}' snapshot,
            CONVERT(varchar(8),_RecorderTRef,2) recorder_type,_RecordKind record_kind,
            CASE WHEN _Period<='{JUNE_CUTOFF}' THEN 'at_or_before_june'
                 WHEN _Period<='{SEPT_BACKUP}' THEN 'july_to_september_backup'
                 WHEN _Period<='{SEPT_CUTOFF}' THEN 'extra_effective_day' ELSE 'after_effective' END period_bucket,
            CONVERT(varchar(8),_Fld3338_RTRef,2) dimension_type,COUNT_BIG(*) rows_count,
            SUM(CAST(_Fld3339 AS decimal(38,3))) quantity
            FROM [{db}].dbo._AccumRg3336 WHERE _Active=0x01
            GROUP BY _RecorderTRef,_RecordKind,_Fld3338_RTRef,
              CASE WHEN _Period<='{JUNE_CUTOFF}' THEN 'at_or_before_june'
                   WHEN _Period<='{SEPT_BACKUP}' THEN 'july_to_september_backup'
                   WHEN _Period<='{SEPT_CUTOFF}' THEN 'extra_effective_day' ELSE 'after_effective' END""")
    queries["visit_movement_timeline"] = "SELECT * FROM (" + " UNION ALL ".join(movement_groups) + ") q ORDER BY recorder_type,period_bucket,record_kind,dimension_type,snapshot"
    def historical_group(db: str) -> str:
        return f"""SELECT _Fld3337_TYPE,_Fld3337_RTRef,_Fld3337_RRRef,
            _Fld3338_TYPE,_Fld3338_RTRef,_Fld3338_RRRef,
            COUNT_BIG(*) n,SUM(CAST(CASE WHEN _RecordKind=0 THEN _Fld3339 ELSE -_Fld3339 END AS decimal(38,3))) balance
            FROM [{db}].dbo._AccumRg3336 WHERE _Active=0x01 AND _Period<='{JUNE_CUTOFF}'
            GROUP BY _Fld3337_TYPE,_Fld3337_RTRef,_Fld3337_RRRef,_Fld3338_TYPE,_Fld3338_RTRef,_Fld3338_RRRef"""
    group_keys = ["_Fld3337_TYPE", "_Fld3337_RTRef", "_Fld3337_RRRef", "_Fld3338_TYPE", "_Fld3338_RTRef", "_Fld3338_RRRef"]
    queries["historical_visit_balances"] = f"""WITH j AS ({historical_group(JUNE)}),s AS ({historical_group(SEPT)})
        SELECT CONVERT(varchar(8),COALESCE(j._Fld3337_RTRef,s._Fld3337_RTRef),2) contract_dimension_type,
        CONVERT(varchar(8),COALESCE(j._Fld3338_RTRef,s._Fld3338_RTRef),2) secondary_dimension_type,
        COUNT_BIG(*) all_groups,
        {count_if('j.n IS NOT NULL AND s.n IS NOT NULL','retained_groups')},
        {count_if('s.n IS NULL','removed_groups')}, {count_if('j.n IS NULL','added_groups')},
        {count_if('COALESCE(j.balance,0)<>COALESCE(s.balance,0)','changed_balance_groups')},
        {count_if('COALESCE(j.n,0)<>COALESCE(s.n,0)','changed_row_count_groups')},
        SUM(COALESCE(j.balance,0)) june_balance,SUM(COALESCE(s.balance,0)) september_historical_balance,
        SUM(ABS(COALESCE(s.balance,0)-COALESCE(j.balance,0))) total_absolute_balance_change
        FROM j FULL JOIN s ON {' AND '.join('j.'+k+'=s.'+k for k in group_keys)}
        GROUP BY COALESCE(j._Fld3337_RTRef,s._Fld3337_RTRef),COALESCE(j._Fld3338_RTRef,s._Fld3338_RTRef)"""
    for table in ["_AccumRg3305", "_AccumRg3336"]:
        amount = "_Fld3311" if table == "_AccumRg3305" else "_Fld3339"
        queries[f"removed{table}"] = f"""SELECT CONVERT(varchar(8),j._RecorderTRef,2) recorder_type,
            COUNT_BIG(*) removed_rows,COUNT(DISTINCT j._RecorderRRef) removed_recorders,
            MIN(CONVERT(varchar(19),DATEADD(year,-2000,j._Period),126)) min_period,
            MAX(CONVERT(varchar(19),DATEADD(year,-2000,j._Period),126)) max_period,
            j._RecordKind record_kind,SUM(j.{amount}) removed_amount_or_quantity,
            CONVERT(int,COALESCE(d152._Posted,d154._Posted,d138._Posted,d163._Posted)) september_recorder_posted,
            CONVERT(int,COALESCE(d152._Marked,d154._Marked,d138._Marked,d163._Marked)) september_recorder_marked
            FROM [{JUNE}].dbo.[{table}] j LEFT JOIN [{SEPT}].dbo.[{table}] s
              ON j._RecorderRRef=s._RecorderRRef AND j._RecorderTRef=s._RecorderTRef AND j._LineNo=s._LineNo AND j._Fld346=s._Fld346
            LEFT JOIN [{SEPT}].dbo._Document152 d152 ON j._RecorderTRef=0x00000098 AND d152._IDRRef=j._RecorderRRef
            LEFT JOIN [{SEPT}].dbo._Document154 d154 ON j._RecorderTRef=0x0000009A AND d154._IDRRef=j._RecorderRRef
            LEFT JOIN [{SEPT}].dbo._Document138 d138 ON j._RecorderTRef=0x0000008A AND d138._IDRRef=j._RecorderRRef
            LEFT JOIN [{SEPT}].dbo._Document163 d163 ON j._RecorderTRef=0x000000A3 AND d163._IDRRef=j._RecorderRRef
            WHERE s._RecorderRRef IS NULL
            GROUP BY j._RecorderTRef,j._RecordKind,
              COALESCE(d152._Posted,d154._Posted,d138._Posted,d163._Posted),
              COALESCE(d152._Marked,d154._Marked,d138._Marked,d163._Marked)"""
    return queries


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--section", action="append", help="Run only this named section; repeatable")
    parser.add_argument("--resume", action="store_true", help="Reuse completed local sections after an interrupted run")
    args = parser.parse_args()
    queries = build_queries()
    unknown = set(args.section or []) - queries.keys()
    if unknown:
        parser.error(f"Unknown sections: {sorted(unknown)}")
    for name, sql in queries.items():
        if args.section is None or name in args.section:
            if args.resume and (OUT / f"{name}.json").exists():
                continue
            run_query(name, sql)


if __name__ == "__main__":
    main()
