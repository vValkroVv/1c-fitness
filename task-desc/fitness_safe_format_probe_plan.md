# План безопасной проверки формата данных `Fitnes.bak` на сервере

## 1. Цель проверки

Нужно безопасно понять, что именно лежит в ежедневном сохранении из `1C Fitness`:

- SQL Server backup (`.bak`);
- 1C dump (`.dt`) или другой файл восстановления 1C;
- файловая база 1C (`1Cv8.1CD`), возможно переименованная;
- PostgreSQL dump/archive;
- обычный архив (`zip`, `7z`, `rar`, `tar`, `gzip`);
- другой бинарный формат.

Главная цель — определить формат и дальнейший путь обработки **без восстановления, распаковки и копирования всего файла** на текущем диске.

---

## 2. Текущие ограничения сервера

По текущему описанию сервера:

- основной файл: `/home/linuxadmin/Fitnes.bak`;
- размер файла: `12,770,610,688 bytes`, примерно `11.9 GiB` / `12.8 GB`;
- команда `file` уже определяла тип как просто `data`, то есть стандартный тип по сигнатуре не распознан;
- RAM: примерно `30 GiB`, доступно примерно `29 GiB`;
- swap: `8 GiB`, свободен;
- `/home` находится на корневом разделе `/`;
- размер текущего filesystem: `48G`;
- свободно на текущем filesystem: около `23G`.

Вывод: **на текущем `/home` нельзя безопасно делать восстановление или распаковку**, потому что файл уже занимает около `12G`, а свободного места всего около `23G`. В разговоре также звучало предположение, что архив `12G` может разворачиваться примерно в `100G`, поэтому любые операции восстановления надо делать только после оценки фактического размера или на отдельном диске/разделе.

---

## 3. Правила безопасности перед любыми действиями

### 3.1. Что можно делать сразу

Разрешены только операции чтения:

- `stat`, `ls`, `du`, `df`, `free`, `file`;
- чтение первых/последних мегабайт файла;
- снятие маленьких бинарных сэмплов;
- поиск сигнатур только по сэмплам;
- SQL Server metadata-команды `RESTORE HEADERONLY` и `RESTORE FILELISTONLY`, если на сервере уже есть доступный SQL Server и `sqlcmd`;
- `RESTORE VERIFYONLY` — только после `HEADERONLY` / `FILELISTONLY`, потому что эта команда читает backup целиком, пусть и не восстанавливает его.

### 3.2. Что запрещено до определения формата и размера восстановления

Не выполнять:

```bash
cp /home/linuxadmin/Fitnes.bak ...
tar -xf /home/linuxadmin/Fitnes.bak
unzip /home/linuxadmin/Fitnes.bak
7z x /home/linuxadmin/Fitnes.bak
unrar x /home/linuxadmin/Fitnes.bak
RESTORE DATABASE ...
1cv8 DESIGNER ... /RestoreIB ...
```

Причина: эти команды могут создать десятки или сотни гигабайт данных и забить текущий filesystem.

### 3.3. Лимиты на диагностические файлы

Для первичной диагностики создать не больше:

- `64 MiB` с начала файла;
- `64 MiB` с конца файла;
- текстовые логи;
- отчет `probe_report.md`.

Итого рабочая папка должна занимать меньше `300 MiB`.

---

## 4. Подготовить рабочую папку и логирование

Войти на сервер под `linuxadmin` и выполнить:

```bash
set -Eeuo pipefail

SRC="/home/linuxadmin/Fitnes.bak"
WORK="/home/linuxadmin/fitnes_probe_$(date +%Y%m%d_%H%M%S)"

mkdir -p "$WORK/logs" "$WORK/samples" "$WORK/results"
chmod 700 "$WORK"

exec > >(tee -a "$WORK/logs/session.log") 2>&1

echo "SRC=$SRC"
echo "WORK=$WORK"
date
hostname
```

Проверить, что файл существует:

```bash
test -f "$SRC"
```

---

## 5. Проверить, что ежедневное сохранение не пишется прямо сейчас

Так как заказчик говорил, что это ежедневное сохранение из 1C Fitness, важно не читать файл в момент, когда он еще дописывается.

Сначала снять `stat`:

```bash
stat "$SRC" | tee "$WORK/results/stat_1.txt"
```

Через 60 секунд повторить:

```bash
sleep 60
stat "$SRC" | tee "$WORK/results/stat_2.txt"
```

Сравнить размер и `Modify`. Если размер или время изменения изменились — остановиться. Значит, файл сейчас обновляется или заменяется.

Дополнительно проверить открытые дескрипторы, если доступны команды:

```bash
command -v lsof >/dev/null 2>&1 && lsof -- "$SRC" | tee "$WORK/results/lsof.txt" || true
command -v fuser >/dev/null 2>&1 && fuser -v "$SRC" | tee "$WORK/results/fuser.txt" || true
```

Если `lsof` / `fuser` показывают, что файл открыт процессом backup/1C/SQL, диагностику лучше остановить и дождаться завершения сохранения.

---

## 6. Зафиксировать состояние ресурсов сервера

```bash
{
  echo "## date"; date
  echo "## uname"; uname -a
  echo "## free"; free -h
  echo "## df"; df -hT / /home
  echo "## lsblk"; lsblk -f
  echo "## source ls"; ls -lh "$SRC"
  echo "## source du"; du -h "$SRC"
  echo "## source stat"; stat "$SRC"
} | tee "$WORK/results/server_state.txt"
```

Критерий остановки:

- если свободно на `/home` меньше `10G`, не делать даже расширенную диагностику;
- если свободно меньше `5G`, не создавать сэмплы, только `stat`/`df`/`file`.

На текущем сервере свободно около `23G`, поэтому сэмплы по `64 MiB` допустимы.

---

## 7. Быстрая проверка типа без чтения всего файла

```bash
file "$SRC" | tee "$WORK/results/file_full.txt"
file -b "$SRC" | tee "$WORK/results/file_brief.txt"

head -c 4096 "$SRC" | xxd -g1 | tee "$WORK/results/head_4k.hex"
tail -c 4096 "$SRC" | xxd -g1 | tee "$WORK/results/tail_4k.hex"

head -c 16 "$SRC" | od -An -tx1 | tee "$WORK/results/magic_16_bytes.txt"
```

Ожидаемая логика:

- если `file` показывает `Zip archive`, `gzip`, `7-zip`, `RAR`, `tar` — дальше проверять архив только через листинг, не распаковку;
- если `file` показывает просто `data` — это нормально для многих DB backup-форматов, дальше идти к SQL/1C/PostgreSQL проверкам;
- если первые байты похожи на `PGDMP` — вероятен PostgreSQL custom dump;
- если в файле встречаются признаки SQL Server backup — проверять через SQL Server `RESTORE HEADERONLY` / `FILELISTONLY`;
- если формат не определился — продолжить через сэмплы.

---

## 8. Снять маленькие сэмплы начала и конца файла

Сэмплы нужны, чтобы не гонять `strings` и поиск сигнатур по всему `12G` файлу.

```bash
# первые 64 MiB
ionice -c2 -n7 nice -n19 \
  dd if="$SRC" of="$WORK/samples/head_64MiB.bin" bs=1M count=64 status=progress

# последние 64 MiB
ionice -c2 -n7 nice -n19 \
  tail -c 67108864 "$SRC" > "$WORK/samples/tail_64MiB.bin"

ls -lh "$WORK/samples" | tee "$WORK/results/samples_ls.txt"
```

Снять частичные хэши, чтобы потом понимать, что проверяли именно этот файл:

```bash
sha256sum "$WORK/samples/head_64MiB.bin" | tee "$WORK/results/head_64MiB.sha256.txt"
sha256sum "$WORK/samples/tail_64MiB.bin" | tee "$WORK/results/tail_64MiB.sha256.txt"
```

Полный `sha256sum` всего `12G` файла на первом этапе не обязателен: это безопасно по памяти, но читает весь файл и может быть лишней нагрузкой.

---

## 9. Поиск сигнатур по сэмплам

```bash
for S in "$WORK"/samples/*.bin; do
  B=$(basename "$S")
  file "$S" | tee "$WORK/results/file_$B.txt"
  strings -a -n 8 "$S" | head -n 1000 > "$WORK/results/strings_${B}.txt"

  LC_ALL=C grep -aob -m 50 \
    -E 'Microsoft SQL Server|SQL Server|1C|1Cv8|1CD|Infobase|PGDMP|postgres|PostgreSQL|TAPE|BACKUP|DatabaseName|CompressionAlgorithm' \
    "$S" > "$WORK/results/signatures_${B}.txt" || true
done
```

Что смотреть в результатах:

- `Microsoft SQL Server`, `SQL Server`, `TAPE`, `DatabaseName`, `BackupName` → вероятен SQL Server backup;
- `PGDMP`, `PostgreSQL` → вероятен PostgreSQL archive dump;
- `1C`, `1Cv8`, `Infobase`, `1CD` → вероятен формат 1C или данные 1C внутри DB backup;
- отсутствие строк не значит, что формат не SQL/1C: backup может быть сжатым или бинарным.

---

## 10. Проверить, есть ли на сервере SQL Server / sqlcmd

```bash
{
  echo "## sqlcmd"
  command -v sqlcmd || true
  ls -1 /opt/mssql-tools*/bin/sqlcmd 2>/dev/null || true

  echo "## mssql services"
  systemctl list-units --type=service --all | grep -iE 'mssql|sql server' || true

  echo "## mssql dirs"
  ls -ld /opt/mssql /var/opt/mssql 2>/dev/null || true
} | tee "$WORK/results/sqlserver_tools.txt"
```

Если SQL Server и `sqlcmd` уже установлены, можно делать metadata-проверку. Если не установлены — **не ставить SQL Server сразу на текущий раздел**, потому что установка и дальнейшее восстановление могут забрать много места. В этом случае сначала закончить файловую диагностику и решить, нужен ли отдельный диск.

---

## 11. SQL Server ветка: проверить `.bak` без восстановления

Эта ветка выполняется, если есть доступный SQL Server и учетные данные для `sqlcmd`.

### 11.1. Дать SQL Server временный read-only доступ к backup-файлу

Если SQL Server работает под пользователем `mssql`, ему может не хватить прав на `/home/linuxadmin/Fitnes.bak`. Не копировать файл. Лучше временно дать ACL:

```bash
sudo setfacl -m u:mssql:x /home/linuxadmin
sudo setfacl -m u:mssql:r "$SRC"
getfacl "$SRC" | tee "$WORK/results/fitnes_bak_acl_before_sql.txt"
```

После проверки ACL надо убрать.

### 11.2. Выполнить `RESTORE HEADERONLY`

Команда возвращает информацию о backup set: имя базы, тип backup, даты, версию сервера, размер backup и другие поля.

Пример:

```bash
SQLCMD="$(command -v sqlcmd || ls -1 /opt/mssql-tools*/bin/sqlcmd 2>/dev/null | head -n1)"

"$SQLCMD" -S localhost -U '<SQL_USER>' -P '<SQL_PASSWORD>' -C \
  -Q "RESTORE HEADERONLY FROM DISK = N'/home/linuxadmin/Fitnes.bak';" \
  -o "$WORK/results/sql_restore_headeronly.txt"
```

Если используется другой способ авторизации, заменить `-U/-P` на актуальные параметры.

### 11.3. Выполнить `RESTORE FILELISTONLY`

Команда возвращает список файлов внутри backup: data/log/fulltext/filestream, их logical name, physical name и размер.

```bash
"$SQLCMD" -S localhost -U '<SQL_USER>' -P '<SQL_PASSWORD>' -C \
  -Q "RESTORE FILELISTONLY FROM DISK = N'/home/linuxadmin/Fitnes.bak';" \
  -o "$WORK/results/sql_restore_filelistonly.txt"
```

По результатам `FILELISTONLY` посчитать сумму поля `Size` по файлам. Это фактическая оценка размера, который понадобится под восстановленную БД, без учета запаса.

Правило:

- если сумма `Size` больше `15G`, не восстанавливать на текущий `/home`;
- если сумма близка к `100G`, нужен отдельный диск минимум `150G`, лучше `200–250G`, особенно если там же будут временные файлы и экспорт;
- для боевой обработки лучше держать backup и восстановленную базу на разных местах хранения.

### 11.4. Опционально выполнить `RESTORE VERIFYONLY`

Делать только после `HEADERONLY` и `FILELISTONLY`, когда понятно, что это SQL Server backup.

```bash
"$SQLCMD" -S localhost -U '<SQL_USER>' -P '<SQL_PASSWORD>' -C \
  -Q "RESTORE VERIFYONLY FROM DISK = N'/home/linuxadmin/Fitnes.bak' WITH CHECKSUM;" \
  -o "$WORK/results/sql_restore_verifyonly.txt"
```

Особенности:

- команда не восстанавливает базу;
- читает backup целиком;
- может занять время и создать I/O нагрузку;
- если backup был создан без checksums, вариант `WITH CHECKSUM` может быть неприменим — тогда повторить без `WITH CHECKSUM`.

### 11.5. Убрать временные ACL

```bash
sudo setfacl -x u:mssql "$SRC" || true
sudo setfacl -x u:mssql /home/linuxadmin || true
```

---

## 12. PostgreSQL ветка: проверить archive dump без восстановления

Эта ветка нужна, если первые байты/строки показывают `PGDMP` или есть признаки PostgreSQL.

Проверить наличие `pg_restore`:

```bash
command -v pg_restore | tee "$WORK/results/pg_restore_path.txt" || true
```

Если `pg_restore` есть, сделать только листинг:

```bash
ionice -c2 -n7 nice -n19 timeout 600 \
  pg_restore --list "$SRC" > "$WORK/results/postgres_pg_restore_list.txt"
```

Не выполнять `pg_restore -d ...`, пока не рассчитан размер восстановления и не подготовлен отдельный test database / storage.

По листингу искать таблицы/схемы, похожие на 1C:

```bash
grep -iE '1c|_reference|_document|_inforg|_accumrg|client|card|abon|fitness' \
  "$WORK/results/postgres_pg_restore_list.txt" \
  > "$WORK/results/postgres_possible_1c_objects.txt" || true
```

---

## 13. 1C ветка: проверить наличие платформы 1C, но не восстанавливать

Проверить, установлена ли 1C:

```bash
{
  echo "## 1C binaries"
  find /opt /usr -maxdepth 5 -type f \
    \( -name '1cv8' -o -name '1cv8c' -o -name 'rac' -o -name 'ras' \) \
    2>/dev/null || true

  echo "## 1C services"
  systemctl list-units --type=service --all | grep -iE '1c|srv1cv8|ras|rac' || true
} | tee "$WORK/results/1c_tools.txt"
```

Если 1C установлена, на этом этапе **не запускать восстановление**. Сначала определить, что это за файл:

- если это `.dt`, восстановление делать только в пустую тестовую инфобазу на отдельном диске;
- если это файловая база `1Cv8.1CD`, открыть ее можно только в изолированной копии/папке, а не как рабочий файл;
- если это SQL Server backup с базой 1C, работать через восстановленную SQL-базу и/или через платформу 1C после восстановления.

Важно: восстановление 1C dump полностью заменяет целевую инфобазу. Поэтому нельзя указывать рабочую/продуктивную инфобазу как цель.

---

## 14. Архивная ветка: только листинг, без распаковки

Если сигнатуры показывают обычный архив, использовать только команды просмотра состава.

### ZIP

```bash
command -v unzip >/dev/null 2>&1 && \
  timeout 600 unzip -l "$SRC" > "$WORK/results/archive_unzip_list.txt"
```

### 7z / RAR / смешанные форматы

```bash
command -v 7z >/dev/null 2>&1 && \
  timeout 600 7z l "$SRC" > "$WORK/results/archive_7z_list.txt"
```

### tar

```bash
command -v tar >/dev/null 2>&1 && \
  timeout 600 tar -tf "$SRC" > "$WORK/results/archive_tar_list.txt"
```

Если листинг показывает файл `1Cv8.1CD`, `.dt`, `.bak`, `.mdf`, `.ldf`, `.sql`, `.backup`, дальше переходить в соответствующую ветку. Распаковку делать только на отдельный диск с запасом.

---

## 15. Сформировать короткий отчет по результатам диагностики

Создать файл:

```bash
REPORT="$WORK/results/probe_report.md"

{
  echo "# Fitnes.bak probe report"
  echo
  echo "## Source"
  stat "$SRC"
  echo
  echo "## Disk/RAM"
  free -h
  df -hT / /home
  echo
  echo "## file"
  cat "$WORK/results/file_full.txt" 2>/dev/null || true
  echo
  echo "## Magic bytes"
  cat "$WORK/results/magic_16_bytes.txt" 2>/dev/null || true
  echo
  echo "## SQL Server tools"
  cat "$WORK/results/sqlserver_tools.txt" 2>/dev/null || true
  echo
  echo "## SQL HEADERONLY summary"
  cat "$WORK/results/sql_restore_headeronly.txt" 2>/dev/null || true
  echo
  echo "## SQL FILELISTONLY summary"
  cat "$WORK/results/sql_restore_filelistonly.txt" 2>/dev/null || true
  echo
  echo "## PostgreSQL list summary"
  head -n 200 "$WORK/results/postgres_pg_restore_list.txt" 2>/dev/null || true
  echo
  echo "## 1C tools"
  cat "$WORK/results/1c_tools.txt" 2>/dev/null || true
  echo
  echo "## Archive list summary"
  head -n 200 "$WORK/results/archive_7z_list.txt" 2>/dev/null || true
  head -n 200 "$WORK/results/archive_unzip_list.txt" 2>/dev/null || true
  head -n 200 "$WORK/results/archive_tar_list.txt" 2>/dev/null || true
} > "$REPORT"

ls -lh "$REPORT"
```

---

## 16. Как принять решение по результату

### Вариант A: это SQL Server backup

Признаки:

- `RESTORE HEADERONLY` успешно отработал;
- `RESTORE FILELISTONLY` показывает data/log files;
- в metadata есть `DatabaseName`, `BackupStartDate`, `BackupFinishDate`, `ServerName`, `DatabaseVersion`, `BackupSize`, `CompressedBackupSize`.

Дальше:

1. По `FILELISTONLY` оценить размер восстановления.
2. Если размер больше безопасного лимита текущего `/home`, подготовить отдельный диск/volume.
3. Восстановить базу только в тестовое имя, например `Fitnes_probe`, не в production.
4. После восстановления искать структуру 1C: таблицы `_Reference...`, `_Document...`, `_InfoRg...`, `_AccumRg...`, `_Enum...` и т.п.
5. Дальше писать SQL-выгрузку или промежуточный ETL-скрипт.
6. Обработку делать батчами/стримингом, не загружать всю базу в RAM.
7. Для XLSX использовать потоковую запись (`openpyxl` write-only или аналог), чтобы не держать весь результат в памяти.

### Вариант B: это 1C `.dt` dump

Признаки:

- SQL Server `HEADERONLY` не работает;
- файл не является обычным архивом;
- 1C-платформа распознает файл как dump при попытке восстановления в тестовую инфобазу;
- есть 1C-специфические строки/признаки.

Дальше:

1. Не восстанавливать на текущем `/home`.
2. Подготовить отдельное место. Если файл `12G`, а ожидаемый развернутый размер около `100G`, безопасный минимум — `200G+`.
3. Создать пустую тестовую инфобазу.
4. Восстановить `.dt` только в нее.
5. Извлекать данные через 1C-платформу или через DBMS после перевода/размещения в клиент-серверном режиме.

### Вариант C: это файловая база 1C `1Cv8.1CD`

Признаки:

- файл похож на бинарную файловую базу 1C;
- внутри/рядом должен быть файл `1Cv8.1CD`, либо текущий `Fitnes.bak` является переименованным `.1CD`.

Дальше:

1. Не открывать файл напрямую как рабочую базу.
2. Сделать изолированную копию только на отдельный диск.
3. Открыть через 1C-платформу в файловом режиме.
4. Лучше конвертировать/перенести в клиент-серверный режим для дальнейших SQL/ETL-запросов.
5. Не парсить `.1CD` напрямую самописным бинарным парсером, если есть возможность использовать 1C-платформу.

### Вариант D: это PostgreSQL archive dump

Признаки:

- сигнатура `PGDMP`;
- `pg_restore --list` успешно показывает table of contents.

Дальше:

1. По листингу определить схемы и таблицы.
2. Оценить размер восстановления отдельно.
3. Восстановить в тестовую PostgreSQL-базу на отдельном storage.
4. Ищем 1C-структуру таблиц и далее пишем SQL/ETL.

### Вариант E: это обычный архив

Признаки:

- `7z l`, `unzip -l` или `tar -tf` показывает список файлов.

Дальше:

1. По листингу определить, что внутри: `.dt`, `.1CD`, `.bak`, `.mdf/.ldf`, `.sql`, `.backup`.
2. Не распаковывать на текущий `/home`.
3. Подготовить отдельный диск.
4. Распаковать только нужные файлы, если формат архива позволяет выборочное извлечение.

### Вариант F: формат неизвестен

Признаки:

- `file` показывает `data`;
- SQL Server `HEADERONLY` не работает;
- `pg_restore --list` не работает;
- архивные листинги не работают;
- 1C не распознает файл без восстановления.

Дальше:

1. Сохранить `head/tail` сэмплы, логи и `probe_report.md`.
2. Запросить у администратора/заказчика точное описание механизма ежедневного сохранения:
   - через какую кнопку/регламент в 1C делается сохранение;
   - расширение исходного файла до переименования;
   - используется ли SQL Server/PostgreSQL;
   - есть ли исходная база сейчас в production;
   - есть ли штатная инструкция восстановления.
3. Попросить тестовый маленький backup или создать новый backup с явно указанным форматом.
4. Не пытаться «угадывать» формат через распаковку или восстановление на текущем диске.

---

## 17. Минимальный итог, который должен быть после проверки

После безопасной проверки должен быть набор файлов:

```text
/home/linuxadmin/fitnes_probe_YYYYMMDD_HHMMSS/
├── logs/
│   └── session.log
├── samples/
│   ├── head_64MiB.bin
│   └── tail_64MiB.bin
└── results/
    ├── server_state.txt
    ├── file_full.txt
    ├── magic_16_bytes.txt
    ├── strings_head_64MiB.bin.txt
    ├── strings_tail_64MiB.bin.txt
    ├── signatures_head_64MiB.bin.txt
    ├── signatures_tail_64MiB.bin.txt
    ├── sql_restore_headeronly.txt              # если SQL Server ветка сработала
    ├── sql_restore_filelistonly.txt            # если SQL Server ветка сработала
    ├── sql_restore_verifyonly.txt              # если запускали verify
    ├── postgres_pg_restore_list.txt            # если PostgreSQL ветка сработала
    ├── archive_7z_list.txt / archive_unzip_list.txt / archive_tar_list.txt
    └── probe_report.md
```

Главный артефакт — `probe_report.md`. По нему должно быть понятно:

- какой формат у `Fitnes.bak`;
- какой инструмент нужен для восстановления/чтения;
- сколько примерно места нужно для восстановления;
- можно ли работать на текущем сервере или нужен отдельный диск;
- как дальше строить ETL для выгрузки в XLSX.

---

## 18. Дальнейшая стратегия обработки после определения формата

Когда формат определен, общий безопасный путь такой:

1. Восстановить/открыть данные только в тестовой среде.
2. Найти таблицы/объекты клиентов, договоров/абонементов, продаж, телефонов, карт, броней.
3. Сначала сделать маленькую выборку: 10–50 клиентов.
4. Проверить, что по этим клиентам можно получить:
   - ID клиента из 1C;
   - ФИО;
   - телефоны, включая несколько номеров через запятую;
   - дату первого появления/первой продажи;
   - текущий активный абонемент;
   - дату окончания абонемента;
   - признак брони;
   - номер пластиковой карты.
5. Сделать тестовую XLSX-выгрузку на 100–500 клиентов.
6. Сверить с заказчиком вручную 5–10 клиентов в 1C.
7. Только после сверки делать массовую выгрузку.
8. Массовую выгрузку писать потоково, батчами, без загрузки всей базы в память.

---

## 19. Ключевой практический вывод

На текущем сервере можно безопасно определить формат файла и собрать metadata, но **нельзя безопасно восстанавливать или распаковывать файл на текущем `/home`**, пока не известен фактический размер восстановления. Самая вероятная безопасная первая техническая проверка для файла с расширением `.bak` — проверить его как SQL Server backup через `RESTORE HEADERONLY` и `RESTORE FILELISTONLY`, потому что эти команды дают metadata без `RESTORE DATABASE`.

---

## Источники для технических решений

- Microsoft Learn: `RESTORE HEADERONLY` возвращает backup header information for backup sets.
- Microsoft Learn: `RESTORE FILELISTONLY` возвращает список database/log files внутри SQL Server backup, включая `Size`.
- Microsoft Learn: `RESTORE VERIFYONLY` проверяет backup, не восстанавливая его, но читает backup и проверяет, что backup set complete/readable.
- 1C:Enterprise documentation: 1C может хранить infobase в файловом режиме как `1Cv8.1CD` или в DBMS, включая Microsoft SQL Server и PostgreSQL.
- 1C:Enterprise administrator guide: при восстановлении infobase из файла нужен свободный диск под временные файлы примерно равный expanded size; итоговая база может быть в несколько раз больше `.dt`; восстановление уничтожает целевую infobase.
- PostgreSQL documentation: `pg_restore --list` показывает table of contents archive без восстановления в базу.
