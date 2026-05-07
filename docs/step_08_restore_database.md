# Execution Log: step 8 restore database with WITH MOVE

Date: 2026-05-07
Workspace: `/root/workspace/1c-fitness`
Plan step: `## 8. Восстановить базу через WITH MOVE`

## Preflight

Before restore:

```text
container: mssql-fitness
SQL runtime: Microsoft Azure SQL Edge Developer 15.0.2000.1574 (ARM64)
database FitnessRestored existed: no
backup verified by step 7: yes
available disk before restore: about 174G
```

Target files did not exist before restore:

```text
mssql/data/FitnessRestored.mdf
mssql/data/FitnessRestored_log.ldf
```

## Restore SQL

Created:

```text
sql/01_restore_database.sql
```

Restore command:

```sql
RESTORE DATABASE [FitnessRestored]
FROM DISK = N'/backup/Fitnes.bak'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'/var/opt/mssql/data/FitnessRestored.mdf',
    MOVE N'Fitness_log' TO N'/var/opt/mssql/data/FitnessRestored_log.ldf',
    RECOVERY,
    STATS = 5;
GO
```

## Restore execution

Executed through:

```bash
scripts/sqlcmd.sh -b -i /sql/01_restore_database.sql
```

Logs:

```text
logs/restore.log
logs/restore.exit
logs/restore_started_at.txt
logs/restore_finished_at.txt
```

Timing:

```text
started: 2026-05-07T14:35:50+03:00
finished: 2026-05-07T14:37:51+03:00
sql restore duration: 117.362 seconds
exit code: 0
```

Restore output summary:

```text
Processed 6805680 pages for database 'FitnessRestored', file 'Fitness' on file 1.
Processed 4 pages for database 'FitnessRestored', file 'Fitness_log' on file 1.
Converting database 'FitnessRestored' from version 852 to the current version 921.
RESTORE DATABASE successfully processed 6805684 pages in 117.362 seconds (453.037 MB/sec).
```

## Post-restore checks

Created:

```text
sql/02_post_restore_checks.sql
```

Executed through:

```bash
scripts/sqlcmd.sh -b -i /sql/02_post_restore_checks.sql
```

Logs:

```text
logs/post_restore_checks.txt
logs/post_restore_checks.exit
```

Results:

```text
database: FitnessRestored
state_desc: ONLINE
recovery_model_desc: SIMPLE
compatibility_level: 130
user_tables_count: 2503
post_restore_checks exit code: 0
```

Files:

| Logical name | Type | Size MB | Container path | Host path |
|---|---:|---:|---|---|
| `Fitness` | ROWS | `76680.000000` | `/var/opt/mssql/data/FitnessRestored.mdf` | `mssql/data/FitnessRestored.mdf` |
| `Fitness_log` | LOG | `3528.000000` | `/var/opt/mssql/data/FitnessRestored_log.ldf` | `mssql/data/FitnessRestored_log.ldf` |

Host file sizes:

```text
mssql/data/FitnessRestored.mdf: 75G
mssql/data/FitnessRestored_log.ldf: 3.5G
```

Disk after restore:

```text
filesystem: /dev/vda1
used: about 98G
available: about 96G
mssql/: about 79G
```

## Decision

Step 8 passed.

`FitnessRestored` is restored and online. Full `DBCC CHECKDB` was not run,
following the plan restriction to avoid an expensive first-step integrity check.

Allowed next action:

```text
Proceed with post-restore/schema inventory work.
```
