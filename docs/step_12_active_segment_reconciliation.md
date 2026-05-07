# Step 12: Active Segment Reconciliation

Date: 2026-05-07

## Goal

Resolve the conflict between:

- static client segment `Активные членства (клиенты)` from `dbo._InfoRg2878`;
- calculated active memberships from `dbo._InfoRg3060 + dbo._Document163`;
- external manager export `data/gym_sales.csv`.

This step is required before generating final XLSX files, because using the wrong
active-client segment changes the export population.

## Scripts And Logs

| Artifact | Purpose |
|---|---|
| `sql/05_active_segment_reconciliation_probe.sql` | role and overlap probe for current cutoff `2026-04-29` |
| `sql/05_segment_metadata_probe.sql` | segment metadata and overlap with other client segments |
| `sql/05_segment_mismatch_deep_dive.sql` | corrected reasons why target segment and register differ |
| `sql/05_active_snapshot_role_mode_counts.sql` | August 2025 role-mode count test |
| `sql/05_export_active_clients_snapshot.sql` | SQL export for a chosen active snapshot date |
| `scripts/05_compare_active_clients_with_gym_sales.py` | reproducible CSV-vs-SQL active-client comparison |
| `logs/step12_active_segment_reconciliation_probe.txt` | current cutoff role/overlap log |
| `logs/step12_segment_metadata_probe.txt` | segment metadata log |
| `logs/step12_segment_mismatch_deep_dive.txt` | corrected mismatch reasons |
| `logs/step12_active_snapshot_role_mode_counts.txt` | role-mode counts for `2025-08-31` |
| `logs/step12_gym_sales_compare_2025-08-31.txt` | CSV comparison run log |
| `logs/step12_gym_sales_compare_2022_2025_snapshots.txt` | multi-date CSV comparison run log |
| `logs/step12_gym_sales_compare_YYYY-MM-DD_sql_export.txt` | SQL export logs per snapshot date |
| `output/active_compare_2022_2025_snapshots_summary.csv` | combined multi-date summary |
| `output/active_compare_2025-08-31_summary.csv` | August summary metrics |
| `output/active_compare_2025-08-31_length_breakdown.csv` | August duration buckets |
| `output/active_compare_2025-08-31_overlap_by_length.csv` | phone overlap by duration bucket |
| `output/active_compare_2025-08-31_top_products.csv` | top products by source and duration bucket |
| `output/active_compare_YYYY-MM-DD_*.csv` | same summary, duration, overlap, and top-product files for each validated snapshot |

## Key Findings

### 1. The 8,099 Segment Is Static, Not Current

`dbo._InfoRg2878` has only 7 columns and no period/current flag. It stores
membership of clients in named segments.

The segment `Активные членства (клиенты)`:

- has `8,099` clients;
- has `_Reference91._Fld4329 = 4025-04-17`, i.e. real date `2025-04-17`;
- is an exact duplicate by members of `Сегмент из отчета: Активные членства 16.04.2025`;
- overlaps the calculated current active list by only `5,032` clients.

Conclusion: this segment is a saved/report segment around April 2025, not an
authoritative active-client source for the restored database as of
`2026-04-29`.

### 2. Low Overlap Is Mostly Explained By Time Drift

For current cutoff `2026-04-29`, using both known client roles as a union gives:

| Metric | Clients |
|---|---:|
| target segment clients | 8,099 |
| register active candidates | 11,344 |
| intersection | 5,032 |
| in target segment but not active by register | 3,067 |
| active by register but not in target segment | 6,312 |

Corrected reasons for the `3,067` target-segment-only clients:

| Reason | Clients |
|---|---:|
| membership product exists but not active by `_InfoRg3060._Fld3064` | 2,999 |
| no membership-like product by keywords | 50 |
| active membership but duration under 30 days | 7 |
| no `Document163` by known client roles | 6 |
| only unposted/marked documents | 5 |

For register-only clients, the main reason is that the saved segment predates
many later sales:

| Document timing | Clients |
|---|---:|
| documents after segment creation in 2025 | 4,236 |
| documents in 2026 | 1,995 |
| documents before target segment creation | 81 |

### 3. Client Role Must Be Preferred Holder, Not Union

`dbo._Document163` has two client-like fields:

- `_Fld1447_RTRef/_Fld1447_RRRef`: payer/buyer-like client field;
- `_Fld9152RRef`: direct client/member/holder-like field.

They differ in `1,797` documents. Using both as a union overcounts clients.

Role-mode tests:

| Snapshot | Role mode | SQL active clients |
|---|---|---:|
| 2025-08-31 | payer `_Fld1447` only | 9,143 |
| 2025-08-31 | member `_Fld9152RRef` only | 8,633 |
| 2025-08-31 | preferred `_Fld9152RRef`, fallback `_Fld1447` | 8,923 |
| 2025-08-31 | union of both roles | 9,515 |
| 2026-04-29 | payer `_Fld1447` only | 11,157 |
| 2026-04-29 | member `_Fld9152RRef` only | 10,548 |
| 2026-04-29 | preferred `_Fld9152RRef`, fallback `_Fld1447` | 10,796 |
| 2026-04-29 | union of both roles | 11,485 |

The manager CSV has `8,885` unique active clients for the same date. Therefore
the best client identity rule is:

```text
Use _Document163._Fld9152RRef if it points to dbo._Reference64.
Otherwise fall back to _Document163._Fld1447_RRRef where _Fld1447_RTRef = 0x00000040.
```

For audit and phone/contact QA, keep both roles available in intermediate
outputs, but do not use their union as the final client segment.

### 4. CSV Cross-Check For August 2025

Snapshot date used: `2025-08-31`.

CSV logic:

- source: `data/gym_sales.csv`;
- active if `sale_datetime <= 2025-08-31` and `valid_to >= 2025-08-31`;
- membership-like product names only;
- unique client key: normalized phone + normalized client name.

SQL logic:

- source: `dbo._InfoRg3060 + dbo._Document163`;
- client identity: preferred `_Fld9152RRef`, fallback `_Fld1447`;
- active if start date candidate `<= 4025-08-31` and `_Fld3064 >= 4025-08-31`;
- product name matches membership keywords;
- posted and not marked documents only.

Summary:

| Metric | Value |
|---|---:|
| CSV active rows | 9,752 |
| CSV active unique clients | 8,885 |
| SQL active unique clients | 8,923 |
| SQL minus CSV | 38 |
| CSV active clients with SQL phone match | 8,244 |
| SQL active clients with CSV phone match | 8,236 |
| exact phone+name matches | 8,177 |
| SQL active clients also in `Активные членства (клиенты)` | 6,353 |
| SQL active clients also in `ЧК и КК` | 7,043 |

This validates that the register-based preferred-holder rule is close to the
manager export, while the saved `Активные членства (клиенты)` segment is too
small even for an August 2025 historical check.

Duration breakdown:

| Length bucket | CSV clients | SQL clients | SQL - CSV |
|---|---:|---:|---:|
| up to 2 weeks | 21 | 23 | 2 |
| 1 month | 88 | 87 | -1 |
| 2 months | 9 | 9 | 0 |
| 3 months | 25 | 29 | 4 |
| 4-5 months | 15 | 21 | 6 |
| 6 months | 17 | 55 | 38 |
| 9 months | 100 | 129 | 29 |
| 12 months | 3,611 | 3,926 | 315 |
| 13-15 months | 3,133 | 3,083 | -50 |
| 16-18 months | 936 | 751 | -185 |
| 19-24 months | 574 | 690 | 116 |
| 24+ months | 356 | 120 | -236 |

The total count is very close. Remaining bucket differences are likely caused by
different duration semantics: CSV duration is derived from `sale_datetime` to
`valid_to`, while SQL uses register start candidate `_Fld3063` to `_Fld3064`.

### 5. Multi-Date CSV Cross-Check

Additional business-requested validation was run on four dates outside August,
covering 2022-2025. Dates chosen:

- `2022-12-31`
- `2023-12-31`
- `2024-12-31`
- `2025-11-30`

`2025-11-30` was chosen instead of the end of December because
`data/gym_sales.csv` has sales only up to `2025-12-23`, so November is a safer
complete-month control point. The August control date `2025-08-31` was rerun in
the same batch for comparability.

Combined result:

| Snapshot | CSV active clients | SQL active clients | SQL - CSV | Delta vs CSV | Exact phone+name matches |
|---|---:|---:|---:|---:|---:|
| 2022-12-31 | 7,773 | 7,929 | 156 | 2.0% | 7,538 |
| 2023-12-31 | 8,551 | 8,702 | 151 | 1.8% | 8,055 |
| 2024-12-31 | 7,675 | 7,458 | -217 | -2.8% | 6,773 |
| 2025-08-31 | 8,885 | 8,923 | 38 | 0.4% | 8,177 |
| 2025-11-30 | 9,554 | 9,575 | 21 | 0.2% | 8,877 |

Interpretation:

- total active-client counts match closely across all tested years;
- the largest absolute gap is `217` clients on `2024-12-31`, or `-2.8%` vs CSV;
- late-2025 checks are almost identical: `+38` clients in August and `+21` in
  November;
- per-date duration breakdowns were generated, but the bucket labels remain
  diagnostic only until final business length is derived from nominal product
  name instead of raw date span.

This multi-date validation strengthens the decision to use the register-based
preferred-holder rule as the active-client source.

## Decision For Final Extraction

Use `dbo._InfoRg3060 + dbo._Document163` as the authoritative membership source.

For active client identity:

1. Use `_Document163._Fld9152RRef` when it points to `dbo._Reference64`.
2. Fall back to `_Document163._Fld1447_RRRef` when `_Fld1447_RTRef = 0x00000040`.
3. Do not union payer and holder for the final client list.

For active status on a snapshot date:

1. Document must be posted and not marked.
2. Product must match membership keywords.
3. Start date candidate must be `<= snapshot_date`.
4. Valid-until candidate `_InfoRg3060._Fld3064` must be `>= snapshot_date`.

Use `dbo._InfoRg2878` segments only as validation/business labels, not as the
primary active-client source.

## Remaining Business Check

Confirm with the business owner that `_Fld9152RRef` means the actual membership
holder/client. The August CSV test strongly supports this, but final XLSX logic
should still keep payer and holder fields in an intermediate audit output.
