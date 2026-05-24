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
  --cards-template "task-desc/Пластиковая карта.xlsx"
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
main rows match final_funnel_clients.csv: PASS
cards rows match final_funnel_clients.csv: PASS
only 3 customer final funnel values: PASS
only 3 customer final funnel_step values: PASS
old multi-stage names absent from final XLSX: PASS
duplicate client_ref/client_id absent: PASS
quality reports exist and match stage: PASS
```

Final single-stage distribution:

```text
новые заявки / неразобранные: 34105
Действующие абонементы / Все действующие абонементы: 10749
Реактивация(годовые абонементы) / Все закрытые абонементы: 28008
```

Warnings are documented, not blocking:

```text
product_review_rows: 68
missing_phone: 6054
missing_card: 22475
multiple_subscription_clients: 12642
```
