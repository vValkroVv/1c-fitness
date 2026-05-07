# Результат проверки формата `Fitnes.bak`

Проверка выполнена 2026-05-04 по плану `task-desc/fitness_safe_format_probe_plan.md`.

## Итоговый вывод

`/home/linuxadmin/Fitnes.bak` — это **Microsoft SQL Server backup**.

Главное доказательство: первые 8 bytes файла — ASCII-сигнатура `MSSQLBAK`.

```text
magic16= 4d 53 53 51 4c 42 41 4b 02 00 00 00 03 00 00 00
ASCII:    M  S  S  Q  L  B  A  K
```

Обычная команда `file` показывает только `data`, но для SQL Server `.bak` это нормально: стандартный `file` не всегда распознает такой backup.

## Где лежат артефакты проверки на сервере

```text
/home/linuxadmin/fitnes_probe_20260504_184740/
```

Главные файлы:

```text
/home/linuxadmin/fitnes_probe_20260504_184740/logs/session.log
/home/linuxadmin/fitnes_probe_20260504_184740/results/probe_report.md
/home/linuxadmin/fitnes_probe_20260504_184740/results/final_classification.txt
/home/linuxadmin/fitnes_probe_20260504_184740/results/deeper_strings_probe.txt
/home/linuxadmin/fitnes_probe_20260504_184740/samples/head_64MiB.bin
/home/linuxadmin/fitnes_probe_20260504_184740/samples/tail_64MiB.bin
```

Папка диагностики занимает около `129M`, в рамках безопасного лимита.

## Что проверено

- Файл стабилен: размер и `mtime` не менялись во время 60-секундной проверки.
- `lsof` / `fuser` не показали открытых процессов на файле.
- Размер файла: `12,770,610,688` bytes, то есть около `11.9 GiB` / `12.8 GB`.
- RAM: около `30 GiB`, доступно около `29 GiB`.
- Свободно на `/home`: около `23G`.
- Созданы только два сэмпла по `64 MiB`: начало и конец файла.
- Полная распаковка, восстановление и копирование всего файла не выполнялись.

## Что это не является

- Не ZIP: `unzip -l` завершился с ошибкой `End-of-central-directory signature not found`.
- Не TAR: `tar -tf` завершился с ошибкой `This does not look like a tar archive`.
- `7z` на сервере не установлен, но сигнатура `MSSQLBAK` уже определяет SQL Server backup.
- `pg_restore` на сервере не установлен; признака `PGDMP` в magic bytes нет.
- 1C-платформа на сервере не найдена.

## Ограничение текущей проверки

На сервере не установлен `sqlcmd` и не найден SQL Server:

```text
sqlcmd not found
mssql services: not found
mssql dirs: not found
```

Поэтому команды `RESTORE HEADERONLY` и `RESTORE FILELISTONLY` на этом сервере выполнить нельзя без установки SQL Server tools / SQL Server и без учетных данных SQL Server.

## Как работать дальше

Дальше нужен именно путь SQL Server:

1. Подготовить SQL Server среду, лучше не на текущем `/home`.
2. Выполнить:

```sql
RESTORE HEADERONLY FROM DISK = N'/path/to/Fitnes.bak';
RESTORE FILELISTONLY FROM DISK = N'/path/to/Fitnes.bak';
```

3. По `FILELISTONLY` посчитать сумму размеров data/log files и понять реальный размер восстановления.
4. Не восстанавливать на текущий `/home`: сейчас там свободно около `23G`, а backup `12G` может разворачиваться существенно больше.
5. Для безопасной работы подготовить отдельный диск/volume. До `FILELISTONLY` разумно закладывать минимум `150-250G`, если ожидается база порядка `100G`.
6. Восстанавливать только в тестовую базу, например `Fitnes_probe`, не в production.
7. После восстановления искать структуру 1C в SQL Server: таблицы вида `_Reference...`, `_Document...`, `_InfoRg...`, `_AccumRg...`, `_Enum...`.
8. Выгрузку в XLSX делать батчами/стримингом, не загружая всю базу в RAM.

## Коротко

Файл `Fitnes.bak` — это SQL Server backup. Для дальнейшей работы нужен SQL Server restore workflow: сначала `HEADERONLY` / `FILELISTONLY`, потом восстановление в тестовую базу на отдельном диске с достаточным запасом места.
