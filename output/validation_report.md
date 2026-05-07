# Fitbase Final Export Validation

Run date: 2026-05-07T19:26:55
cutoff_date: `2026-04-29`
date_stamp: `20260429`
backup: `data/Fitnes.bak` (12,770,610,688 bytes)
DatabaseName: `FitnessRestored`
Restored DB user tables: `2503`

## Output Files

- Main XLSX: `output/fitbase_active_clients_import_zayavki_20260429.xlsx`
- Plastic cards XLSX: `output/fitbase_active_clients_plastic_cards_20260429.xlsx`
- Validation/report files are in `output/`.

## Counts

- active-client candidates before deduplication: `10796`
- clients after exact FIO+phone deduplication: `10796`
- rows in main XLSX: `10796`
- rows in plastic cards XLSX: `10796`
- clients without phone: `11`
- clients without FIO: `0`
- clients without first sale: `0`
- clients without create_date: `0`
- clients without plastic card: `243`
- clients with multiple active subscriptions: `471`
- clients with multiple plastic cards: `7570`
- clients with booking but without active subscription: `0`
- exact duplicate groups auto-merged: `0`
- same-phone/different-FIO groups reported: `53`
- same-FIO/different-phone groups reported: `38`

## Funnel Step Distribution

- `Действующие клиенты`: `9422`
- `60-31 день до окончания`: `575`
- `30-8 дней до окончания`: `504`
- `7-0 день до окончания`: `178`
- `Бронь`: `117`

## Manager Distribution

- `A3`: `3632`
- `A2`: `3617`
- `A1`: `3547`

## Remaining Technical Questions

- Fitbase date-format acceptance still needs a mini-test; current XLSX writes `create_date` as an Excel date with `yyyy-mm-dd` format.
- Multiple active subscriptions are reported and not silently resolved by business logic.
- Multiple plastic cards are reported; the export writes all active/unmarked card numbers comma-separated.

## Validation

Errors: none.

Data-quality warnings:
- missing required field rows exported and reported: 11
- clients without plastic card exported and reported: 243
- clients with multiple active subscriptions reported: 471
- clients with multiple plastic cards reported: 7570
- duplicate/potential duplicate signals reported: 91

Verdict: `PASS`
