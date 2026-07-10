# Какой backup нужен и что проверить после restore

`run_pipeline.py` начинает работу с уже восстановленной базы. Он не запускает
SQL Server и не делает `RESTORE DATABASE`. Я не стал автоматизировать этот
кусок: у всех сред разные пути к backup, MDF и LDF, а универсальный restore в
такой ситуации обычно только мешает.

Восстановить базу можно как удобно: через SSMS, обычный T-SQL, Docker или
отдельный SQL-сервер. Дальше пайплайну нужны только адрес, порт, имя базы и
SQL-логин.

## Проверяем, что backup тот самый

```text
file name: Fitnes-30-06-26.bak
size:      13137564672 bytes
sha256:    7e684086442f0eeac44014b9f5170da5c2873620c57788dbc59f58efed1d0810
```

Проверка из корня проекта:

```shell
python scripts/verify_backup.py /путь/к/Fitnes-30-06-26.bak
```

Если размер или SHA-256 не совпал, дальше идти не надо. Это другой файл или
незавершённая загрузка.

## Что записано в backup

Эти значения получили через `RESTORE HEADERONLY` и `RESTORE FILELISTONLY`:

```text
DatabaseName: Fitness
DatabaseVersion: 852
CompatibilityLevel: 130
BackupStartDate:  2026-06-30 23:25:54
BackupFinishDate: 2026-06-30 23:27:03
Logical data file: Fitness
Logical log file:  Fitness_log
Data file size: 80404807680 bytes
Log file size:   3699376128 bytes
Collation: Cyrillic_General_CI_AS
Recovery model: SIMPLE
HasBackupChecksums: 0
```

У этого backup нет встроенных checksums. Поэтому `RESTORE VERIFYONLY` нужно
выполнять без `WITH CHECKSUM`.

## Проверки перед restore

`<BACKUP_PATH_VISIBLE_TO_SQL_SERVER>` означает путь внутри среды SQL Server.
Например, для контейнера это путь внутри контейнера, а не путь на хосте.

```sql
RESTORE HEADERONLY
FROM DISK = N'<BACKUP_PATH_VISIBLE_TO_SQL_SERVER>';

RESTORE FILELISTONLY
FROM DISK = N'<BACKUP_PATH_VISIBLE_TO_SQL_SERVER>'
WITH FILE = 1;

RESTORE VERIFYONLY
FROM DISK = N'<BACKUP_PATH_VISIBLE_TO_SQL_SERVER>'
WITH FILE = 1;
```

В результате должна быть одна полная копия базы `Fitness`. Logical names:
`Fitness` и `Fitness_log`. `VERIFYONLY` должен закончиться без ошибок.

## Шаблон команды restore

Команда ниже специально оставлена с placeholders. Подставьте пути, которые
подходят вашему SQL Server.

```sql
RESTORE DATABASE [FitnessRestored]
FROM DISK = N'<BACKUP_PATH_VISIBLE_TO_SQL_SERVER>'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'<TARGET_DATA_FILE_PATH>',
    MOVE N'Fitness_log' TO N'<TARGET_LOG_FILE_PATH>',
    RECOVERY,
    STATS = 5;
```

## Что проверить после restore

```sql
SELECT
    DB_NAME() AS database_name,
    d.state_desc,
    d.compatibility_level,
    COUNT(t.object_id) AS dbo_user_tables
FROM sys.databases AS d
JOIN sys.tables AS t ON t.is_ms_shipped = 0
JOIN sys.schemas AS s ON s.schema_id = t.schema_id AND s.name = N'dbo'
WHERE d.name = DB_NAME()
GROUP BY d.state_desc, d.compatibility_level;
```

Для проверенной копии результат такой:

```text
state_desc: ONLINE
compatibility_level: 130
dbo source tables: 2503
```

Необязательно выполнять эту проверку вручную. Этап `preflight` повторит её и
заодно проверит все 17 таблиц 1С, которые используются в SQL.

## Сколько нужно места

После restore MDF и LDF занимают около 78,3 GiB. SQL Server Express здесь не
подойдёт. Для backup, файлов базы и рабочего запаса лучше выделить хотя бы
120 GiB свободного места.

Сам пайплайн пишет примерно 1,3 GiB промежуточных CSV и TSV. Под них стоит
оставить ещё 2-3 ГБ.

## Права SQL-логина

Логину нужны:

- `CONNECT` к восстановленной базе;
- `SELECT` на таблицы `dbo`, которые читает пайплайн;
- право создать схему `fitbase_part2`, если её пока нет;
- `CREATE TABLE`, `ALTER`, `DROP` и `SELECT` внутри `fitbase_part2`.

Исходные таблицы `dbo` скрипты не меняют. Они пересоздают только служебные
таблицы `fitbase_part2`.
