# Open Questions And Risks

Date: 2026-05-07

## Still open before extraction

1. Current SQL runtime is `Azure SQL Edge Developer 15.0.2000.1574 (ARM64)`,
   selected because the VPS is ARM64. `HEADERONLY`, `FILELISTONLY`,
   `VERIFYONLY`, full restore, and post-restore access checks are complete.
2. `openpyxl` is installed through the system package `python3-openpyxl` and is
   used by `scripts/build_fitbase_xlsx.py`.
3. `FitnessRestored` is restored, `ONLINE`, and accessible. Step 9 smoke-check
   found `2503` user tables and `19421` user columns. Full `DBCC CHECKDB` was
   not run by design.
4. Primary schema inventory and step 11 candidate mapping are complete:
   `config/table_mapping.yml`, `output/table_mapping_report.md`,
   `output/step11_candidate_tables.csv`, and
   `docs/step_11_candidate_tables.md`. For physical table discovery, the only
   email source is now identified in `docs/step_13_email_discovery.md`, with
   low coverage.
5. Active-client reconciliation is functionally resolved in
   `docs/step_12_active_segment_reconciliation.md`: use
   `dbo._InfoRg3060 + dbo._Document163` with preferred holder
   `_Document163._Fld9152RRef`, fallback `_Fld1447_RRRef`. The saved segment
   `Активные членства (клиенты)` is a static/report segment dated
   `2025-04-17`, not the authoritative current active-client source. Current
   cutoff `2026-04-29` gives `10,796` active clients by the preferred-holder
   rule.
6. Plan section 12 staging is built in
   `docs/step_14_staging_sets.md`: SQL schema `fitbase_stg` contains staging
   tables and `mart_active_clients`; CSV exports are in
   `output/staging_2026-04-29/` and ignored by git because they are generated
   large data. The final active mart includes 1-day, 7-day, trial-day, and
   other short active products; 10 current mart clients are marked with
   `is_short_duration_active = 1`.
7. Plan sections 13-16 are implemented in
   `docs/step_15_final_business_rules_dedup_managers_xlsx.md`: final XLSX
   files and report CSVs are in `output/`, and `output/validation_report.md`
   currently has verdict `PASS`.
8. Data-quality risks are detailed in
   `docs/step_16_data_quality_risk_review.md`. Current practical blockers
   before production upload are: 11 clients without phone, 471 clients with
   multiple active subscriptions, and Fitbase acceptance of comma-separated
   card numbers for 7,570 clients with multiple active cards.
9. Final active-client XLSX was split into 9 mutually exclusive validation
   groups in `output/splits/`; details are in
   `docs/step_17_active_clients_problem_splits.md`.
10. Business should still confirm the role semantics:
   `_Document163._Fld9152RRef` appears to be the actual membership holder, while
   `_Fld1447_RRRef` appears to be payer/buyer. CSV checks strongly support the
   preferred-holder rule: SQL-vs-CSV active-client gaps are `+156`
   (`2022-12-31`), `+151` (`2023-12-31`), `-217` (`2024-12-31`), `+38`
   (`2025-08-31`), and `+21` (`2025-11-30`).
11. The strongest stage end-date candidate is `dbo._InfoRg3060._Fld3064`.
   The table/column is known; business must verify that this is the final rule
   before it drives funnel stages.
12. The strongest structured booking candidate is
   `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062`, status
   `Бронь абонемента`. The table is known; business must confirm it as the
   `Бронь` flag.
13. Email source is `dbo._InfoRg5255._Fld5257`, joined by
   `_Fld5256RRef -> dbo._Reference64._IDRRef`. Coverage is low: 30 clients
   total, 11 current active clients. If business expects many more emails, they
   are likely outside this restored 1C backup or in a non-canonical message
   stream.
14. Plastic cards are in `dbo._Reference59`; no expiration/valid-until column
   was found. Multiple active/unmarked cards are exported comma-separated in
   one cell.
15. Fitbase mini-test is still needed to confirm import acceptance, especially
   `create_date` Excel date formatting, comma-separated phones, and
   comma-separated plastic-card numbers.
16. If customer has known example clients or phone numbers, they will be useful
   later to verify that table mapping is correct.

## Confirmed business clarifications

- `Дата создания *` / `create_date` means the first date when the client
  appeared in the database through any sale, including membership, 7-day,
  1-day, trial-day, and similar products/services. It is not the CSV
  visit/activity date, and client card creation date must not silently replace
  a missing first sale date.
