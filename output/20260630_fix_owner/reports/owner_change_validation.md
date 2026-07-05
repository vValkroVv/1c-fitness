# Owner Change Validation

cutoff: `2026-06-30 23:27:03`

## Source

- owner-change source table: `dbo._Document138`
- membership modifier: `Смена владельца`
- effective rule: latest owner-change per membership on cutoff

## Counts

```text
membership_owner_change_rows: 4595
effective_membership_owner_changes: 4458
memberships_with_multiple_changes: 123
stg_subscriptions_all_rows: 116267
subscriptions_with_owner_change: 4441
```

## Final Outputs

```text
main_xlsx_rows: 65231
cards_xlsx_rows: 10907
validation_verdict: PASS
validation_errors: 0
```

## Named Cases

| Client | Result |
| --- | --- |
| Успенский Леонид Владимирович | `Действующие клиенты`; selected subscription `Абонемент Ультра 15 месяцев (подарок)`, sale `2026-05-11`, end `2027-08-13` |
| Василевская Вера Михайловна | `Действующие клиенты`; selected subscription `Абонемент МУЛЬТИКАРТА 12 месяцев (подарок)`, sale `2026-04-30`, end `2027-08-19` |
| Россиева София Сергеевна | now included on fresh cutoff; `Действующие клиенты`; selected subscription `Абонемент МУЛЬТИКАРТА 15 месяцев (подарок) спецпредложение`, sale `2026-05-29`, end `2027-09-30` |
| Бламберус Михаил Александрович | unchanged: `Новые заявки`; no selected subscription, card `1111111141755` |

## Note

The previous May report compared against an older non-owner-change baseline for
delta guard. For this fresh backup run, the reproducible pipeline was executed
directly with the final owner-change SQL, so the new guard is source/count and
named-case validation against the fresh stage.
