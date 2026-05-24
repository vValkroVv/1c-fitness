# Final XLSX export filters

These rules are applied only when writing the final Fitbase XLSX files.
The source `final_funnel_clients.csv` remains complete for audit and reports.

## Applied rules

- Main `import_заявки` XLSX: `Новые заявки` rows without a phone are excluded.
- Plastic-card XLSX: only internal funnel `Действующие клиенты` is exported.

## Counts

- source_stage_clients: `72862`
- main_xlsx_clients: `64991`
- cards_xlsx_clients: `10691`
- main_excluded_total: `7871`
- main_excluded_new_applications_without_phone: `5481`
- cards_excluded_not_matching_filter: `62171`
- phone_deduplication_removed_clients: `2390`

## Distribution

- `Действующие клиенты`: source `10750`, missing phone `12`, main XLSX `10691`, cards XLSX `10691`
- `Новые заявки`: source `33180`, missing phone `5481`, main XLSX `25676`, cards XLSX `0`
- `Реактивация`: source `28932`, missing phone `561`, main XLSX `28624`, cards XLSX `0`
