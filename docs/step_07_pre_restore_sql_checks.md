# Execution Log: step 7 pre-restore SQL checks

Date: 2026-05-07
Workspace: `/root/workspace/1c-fitness`
Plan step: `## 7. Повторная SQL-проверка перед восстановлением`

## Runtime

Checks were executed against the currently running SQL-compatible runtime:

```text
container: mssql-fitness
image: mcr.microsoft.com/azure-sql-edge:latest
version: Microsoft Azure SQL Edge Developer 15.0.2000.1574 (ARM64)
port: 127.0.0.1:1433
backup path in container: /backup/Fitnes.bak
```

`/backup/Fitnes.bak` is mounted read-only from repository path `data/Fitnes.bak`.

## SQL files created

```text
sql/07_restore_headeronly.sql
sql/07_restore_filelistonly.sql
sql/07_restore_verifyonly.sql
```

They are executed through:

```bash
scripts/sqlcmd.sh -i /sql/07_restore_headeronly.sql
scripts/sqlcmd.sh -i /sql/07_restore_filelistonly.sql
scripts/sqlcmd.sh -i /sql/07_restore_verifyonly.sql
```

## Raw logs

```text
logs/restore_headeronly.txt
logs/restore_headeronly.exit
logs/restore_filelistonly.txt
logs/restore_filelistonly.exit
logs/restore_verifyonly.txt
logs/restore_verifyonly.exit
```

Exit codes:

```text
HEADERONLY: 0
FILELISTONLY: 0
VERIFYONLY: 0
```

## RESTORE HEADERONLY result

Key values:

```text
DatabaseName: Fitness
BackupTypeDescription: Database
FILE position: 1
Compressed: 1
HasBackupChecksums: 1
DatabaseVersion: 852
CompatibilityLevel: 130
SoftwareVersion: 13.0.5108
BackupStartDate: 2026-04-29 23:55:53.000
BackupFinishDate: 2026-04-29 23:57:02.000
RecoveryModel: SIMPLE
Collation: Cyrillic_General_CI_AS
CompressedBackupSize: 12770616429
KeyAlgorithm: NULL
EncryptorThumbprint: NULL
EncryptorType: NULL
```

Interpretation:

```text
Backup metadata is readable on the current SQL runtime.
The backup set is a SQL Server database backup for database Fitness.
No TDE/encryption metadata was reported.
```

## RESTORE FILELISTONLY result

Files inside backup:

| LogicalName | PhysicalName | Type | Size bytes | Size GiB |
|---|---|---:|---:|---:|
| `Fitness` | `D:\SQLDATA\Fitness.mdf` | D | `80,404,807,680` | `74.88` |
| `Fitness_log` | `D:\SQLDATA\Fitness_log.ldf` | L | `3,699,376,128` | `3.45` |

Estimated restore size:

```text
84,104,183,808 bytes
78.33 GiB
```

`TDEThumbprint` is `NULL` for both files.

## RESTORE VERIFYONLY result

Output:

```text
The backup set on file 1 is valid.
```

Interpretation:

```text
The current SQL runtime can read and validate the backup set.
This satisfies the pre-restore verification gate.
```

## Disk state after checks

```text
filesystem: /dev/vda1
available: about 174G
mssql runtime data: about 72M
backup: 12G
```

## Decision

Step 7 passed.

Allowed next action:

```text
Proceed to restore with WITH MOVE into repository-local persistent volume mssql/.
```

Important: full `RESTORE DATABASE` has not been run yet. The restore SQL must
move Windows source paths to Linux container paths, for example:

```text
Fitness     -> /var/opt/mssql/data/FitnessRestored.mdf
Fitness_log -> /var/opt/mssql/data/FitnessRestored_log.ldf
```
