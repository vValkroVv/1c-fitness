# Step 27: final branch column for 2026-05-25 08:00 MSK

Run date: `2026-05-25`

## Customer request

Add a `филиал` column to the final `import_заявки` XLSX.

Allowed values:

```text
Фитнес Империя (Гоголевский)
Фитнес Империя (Промышленная)
Фитнес Империя (Ровио)
Фитнес Империя (Столица)
```

## Implementation

The branch is assigned from `normalized_club` using:

```text
config/branches_by_club.yml
```

Mapping:

```text
Коммунальная, 20 -> Фитнес Империя (Гоголевский)
Лососинское шоссе, 26 -> Фитнес Империя (Столица)
Промышленная, 10 -> Фитнес Империя (Промышленная)
Ровио, 3 -> Фитнес Империя (Ровио)
Карельский (закрыт) -> Фитнес Империя (Ровио)
```

Important: `Карельский (закрыт)` is intentionally exported as
`Фитнес Империя (Ровио)`.

The column is added only to `import_заявки`. The plastic-card XLSX keeps the
same 3-column template.

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
  --branches-config config/branches_by_club.yml \
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
  --branches-config config/branches_by_club.yml \
  --main-require-phone-for-new-applications \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription
```

Result:

```text
verdict=PASS
errors=0
```

Checked:

```text
import_заявки columns: 10
last column: филиал
branch values are only from the allowed 4-value list: PASS
branch distribution matches normalized_club mapping: PASS
Карельский (закрыт) maps to Фитнес Империя (Ровио): PASS
```

Branch distribution in final `import_заявки`:

```text
Фитнес Империя (Гоголевский): 40449
Фитнес Империя (Столица): 8492
Фитнес Империя (Ровио): 8260
Фитнес Империя (Промышленная): 7790
```

Club-to-branch distribution:

```text
Коммунальная, 20 -> Фитнес Империя (Гоголевский): 40449
Лососинское шоссе, 26 -> Фитнес Империя (Столица): 8492
Промышленная, 10 -> Фитнес Империя (Промышленная): 7790
Карельский (закрыт) -> Фитнес Империя (Ровио): 5594
Ровио, 3 -> Фитнес Империя (Ровио): 2666
```

Reports:

```text
output/part2_20260525_0800_final/reports/branch_distribution.csv
output/part2_20260525_0800_final/reports/branch_distribution_by_club.csv
```
