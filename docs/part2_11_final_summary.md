# Part 2 Final Summary

Date: 2026-05-20
Cutoff: `2026-04-29`

## Final XLSX

- `output/part2_20260429/fitbase_active_clients_import_zayavki_20260429__deystvuyushchie_klienty.xlsx`
- `output/part2_20260429/fitbase_active_clients_plastic_cards_20260429__deystvuyushchie_klienty.xlsx`
- `output/part2_20260429/fitbase_active_clients_import_zayavki_20260429__novye_zayavki.xlsx`
- `output/part2_20260429/fitbase_active_clients_plastic_cards_20260429__novye_zayavki.xlsx`
- `output/part2_20260429/fitbase_active_clients_import_zayavki_20260429__reaktivatsiya.xlsx`
- `output/part2_20260429/fitbase_active_clients_plastic_cards_20260429__reaktivatsiya.xlsx`

## Counts

Funnel distribution:

- `Действующие клиенты`: 10,813
- `Новые заявки`: 34,006
- `Реактивация`: 27,767

Data-quality/report counts:

- clients without phone: 6,042
- clients without selected card: 22,366
- clients without discovered club: 0
- clients without manager: 0
- active clients with multiple active subscription candidates: 685
- reactivation clients with multiple finished subscription candidates: 11,751
- clients with multiple card candidates: 24,108

Club distribution:

- `Коммунальная, 20`: 45,945
- `Лососинское шоссе, 26`: 9,250
- `Промышленная, 10`: 8,556
- `Карельский (закрыт)`: 6,216
- `Ровио, 3`: 2,612
- `Клуб не определен (fallback)`: 7

Fallback managers:

- `Карельский (закрыт)` -> `УТОЧНИТЬ: Карельский`: 6,216 rows
- `Клуб не определен (fallback)` -> `УТОЧНИТЬ: клуб не определен`: 7 rows

## Validation

Validation report:

- `output/part2_20260429/reports/validation_report.md`
- verdict: `PASS`

Manual checks:

- `Бронь`: 0
- `A1/A2/A3`: 0
- overlapping clients between funnels: 0
- comma-separated cards in card XLSX: 0

## Cutoff Shift

Report:

- `output/part2_20260429/reports/cutoff_shift_comparison_report.md`

Summary for `2026-04-24 -> 2026-04-27`:

- clients changed funnel: 77
- clients changed stage: 442
- clients exited active: 42
- clients entered reactivation: 42

## Mini-Test

Mini-test package:

- `output/part2_20260429/mini_test/mini_fitbase_part2_import_zayavki_20260429.xlsx`
- `output/part2_20260429/mini_test/mini_fitbase_part2_plastic_cards_20260429.xlsx`

Rows: 100 unique clients.

External Fitbase upload status: pending.

## Delivery

Final delivery folder:

- `output/final_delivery_part2_20260429/`

Archive:

- `output/final_delivery_part2_20260429.tar.gz`
