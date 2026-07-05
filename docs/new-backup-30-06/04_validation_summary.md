# Новый backup 2026-06-30: validation summary

## Команды

Команды пересборки сохранены в:

```text
docs/new-backup-30-06/01_run_commands.md
```

## Результат валидаторов

```text
output/20260630_fix_owner/reports/validation_report.md: PASS
output/20260630_fix_owner/reports/owner_change_validation.md: PASS
output/20260630_fix_owner_new_import/reports/validation_recheck.md: PASS
output/20260630_fix_owner_new_import/reports/services_validation_report.md: PASS
```

## XLSX-smoke

Проверены фактические строки и колонки в итоговых workbook:

| Файл | Data rows | Cols | Status |
|---|---:|---:|---|
| `fitbase_active_clients_import_zayavki_20260630_all_funnels.xlsx` | 65231 | 10 | PASS |
| `fitbase_active_clients_plastic_cards_20260630_all_funnels.xlsx` | 10907 | 3 | PASS |
| `fitbase_import_abonementy_clientov_20260630.xlsx` | 98944 | 20 | PASS |
| `fitbase_import_shablony_abonementov_20260630.xlsx` | 114 | 12 | PASS |
| `fitbase_import_uslugi_clientov_20260630.xlsx` | 528 | 16 | PASS |
| `fitbase_import_shablony_uslug_20260630.xlsx` | 51 | 9 | PASS |
| `active_problem_1_no_payment_cash_3_cases_20260630.xlsx` | 3 | 20 | PASS |
| `active_problem_2_zero_price_direct_full_41_cases_20260630.xlsx` | 41 | 20 | PASS |
| `active_problem_3_non_named_payment_left_179_cases_20260630.xlsx` | 179 | 20 | PASS |
| `payment_price_manual_review_examples_25_after_rules_20260630.xlsx` | 25 | 24 | PASS |
| `membership_import_representative_28_examples_20260630.xlsx` | 28 | 20 | PASS |

## Warnings

Warnings остались бизнесово ожидаемыми и не блокируют сборку:

- `product_review_rows`: 25;
- новые заявки без телефона исключены из `import_заявки`: 5673;
- same-phone duplicate clients исключены из `import_заявки`: 2388;
- blank `type_of_payment` в импорте абонементов: 29287;
- услуги вне финального `import_заявки`: 1 historical fallback;
- услуги только в шаблонах: 7.
- representative examples missing categories on fresh cutoff: 2
  (`zero_direct_kept_week_site`, `zero_direct_raw_blank`).

## Owner-change named cases

| Client | Fresh cutoff result |
|---|---|
| `Успенский Леонид Владимирович` | `Действующие клиенты`, `Абонемент Ультра 15 месяцев (подарок)` |
| `Василевская Вера Михайловна` | `Действующие клиенты`, `Абонемент МУЛЬТИКАРТА 12 месяцев (подарок)` |
| `Россиева София Сергеевна` | `Действующие клиенты`, `Абонемент МУЛЬТИКАРТА 15 месяцев (подарок) спецпредложение` |
| `Бламберус Михаил Александрович` | remains `Новые заявки`, no selected subscription |

## Karelsky -> Rovio check

```text
final_normalized_karelsky: 0
final_normalized_rovio: 9170
final_manager_karelsky_fallback: 0
stg_sales_all raw_club_karelsky: 44873
stg_sales_all normalized_karelsky: 0
stg_subscriptions_all raw_club_karelsky: 14108
stg_subscriptions_all normalized_karelsky: 0
```
