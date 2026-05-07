# Execution Log: step 10 primary schema inventory

Date: 2026-05-07
Workspace: `/root/workspace/1c-fitness`
Plan step: `## 10. Первичная инвентаризация таблиц SQL Server / 1C`

## Runtime

```text
container: mssql-fitness
database: FitnessRestored
state: ONLINE
```

## SQL files created

```text
sql/03_schema_inventory.sql
sql/03_schema_inventory_csv.sql
sql/03_schema_tables_csv.sql
sql/03_schema_inventory_summary.sql
```

Purpose:

| File | Purpose |
|---|---|
| `sql/03_schema_inventory.sql` | raw human-readable table and column inventory |
| `sql/03_schema_inventory_csv.sql` | machine-readable column-level inventory |
| `sql/03_schema_tables_csv.sql` | machine-readable table-level inventory |
| `sql/03_schema_inventory_summary.sql` | summary counts and top tables |

## Outputs

Required output:

```text
output/schema_inventory.csv
logs/schema_inventory.txt
```

Additional useful output:

```text
output/schema_tables.csv
logs/schema_inventory_summary.txt
```

Exit codes:

```text
logs/schema_inventory.exit: 0
logs/schema_inventory_csv.exit: 0
logs/schema_tables_csv.exit: 0
logs/schema_inventory_summary.exit: 0
```

## CSV validation

`output/schema_inventory.csv`:

```text
rows including header: 19422
data rows: 19421
header columns: 10
level: one row per user table column
```

Columns:

```text
schema_name
table_name
approx_rows
column_id
column_name
sql_type
max_length
precision
scale
is_nullable
```

`output/schema_tables.csv`:

```text
rows including header: 2504
data rows: 2503
header columns: 4
level: one row per user table
```

Columns:

```text
schema_name
table_name
approx_rows
column_count
```

## Summary counts

From `logs/schema_inventory_summary.txt`:

```text
user_tables_count: 2503
user_columns_count: 19421
Config table present: 1
_Reference tables: 427
_Document tables: 208
_InfoRg tables: 596
_AccumRg tables: 193
_Enum tables: 240
_Const tables: 580
_Chrc tables: 21
_Task tables: 4
_DocumentJournal tables: 6
```

## Largest tables by approximate row count

Top observed tables:

| Table | Approx rows | Columns |
|---|---:|---:|
| `dbo._InfoRg2567` | `19,791,206` | `9` |
| `dbo._AccRgED4729` | `8,363,806` | `10` |
| `dbo._AccumRg3336` | `7,236,853` | `24` |
| `dbo._AccumRgT3353` | `6,490,567` | `18` |
| `dbo._Document150` | `3,012,966` | `42` |
| `dbo._AccRgAT14723` | `2,531,090` | `17` |
| `dbo._AccRgAT24724` | `2,319,670` | `20` |
| `dbo._Seq3373` | `2,238,889` | `5` |
| `dbo._AccRg4711` | `1,656,572` | `56` |
| `dbo._DocumentJournal1621` | `1,177,049` | `16` |

## Notes

The database clearly has 1C-style technical table names. At this stage no
business meaning is assigned to `_ReferenceXXX`, `_DocumentXXX`, `_InfoRgXXX`,
or `_AccumRgXXX` tables. Mapping must be discovered through samples,
metadata, and relationship tracing in later steps.

## Decision

Step 10 passed.

Allowed next action:

```text
Proceed to candidate table discovery for clients, contacts, subscriptions,
sales, bookings, and plastic cards.
```
