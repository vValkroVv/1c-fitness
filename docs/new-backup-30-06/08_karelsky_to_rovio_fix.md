# Правка Карельский -> Ровио для backup 2026-06-30

Дата: `2026-07-05`.

## Задача

Клуб `Карельский` закрыт. В текущей сборке он не должен оставаться отдельным
продуктовым/клубным fallback-сценарием и не должен получать менеджера
`УТОЧНИТЬ: Карельский`.

Правило, уже зафиксированное раньше в `docs/step_27_part2_20260525_branch_column.md`:

```text
Карельский (закрыт) -> Фитнес Империя (Ровио)
```

Для свежей сборки правило расширено ниже по пайплайну:

- raw `Фитнес Империя (Карельский)` сохраняется в `raw_club` как исторический
  источник;
- нормализованный клуб для всех новых расчетов становится `Ровио, 3`;
- менеджер назначается из пула менеджеров `Ровио, 3`;
- в финальном `import_заявки` филиал остается `Фитнес Империя (Ровио)`.

## Изменения в коде и конфигах

- `sql/part2_03_build_three_funnel_staging.sql`: все ветки нормализации
  `LIKE '%Карель%'` теперь возвращают `Ровио, 3`, а не
  `Карельский (закрыт)`.
- `config/club_normalization.yml`: входы `Фитнес Империя (Карельский)`,
  `Карельский`, `Карельский (закрыт)` нормализуются в `Ровио, 3`.
- `config/club_org_mapping.csv`: справочник клуба Карельский переведен на
  normalized club `Ровио, 3`, с пометкой `closed_club_mapped_to_rovio`.
- `config/managers_by_club.yml`: старый ключ `Карельский (закрыт)` оставлен
  только для обратной совместимости и направлен на тот же пул менеджеров, что
  `Ровио, 3`.
- `scripts/15_build_part2_mini_test_package.py`: отдельный mini-test bucket
  `Карельский (закрыт)` удален, потому что в продуктовом сценарии клуб больше
  не существует отдельно от `Ровио, 3`.
- `scripts/30_build_owner_change_fix_outputs.sh`: перед сборкой XLSX удаляет
  старые canonical/double-underscore файлы, чтобы повторный запуск не падал на
  validator из-за четырех XLSX в output.

## Пересборка

Команды повторяют текущий `docs/new-backup-30-06/01_run_commands.md`.

```bash
OWNER_FIX_OUTPUT_ROOT=output/20260630_fix_owner \
OWNER_FIX_DATABASE_NAME=FitnessRestored_20260630_macos \
OWNER_FIX_SQLCMD_SERVER=mssql-fitness-2022,1433 \
OWNER_FIX_CUTOFF_DATE=2026-06-30 \
OWNER_FIX_CUTOFF_AT="2026-06-30 23:27:03" \
OWNER_FIX_BACKUP_FINISH_AT="2026-06-30 23:27:03" \
OWNER_FIX_DATE_STAMP=20260630 \
OWNER_FIX_RUN_LABEL=20260630_fix_owner_raw \
OWNER_FIX_LOGS_DIR=logs/new-backup-30-06/owner_change \
scripts/30_build_owner_change_fix_outputs.sh
```

Результат: `verdict=PASS`, `main_xlsx_rows=65231`, `cards_xlsx_rows=10907`.

```bash
MEMBERSHIP_SOURCE_OUTPUT_ROOT=output/20260630_fix_owner \
MEMBERSHIP_OUTPUT_ROOT=output/20260630_fix_owner_new_import \
MEMBERSHIP_DATABASE_NAME=FitnessRestored_20260630_macos \
MEMBERSHIP_SQLCMD_SERVER=mssql-fitness-2022,1433 \
MEMBERSHIP_DATE_STAMP=20260630 \
MEMBERSHIP_LOG_ROOT=logs/new-backup-30-06/membership \
scripts/31_build_membership_import_outputs.sh
```

Результат: membership validation/recheck `PASS`, `client membership rows=98944`,
`membership template rows=114`.

```bash
SERVICES_SOURCE_OUTPUT_ROOT=output/20260630_fix_owner \
SERVICES_OUTPUT_ROOT=output/20260630_fix_owner_new_import \
SERVICES_DATABASE_NAME=FitnessRestored_20260630_macos \
SERVICES_SQLCMD_SERVER=mssql-fitness-2022,1433 \
SERVICES_DATE_STAMP=20260630 \
SERVICES_LOG_ROOT=logs/new-backup-30-06/services \
scripts/32_build_services_import_outputs.sh
```

Результат: services validation `PASS`, `client rows=528`, `template rows=51`.

```bash
ACTIVE_PROBLEM_OUTPUT_DIR=output/20260630_fix_owner_new_import \
ACTIVE_PROBLEM_DATE_STAMP=20260630 \
ACTIVE_PROBLEM_CUTOFF_DATE=2026-06-30 \
python3 scripts/36_build_active_problem_case_workbooks.py
```

Результат: active-problem counts не изменились: `3`, `41`, `179`.

Дополнительно пересобраны:

```bash
python3 scripts/21_build_payment_price_manual_review_examples.py \
  --output-dir output/20260630_fix_owner_new_import \
  --date-stamp 20260630

python3 scripts/22_build_membership_representative_examples.py \
  --output-dir output/20260630_fix_owner_new_import \
  --date-stamp 20260630 \
  --report-md docs/new-backup-30-06/05_representative_membership_examples.md

python3 scripts/39_compare_backup_xlsx_outputs.py
python3 scripts/40_analyze_new_backup_problem_status.py
```

## Проверка эффекта

`output/20260630_fix_owner/staging/final_funnel_clients.csv`:

```text
final_funnel_rows: 73292
final_normalized_karelsky: 0
final_normalized_rovio: 9170
final_manager_karelsky_fallback: 0
```

`output/20260630_fix_owner/staging/stg_sales_all.csv`:

```text
raw_club_karelsky: 44873
normalized_karelsky: 0
normalized_rovio: 57069
```

`output/20260630_fix_owner/staging/stg_subscriptions_all.csv`:

```text
raw_club_karelsky: 14108
normalized_karelsky: 0
normalized_rovio: 17506
```

`output/20260630_fix_owner/reports/branch_distribution_by_club.csv` теперь
содержит только:

```text
Коммунальная, 20 -> Фитнес Империя (Гоголевский): 40477
Лососинское шоссе, 26 -> Фитнес Империя (Столица): 8547
Ровио, 3 -> Фитнес Империя (Ровио): 8374
Промышленная, 10 -> Фитнес Империя (Промышленная): 7833
```

Вывод: текущий нормализованный/product-club слой больше не содержит
`Карельский (закрыт)`. Исторический факт Карельского сохранен только в `raw_club`.
