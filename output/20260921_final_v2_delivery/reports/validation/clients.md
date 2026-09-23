# Part 2 Combined Single-Stage Validation Report

Run date: `2026-09-21T02:02:43`
cutoff_date: `2026-09-21`
date_stamp: `20260921`
stage_rows: `74453`
main_expected_rows_after_filters: `40508`
cards_expected_rows_after_filters: `11131`
main_xlsx_rows: `40508`
cards_xlsx_rows: `11131`
same_phone_deduplication_removed: `2388`
new_application_refusers_to_membership: `25840`

## Verdict

`PASS`

## Final Single-Stage Distribution

- `Реактивация` / `Закрытые годовые абонементы`: `29377`
- `Действующие абонементы` / `Все действующие абонементы`: `11131`

## Branch Distribution

- `Фитнес Империя (Гоголевский)`: `23405`
- `Фитнес Империя (Столица)`: `6220`
- `Фитнес Империя (Ровио)`: `5739`
- `Фитнес Империя (Промышленная)`: `5144`

## Data Quality Counts

- missing_phone: `6158`
- exported_main_missing_phone: `441`
- excluded_new_applications_without_phone: `5717`
- new_application_refusers_to_membership: `25840`
- same_phone_deduplication_removed: `2388`
- missing_card: `23224`
- missing_club: `0`
- multiple_subscription_clients: `14042`
- product_review_rows: `28`

## Errors

None.

## Warnings

- product classification rows needing business review: 28
- new application rows without phone excluded from main XLSX: 5717
- new application/refuser rows moved to membership import: 25840
- same-phone duplicate clients excluded from main XLSX: 2388
- clients without phone still present outside new applications in main XLSX: 441
- clients without selected card in full stage and reported: 23224
- clients with multiple subscription candidates reported: 14042
