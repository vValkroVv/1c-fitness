# Final XLSX export filters

These rules are applied only when writing the final Fitbase XLSX files.
The source `final_funnel_clients.csv` remains complete for audit and reports.

## Applied rules

- Main `import_заявки` XLSX: `Новые заявки` rows without a phone are excluded.
- Plastic-card XLSX: only internal funnel `Действующие клиенты` is exported.

## Counts

- source_stage_clients: `73292`
- main_xlsx_clients: `65231`
- cards_xlsx_clients: `10907`
- main_excluded_total: `8061`
- main_excluded_new_applications_without_phone: `5673`
- cards_excluded_not_matching_filter: `62385`
- phone_deduplication_removed_clients: `2388`

## Distribution

- `Действующие клиенты`: source `10971`, missing phone `13`, main XLSX `10907`, cards XLSX `10907`
- `Новые заявки`: source `33396`, missing phone `5673`, main XLSX `25707`, cards XLSX `0`
- `Реактивация`: source `28925`, missing phone `400`, main XLSX `28617`, cards XLSX `0`
