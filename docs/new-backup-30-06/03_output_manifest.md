# Новый backup 2026-06-30: manifest итоговых файлов

> Архивный manifest первой сборки. Актуальные девять файлов и счётчики зафиксированы в
> `docs/20260630_full_cutoff_rebuild_20260714.md`.

Дата сборки: `2026-07-05`

Backup:

```text
data/Fitnes-30-06-26.bak
```

Database:

```text
FitnessRestored_20260630_macos
```

Cutoff:

```text
2026-06-30 23:27:03
```

## Owner-change / заявки / пластиковые карты

Папка:

```text
output/20260630_fix_owner/
```

Файлы:

```text
output/20260630_fix_owner/fitbase_active_clients_import_zayavki_20260630_all_funnels.xlsx
output/20260630_fix_owner/fitbase_active_clients_plastic_cards_20260630_all_funnels.xlsx
```

Счетчики:

```text
stage final_funnel_clients: 73292
import_zayavki rows: 39524
plastic_cards rows: 10907
same-phone dedup removed: 2388
new_application_refusers moved to membership: 25707
validation: PASS
```

Отчет:

```text
output/20260630_fix_owner/reports/validation_report.md
output/20260630_fix_owner/reports/owner_change_validation.md
output/20260630_fix_owner/csv/new_application_refusers.csv
```

## Импорт абонементов

Папка:

```text
output/20260630_fix_owner_new_import/
```

Файлы:

```text
output/20260630_fix_owner_new_import/fitbase_import_abonementy_clientov_20260630.xlsx
output/20260630_fix_owner_new_import/fitbase_import_shablony_abonementov_20260630.xlsx
```

Счетчики:

```text
client membership rows: 120040
membership template rows: 114
source final clients: 65231
row clients: 64176
duplicate contract_id values: 0
missing template names: 0
refuser source clients: 25707
refuser tagged rows: 26950
refuser placeholder rows: 21096
validation: PASS
```

Отчеты:

```text
output/20260630_fix_owner_new_import/reports/validation_report.md
output/20260630_fix_owner_new_import/reports/validation_recheck.md
output/20260630_fix_owner_new_import/reports/rassrochka_validation.md
output/20260630_fix_owner_new_import/reports/membership_import_uncertainties.csv
output/20260630_fix_owner_new_import/reports/membership_branch_distribution.csv
```

## Импорт услуг

Файлы:

```text
output/20260630_fix_owner_new_import/fitbase_import_uslugi_clientov_20260630.xlsx
output/20260630_fix_owner_new_import/fitbase_import_shablony_uslug_20260630.xlsx
```

Счетчики:

```text
client service rows: 522
service template rows: 51
services represented in client rows: 44
template-only services: 7
duplicate service_id values: 0
validation: PASS
```

Отчеты:

```text
output/20260630_fix_owner_new_import/reports/services_build_report.md
output/20260630_fix_owner_new_import/reports/services_validation_report.md
output/20260630_fix_owner_new_import/reports/services_coverage_report.csv
output/20260630_fix_owner_new_import/reports/services_active_rows_audit.csv
output/20260630_fix_owner_new_import/reports/services_branch_distribution.csv
```

## Active-problem XLSX

Файлы:

```text
output/20260630_fix_owner_new_import/active_problem_1_no_payment_cash_3_cases_20260630.xlsx
output/20260630_fix_owner_new_import/active_problem_2_zero_price_direct_full_41_cases_20260630.xlsx
output/20260630_fix_owner_new_import/active_problem_3_non_named_payment_left_179_cases_20260630.xlsx
```

Проверка:

```text
all files have 22 import-abonement columns
duplicate contract_id inside each file: 0
contract_id intersections between active-problem files: 0
validation: PASS
```

## Review/example XLSX

Воспроизводимые review-файлы, пересобранные из свежего
`membership_import_rows.csv`:

```text
output/20260630_fix_owner_new_import/payment_price_manual_review_examples_25_after_rules_20260630.xlsx
output/20260630_fix_owner_new_import/membership_import_representative_28_examples_20260630.xlsx
```

Отчеты:

```text
output/20260630_fix_owner_new_import/reports/payment_price_manual_review_examples_report.md
docs/new-backup-30-06/05_representative_membership_examples.md
```

Старые файлы `*-with-answers.xlsx` и ручные 7-row snapshots из майского
разбора не копировались: они содержат старые ручные ответы или фиксированные
contract_id прошлого cutoff. Для свежего backup вместо них собраны полные
active-problem XLSX выше.
