# Execution Log: step 9 post-restore access check

Date: 2026-05-07
Workspace: `/root/workspace/1c-fitness`
Plan step: `## 9. Проверить, что база восстановилась и доступна`

## Runtime

```text
container: mssql-fitness
image: mcr.microsoft.com/azure-sql-edge:latest
port: 127.0.0.1:1433
database: FitnessRestored
```

## Canonical post-restore check

Re-used and re-ran:

```text
sql/02_post_restore_checks.sql
```

Logs:

```text
logs/post_restore_checks.txt
logs/post_restore_checks.exit
logs/step09_post_restore_checks.txt
logs/step09_post_restore_checks.exit
```

Exit code:

```text
0
```

Results:

```text
database: FitnessRestored
state_desc: ONLINE
recovery_model_desc: SIMPLE
compatibility_level: 130
create_date: 2026-05-07 11:35:51.643 UTC
user_tables_count: 2503
```

Database files according to `sys.master_files`:

| Logical name | Type | Size MB | Physical path |
|---|---:|---:|---|
| `Fitness` | ROWS | `76680.000000` | `/var/opt/mssql/data/FitnessRestored.mdf` |
| `Fitness_log` | LOG | `3528.000000` | `/var/opt/mssql/data/FitnessRestored_log.ldf` |

## Access smoke-check

Created and ran:

```text
sql/09_access_smoke_check.sql
```

Logs:

```text
logs/step09_access_smoke_check.txt
logs/step09_access_smoke_check.exit
```

Exit code:

```text
0
```

Access results:

```text
user_tables_count: 2503
user_columns_count: 19421
```

1C-like table pattern counts:

```text
Config table present: 1
_Reference tables: 427
_Document tables: 208
_InfoRg tables: 596
_AccumRg tables: 193
_Enum tables: 240
```

Top tables by approximate row count are readable. Largest observed tables:

| Table | Approx rows |
|---|---:|
| `dbo._InfoRg2567` | `19,791,206` |
| `dbo._AccRgED4729` | `8,363,806` |
| `dbo._AccumRg3336` | `7,236,853` |
| `dbo._AccumRgT3353` | `6,490,567` |
| `dbo._Document150` | `3,012,966` |

## Disk state

```text
filesystem: /dev/vda1
used: about 98G
available: about 96G
mssql/: about 79G
data/Fitnes.bak: 12G
```

## Decision

Step 9 passed.

The restored database is online, accessible, and contains expected 1C-style
tables. Full `DBCC CHECKDB` was not run, following the plan restriction.

Allowed next action:

```text
Proceed to schema inventory.
```
