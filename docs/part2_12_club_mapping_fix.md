# Part 2 Club Mapping Fix

Date: 2026-05-20

## Reason

The first Part 2 export left many rows without club/manager because only
already-normalized club names were mapped. In 1C the reliable source is the
organization reference in `dbo._Reference105`, where several real clubs are
stored under historical/legal names.

## Confirmed Mapping

Saved in `config/club_org_mapping.csv`:

- `Фитнес Империя (Гоголевский)` -> `Коммунальная, 20`
- `Фитнес Империя (Столица)` -> `Лососинское шоссе, 26`
- `Фитнес Империя (Промышленная)` -> `Промышленная, 10`
- `Фитнес Империя (Карельский)` -> `Карельский (закрыт)`
- `Фитнес Империя (Ровио,3)` -> `Ровио, 3`

`Карельский (закрыт)` is preserved as a separate club with placeholder manager
`УТОЧНИТЬ: Карельский`, so manager assignment can be changed later from config
without restoring the SQL database.

## SQL Sources

- membership documents: `dbo._Document163._Fld1443RRef -> dbo._Reference105`
- payment/sale documents: `dbo._Document152._Fld1051RRef -> dbo._Reference105`
- client-level fallback: `dbo._Reference64._Fld3831RRef -> dbo._Reference105`

## Result

Baseline cutoff `2026-04-29` after rebuild:

- final rows: 72,586
- missing club: 0
- missing manager: 0
- `Карельский (закрыт)`: 6,216 rows
- `Клуб не определен (fallback)`: 7 rows

Validation: `PASS`.
