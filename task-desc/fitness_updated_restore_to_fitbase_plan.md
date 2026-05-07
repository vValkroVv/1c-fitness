# Обновленный план: от восстановления `Fitnes.bak` до двух таблиц Fitbase

Дата обновления: 2026-05-04  
Статус: план после уже выполненной проверки формата и SQL Server metadata

---

## 0. Что уже сделано и больше не повторяем

Уже подтверждено:

1. `/home/linuxadmin/Fitnes.bak` — это **Microsoft SQL Server database backup**, а не ZIP/TAR/1C `.dt`.
2. Внутри backup один backup set:
   - `DatabaseName`: `Fitness`;
   - `BackupTypeDescription`: `Database`;
   - `FILE position`: `1`;
   - backup сжатый;
   - backup с checksum;
   - явных признаков TDE/encryption нет.
3. Backup создан SQL Server ветки `13.0.5108`, то есть SQL Server 2016-линейкой.
4. Metadata и читаемость backup уже проверены:
   - `RESTORE HEADERONLY`: success;
   - `RESTORE FILELISTONLY`: success;
   - `RESTORE VERIFYONLY`: success;
   - результат `VERIFYONLY`: `The backup set on file 1 is valid.`
5. Размер backup-файла:
   - `12,770,610,688 bytes`;
   - примерно `11.90 GiB`.
6. Оценочный размер восстановленной базы по `FILELISTONLY`:

| LogicalName | PhysicalName | Type | Size bytes | Size GiB |
|---|---|---:|---:|---:|
| `Fitness` | `D:\SQLDATA\Fitness.mdf` | data | `80,404,807,680` | `74.88 GiB` |
| `Fitness_log` | `D:\SQLDATA\Fitness_log.ldf` | log | `3,699,376,128` | `3.45 GiB` |

Итого restore size: **78.33 GiB**.

7. Текущий сервер заказчика не подходит для восстановления на `/home`, потому что там свободно только около `22–23 GiB`.
8. Следующий этап должен выполняться на отдельном VPS/volume, например `200 GB disk / 40 GB RAM`, либо на другом сервере с достаточным диском.

---

## 1. Цель обновленного плана

Нужно восстановить SQL Server backup базы `Fitness` в безопасной тестовой среде, найти в восстановленной базе таблицы и поля 1C Fitness, извлечь сегмент **«Действующие клиенты»**, обработать его по бизнес-правилам заказчика и сформировать две XLSX-таблицы для Fitbase:

1. `Копия Импорт_заявки.xlsx` — основной импорт клиентов/заявок в воронку Fitbase.
2. `Пластиковая карта.xlsx` — отдельная таблица телефонов, ФИО и номеров пластиковых карт.

План ниже начинается **после уже выполненной no-restore проверки** и охватывает всю часть от подготовки restore-среды до передачи готовых таблиц Fitbase.

---

## 2. Финальный результат, который должен быть получен

Минимальный финальный результат тестового этапа:

```text
fitness_migration/
  config/
    settings.yml
    managers.yml
    table_mapping.yml
    stage_rules.yml
  sql/
    01_restore_database.sql
    02_post_restore_checks.sql
    03_schema_inventory.sql
    04_candidate_tables_probe.sql
    05_extract_normalized_dataset.sql
  scripts/
    extract_to_staging.py
    build_fitbase_xlsx.py
    validate_outputs.py
  output/
    fitbase_active_clients_import_zayavki_YYYYMMDD.xlsx
    fitbase_active_clients_plastic_cards_YYYYMMDD.xlsx
    validation_report.md
    stage_distribution.csv
    duplicates_report.csv
    missing_required_fields.csv
    missing_sales_report.csv
    missing_cards_report.csv
    multiple_active_subscriptions_report.csv
    multiple_cards_report.csv
    booking_without_active_subscription_report.csv
    schema_inventory.csv
    table_mapping_report.md
  logs/
    restore.log
    schema_discovery.log
    extraction.log
    xlsx_build.log
    validation.log
```

### 2.1. Основной XLSX: `fitbase_active_clients_import_zayavki_YYYYMMDD.xlsx`

Должен быть сформирован строго по шаблону `Копия Импорт_заявки.xlsx`.

Шаблон содержит 9 рабочих колонок:

| Колонка | Техническое поле | Русское поле в шаблоне | Правило заполнения |
|---|---|---|---|
| A | `client_id` | `Внутренний номер клиента` | внутренний номер/код клиента из 1C |
| B | `phone` | `Телефон *` | все телефоны клиента как в 1C, несколько телефонов через запятую |
| C | `client_fio` | `ФИО клиента *` | ФИО клиента |
| D | `email` | `Почта` | все email клиента через запятую, если есть |
| E | `funnel` | `Воронка *` | всегда `Действующие клиенты` |
| F | `funnel_step` | `Этап воронки *` | этап по алгоритму |
| G | `budget` | `Бюджет` | всегда `0` |
| H | `create_date` | `Дата создания *` | первая дата, когда клиент появился в базе через любую продажу: абонемент, 7 дней, 1 день, пробный день и т.д.; это не дата посещения из CSV |
| I | `manager` | `Менеджер` | детерминированное равномерное распределение между `A1`, `A2`, `A3` |

Правило записи:

```text
строка 1 шаблона — сохранить без изменений;
строка 2 шаблона — сохранить без изменений;
строка 3 с примером — удалить/очистить;
данные клиентов писать с 3-й строки.
```

### 2.2. XLSX пластиковых карт: `fitbase_active_clients_plastic_cards_YYYYMMDD.xlsx`

Должен быть сформирован строго по шаблону `Пластиковая карта.xlsx`.

Шаблон содержит 3 колонки:

| Колонка | Поле | Правило заполнения |
|---|---|---|
| A | `телефон` | все телефоны клиента через запятую |
| B | `фио` | ФИО клиента |
| C | `номер пластиковой карты` | все активные/unmarked пластиковые карты клиента через запятую; если карты нет — пусто и строка в отчете |

Правило записи:

```text
строка 1 шаблона — сохранить без изменений;
данные писать со 2-й строки.
```

### 2.3. Отчеты, без которых результат нельзя считать готовым

Обязательно должны быть готовы:

1. `validation_report.md` — итоговая проверка выгрузки.
2. `stage_distribution.csv` — количество клиентов по этапам.
3. `duplicates_report.csv` — что было склеено по правилу `ФИО + телефон`, а что оставлено как спорный дубль.
4. `missing_required_fields.csv` — клиенты без телефона/ФИО/даты создания; их все равно пытаться выгрузить, но отдельно подсветить.
5. `missing_sales_report.csv` — клиенты без найденной первой продажи; это ненормальная ситуация для `Дата создания *`, решать отдельно.
6. `missing_cards_report.csv` — клиенты без пластиковой карты.
7. `multiple_active_subscriptions_report.csv` — клиенты, у которых найдено больше одного действующего абонемента.
8. `multiple_cards_report.csv` — клиенты, у которых найдено несколько пластиковых карт.
9. `booking_without_active_subscription_report.csv` — клиенты с флагом брони, но без действующего абонемента; в основной XLSX не включать без отдельного решения.
10. `table_mapping_report.md` — карта: какое поле Fitbase из какой таблицы/колонки 1C берется.
11. `schema_inventory.csv` — список таблиц восстановленной SQL Server базы с количеством строк и колонками.

---

## 3. Рабочая среда для восстановления

### 3.1. Минимальная конфигурация VPS

Рекомендуемая конфигурация:

```text
Disk: 200 GB SSD/NVMe минимум
RAM: 40 GB
CPU: 4+ vCPU, лучше 6–8 vCPU
OS: Ubuntu/Debian Linux x64
SQL Server edition: Developer или Evaluation/Standard, НЕ Express
```

Почему не Express:

```text
Восстановленная база ожидается 78.33 GiB,
а SQL Server Express имеет лимит relational database size 10 GB.
```

### 3.2. Проверка свободного места до копирования backup

На новом VPS сразу выполнить:

```bash
df -h
lsblk -f
free -h
nproc
```

Критерий допуска:

```text
До копирования Fitnes.bak свободно желательно >= 170 GiB.
Минимально допустимо: >= 160 GiB, но это уже тесный режим.
```

На 200 GB VPS после установки системы обычно останется около `180+ GiB`, этого должно хватить для:

```text
Fitnes.bak: 11.90 GiB
FitnessRestored.mdf/ldf: 78.33 GiB
tempdb / логи / промежуточные файлы: 20–40 GiB
XLSX / CSV / отчеты: 5–15 GiB
запас: 30–50 GiB
```

### 3.3. Что нельзя делать на 200 GB VPS

До получения итоговых файлов нельзя:

1. Копировать `.bak` несколько раз.
2. Создавать вторую восстановленную копию базы.
3. Делать полный dump всех таблиц в CSV.
4. Запускать полный `DBCC CHECKDB` как первый шаг.
5. Открывать порт `1433` наружу без необходимости.
6. Восстанавливать базу в SQL Server Express.

---

## 4. Подготовка директорий на VPS

Создать рабочую структуру:

```bash
sudo mkdir -p /mnt/fitness_sql/{backup,mssql,work,output,logs,tmp}
sudo chown -R "$USER:$USER" /mnt/fitness_sql

mkdir -p /mnt/fitness_sql/work/{config,sql,scripts,docs}
```

Рекомендуемые пути:

```text
/mnt/fitness_sql/backup/Fitnes.bak      # один экземпляр backup
/mnt/fitness_sql/mssql/                 # persistent data SQL Server container
/mnt/fitness_sql/work/                  # скрипты, конфиги, документы
/mnt/fitness_sql/output/                # итоговые XLSX и отчеты
/mnt/fitness_sql/logs/                  # логи восстановления и обработки
/mnt/fitness_sql/tmp/                   # временные CSV/staging files
```

---

## 5. Перенос `Fitnes.bak` на новый VPS

Скопировать backup один раз:

```bash
rsync -P --partial --append-verify \
  linuxadmin@192.168.2.36:/home/linuxadmin/Fitnes.bak \
  /mnt/fitness_sql/backup/Fitnes.bak
```

После копирования проверить размер:

```bash
stat /mnt/fitness_sql/backup/Fitnes.bak
ls -lh /mnt/fitness_sql/backup/Fitnes.bak
du -h /mnt/fitness_sql/backup/Fitnes.bak
```

Если есть checksum с исходного сервера — сверить:

```bash
sha256sum /mnt/fitness_sql/backup/Fitnes.bak
```

Если checksum заранее не был снят, на исходном сервере снять его отдельно и сравнить:

```bash
sha256sum /home/linuxadmin/Fitnes.bak
```

Результат шага:

```text
Backup лежит на новом VPS в одном экземпляре.
Размер совпадает: 12,770,610,688 bytes.
Файл не поврежден при копировании.
```

---

## 6. Поднять SQL Server для восстановления

### 6.1. Установить Docker

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo apt-get install -y docker.io
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

После добавления в группу Docker перелогиниться в SSH-сессию.

### 6.2. Запустить SQL Server Developer container

Создать пароль:

```bash
export MSSQL_SA_PASSWORD='CHANGE_ME_StrongPassword_2026!'
```

Запустить контейнер:

```bash
docker run -d \
  --name mssql-fitness \
  --hostname mssql-fitness \
  --memory=34g \
  --cpus=6 \
  -e ACCEPT_EULA=Y \
  -e MSSQL_SA_PASSWORD="$MSSQL_SA_PASSWORD" \
  -e MSSQL_PID=Developer \
  -e MSSQL_MEMORY_LIMIT_MB=28672 \
  -p 127.0.0.1:1433:1433 \
  -v /mnt/fitness_sql/mssql:/var/opt/mssql \
  -v /mnt/fitness_sql/backup:/backup:ro \
  mcr.microsoft.com/mssql/server:2022-latest
```

Важные параметры:

```text
-p 127.0.0.1:1433:1433  # порт доступен только локально на VPS
-v /mnt/fitness_sql/backup:/backup:ro  # backup примонтирован read-only
MSSQL_MEMORY_LIMIT_MB=28672  # SQL Server получает около 28 GB RAM
--memory=34g  # контейнер не может съесть всю RAM VPS
```

Проверить запуск:

```bash
docker ps
docker logs mssql-fitness --tail 100
```

Если внутри контейнера нет `sqlcmd`, установить `mssql-tools18` на хост или использовать отдельный tools-контейнер. Важно, чтобы команды выполнялись против SQL Server instance, а не просто локально по файлу.

---

## 7. Повторная SQL-проверка перед восстановлением

Даже если metadata уже проверяли ранее, на новом VPS нужно повторить минимум:

```sql
RESTORE HEADERONLY
FROM DISK = N'/backup/Fitnes.bak';

RESTORE FILELISTONLY
FROM DISK = N'/backup/Fitnes.bak'
WITH FILE = 1;

RESTORE VERIFYONLY
FROM DISK = N'/backup/Fitnes.bak'
WITH FILE = 1;
```

Сохранить выводы:

```text
/mnt/fitness_sql/logs/restore_headeronly.txt
/mnt/fitness_sql/logs/restore_filelistonly.txt
/mnt/fitness_sql/logs/restore_verifyonly.txt
```

Критерии допуска к restore:

```text
HEADERONLY вернул DatabaseName = Fitness;
FILELISTONLY вернул LogicalName = Fitness и Fitness_log;
VERIFYONLY вернул The backup set on file 1 is valid;
df -h показывает достаточный запас места.
```

---

## 8. Восстановить базу через `WITH MOVE`

Так как исходные пути внутри backup Windows-формата:

```text
D:\SQLDATA\Fitness.mdf
D:\SQLDATA\Fitness_log.ldf
```

на Linux нужно обязательно восстанавливать через `WITH MOVE`.

Создать файл:

```text
/mnt/fitness_sql/work/sql/01_restore_database.sql
```

Содержимое:

```sql
RESTORE DATABASE [FitnessRestored]
FROM DISK = N'/backup/Fitnes.bak'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'/var/opt/mssql/data/FitnessRestored.mdf',
    MOVE N'Fitness_log' TO N'/var/opt/mssql/data/FitnessRestored_log.ldf',
    RECOVERY,
    STATS = 5;
GO
```

Запустить:

```bash
sqlcmd -S 127.0.0.1,1433 -U sa -P "$MSSQL_SA_PASSWORD" \
  -C -i /mnt/fitness_sql/work/sql/01_restore_database.sql \
  | tee /mnt/fitness_sql/logs/restore.log
```

Во время restore в отдельной SSH-сессии мониторить диск:

```bash
watch -n 5 'df -h /mnt/fitness_sql; du -sh /mnt/fitness_sql/mssql /mnt/fitness_sql/backup /mnt/fitness_sql/tmp 2>/dev/null'
```

Критерий успешного restore:

```text
SQL Server завершил RESTORE DATABASE без ошибок.
База FitnessRestored находится в state ONLINE.
Файлы MDF/LDF появились в /mnt/fitness_sql/mssql/data/ внутри persistent volume.
```

---

## 9. Проверить, что база восстановилась и доступна

Создать файл:

```text
/mnt/fitness_sql/work/sql/02_post_restore_checks.sql
```

Содержимое:

```sql
SELECT
    name,
    state_desc,
    recovery_model_desc,
    compatibility_level,
    create_date
FROM sys.databases
WHERE name = N'FitnessRestored';
GO

SELECT
    DB_NAME(database_id) AS database_name,
    name AS logical_name,
    type_desc,
    size * 8.0 / 1024 AS size_mb,
    physical_name
FROM sys.master_files
WHERE database_id = DB_ID(N'FitnessRestored')
ORDER BY type_desc, logical_name;
GO

USE [FitnessRestored];
GO

SELECT COUNT(*) AS user_tables_count
FROM sys.tables
WHERE is_ms_shipped = 0;
GO
```

Сохранить вывод:

```bash
sqlcmd -S 127.0.0.1,1433 -U sa -P "$MSSQL_SA_PASSWORD" -C \
  -i /mnt/fitness_sql/work/sql/02_post_restore_checks.sql \
  | tee /mnt/fitness_sql/logs/post_restore_checks.txt
```

На первом этапе **не запускать полный `DBCC CHECKDB`**. Если нужна минимальная физическая проверка и места достаточно, можно позже выполнить:

```sql
DBCC CHECKDB(N'FitnessRestored') WITH PHYSICAL_ONLY, NO_INFOMSGS;
```

Полный `DBCC CHECKDB` запускать только после выгрузки данных или при наличии дополнительного запаса места.

---

## 10. Первичная инвентаризация таблиц SQL Server / 1C

После restore нужно получить карту всех таблиц, не пытаясь сразу писать бизнес-запросы.

Создать файл:

```text
/mnt/fitness_sql/work/sql/03_schema_inventory.sql
```

Содержимое:

```sql
USE [FitnessRestored];
GO

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    SUM(CASE WHEN p.index_id IN (0, 1) THEN p.rows ELSE 0 END) AS approx_rows
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
LEFT JOIN sys.partitions p ON p.object_id = t.object_id
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name
ORDER BY approx_rows DESC, t.name;
GO

SELECT
    s.name AS schema_name,
    t.name AS table_name,
    c.column_id,
    c.name AS column_name,
    ty.name AS sql_type,
    c.max_length,
    c.precision,
    c.scale,
    c.is_nullable
FROM sys.tables t
JOIN sys.schemas s ON s.schema_id = t.schema_id
JOIN sys.columns c ON c.object_id = t.object_id
JOIN sys.types ty ON ty.user_type_id = c.user_type_id
WHERE t.is_ms_shipped = 0
ORDER BY t.name, c.column_id;
GO
```

Сохранить результаты в CSV/текст:

```text
/mnt/fitness_sql/output/schema_inventory.csv
/mnt/fitness_sql/logs/schema_inventory.txt
```

Ожидаемые признаки 1C-базы:

```text
Config
Params
Files
_Reference...
_Document...
_InfoRg...
_AccumRg...
_Enum...
```

Важно: прямые SQL-таблицы 1C имеют технические имена. Нельзя угадывать, что `_Reference123` — это клиент, без проверки содержимого и связей.

---

## 11. Найти таблицы-кандидаты для бизнес-сущностей

Нужно найти физические таблицы, соответствующие этим сущностям:

| Бизнес-сущность | Что нужно получить |
|---|---|
| Клиент | внутренний ID, ФИО, дата создания карточки, ссылка/ref |
| Контактная информация | телефоны, email, связь с клиентом |
| Абонемент / клубная карта / продажа услуги | дата продажи, окончание, статус, срок, клиент |
| Продажа / чек / реализация | первая продажа клиента |
| Бронь | признак актуальной брони, дата/статус |
| Пластиковая карта | номер карты, связь с клиентом |

### 11.1. Метод поиска таблиц

1. Сначала получить список самых больших и самых «похожих» таблиц:
   - `_Reference%` — справочники;
   - `_Document%` — документы;
   - `_InfoRg%` — регистры сведений;
   - `_AccumRg%` — регистры накопления;
   - `_Enum%` — перечисления.
2. Для каждой таблицы-кандидата получить:
   - количество строк;
   - список колонок;
   - 20–50 строк sample без массового dump;
   - набор уникальных/частых значений для колонок-статусов;
   - min/max дат по колонкам типа date/datetime.
3. Найти несколько известных клиентов вручную по ФИО/телефону, если заказчик может дать примеры.
4. По найденным клиентам проследить связи:
   - клиент -> контактная информация;
   - клиент -> абонементы;
   - клиент -> продажи;
   - клиент -> пластиковая карта;
   - клиент -> бронь.
5. Зафиксировать все найденные соответствия в `table_mapping.yml` и `table_mapping_report.md`.

### 11.2. Что должно попасть в `table_mapping.yml`

Пример структуры:

```yaml
source_database: FitnessRestored
cutoff_date: "2026-04-29"

entities:
  clients:
    table: "dbo._ReferenceXXX"
    ref_column: "_IDRRef"
    code_column: "_Code"
    fio_column: "_Description"
    created_at_column: "..."

  contacts:
    table: "dbo._InfoRgYYY"
    owner_ref_column: "..."
    type_column: "..."
    value_column: "..."

  subscriptions:
    table: "dbo._DocumentZZZ_or__InfoRgZZZ"
    client_ref_column: "..."
    sale_date_column: "..."
    end_date_column: "..."
    status_column: "..."
    product_ref_column: "..."

  sales:
    table: "dbo._DocumentAAA_or__AccumRgAAA"
    client_ref_column: "..."
    sale_date_column: "..."

  bookings:
    table: "dbo._DocumentBBB_or__InfoRgBBB"
    client_ref_column: "..."
    status_column: "..."
    active_condition: "..."

  plastic_cards:
    table: "dbo._ReferenceCCC_or__InfoRgCCC"
    client_ref_column: "..."
    card_number_column: "..."
```

До заполнения `table_mapping.yml` нельзя переходить к финальной выгрузке, потому что иначе будет риск взять неверные таблицы 1C.

---

## 12. Построить промежуточные staging-наборы

После сопоставления таблиц нужно не сразу писать XLSX, а сначала собрать нормализованный промежуточный датасет.

Рекомендуемые staging-наборы:

```text
stg_clients
stg_client_contacts
stg_subscriptions
stg_sales
stg_bookings
stg_plastic_cards
mart_active_clients
```

### 12.1. `stg_clients`

Поля:

```text
client_ref
client_id
client_fio
client_created_at
raw_source_table
```

### 12.2. `stg_client_contacts`

Поля:

```text
client_ref
phone_raw
email_raw
contact_type
raw_value
```

Правила:

```text
Телефоны в итоговом XLSX оставлять как в 1C.
Несколько телефонов клиента объединять через запятую.
Все email клиента объединять через запятую.
Нормализацию телефонов использовать только для служебной проверки дублей, не для выгрузки.
```

### 12.3. `stg_subscriptions`

Поля:

```text
client_ref
subscription_ref
subscription_name
sale_date
end_date
status
is_active
duration_days
```

`duration_days` считать по разнице между `end_date` и `sale_date`.

### 12.4. `stg_sales`

Поля:

```text
client_ref
sale_ref
sale_date
amount
```

Нужно получить первую продажу клиента:

```text
first_sale_date = MIN(sale_date) по клиенту
```

### 12.5. `stg_bookings`

Поля:

```text
client_ref
booking_ref
booking_date
booking_status
is_active_booking
```

### 12.6. `stg_plastic_cards`

Поля:

```text
client_ref
plastic_card_number
card_status
issue_date
```

### 12.7. `mart_active_clients`

Это главный нормализованный набор перед XLSX.

Поля:

```text
client_ref
client_id
client_fio
phones
email
first_sale_date
client_created_at
create_date
create_date_source
active_subscription_ref
active_subscription_sale_date
active_subscription_end_date
active_subscription_duration_days
is_short_duration_active
days_to_end
has_active_booking
plastic_card_number
funnel
funnel_step
budget
manager
dedupe_status
validation_status
```

`mart_active_clients` можно хранить как:

1. SQL temp/permanent table в restored DB; или
2. CSV в `/mnt/fitness_sql/tmp/mart_active_clients.csv`; или
3. SQLite/parquet промежуточный файл.

Для 30 тысяч клиентов достаточно CSV, но для удобства проверки лучше сначала собрать SQL view/table, а потом выгружать в CSV/XLSX.

---

## 13. Бизнес-правила отбора и этапов

### 13.1. Дата расчета

В конфиге должна быть явная дата:

```yaml
run:
  cutoff_date: "2026-04-29"
```

Для текущего backup утвержденный `cutoff_date` — дата backup-а, то есть `2026-04-29`.

### 13.2. Критерий «действующий клиент»

Клиент попадает в основную выгрузку, если:

```text
1. Клиент уникальный после дедупликации.
2. У клиента есть активный/открытый абонемент на cutoff_date.
3. Включать все активные абонементы/продукты на дату, включая 1 день, 7 дней,
   пробные дни и другие короткие активные продукты. `duration_days` сохранять
   как audit-поле, но не использовать как фильтр исключения.
4. Клиент относится к сегменту действующих клиентов; `Бронь` применяется к любому клиенту внутри этого сегмента, если у него стоит флаг брони.
5. Если флаг `Бронь` найден у клиента без действующего абонемента, такого клиента вынести в `booking_without_active_subscription_report.csv` и не включать в основной XLSX без отдельного решения.
6. У клиента есть ФИО и телефон; если чего-то нет, клиента все равно пытаться выгрузить, но подсветить в отчете.
```

Базовая логика активного абонемента:

```text
subscription.start_date <= cutoff_date
AND subscription.end_date >= cutoff_date
AND subscription.status IN active_statuses
```

Параметры в `stage_rules.yml`:

```yaml
active_clients:
  include_short_active_products: true
  duration_source: "end_date - sale_date, audit only"
  active_statuses: []
```

Реальные значения `active_statuses` не задавать заранее. Их нужно получить из восстановленной базы по фактическим данным и согласовать отдельно.

### 13.3. Если у клиента несколько активных абонементов

По бизнес-правилу у клиента может быть только один действующий абонемент, действующие абонементы не должны пересекаться.

Если найдено несколько действующих абонементов:

```text
1. Клиента вынести в multiple_active_subscriptions_report.csv.
2. Не склеивать и не выбирать абонемент молча.
3. В validation_report.md показать количество таких случаев.
4. Решение по таким клиентам принимать отдельно после ручной проверки.
```

### 13.4. Приоритет этапов воронки

Воронка у всех строк:

```text
Действующие клиенты
```

Этапы:

```text
60-31 день до окончания
30-8 дней до окончания
7-0 день до окончания
Бронь
Действующие клиенты
```

Порядок приоритета:

```text
1. Бронь
2. 60-31 день до окончания
3. 30-8 дней до окончания
4. 7-0 день до окончания
5. Действующие клиенты
```

Алгоритм:

```python
if has_active_booking:
    funnel_step = "Бронь"
elif 31 <= days_to_end <= 60:
    funnel_step = "60-31 день до окончания"
elif 8 <= days_to_end <= 30:
    funnel_step = "30-8 дней до окончания"
elif 0 <= days_to_end <= 7:
    funnel_step = "7-0 день до окончания"
else:
    funnel_step = "Действующие клиенты"
```

`Бронь` имеет приоритет над любым количеством дней до окончания.

### 13.5. Этап `Разблокирование клиента`

Такого этапа в текущей задаче нет.

```text
Не добавлять "Разблокирование клиента" в XLSX, stage_rules.yml, validation и мини-тест.
Допустимые этапы только:
- 60-31 день до окончания
- 30-8 дней до окончания
- 7-0 день до окончания
- Бронь
- Действующие клиенты
```

### 13.6. `budget`

В основной XLSX:

```text
budget = 0
```

Не ставить `100`. Не оставлять пустую ячейку.

### 13.7. `create_date`

Приоритет:

```text
1. Первая продажа клиента в базе.
   Считать любую продажу, по которой клиент появился в базе: абонемент,
   7 дней, 1 день, пробный день и т.д.
2. Не подменять эту дату датой посещения из CSV.
3. Если продаж нет — не использовать дату создания карточки клиента как
   нормальную замену; выгрузить насколько возможно и вынести клиента в
   missing_sales_report.csv / missing_required_fields.csv.
```

---

## 14. Дедупликация клиентов

Заказчик предупредил, что в 1C могут быть дубли. Правило: дубли определять только по связке `ФИО + телефон`, без дополнительных эвристик.

### 14.1. Нормализация для поиска дублей

Сформировать поля:

```text
normalized_fio
normalized_phones_set
```

Нормализация ФИО:

```text
trim;
убрать двойные пробелы;
привести к единому регистру для сравнения;
не менять исходное ФИО для выгрузки.
```

Нормализация телефонов:

```text
только для ключа дубля привести телефон к стабильному виду сравнения;
в итоговый XLSX писать телефон как в 1C;
не использовать email, дату рождения, пластиковые карты, похожесть ФИО или другие признаки для автоматического склеивания.
```

### 14.2. Что склеивать автоматически

Автоматически можно склеивать только:

```text
одинаковые normalized_fio + одинаковый normalized_phones_set.
```

### 14.3. Что не склеивать молча

В `duplicates_report.csv` выносить:

```text
одинаковый телефон, но разные ФИО;
одинаковое ФИО, но разные телефоны;
любые похожие записи, которые не совпали по точному правилу ФИО + телефон.
```

### 14.4. Приоритет записи при склейке

Если записи считаются дублями:

```text
1. Оставить одну запись с меньшим/первым client_id.
2. Телефоны и email объединить уникальным списком, но значения телефонов сохранять как в 1C.
3. Пластиковые карты объединить уникальным списком через запятую.
4. Если карт несколько — вынести клиента в multiple_cards_report.csv.
```

---

## 15. Менеджеры

Менеджеры не вытаскиваются из 1C. Для тестовой выгрузки использовать временный список:

```text
A1
A2
A3
```

Филиал для менеджера не нужен.

Создать конфиг:

```text
/mnt/fitness_sql/work/config/managers.yml
```

Пример:

```yaml
managers:
  - "A1"
  - "A2"
  - "A3"
```

Распределение должно быть детерминированным, а не случайным:

```python
manager = managers[stable_hash(client_id) % len(managers)]
```

Так при повторном запуске тот же клиент получит того же менеджера, а вся выборка распределится примерно по 1/3 на каждого менеджера.

---

## 16. Генерация двух XLSX-файлов

### 16.1. Основной файл `Копия Импорт_заявки.xlsx`

Скрипт `build_fitbase_xlsx.py` должен:

1. Открыть исходный шаблон.
2. Проверить заголовки строки 1:

```text
client_id, phone, client_fio, email, funnel, funnel_step, budget, create_date, manager
```

3. Проверить русские заголовки строки 2.
4. Очистить пример в строке 3.
5. Записать `mart_active_clients` с 3-й строки.
6. Не добавлять лишние колонки.
7. Не менять порядок колонок.
8. Дату `create_date` писать как дату Excel или строку в формате, который Fitbase точно принимает после мини-теста.
9. `budget` писать числом `0`.
10. Сохранить в `/mnt/fitness_sql/output/`.

Пример соответствия:

| XLSX поле | Источник в `mart_active_clients` |
|---|---|
| `client_id` | `client_id` |
| `phone` | `phones` |
| `client_fio` | `client_fio` |
| `email` | `email` |
| `funnel` | constant `Действующие клиенты` |
| `funnel_step` | `funnel_step` |
| `budget` | constant `0` |
| `create_date` | `create_date` |
| `manager` | `manager` |

### 16.2. Файл пластиковых карт

Скрипт должен:

1. Открыть шаблон `Пластиковая карта.xlsx`.
2. Проверить заголовки:

```text
телефон, фио, номер пластиковой карты
```

3. Записывать данные со 2-й строки.
4. Включать всех клиентов, которые попали в основной XLSX.
5. Для клиентов без карты оставлять `номер пластиковой карты` пустым и записывать клиента в `missing_cards_report.csv`.
6. Если у клиента несколько активных/unmarked карт, записывать все номера карт в одну ячейку через запятую и записывать клиента в `multiple_cards_report.csv`.

Пример соответствия:

| XLSX поле | Источник в `mart_active_clients` |
|---|---|
| `телефон` | `phones` |
| `фио` | `client_fio` |
| `номер пластиковой карты` | `plastic_card_number` |

---

## 17. Валидация перед передачей Fitbase

Создать скрипт:

```text
/mnt/fitness_sql/work/scripts/validate_outputs.py
```

### 17.1. Проверки основного XLSX

Обязательные проверки:

```text
1. Заголовки полностью совпадают с шаблоном.
2. Нет лишних колонок.
3. Количество строк совпадает с mart_active_clients после фильтрации.
4. Нет дублей по client_id.
5. Нет дублей по правилу `ФИО + телефон`.
6. Пустые phone разрешены только как data-quality проблема: строку выгрузить, клиента записать в `missing_required_fields.csv`.
7. Пустые client_fio разрешены только как data-quality проблема: строку выгрузить, клиента записать в `missing_required_fields.csv`.
8. Нет пустых funnel.
9. Нет пустых funnel_step.
10. Пустой create_date разрешен только как data-quality проблема: строку выгрузить, клиента записать в `missing_required_fields.csv`.
11. funnel везде = Действующие клиенты.
12. funnel_step входит только в разрешенный список.
13. budget везде = 0.
14. Все клиенты с has_active_booking = true имеют funnel_step = Бронь.
15. Границы этапов по days_to_end соблюдены.
16. Все телефоны в одной ячейке разделены запятой.
17. Нет клиентов с несколькими действующими абонементами без записи в `multiple_active_subscriptions_report.csv`.
18. Нет клиентов с бронью без действующего абонемента без записи в `booking_without_active_subscription_report.csv`.
```

Разрешенные `funnel_step`:

```text
Бронь
60-31 день до окончания
30-8 дней до окончания
7-0 день до окончания
Действующие клиенты
```

Границы:

```text
60-31: 31 <= days_to_end <= 60
30-8:   8 <= days_to_end <= 30
7-0:    0 <= days_to_end <= 7
```

### 17.2. Проверки пластиковых карт

```text
1. Заголовки совпадают с шаблоном.
2. Пустые телефоны разрешены только если этот же клиент отражен в `missing_required_fields.csv`.
3. Пустые ФИО разрешены только если этот же клиент отражен в `missing_required_fields.csv`.
4. Номера карт не дублируются, если карта должна быть уникальной.
5. Все клиенты из основного XLSX попали во второй XLSX.
6. Клиенты без карты отражены в missing_cards_report.csv.
7. Клиенты с несколькими картами отражены в multiple_cards_report.csv.
```

### 17.3. Отчет `validation_report.md`

Отчет должен содержать:

```text
Дата запуска
cutoff_date
backup file name и размер
DatabaseName
число таблиц в restored DB
количество кандидатов действующих клиентов до дедупликации
количество после дедупликации
количество строк в основном XLSX
количество строк в XLSX пластиковых карт
распределение по funnel_step
количество клиентов без телефона
количество клиентов без ФИО
количество клиентов без первой продажи
количество клиентов без create_date
количество клиентов без пластиковой карты
количество клиентов с несколькими действующими абонементами
количество клиентов с несколькими пластиковыми картами
количество клиентов с бронью без действующего абонемента
количество дублей
список оставшихся технических вопросов по данным
вердикт: PASS / FAIL
```

---

## 18. Мини-тест загрузки в Fitbase

Перед полной выгрузкой сделать маленький тестовый пакет:

```text
output/mini_fitbase_active_clients_import_zayavki_YYYYMMDD.xlsx
output/mini_fitbase_active_clients_plastic_cards_YYYYMMDD.xlsx
```

Состав мини-теста:

```text
5–10 клиентов с этапом Бронь;
5–10 клиентов с этапом 60-31 день до окончания;
5–10 клиентов с этапом 30-8 дней до окончания;
5–10 клиентов с этапом 7-0 день до окончания;
5–10 клиентов с этапом Действующие клиенты;
несколько клиентов с двумя телефонами;
несколько клиентов с email;
несколько клиентов с пластиковыми картами;
несколько клиентов без пластиковых карт;
несколько клиентов без первой продажи, если такие найдены.
```

Что проверить в Fitbase:

```text
1. Импорт принимает структуру основного XLSX.
2. Fitbase корректно читает первые две строки основного шаблона.
3. Телефоны через запятую не ломают импорт.
4. `budget = 0` принимается.
5. create_date принимается в выбранном формате.
6. Воронка Действующие клиенты создается/находится корректно.
7. Этапы создаются/находятся корректно.
8. Менеджеры распознаются.
9. Пластиковые карты загружаются и связываются как ожидается.
```

Если Fitbase возвращает ошибки, менять только форматную часть, а бизнес-алгоритм менять только после согласования.

---

## 19. Полная тестовая выгрузка действующих клиентов

После успешного мини-теста:

1. Запустить extraction на всех действующих клиентах.
2. Сформировать `mart_active_clients`.
3. Прогнать дедупликацию.
4. Сформировать основной XLSX.
5. Сформировать XLSX пластиковых карт.
6. Прогнать `validate_outputs.py`.
7. Если `validation_report.md` = `PASS`, передать пакет заказчику/Fitbase.

Пакет передачи:

```text
fitbase_active_clients_import_zayavki_YYYYMMDD.xlsx
fitbase_active_clients_plastic_cards_YYYYMMDD.xlsx
validation_report.md
stage_distribution.csv
duplicates_report.csv
missing_required_fields.csv
missing_sales_report.csv
missing_cards_report.csv
multiple_active_subscriptions_report.csv
multiple_cards_report.csv
booking_without_active_subscription_report.csv
table_mapping_report.md
```

---

## 20. Контрольные критерии готовности

Работа считается выполненной, если:

```text
1. SQL Server backup восстановлен в тестовую базу FitnessRestored.
2. База ONLINE.
3. Получен список таблиц и колонок.
4. Найдены и подтверждены таблицы клиентов, контактов, абонементов, продаж, брони и пластиковых карт.
5. Создан table_mapping.yml.
6. Создан mart_active_clients.
7. В mart_active_clients только уникальные действующие клиенты.
8. Клиенты без ФИО/телефона/create_date не потеряны: они выгружены насколько возможно и отдельно перечислены в `missing_required_fields.csv`.
9. Этапы воронки рассчитаны по согласованному алгоритму.
10. Бронь имеет приоритет над этапами по дням.
11. `budget` везде равен `0`.
12. `create_date` = первая продажа клиента в базе по любому продукту/услуге; дата создания карточки не используется как нормальная замена, клиенты без продажи попадают в отчет проблем.
13. Основной XLSX соответствует шаблону.
14. XLSX пластиковых карт соответствует шаблону и содержит всех клиентов из основного XLSX.
15. Валидационный отчет показывает PASS либо содержит конкретный список проблем.
16. Заказчику передан полный пакет файлов.
```

---

## 21. Что еще нужно выяснить по данным после restore

Бизнес-правила выше уже согласованы. После восстановления базы нужно выяснить технические соответствия в данных:

1. Какие реальные статусы/поля в 1C соответствуют активному/открытому абонементу.
2. В какой таблице и каком поле хранится признак `Бронь`.
3. Где в данных находятся `sale_date` и `end_date` абонемента, по которым считается `duration_days = end_date - sale_date`.
4. Где хранится активная пластиковая карта и как отличить активную карту от неактивной.
5. Какой формат даты `create_date` Fitbase точно принимает: Excel-date или строка `YYYY-MM-DD` / `DD.MM.YYYY`.

Эти пункты решаются через schema discovery, samples и мини-тест загрузки, а не через изменение бизнес-правил.

---

## 22. Риски и защита

| Риск | Как защищаемся |
|---|---|
| Диск 200 GB окажется тесным | Не копировать backup несколько раз, не делать full DB dump, не запускать полный DBCC CHECKDB до выгрузки |
| SQL Server съест всю RAM | `MSSQL_MEMORY_LIMIT_MB=28672` и Docker `--memory=34g` |
| Открытый SQL Server порт наружу | Проброс только `127.0.0.1:1433` или SSH tunnel |
| Неверно сопоставлены таблицы 1C | Обязательный `schema_inventory.csv`, samples, примеры клиентов и `table_mapping_report.md` |
| Статусы абонементов определены неверно | Выгрузить список фактических статусов из базы и настроить `active_statuses` только после проверки данных |
| Бронь не найдена или найдена неверно | Найти фактическое поле/таблицу брони и проверить на клиентах-примерах, не угадывать поле |
| У клиента найдено несколько действующих абонементов | Не выбирать абонемент молча, вынести клиента в `multiple_active_subscriptions_report.csv` |
| Дубли склеены слишком агрессивно | Склеивать только по правилу `ФИО + телефон`, все похожие случаи оставлять отдельными и писать в отчет |
| Fitbase не принимает формат даты/телефона | Сначала мини-тест, потом полная выгрузка |
| У клиента несколько пластиковых карт | Записать все активные/unmarked номера карт через запятую, вынести клиента в `multiple_cards_report.csv` |

---

## 23. Рекомендуемый порядок выполнения одним списком

```text
1. Поднять VPS 200 GB / 40 GB RAM.
2. Проверить свободное место: df -h.
3. Создать /mnt/fitness_sql структуру папок.
4. Скопировать Fitnes.bak один раз.
5. Сверить размер/checksum backup.
6. Поднять SQL Server Developer container с лимитом RAM.
7. Повторить HEADERONLY / FILELISTONLY / VERIFYONLY.
8. Восстановить FitnessRestored через RESTORE DATABASE ... WITH MOVE.
9. Проверить, что база ONLINE.
10. Получить список таблиц и колонок через sys.tables/sys.columns.
11. Найти таблицы 1C-кандидаты: _Reference, _Document, _InfoRg, _AccumRg, _Enum.
12. Найти таблицы клиентов, контактов, абонементов, продаж, брони, пластиковых карт.
13. Зафиксировать table_mapping.yml.
14. Собрать staging-наборы.
15. Собрать mart_active_clients.
16. Применить дедупликацию.
17. Применить правила активных клиентов и этапов.
18. Назначить менеджеров.
19. Сформировать основной XLSX по шаблону.
20. Сформировать XLSX пластиковых карт по шаблону.
21. Прогнать validate_outputs.py.
22. Сформировать validation_report.md и вспомогательные CSV.
23. Сделать мини-тест загрузки в Fitbase.
24. По результатам мини-теста исправить только форматные проблемы.
25. Сформировать полную тестовую выгрузку.
26. Передать заказчику/Fitbase полный пакет файлов и отчетов.
```

---

## 24. Технические источники для проверки подхода

1. Microsoft SQL Server restore database to a new location / `WITH MOVE`:  
   https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-database-to-a-new-location-sql-server

2. Microsoft SQL Server `sys.tables` catalog view:  
   https://learn.microsoft.com/en-us/sql/relational-databases/system-catalog-views/sys-tables-transact-sql

3. Microsoft SQL Server Linux/container environment variables, включая `MSSQL_MEMORY_LIMIT_MB`:  
   https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-configure-environment-variables

4. Microsoft SQL Server Linux containers:  
   https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-configure

5. Microsoft SQL Server restore older database to newer version:  
   https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/restore-a-database-backup-using-ssms

6. SQL Server 2022 editions and Express database size limit:  
   https://learn.microsoft.com/en-us/sql/sql-server/editions-and-components-of-sql-server-2022

7. 1C:Enterprise 8 data structure:  
   https://1c-dn.com/library/data_structure_in_1c_enterprise_8/

8. 1C:Enterprise platform data saving structure in DBMS:  
   https://kb.1ci.com/1C_Enterprise_Platform/FAQ/Administration/DBMS/1C_Enterprise_Platform_data_saving_structure_in_the_DBMS/
