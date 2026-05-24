# Step 26: final same-phone deduplication for 2026-05-25 08:00 MSK

Run date: `2026-05-24`

## Customer rule

Customer comment from `2026-05-24 18:02-18:03`:

```text
Такое удаляем.
Оставляем таких клиентов либо действующих, либо в реактивации.
Вообще по номеру телефону должен остаться один клиент с самым свежим приобретенным абонементом.
```

## Applied rule

Before writing the final XLSX files, rows are deduplicated by normalized phone
component.

If several rows share the same normalized phone, the export keeps one row:

1. prefer a row with a selected/purchased subscription;
2. among subscription rows, keep the row with the latest
   `selected_subscription_sale_date`;
3. if needed, use latest subscription end/start dates as tie-breakers;
4. if no subscription exists in the phone component, keep the latest fallback
   row by create date/client id.

This is applied after the previous export filter:

```text
Новые заявки without phone are not exported to import_заявки.
```

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

Removed by original internal funnel:

```text
Новые заявки: 2023
Реактивация: 308
Действующие клиенты: 59
```

Winner funnel for removed rows:

```text
Реактивация: 1228
Новые заявки: 623
Действующие клиенты: 539
```

Deduplication reports:

```text
output/part2_20260525_0800_final/reports/phone_deduplication_removed_clients.csv
output/part2_20260525_0800_final/reports/phone_deduplication_summary.csv
```

## Validation

Command:

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

Result:

```text
verdict=PASS
errors=0
```

The explicit duplicate-check script was also run:

```bash
python3 scripts/check_import_zayavki_implicit_duplicates.py
```

Console result:

```text
xlsx_rows=64991
phone_groups_with_multiple_rows=0
duplicate_phone_extra_rows=0
same_phone_different_fio_candidate_groups=0
```

Plastic-card XLSX was checked separately:

```text
cards_rows=10691
cards_duplicate_phone_groups=0
cards_duplicate_nonempty_card_numbers=0
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
