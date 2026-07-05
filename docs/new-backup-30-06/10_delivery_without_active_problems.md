# Delivery without active problem cases

Дата: 2026-07-06

## Задача

Собрать одну папку с 9 XLSX-файлами:

- 6 финальных XLSX для передачи, но без активных проблемных строк по абонементам;
- 3 отдельных XLSX с вынесенными проблемами `problem_1`, `problem_2`, `problem_3`.

Проблемные строки определялись по активным контрольным файлам из текущей сборки:

- `active_problem_1_no_payment_cash_3_cases_20260630.xlsx`
- `active_problem_2_zero_price_direct_full_41_cases_20260630.xlsx`
- `active_problem_3_non_named_payment_left_179_cases_20260630.xlsx`

## Выходная папка

```text
output/20260630_delivery_without_active_problems/
```

## Правило фильтрации

Из полного файла `fitbase_import_abonementy_clientov_20260630.xlsx` удалены строки, у которых `contract_id` попадает в объединение трех активных проблемных наборов.

Остальные 5 финальных XLSX скопированы без изменений, потому что эти 3/41/179 проблемных кейсов относятся к строкам импорта абонементов клиентов.

## Контроль

Уникальных проблемных `contract_id`: `223`.

Из полного файла абонементов удалено строк: `223`.

После фильтрации в полном файле абонементов не осталось ни одного `contract_id` из трех проблемных наборов.

## Итоговые файлы

| file | data rows | cols |
| --- | ---: | ---: |
| `fitbase_active_clients_import_zayavki_20260630_all_funnels.xlsx` | 39525 | 10 |
| `fitbase_active_clients_plastic_cards_20260630_all_funnels.xlsx` | 10907 | 3 |
| `fitbase_import_abonementy_clientov_20260630.xlsx` | 119818 | 21 |
| `fitbase_import_shablony_abonementov_20260630.xlsx` | 115 | 12 |
| `fitbase_import_shablony_uslug_20260630.xlsx` | 52 | 9 |
| `fitbase_import_uslugi_clientov_20260630.xlsx` | 523 | 16 |
| `problem_1_no_payment_cash_3_cases_20260630.xlsx` | 3 | 21 |
| `problem_2_zero_price_direct_full_41_cases_20260630.xlsx` | 41 | 21 |
| `problem_3_non_named_payment_left_179_cases_20260630.xlsx` | 179 | 21 |

