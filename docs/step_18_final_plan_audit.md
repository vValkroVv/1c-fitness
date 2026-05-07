# Step 18: Final Plan Audit

Date: 2026-05-07

Goal: verify that `task-desc/fitness_updated_restore_to_fitbase_plan.md` is
completed technically and that all known ambiguous/problem cases are reported.

## Commands Re-run

```bash
scripts/build_fitbase_xlsx.py
scripts/08_analyze_data_quality_risks.py
scripts/09_build_validation_split_xlsx.py
scripts/10_build_mini_fitbase_test_package.py
scripts/validate_outputs.py
```

`scripts/validate_outputs.py` result:

```text
verdict=PASS
errors=0
warnings=0
report=output/final_audit_report.md
```

## Environment Check

SQL container:

```text
mssql-fitness: running
FitnessRestored: ONLINE
```

Current DB has `2511` user tables because the restored database now also
contains staging/audit tables. The original schema inventory from step 10 was
captured before staging and has `2503` restored 1C user tables.

## Final Files

Main package:

```text
output/fitbase_active_clients_import_zayavki_20260429.xlsx
output/fitbase_active_clients_plastic_cards_20260429.xlsx
```

Mini-test package for Fitbase format check:

```text
output/mini_fitbase_active_clients_import_zayavki_20260429.xlsx
output/mini_fitbase_active_clients_plastic_cards_20260429.xlsx
output/mini_fitbase_active_clients_summary_20260429.csv
```

Split packages:

```text
output/splits/
```

Each split group contains both XLSX files: main import and plastic cards.

## Plan Checklist

| Plan requirement | Status | Evidence |
|---|---|---|
| Backup restored | done | `docs/step_08_restore_database.md` |
| DB online/access checked | done | `docs/step_09_post_restore_access_check.md` |
| Schema inventory created | done | `output/schema_inventory.csv`, `output/schema_tables.csv` |
| Candidate tables found | done | `docs/step_11_candidate_tables.md`, `output/table_mapping_report.md`, `config/table_mapping.yml` |
| Active segment reconciled with `gym_sales.csv` | done | `docs/step_12_active_segment_reconciliation.md`, `output/active_compare_2022_2025_snapshots_summary.csv` |
| Staging sets built | done | `output/staging_2026-04-29/*.csv`, `docs/step_14_staging_sets.md` |
| Short active products included | done | `include_short_active_products: true`; final rows include all active products |
| `create_date` = first sale | done | `missing_sales_report.csv` has `0` rows |
| Business rules/stages applied | done | `output/stage_distribution.csv`, `output/validation_report.md` |
| Managers assigned deterministically | done | `output/manager_distribution.csv` |
| Main XLSX generated from template | done | `10,796` data rows |
| Plastic-card XLSX generated from template | done | `10,796` data rows |
| Two XLSX files generated per split group | done | `output/splits/split_summary.csv` |
| Final validation report PASS | done | `output/validation_report.md`, `output/final_audit_report.md` |
| Fitbase mini-test files prepared | done | `72` mini-test clients |
| Actual Fitbase import test | external | must be run in Fitbase UI/API |

## Table Mapping Summary

| Entity | Final source |
|---|---|
| Clients | `dbo._Reference64` |
| Phones | `dbo._Reference64._Fld3832` |
| Email | `dbo._InfoRg5255._Fld5257`, joined through `_Fld5256RRef -> dbo._Reference64._IDRRef`; low coverage |
| Subscriptions | `dbo._InfoRg3060 + dbo._Document163` |
| First sale/create date | `dbo._Document152` payments plus membership sales from `dbo._Document163` |
| Booking | `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062` |
| Plastic cards | `dbo._Reference59` |

## Final Counts

| Metric | Count |
|---|---:|
| Final active clients | 10,796 |
| Main XLSX rows | 10,796 |
| Plastic-card XLSX rows | 10,796 |
| Mini-test rows | 72 |
| Split groups | 9 |
| Split rows total | 10,796 |

Stage distribution:

| Stage | Clients |
|---|---:|
| Действующие клиенты | 9,422 |
| 60-31 день до окончания | 575 |
| 30-8 дней до окончания | 504 |
| 7-0 день до окончания | 178 |
| Бронь | 117 |

Manager distribution:

| Manager | Clients |
|---|---:|
| A3 | 3,632 |
| A2 | 3,617 |
| A1 | 3,547 |

## Ambiguous And Problem Cases

All known disputed cases are detected and reported:

| Case | Count | Handling |
|---|---:|---|
| Missing required fields | 11 | all are missing `phone`; exported and listed in `output/missing_required_fields.csv` |
| Missing first sale/create date | 0 | no blocker after using full backup-day sales cutoff |
| Missing plastic card | 243 | exported with empty card cell and listed in `output/missing_cards_report.csv` |
| Multiple active subscriptions | 471 | exported, not silent: listed in `output/multiple_active_subscriptions_report.csv`; detailed rows in `output/multiple_active_subscriptions_detail.csv` |
| Stage would change if earliest active end date were used | 70 | listed in `output/multiple_active_subscriptions_client_summary.csv` |
| Multiple plastic cards | 7,570 | all active/unmarked card numbers are exported comma-separated and cases are listed in `output/multiple_cards_report.csv` |
| Duplicate/potential duplicate signals | 91 | listed in `output/duplicates_report.csv`; exact auto-merge groups in final output: `0` |
| Same phone, different FIO | 53 | report only, not auto-merged |
| Same FIO, different phones | 38 | report only, not auto-merged |
| Booking without active subscription | 0 | report exists and is empty |
| Future/anomalous plastic card issue date | 3 | listed in `output/plastic_cards_anomalies.csv`; affects review/order only, not inclusion |
| Plastic-card ordering ties | 837 | listed in `output/plastic_cards_ordering_ties.csv`; affects ordering only |
| Missing phone recoverable from `gym_sales.csv` by FIO | 3 of 11 | listed in `output/missing_phone_recovery_candidates.csv`; not auto-filled from CSV |

## Active Segment Cross-check

The historical check against `data/gym_sales.csv` was performed for five dates:

```text
2022-12-31
2023-12-31
2024-12-31
2025-08-31
2025-11-30
```

The important August 2025 check is close:

```text
CSV active unique clients: 8,885
SQL active unique clients: 8,923
Difference: +38
```

The year-end and November snapshots are documented in
`output/active_compare_2022_2025_snapshots_summary.csv`.

## Final Assessment

Technical pipeline status: `PASS`.

The repository now has reproducible scripts from staging export to final XLSX,
reports, split packages, mini-test package, and final audit. The only remaining
step outside this repository is the actual mini import into Fitbase to confirm:

1. Excel-date `create_date` format.
2. Comma-separated phones.
3. Comma-separated plastic-card numbers.
4. Manager/stage/funnel recognition.

If Fitbase rejects only a format, change only the output formatting after
confirmation. No unresolved table-mapping blocker remains.
