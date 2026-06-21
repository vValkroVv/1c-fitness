# Step 28: Blamberus membership attribution check

Run date: `2026-06-02`

## Scope

Checked customer comment about client:

```text
Бламберус Михаил Александрович
client_id: 000073891
phone: +7 (953) 5298192
```

No code was changed. The check used the latest combined export:

```text
output/part2_20260525_0800_final_combined/
```

and the corresponding latest staging/audit CSV:

```text
output/part2_20260525_0800_final/
```

## Final XLSX result

In the latest combined `import_заявки` workbook the client is present once:

```text
file: output/part2_20260525_0800_final_combined/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
sheet: Лист1
row: 64947
client_id: 000073891
client_fio: Бламберус Михаил Александрович
funnel: новые заявки
funnel_step: неразобранные
create_date: 2026-05-15
manager: Васильева Яна Денисовна
филиал: Фитнес Империя (Гоголевский)
```

The client was not found in:

```text
output/part2_20260525_0800_final_combined/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx
```

In split CSV the same result is reproduced:

```text
output/part2_20260525_0800_final/csv/final_funnel_clients__novye_zayavki.csv: found
output/part2_20260525_0800_final/csv/final_funnel_clients__reaktivatsiya.csv: not found
```

So the latest build does not put this client into `Реактивация`; it puts him into `Новые заявки`.

## Staging facts

The source staging row is:

```text
client_ref: B214000C29D830FD11F1505B4DE7BB06
client_id: 000073891
client_fio: Бламберус Михаил Александрович
phones: +7 (953) 5298192
funnel: Новые заявки
funnel_step: Неразобранные
create_date: 2026-05-15
create_date_source: client_created_at_no_sales
selected_card_number: 1111111141755
selected_card_ref: B214000C29D830FD11F1505BD30BE477
active_full_subscription_count: 0
finished_full_subscription_count: 0
full_subscription_count: 0
trial_or_guest_sale_count: 0
selection_reason: no full subscription
validation_status: ok
```

`client_history_summary.csv` confirms the same source facts:

```text
has_any_sale: 0
has_any_full_subscription: 0
has_active_full_subscription: 0
has_finished_full_subscription: 0
full_subscription_count: 0
active_full_subscription_count: 0
finished_full_subscription_count: 0
```

The card staging confirms an active/unmarked plastic card on the client:

```text
client_ref: B214000C29D830FD11F1505B4DE7BB06
card_ref: B214000C29D830FD11F1505BD30BE477
plastic_card_number: 1111111141755
card_status: unmarked
is_unmarked: 1
issue_date: 2026-05-15
raw_source: dbo._Reference59
```

The normalized phone was unique in the latest staging/final rows; this row was not affected by same-phone deduplication.

## Current classification rule

The funnel is not chosen from card ownership alone.

Current extraction builds subscriptions from:

```text
dbo._InfoRg3060 + dbo._Document163
```

and attributes a subscription to:

```text
dbo._Document163._Fld9152RRef when it points to dbo._Reference64,
otherwise dbo._Document163._Fld1447_RRRef when _Fld1447_RTRef = 0x00000040.
```

Then the funnel rule is:

```text
has_active_full_subscription = 1 -> Действующие клиенты
has_any_full_subscription = 1 -> Реактивация
else -> Новые заявки
```

Plastic card ownership is extracted separately from:

```text
dbo._Reference59._Fld3750_RRRef
```

and is used for the selected card number, not for subscription/member attribution.

## Finding

For this client, the program did exactly what its current rules say:

1. It found a current/unmarked card owned by Blamberus.
2. It did not find any sale or full subscription where Blamberus is the holder/payer according to the current subscription extraction.
3. Therefore it classified the client as `Новые заявки`.
4. The plastic-card workbook excludes him because that workbook currently exports only internal `Действующие клиенты`.

The customer comment points to a business case that is not covered by the current pipeline: sale/member document remains on another client, while the plastic card owner was changed to Blamberus. The current pipeline can read the current card owner, but it does not use card-owner changes to transfer an active membership from the original sale/client to the current card owner.

## Open point

To classify these cases correctly, we need to identify the authoritative 1C source for membership owner transfer:

```text
card owner history document/register,
or membership/card link register,
or a document that connects old owner, new owner, card, and active membership.
```

Without that source, using only the latest card owner would be risky: it could incorrectly move memberships when the card and membership are not one-to-one.
