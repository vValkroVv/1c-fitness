# Business Notes

Date: 2026-05-07

## Target segment

Only the segment `Действующие клиенты` should be exported to the final Fitbase
files.

## Main Fitbase import file

Template:

```text
task-desc/Копия Импорт_заявки.xlsx
```

Output:

```text
output/fitbase_active_clients_import_zayavki_YYYYMMDD.xlsx
```

Business fill rules confirmed from the plan:

| Field | Rule |
|---|---|
| `client_id` | internal client number/code from 1C |
| `phone` | all client phones as in 1C, multiple values comma-separated |
| `client_fio` | client full name |
| `email` | all client emails comma-separated, if present |
| `funnel` | always `Действующие клиенты` |
| `funnel_step` | derived by the stage algorithm from the plan |
| `budget` | always `0` |
| `create_date` | first date when the client appeared in the database through any sale: membership, 7 days, 1 day, trial day, etc.; not a visit date from CSV |
| `manager` | deterministic even distribution among `A1`, `A2`, `A3` |

Template rows:

```text
row 1: preserve unchanged
row 2: preserve unchanged
row 3: example row, replace/clear
data starts at row 3
```

## Plastic cards file

Template:

```text
task-desc/Пластиковая карта.xlsx
```

Output:

```text
output/fitbase_active_clients_plastic_cards_YYYYMMDD.xlsx
```

Business fill rules confirmed from the plan:

| Field | Rule |
|---|---|
| `телефон` | all client phones comma-separated |
| `фио` | client full name |
| `номер пластиковой карты` | all active/unmarked plastic cards from 1C comma-separated; empty if not found and report separately |

Template rows:

```text
row 1: preserve unchanged
data starts at row 2
```

## Required reports

The final pipeline must produce:

```text
validation_report.md
stage_distribution.csv
duplicates_report.csv
missing_required_fields.csv
missing_sales_report.csv
missing_cards_report.csv
multiple_active_subscriptions_report.csv
multiple_cards_report.csv
booking_without_active_subscription_report.csv
table_mapping_report.md
schema_inventory.csv
```

## Important exclusion

Clients with booking flag but without active subscription must not be included
in the main XLSX without a separate decision.
