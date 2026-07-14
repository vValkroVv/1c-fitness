# Step 11: sale branch in membership and services imports

> Архивный отчёт прежней смешанной поставки. Правило филиала сохранено, но счётчики
> и финальный путь ниже устарели. Актуальная поставка:
> `output/20260630_delivery_full_cutoff/`.

Дата: `2026-07-06`

## Задача

Добавить колонку `филиал` в два клиентских файла:

- `fitbase_import_abonementy_clientov_20260630.xlsx`;
- `fitbase_import_uslugi_clientov_20260630.xlsx`.

Важно: нужен филиал именно продажи, а не текущий/основной филиал клиента.

## Найденный источник

Документ продажи для абонементов и услуг: `dbo._Document154`.

Поле филиала продажи:

```text
dbo._Document154._Fld1116RRef -> dbo._Reference105._IDRRef
```

Проверка по проведенным продажам:

```text
Фитнес Империя (Гоголевский)   -> Фитнес Империя (Гоголевский)
Фитнес Империя (Столица)       -> Фитнес Империя (Столица)
Фитнес Империя (Промышленная)  -> Фитнес Империя (Промышленная)
Фитнес Империя (Карельский)    -> Фитнес Империя (Ровио)
Фитнес Империя (Ровио,3)       -> Фитнес Империя (Ровио)
```

`Карельский` намеренно нормализуется в `Ровио`, как и в прежнем правиле для
`import_заявки`.

Для абонементов есть два источника:

- `79 751` фактов имеют связанный проведенный документ продажи `Document154`;
- `20 208` исторических фактов не имеют строки `Document154_VT1137`, поэтому
  филиал берется из документа абонемента/оформления
  `dbo._Document163._Fld1443RRef -> dbo._Reference105`.

## Реализация

В SQL-стейджинг добавлены поля:

```text
sale_branch_raw
sale_branch
sale_branch_source
```

Измененные файлы:

```text
sql/31_build_membership_import_staging.sql
sql/54_build_services_import_staging.sql
scripts/31_build_membership_import_outputs.sh
scripts/32_build_services_import_outputs.sh
scripts/19_build_membership_import_xlsx.py
scripts/23_build_services_import_xlsx.py
scripts/20_validate_membership_import_xlsx.py
scripts/24_validate_services_import_xlsx.py
```

В XLSX колонка добавлена последней:

```text
филиал
```

Для услуг значение всегда берется из `Document154`.

Для абонементов приоритет такой:

1. `Document154._Fld1116RRef`, если есть связанный документ продажи.
2. `Document163._Fld1443RRef`, если это исторический абонемент без
   `Document154`.
3. Для технических placeholder-строк `отказники` без абонемента и без продажи
   используется филиал из исходной `import_заявки`, потому что sale-документа
   для них не существует.

## Пересборка

Выполнены команды:

```bash
MEMBERSHIP_SOURCE_OUTPUT_ROOT=output/20260630_fix_owner \
MEMBERSHIP_OUTPUT_ROOT=output/20260630_fix_owner_new_import \
MEMBERSHIP_DATABASE_NAME=FitnessRestored_20260630_macos \
MEMBERSHIP_SQLCMD_SERVER=mssql-fitness-2022,1433 \
MEMBERSHIP_DATE_STAMP=20260630 \
MEMBERSHIP_LOG_ROOT=logs/new-backup-30-06/membership \
scripts/31_build_membership_import_outputs.sh
```

```bash
SERVICES_SOURCE_OUTPUT_ROOT=output/20260630_fix_owner \
SERVICES_OUTPUT_ROOT=output/20260630_fix_owner_new_import \
SERVICES_DATABASE_NAME=FitnessRestored_20260630_macos \
SERVICES_SQLCMD_SERVER=mssql-fitness-2022,1433 \
SERVICES_DATE_STAMP=20260630 \
SERVICES_LOG_ROOT=logs/new-backup-30-06/services \
scripts/32_build_services_import_outputs.sh
```

```bash
ACTIVE_PROBLEM_OUTPUT_DIR=output/20260630_fix_owner_new_import \
ACTIVE_PROBLEM_DATE_STAMP=20260630 \
ACTIVE_PROBLEM_CUTOFF_DATE=2026-06-30 \
python3 scripts/36_build_active_problem_case_workbooks.py
```

Финальная папка `output/20260630_delivery_without_active_problems/` пересобрана
из обновленных XLSX. Из файла абонементов удалены `223` problem-строки.

## Контроль

Полная сборка:

```text
fitbase_import_abonementy_clientov_20260630.xlsx: 120040 rows, 22 cols, PASS
fitbase_import_uslugi_clientov_20260630.xlsx: 522 rows, 17 cols, PASS
```

Распределение филиалов в полном файле абонементов:

```text
Фитнес Империя (Гоголевский): 72927
Фитнес Империя (Столица): 18047
Фитнес Империя (Промышленная): 15327
Фитнес Империя (Ровио): 13739
```

Распределение филиалов в полном файле услуг:

```text
Фитнес Империя (Гоголевский): 240
Фитнес Империя (Ровио): 105
Фитнес Империя (Промышленная): 89
Фитнес Империя (Столица): 88
```

Финальная delivery-папка:

```text
fitbase_import_abonementy_clientov_20260630.xlsx: 119817 rows, 22 cols
fitbase_import_uslugi_clientov_20260630.xlsx: 522 rows, 17 cols
problem contract_id remaining in delivery membership file: 0
```

Распределение филиалов в delivery-файле абонементов:

```text
Фитнес Империя (Гоголевский): 72833
Фитнес Империя (Столица): 18005
Фитнес Империя (Промышленная): 15285
Фитнес Империя (Ровио): 13694
```

Во всех файлах с колонкой `филиал` значения только из 4 разрешенных филиалов;
пустых значений нет.
