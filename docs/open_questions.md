# Open Questions And Risks

Date: 2026-05-07

## Still open before extraction

1. Current SQL runtime is `Azure SQL Edge Developer 15.0.2000.1574 (ARM64)`,
   selected because the VPS is ARM64. `HEADERONLY`, `FILELISTONLY`,
   `VERIFYONLY`, full restore, and post-restore access checks are complete.
2. `openpyxl` is not installed. It will likely be needed for scripts that build
   final XLSX files from the templates.
3. `FitnessRestored` is restored, `ONLINE`, and accessible. Step 9 smoke-check
   found `2503` user tables and `19421` user columns. Full `DBCC CHECKDB` was
   not run by design.
4. Primary schema inventory and step 11 candidate mapping are complete:
   `config/table_mapping.yml`, `output/table_mapping_report.md`,
   `output/step11_candidate_tables.csv`, and
   `docs/step_11_candidate_tables.md`.
5. Active-client reconciliation is functionally resolved in
   `docs/step_12_active_segment_reconciliation.md`: use
   `dbo._InfoRg3060 + dbo._Document163` with preferred holder
   `_Document163._Fld9152RRef`, fallback `_Fld1447_RRRef`. The saved segment
   `Активные членства (клиенты)` is a static/report segment dated
   `2025-04-17`, not the authoritative current active-client source. Current
   cutoff `2026-04-29` gives `10,796` active clients by the preferred-holder
   rule.
6. Business should still confirm the role semantics:
   `_Document163._Fld9152RRef` appears to be the actual membership holder, while
   `_Fld1447_RRRef` appears to be payer/buyer. CSV checks strongly support the
   preferred-holder rule: SQL-vs-CSV active-client gaps are `+156`
   (`2022-12-31`), `+151` (`2023-12-31`), `-217` (`2024-12-31`), `+38`
   (`2025-08-31`), and `+21` (`2025-11-30`).
7. The strongest stage end-date candidate is `dbo._InfoRg3060._Fld3064`.
   It must be business-verified before it drives funnel stages.
8. The strongest structured booking candidate is
   `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062`, status
   `Бронь абонемента`. It must be confirmed as the business `Бронь` flag.
9. Email has no confirmed canonical client source. `dbo._InfoRg5255._Fld5257`
   has only `31` email-like rows and needs deterministic phone/client matching
   if we use it.
10. Plastic cards are in `dbo._Reference59`, but active-card selection among
   multiple unmarked cards still needs the final rule.
11. If customer has known example clients or phone numbers, they will be useful
   later to verify that table mapping is correct.

## Confirmed business clarifications

- `Дата создания *` / `create_date` means the first date when the client
  appeared in the database through any sale, including membership, 7-day,
  1-day, trial-day, and similar products/services. It is not the CSV
  visit/activity date, and client card creation date must not silently replace
  a missing first sale date.
