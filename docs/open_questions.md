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
5. The active-client source is not reconciled yet. Segment
   `Активные членства (клиенты)` has `8,099` clients; the `_InfoRg3060`
   membership filter has `11,012` clients; their intersection is only `4,986`.
   This must be decided before final extraction.
6. The strongest stage end-date candidate is `dbo._InfoRg3060._Fld3064`.
   It must be business-verified before it drives funnel stages.
7. The strongest structured booking candidate is
   `dbo._InfoRg3060._Fld5960RRef -> dbo._Reference5062`, status
   `Бронь абонемента`. It must be confirmed as the business `Бронь` flag.
8. Email has no confirmed canonical client source. `dbo._InfoRg5255._Fld5257`
   has only `31` email-like rows and needs deterministic phone/client matching
   if we use it.
9. Plastic cards are in `dbo._Reference59`, but active-card selection among
   multiple unmarked cards still needs the final rule.
10. If customer has known example clients or phone numbers, they will be useful
   later to verify that table mapping is correct.
