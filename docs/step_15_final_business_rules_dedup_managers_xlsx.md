# Step 15: Business Rules, Deduplication, Managers, XLSX

Date: 2026-05-07

Plan sections covered:

```text
## 13. Бизнес-правила отбора и этапов
## 14. Дедупликация клиентов
## 15. Менеджеры
## 16. Генерация двух XLSX-файлов
```

## Inputs

Final generation uses the staging package built for backup cutoff date
`2026-04-29`:

```text
output/staging_2026-04-29/mart_active_clients.csv
output/staging_2026-04-29/stg_bookings.csv
task-desc/Копия Импорт_заявки.xlsx
task-desc/Пластиковая карта.xlsx
```

Command:

```bash
scripts/build_fitbase_xlsx.py
```

## Configs

| Config | Purpose |
|---|---|
| `config/stage_rules.yml` | fixed active-client and funnel-stage rules |
| `config/managers.yml` | deterministic temporary managers `A1`, `A2`, `A3` |

Managers are assigned deterministically:

```text
manager = managers[sha256(client_id) % len(managers)]
```

This replaces the staging preview manager value and keeps assignment stable
between runs.

## Business Rules Applied

- Cutoff date: `2026-04-29`.
- Active clients include all active products on cutoff date, including 1-day,
  7-day, trial-day, and other short active products.
- `duration_days` / `active_subscription_duration_days` is audit only and does
  not exclude clients.
- Funnel is always `Действующие клиенты`.
- Funnel step priority is `Бронь`, then `60-31`, then `30-8`, then `7-0`, then
  `Действующие клиенты`.
- `budget = 0`.
- `create_date = first_sale_date`; client card creation date is not used as a
  replacement.
- Clients missing phone/FIO/create date are still exported and reported.

## Deduplication

Automatic merge rule:

```text
normalized_fio + normalized_phones_set
```

No extra heuristics were used. Exact duplicate groups found: `0`, so the final
row count did not decrease.

Potential duplicate signals were report-only:

| Signal | Groups |
|---|---:|
| Same normalized phone, different FIO | 53 |
| Same normalized FIO, different phone set | 38 |

Report:

```text
output/duplicates_report.csv
```

## Final Outputs

| File | Rows |
|---|---:|
| `output/fitbase_active_clients_import_zayavki_20260429.xlsx` | 10,796 |
| `output/fitbase_active_clients_plastic_cards_20260429.xlsx` | 10,796 |
| `output/final_active_clients_20260429.csv` | 10,796 |

The main XLSX keeps exactly these 9 columns:

```text
client_id, phone, client_fio, email, funnel, funnel_step, budget, create_date, manager
```

The plastic-card XLSX keeps exactly these 3 columns:

```text
телефон, фио, номер пластиковой карты
```

## Distributions

Funnel steps:

| Funnel step | Clients |
|---|---:|
| `Действующие клиенты` | 9,422 |
| `60-31 день до окончания` | 575 |
| `30-8 дней до окончания` | 504 |
| `7-0 день до окончания` | 178 |
| `Бронь` | 117 |

Managers:

| Manager | Clients |
|---|---:|
| `A3` | 3,632 |
| `A2` | 3,617 |
| `A1` | 3,547 |

## Data-Quality Reports

| Report | Rows excluding header |
|---|---:|
| `output/missing_required_fields.csv` | 11 |
| `output/missing_sales_report.csv` | 0 |
| `output/missing_cards_report.csv` | 243 |
| `output/multiple_active_subscriptions_report.csv` | 471 |
| `output/multiple_cards_report.csv` | 7,570 |
| `output/booking_without_active_subscription_report.csv` | 0 |

## Validation

`output/validation_report.md` verdict:

```text
PASS
```

Checked:

- XLSX headers match templates.
- Main XLSX has 10,796 data rows.
- Plastic-card XLSX has 10,796 data rows.
- No duplicate `client_id` remains.
- No duplicate exact `ФИО + phone set` remains.
- Funnel/stage/budget rules are valid.
- Booking priority is respected.
- Date-boundary stages are valid.
- Plastic card numbers are not duplicated.

## Remaining For Fitbase Mini-Test

- Confirm that Fitbase accepts `create_date` as an Excel date with
  `yyyy-mm-dd` number format.
- Multiple active subscriptions are reported and not silently resolved.
- Multiple plastic cards are reported; export writes all active/unmarked card
  numbers comma-separated in the `номер пластиковой карты` cell.
