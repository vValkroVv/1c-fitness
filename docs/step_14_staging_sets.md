# Step 14: Staging Sets Before XLSX

Date: 2026-05-07

Plan section: `## 12. Построить промежуточные staging-наборы`.

## Cutoff Date

The backup metadata confirms:

```text
BackupFinishDate: 2026-04-29 23:57:02
```

Therefore staging was built for real cutoff date `2026-04-29`
(`4026-04-29` inside 1C SQL date fields).

## Artifacts

SQL tables were created in restored database schema:

```text
fitbase_stg
```

CSV exports were written to:

```text
output/staging_2026-04-29/
```

This output directory is generated data and is ignored by git because it is
large (`147M` in the first run).

## Scripts And Logs

| Artifact | Purpose |
|---|---|
| `sql/06_build_staging_tables.sql` | creates `fitbase_stg.*` tables |
| `scripts/07_build_and_export_staging.py` | renders cutoff variables, runs SQL, exports CSV |
| `logs/step14_build_staging_tables.txt` | SQL build log |
| `logs/step14_export_staging_tables.txt` | CSV export log |
| `output/staging_2026-04-29/staging_summary.csv` | row counts and cutoff metadata |

Command used:

```bash
python3 scripts/07_build_and_export_staging.py \
  --cutoff-date 2026-04-29 \
  --backup-finish-at '2026-04-29 23:57:02'
```

## Row Counts

| Dataset | Rows |
|---|---:|
| `stg_clients` | 72,586 |
| `stg_client_contacts` | 66,574 |
| `stg_subscriptions` | 97,755 |
| `stg_sales` | 499,614 |
| `stg_bookings` | 395 |
| `stg_plastic_cards` | 105,524 |
| `mart_active_clients` | 10,796 |

`mart_active_clients` now includes all active products on cutoff date,
including 1-day, 7-day, trial-day, and other short active products.
`duration_days` is an audit field and is not used as an exclusion filter.
The mart has `10` clients with `is_short_duration_active = 1`.

## Mart Stage Distribution

| Funnel step | Clients |
|---|---:|
| `Действующие клиенты` | 9,422 |
| `60-31 день до окончания` | 575 |
| `30-8 дней до окончания` | 504 |
| `7-0 день до окончания` | 178 |
| `Бронь` | 117 |

## Short Active Product Distribution

| `is_short_duration_active` | Clients |
|---|---:|
| `0` | 10,786 |
| `1` | 10 |

## Validation Signals

Top `validation_status` groups:

| Status | Clients |
|---|---:|
| `multiple_plastic_cards;` | 7,201 |
| `ok` | 2,885 |
| `multiple_active_subscriptions;multiple_plastic_cards;` | 366 |
| `missing_plastic_card;` | 228 |
| `multiple_active_subscriptions;` | 92 |

Other signals:

- clients with exactly one active subscription: `10,325`;
- clients with multiple active subscriptions: `471`;
- clients with no active plastic card: `243`;
- clients with exactly one active plastic card: `2,983`;
- clients with multiple active plastic cards: `7,570`;
- clients missing phone in mart: `11`;
- clients missing first sale in mart: `0`;
- clients with short active products included by the final rule: `10`.

Note: the sales cutoff uses the full backup timestamp
`4026-04-29 23:57:02`, not midnight at the start of the day. This keeps
sales made during `2026-04-29` in `stg_sales` and prevents false missing
`create_date` rows.

These are staging signals for review before final XLSX generation. In
particular, multiple-card and multiple-active-subscription handling should be
turned into explicit final reports before writing XLSX.

## Source Rules Implemented

- Clients: `dbo._Reference64`.
- Phones: `dbo._Reference64._Fld3832`, preserved raw.
- Email: `dbo._InfoRg5255._Fld5257`, joined through `_Fld5256RRef`.
- Subscriptions: `dbo._InfoRg3060 + dbo._Document163`.
- Active subscription filter: `start_date <= cutoff_date` and
  `end_date >= cutoff_date`; short durations are included.
- Active client role: preferred holder `_Document163._Fld9152RRef`, fallback
  payer `_Fld1447_RRRef`.
- Subscription end date: `dbo._InfoRg3060._Fld3064`.
- Sales/create date: union of `dbo._Document152` payments and
  `dbo._Document163` membership sales; `create_date = first_sale_date`.
- Booking: structured status `Бронь абонемента` from
  `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062`.
- Plastic cards: `dbo._Reference59`, all unmarked card numbers exported
  comma-separated; issue date/card ref are used only for deterministic ordering.

## Status

Plan section 12 is implemented as a reproducible staging build. Next step should
produce final validation reports and then generate the two XLSX files from
`fitbase_stg.mart_active_clients`.
