# macOS backup restore check: Fitnes-23-05-26.bak

Run date: `2026-06-22`

## Итог

Backup `data/Fitnes-23-05-26.bak` удалось восстановить локально на macOS.

Текущая рабочая база:

```text
container: mssql-fitness-macos
image: mcr.microsoft.com/azure-sql-edge:latest
version: Microsoft Azure SQL Edge Developer 15.0.2000.1574 ARM64
host port: 127.0.0.1:11433
database: FitnessRestored_20260523_macos
state: ONLINE
user_tables: 2503
user_columns: 19421
SQL data folder: mssql-macos/
```

Контейнер после финальной проверки оставлен запущенным.

## Безопасность Mac

- Системные пакеты macOS не ставились.
- Docker Desktop был использован как уже установленный runtime.
- SQL Server запускался в отдельном контейнере `mssql-fitness-macos`.
- Старые `mssql/` и `tmp/mssql-fitness.env` не трогались.
- Для macOS runtime использованы отдельные пути:
  - `mssql-macos/`
  - `tmp/macos-backup/`
  - `logs/macos-backup/`
  - `sql/macos-backup/`
  - `docs/macos-backup/`
- `mssql-macos/` добавлен в `.gitignore`, потому что это runtime data на десятки гигабайт.

## Host/Docker environment

```text
host: macOS Darwin ARM64, Apple M3 Pro
host RAM: 19327352832 bytes
Docker Desktop VM memory: 7.653 GiB
Docker Desktop VM CPUs: 12
free disk before final restored state cleanup/retry: about 126 GiB
free disk after restored DB kept: about 47 GiB
restored SQL data size: about 78 GiB
```

## Backup file

```text
path: data/Fitnes-23-05-26.bak
sha256: 0964142666cd98da0cd1d72340e8399e329d348a44ccefa0033f2fbf2933f191
```

SHA256 matched the earlier Linux restore documentation.

## Pre-restore checks

SQL files:

```text
sql/macos-backup/01_restore_headeronly_20260523.sql
sql/macos-backup/02_restore_filelistonly_20260523.sql
sql/macos-backup/03_restore_verifyonly_20260523.sql
```

Logs:

```text
logs/macos-backup/restore_headeronly_20260523.txt
logs/macos-backup/restore_filelistonly_20260523.txt
logs/macos-backup/restore_verifyonly_20260523.txt
logs/macos-backup/backup_sha256.txt
```

Key results:

```text
DatabaseName: Fitness
BackupStartDate: 2026-05-23 23:16:00
BackupFinishDate: 2026-05-23 23:17:17
DatabaseVersion: 852
CompatibilityLevel: 130
CompressedBackupSize: 12909320329
LogicalName data: Fitness
LogicalName log: Fitness_log
VERIFYONLY: The backup set on file 1 is valid.
```

## Successful restore

Final successful restore used bind mount storage, not Docker named volume:

```text
/Users/valerii.kropotin/Папа-работа/1c-preprocess/mssql-macos:/var/opt/mssql
/Users/valerii.kropotin/Папа-работа/1c-preprocess/data:/backup:ro
```

Final working container config:

```text
container memory: 6 GiB
container CPUs: 2
capability: SYS_PTRACE
SQL env MSSQL_MEMORY_LIMIT_MB: 4096
```

Restore SQL:

```text
sql/macos-backup/04_restore_database_20260523_macos.sql
```

Successful restore log:

```text
logs/macos-backup/restore_bind_retry_20260523_macos.log
```

Timing:

```text
started_at: 2026-06-22T01:15:41+0300
finished_at: 2026-06-22T01:19:38+0300
```

Restore summary:

```text
RESTORE DATABASE successfully processed 6890046 pages in 108.022 seconds (498.310 MB/sec).
```

Post-restore check was done with a local Python venv and `pymssql`, because the
amd64 `mssql-tools` client containers became unreliable after the large restore
on Docker Desktop.

Post-check script/log:

```text
scripts/macos_backup_post_restore_check.py
logs/macos-backup/post_restore_checks_python_after_docker_restart_20260523_macos.txt
```

Post-check result:

```text
database                         state_desc  recovery_model_desc  compatibility_level
FitnessRestored_20260523_macos   ONLINE      SIMPLE               130

user_tables: 2503
user_columns: 19421
```

## Important macOS findings

1. Azure SQL Edge ARM64 needs `--cap-add SYS_PTRACE` on this Docker Desktop setup.
   Without it, `sqlservr` crashes during startup with `SIGABRT` and
   `S_SbtUnimplementedInstruction`.

2. Docker named volume was tested and rejected for this run. With
   `fitness_macos_sql_20260523:/var/opt/mssql`, Azure SQL Edge crashed during
   startup of `master`, even with `SYS_PTRACE`.

3. Bind mount restore works, but Docker Desktop can temporarily keep deleted
   large MDF/LDF files open through `com.apple.Virtualization.VirtualMachine`.
   When that happened, disk space returned only after restarting Docker Desktop.

4. The first bind-mount restore attempt reached `100 percent processed`, but
   crashed during recovery. The stable final run used fewer CPUs (`2`) and then
   the container was recreated with `6g` memory before final post-check.

5. After the successful restore, direct SQL clients timed out until Docker
   Desktop/container were restarted. After restart, SQL Server reported the
   restored database during startup and the Python post-check succeeded.

6. Current restored data consumes about `78 GiB`; free disk is about `47 GiB`.
   Do not run another full restore without either deleting `mssql-macos/` or
   freeing additional disk.

## Later SQL runtime issue and working recovery path

Update date: `2026-06-22`, during owner-change fix work.

The restored data in `mssql-macos/data/` remained usable, but the original
Azure SQL Edge ARM64 container became unstable during SQL discovery. A broad
metadata scan over many `_Document*` tables caused `sqlservr` to abort. After
that, recreating/starting `mssql-fitness-macos` repeatedly crashed before the
SQL listener opened.

Observed failure:

```text
container: mssql-fitness-macos
image: mcr.microsoft.com/azure-sql-edge:latest
symptom: container exits with code 1 before SQL port is available
dump signal: SIGABRT
stack marker: S_SbtUnimplementedInstruction
stage: startup of master, before restored database access
OOMKilled: false
```

This is a runtime/container problem, not evidence that the restored
`FitnessRestored_20260523_macos.mdf/.ldf` files are unusable.

The working path was to run full SQL Server 2022 under amd64 emulation and
attach the already-restored MDF/LDF files:

```text
container: mssql-fitness-2022
image: mcr.microsoft.com/mssql/server:2022-latest
platform: linux/amd64
host port: 127.0.0.1:11434
system SQL data: Docker volume fitness_mssql_2022_system
attached database files: mssql-macos/data/FitnessRestored_20260523_macos.mdf/.ldf
database: FitnessRestored_20260523_macos
state after attach: ONLINE
compatibility_level: 130
```

Use this helper for future heavy SQL work on macOS:

```bash
scripts/29_start_mssql_2022_attach_macos.sh
```

It starts `mssql-fitness-2022`, joins it to the existing
`fitness-macos-sql` Docker network, waits for SQL readiness, and runs:

```sql
CREATE DATABASE [FitnessRestored_20260523_macos]
ON (FILENAME = N'/restoredata/FitnessRestored_20260523_macos.mdf'),
   (FILENAME = N'/restoredata/FitnessRestored_20260523_macos_log.ldf')
FOR ATTACH;
```

Check the attached database through the tools container:

```bash
SQLCMD_SERVER=mssql-fitness-2022,1433 \
scripts/macos_backup_sqlcmd.sh -Q "
SELECT name, state_desc, compatibility_level
FROM sys.databases
WHERE name = N'FitnessRestored_20260523_macos';
"
```

For pipeline commands that use `scripts/11_export_part2_stage.py`, point the
exporter to the macOS tools wrapper and the SQL Server 2022 container:

```bash
PART2_SQLCMD=scripts/macos_backup_sqlcmd.sh \
SQLCMD_SERVER=mssql-fitness-2022,1433 \
scripts/11_export_part2_stage.py \
  --database FitnessRestored_20260523_macos \
  --cutoff-date 2026-05-25 \
  --cutoff-at "2026-05-25 08:00:00" \
  --backup-finish-at "2026-05-23 23:17:17" \
  --output-run-label <run_label> \
  --output-dir <output_dir>/staging \
  --reports-dir <output_dir>/reports \
  --logs-dir logs
```

For the owner-change fixed build, the complete wrapper is:

```bash
scripts/30_build_owner_change_fix_outputs.sh
```

Operational notes:

- Do not delete `mssql-macos/data/*.mdf` or `mssql-macos/data/*.ldf`; these are
  the restored database files reused by SQL Server 2022.
- It is safe to delete Azure SQL Edge crash dump directories like
  `mssql-macos/log/core.sqlservr.*.d` if disk space is needed. Do not delete
  normal database files.
- Avoid broad exploratory scans against `mssql-fitness-macos` / Azure SQL Edge
  ARM64. For schema discovery, staging builds, and large joins, use
  `mssql-fitness-2022`.
- `scripts/macos_backup_sqlcmd.sh` runs `mssql-tools` in a separate container.
  When using SQL Server 2022, set `SQLCMD_SERVER=mssql-fitness-2022,1433`;
  do not rely on the old `mssql-fitness-macos` default.

## Reuse commands

Check container:

```bash
docker ps --filter name=mssql-fitness-macos
```

Run Python post-check:

```bash
tmp/macos-backup/pycheck-venv/bin/python scripts/macos_backup_post_restore_check.py
```

Start the macOS SQL container if it is removed and `mssql-macos/` is still present:

```bash
MSSQL_CONTAINER_NAME=mssql-fitness-macos \
MSSQL_CPUS=2 \
MSSQL_CONTAINER_MEMORY=6g \
scripts/macos_backup_start_mssql_container.sh
```

Preferred check for the stable SQL Server 2022 attached runtime:

```bash
scripts/29_start_mssql_2022_attach_macos.sh
```
