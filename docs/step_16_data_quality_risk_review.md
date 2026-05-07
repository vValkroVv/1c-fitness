# Step 16: Data Quality Risk Review

Date: 2026-05-07

This note explains the warnings from `output/validation_report.md` and the
additional risk reports generated after final XLSX creation.

Command:

```bash
scripts/08_analyze_data_quality_risks.py
```

## Create Date Fix

The first final run showed 9 clients without `create_date`. Investigation showed
this was not a business-data absence. `stg_sales` filtered sales documents by
`4026-04-29 00:00:00`, while the backup finished at `2026-04-29 23:57:02`.

Fix applied in `sql/06_build_staging_tables.sql`:

```text
use cutoff_sql_end_at = 4026-04-29 23:57:02 for sales document filters
```

After rebuild:

| Metric | Before | After |
|---|---:|---:|
| `stg_sales` rows | 499,316 | 499,614 |
| missing `create_date` clients | 9 | 0 |
| `mart_active_clients` rows | 10,796 | 10,796 |

## Missing Required Fields

After the cutoff fix, missing required fields are only phones:

| Missing field | Clients |
|---|---:|
| `phone` | 11 |
| `client_fio` | 0 |
| `create_date` | 0 |

Report:

```text
output/missing_required_fields.csv
```

Cross-check against manager CSV `data/gym_sales.csv` found exact FIO phone
candidates for 3 of 11:

| client_id | FIO | gym_sales phone |
|---|---|---|
| `000008651` | Мелентьева Янина Андреевна | `+7 (981) 407-92-67` |
| `000034854` | Поташева Татьяна Николаевна | `+7 (921) 463-38-71` |
| `000064123` | Афанасьев Яков Евгеньевич | `+7 (911) 403-22-33` |

The remaining 8 were not found by exact normalized FIO in `gym_sales.csv`.
These values were not auto-filled into XLSX because the main reproducible
pipeline is still based on the `.bak`; the CSV candidates are written to:

```text
output/missing_phone_recovery_candidates.csv
```

## Multiple Active Subscriptions

There are 471 clients with more than one active subscription on `2026-04-29`.
The detailed report contains all 995 active subscription rows:

```text
output/multiple_active_subscriptions_detail.csv
output/multiple_active_subscriptions_client_summary.csv
```

Distribution:

| Active subscriptions per client | Clients |
|---|---:|
| 2 | 434 |
| 3 | 28 |
| 4 | 6 |
| 5 | 1 |
| 7 | 2 |

Duration profile for those 995 active rows:

| Duration bin | Active subscription rows |
|---|---:|
| 181-365 | 476 |
| 451+ | 402 |
| 366-450 | 102 |
| 30-60 | 8 |
| 61-180 | 7 |
| `<30` | 0 |

Conclusion: these are not the short 1/7/10-day products. They are mostly long
12-15 month products, often with gift/freezing variants or overlapping renewal
documents.

Current export rule chooses the active subscription with the latest `end_date`.
For 70 of 471 clients, the funnel step would change if the earliest active
`end_date` were used instead:

| Earliest-end step | Latest-end step | Clients |
|---|---:|---:|
| `60-31 день до окончания` | `Действующие клиенты` | 31 |
| `30-8 дней до окончания` | `Действующие клиенты` | 24 |
| `7-0 день до окончания` | `Действующие клиенты` | 13 |
| `30-8 дней до окончания` | `60-31 день до окончания` | 1 |
| `7-0 день до окончания` | `60-31 день до окончания` | 1 |

This is the main business risk: not the active-client segment count, but the
stage assignment for those 70 clients. Examples:

| client_id | FIO | earliest end/step | selected latest end/step |
|---|---|---|---|
| `000000439` | Алова Елена Викторовна | `2026-05-28` / `30-8 день` | `2027-04-06` / `Действующие клиенты` |
| `000001253` | Баранова Марина Андреевна | `2026-06-28` / `60-31 день` | `2026-10-22` / `Действующие клиенты` |
| `000002291` | Бурлаков Андрей Викторович | `2026-04-30` / `7-0 день` | `2026-12-29` / `Действующие клиенты` |

Decision needed before production import: should Fitbase stage use latest active
end date, earliest active end date, or a manually curated current membership
when overlaps exist?

## Multiple Plastic Cards

There are 7,570 clients with multiple unmarked plastic cards. Details:

```text
output/multiple_cards_detail.csv
output/multiple_cards_report.csv
```

`dbo._Reference59` fields checked:

- `_Fld3750_RRRef` links card to client.
- `_Fld3753` / `_Fld3756` hold card number values.
- `_Fld3751` is the only date-like card field found; it behaves like issue or
  creation date.
- `_Marked` is the only useful active/not-deleted candidate.
- No card expiration/valid-until date column was found.
- `_Fld3757`, `_Fld8852`, `_Fld9523`, `_Fld9524` are all zero for client-linked
  cards.
- `_Fld3755`, `_Fld8109`, `_Fld346` are all zero.
- `_Fld8108` is empty.

So current rule is: export all unmarked card numbers for the client. If a
client has multiple active cards, write them in one cell comma-separated;
`_Fld3751` and card ref are used only for deterministic ordering inside that
list.

Additional risks found:

| Risk | Count | Report |
|---|---:|---|
| included card has future/anomalous issue date after cutoff | 3 | `output/plastic_cards_anomalies.csv` |
| multiple cards share the same max issue date; affects ordering only | 837 | `output/plastic_cards_ordering_ties.csv` |

The 3 future/anomalous included cards are:

| client_id | FIO | included card | issue_date |
|---|---|---:|---|
| `000024090` | Шумакова Наталия Александровна | `1150004022016` | `2402-04-11` |
| `000024414` | Подопригора Никита Игоревич | `1150004054000` | `2405-05-11` |
| `000029269` | Тимофеева Наталья Сергеевна | `1046000030318` | `2030-04-10` |

These should be manually checked before production import, or the export rule
should ignore card issue dates greater than the backup cutoff date.

## Current Validation State

`output/validation_report.md` remains:

```text
PASS
```

But the recommended blockers before production upload are:

1. Decide latest vs earliest active end-date for the 471 clients with multiple
   active subscriptions; especially the 70 clients whose stage changes.
2. Decide whether to fill 3 missing phones from `data/gym_sales.csv`.
3. Decide whether anomalous future card issue dates should affect ordering and
   how to handle 837 max-date ordering ties.
