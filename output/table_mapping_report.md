# Table Mapping Report

Date: 2026-05-07
Status: staging sets built; ready for validation reports and XLSX generation.

## Summary

The strongest mapping is:

| Business entity | Primary source | Confidence |
|---|---|---|
| Клиент | `dbo._Reference64` | high |
| Телефон | `dbo._Reference64._Fld3832` | high |
| Карточка клиента создана | `dbo._Reference64._Fld3822` | high |
| Абонемент / членство | `dbo._InfoRg3060` joined to `dbo._Document163` | medium-high |
| Дата для этапов | candidate `dbo._InfoRg3060._Fld3064` | medium |
| Бронь | candidate `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062` | medium-high |
| Пластиковая карта | `dbo._Reference59` | high |
| Сегмент активных | `dbo._InfoRg2878 + dbo._Reference91` | medium |
| Первая продажа / платеж | candidate `dbo._Document152`, plus `dbo._Document163` | medium |
| `Дата создания *` | first client sale in database, not CSV visit date | business-confirmed |

Staging result for backup cutoff `2026-04-29`:

- SQL schema: `fitbase_stg`
- CSV output: `output/staging_2026-04-29/`
- `mart_active_clients`: `10,796`
- full details: `docs/step_14_staging_sets.md`

Final Fitbase export result:

- main XLSX: `output/fitbase_active_clients_import_zayavki_20260429.xlsx`
- plastic cards XLSX: `output/fitbase_active_clients_plastic_cards_20260429.xlsx`
- rows before/after exact FIO+phone deduplication: `10,796 / 10,796`
- validation: `output/validation_report.md` = `PASS`
- full details: `docs/step_15_final_business_rules_dedup_managers_xlsx.md`

## Key Findings

### Clients

`dbo._Reference64` is the client master table:

- `_IDRRef` is the client ref.
- `_Code` is the internal client code.
- `_Description` is FIO.
- `_Fld3822` behaves as client card creation date.
- `_Fld3832` stores phone values, including multiple comma-separated phones.
- `_Fld3818` is client note/comment text.
- `_Fld3810` looks like birth date and must not be used as create date.

Evidence: `logs/step11_reference64_text_profile.txt`, `logs/step11_reference64_date_profile.txt`.

### Contacts

Primary phone source is confirmed as `dbo._Reference64._Fld3832`.

Email source after deep search:

- `dbo._Reference64` has no email-like values in profiled text columns.
- `dbo._InfoRg5255._Fld5257` is the structured client-linked email candidate.
- Join: `dbo._InfoRg5255._Fld5256RRef -> dbo._Reference64._IDRRef`.
- Coverage is low: 30 clients total have structured email, including 11 current
  active clients for cutoff `2026-04-29`.
- `dbo._InfoRg5867._Fld5869` is not email: all `@` values are domain `c.us`,
  which looks like WhatsApp/JID contact IDs.
- `dbo._InfoRg5226._Fld5231`, `dbo._InfoRg5211._Fld5222`, and
  `dbo._InfoRg5843` contain embedded email text in notes/messages, but they are
  not canonical email fields.

Recommendation for first extraction: fill email from `dbo._InfoRg5255._Fld5257`
when present; leave it empty otherwise and report low coverage in validation.

### Create Date

Business-confirmed rule for Fitbase field `Дата создания *` / `create_date`:
use the first date when the client appeared in the database through any sale,
including membership, 7-day, 1-day, trial-day, and similar products/services.
This is not the CSV visit/activity date. Client card creation date
`dbo._Reference64._Fld3822` is useful for audit, but it must not silently
replace a missing first sale date; clients without a found sale go to
`missing_sales_report.csv` and/or `missing_required_fields.csv`.

### Memberships

`dbo._InfoRg3060` is the primary membership register candidate:

- It has `116,523` rows.
- `dbo._InfoRg3060._Fld3061RRef` joins to `dbo._Document163._IDRRef` for all `116,523` rows.
- `dbo._Document163._Fld9152RRef` and `_Fld1447_RTRef/_Fld1447_RRRef` both join the membership document to `dbo._Reference64`.
- `dbo._Document163._Fld1446RRef` joins product/service to `dbo._Reference72`.

Important date candidates:

- `dbo._Document163._Date_Time` and `dbo._InfoRg3060._Fld3062`: sale/document date candidates.
- `dbo._InfoRg3060._Fld3063`: start-date candidate.
- `dbo._InfoRg3060._Fld3064`: valid-until candidate for active/stage calculations.
- `dbo._InfoRg3060._Fld3065`: service duration or auxiliary days candidate; for duration buckets, the more comparable value is `_Fld3064 - _Fld3063 + 1`.

Using `_Document163._Fld1450` alone gives only `285` active clients by full cutoff day, so it is not sufficient for final active-client logic.

Client identity rule after step 12:

```text
Use _Document163._Fld9152RRef when it points to dbo._Reference64.
Otherwise fall back to _Document163._Fld1447_RRRef where _Fld1447_RTRef = 0x00000040.
```

This matched the manager CSV control export best: on snapshot `2025-08-31`,
`data/gym_sales.csv` has `8,885` active unique clients, while SQL with the
preferred-holder rule has `8,923`.

The same rule was validated across additional historical snapshots:

| Snapshot | CSV active clients | SQL active clients | SQL - CSV |
|---|---:|---:|---:|
| 2022-12-31 | 7,773 | 7,929 | 156 |
| 2023-12-31 | 8,551 | 8,702 | 151 |
| 2024-12-31 | 7,675 | 7,458 | -217 |
| 2025-08-31 | 8,885 | 8,923 | 38 |
| 2025-11-30 | 9,554 | 9,575 | 21 |

Evidence: `output/active_compare_2022_2025_snapshots_summary.csv`.

Using the same preferred-holder rule for current cutoff `2026-04-29` gives
`10,796` active clients.

### Active Segment Resolution

Step 12 showed that `dbo._InfoRg2878` stores static/report segments, not a
current active-client state. The segment `Активные членства (клиенты)` is dated
`2025-04-17` in `_Reference91._Fld4329` and duplicates
`Сегмент из отчета: Активные членства 16.04.2025`.

Initial conflict:

| Source | Clients |
|---|---:|
| Segment `Активные членства (клиенты)` in `dbo._InfoRg2878` | 8,099 |
| Initial diagnostic register filter from step 12, before final holder-role and short-product rules | 11,012 |
| Intersection | 4,986 |
| In segment but not in register filter | 3,113 |
| In register filter but not in segment | 6,026 |

Resolved interpretation: use `dbo._InfoRg3060 + dbo._Document163` for active
membership state. Use `dbo._InfoRg2878` only as validation/business labels.
The final staging extraction includes short active products as well; duration is
kept for audit and does not exclude 1-day, 7-day, trial-day, or similar active
clients.
Full evidence is in `docs/step_12_active_segment_reconciliation.md`.

### Booking

The strongest structured booking candidate is:

```text
dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062._IDRRef
dbo._Reference5062._Description = "Бронь абонемента"
```

Counts from `logs/step11_membership_register_probe.txt`:

- `411` clients have status `Бронь абонемента`.
- `120` clients are active by `_InfoRg3060._Fld3064`.
- In the active-segment preview, `59` clients land in the `Бронь` stage.

Text fallback sources:

- `dbo._Reference64._Fld3818`: 12 rows with `брон`.
- `dbo._InfoRg5226._Fld5231`: 551 rows / 544 clients with `брон`.

`dbo._Document9230` is weak/rejected for booking: it is client-linked, but only 2 rows contain `брон`, and samples look more like one-off visits/services.

### Plastic Cards

`dbo._Reference59` is the plastic card table:

- `_Fld3750_RTRef = 0x00000040` and `_Fld3750_RRRef` joins to `dbo._Reference64._IDRRef`.
- `_Fld3753` and `_Fld3756` are card number candidates; samples match.
- `_Fld3751` is card issue/created date candidate.
- `_Marked = 0x00` is the active/not-deleted candidate.
- No expiration/valid-until date column was found in `_Reference59`; its only
  date-like business column is `_Fld3751`.

Flag distribution for client-linked cards:

- `100,822` rows unmarked.
- `4,702` rows marked.
- `6` rows with `_Fld3752 = 0x01`.
- Other checked flags `_Fld3757`, `_Fld8852`, `_Fld9523`, `_Fld9524` are all
  zero for client-linked cards; numeric fields `_Fld3755`, `_Fld8109`, `_Fld346`
  are also all zero.

Final export rule: write all unmarked card numbers for the client, comma-separated when multiple cards exist, and write multiple-card cases to `multiple_cards_report.csv`. `_Fld3751` and `card_ref` are used only for deterministic ordering inside the comma-separated list.

### Sales

`dbo._Document152` is the payment/sale document candidate:

- `_Fld1057_RTRef/_Fld1057_RRRef` links to clients.
- `_Fld1058RRef` also matches `dbo._Reference64`.
- `_Date_Time` is payment/document date candidate.
- `_Fld1072RRef` maps to payment operation (`dbo._Reference101`).
- `_Fld1074RRef` maps to payment method (`dbo._Reference125`).

`dbo._AccumRg3305` is a money/payment movement register and should be used for validation, not as the primary active-membership source.

## Reproducibility

Step 11 scripts and logs:

- `sql/04_find_client_rtrefs.sql` -> `logs/step11_client_rtref_hits.txt`
- `sql/04_candidate_table_samples.sql` -> `logs/step11_candidate_table_samples.txt`
- `sql/04_reference_column_match_probe.sql` -> `logs/step11_reference_column_matches.txt`
- `sql/04_reference64_text_profile.sql` -> `logs/step11_reference64_text_profile.txt`
- `sql/04_client_segments_probe.sql` -> `logs/step11_client_segments_probe.txt`
- `sql/04_document163_active_probe.sql` -> `logs/step11_document163_active_probe.txt`
- `sql/04_membership_register_probe.sql` -> `logs/step11_membership_register_probe.txt`
- `sql/04_active_segment_vs_membership_probe.sql` -> `logs/step11_active_segment_vs_membership_probe.txt`
- `sql/04_booking_candidate_probe.sql` -> `logs/step11_booking_candidate_probe.txt`
- `sql/04_email_targeted_small_probe.sql` -> `logs/step11_email_targeted_small_probe.txt`
- `sql/04_email_client_link_probe.sql` -> `logs/step11_email_client_link_probe.txt`
- `sql/04_email_domain_probe.sql` -> `logs/step11_email_domain_probe.txt`
- `sql/04_email_final_candidate_probe.sql` -> `logs/step11_email_final_candidate_probe.txt`

Config draft: `config/table_mapping.yml`.
Candidate CSV: `output/step11_candidate_tables.csv`.
