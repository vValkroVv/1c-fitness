# Part 2 Combined Single-Stage Validation Report

Run date: `2026-06-22T11:57:17`
cutoff_date: `2026-05-25`
date_stamp: `20260525_0800`
stage_rows: `72862`
main_expected_rows_after_filters: `64934`
cards_expected_rows_after_filters: `10890`
main_xlsx_rows: `64934`
cards_xlsx_rows: `10890`
same_phone_deduplication_removed: `2390`

## Verdict

`PASS`

## Final Single-Stage Distribution

- `Реактивация(годовые абонементы)` / `Все закрытые абонементы`: `28499`
- `новые заявки` / `неразобранные`: `25545`
- `Действующие абонементы` / `Все действующие абонементы`: `10890`

## Branch Distribution

- `Фитнес Империя (Гоголевский)`: `40450`
- `Фитнес Империя (Столица)`: `8459`
- `Фитнес Империя (Ровио)`: `8255`
- `Фитнес Империя (Промышленная)`: `7770`

## Data Quality Counts

- missing_phone: `6054`
- exported_main_missing_phone: `516`
- excluded_new_applications_without_phone: `5538`
- same_phone_deduplication_removed: `2390`
- missing_card: `22475`
- missing_club: `0`
- multiple_subscription_clients: `13042`
- product_review_rows: `25`

## Errors

None.

## Warnings

- product classification rows needing business review: 25
- new application rows without phone excluded from main XLSX: 5538
- same-phone duplicate clients excluded from main XLSX: 2390
- clients without phone still present outside new applications in main XLSX: 516
- clients without selected card in full stage and reported: 22475
- clients with multiple subscription candidates reported: 13042
