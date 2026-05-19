# Part 2 restore and select check

Date: 2026-05-19
Workspace: `/root/workspace/1c-fitness`

## Runtime

The local workspace did not have Docker installed initially, so Docker was
installed and the existing SQL container workflow was used.

```text
container: mssql-fitness
image: mcr.microsoft.com/mssql/server:2022-latest
port: 127.0.0.1:1433
database: FitnessRestored
backup: data/Fitnes.bak
```

## Backup preflight

Re-ran the same pre-restore gates used in the earlier docs:

```text
logs/restore_headeronly.txt       exit 0
logs/restore_filelistonly.txt     exit 0
logs/restore_verifyonly.txt       exit 0
```

`RESTORE VERIFYONLY` result:

```text
The backup set on file 1 is valid.
```

## Restore

Restore SQL:

```text
sql/01_restore_database.sql
```

Timing:

```text
started: 2026-05-19T23:37:08+03:00
finished: 2026-05-19T23:39:09+03:00
exit code: 0
```

Restore output:

```text
Processed 6805680 pages for database 'FitnessRestored', file 'Fitness' on file 1.
Processed 4 pages for database 'FitnessRestored', file 'Fitness_log' on file 1.
Converting database 'FitnessRestored' from version 852 to the current version 957.
RESTORE DATABASE successfully processed 6805684 pages in 119.830 seconds (443.706 MB/sec).
```

Restored files:

```text
mssql/data/FitnessRestored.mdf      75G
mssql/data/FitnessRestored_log.ldf  3.5G
```

## Post-restore checks

Post-restore logs:

```text
logs/post_restore_checks.txt        exit 0
logs/step09_access_smoke_check.txt  exit 0
logs/select_smoke_check.txt         exit 0
```

Database state:

```text
name: FitnessRestored
state_desc: ONLINE
recovery_model_desc: SIMPLE
compatibility_level: 130
user_tables_count: 2503
user_columns_count: 19421
```

1C table pattern counts:

```text
Config table present: 1
_Reference tables: 427
_Document tables: 208
_InfoRg tables: 596
_AccumRg tables: 193
_Enum tables: 240
```

Direct data SELECT smoke check:

```text
dbo._Reference64 client_rows: 72586
SELECT TOP (5) from dbo._Reference64: ok
SELECT TOP (5) from dbo._Document150: ok
SELECT TOP (5) from dbo._AccumRg3305: ok
```

## Decision

Restore is successful. `FitnessRestored` is online and direct SELECT queries
against restored user tables work.
