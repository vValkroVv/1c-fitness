# Step 21: restore backup 2026-05-23

Run date: `2026-05-24`

## Goal

Validate and restore the new backup:

```text
data/Fitnes-23-05-26.bak
```

Target database:

```text
FitnessRestored_20260523
```

## Runtime

The current host is `x86_64`, so the SQL container was started with:

```text
container: mssql-fitness
image: mcr.microsoft.com/mssql/server:2022-latest
version: Microsoft SQL Server 2022 Developer 16.0.4255.1
port: 127.0.0.1:1433
```

Docker and `python3-openpyxl` were installed on this host before the run because
they were not present in the fresh environment.

## Backup file

```text
path: data/Fitnes-23-05-26.bak
size_bytes: 12909315072
sha256: 0964142666cd98da0cd1d72340e8399e329d348a44ccefa0033f2fbf2933f191
```

## Pre-restore checks

Created SQL files:

```text
sql/21_restore_headeronly_20260523.sql
sql/21_restore_filelistonly_20260523.sql
sql/21_restore_verifyonly_20260523.sql
```

Logs:

```text
logs/restore_headeronly_20260523.txt
logs/restore_filelistonly_20260523.txt
logs/restore_verifyonly_20260523.txt
```

HEADERONLY key fields:

```text
DatabaseName: Fitness
BackupStartDate: 2026-05-23 23:16:00
BackupFinishDate: 2026-05-23 23:17:17
DatabaseVersion: 852
CompatibilityLevel: 130
CompressedBackupSize: 12909320329
```

FILELISTONLY logical names:

```text
Fitness
Fitness_log
```

VERIFYONLY result:

```text
The backup set on file 1 is valid.
```

## Restore

Created restore SQL:

```text
sql/21_restore_database_20260523.sql
```

Started and finished:

```text
started_at: 2026-05-24T14:52:43+03:00
finished_at: 2026-05-24T14:54:45+03:00
```

Restore log:

```text
logs/restore_20260523.log
```

Restore summary:

```text
RESTORE DATABASE successfully processed 6890046 pages in 119.723 seconds.
```

## Post-restore check

Log:

```text
logs/post_restore_checks_20260523.txt
```

Result:

```text
database: FitnessRestored_20260523
state_desc: ONLINE
recovery_model_desc: SIMPLE
compatibility_level: 130
user_tables: 2503
user_columns: 19421
```
