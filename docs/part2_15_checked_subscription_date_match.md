# Part 2 Checked Subscription Date Match

Date: 2026-05-20

## Source

Checked manager file:

- `output/splits/checked/fitbase_active_clients_import_zayavki_20260429__05_tolko_neskolko_abonementov(проверено).xlsx`

Columns used:

- `Дата продажи`
- `Дата активации`
- `Дата окончания`
- manager comment column

Comparison report:

- `output/part2_20260429/reports/checked_subscription_date_match.csv`

## Result

Rows in checked subscription file: 92.

Rows with explicit sale/start/end dates from managers: 10.

Current automatic selected active subscription matches manager-provided dates:

- full match: 7
- mismatch / needs decision: 3

For cells like `09.10.2025(11.11.2025)`, both date options were accepted as
manager-provided dates. This matters for rows where managers wrote the original
date and the corrected date in parentheses.

## Full Matches

- `000000317` / Александров Виктор Анатольевич:
  selected `2025-05-30 / 2025-05-30 / 2026-08-29`.
- `000002557` / Васара Татьяна Алексеевна:
  selected `2025-11-11 / 2025-11-12 / 2026-11-11`, matching the dates in
  parentheses.
- `000043376` / Яковлева Анастасия Ильинична:
  selected `2026-01-23 / 2026-02-23 / 2027-02-22`, matching the dates in
  parentheses.
- `000066967`:
  selected `2026-03-30 / 2026-04-13 / 2027-07-12`.
- `000071850`:
  selected `2026-03-20 / 2026-03-20 / 2027-07-19`.
- `000072596`:
  selected `2026-02-13 / 2026-02-13 / 2027-02-12`.
- `000073125`:
  selected `2026-03-19 / 2026-03-19 / 2027-05-18`.

## Mismatches

### `000069463` / Зубкова Мария Николаевна

Manager dates:

- sale: `2026-07-31`
- start: `2026-07-31`
- end: `2026-09-21`

Automatic selected subscription:

- sale: `2025-07-31`
- start: `2025-07-31`
- end: `2026-09-21`

The selected subscription end date matches. Sale/start differ only by year.
There is no active candidate in staging with sale/start `2026-07-31`, so this
looks like a likely year typo in the checked file or a manager note not present
as a separate 1C subscription row.

### `000070370` / Овчинников Алексей Константинович

Manager dates:

- sale: `2025-09-30`
- start: `2025-09-30`
- end: `2026-09-29`

Automatic selected subscription:

- sale: `2026-03-04`
- start: `2026-04-04`
- end: `2027-07-03`

The manager-selected dates match an existing active candidate, but it is rank 2
by the current rule. Current rule selects rank 1 because `2027-07-03` is later
than `2026-09-29`.

Decision needed: if manager choice is authoritative, add an explicit
subscription override for this client.

### `000070786` / Корнев Михаил Дмитриевич

Manager dates:

- sale: `2025-10-24`
- start: `2025-11-21`
- end: `2027-01-15`

Automatic selected subscription:

- sale: `2026-01-13`
- start: `2026-01-31`
- end: `2027-04-29`

No active candidate extracted into staging matches the manager date triplet.
The two active candidates in staging have the same selected date triplet
`2026-01-13 / 2026-01-31 / 2027-04-29`.

Decision needed: either investigate the SQL source for this client or provide a
business override with the correct subscription identifier/source.

## Recommendation

Keep the automatic rule for the 7 matching rows.

For `000070370`, add manual override support if the manager-selected rank 2
subscription should win over the longer end-date rule.

For `000069463` and `000070786`, do not blindly override from dates only:

- `000069463` may be a year typo in the manager file.
- `000070786` has no matching active subscription row in the current extracted
  staging data.
