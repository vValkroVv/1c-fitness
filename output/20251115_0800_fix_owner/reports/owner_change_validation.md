# Owner Change Validation

cutoff: `2026-05-25 08:00:00`

## Source

- owner-change source table: `dbo._Document138`
- membership modifier: `Смена владельца`
- effective rule: latest owner-change per membership on cutoff

## Counts

```text
membership_owner_change_rows: 781
effective_membership_owner_changes: 746
memberships_with_multiple_changes: 30
stg_subscriptions_all_rows: 115204
```

## Final Outputs

```text
main_xlsx_rows: 64934
cards_xlsx_rows: 10890
validation_verdict: PASS
validation_errors: 0
```

## Named Cases

| Client | Result |
| --- | --- |
| Успенский Леонид Владимирович | moved from `Новые заявки` to `Действующие клиенты`; selected subscription `Абонемент Ультра 15 месяцев (подарок)` |
| Василевская Вера Михайловна | moved from `Реактивация` to `Действующие клиенты`; selected subscription `Абонемент МУЛЬТИКАРТА 12 месяцев (подарок)` |
| Россиева София Сергеевна | not applied because `56554` is after cutoff and after backup finish |
| Бламберус Михаил Александрович | unchanged because no membership owner-change document was found on cutoff |

## Delta Guard

```text
changed_final_clients: 889
changed_not_in_owner_change_old_new_or_original_client_set: 0
```

The final stage delta is limited to clients involved in membership owner-change
chains and their recalculated funnel results.
