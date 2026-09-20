# Part 2 Combined Single-Stage Validation Report

Run date: `2026-08-20T23:41:40`
cutoff_date: `2026-06-30`
date_stamp: `20260630`
stage_rows: `73292`
main_expected_rows_after_filters: `39550`
cards_expected_rows_after_filters: `11024`
main_xlsx_rows: `39550`
cards_xlsx_rows: `11024`
same_phone_deduplication_removed: `2388`
new_application_refusers_to_membership: `25676`

## Verdict

`PASS`

## Final Single-Stage Distribution

- `Реактивация` / `Закрытые годовые абонементы`: `28526`
- `Действующие абонементы` / `Все действующие абонементы`: `11024`

## Branch Distribution

- `Фитнес Империя (Гоголевский)`: `22672`
- `Фитнес Империя (Столица)`: `6143`
- `Фитнес Империя (Ровио)`: `5675`
- `Фитнес Империя (Промышленная)`: `5060`

## Data Quality Counts

- missing_phone: `6086`
- exported_main_missing_phone: `408`
- excluded_new_applications_without_phone: `5678`
- new_application_refusers_to_membership: `25676`
- same_phone_deduplication_removed: `2388`
- missing_card: `22707`
- missing_club: `0`
- multiple_subscription_clients: `13169`
- product_review_rows: `25`

## Errors

None.

## Warnings

- product classification rows needing business review: 25
- new application rows without phone excluded from main XLSX: 5678
- new application/refuser rows moved to membership import: 25676
- same-phone duplicate clients excluded from main XLSX: 2388
- clients without phone still present outside new applications in main XLSX: 408
- clients without selected card in full stage and reported: 22707
- clients with multiple subscription candidates reported: 13169
