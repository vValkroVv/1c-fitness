##описание задачи##
Нам нужно перевести данные из формата backup microsoft sql и xlsx файл вороки, важно делать максмально четко по инструкции, все непонятные моменты записывать в промежуточные файлы, вести логирование

##основная инструкция##
task-desc/fitness_updated_restore_to_fitbase_plan.md (в иснтрукции пути с другого сервера, сейчас наш репозиторий это /root/workspace/1c-fitness, основной .bak файл data/Fitnes.bak), сохраняй все в /root/workspace/1c-fitness по папкам как я прошу

##во время выполения##
Заведи папку docs, если она еще не создана и там логируй все по md файлам (разделях их на работу с самим файлом, бизнесовые комментарии, и тд), чтобы весь процесс был задокументирован

##итоговая цель##
Итоговая цель сделай воспроизводимый пайплайн, который по .bak файлу сформирует нам два xlsx файла с указанными требованиями

##итоговые файлы##
Скрипты обрабаотки установки создавай в папке scripts, а итоговый файлы xlsx в output (более детально посмотри в файле task-desc/fitness_updated_restore_to_fitbase_plan.md, там все раписано)

##текущее sql окружение##
На текущем сервере ARM64 поднят SQL-compatible runtime для работы с backup:

```text
container: mssql-fitness
image: mcr.microsoft.com/azure-sql-edge:latest
version: Microsoft Azure SQL Edge Developer 15.0.2000.1574 (ARM64)
port: 127.0.0.1:1433
backup внутри контейнера: /backup/Fitnes.bak
persistent SQL data: mssql/
runtime env/password: tmp/mssql-fitness.env
```

Важно: это Azure SQL Edge ARM64, а не полный SQL Server 2022 Developer. Он выбран под текущее окружение сервера. Перед полным restore обязательно проверить backup через `RESTORE HEADERONLY`, `RESTORE FILELISTONLY`, `RESTORE VERIFYONLY`.

Как пользоваться:

```bash
# проверить, что контейнер работает
docker ps --filter name=mssql-fitness

# запустить контейнер, если он удален/не создан
scripts/06_start_mssql_container.sh

# выполнить SQL-запрос
scripts/sqlcmd.sh -Q "SELECT @@VERSION AS version"

# выполнить SQL-файл
scripts/sqlcmd.sh -i /sql/имя_файла.sql

# посмотреть логи контейнера
docker logs mssql-fitness --tail 200
```

`scripts/sqlcmd.sh` запускает `mssql-tools` отдельным tools-контейнером и подключается к `127.0.0.1:1433`. Папки `mssql/`, `tmp/`, `logs/` служебные; не коммитить runtime data и секреты.

Текущий статус backup-проверки:

```text
RESTORE HEADERONLY: success, logs/restore_headeronly.txt
RESTORE FILELISTONLY: success, logs/restore_filelistonly.txt
RESTORE VERIFYONLY: success, logs/restore_verifyonly.txt
VERIFYONLY result: The backup set on file 1 is valid.
step 7 report: docs/step_07_pre_restore_sql_checks.md
RESTORE DATABASE FitnessRestored: success, logs/restore.log
post-restore check: FitnessRestored ONLINE, 2503 user tables, logs/post_restore_checks.txt
step 8 report: docs/step_08_restore_database.md
step 9 access check: success, FitnessRestored ONLINE, 2503 tables, 19421 columns, docs/step_09_post_restore_access_check.md
step 10 schema inventory: success, output/schema_inventory.csv, output/schema_tables.csv, logs/schema_inventory.txt, docs/step_10_schema_inventory.md
```

##github##
Чтобы пушить в репозиторий используй токен из .env
