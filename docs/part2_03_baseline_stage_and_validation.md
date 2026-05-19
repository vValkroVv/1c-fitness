# Part 2 Baseline Stage And Validation

Date: 2026-05-20
Cutoff: `2026-04-29`

## Stage

Baseline stage output:

- `output/part2_20260429/staging/`
- rows in `final_funnel_clients.csv`: 72,586

Funnel distribution:

- `Действующие клиенты`: 10,813
- `Новые заявки`: 34,006
- `Реактивация`: 27,767

Stage distribution:

- `Новые заявки / Неразобранные`: 34,006
- `Реактивация / более 90 дней`: 26,427
- `Действующие клиенты / Действующие клиенты`: 9,658
- `Действующие клиенты / 60-31 день до окончания`: 559
- `Действующие клиенты / 30-8 дней до окончания`: 446
- `Действующие клиенты / 7-0 день до окончания`: 150
- `Реактивация / 1-6 дней`: 84
- `Реактивация / 7-29 дней`: 436
- `Реактивация / 30-59 дней`: 449
- `Реактивация / 60-89 дней`: 371

Club distribution after confirmed organization mapping:

- `Коммунальная, 20`: 45,945
- `Лососинское шоссе, 26`: 9,250
- `Промышленная, 10`: 8,556
- `Карельский (закрыт)`: 6,216
- `Ровио, 3`: 2,612
- `Клуб не определен (fallback)`: 7

## Validation

Validation report:

- `output/part2_20260429/reports/validation_report.md`
- verdict: `PASS`

Manual checks:

- `Бронь`: 0 rows
- `A1/A2/A3`: 0 rows
- client overlap between funnels: 0 rows
- comma-separated cards in card XLSX: 0 rows
- missing club: 0 rows
- missing manager: 0 rows

Warnings are data-quality/report-only items: missing phones, missing cards,
multiple subscription candidates, and product classification review rows.

`Карельский (закрыт)` is exported with placeholder manager
`УТОЧНИТЬ: Карельский`, and `Клуб не определен (fallback)` is exported with
placeholder manager `УТОЧНИТЬ: клуб не определен`. These placeholders are
configured in `config/managers_by_club.yml` so they can be replaced locally
without restoring the SQL backup again.
