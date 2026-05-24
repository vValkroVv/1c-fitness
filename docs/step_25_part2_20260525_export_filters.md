# Step 25: final XLSX export filters for 2026-05-25 08:00 MSK

Run date: `2026-05-24`

## Goal

Apply the final customer export filters on top of the already audited
`output/part2_20260525_0800_final/staging/final_funnel_clients.csv`.

The source stage remains complete for audit:

```text
source_stage_clients: 72862
```

The filters are applied only to the two final XLSX files.

## Applied rules

1. Main `import_заявки` XLSX:
   keep `новые заявки / неразобранные` only when the client has a phone.
2. Plastic-card XLSX:
   export only the internal `Действующие клиенты` category.

## Build command

```bash
python3 scripts/17_build_part2_combined_xlsx.py \
  --cutoff-date 2026-05-25 \
  --date-stamp 20260525_0800 \
  --stage-dir output/part2_20260525_0800_final/staging \
  --output-dir output/part2_20260525_0800_final_combined \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --managers-config config/managers_by_club.yml \
  --fitbase-label-mode customer_20260520_single_stage \
  --main-require-phone-for-new-applications \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription
```

Result:

```text
source_rows=72862
main_xlsx_rows=64991
cards_xlsx_rows=10691
phone_deduplication_removed_rows=2390
```

## Filter impact

```text
Новые заявки:
  source: 33180
  without phone excluded from main XLSX: 5481
  main XLSX after same-phone dedupe: 25676

Действующие клиенты:
  source: 10750
  main XLSX after same-phone dedupe: 10691
  plastic-card XLSX: 10691

Реактивация:
  source: 28932
  main XLSX after same-phone dedupe: 28624
  plastic-card XLSX: 0
```

Same-phone deduplication is documented separately:

```text
docs/step_26_part2_20260525_phone_deduplication.md
```

Detailed filter reports:

```text
output/part2_20260525_0800_final/reports/export_filter_rules.md
output/part2_20260525_0800_final/reports/export_filter_summary.csv
output/part2_20260525_0800_final/reports/export_filter_funnel_distribution.csv
```

## Validation command

```bash
python3 scripts/18_validate_combined_single_stage_outputs.py \
  --cutoff-date 2026-05-25 \
  --date-stamp 20260525_0800 \
  --stage-dir output/part2_20260525_0800_final/staging \
  --output-dir output/part2_20260525_0800_final_combined \
  --reports-dir output/part2_20260525_0800_final/reports \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --main-require-phone-for-new-applications \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription
```

Validation result:

```text
verdict=PASS
errors=0
```

Checked:

```text
main XLSX rows: 64991
plastic-card XLSX rows: 10691
new application rows without phone in main XLSX: 0
duplicate normalized phone groups in main XLSX: 0
duplicate normalized phone groups in plastic-card XLSX: 0
duplicate client_id rows in main XLSX: 0
duplicate non-empty plastic card numbers in card XLSX: 0
only customer single-stage funnel/stage names in main XLSX: PASS
plastic-card XLSX rows match kept internal Действующие клиенты rows: PASS
```

Final main XLSX distribution:

```text
новые заявки / неразобранные: 25676
Действующие абонементы / Все действующие абонементы: 10691
Реактивация(годовые абонементы) / Все закрытые абонементы: 28624
```

Final files:

```text
output/part2_20260525_0800_final_combined/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
output/part2_20260525_0800_final_combined/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx
```
