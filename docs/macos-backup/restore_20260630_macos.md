# macOS backup restore: Fitnes-30-06-26.bak

Run date: `2026-07-05`

## Goal

Restore the new downloaded backup for local processing and SQL queries:

```text
backup: data/Fitnes-30-06-26.bak
target database: FitnessRestored_20260630_macos
preferred runtime: mssql-fitness-2022
```

This follows the stable runtime finding from
`docs/macos-backup/restore_20260523_macos.md`: use SQL Server 2022 for heavy
work on macOS, not Azure SQL Edge ARM64.

## Runtime layout

```text
container: mssql-fitness-2022
image: mcr.microsoft.com/mssql/server:2022-latest
platform: linux/amd64
host port: 127.0.0.1:11434
system SQL data: Docker volume fitness_mssql_2022_system
restored MDF/LDF bind mount: mssql-macos/data -> /restoredata
backup bind mount: data -> /backup:ro
```

Start command:

```bash
scripts/37_start_mssql_2022_restore_runtime_macos.sh
```

Query command:

```bash
SQLCMD_SERVER=mssql-fitness-2022,1433 \
scripts/macos_backup_sqlcmd.sh -d FitnessRestored_20260630_macos -Q "SELECT DB_NAME() AS database_name;"
```

## SQL files

```text
sql/macos-backup/06_restore_headeronly_20260630.sql
sql/macos-backup/07_restore_filelistonly_20260630.sql
sql/macos-backup/08_restore_verifyonly_20260630.sql
sql/macos-backup/09_restore_database_20260630_macos.sql
sql/macos-backup/10_post_restore_checks_20260630_macos.sql
```

## Logs

```text
logs/macos-backup/restore_headeronly_20260630.txt
logs/macos-backup/restore_filelistonly_20260630.txt
logs/macos-backup/restore_verifyonly_20260630.txt
logs/macos-backup/restore_20260630_macos.log
logs/macos-backup/post_restore_checks_20260630_macos.txt
```

## Status

Status: `PASS`.

The backup was checked, restored, and verified. The SQL Server 2022 container is
left running for follow-up queries and processing.

## Pre-restore checks

`RESTORE HEADERONLY`:

```text
DatabaseName: Fitness
DatabaseVersion: 852
CompatibilityLevel: 130
BackupStartDate: 2026-06-30 23:25:54
BackupFinishDate: 2026-06-30 23:27:03
BackupSize: 57603682304
CompressedBackupSize: 13137570090
HasBackupChecksums: 0
CompressionAlgorithm: MS_XPRESS
```

`RESTORE FILELISTONLY`:

```text
LogicalName: Fitness
Type: D
Original path: D:\SQLDATA\Fitness.mdf
Size: 80404807680
BackupSizeInBytes: 57603391488

LogicalName: Fitness_log
Type: L
Original path: D:\SQLDATA\Fitness_log.ldf
Size: 3699376128
BackupSizeInBytes: 0
```

`RESTORE VERIFYONLY WITH CHECKSUM` was intentionally not used in the final check
because the backup set has `HasBackupChecksums = 0`. SQL Server rejects checksum
verification for this backup with:

```text
RESTORE WITH CHECKSUM cannot be specified because the backup set does not contain checksum information.
```

Final `RESTORE VERIFYONLY` result:

```text
The backup set on file 1 is valid.
started_at=2026-07-05T17:11:20+0300
finished_at=2026-07-05T17:12:02+0300
```

## Restore result

Restore SQL:

```text
sql/macos-backup/09_restore_database_20260630_macos.sql
```

Target files:

```text
mssql-macos/data/FitnessRestored_20260630_macos.mdf
mssql-macos/data/FitnessRestored_20260630_macos_log.ldf
```

Timing:

```text
started_at=2026-07-05T17:12:19+0300
finished_at=2026-07-05T17:15:17+0300
```

Restore summary:

```text
RESTORE DATABASE successfully processed 7031669 pages in 81.620 seconds (673.056 MB/sec).
```

SQL Server upgraded the restored database from version `852` to `957`.

## Post-restore check

Post-check command:

```bash
SQLCMD_SERVER=mssql-fitness-2022,1433 \
scripts/macos_backup_sqlcmd.sh \
  -i /sql/macos-backup/10_post_restore_checks_20260630_macos.sql \
  -o /logs/macos-backup/post_restore_checks_20260630_macos.txt
```

Result:

```text
database: FitnessRestored_20260630_macos
state_desc: ONLINE
recovery_model_desc: SIMPLE
compatibility_level: 130
user_tables: 2503
user_columns: 19421
```

Largest tables from the smoke query:

```text
dbo._InfoRg2567      20451026
dbo._AccRgED4729      8361416
dbo._AccumRg3336      7434527
dbo._AccumRgT3353     6621677
dbo._Document150      3100693
```

Runtime size after restore:

```text
mssql-macos/data: 78G
data: 24G
free disk after restore: about 106Gi
```

## Client wrapper note

During this restore, external one-off `mcr.microsoft.com/mssql-tools`
containers hung in Docker Desktop and stayed in `Created` state. SQL Server
itself was healthy, and `/opt/mssql-tools18/bin/sqlcmd` inside
`mssql-fitness-2022` worked correctly.

The wrappers were updated so that when `SQLCMD_SERVER=mssql-fitness-2022,1433`
and the container is running:

- `scripts/macos_backup_sqlcmd.sh` uses `/opt/mssql-tools18/bin/sqlcmd` inside
  `mssql-fitness-2022`;
- `scripts/macos_backup_bcp.sh` uses `/opt/mssql-tools18/bin/bcp` inside
  `mssql-fitness-2022` and copies `/output/...` queryout files back to the host.

The old external-tools-container path remains as fallback for other SQL
runtimes.

## Processing commands

Smoke query:

```bash
SQLCMD_SERVER=mssql-fitness-2022,1433 \
scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260630_macos \
  -Q "SELECT DB_NAME() AS database_name, COUNT(*) AS user_tables FROM sys.tables WHERE is_ms_shipped = 0;"
```

Before running the existing output builders against this backup, pass the new
database name explicitly:

```bash
MEMBERSHIP_DATABASE_NAME=FitnessRestored_20260630_macos \
MEMBERSHIP_SQLCMD_SERVER=mssql-fitness-2022,1433 \
scripts/31_build_membership_import_outputs.sh
```

```bash
SERVICES_DATABASE_NAME=FitnessRestored_20260630_macos \
SERVICES_SQLCMD_SERVER=mssql-fitness-2022,1433 \
scripts/32_build_services_import_outputs.sh
```
