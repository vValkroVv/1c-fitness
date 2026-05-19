# 1C Fitness → Fitbase. Part 2: пошаговый implementation plan для доработки выгрузки и трех воронок

Дата подготовки плана: 2026-05-16 / 2026-05-17  
Рабочий контур по текущему архиву: `/root/workspace/1c-fitness`  
Источник данных: восстановленная база SQL Server/Azure SQL Edge `FitnessRestored` из `data/Fitnes.bak`  
Дата основного среза: `2026-04-29`  
Даты эксперимента пятница-понедельник: `2026-04-24` -> `2026-04-27`

---

## 0. Что уже известно и что НЕ нужно делать заново

Уже выполнено и подтверждено предыдущими шагами:

1. `Fitnes.bak` — валидный Microsoft SQL Server backup.
2. Backup проверен через:
   - `RESTORE HEADERONLY`;
   - `RESTORE FILELISTONLY`;
   - `RESTORE VERIFYONLY`.
3. База восстановлена как `FitnessRestored`.
4. База `FitnessRestored` находится в состоянии `ONLINE`.
5. Восстановленная база содержит 1C-структуру:
   - `2503` user tables;
   - `19421` user columns;
   - таблицы вида `_Reference*`, `_Document*`, `_InfoRg*`, `_AccumRg*`.
6. Построена первая версия pipeline для воронки `Действующие клиенты`.
7. На дату `2026-04-29` старая версия pipeline дала:
   - `10,796` строк действующих клиентов;
   - `117` клиентов на этапе `Бронь`;
   - `471` клиентов с несколькими активными абонементами;
   - `7,570` клиентов с несколькими пластиковыми картами;
   - `11` клиентов без телефона;
   - `243` клиента без карты.
8. Предыдущая выгрузка прошла техническую валидацию `PASS`, но по новой инструкции ее нужно доработать.

Повторное восстановление backup-а **не требуется**, если на сервере база `FitnessRestored` уже доступна. Повторять restore нужно только если контейнер/данные базы удалены.

### 0.1. Проверенные файлы от заказчика

Перед реализацией Part 2 нужно обязательно разобрать уже проверенные файлы из
repo root:

```text
output/splits/checked/fitbase_active_clients_import_zayavki_20260429__05_tolko_neskolko_abonementov(проверено).xlsx
output/splits/checked/fitbase_active_clients_import_zayavki_20260429__07_tolko_net_telefona(проверено).xlsx
output/splits/checked/fitbase_active_clients_plastic_cards_20260429__02_tolko_neskolko_kart (проверено).xlsx
```

Что нужно извлечь:

1. Из файла `05_tolko_neskolko_abonementov(проверено).xlsx`:
   - комментарии по нескольким абонементам;
   - финальные даты продажи/активации/окончания, если они заполнены;
   - случаи, где проверка указывает ошибку системы, смену владельца,
     модификаторы или помеченные на удаление продажи;
   - кандидаты для `config/subscription_overrides.csv`.
2. Из файла `07_tolko_net_telefona(проверено).xlsx`:
   - подтверждение, что в проверенных строках телефонов нет;
   - эти строки не нужно пытаться автоматически заполнить из `.bak`.
3. Из файла `02_tolko_neskolko_kart (проверено).xlsx`:
   - выбранные карты из добавленной проверочной колонки;
   - сверить, что выбранная карта совпадает с правилом последней карты
     `issue_date DESC, card_ref DESC`;
   - если найдутся расхождения, вынести их в `card_selection_report.csv` и
     отдельный override/decision report.

Результат разбора checked-файлов сохранить в:

```text
output/part2_20260429/reports/checked_review_summary.md
output/part2_20260429/reports/checked_subscription_decisions.csv
output/part2_20260429/reports/checked_card_decisions.csv
output/part2_20260429/reports/checked_missing_phone_confirmations.csv
```

---

## 1. Финальный результат, который нужно получить

Нужно доработать pipeline так, чтобы он строил **три взаимно непересекающиеся воронки Fitbase**:

1. `Действующие клиенты`
2. `Новые заявки`
3. `Реактивация`

По каждой воронке нужно получить **два XLSX-файла**:

1. основной импорт клиентов/заявок по шаблону `task-desc/Копия Импорт_заявки.xlsx`;
2. импорт пластиковых карт по шаблону `task-desc/Пластиковая карта.xlsx`.

Итого финальные XLSX:

```text
output/part2_20260429/fitbase_active_clients_import_zayavki_20260429__deystvuyushchie_klienty.xlsx
output/part2_20260429/fitbase_active_clients_plastic_cards_20260429__deystvuyushchie_klienty.xlsx

output/part2_20260429/fitbase_active_clients_import_zayavki_20260429__novye_zayavki.xlsx
output/part2_20260429/fitbase_active_clients_plastic_cards_20260429__novye_zayavki.xlsx

output/part2_20260429/fitbase_active_clients_import_zayavki_20260429__reaktivatsiya.xlsx
output/part2_20260429/fitbase_active_clients_plastic_cards_20260429__reaktivatsiya.xlsx
```

Также нужно получить воспроизводимые stage/CSV/report-артефакты:

```text
output/part2_20260429/staging/
output/part2_20260429/csv/
output/part2_20260429/reports/
output/part2_shift_20260424_to_20260427/
docs/part2_*.md
logs/part2_*.txt
```

Минимальный набор отчетов:

```text
validation_report.md
funnel_distribution.csv
stage_distribution_by_funnel.csv
manager_distribution_by_club.csv
missing_phone_report.csv
missing_card_report.csv
missing_club_report.csv
multiple_subscriptions_report.csv
subscription_selection_report.csv
subscription_overrides_report.csv
multiple_cards_report.csv
card_selection_report.csv
product_classification_preflight.csv
product_classification_report.csv
product_classification_review_report.csv
club_discovery_report.md
active_diff_vs_previous_export.csv
cutoff_shift_comparison_report.md
```

Финальный критерий: `validation_report.md` должен иметь verdict `PASS`, а все спорные случаи должны быть либо автоматически разрешены по описанному правилу, либо отражены в отчетах.

---

## 2. Главные изменения относительно первой версии pipeline

### 2.1. Воронка `Действующие клиенты`

Было:

```text
Действующие клиенты + этап Бронь с приоритетом выше даты окончания
```

Должно стать:

```text
Действующие клиенты без отдельного этапа Бронь
```

Этапы строго:

```text
60-31 день до окончания
30-8 дней до окончания
7-0 день до окончания
Действующие клиенты
```

Правило:

1. Берем клиентов, у которых на дату среза есть действующий **полноценный абонемент**.
2. Выбираем один финальный действующий абонемент.
3. Этап считаем только по `end_date` выбранного абонемента.
4. `Бронь` полностью убрать как этап.
5. Клиентов, которые раньше попадали в `Бронь`, перераспределить по обычным этапам.

### 2.2. Воронка `Новые заявки`

Название:

```text
Новые заявки
```

Этап:

```text
Неразобранные
```

Кого включать:

1. Клиент есть в базе 1C.
2. Клиент **ни разу не покупал полноценный абонемент**.
3. У клиента могли быть гостевой день, гостевая неделя, пробный день, короткий тестовый продукт, разовые визиты или другие не-абонементные продажи.
4. Клиент не должен пересекаться с `Действующие клиенты` и `Реактивация`.

Уточнение от заказчика по `create_date`: для таких клиентов нужно ставить дату
первого тестового/гостевого продукта — то есть дату, когда клиент впервые попал
в базу с этим продуктом. В текущей постановке заказчик явно называл тестовыми
примерами `гостевой день` и `гостевая неделя`. Остальные пробные/короткие
продукты считать кандидатами на тестовые до ручной проверки классификации
продуктов.

### 2.3. Воронка `Реактивация`

Название:

```text
Реактивация
```

Кого включать:

1. У клиента раньше был полноценный абонемент.
2. На дату среза у клиента нет действующего полноценного абонемента.
3. Нужно выбрать последний завершившийся полноценный абонемент.
4. Этап считается по количеству дней после окончания последнего абонемента.

Этапы строго:

```text
1-6 дней
7-29 дней
30-59 дней
60-89 дней
более 90 дней
```

---

## 3. Подготовить рабочее окружение на сервере

### 3.1. Зайти на сервер и перейти в workspace

```bash
cd /root/workspace/1c-fitness
pwd
git status --short
```

### 3.2. Зафиксировать текущий baseline перед изменениями

```bash
mkdir -p docs logs output/archive_before_part2
cp -a output/fitbase_active_clients_import_zayavki_20260429.xlsx output/archive_before_part2/ 2>/dev/null || true
cp -a output/fitbase_active_clients_plastic_cards_20260429.xlsx output/archive_before_part2/ 2>/dev/null || true
cp -a output/final_active_clients_20260429.csv output/archive_before_part2/ 2>/dev/null || true
cp -a output/validation_report.md output/archive_before_part2/validation_report_before_part2.md 2>/dev/null || true
cp -a output/stage_distribution.csv output/archive_before_part2/stage_distribution_before_part2.csv 2>/dev/null || true
cp -a output/manager_distribution.csv output/archive_before_part2/manager_distribution_before_part2.csv 2>/dev/null || true
```

Создать лог начала работ:

```bash
cat > docs/part2_00_start.md <<'EOF'
# Part 2 start

Goal: rebuild 1C Fitness -> Fitbase pipeline for 3 funnels:
- Действующие клиенты
- Новые заявки
- Реактивация

Baseline cutoff: 2026-04-29
Shift experiment: Friday 2026-04-24 -> Monday 2026-04-27
EOF
```

### 3.3. Проверить, что SQL-контейнер и база доступны

```bash
docker ps --filter name=mssql-fitness
scripts/sqlcmd.sh -b -Q "SELECT @@VERSION AS version;"
scripts/sqlcmd.sh -b -Q "SELECT name, state_desc FROM sys.databases WHERE name = N'FitnessRestored';"
scripts/sqlcmd.sh -b -Q "USE FitnessRestored; SELECT COUNT(*) AS user_tables FROM sys.tables WHERE is_ms_shipped = 0;"
```

Ожидаемо:

```text
FitnessRestored ONLINE
user_tables около 2503
```

Если база отсутствует или не `ONLINE`, не начинать Part 2. Сначала восстановить базу по уже существующим шагам `docs/step_08_restore_database.md` и `docs/step_09_post_restore_access_check.md`.

---

## 4. Обновить конфиги проекта

### 4.1. Создать новую структуру конфигов

Создать/обновить:

```text
config/part2.yml
config/managers_by_club.yml
config/product_classification.yml
config/subscription_overrides.csv
config/card_selection_rules.yml
config/club_normalization.yml
```

Команда:

```bash
mkdir -p config
```

### 4.2. `config/part2.yml`

Содержимое:

```yaml
run:
  source_database: FitnessRestored
  baseline_cutoff_date: "2026-04-29"
  shift_experiment_friday_cutoff_date: "2026-04-24"
  shift_experiment_monday_cutoff_date: "2026-04-27"
  backup_finish_at: "2026-04-29 23:57:02"
  sql_1c_year_offset: 2000
  output_root: "output/part2_20260429"
  shifted_output_root: "output/part2_shift_20260424_to_20260427"

funnels:
  active:
    name: "Действующие клиенты"
    allowed_steps:
      - "60-31 день до окончания"
      - "30-8 дней до окончания"
      - "7-0 день до окончания"
      - "Действующие клиенты"
    remove_booking_stage: true

  new_applications:
    name: "Новые заявки"
    allowed_steps:
      - "Неразобранные"

  reactivation:
    name: "Реактивация"
    allowed_steps:
      - "1-6 дней"
      - "7-29 дней"
      - "30-59 дней"
      - "60-89 дней"
      - "более 90 дней"

selection:
  active_subscription_order:
    - "manual_override"
    - "end_date DESC"
    - "start_date DESC"
    - "sale_date DESC"
    - "subscription_ref DESC"
  reactivation_subscription_order:
    - "manual_override"
    - "end_date DESC"
    - "start_date DESC"
    - "sale_date DESC"
    - "subscription_ref DESC"
  card_order:
    - "issue_date DESC"
    - "card_ref DESC"

validation:
  require_no_client_overlap_between_funnels: true
  require_no_booking_stage: true
  require_no_a_managers: true
  allow_missing_phone: true
  allow_missing_card: true
  allow_missing_club_with_report: true
```

### 4.3. `config/managers_by_club.yml`

Содержимое:

```yaml
clubs:
  "Коммунальная, 20":
    - "Пеуна Анастасия Ивановна"
    - "Васильева Яна Денисовна"
    - "Абраамян Татьяна Викторовна"
    - "Пилия Анастасия Артуровна"

  "Лососинское шоссе, 26":
    - "Седунова Анна Сергеевна"
    - "Фёдорова Надежда Сергеевна"
    - "Мартынова Дарья Дмитриевна"

  "Промышленная, 10":
    - "Васьковская Виктория Петровна"
    - "Лисовская Екатерина Александровна"
    - "Яковлева Александра Владимировна"

  "Ровио, 3":
    - "Соколова Анастасия Александровна"
    - "Анухина Кристина Алексеевна"
    - "Петрова Полина Владимировна"
    - "Фёдорова Милана Андреевна"
```

Правило назначения менеджера:

```text
manager = managers_by_club[normalized_club][sha256(client_id) % len(managers_by_club[normalized_club])]
```

Если клуб не найден:

1. `manager` оставить пустым или поставить утвержденный fallback только после согласования.
2. Клиента обязательно записать в `missing_club_report.csv`.
3. В `validation_report.md` указать количество клиентов без клуба по каждой воронке.

### 4.4. `config/product_classification.yml`

Цель: явно определить, какие продукты считаются полноценными абонементами, а какие — гостевыми/пробными/короткими.

Начальный вариант правил:

```yaml
classification_version: 1

full_subscription:
  include_name_keywords:
    - "абонемент"
    - "мульти"
    - "ультра"
    - "членств"
  min_duration_days: 30
  exclude_name_keywords:
    - "гост"
    - "гостевой"
    - "проб"
    - "пробный"
    - "тест"
    - "разов"
    - "1 день"
    - "один день"
    - "7 дней"
    - "неделя"
    - "переоформ"
    - "перенос"

trial_or_guest:
  include_name_keywords:
    - "гост"
    - "гостевой"
    - "проб"
    - "пробный"
    - "тест"
    - "разов"
    - "1 день"
    - "один день"
    - "7 дней"
    - "неделя"

manual_overrides: []
```

Важно: это только стартовое правило. Слово `замороз` нельзя использовать как
общий exclude: в базе есть полноценные абонементы вида `... заморозки в
подарок`. Отдельные продукты-заморозки нужно ловить через
`product_classification_review_report.csv` и `manual_overrides`.

Перед финальным разбиением клиентов на воронки нужно сделать обязательный
preflight по продуктам:

1. Сформировать `product_classification_preflight.csv` со всеми продуктами,
   которые автоматическое правило считает потенциально полноценными
   абонементами, тестовыми/гостевыми продуктами или спорными продуктами.
2. Отдельно сформировать `product_classification_review_report.csv` по всем
   продуктам, где классификация неочевидна или влияет на большое количество
   клиентов.
3. Дать этот список на ручную проверку перед финальным запуском.
4. После проверки добавить решения в `manual_overrides`.
5. Только после этого строить финальные воронки и XLSX.

### 4.5. `config/subscription_overrides.csv`

Создать пустой файл с колонками:

```csv
client_ref,client_id,subscription_ref,override_type,applies_to_funnel,reason,approved_by,approved_at,note
```

Где:

```text
override_type:
- force_select_subscription
- force_exclude_subscription
- force_exclude_client_from_funnel
```

Команда:

```bash
cat > config/subscription_overrides.csv <<'EOF'
client_ref,client_id,subscription_ref,override_type,applies_to_funnel,reason,approved_by,approved_at,note
EOF
```

Этот файл нужен для 471 клиентов с несколькими активными абонементами и для спорных случаев по реактивации.

### 4.6. `config/card_selection_rules.yml`

Содержимое:

```yaml
card_selection:
  include_only_unmarked: true
  require_non_empty_card_number: true
  order:
    - "issue_date DESC"
    - "card_ref DESC"
  output_one_card_only: true
  future_issue_date_policy: "do_not_exclude_by_default_report_only"
```

Правило: в итоговый XLSX карт должна попадать **одна выбранная карта**, а не список через запятую.

---

## 5. Найти и зафиксировать клуб/филиал покупки

Это критический новый блок. В текущем итоговом CSV поля клуба нет, а менеджеры `A1/A2/A3` временные. Нужно найти клуб в восстановленной базе.

### 5.1. Создать SQL для поиска справочника клубов

Создать файл:

```text
sql/part2_01_find_club_references.sql
```

Логика:

1. По всем таблицам `_Reference%`, у которых есть `_Description`, найти строки с адресами:
   - `Коммунальная`
   - `Лососинское`
   - `Промышленная`
   - `Ровио`
2. Выгрузить:
   - имя таблицы;
   - `_IDRRef`;
   - `_Code`, если есть;
   - `_Description`;
   - количество похожих строк.

Шаблон dynamic SQL:

```sql
USE [FitnessRestored];
GO

DECLARE @sql nvarchar(max) = N'';

SELECT @sql = STRING_AGG(CAST('
SELECT
    N''' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N''' AS table_name,
    CONVERT(varchar(32), _IDRRef, 2) AS ref_hex,
    CAST(_Description AS nvarchar(400)) AS description
FROM ' + QUOTENAME(SCHEMA_NAME(t.schema_id)) + N'.' + QUOTENAME(t.name) + N'
WHERE _Description LIKE N''%Коммуналь%''
   OR _Description LIKE N''%Лососин%''
   OR _Description LIKE N''%Промышлен%''
   OR _Description LIKE N''%Ровио%''
' AS nvarchar(max)), N'
UNION ALL
')
FROM sys.tables AS t
JOIN sys.columns AS c
  ON c.object_id = t.object_id
 AND c.name = N'_Description'
WHERE t.name LIKE N'_Reference%';

EXEC sp_executesql @sql;
GO
```

Запуск:

```bash
scripts/sqlcmd.sh -b -i /sql/part2_01_find_club_references.sql \
  > logs/part2_01_find_club_references.txt
```

Ожидаемый результат:

```text
Найден один или несколько справочников/таблиц, где хранятся клубы/филиалы.
```

Документировать вывод:

```text
docs/part2_01_club_discovery.md
output/part2_20260429/reports/club_reference_candidates.csv
```

### 5.2. Найти связь клуба с продажей/абонементом

После того как найден справочник клубов, нужно определить, где именно хранится ссылка на клуб:

1. В документе абонемента `dbo._Document163`.
2. В регистре абонементов `dbo._InfoRg3060`.
3. В платежном/продажном документе `dbo._Document152`.
4. В продукте `dbo._Reference72`.
5. В другом связанном документе/справочнике.

Создать SQL:

```text
sql/part2_02_find_club_links.sql
```

Логика:

1. Взять найденные `club_ref`.
2. Проверить все binary/ref-like колонки в `Document163`, `InfoRg3060`, `Document152`.
3. Посчитать, какая колонка чаще всего содержит ссылки на найденные клубы.
4. Вывести candidate columns.

Проверяемые таблицы минимум:

```text
dbo._Document163
dbo._InfoRg3060
dbo._Document152
dbo._Reference72
dbo._Reference64
```

Критерий хорошей связи:

```text
column contains club refs for a meaningful share of membership/sale rows
```

Если прямая связь найдена:

```text
subscription_ref -> normalized_club
sale_ref -> normalized_club
```

Если связь найдена только через продукт или документ продажи, это тоже допустимо, но источник нужно записать в `club_source`.

### 5.3. Сделать `club_normalization.yml`

После discovery создать маппинг:

```yaml
normalization:
  "Коммунальная, 20": "Коммунальная, 20"
  "Коммунальная 20": "Коммунальная, 20"
  "Лососинское шоссе, 26": "Лососинское шоссе, 26"
  "Лососинское 26": "Лососинское шоссе, 26"
  "Промышленная, 10": "Промышленная, 10"
  "Промышленная 10": "Промышленная, 10"
  "Ровио, 3": "Ровио, 3"
  "Ровио 3": "Ровио, 3"
```

### 5.4. Критерий завершения блока клубов

Блок считается завершенным, когда есть:

```text
output/part2_20260429/reports/club_reference_candidates.csv
output/part2_20260429/reports/club_link_candidates.csv
docs/part2_01_club_discovery.md
config/club_normalization.yml
```

И в stage можно получить поля:

```text
raw_club
normalized_club
club_source
club_ref
```

---

## 6. Расширить SQL-stage под все три воронки

Текущий `sql/06_build_staging_tables.sql` строит только `mart_active_clients`. Для новой задачи нужен stage, который содержит всю историю клиента и признаки для трех воронок.

Лучше не ломать старый файл, а создать новый:

```text
sql/part2_03_build_three_funnel_staging.sql
```

### 6.1. Входные параметры SQL

SQL должен принимать:

```text
$(cutoff_date)
$(backup_finish_at)
$(output_run_label)
```

Пример:

```bash
scripts/sqlcmd.sh -b \
  -v cutoff_date="2026-04-29" backup_finish_at="2026-04-29 23:57:02" \
  -i /sql/part2_03_build_three_funnel_staging.sql \
  > logs/part2_03_build_three_funnel_staging_20260429.txt
```

Для эксперимента пятница-понедельник обе даты должны быть до даты backup
`2026-04-29`. Использовать:

```text
пятница:    2026-04-24
понедельник: 2026-04-27
```

Stage нужно построить для обеих дат эксперимента:

```bash
scripts/sqlcmd.sh -b \
  -v cutoff_date="2026-04-24" backup_finish_at="2026-04-29 23:57:02" \
  -i /sql/part2_03_build_three_funnel_staging.sql \
  > logs/part2_03_build_three_funnel_staging_20260424.txt

scripts/sqlcmd.sh -b \
  -v cutoff_date="2026-04-27" backup_finish_at="2026-04-29 23:57:02" \
  -i /sql/part2_03_build_three_funnel_staging.sql \
  > logs/part2_03_build_three_funnel_staging_20260427.txt
```

### 6.2. Схема stage

Создать отдельную схему:

```sql
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'fitbase_part2')
    EXEC(N'CREATE SCHEMA fitbase_part2');
```

На каждый запуск удалять и пересоздавать только таблицы `fitbase_part2`, не трогая старую `fitbase_stg`.

### 6.3. Таблица `fitbase_part2.stg_clients`

Должна содержать минимум:

```text
client_ref
client_id
client_fio
client_created_at
client_marked
raw_source_table
```

Важно: добавить `client_marked`, чтобы спорные удаленные клиенты можно было анализировать в reports.

### 6.4. Таблица `fitbase_part2.stg_client_contacts`

Должна содержать:

```text
client_ref
contact_type
raw_value
normalized_value
raw_source
```

Правила:

1. Телефоны брать как раньше из `dbo._Reference64._Fld3832`.
2. Если телефонов несколько, сохранять все в stage.
3. Email брать из ранее найденного источника `dbo._InfoRg5255._Fld5257`.
4. Отсутствие телефона не блокирует экспорт.
5. Клиенты без телефона пишутся в `missing_phone_report.csv`.

### 6.5. Таблица `fitbase_part2.stg_products`

Нужно построить отдельный справочник продуктов из `dbo._Reference72` и связанных продаж/абонементов.

Колонки:

```text
product_ref
product_code
product_name
product_name_norm
observed_subscription_rows
observed_sale_rows
min_duration_days
max_duration_days
median_duration_days или avg_duration_days
is_full_subscription_candidate
is_trial_or_guest_candidate
classification_reason
needs_manual_review
```

Правила классификации:

1. `full_subscription` — полноценный абонемент.
2. `trial_or_guest` — гостевой/пробный/короткий продукт.
3. `other_sale` — прочие продажи/услуги.
4. `unknown_review_required` — продукт, по которому автоматическое правило не уверено.

Критично: новая воронка `Новые заявки` зависит от этого классификатора. Нельзя считать клиента новым, пока непонятно, был ли его продукт полноценным абонементом.

Перед финальным разбиением на воронки нужно вывести список продуктов для ручной
проверки:

```text
product_classification_preflight.csv
```

В этом списке должны быть:

1. все продукты-кандидаты в полноценные абонементы;
2. все продукты-кандидаты в тестовые/гостевые;
3. все продукты с неизвестной классификацией;
4. количество клиентов/продаж по каждому продукту;
5. минимальная/максимальная длительность, если она есть;
6. причина автоматической классификации.

Без ручного подтверждения этого списка нельзя считать финальное распределение по
воронкам закрытым.

### 6.6. Таблица `fitbase_part2.stg_subscriptions_all`

Нужно сохранить **все кандидаты абонементов**, а не только активные.

Колонки:

```text
client_ref
client_id
subscription_ref
holder_client_ref
payer_client_ref
client_role_source
product_ref
product_code
subscription_name
product_class
is_full_subscription
is_trial_or_guest
sale_date
start_date
end_date
duration_days
status
booking_status_ref
booking_status_name
doc_posted
doc_marked
register_duration_days
is_active_on_cutoff
is_finished_before_cutoff
days_to_end
days_since_end
raw_club
normalized_club
club_source
raw_source
```

Фильтры:

1. Документ должен быть проведен:

```sql
d._Posted = 0x01
```

2. Документ не должен быть помечен на удаление:

```sql
d._Marked = 0x00
```

3. Для final funnel logic использовать только `is_full_subscription = 1`.
4. Trial/guest/short products оставить в stage и reports, но они не переводят клиента в категорию покупавших полноценный абонемент.
5. Если `sale_date` позже даты среза, такой абонемент не должен влиять на воронку этого среза.

Активность:

```text
is_active_on_cutoff = start_date <= cutoff_date AND end_date >= cutoff_date AND sale_date <= cutoff_date
```

Завершение:

```text
is_finished_before_cutoff = end_date < cutoff_date AND sale_date <= cutoff_date
```

### 6.7. Таблица `fitbase_part2.stg_sales_all`

Нужно сохранить все продажи, которые могут понадобиться для:

1. `create_date`;
2. определения клуба для `Новые заявки`;
3. аудита клиентов без полноценного абонемента.

Колонки:

```text
client_ref
sale_ref
sale_date
product_ref
product_name
product_class
amount
operation_name
payment_method
raw_club
normalized_club
club_source
sale_source
```

`create_date` считать так:

1. Для клиентов воронки `Новые заявки` брать дату первого
   тестового/гостевого продукта: `first_trial_or_guest_product_date`.
2. Под тестовыми продуктами на старте понимать то, что заказчик назвал в
   постановке: `гостевой день` и `гостевая неделя`. Остальные
   пробные/короткие продукты считать кандидатами и подтверждать через
   `product_classification_preflight.csv`.
3. Если у клиента нет тестового/гостевого продукта, но есть другая
   не-абонементная продажа, брать дату первой такой продажи и записывать клиента
   в report для проверки.
4. Если у клиента нет продаж/продуктов вообще, брать `client_created_at`.
5. Источник записывать в `create_date_source`:
   - `first_trial_or_guest_product`;
   - `first_non_full_sale_requires_review`;
   - `client_created_at_no_sales`.

Это важно для воронки `Новые заявки`: там могут быть клиенты без полноценного
абонемента, у которых дата создания должна отражать первый тестовый продукт, а
поле `Дата создания *` в Fitbase обязательное.

### 6.8. Таблица `fitbase_part2.stg_plastic_cards`

Колонки:

```text
client_ref
card_ref
plastic_card_number
plastic_card_number_primary
plastic_card_number_secondary
card_status
is_unmarked
issue_date
is_future_issue_date
raw_source
```

Правила:

1. В stage хранить все карты.
2. В final выбрать одну карту.
3. Если карт нет — пустое значение и строка в `missing_card_report.csv`.
4. Если карт несколько — выбрать последнюю по:

```text
issue_date DESC, card_ref DESC
```

5. Если дата выпуска аномально будущая, не исключать автоматически, но записать в `card_selection_report.csv` и `multiple_cards_report.csv`.

### 6.9. Таблица `fitbase_part2.client_history_summary`

Одна строка на клиента.

Колонки:

```text
client_ref
client_id
client_fio
phones
email
first_sale_date
first_sale_source
client_created_at
has_any_sale
has_any_full_subscription
has_active_full_subscription
has_finished_full_subscription
full_subscription_count
active_full_subscription_count
finished_full_subscription_count
trial_or_guest_sale_count
last_sale_date
last_sale_product_name
last_sale_club
last_sale_club_source
client_marked
```

Эта таблица — основа для распределения клиента между тремя воронками.

### 6.10. Таблица `fitbase_part2.subscription_candidates_ranked`

Одна строка на каждый candidate subscription с ranking-полями.

Колонки:

```text
client_ref
subscription_ref
candidate_for_funnel
rank_number
auto_rank_reason
manual_override_applied
selection_status
selection_reason
```

Для активных:

```text
candidate_for_funnel = active
ORDER BY end_date DESC, start_date DESC, sale_date DESC, subscription_ref DESC
```

Для реактивации:

```text
candidate_for_funnel = reactivation
ORDER BY end_date DESC, start_date DESC, sale_date DESC, subscription_ref DESC
```

Если есть ручной override из `config/subscription_overrides.csv`, он должен иметь приоритет.

### 6.11. Таблица `fitbase_part2.selected_subscriptions`

Одна строка на клиента, если для него выбран абонемент.

Колонки:

```text
client_ref
selected_subscription_ref
selected_for_funnel
selected_subscription_name
selected_sale_date
selected_start_date
selected_end_date
selected_duration_days
days_to_end
days_since_end
selected_raw_club
selected_normalized_club
selected_club_source
selection_reason
manual_override_applied
candidate_count
```

### 6.12. Таблица `fitbase_part2.selected_cards`

Одна строка на клиента.

Колонки:

```text
client_ref
selected_card_ref
selected_card_number
selected_issue_date
card_selection_reason
active_card_count
all_card_refs
all_card_numbers_for_audit
```

В итоговый XLSX попадет только `selected_card_number`.

### 6.13. Таблица `fitbase_part2.final_funnel_clients`

Это главный mart для всех трех воронок.

Одна строка на клиента.

Колонки:

```text
client_ref
client_id
client_fio
phones
email
funnel
funnel_step
budget
create_date
create_date_source
manager
normalized_club
club_source
selected_subscription_ref
selected_subscription_name
selected_subscription_start_date
selected_subscription_end_date
selected_subscription_sale_date
days_to_end
days_since_end
selected_card_number
selected_card_ref
active_full_subscription_count
finished_full_subscription_count
full_subscription_count
trial_or_guest_sale_count
selection_reason
validation_status
cutoff_date
```

Правило распределения по воронкам должно быть строго взаимоисключающим:

```text
1. Если has_active_full_subscription = 1:
   funnel = Действующие клиенты

2. Иначе если has_any_full_subscription = 1 AND has_active_full_subscription = 0:
   funnel = Реактивация

3. Иначе если has_any_full_subscription = 0:
   funnel = Новые заявки
```

---

## 7. Реализовать business rules в Python-скриптах

Чтобы не ломать старую первую версию, лучше добавить новые скрипты.

Создать:

```text
scripts/11_export_part2_stage.py
scripts/12_build_part2_three_funnel_xlsx.py
scripts/13_validate_part2_outputs.py
scripts/14_compare_cutoff_shift.py
```

### 7.1. `scripts/11_export_part2_stage.py`

Назначение:

1. Выполнить SQL stage для заданной даты среза.
2. Экспортировать таблицы `fitbase_part2.*` в CSV.
3. Сложить CSV в отдельную папку.

CLI:

```bash
scripts/11_export_part2_stage.py \
  --cutoff-date 2026-04-29 \
  --backup-finish-at "2026-04-29 23:57:02" \
  --output-dir output/part2_20260429/staging
```

Для эксперимента пятница-понедельник:

```bash
scripts/11_export_part2_stage.py \
  --cutoff-date 2026-04-24 \
  --backup-finish-at "2026-04-29 23:57:02" \
  --output-dir output/part2_shift_20260424_to_20260427/friday_20260424/staging

scripts/11_export_part2_stage.py \
  --cutoff-date 2026-04-27 \
  --backup-finish-at "2026-04-29 23:57:02" \
  --output-dir output/part2_shift_20260424_to_20260427/monday_20260427/staging
```

CSV, которые должны появиться:

```text
stg_clients.csv
stg_client_contacts.csv
stg_products.csv
stg_subscriptions_all.csv
stg_sales_all.csv
stg_plastic_cards.csv
client_history_summary.csv
subscription_candidates_ranked.csv
selected_subscriptions.csv
selected_cards.csv
final_funnel_clients.csv
```

### 7.2. `scripts/12_build_part2_three_funnel_xlsx.py`

Назначение:

1. Прочитать `final_funnel_clients.csv`.
2. Разделить строки по трем воронкам.
3. Сформировать 6 XLSX по двум шаблонам.
4. Сформировать отчеты.

CLI:

```bash
scripts/12_build_part2_three_funnel_xlsx.py \
  --cutoff-date 2026-04-29 \
  --stage-dir output/part2_20260429/staging \
  --output-dir output/part2_20260429 \
  --main-template task-desc/Копия\ Импорт_заявки.xlsx \
  --cards-template task-desc/Пластиковая\ карта.xlsx \
  --managers-config config/managers_by_club.yml
```

Для каждого клиента в основной XLSX:

```text
client_id        <- client_id из 1C
phone            <- phones через запятую, может быть пустым
client_fio       <- ФИО клиента
email            <- email через запятую, если есть
funnel           <- одна из 3 воронок
funnel_step      <- этап по правилам воронки
budget           <- 0
create_date      <- final_create_date по правилам конкретной воронки
manager          <- реальный менеджер по клубу или пусто + missing_club_report
```

Для каждого клиента в XLSX пластиковых карт:

```text
телефон                  <- phones через запятую, может быть пустым
фио                      <- client_fio
номер пластиковой карты  <- selected_card_number, одна карта, не список через запятую
```

### 7.3. `scripts/13_validate_part2_outputs.py`

Назначение:

1. Проверить 6 XLSX.
2. Проверить CSV/reports.
3. Сформировать `validation_report.md`.

CLI:

```bash
scripts/13_validate_part2_outputs.py \
  --cutoff-date 2026-04-29 \
  --stage-dir output/part2_20260429/staging \
  --output-dir output/part2_20260429
```

Обязательные проверки:

```text
1. Существует 6 XLSX.
2. Заголовки XLSX совпадают с шаблонами.
3. Количество строк в main XLSX каждой воронки = количеству строк этой воронки в final_funnel_clients.csv.
4. Количество строк в plastic-card XLSX каждой воронки = количеству строк main XLSX той же воронки.
5. Один client_ref/client_id не встречается в нескольких воронках.
6. В active funnel нет этапа Бронь.
7. В active funnel этапы только:
   - 60-31 день до окончания
   - 30-8 дней до окончания
   - 7-0 день до окончания
   - Действующие клиенты
8. В new applications funnel этап только Неразобранные.
9. В reactivation funnel этапы только:
   - 1-6 дней
   - 7-29 дней
   - 30-59 дней
   - 60-89 дней
   - более 90 дней
10. Нет менеджеров A1/A2/A3.
11. Если manager заполнен, он входит в список менеджеров своего клуба.
12. Если club пустой, клиент есть в missing_club_report.csv.
13. Если phone пустой, клиент есть в missing_phone_report.csv.
14. Если selected_card_number пустой, клиент есть в missing_card_report.csv.
15. Если у клиента несколько карт, он есть в multiple_cards_report.csv и card_selection_report.csv объясняет выбранную карту.
16. Если у клиента несколько абонементов-кандидатов, он есть в multiple_subscriptions_report.csv и subscription_selection_report.csv объясняет выбранный абонемент.
17. В card XLSX нет списка карт через запятую в поле `номер пластиковой карты`.
18. В final XLSX нет технических колонок.
19. В stage сохранены technical refs для аудита.
```

### 7.4. `scripts/14_compare_cutoff_shift.py`

Назначение:

1. Сравнить результат на пятницу `2026-04-24` и понедельник `2026-04-27`.
2. Сформировать `cutoff_shift_comparison_report.md`.

CLI:

```bash
scripts/14_compare_cutoff_shift.py \
  --base-final output/part2_shift_20260424_to_20260427/friday_20260424/staging/final_funnel_clients.csv \
  --shift-final output/part2_shift_20260424_to_20260427/monday_20260427/staging/final_funnel_clients.csv \
  --output output/part2_20260429/reports/cutoff_shift_comparison_report.md
```

Сравнить:

```text
- количество клиентов по каждой воронке;
- распределение по этапам;
- кто перешел между этапами;
- кто вышел из Действующих клиентов;
- кто попал в Реактивацию;
- кто стал новой заявкой;
- изменения по missing reports;
- изменения по менеджерам/клубам;
- изменения по выбранному абонементу;
- изменения по выбранной карте.
```

Важная оговорка для отчета: эксперимент пятница-понедельник работает на том же
backup-е от `2026-04-29`, поэтому он может пересчитать статусы по датам уже
имеющихся абонементов, но не может увидеть документы/продажи, которые реально
появились в 1C после backup-а. Обе даты эксперимента специально выбраны до
даты backup: `2026-04-24` и `2026-04-27`.

---

## 8. Детальные правила выбора абонемента

### 8.1. Полноценный абонемент

Для всех трех воронок использовать только `is_full_subscription = 1`.

Trial/guest/short продукты:

```text
- не делают клиента active;
- не делают клиента reactivation;
- не мешают клиенту попасть в Новые заявки;
- учитываются в create_date;
- учитываются в stage для аудита.
```

### 8.2. Активный клиент

Клиент попадает в `Действующие клиенты`, если на дату среза:

```text
has_active_full_subscription = 1
```

Выбранный абонемент:

1. Если есть manual override — использовать его.
2. Иначе взять активный полноценный абонемент с максимальной датой окончания.
3. При равенстве взять более позднюю дату активации.
4. При равенстве взять более позднюю дату продажи.
5. При равенстве взять больший/последний `subscription_ref` для стабильности.

Этап:

```text
if days_to_end between 31 and 60 -> 60-31 день до окончания
elif days_to_end between 8 and 30 -> 30-8 дней до окончания
elif days_to_end between 0 and 7 -> 7-0 день до окончания
else -> Действующие клиенты
```

`Бронь` не используется вообще.

### 8.3. Реактивация

Клиент попадает в `Реактивация`, если:

```text
has_any_full_subscription = 1
AND has_active_full_subscription = 0
AND last_finished_full_subscription.end_date < cutoff_date
```

Выбранный абонемент:

1. Если есть manual override — использовать его.
2. Иначе взять завершившийся полноценный абонемент с максимальной датой окончания.
3. При равенстве взять более позднюю дату активации.
4. При равенстве взять более позднюю дату продажи.
5. При равенстве взять `subscription_ref`.

Этап:

```text
days_since_end = DATEDIFF(day, selected_end_date, cutoff_date)

1-6      -> 1-6 дней
7-29     -> 7-29 дней
30-59    -> 30-59 дней
60-89    -> 60-89 дней
>= 90    -> более 90 дней
```

Если `days_since_end <= 0`, клиент не должен попадать в реактивацию. Такой случай записать в `reactivation_boundary_anomalies.csv`.

### 8.4. Новые заявки

Клиент попадает в `Новые заявки`, если:

```text
has_any_full_subscription = 0
```

При этом:

```text
has_any_sale может быть 0 или 1
trial_or_guest_sale_count может быть > 0
```

`create_date` для `Новых заявок`:

```text
если есть первый тестовый/гостевой продукт -> create_date = first_trial_or_guest_product_date
если есть только другая не-full продажа    -> create_date = first_non_full_sale_date + report
если продаж/продуктов нет вообще           -> create_date = client_created_at + report
```

В `create_date_source` обязательно записывать, какой источник использован.
Это закрывает риск пустой обязательной даты у клиентов без продаж и фиксирует
логику заказчика: для новых заявок дата должна отражать первый тестовый продукт,
с которым клиент попал в базу.

Этап всегда:

```text
Неразобранные
```

Клуб для менеджера:

1. Если есть последняя продажа/продукт с клубом — использовать клуб последней продажи до среза.
2. Иначе если есть другой надежный клуб клиента — использовать его.
3. Иначе `normalized_club` пустой и строка в `missing_club_report.csv`.

---

## 9. Детальные правила выбора пластиковой карты

Для каждой из трех воронок формировать отдельный card XLSX.

Правило выбора карты:

```text
1. Взять карты клиента из stg_plastic_cards.
2. Оставить только is_unmarked = 1 и непустой plastic_card_number.
3. Отсортировать по issue_date DESC, card_ref DESC.
4. Выбрать первую строку.
```

Если карт нет:

```text
selected_card_number = пусто
missing_card_report.csv += client
```

Если карт несколько:

```text
multiple_cards_report.csv += all candidates
card_selection_report.csv += selected card + reason
```

В итоговом XLSX:

```text
номер пластиковой карты = только одна выбранная карта
```

Запрещено:

```text
номер1, номер2, номер3
```

Исключение: только если Fitbase письменно подтвердит, что ему нужен список. По текущей Part 2 инструкции список запрещен.

---

## 10. Детальные правила телефонов

Телефоны:

1. Если телефон один — выгрузить его.
2. Если телефонов несколько — выгрузить все телефоны через запятую.
3. Если телефона нет — оставить поле пустым.
4. Все строки без телефона записать в `missing_phone_report.csv`.

Отсутствие телефона не является блокером.

---

## 11. Детальные правила менеджеров и клубов

### 11.1. Нормализация клуба

Все найденные клубы должны быть приведены к одному из четырех значений:

```text
Коммунальная, 20
Лососинское шоссе, 26
Промышленная, 10
Ровио, 3
```

### 11.2. Источник клуба по воронкам

Для `Действующие клиенты`:

```text
club = клуб выбранного активного полноценного абонемента
```

Для `Реактивация`:

```text
club = клуб выбранного последнего завершенного полноценного абонемента
```

Для `Новые заявки`:

```text
club = клуб последней продажи/продукта до даты среза
```

Если у новой заявки нет продаж или клуб не найден:

```text
club = пусто
manager = пусто
missing_club_report.csv += client
```

### 11.3. Назначение менеджера

Python-правило:

```python
import hashlib

idx = int(hashlib.sha256(client_id.encode("utf-8")).hexdigest(), 16) % len(managers_by_club[club])
manager = managers_by_club[club][idx]
```

Свойства:

1. Распределение стабильное между перезапусками.
2. Один и тот же client_id всегда получает одного и того же менеджера внутри клуба.
3. Менеджеры `A1`, `A2`, `A3` запрещены.

---

## 12. Сформировать отчеты

### 12.1. `funnel_distribution.csv`

Колонки:

```text
funnel,clients
```

### 12.2. `stage_distribution_by_funnel.csv`

Колонки:

```text
funnel,funnel_step,clients
```

### 12.3. `manager_distribution_by_club.csv`

Колонки:

```text
normalized_club,manager,clients
```

### 12.4. `missing_phone_report.csv`

Колонки:

```text
client_ref,client_id,client_fio,funnel,funnel_step,normalized_club,manager,reason
```

### 12.5. `missing_card_report.csv`

Колонки:

```text
client_ref,client_id,client_fio,funnel,funnel_step,reason
```

### 12.6. `missing_club_report.csv`

Колонки:

```text
client_ref,client_id,client_fio,funnel,funnel_step,selected_subscription_ref,last_sale_ref,club_source_attempted,reason
```

### 12.7. `multiple_subscriptions_report.csv`

Колонки:

```text
client_ref,client_id,client_fio,funnel,candidate_count,selected_subscription_ref,selection_reason
```

### 12.8. `subscription_selection_report.csv`

Одна или несколько строк на клиента-кандидата.

Колонки:

```text
client_ref,client_id,client_fio,candidate_for_funnel,subscription_ref,subscription_name,sale_date,start_date,end_date,status,is_full_subscription,is_active_on_cutoff,days_to_end,days_since_end,rank_number,selected,selection_reason,manual_override_applied
```

### 12.9. `subscription_overrides_report.csv`

Колонки:

```text
client_ref,client_id,subscription_ref,override_type,applies_to_funnel,applied,result,reason,note
```

### 12.10. `multiple_cards_report.csv`

Колонки:

```text
client_ref,client_id,client_fio,funnel,card_ref,plastic_card_number,issue_date,is_selected,selection_reason
```

### 12.11. `card_selection_report.csv`

Колонки:

```text
client_ref,client_id,client_fio,funnel,selected_card_ref,selected_card_number,selected_issue_date,active_card_count,selection_reason,has_future_issue_date_candidate,has_issue_date_tie
```

### 12.12. `product_classification_preflight.csv`

Обязательный отчет перед финальным разбиением клиентов на воронки.

Колонки:

```text
product_ref,product_code,product_name,auto_classification,is_full_subscription_candidate,is_trial_or_guest_candidate,is_unknown,observed_clients,observed_sales,observed_subscription_rows,min_duration_days,max_duration_days,classification_reason,needs_manual_review
```

Назначение:

1. Показать все продукты, которые могут быть полноценными абонементами.
2. Показать все продукты, которые могут быть тестовыми/гостевыми.
3. Показать спорные продукты, где автоматическое правило не уверено.
4. Дать пользователю возможность подтвердить классификацию до финального
   распределения по воронкам.

Текущие явно названные заказчиком тестовые примеры:

```text
гостевой день
гостевая неделя
```

Остальные короткие/пробные продукты должны попасть в этот отчет как кандидаты,
но финальное решение по ним нужно подтвердить вручную.

### 12.13. `product_classification_report.csv`

Колонки:

```text
product_ref,product_code,product_name,product_class,is_full_subscription,is_trial_or_guest,observed_clients,observed_sales,observed_subscription_rows,min_duration_days,max_duration_days,classification_reason
```

### 12.14. `product_classification_review_report.csv`

Колонки:

```text
product_ref,product_code,product_name,observed_clients,observed_sales,observed_subscription_rows,min_duration_days,max_duration_days,auto_classification,review_reason,recommended_action
```

### 12.15. `active_diff_vs_previous_export.csv`

Сравнить новую активную воронку с предыдущим `output/final_active_clients_20260429.csv`.

Колонки:

```text
client_ref,client_id,client_fio,old_present,new_present,old_funnel_step,new_funnel_step,old_manager,new_manager,old_card,new_card,diff_reason
```

Особо проверить:

```text
- все 117 старых Бронь-клиентов должны получить обычный stage;
- клиенты с короткими/гостевыми продуктами могут быть исключены из active, если они не full_subscription;
- card field должен измениться с списка карт на одну выбранную карту;
- manager должен измениться с A1/A2/A3 на ФИО менеджера.
```

---

## 13. Запуск основного baseline pipeline

### 13.1. Установить зависимости

Если зависимости уже стоят, команда безопасна.

```bash
apt-get update
apt-get install -y python3 python3-pip python3-venv python3-openpyxl python3-yaml
python3 - <<'PY'
import openpyxl
print('openpyxl', openpyxl.__version__)
PY
```

Если используется виртуальное окружение:

```bash
python3 -m venv .venv
. .venv/bin/activate
pip install --upgrade pip
pip install openpyxl pyyaml
```

### 13.2. Запустить discovery клубов

```bash
mkdir -p output/part2_20260429/reports logs docs
scripts/sqlcmd.sh -b -i /sql/part2_01_find_club_references.sql \
  > logs/part2_01_find_club_references.txt
scripts/sqlcmd.sh -b -i /sql/part2_02_find_club_links.sql \
  > logs/part2_02_find_club_links.txt
```

После этого заполнить:

```text
docs/part2_01_club_discovery.md
config/club_normalization.yml
```

### 13.3. Запустить stage на основную дату

```bash
scripts/11_export_part2_stage.py \
  --cutoff-date 2026-04-29 \
  --backup-finish-at "2026-04-29 23:57:02" \
  --output-dir output/part2_20260429/staging \
  | tee logs/part2_03_stage_20260429.txt
```

Проверить наличие CSV:

```bash
find output/part2_20260429/staging -maxdepth 1 -type f -name '*.csv' -print | sort
```

### 13.4. Проверить product classification до XLSX

```bash
python3 - <<'PY'
import csv
from pathlib import Path
p = Path('output/part2_20260429/staging/stg_products.csv')
rows = list(csv.DictReader(p.open(encoding='utf-8-sig')))
unknown = [r for r in rows if r.get('product_class') == 'unknown_review_required']
print('products:', len(rows))
print('unknown_review_required:', len(unknown))
PY
```

Если `unknown_review_required > 0`, открыть `product_classification_review_report.csv` и решить:

1. добавить override в `config/product_classification.yml`;
2. перезапустить stage;
3. повторить проверку.

### 13.5. Собрать 6 XLSX

```bash
scripts/12_build_part2_three_funnel_xlsx.py \
  --cutoff-date 2026-04-29 \
  --stage-dir output/part2_20260429/staging \
  --output-dir output/part2_20260429 \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --managers-config config/managers_by_club.yml \
  | tee logs/part2_04_build_xlsx_20260429.txt
```

Проверить файлы:

```bash
ls -lh output/part2_20260429/*.xlsx
```

Должно быть 6 XLSX.

### 13.6. Запустить валидацию

```bash
scripts/13_validate_part2_outputs.py \
  --cutoff-date 2026-04-29 \
  --stage-dir output/part2_20260429/staging \
  --output-dir output/part2_20260429 \
  | tee logs/part2_05_validate_20260429.txt
```

Ожидаемый результат:

```text
output/part2_20260429/reports/validation_report.md
Verdict: PASS
```

Если `WARN`, можно продолжать только если предупреждения ожидаемые и описаны.

Если `FAIL`, исправить причину и перезапустить.

---

## 14. Запуск эксперимента пятница-понедельник

Эксперимент должен использовать апрельские даты до backup `2026-04-29`.
Нужная пара:

```text
пятница:    2026-04-24
понедельник: 2026-04-27
```

Это соответствует бизнес-смыслу "конец пятницы -> начало понедельника" и не
выходит за пределы данных backup.

### 14.1. Построить stage для пятницы `2026-04-24`

```bash
scripts/11_export_part2_stage.py \
  --cutoff-date 2026-04-24 \
  --backup-finish-at "2026-04-29 23:57:02" \
  --output-dir output/part2_shift_20260424_to_20260427/friday_20260424/staging \
  | tee logs/part2_06_stage_20260424_friday.txt
```

### 14.2. Построить stage для понедельника `2026-04-27`

```bash
scripts/11_export_part2_stage.py \
  --cutoff-date 2026-04-27 \
  --backup-finish-at "2026-04-29 23:57:02" \
  --output-dir output/part2_shift_20260424_to_20260427/monday_20260427/staging \
  | tee logs/part2_07_stage_20260427_monday.txt
```

### 14.3. Собрать XLSX для экспериментальных дат, если нужно для проверки

```bash
scripts/12_build_part2_three_funnel_xlsx.py \
  --cutoff-date 2026-04-24 \
  --stage-dir output/part2_shift_20260424_to_20260427/friday_20260424/staging \
  --output-dir output/part2_shift_20260424_to_20260427/friday_20260424 \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --managers-config config/managers_by_club.yml \
  | tee logs/part2_08_build_xlsx_20260424_friday.txt

scripts/12_build_part2_three_funnel_xlsx.py \
  --cutoff-date 2026-04-27 \
  --stage-dir output/part2_shift_20260424_to_20260427/monday_20260427/staging \
  --output-dir output/part2_shift_20260424_to_20260427/monday_20260427 \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --managers-config config/managers_by_club.yml \
  | tee logs/part2_09_build_xlsx_20260427_monday.txt
```

### 14.4. Провалидировать экспериментальные даты

```bash
scripts/13_validate_part2_outputs.py \
  --cutoff-date 2026-04-24 \
  --stage-dir output/part2_shift_20260424_to_20260427/friday_20260424/staging \
  --output-dir output/part2_shift_20260424_to_20260427/friday_20260424 \
  | tee logs/part2_10_validate_20260424_friday.txt

scripts/13_validate_part2_outputs.py \
  --cutoff-date 2026-04-27 \
  --stage-dir output/part2_shift_20260424_to_20260427/monday_20260427/staging \
  --output-dir output/part2_shift_20260424_to_20260427/monday_20260427 \
  | tee logs/part2_11_validate_20260427_monday.txt
```

### 14.5. Сформировать comparison report

```bash
scripts/14_compare_cutoff_shift.py \
  --base-final output/part2_shift_20260424_to_20260427/friday_20260424/staging/final_funnel_clients.csv \
  --shift-final output/part2_shift_20260424_to_20260427/monday_20260427/staging/final_funnel_clients.csv \
  --output output/part2_20260429/reports/cutoff_shift_comparison_report.md \
  | tee logs/part2_12_cutoff_shift_comparison_20260424_20260427.txt
```

В отчете обязательно указать:

```text
- базовая дата эксперимента: 2026-04-24, пятница;
- сдвинутая дата эксперимента: 2026-04-27, понедельник;
- backup доступен только до 2026-04-29 23:57:02;
- сравнение отражает пересчет статусов по датам, а не реальные новые документы после backup;
- сколько клиентов изменили воронку;
- сколько клиентов изменили этап;
- сколько клиентов вышли из active;
- сколько клиентов перешли в reactivation;
- изменения missing reports.
```

---

## 15. Финальная проверка вручную перед отдачей заказчику

### 15.1. Проверить итоговые XLSX руками через openpyxl

```bash
python3 - <<'PY'
from pathlib import Path
from openpyxl import load_workbook

for p in sorted(Path('output/part2_20260429').glob('*.xlsx')):
    wb = load_workbook(p, read_only=True, data_only=True)
    ws = wb.active
    print(p.name, 'rows=', ws.max_row, 'cols=', ws.max_column)
PY
```

Ожидаемо:

```text
6 файлов открываются без ошибок.
```

### 15.2. Проверить отсутствие `Бронь`

```bash
python3 - <<'PY'
import csv
rows = list(csv.DictReader(open('output/part2_20260429/staging/final_funnel_clients.csv', encoding='utf-8-sig')))
bron = [r for r in rows if r.get('funnel_step') == 'Бронь']
print('bron_rows:', len(bron))
assert len(bron) == 0
PY
```

### 15.3. Проверить отсутствие `A1/A2/A3`

```bash
python3 - <<'PY'
import csv
rows = list(csv.DictReader(open('output/part2_20260429/staging/final_funnel_clients.csv', encoding='utf-8-sig')))
bad = [r for r in rows if r.get('manager') in {'A1','A2','A3'}]
print('A managers:', len(bad))
assert len(bad) == 0
PY
```

### 15.4. Проверить отсутствие пересечений между воронками

```bash
python3 - <<'PY'
import csv
from collections import defaultdict
rows = list(csv.DictReader(open('output/part2_20260429/staging/final_funnel_clients.csv', encoding='utf-8-sig')))
by_client = defaultdict(set)
for r in rows:
    by_client[r['client_ref']].add(r['funnel'])
overlap = {k:v for k,v in by_client.items() if len(v) > 1}
print('overlap_clients:', len(overlap))
assert len(overlap) == 0
PY
```

### 15.5. Проверить одну карту в card XLSX

```bash
python3 - <<'PY'
from pathlib import Path
from openpyxl import load_workbook

bad = []
for p in Path('output/part2_20260429').glob('*plastic_cards*.xlsx'):
    wb = load_workbook(p, read_only=True, data_only=True)
    ws = wb.active
    for row_idx, row in enumerate(ws.iter_rows(min_row=2, values_only=True), start=2):
        card = row[2] if len(row) >= 3 else None
        if isinstance(card, str) and ',' in card:
            bad.append((p.name, row_idx, card))
print('comma_cards:', len(bad))
assert len(bad) == 0
PY
```

---

## 16. Mini-test в Fitbase

Перед полной загрузкой в Fitbase подготовить маленький тестовый пакет.

Создать скрипт или доработать существующий:

```text
scripts/15_build_part2_mini_test_package.py
```

Мини-тест должен включать клиентов из разных групп:

```text
- 5 действующих клиентов из каждого active stage;
- 5 новых заявок;
- 5 клиентов реактивации из каждого reactivation stage;
- клиенты без телефона;
- клиенты без карты;
- клиенты с несколькими картами, где выбрана одна;
- клиенты с несколькими абонементами, где выбран один;
- клиенты с каждым из 4 клубов;
- клиенты с пустым клубом, если такие остались.
```

Команда:

```bash
scripts/15_build_part2_mini_test_package.py \
  --source output/part2_20260429/staging/final_funnel_clients.csv \
  --output-dir output/part2_20260429/mini_test \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx"
```

После тестовой загрузки в Fitbase записать результат:

```text
docs/part2_10_fitbase_mini_test_result.md
```

В документе указать:

```text
- какие файлы загружались;
- сколько строк;
- какие ошибки Fitbase показал;
- принял ли Fitbase пустой phone;
- принял ли Fitbase пустой card;
- принял ли Fitbase create_date в текущем формате;
- корректно ли распознал воронки и этапы;
- корректно ли назначил менеджеров.
```

---

## 17. Финальный пакет для отдачи

После `PASS` и mini-test подготовить финальный каталог:

```bash
mkdir -p output/final_delivery_part2_20260429
cp output/part2_20260429/*.xlsx output/final_delivery_part2_20260429/
cp -a output/part2_20260429/reports output/final_delivery_part2_20260429/
cp output/part2_20260429/staging/final_funnel_clients.csv output/final_delivery_part2_20260429/
cp output/part2_20260429/staging/selected_subscriptions.csv output/final_delivery_part2_20260429/ 2>/dev/null || true
cp output/part2_20260429/staging/selected_cards.csv output/final_delivery_part2_20260429/ 2>/dev/null || true
```

Создать архив:

```bash
tar -czf output/final_delivery_part2_20260429.tar.gz -C output final_delivery_part2_20260429
ls -lh output/final_delivery_part2_20260429.tar.gz
```

В финальном `docs/part2_11_final_summary.md` указать:

```text
1. Список 6 XLSX.
2. Количество клиентов по каждой воронке.
3. Количество клиентов по каждому этапу.
4. Количество клиентов без телефона.
5. Количество клиентов без карты.
6. Количество клиентов без клуба.
7. Количество клиентов с несколькими абонементами и как они были разрешены.
8. Количество клиентов с несколькими картами и как они были разрешены.
9. Итог `cutoff_shift_comparison_report`.
10. Итог mini-test в Fitbase.
11. Verdict validation_report.
```

---

## 18. Критерии готовности Part 2

Работа считается готовой, когда выполнено все ниже:

1. Сформированы все 6 XLSX-файлов.
2. Воронки `Действующие клиенты`, `Новые заявки`, `Реактивация` построены из одного воспроизводимого stage.
3. Один клиент не попадает сразу в несколько воронок.
4. Этап `Бронь` полностью отсутствует.
5. Клиенты, ранее попадавшие в `Бронь`, перераспределены по датам окончания.
6. Для клиента с несколькими активными абонементами выбран один абонемент.
7. Для клиента с несколькими завершенными абонементами выбран один последний завершенный абонемент.
8. Все кандидаты абонементов сохранены в stage и selection reports.
9. Для клиента с несколькими картами выбрана одна последняя карта.
10. В итоговом XLSX пластиковых карт нет списков карт через запятую.
11. Телефоны выгружаются как раньше: несколько телефонов через запятую, отсутствие телефона допустимо.
12. Менеджеры `A1`, `A2`, `A3` отсутствуют.
13. Менеджеры назначены по клубам через стабильный hash client_id.
14. Если клуб не найден, клиент попал в `missing_club_report.csv`.
15. Сформирован `product_classification_preflight.csv`.
16. Продукты разделены на full subscription / trial-or-guest / other / unknown-review.
17. Классификация продуктов вручную подтверждена до финального разбиения по воронкам.
18. Нет необработанных `unknown-review` продуктов, влияющих на воронки, либо они явно описаны и согласованы.
19. Сформирован `cutoff_shift_comparison_report.md`.
20. Сформирован `validation_report.md` с verdict `PASS`.
21. Сформирован mini-test package и результат mini-test записан в docs.
22. Финальная папка `output/final_delivery_part2_20260429/` содержит XLSX и отчеты.

---

## 19. Приоритет выполнения

Рекомендуемый порядок работ:

```text
1. Baseline backup текущих output.
2. Проверить SQL container + FitnessRestored ONLINE.
3. Обновить configs.
4. Найти клуб/филиал в базе.
5. Сделать product classification preflight + review reports.
6. Ручно подтвердить классификацию продуктов и зафиксировать overrides.
7. Реализовать расширенный stage под все три воронки.
8. Реализовать выбор абонемента и карты.
9. Реализовать менеджеров по клубу.
10. Собрать baseline 2026-04-29.
11. Провалидировать baseline.
12. Собрать эксперимент пятница-понедельник: 2026-04-24 и 2026-04-27.
13. Сформировать cutoff comparison по 2026-04-24 -> 2026-04-27.
13. Собрать mini-test package.
14. Провести mini-test в Fitbase.
15. Собрать final delivery package.
```

---

## 20. Главные риски и как их закрывать

### Риск 1. Клуб не найден для части клиентов

Что делать:

1. Не подставлять случайный клуб.
2. Не использовать название продукта как основной источник, если оно покрывает только малую часть клиентов.
3. Писать в `missing_club_report.csv`.
4. Проверить дополнительные таблицы/документы.
5. Если покрытие все равно неполное, получить от заказчика fallback-правило.

### Риск 2. Неясно, какие продукты являются полноценными абонементами

Что делать:

1. Сформировать `product_classification_preflight.csv`.
2. Сформировать `product_classification_review_report.csv`.
3. Отсортировать продукты по количеству клиентов/продаж.
4. Все спорные массовые продукты вынести на ручное решение до финального
   разбиения по воронкам.
5. Зафиксировать решение в `config/product_classification.yml`.
6. Перезапустить stage.

### Риск 3. Несколько активных абонементов меняют этап клиента

Что делать:

1. Базовое правило: самый поздний `end_date`.
2. Все случаи с несколькими кандидатами писать в `multiple_subscriptions_report.csv`.
3. Для проверенных конфликтов использовать `config/subscription_overrides.csv`.
4. В `subscription_selection_report.csv` объяснять выбранный абонемент.

### Риск 4. Аномальные даты карт

Что делать:

1. Выбирать по `issue_date DESC, card_ref DESC`, как требует инструкция.
2. Аномально будущие даты писать в report.
3. Не менять правило без согласования.

### Риск 5. Эксперимент пятница-понедельник может быть неправильно истолкован

Что делать:

В `cutoff_shift_comparison_report.md` явно написать:

```text
Это не новый backup за понедельник 2026-04-27. Это пересчет статусов на даты
2026-04-24 и 2026-04-27 на основании данных, которые уже были в backup от
2026-04-29. Эксперимент не видит документы, созданные после backup.
```

---

## 21. Короткий чек-лист перед финальным ответом заказчику

```text
[ ] 6 XLSX есть
[ ] validation_report.md = PASS
[ ] Бронь отсутствует
[ ] A1/A2/A3 отсутствуют
[ ] one client -> one funnel
[ ] active stages корректны
[ ] new applications stage = Неразобранные
[ ] reactivation stages корректны
[ ] one selected card per client
[ ] missing phone/card/club reports есть
[ ] multiple subscriptions/cards reports есть
[ ] product classification reports есть
[ ] club discovery documented
[ ] cutoff shift comparison есть
[ ] mini-test result documented
[ ] final_delivery_part2_20260429.tar.gz создан
```
