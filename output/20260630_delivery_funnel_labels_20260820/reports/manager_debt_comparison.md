# Manager debt vs 1C register

- verdict: **PASS**
- cutoff: `2026-06-30 23:27:03`
- manager sale rows: `274`
- mapped to new delivery: `274`
- sold mismatches: `0`
- debt mismatches: `0`
- paid mismatches: `63`
- full triple matches: `211`
- new delivery tuple mismatches vs DB: `0`
- manager paid excess absent from backup: `216149`
- active register positive debts: `279`
- active positive debts outside register source: `0`

The manager XLSX is used only for validation. Delivery values come from the restored database at the backup cutoff.

## Errors

- none
