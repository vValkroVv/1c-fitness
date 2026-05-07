# План безопасной проверки `Fitnes.bak` через SQL Server без восстановления базы

## 0. Финальный вывод, на котором строим план

`/home/linuxadmin/Fitnes.bak` уже определен как **Microsoft SQL Server backup** по сигнатуре `MSSQLBAK`.

Текущий сервер подходит для **проверки metadata backup-файла**, но не подходит для восстановления базы на текущий `/home`: файл backup занимает около `12.8 GB`, свободно на `/home` около `23G`, а восстановленная база может быть существенно больше backup-файла.

Главное ограничение: **таблицы внутри базы нельзя надежно посмотреть без `RESTORE DATABASE`**. До восстановления SQL Server может показать только metadata backup-файла: заголовки backup set, список файлов базы внутри backup, примерный размер восстановления и результат проверки читаемости backup.

Поэтому безопасный следующий этап делится на две части:

1. **Обязательная часть без restore** — проверить backup средствами SQL Server: `RESTORE HEADERONLY`, `RESTORE FILELISTONLY`, `RESTORE VERIFYONLY`.
2. **Отложенная часть только после отдельного диска/volume** — восстановить тестовую базу и уже тогда проверить таблицы, структуру 1C и готовность к выгрузке.

---

## 1. Финальный результат, который нужно получить на этом этапе

После выполнения плана должен появиться отчет:

```text
/home/linuxadmin/fitnes_mssql_probe_YYYYMMDD_HHMMSS/results/final_report.md
```

В этом отчете должны быть четко заполнены такие поля:

```text
1. Backup-файл:
   - путь: /home/linuxadmin/Fitnes.bak
   - размер backup-файла
   - дата изменения файла

2. SQL Server metadata:
   - SQL Server смог прочитать backup header: да/нет
   - количество backup sets внутри .bak
   - выбранный backup set / FILE position
   - DatabaseName
   - BackupType / BackupTypeDescription
   - BackupStartDate / BackupFinishDate
   - SQL Server version, которой был создан backup
   - compressed: да/нет
   - encrypted/TDE: да/нет/непонятно
   - checksum в backup: да/нет/непонятно

3. Оценка размера восстановления:
   - список LogicalName / PhysicalName / Type / Size
   - сумма data files, GiB
   - сумма log files, GiB
   - общий estimated restore size, GiB
   - минимальный рекомендуемый объем отдельного restore-volume

4. Проверка читаемости:
   - RESTORE VERIFYONLY выполнен: да/нет
   - результат: success/error
   - если error — точный текст ошибки
   - если error только про нехватку места назначения — отдельно пометить, что это не равно повреждению backup

5. Решение:
   - можно ли восстанавливать на текущий /home: да/нет
   - можно ли проверять таблицы без restore: нет
   - что нужно для проверки таблиц: отдельный диск/volume + тестовый RESTORE DATABASE
   - следующий шаг: подготовить volume нужного размера или запросить у заказчика SQL Server/1C-выгрузку в читаемом формате
```

Ключевая формулировка в финальном отчете:

```text
На текущем этапе восстановление базы НЕ выполнялось.
Backup проверен только на уровне metadata/readability.
Список таблиц и данные клиентов без восстановления базы получить нельзя.
```

---

## 2. Что категорически не делаем на текущем `/home`

Не выполнять:

```sql
RESTORE DATABASE ...
```

Не выполнять:

```bash
cp /home/linuxadmin/Fitnes.bak ...
sha256sum /home/linuxadmin/Fitnes.bak
7z x /home/linuxadmin/Fitnes.bak
unzip /home/linuxadmin/Fitnes.bak
```

Почему:

- `RESTORE DATABASE` может создать `.mdf/.ndf/.ldf` существенно больше 12 GB.
- Полное копирование backup-файла съест еще 12.8 GB и почти исчерпает текущий `/home`.
- Архиваторы не нужны: это не ZIP/TAR, а SQL Server backup.
- Полный hash необязателен: он безопасен по записи, но читает весь файл 12.8 GB и не дает нужной SQL Server metadata.

---

## 3. Что можно проверить без восстановления

### 3.1. `RESTORE HEADERONLY`

Показывает заголовки backup sets внутри `.bak`.

Нужно получить:

- `DatabaseName`
- `BackupType` / `BackupTypeDescription`
- `Position`, то есть номер backup set внутри файла
- `BackupStartDate`
- `BackupFinishDate`
- `DatabaseVersion`
- `SoftwareVersionMajor/Minor/Build`
- `Compressed`
- признаки encryption/TDE, если есть в result set
- признаки checksum, если есть в result set

### 3.2. `RESTORE FILELISTONLY`

Показывает список database/log files внутри выбранного backup set.

Нужно получить:

- `LogicalName`
- `PhysicalName`
- `Type`: `D` = data file, `L` = log file
- `Size`
- `BackupSizeInBytes`, если доступно

По `Size` считаем estimated restore size.

### 3.3. `RESTORE VERIFYONLY`

Проверяет, что backup set полный и читаемый. Команда **не восстанавливает базу**, но читает backup и может занять время за счет I/O.

Важно: `VERIFYONLY` не доказывает логическую целостность таблиц и не показывает таблицы. Он проверяет backup на уровне читаемости backup set.

---

## 4. Почему нужен SQL Server engine, а не просто Python-библиотека

`.bak` — это SQL Server backup media. Его корректно интерпретирует SQL Server Database Engine.

`sqlcmd` сам по себе — только клиентская утилита для отправки запросов в SQL Server. Поэтому установка только `sqlcmd` недостаточна: нужен запущенный SQL Server instance, хотя бы временный container.

На текущем сервере ранее было зафиксировано:

```text
sqlcmd not found
mssql services: not found
mssql dirs: not found
```

Поэтому безопасный вариант — поднять временный SQL Server container только для metadata-команд, без проброса порта наружу и без `RESTORE DATABASE`.

---

## 5. Подготовка рабочей папки

```bash
set -euo pipefail

BAK='/home/linuxadmin/Fitnes.bak'
TS="$(date +%Y%m%d_%H%M%S)"
WORK="/home/linuxadmin/fitnes_mssql_probe_${TS}"

mkdir -p "$WORK"/{logs,results,queries,tmp}
exec > >(tee -a "$WORK/logs/session.log") 2>&1

echo "WORK=$WORK"
date -Is
```

Сразу зафиксировать состояние файла и сервера:

```bash
stat "$BAK" | tee "$WORK/results/00_stat.txt"
df -h /home / /tmp | tee "$WORK/results/00_df.txt"
free -h | tee "$WORK/results/00_free.txt"
lsblk -f | tee "$WORK/results/00_lsblk.txt"
```

Проверить, что backup не меняется прямо сейчас:

```bash
stat -c '%s %Y' "$BAK" | tee "$WORK/tmp/stat_before.txt"
sleep 60
stat -c '%s %Y' "$BAK" | tee "$WORK/tmp/stat_after.txt"

diff -u "$WORK/tmp/stat_before.txt" "$WORK/tmp/stat_after.txt" \
  && echo 'OK: file is stable for 60 seconds' \
  || { echo 'STOP: Fitnes.bak changed during check'; exit 1; }
```

Проверить, что файл не открыт процессами:

```bash
lsof "$BAK" 2>&1 | tee "$WORK/results/00_lsof.txt" || true
fuser -v "$BAK" 2>&1 | tee "$WORK/results/00_fuser.txt" || true
```

---

## 6. Проверка свободного места перед установкой Docker/SQL Server image

Нужно оставить запас на систему. Для metadata-проверки restore не выполняется, но Docker image и writable layer SQL Server все равно займут место.

Минимальный guard:

```bash
FREE_GIB=$(df -BG --output=avail /home | tail -1 | tr -dc '0-9')
echo "FREE_GIB_ON_HOME=$FREE_GIB" | tee "$WORK/results/00_free_gib.txt"

if [ "$FREE_GIB" -lt 10 ]; then
  echo 'STOP: свободного места меньше 10G, даже metadata-проверку через container лучше не начинать'
  exit 1
fi
```

На текущем сервере ожидаемо около `23G` свободно. Этого должно хватить на Docker/SQL Server image и metadata-проверку, но **не на restore**.

---

## 7. Установка Docker, если его нет

Проверить:

```bash
command -v docker && docker --version || echo 'docker not installed'
```

Если Docker не установлен:

```bash
sudo apt-get update
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo docker info | tee "$WORK/results/00_docker_info.txt"
```

После установки еще раз проверить свободное место:

```bash
df -h /home / | tee "$WORK/results/00_df_after_docker.txt"
```

Если стало меньше `10G` свободно — остановиться.

---

## 8. Запуск временного SQL Server container только для metadata

Использовать SQL Server 2022 Developer container как первый вариант. Если `HEADERONLY` скажет, что backup создан более новой версией SQL Server и не поддерживается, тогда повторить с `mcr.microsoft.com/mssql/server:2025-latest`.

Создать пароль без вывода в общий лог:

```bash
SA_PASSWORD="$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-24)Aa1!"
printf '%s\n' "$SA_PASSWORD" > "$WORK/tmp/sa_password.txt"
chmod 600 "$WORK/tmp/sa_password.txt"
```

Запустить container:

```bash
CONTAINER='fitnes_mssql_probe'

sudo docker rm -f "$CONTAINER" 2>/dev/null || true

sudo docker pull mcr.microsoft.com/mssql/server:2022-latest

sudo docker run \
  --name "$CONTAINER" \
  --hostname fitnes-mssql-probe \
  --memory=6g \
  --memory-swap=6g \
  --cpus=2 \
  --network none \
  -e ACCEPT_EULA=Y \
  -e MSSQL_PID=Developer \
  -e MSSQL_SA_PASSWORD="$SA_PASSWORD" \
  -e MSSQL_MEMORY_LIMIT_MB=4096 \
  --mount type=bind,src="$BAK",dst=/var/backups/Fitnes.bak,readonly \
  -d mcr.microsoft.com/mssql/server:2022-latest
```

Пояснения:

- `--network none` — SQL Server не публикуется наружу.
- Нет `-p 1433:1433` — порт не проброшен на сервер.
- `.bak` смонтирован read-only.
- `--memory` и `MSSQL_MEMORY_LIMIT_MB` ограничивают потребление RAM.
- Никакая база из backup не восстанавливается.

Подождать готовность SQL Server:

```bash
for i in $(seq 1 60); do
  if sudo docker exec -e SA_PASSWORD="$SA_PASSWORD" "$CONTAINER" bash -lc '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi
    "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT @@VERSION" >/tmp/sql_ready.txt 2>&1
  '; then
    echo 'SQL Server is ready'
    sudo docker exec "$CONTAINER" cat /tmp/sql_ready.txt | tee "$WORK/results/00_sql_version.txt"
    break
  fi
  sleep 5
  if [ "$i" -eq 60 ]; then
    echo 'STOP: SQL Server container did not become ready'
    sudo docker logs "$CONTAINER" | tail -200 | tee "$WORK/results/00_container_logs_tail.txt"
    exit 1
  fi
done
```

---

## 9. Выполнение `RESTORE HEADERONLY`

Создать SQL-файл:

```bash
cat > "$WORK/queries/01_headeronly.sql" <<'SQL'
SET NOCOUNT ON;
RESTORE HEADERONLY
FROM DISK = N'/var/backups/Fitnes.bak';
GO
SQL
```

Запустить:

```bash
sudo docker exec \
  -e SA_PASSWORD="$SA_PASSWORD" \
  -i "$CONTAINER" bash -lc '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi
    "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -W -w 65535 -y 0 -Y 0 -s "|" -i /dev/stdin
  ' < "$WORK/queries/01_headeronly.sql" \
  | tee "$WORK/results/01_headeronly.tsv"
```

Что проверить в результате:

```text
Position
DatabaseName
BackupType / BackupTypeDescription
BackupStartDate
BackupFinishDate
ExpirationDate
Compressed
SoftwareVersionMajor
SoftwareVersionMinor
SoftwareVersionBuild
DatabaseVersion
HasBackupChecksums / IsDamaged, если такие колонки есть
EncryptorThumbprint / EncryptorType / KeyAlgorithm, если такие колонки есть
```

Если `HEADERONLY` не читается:

1. Сохранить ошибку в `final_report.md`.
2. Не запускать `FILELISTONLY` и `VERIFYONLY`.
3. Проверить вариант SQL Server 2025 container.
4. Если и SQL Server 2025 не читает — backup либо поврежден, либо не SQL Server backup, либо требует password/encryption material.

---

## 10. Выбор backup set / FILE position

Если `HEADERONLY` вернул одну строку — использовать:

```text
FILE = 1
```

Если строк несколько:

1. Выбрать последнюю по `BackupFinishDate` строку с типом full database backup.
2. Зафиксировать ее `Position`.
3. Использовать этот номер в `RESTORE FILELISTONLY ... WITH FILE = <Position>` и `RESTORE VERIFYONLY ... WITH FILE = <Position>`.

В отчете обязательно написать:

```text
Selected backup set position: <N>
Reason: latest full database backup / only backup set / другое объяснение
```

---

## 11. Выполнение `RESTORE FILELISTONLY`

Задать выбранный номер backup set:

```bash
BACKUP_FILE_POSITION=1
```

Создать SQL-файл:

```bash
cat > "$WORK/queries/02_filelistonly.sql" <<SQL
SET NOCOUNT ON;
RESTORE FILELISTONLY
FROM DISK = N'/var/backups/Fitnes.bak'
WITH FILE = ${BACKUP_FILE_POSITION};
GO
SQL
```

Запустить с заголовками:

```bash
sudo docker exec \
  -e SA_PASSWORD="$SA_PASSWORD" \
  -i "$CONTAINER" bash -lc '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi
    "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -W -w 65535 -y 0 -Y 0 -s "|" -i /dev/stdin
  ' < "$WORK/queries/02_filelistonly.sql" \
  | tee "$WORK/results/02_filelistonly.tsv"
```

Запустить второй раз без заголовков для подсчета размеров:

```bash
sudo docker exec \
  -e SA_PASSWORD="$SA_PASSWORD" \
  -i "$CONTAINER" bash -lc '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi
    "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -h-1 -W -w 65535 -y 0 -Y 0 -s "|" -i /dev/stdin
  ' < "$WORK/queries/02_filelistonly.sql" \
  | tee "$WORK/results/02_filelistonly_noheader.tsv"
```

Посчитать estimated restore size из колонки `Size`. В `FILELISTONLY` порядок первых колонок такой:

```text
1 LogicalName
2 PhysicalName
3 Type
4 FileGroupName
5 Size
```

Команда подсчета:

```bash
awk -F'|' '
  NF >= 5 {
    type=$3; size=$5;
    gsub(/^[ \t]+|[ \t]+$/, "", type);
    gsub(/^[ \t]+|[ \t]+$/, "", size);
    if (size ~ /^[0-9]+$/) {
      total += size;
      if (type == "D") data += size;
      if (type == "L") log += size;
    }
  }
  END {
    gib=1024*1024*1024;
    printf "data_bytes=%0.f\n", data;
    printf "log_bytes=%0.f\n", log;
    printf "total_bytes=%0.f\n", total;
    printf "data_gib=%.2f\n", data/gib;
    printf "log_gib=%.2f\n", log/gib;
    printf "total_restore_gib=%.2f\n", total/gib;
    printf "recommended_volume_gib=%.2f\n", (total/gib*1.3 + 20);
  }
' "$WORK/results/02_filelistonly_noheader.tsv" \
| tee "$WORK/results/02_restore_size_summary.txt"
```

Интерпретация:

```text
total_restore_gib = сколько примерно займут MDF/NDF/LDF после restore
recommended_volume_gib = restore size * 1.3 + 20G технического запаса
```

Если `recommended_volume_gib` больше свободного места на `/home`, восстановление на текущий раздел запрещено.

---

## 12. Выполнение `RESTORE VERIFYONLY`

Запускать только после успешных `HEADERONLY` и `FILELISTONLY`.

Создать SQL-файл:

```bash
cat > "$WORK/queries/03_verifyonly.sql" <<SQL
SET NOCOUNT ON;
RESTORE VERIFYONLY
FROM DISK = N'/var/backups/Fitnes.bak'
WITH FILE = ${BACKUP_FILE_POSITION}, STATS = 10;
GO
SQL
```

Запустить:

```bash
sudo docker exec \
  -e SA_PASSWORD="$SA_PASSWORD" \
  -i "$CONTAINER" bash -lc '
    if [ -x /opt/mssql-tools18/bin/sqlcmd ]; then SQLCMD=/opt/mssql-tools18/bin/sqlcmd; else SQLCMD=/opt/mssql-tools/bin/sqlcmd; fi
    "$SQLCMD" -S localhost -U sa -P "$SA_PASSWORD" -C -W -w 65535 -y 0 -Y 0 -i /dev/stdin
  ' < "$WORK/queries/03_verifyonly.sql" \
  | tee "$WORK/results/03_verifyonly.log"
```

Если в `HEADERONLY` видно, что backup был создан с checksum, можно отдельно выполнить checksum-вариант:

```sql
RESTORE VERIFYONLY
FROM DISK = N'/var/backups/Fitnes.bak'
WITH FILE = <N>, CHECKSUM, STATS = 10;
```

Как трактовать результат:

```text
VERIFYONLY success
=> backup set полный и читаемый SQL Server-движком.
=> это НЕ означает, что таблицы проверены.
=> это НЕ означает, что база восстановлена.

VERIFYONLY error из-за нехватки места назначения
=> это может быть следствием проверки destination devices.
=> это НЕ равно повреждению backup.
=> нужно смотреть точный текст ошибки.

VERIFYONLY error на чтении/checksum/media
=> backup может быть поврежден или требует другой SQL Server version/password/encryption material.
```

---

## 13. Остановка и очистка временного container

После получения metadata:

```bash
sudo docker logs "$CONTAINER" | tail -300 | tee "$WORK/results/99_container_logs_tail.txt" || true
sudo docker rm -f "$CONTAINER" || true
```

Проверить место после очистки:

```bash
df -h /home / | tee "$WORK/results/99_df_after_cleanup.txt"
sudo docker system df | tee "$WORK/results/99_docker_system_df.txt" || true
```

Не удалять рабочую папку `WORK`: там отчет и результаты.

---

## 14. Сборка `final_report.md`

Создать файл:

```bash
cat > "$WORK/results/final_report.md" <<'MD_REPORT'
# Итог проверки Fitnes.bak без восстановления базы

## Короткий вердикт

- Восстановление базы выполнялось: НЕТ
- Backup header прочитан SQL Server: <да/нет>
- File list прочитан SQL Server: <да/нет>
- VerifyOnly выполнен: <да/нет>
- Backup set readable: <да/нет/неизвестно>
- Таблицы проверены: НЕТ
- Почему таблицы не проверены: таблицы доступны только после RESTORE DATABASE в тестовую БД
- Можно восстанавливать на текущий /home: <да/нет>
- Следующий шаг: <подготовить отдельный volume X GiB / запросить другой формат выгрузки / другое>

## Backup file

- Path: /home/linuxadmin/Fitnes.bak
- Size: <bytes/GiB>
- mtime: <timestamp>

## HeaderOnly

Вставить краткую таблицу из 01_headeronly.tsv:

- Position: <N>
- DatabaseName: <name>
- BackupTypeDescription: <type>
- BackupStartDate: <date>
- BackupFinishDate: <date>
- SQL Server version: <version>
- Compressed: <yes/no>
- Encrypted/TDE: <yes/no/unknown>
- Checksum: <yes/no/unknown>

## FileListOnly

- data_gib: <value>
- log_gib: <value>
- total_restore_gib: <value>
- recommended_volume_gib: <value>

Файлы:

```text
LogicalName | Type | SizeGiB | OriginalPhysicalName
...
```

## VerifyOnly

- Status: <success/error/not_run>
- Exact output/error:

```text
<вставить вывод 03_verifyonly.log>
```

## Решение по дальнейшей работе

1. Если `VERIFYONLY success` и `recommended_volume_gib` помещается на отдельный volume:
   - готовить тестовое восстановление `Fitnes_probe` на отдельный диск.
2. Если `VERIFYONLY success`, но места нет:
   - не восстанавливать на текущем сервере;
   - запросить volume минимум `<recommended_volume_gib>` GiB.
3. Если `VERIFYONLY error`:
   - разобрать точную ошибку;
   - при ошибке версии попробовать SQL Server 2025;
   - при encryption/TDE запросить certificate/private key/password;
   - при media/checksum error запросить свежий backup.

## Что НЕ подтверждено на этом этапе

- Список таблиц.
- Наличие таблиц 1C `Config`, `Params`, `DBSchema`.
- Наличие клиентских данных, телефонов, абонементов, броней, пластиковых карт.
- Готовность к выгрузке в XLSX.

Все это проверяется только после тестового восстановления базы.
MD_REPORT
```

Заполнить placeholders вручную по файлам:

```text
01_headeronly.tsv
02_filelistonly.tsv
02_restore_size_summary.txt
03_verifyonly.log
```

---

## 15. Что значит “проверить таблицы” и почему это отдельный этап

Таблицы SQL Server доступны через catalog views, например `sys.tables` и `sys.objects`, только в уже подключенной базе данных. Пока база находится только внутри `.bak`, SQL Server не дает обычный SQL-доступ к таблицам.

Поэтому статус проверки должен быть таким:

```text
Backup metadata checked: да/нет
Backup readable: да/нет
Database restored: нет
Tables inspected: нет
```

Нельзя писать:

```text
База восстановилась
Таблицы найдены
Структура 1C подтверждена
```

пока не выполнен тестовый `RESTORE DATABASE` на отдельный безопасный volume.

---

## 16. Отложенный план проверки таблиц после отдельного volume

Этот раздел **не выполнять на текущем `/home`**. Он нужен, чтобы понимать, какой будет следующий шаг после metadata-проверки.

### 16.1. Условия для restore

Восстанавливать можно только если есть отдельный volume:

```text
/mnt/fitnes_restore
```

Требования:

```text
filesystem: ext4 или XFS
свободный объем: не меньше recommended_volume_gib из FILELISTONLY
лучше: 150–250G, если ожидается восстановленная база около 100G
```

### 16.2. Restore в тестовую базу

Примерно так, после подстановки logical names из `FILELISTONLY`:

```sql
RESTORE DATABASE Fitnes_probe
FROM DISK = N'/var/backups/Fitnes.bak'
WITH FILE = <N>,
     MOVE N'<logical_data_name>' TO N'/mnt/fitnes_restore/Fitnes_probe.mdf',
     MOVE N'<logical_log_name>'  TO N'/mnt/fitnes_restore/Fitnes_probe_log.ldf',
     RECOVERY,
     STATS = 5;
```

Если data files несколько, нужен `MOVE` для каждого `D` file и каждого `L` file.

После восстановления:

```sql
ALTER DATABASE Fitnes_probe SET READ_ONLY WITH ROLLBACK IMMEDIATE;
```

### 16.3. Проверка, что база действительно восстановилась

```sql
SELECT
    name,
    state_desc,
    user_access_desc,
    recovery_model_desc,
    create_date,
    compatibility_level
FROM sys.databases
WHERE name = N'Fitnes_probe';
```

Критерий успеха:

```text
state_desc = ONLINE
```

### 16.4. Проверка физической целостности после restore

Сначала облегченный вариант:

```sql
DBCC CHECKDB(N'Fitnes_probe') WITH PHYSICAL_ONLY, NO_INFOMSGS;
```

Важно: `DBCC CHECKDB` может создавать internal database snapshot/sparse files и потреблять место. Поэтому этот шаг делать только на отдельном volume с запасом.

### 16.5. Проверка, что это 1C-инфобаза

Минимальная проверка обязательных таблиц:

```sql
USE Fitnes_probe;

SELECT name
FROM sys.tables
WHERE name IN (N'Config', N'Params', N'DBSchema', N'v8users', N'_YearOffset')
ORDER BY name;
```

Критерий:

```text
Должны быть как минимум Config, Params, DBSchema.
```

Проверка типичных таблиц 1C:

```sql
USE Fitnes_probe;

SELECT TOP 200
    SCHEMA_NAME(schema_id) AS schema_name,
    name AS table_name
FROM sys.tables
WHERE name LIKE N'[_]Reference%'
   OR name LIKE N'[_]Document%'
   OR name LIKE N'[_]InfoRg%'
   OR name LIKE N'[_]AccumRg%'
   OR name LIKE N'[_]Enum%'
   OR name LIKE N'[_]Consts%'
ORDER BY name;
```

### 16.6. Получить карту таблиц и row counts

```sql
USE Fitnes_probe;

SELECT
    SCHEMA_NAME(t.schema_id) AS schema_name,
    t.name AS table_name,
    SUM(p.rows) AS row_count
FROM sys.tables t
JOIN sys.partitions p
    ON p.object_id = t.object_id
   AND p.index_id IN (0, 1)
GROUP BY
    SCHEMA_NAME(t.schema_id),
    t.name
ORDER BY
    row_count DESC,
    table_name;
```

Сохранить результат в:

```text
results/restored_tables_rowcounts.tsv
```

### 16.7. Получить структуру колонок

```sql
USE Fitnes_probe;

SELECT
    SCHEMA_NAME(t.schema_id) AS schema_name,
    t.name AS table_name,
    c.column_id,
    c.name AS column_name,
    ty.name AS sql_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable
FROM sys.tables t
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.name LIKE N'[_]Reference%'
   OR t.name LIKE N'[_]Document%'
   OR t.name LIKE N'[_]InfoRg%'
   OR t.name LIKE N'[_]AccumRg%'
   OR t.name IN (N'Config', N'Params', N'DBSchema')
ORDER BY
    t.name,
    c.column_id;
```

Сохранить результат в:

```text
results/restored_columns.tsv
```

### 16.8. Финальный результат restore-этапа

После отдельного restore должен появиться отчет:

```text
/home/linuxadmin/fitnes_restore_probe_YYYYMMDD_HHMMSS/results/restored_db_schema_report.md
```

В нем должны быть ответы:

```text
- База Fitnes_probe восстановлена: да/нет
- state_desc: ONLINE/другое
- DBCC CHECKDB PHYSICAL_ONLY: success/error/not_run
- Это похоже на 1C-инфобазу: да/нет
- Найдены обязательные таблицы 1C: Config/Params/DBSchema
- Количество таблиц _Reference*
- Количество таблиц _Document*
- Количество таблиц _InfoRg*
- Количество таблиц _AccumRg*
- Top-50 таблиц по row_count
- Таблицы-кандидаты для клиентов
- Таблицы-кандидаты для телефонов
- Таблицы-кандидаты для абонементов/продаж
- Таблицы-кандидаты для броней
- Таблицы-кандидаты для пластиковых карт
- Можно переходить к reverse engineering 1C metadata и скрипту выгрузки: да/нет
```

---

## 17. Как связать это с задачей Fitbase

Текущая бизнес-задача: выгрузить тестовый сегмент для Fitbase — воронка `Действующие клиенты`, этапы по дням до окончания, отдельный приоритет `Бронь`, телефоны через запятую, дата создания как первое появление/первая продажа, бюджет пустой, плюс отдельная таблица пластиковых карт.

Но до restore/доступа к таблицам нельзя определить:

```text
- где лежит справочник клиентов;
- где лежат телефоны;
- где лежат продажи/абонементы;
- где дата начала/окончания абонемента;
- где статус брони;
- где номер пластиковой карты;
- как связаны документы продаж, клиенты, карты и статусы.
```

Поэтому metadata-проверка backup нужна не для выгрузки клиентов, а для принятия технического решения:

```text
1. backup читается SQL Server или нет;
2. сколько места нужно для restore;
3. можно ли безопасно делать тестовый restore;
4. какой SQL Server version нужен;
5. нужны ли ключи/certificates/password из-за encryption/TDE.
```

---

## 18. Критерии успеха текущего no-restore этапа

Этап считается успешно завершенным, если есть:

```text
/home/linuxadmin/fitnes_mssql_probe_YYYYMMDD_HHMMSS/results/01_headeronly.tsv
/home/linuxadmin/fitnes_mssql_probe_YYYYMMDD_HHMMSS/results/02_filelistonly.tsv
/home/linuxadmin/fitnes_mssql_probe_YYYYMMDD_HHMMSS/results/02_restore_size_summary.txt
/home/linuxadmin/fitnes_mssql_probe_YYYYMMDD_HHMMSS/results/03_verifyonly.log
/home/linuxadmin/fitnes_mssql_probe_YYYYMMDD_HHMMSS/results/final_report.md
```

И в `final_report.md` есть конкретное решение:

```text
RESTORE на текущем /home: запрещен/разрешен
Минимальный отдельный volume: X GiB
Таблицы без restore: недоступны
Следующий шаг: подготовить отдельный volume и выполнить тестовый restore / запросить другой формат выгрузки
```

---

## 19. Источники и технические основания

- Microsoft Learn — `RESTORE HEADERONLY`: возвращает backup header information по backup sets на backup device.  
  https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-headeronly-transact-sql

- Microsoft Learn — `RESTORE FILELISTONLY`: возвращает список database/log files внутри backup set.  
  https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-filelistonly-transact-sql

- Microsoft Learn — auxiliary `RESTORE` statements: `FILELISTONLY`, `HEADERONLY`, `LABELONLY`, `VERIFYONLY` помогают управлять backup и планировать restore sequence; такие команды требуют `CREATE DATABASE` permission.  
  https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-for-restoring-recovering-and-managing-backups-transact-sql

- Microsoft Learn — `RESTORE VERIFYONLY`: проверяет backup, но не восстанавливает его; не проверяет структуру данных внутри backup volumes.  
  https://learn.microsoft.com/en-us/sql/t-sql/statements/restore-statements-verifyonly-transact-sql

- Microsoft Learn — SQL Server Docker container: официальный способ поднять SQL Server Linux container и подключаться через `sqlcmd`.  
  https://learn.microsoft.com/en-us/sql/linux/quickstart-install-connect-docker

- Microsoft Learn — SQL Server environment variables: `ACCEPT_EULA`, `MSSQL_SA_PASSWORD`, `MSSQL_PID`, `MSSQL_MEMORY_LIMIT_MB`.  
  https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-configure-environment-variables

- Microsoft Learn — SQL Server on Linux requirements: минимум 2 GB RAM, 6 GB disk, x64, ext4/XFS.  
  https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup

- Microsoft Learn — SQL Server catalog views / `sys.tables`: таблицы проверяются через catalog views уже в восстановленной/подключенной базе.  
  https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-tables-transact-sql

- Microsoft Learn — `DBCC CHECKDB`: проверка целостности после restore, но использует internal database snapshot и может потреблять место.  
  https://learn.microsoft.com/en-us/sql/t-sql/database-console-commands/dbcc-checkdb-transact-sql

- 1C:DN — структура данных 1C:Enterprise 8: в client/server mode инфобаза хранится в DBMS; обязательные таблицы включают `Config`, `Params`, `DBSchema`; типичные таблицы конфигурации включают `_Reference<n>`, `_Document<n>` и другие.  
  https://1c-dn.com/library/data_structure_in_1c_enterprise_8/
