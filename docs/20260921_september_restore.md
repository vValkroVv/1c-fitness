# September backup restore, 2026-09-21

Restored `data/Fitnes-20-09-26.fast.bak` into the existing local database
`FitnessRestored_20260630_macos` in `mssql-fitness-2022` (SQL Server 2022,
`127.0.0.1:11434`). The technical database name remains unchanged, but its
contents now come from September. The user requested this restore after
freeing disk space. The June backup and previous deliveries were preserved.
The user subsequently clarified that both restored databases must coexist.
Using replacement was an execution mistake; a separate June restore has now
completed as `FitnessRestored_20260630_original`. Both databases are ONLINE
and their respective backup identities match. See
[both databases](20260921_both_databases.md). Future backups must use separate
databases, without `--replace-existing`.

## Source and time contract

- Backup size: 13,604,230,144 bytes.
- SHA-256: `a65f21760209e60ac3b2ffc49a15a9a308e02dd75ffeb5829c342c9d98170f52`.
- Source database: `Fitness`, full backup at position 1.
- Backup UUID: `8e76ec9f-004f-4291-9842-92017c8e9f53`.
- Actual `BackupFinishDate`: **2026-09-20 20:12:12**.
- Agreed effective snapshot (+1 day): **2026-09-21 20:12:12**.
- Dates use source SQL local time; source operations were not shifted.

## Execution

Docker Desktop was stopped and was started together with the existing SQL
container. The `/backup` and `/restoredata` mounts were verified. The host had
approximately 107 GiB free before preparation.

```bash
python3 scripts/run_fitbase_migration.py \
  --backup-file data/Fitnes-20-09-26.fast.bak \
  --backup-sql-path /backup/Fitnes-20-09-26.fast.bak \
  --database FitnessRestored_20260630_macos \
  --run-name 20260920_final \
  --effective-offset-days 1 \
  --restore --replace-existing \
  --restore-host-dir mssql-macos/data \
  --prepare-only
```

Preparation finished with exit code 0 and audit status `PASS`, from 00:36:56
to 00:39:04 Moscow time. This command completed restoration and configuration
preparation only. XLSX and photo delivery generation was not run.

Before replacement, the runner checked the existing full-restore provenance,
absence of user sessions, matching logical file names and types, unchanged
backup size/mtime, and available disk space. It reused the existing MDF/LDF:

| Logical file | Host file | Size, bytes |
| --- | --- | ---: |
| Fitness | `mssql-macos/data/FitnessRestored_20260630_macos.mdf` | 80,404,807,680 |
| Fitness_log | `mssql-macos/data/FitnessRestored_20260630_macos_log.ldf` | 3,699,376,128 |

The combined allocation is 78.328 GiB. Required growth was zero; the runner
checked its additional 2 GiB reserve. The previous June restore provenance
and file paths remain in the preparation audit.

## Validation

- Local SHA-256 matched the independently verified download.
- `RESTORE HEADERONLY`, `FILELISTONLY`, and `VERIFYONLY`: PASS.
- Latest full restore in `msdb` matched the source database, backup position,
  UUID, and actual backup finish time. Restore history ID: 1002.
- Database state: `ONLINE`, access: `MULTI_USER`, recovery: `SIMPLE`.
- Compatibility level: 130.
- User tables: 2,503; user columns: 19,421.
- Metadata row counts: `_AccumRg3305` 799,437; `_Document131` 2,023;
  `_InfoRg3060` 123,101. These are restore access checks, not delivery counts.

The initial `DBCC CHECKDB ... WITH PHYSICAL_ONLY` reported snapshot creation
errors 1823/5149/7928, including OS error 31 while expanding the internal
`_MSSQL_DBCC6` file in the Docker bind mount. Although SQL attempted a fallback
and reached the completion marker, sqlcmd returned 1, so this attempt was
not accepted as a clean check.

A separate `DBCC CHECKDB ... WITH PHYSICAL_ONLY, TABLOCK, NO_INFOMSGS`
completed with exit code **0**, the completion marker, and no reported errors.
The database remained `ONLINE` and `MULTI_USER`. Final free host space was
approximately **100 GiB**.
[Microsoft documents TABLOCK](https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql)
as checking with locks instead of an internal snapshot. This is a physical
integrity check; full logical CHECKDB validation is outside this restore run.

## Artifacts and next step

- `logs/20260921_restore_september.log`
- `logs/20260921_post_restore_checks.txt` (includes the initial snapshot errors)
- `logs/20260921_post_restore_physical_tablock.txt`
- `end-to-end-xlsx/work/prepared/20260920_final/backup_metadata.json`
- `end-to-end-xlsx/work/prepared/20260920_final/pipeline.yml`
- `end-to-end-xlsx/work/prepared/20260920_final/expected.yml`

The prepared directory is immutable; do not repeat preparation with the same
run name. A later complete migration can use `--use-existing` and a new run
name to verify and use this restored September database. The final delivery
still needs all pipeline, business-data, and photo checks.
