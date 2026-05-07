# Fitness MSSQL no-restore probe result

## Ключевой вывод

- Тип файла: Microsoft SQL Server database backup (`.bak`), backup set type `Database`.
- SQL Server смог прочитать backup metadata через `RESTORE HEADERONLY`.
- SQL Server смог прочитать список файлов базы через `RESTORE FILELISTONLY`.
- `RESTORE VERIFYONLY`: success.

На текущем этапе восстановление базы НЕ выполнялось.
Backup проверен только на уровне metadata/readability.
Список таблиц и данные клиентов без восстановления базы получить нельзя.

## 1. Backup-файл

- путь: `/home/linuxadmin/Fitnes.bak`
- размер backup-файла: 12770610688 bytes (11.90 GiB)
- дата изменения файла: 2026-04-29 20:57:02.000000000 +0000

## 2. SQL Server metadata

- SQL Server смог прочитать backup header: да
- количество backup sets внутри `.bak`: 1
- выбранный backup set / FILE position: 1
- DatabaseName: `Fitness`
- BackupType: `1`
- BackupTypeDescription: `Database`
- BackupStartDate: `2026-04-29 23:55:53.000`
- BackupFinishDate: `2026-04-29 23:57:02.000`
- DatabaseVersion: `852`
- SQL Server version, которой был создан backup: `13.0.5108`
- SQL Server engine для проверки: `Microsoft SQL Server 2022 (RTM-CU24-GDR) (KB5083252) - 16.0.4250.1 (X64)`
- compressed: да
- encrypted/TDE: нет
- checksum в backup: да

## 3. Оценка размера восстановления

| LogicalName | PhysicalName | Type | Size bytes | Size GiB |
|---|---|---:|---:|---:|
| Fitness | D:\SQLDATA\Fitness.mdf | D | 80404807680 | 74.88 |
| Fitness_log | D:\SQLDATA\Fitness_log.ldf | L | 3699376128 | 3.45 |

- сумма data files: 80404807680 bytes (74.88 GiB)
- сумма log files: 3699376128 bytes (3.45 GiB)
- общий estimated restore size: 84104183808 bytes (78.33 GiB)
- минимальный рекомендуемый объем отдельного restore-volume: 97.91 GiB (оценка: restore size * 1.25)
- свободно на текущем `/home`: 22 GiB

## 4. Проверка читаемости

- RESTORE VERIFYONLY выполнен: да
- результат: success
- exit code: `0`

Вывод команды:

```text
The backup set on file 1 is valid.
```

## 5. Решение

- можно ли восстанавливать на текущий `/home`: нет
- можно ли проверять таблицы без restore: нет
- что нужно для проверки таблиц: отдельный диск/volume + тестовый `RESTORE DATABASE`
- следующий шаг: подготовить volume нужного размера или запросить у заказчика SQL Server/1C-выгрузку в читаемом формате

## 6. Артефакты

- итоговый отчет на сервере: `/home/linuxadmin/fitnes_mssql_probe_20260504_201241_lxd/results/final_report.md`
- рабочая папка на сервере: `/home/linuxadmin/fitnes_mssql_probe_20260504_201241_lxd`
- локальная копия артефактов: `inspection-data-base/fitnes_mssql_probe_20260504_201241_lxd`
- raw output: `results/20_restore_headeronly.txt`
- raw output: `results/22_restore_filelistonly.txt`
- raw output: `results/23_restore_verifyonly.txt`
- логи: `logs/session.log`, `logs/lxd_inner.log`

## 7. Ограничение

`RESTORE DATABASE` не выполнялся. Таблицы, схема 1C и клиентские данные на этом этапе не извлекались.
