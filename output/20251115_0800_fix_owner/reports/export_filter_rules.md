# Final XLSX export filters

These rules are applied only when writing the final Fitbase XLSX files.
The source `final_funnel_clients.csv` remains complete for audit and reports.

## Applied rules

- Main `import_заявки` XLSX: `Новые заявки` rows without a phone are excluded.
- Plastic-card XLSX: only internal funnel `Действующие клиенты` is exported.

## Counts

- source_stage_clients: `72862`
- main_xlsx_clients: `64934`
- cards_xlsx_clients: `10890`
- main_excluded_total: `7928`
- main_excluded_new_applications_without_phone: `5538`
- cards_excluded_not_matching_filter: `61972`
- phone_deduplication_removed_clients: `2390`

## Distribution

- `Действующие клиенты`: source `10955`, missing phone `11`, main XLSX `10890`, cards XLSX `10890`
- `Новые заявки`: source `33104`, missing phone `5538`, main XLSX `25545`, cards XLSX `0`
- `Реактивация`: source `28803`, missing phone `505`, main XLSX `28499`, cards XLSX `0`
