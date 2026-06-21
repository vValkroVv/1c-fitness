# Step 23: final validation for 2026-05-25 08:00 MSK

Run date: `2026-05-24`

## Goal

Validate the two combined single-stage Fitbase XLSX files:

```text
output/part2_20260525_0800_final_combined/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
output/part2_20260525_0800_final_combined/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx
```

## Command

```bash
python3 scripts/18_validate_combined_single_stage_outputs.py \
  --cutoff-date 2026-05-25 \
  --date-stamp 20260525_0800 \
  --stage-dir output/part2_20260525_0800_final/staging \
  --output-dir output/part2_20260525_0800_final_combined \
  --reports-dir output/part2_20260525_0800_final/reports \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --branches-config config/branches_by_club.yml \
  --main-require-phone-for-new-applications \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription
```

## Result

Validation report:

```text
output/part2_20260525_0800_final/reports/validation_report.md
```

Verdict:

```text
PASS
```

Checked:

```text
2 final XLSX exist: PASS
headers match templates: PASS
main rows match final_funnel_clients.csv after export filters: PASS
cards rows match internal Действующие клиенты after export filters: PASS
only 3 customer final funnel values: PASS
only 3 customer final funnel_step values: PASS
old multi-stage names absent from final XLSX: PASS
duplicate client_ref/client_id absent: PASS
new application rows without phone absent from main XLSX: PASS
duplicate normalized phone groups absent from main XLSX: PASS
duplicate normalized phone groups absent from card XLSX: PASS
duplicate non-empty plastic card numbers absent from card XLSX: PASS
branch column `филиал` present in import_заявки: PASS
branch values match allowed Fitbase branch list: PASS
Карельский (закрыт) maps to Фитнес Империя (Ровио): PASS
quality reports exist and match stage: PASS
```

Branch distribution:

```text
Фитнес Империя (Гоголевский): 40449
Фитнес Империя (Столица): 8492
Фитнес Империя (Ровио): 8260
Фитнес Империя (Промышленная): 7790
```

Final single-stage distribution:

```text
новые заявки / неразобранные: 25676
Действующие абонементы / Все действующие абонементы: 10691
Реактивация(годовые абонементы) / Все закрытые абонементы: 28624
```

Filtered output row counts:

```text
main_xlsx_rows: 64991
cards_xlsx_rows: 10691
excluded_new_applications_without_phone: 5481
same_phone_deduplication_removed: 2390
```

Warnings are documented, not blocking:

```text
product_review_rows: 25
missing_phone: 6054
missing_card: 22475
multiple_subscription_clients: 13263
```

The full stage still contains all `72862` clients for audit. The export filter
details are documented in:

```text
docs/step_25_part2_20260525_export_filters.md
docs/step_26_part2_20260525_phone_deduplication.md
docs/step_27_part2_20260525_branch_column.md
output/part2_20260525_0800_final/reports/export_filter_rules.md
```
