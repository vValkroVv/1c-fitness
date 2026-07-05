# Part 2 Combined Single-Stage Validation Report

Run date: `2026-07-05T20:55:07`
cutoff_date: `2026-06-30`
date_stamp: `20260630`
stage_rows: `73292`
main_expected_rows_after_filters: `65231`
cards_expected_rows_after_filters: `10907`
main_xlsx_rows: `65231`
cards_xlsx_rows: `10907`
same_phone_deduplication_removed: `2388`

## Verdict

`PASS`

## Final Single-Stage Distribution

- `Реактивация(годовые абонементы)` / `Все закрытые абонементы`: `28617`
- `новые заявки` / `неразобранные`: `25707`
- `Действующие абонементы` / `Все действующие абонементы`: `10907`

## Branch Distribution

- `Фитнес Империя (Гоголевский)`: `40477`
- `Фитнес Империя (Столица)`: `8547`
- `Фитнес Империя (Ровио)`: `8374`
- `Фитнес Империя (Промышленная)`: `7833`

## Data Quality Counts

- missing_phone: `6086`
- exported_main_missing_phone: `413`
- excluded_new_applications_without_phone: `5673`
- same_phone_deduplication_removed: `2388`
- missing_card: `22707`
- missing_club: `0`
- multiple_subscription_clients: `13314`
- product_review_rows: `25`

## Errors

None.

## Warnings

- product classification rows needing business review: 25
- new application rows without phone excluded from main XLSX: 5673
- same-phone duplicate clients excluded from main XLSX: 2388
- clients without phone still present outside new applications in main XLSX: 413
- clients without selected card in full stage and reported: 22707
- clients with multiple subscription candidates reported: 13314
