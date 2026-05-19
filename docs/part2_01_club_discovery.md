# Part 2 Club Discovery

Date: 2026-05-20

SQL files:

- `sql/part2_01_find_club_references.sql`
- `sql/part2_02_find_club_links.sql`

Outputs:

- `output/part2_20260429/reports/club_reference_candidates.csv`
- `output/part2_20260429/reports/club_link_candidates.csv`

## Result

Direct reliable club links found:

- `dbo._Document163._Fld1443RRef -> dbo._Reference105` for membership documents.
- `dbo._Document152._Fld1051RRef -> dbo._Reference105` for payment/sale documents.
- `dbo._Reference64._Fld3831RRef -> dbo._Reference105` for client-level
  fallback club, used only when no sale/subscription club is available.

Reference105 contains reliable club-like organization values for:

- `Фитнес Империя (Гоголевский)` -> `Коммунальная, 20`
- `Фитнес Империя (Столица)` -> `Лососинское шоссе, 26`
- `Фитнес Империя (Промышленная)` -> `Промышленная, 10`
- `Фитнес Империя (Карельский)` -> `Карельский (закрыт)`
- `Фитнес Империя (Ровио,3)` -> `Ровио, 3`

The business mapping is saved in `config/club_org_mapping.csv`. `Карельский`
is intentionally preserved as `Карельский (закрыт)` with fallback manager
`УТОЧНИТЬ: Карельский`, because the club is closed and final manager mapping
will be provided later.

After applying this mapping, the baseline export has:

- rows without normalized club: 0
- rows without manager: 0
- fallback `Карельский (закрыт)`: 6,216 rows
- fallback `Клуб не определен (fallback)`: 7 rows

## Decision

Part 2 uses direct document organization links first, product-name club hints
second, client-level club fallback third, and only then assigns
`Клуб не определен (fallback)`. People are not left without a club/manager.
