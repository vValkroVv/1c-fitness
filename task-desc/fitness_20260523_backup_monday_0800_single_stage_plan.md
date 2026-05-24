# 1C Fitness -> Fitbase. Plan: backup 2026-05-23, Monday 08:00 MSK, 2 XLSX with single-stage funnels

Дата подготовки плана: 2026-05-24  
Рабочий контур: `/root/workspace/1c-fitness` или текущий repo root  
Новый backup: `data/Fitnes-23-05-26.bak`  
Предыдущая финальная логика: `output/part2_20260429_final_combined/`  
Основной срез для выдачи: `2026-05-25 08:00:00 Europe/Moscow`  
Контрольный срез для сверки с `gym_sales.csv`: `2025-11-15 08:00:00 Europe/Moscow`

---

## 0. Что уже известно

Новый backup найден и скачан:

```text
remote: /home/linuxadmin/Fitnes-23-05-26.bak
local: data/Fitnes-23-05-26.bak
size_bytes: 12909315072
sha256: 0964142666cd98da0cd1d72340e8399e329d348a44ccefa0033f2fbf2933f191
```

Подробности уже задокументированы:

```text
docs/step_19_remote_backup_20260523_check.md
docs/step_20_download_remote_backup_20260523.md
```

Важно: файл backup имеет отметку `2026-05-23`, а рабочий срез нужен на
`2026-05-25 08:00:00 MSK`. Это означает: считаем состояние клиентов на
понедельник 25 мая 2026 08:00 по датам и будущим окончаниям абонементов,
которые уже есть в backup. Продажи и изменения, созданные после момента backup,
в результат попасть не могут.

---

## 1. Финальный результат

Нужно получить не шесть отдельных XLSX, а две объединенные финальные книги по
всем трем воронкам:

```text
output/part2_20260525_0800_final_combined/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
output/part2_20260525_0800_final_combined/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx
```

Также должны быть stage/CSV/report-артефакты для воспроизводимости:

```text
output/part2_20260525_0800_final/staging/
output/part2_20260525_0800_final/csv/
output/part2_20260525_0800_final/reports/
logs/part2_20260525_0800_*.txt
docs/step_21_restore_backup_20260523.md
docs/step_22_part2_20260525_0800_build.md
docs/step_23_part2_20260525_0800_final_validation.md
```

Для ноябрьской проверки:

```text
output/part2_20251115_0800_compare/
docs/step_24_part2_20251115_gym_sales_compare.md
```

---

## 2. Бизнес-правила воронок

Логика попадания клиента в одну из трех групп остается такой же, как в финальной
сборке `output/part2_20260429_final_combined/`.

Внутренние логические группы:

1. `active`: клиент имеет действующий полноценный абонемент на срез.
2. `reactivation`: клиент раньше имел полноценный абонемент, но на срез нет
   действующего полноценного абонемента.
3. `new_applications`: клиент есть в 1C, но не имел полноценного абонемента;
   гостевые, пробные, тестовые и короткие продукты не делают клиента
   реактивацией.

Для финального Fitbase XLSX названия воронок и этапов должны быть строго такими,
как написал заказчик:

| Внутренняя группа | `funnel` в XLSX | `funnel_step` в XLSX |
|---|---|---|
| `new_applications` | `новые заявки` | `неразобранные` |
| `active` | `Действующие абонементы` | `Все действующие абонементы` |
| `reactivation` | `Реактивация(годовые абонементы)` | `Все закрытые абонементы` |

Старые этапы не должны попадать в финальный XLSX:

```text
60-31 день до окончания
30-8 дней до окончания
7-0 день до окончания
Действующие клиенты
1-6 дней
7-29 дней
30-59 дней
60-89 дней
более 90 дней
```

При этом старые расчетные поля `days_to_end`, `days_since_end`,
`selected_subscription_*`, `selection_reason` и отчеты по качеству данных нужно
оставить в CSV/report-артефактах для аудита.

---

## 3. Подготовка окружения

```bash
cd /root/workspace/1c-fitness
mkdir -p docs logs output sql scripts
git status --short
docker ps --filter name=mssql-fitness
scripts/06_start_mssql_container.sh
scripts/sqlcmd.sh -b -Q "SELECT @@VERSION AS version;"
```

Если контейнер уже существует, `scripts/06_start_mssql_container.sh` завершится
с сообщением `Container already exists`. Это нормально: нужно просто проверить,
что контейнер запущен и отвечает.

---

## 4. Проверить новый backup до restore

Не использовать старые SQL-файлы как есть, потому что они смотрят на
`/backup/Fitnes.bak`. Для нового файла создать отдельные SQL или добавить
параметр backup path:

```text
sql/21_restore_headeronly_20260523.sql
sql/21_restore_filelistonly_20260523.sql
sql/21_restore_verifyonly_20260523.sql
```

SQL:

```sql
RESTORE HEADERONLY
FROM DISK = N'/backup/Fitnes-23-05-26.bak';
GO

RESTORE FILELISTONLY
FROM DISK = N'/backup/Fitnes-23-05-26.bak'
WITH FILE = 1;
GO

RESTORE VERIFYONLY
FROM DISK = N'/backup/Fitnes-23-05-26.bak'
WITH FILE = 1;
GO
```

Запуск:

```bash
scripts/sqlcmd.sh -b -i /sql/21_restore_headeronly_20260523.sql > logs/restore_headeronly_20260523.txt
scripts/sqlcmd.sh -b -i /sql/21_restore_filelistonly_20260523.sql > logs/restore_filelistonly_20260523.txt
scripts/sqlcmd.sh -b -i /sql/21_restore_verifyonly_20260523.sql > logs/restore_verifyonly_20260523.txt
```

Зафиксировать в `docs/step_21_restore_backup_20260523.md`:

1. `BackupStartDate`, `BackupFinishDate`, `DatabaseName`.
2. Logical names из `FILELISTONLY`.
3. `VERIFYONLY` result.
4. Размер backup и SHA-256 из `docs/step_20_download_remote_backup_20260523.md`.

К restore переходить только если `VERIFYONLY` вернул, что backup set valid.

---

## 5. Restore нового backup

Восстанавливать новый backup лучше в отдельную базу, чтобы не смешать его со
старой `FitnessRestored`:

```text
database: FitnessRestored_20260523
data file: /var/opt/mssql/data/FitnessRestored_20260523.mdf
log file: /var/opt/mssql/data/FitnessRestored_20260523_log.ldf
```

Создать:

```text
sql/21_restore_database_20260523.sql
```

Шаблон SQL, logical names уточнить по `FILELISTONLY`:

```sql
USE [master];
GO

IF DB_ID(N'FitnessRestored_20260523') IS NOT NULL
BEGIN
    ALTER DATABASE [FitnessRestored_20260523] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [FitnessRestored_20260523];
END
GO

RESTORE DATABASE [FitnessRestored_20260523]
FROM DISK = N'/backup/Fitnes-23-05-26.bak'
WITH
    FILE = 1,
    MOVE N'Fitness' TO N'/var/opt/mssql/data/FitnessRestored_20260523.mdf',
    MOVE N'Fitness_log' TO N'/var/opt/mssql/data/FitnessRestored_20260523_log.ldf',
    RECOVERY,
    STATS = 5;
GO
```

Запуск:

```bash
date -Is > logs/restore_20260523_started_at.txt
scripts/sqlcmd.sh -b -i /sql/21_restore_database_20260523.sql > logs/restore_20260523.log
date -Is > logs/restore_20260523_finished_at.txt
```

Проверки после restore:

```bash
scripts/sqlcmd.sh -b -Q "SELECT name, state_desc, recovery_model_desc, compatibility_level FROM sys.databases WHERE name = N'FitnessRestored_20260523';" > logs/post_restore_checks_20260523.txt
scripts/sqlcmd.sh -b -d FitnessRestored_20260523 -Q "SELECT COUNT(*) AS user_tables FROM sys.tables WHERE is_ms_shipped = 0;" >> logs/post_restore_checks_20260523.txt
scripts/sqlcmd.sh -b -d FitnessRestored_20260523 -Q "SELECT COUNT(*) AS user_columns FROM sys.columns AS c JOIN sys.tables AS t ON t.object_id = c.object_id WHERE t.is_ms_shipped = 0;" >> logs/post_restore_checks_20260523.txt
```

Ожидание:

```text
FitnessRestored_20260523 ONLINE
user_tables примерно 2503
user_columns примерно 19421
```

---

## 6. Минимальные изменения в pipeline

### 6.1. Параметризовать имя базы

Сейчас `sql/part2_03_build_three_funnel_staging.sql` и
`scripts/11_export_part2_stage.py` жестко используют `FitnessRestored`.

Нужно добавить параметр:

```bash
--database FitnessRestored_20260523
```

Изменения:

1. В `sql/part2_03_build_three_funnel_staging.sql` заменить
   `USE [FitnessRestored]` на placeholder `USE [$(database_name)]`.
2. В `scripts/11_export_part2_stage.py` добавить `--database`.
3. Все вызовы `scripts/sqlcmd.sh -d FitnessRestored` заменить на
   `scripts/sqlcmd.sh -d args.database`.
4. В metadata сохранить `source_database = DB_NAME()`.

### 6.2. Зафиксировать cutoff как datetime

Добавить параметр:

```bash
--cutoff-at "2026-05-25 08:00:00"
```

Практически:

1. В SQL добавить `@cutoff_at datetime2`.
2. Для текущих date-only правил оставить `@cutoff_date = CONVERT(date, @cutoff_at)`.
3. Если исходное поле содержит время (`_Date_Time`), фильтровать продажи через
   datetime, чтобы продажи позже `08:00` не попадали.
4. Если конкретные регистры абонементов содержат только date-level значения,
   это явно записать в `docs/step_22_part2_20260525_0800_build.md`.

### 6.3. Сохранить внутреннюю старую классификацию

Не переписывать проверенную бизнес-логику воронок. Stage может продолжать
хранить внутренние значения:

```text
Действующие клиенты
Новые заявки
Реактивация
```

Для финального XLSX добавить слой отображения:

```text
internal funnel -> fitbase_funnel
internal funnel -> fitbase_funnel_step
```

Этот слой можно сделать в `scripts/17_build_part2_combined_xlsx.py` или вынести
в общий helper, который используют оба XLSX-builder-а.

### 6.4. Обновить validation под финальную выдачу

Добавить отдельную validation для двух объединенных XLSX:

```text
scripts/18_validate_combined_single_stage_outputs.py
```

Проверки:

1. Есть ровно два финальных XLSX.
2. Заголовки совпадают с шаблонами.
3. Количество строк в `import_zayavki` равно количеству строк в
   `final_funnel_clients.csv`.
4. Количество строк в `plastic_cards` равно количеству строк в
   `final_funnel_clients.csv`.
5. В финальном XLSX только три значения `funnel` из таблицы заказчика.
6. В финальном XLSX только три значения `funnel_step` из таблицы заказчика.
7. Нет старых этапов.
8. Нет дублей `client_id`/`client_ref`.
9. Отчеты `missing_phone`, `missing_card`, `missing_club`,
   `multiple_subscriptions`, `card_selection`, `product_classification_*`
   существуют и согласованы с stage.

---

## 7. Построить основной stage на 2026-05-25 08:00

Сначала выгрузить raw stage по новому backup:

```bash
scripts/11_export_part2_stage.py \
  --database FitnessRestored_20260523 \
  --cutoff-date 2026-05-25 \
  --cutoff-at "2026-05-25 08:00:00" \
  --backup-finish-at "<BackupFinishDate из HEADERONLY>" \
  --output-run-label part2_20260525_0800_raw \
  --output-dir output/part2_20260525_0800_raw/staging \
  --reports-dir output/part2_20260525_0800_raw/reports \
  --logs-dir logs
```

Дальше применить уже согласованные решения по классификации продуктов:

```bash
scripts/16_reclassify_part2_from_csv.py \
  --cutoff-date 2026-05-25 \
  --source-stage-dir output/part2_20260525_0800_raw/staging \
  --source-reports-dir output/part2_20260525_0800_raw/reports \
  --output-stage-dir output/part2_20260525_0800_final/staging \
  --output-reports-dir output/part2_20260525_0800_final/reports \
  --decisions config/product_reclassification_decisions.csv
```

После reclassify проверить:

```bash
wc -l output/part2_20260525_0800_final/staging/final_funnel_clients.csv
cat output/part2_20260525_0800_final/reports/product_reclassification_impact.md
```

---

## 8. Собрать два финальных XLSX

Собрать объединенные книги с single-stage mapping:

```bash
scripts/17_build_part2_combined_xlsx.py \
  --cutoff-date 2026-05-25 \
  --date-stamp 20260525_0800 \
  --stage-dir output/part2_20260525_0800_final/staging \
  --output-dir output/part2_20260525_0800_final_combined \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --managers-config config/managers_by_club.yml \
  --fitbase-label-mode customer_20260520_single_stage
```

Ожидаемые файлы:

```text
output/part2_20260525_0800_final_combined/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
output/part2_20260525_0800_final_combined/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx
```

Сформировать отчет:

```text
docs/step_22_part2_20260525_0800_build.md
output/part2_20260525_0800_final/reports/funnel_distribution.csv
output/part2_20260525_0800_final/reports/single_stage_distribution.csv
```

В `single_stage_distribution.csv` должны быть ровно такие пары:

```text
новые заявки,неразобранные
Действующие абонементы,Все действующие абонементы
Реактивация(годовые абонементы),Все закрытые абонементы
```

---

## 9. Validate основной выдачи

Запустить:

```bash
scripts/18_validate_combined_single_stage_outputs.py \
  --cutoff-date 2026-05-25 \
  --date-stamp 20260525_0800 \
  --stage-dir output/part2_20260525_0800_final/staging \
  --output-dir output/part2_20260525_0800_final_combined \
  --reports-dir output/part2_20260525_0800_final/reports \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx"
```

Результат записать:

```text
output/part2_20260525_0800_final/reports/validation_report.md
docs/step_23_part2_20260525_0800_final_validation.md
```

Критерий приемки:

```text
validation verdict: PASS
2 final XLSX exist
old multi-stage names absent from final XLSX
row counts match final_funnel_clients.csv
```

---

## 10. Ноябрьская сверка с data/gym_sales.csv

Для "середины ноября" фиксируем воспроизводимую дату:

```text
2025-11-15 08:00:00 Europe/Moscow
```

Построить raw stage из нового restored backup:

```bash
scripts/11_export_part2_stage.py \
  --database FitnessRestored_20260523 \
  --cutoff-date 2025-11-15 \
  --cutoff-at "2025-11-15 08:00:00" \
  --backup-finish-at "<BackupFinishDate из HEADERONLY>" \
  --output-run-label part2_20251115_0800_raw \
  --output-dir output/part2_20251115_0800_raw/staging \
  --reports-dir output/part2_20251115_0800_raw/reports \
  --logs-dir logs
```

Применить те же product decisions:

```bash
scripts/16_reclassify_part2_from_csv.py \
  --cutoff-date 2025-11-15 \
  --source-stage-dir output/part2_20251115_0800_raw/staging \
  --source-reports-dir output/part2_20251115_0800_raw/reports \
  --output-stage-dir output/part2_20251115_0800_final/staging \
  --output-reports-dir output/part2_20251115_0800_final/reports \
  --decisions config/product_reclassification_decisions.csv
```

Сравнить с `data/gym_sales.csv`:

```bash
scripts/17_compare_part2_with_gym_sales.py \
  --cutoff-date 2025-11-15 \
  --gym-sales-csv data/gym_sales.csv \
  --source-stage-dir output/part2_20251115_0800_raw/staging \
  --source-reports-dir output/part2_20251115_0800_raw/reports \
  --decisions config/product_reclassification_decisions.csv \
  --output-dir output/part2_20251115_0800_compare \
  --report docs/step_24_part2_20251115_gym_sales_compare.md
```

Важно для интерпретации:

1. `gym_sales.csv` является sales-export, а не полным справочником клиентов.
2. Поэтому `новые заявки` могут не совпадать с 1C-клиентами без полноценного
   абонемента.
3. Основной hard-check для "примерно совпало" делать по клиентам с
   полноценными продажами: `active + reactivation`.
4. Рекомендуемый порог по умолчанию: delta `<= 3%` для суммы
   `active + reactivation`. Если заказчик ожидает другой порог, его нужно
   записать в `docs/step_24_part2_20251115_gym_sales_compare.md`.

Выходные файлы:

```text
output/part2_20251115_0800_compare/funnel_counts_comparison.csv
output/part2_20251115_0800_compare/part2_algorithm_funnel_counts.csv
output/part2_20251115_0800_compare/gym_sales_funnel_counts.csv
output/part2_20251115_0800_compare/gym_sales_product_classification.csv
docs/step_24_part2_20251115_gym_sales_compare.md
```

---

## 11. Итоговый чат после выполнения pipeline

После запуска всех шагов написать в чат коротко и с числами:

```text
Готово.

Ноябрьская сверка на 2025-11-15 08:00 МСК: совпало / не совпало.
- 1C active + reactivation: <N>
- gym_sales active + reactivation: <N>
- delta: <N> (<PCT>%)

Новые финальные XLSX на 2026-05-25 08:00 МСК:
- output/part2_20260525_0800_final_combined/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
- output/part2_20260525_0800_final_combined/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx

Клиентов по воронкам:
- новые заявки / неразобранные: <N>
- Действующие абонементы / Все действующие абонементы: <N>
- Реактивация(годовые абонементы) / Все закрытые абонементы: <N>

Validation: PASS.
Отчеты:
- output/part2_20260525_0800_final/reports/validation_report.md
- docs/step_24_part2_20251115_gym_sales_compare.md
```

Если ноябрьская сверка не проходит порог, не писать "совпало". Вместо этого
написать точный delta, приложить report path и указать, какая группа дает
расхождение.

---

## 12. Критерии Done

1. Новый backup `data/Fitnes-23-05-26.bak` проверен через `HEADERONLY`,
   `FILELISTONLY`, `VERIFYONLY`.
2. Backup восстановлен как `FitnessRestored_20260523`.
3. Restore задокументирован в `docs/step_21_restore_backup_20260523.md`.
4. Основной stage построен на `2026-05-25 08:00:00 MSK`.
5. Финальная выдача состоит из двух XLSX, не из шести.
6. В финальных XLSX нет старых многоэтапных bucket-этапов.
7. Названия воронок и этапов в финальном XLSX строго соответствуют таблице
   заказчика.
8. Validation report имеет verdict `PASS`.
9. Ноябрьская сверка с `data/gym_sales.csv` выполнена и задокументирована.
10. В финальном сообщении указаны пути к двум XLSX и количество клиентов в
    каждой из трех финальных воронок.
