# XLSX comparison: 2026-05-23/25 vs 2026-06-30

Compared only the six requested XLSX pairs.

Old package:

- `output/20251115_0800_fix_owner/`
- `output/20251115_0800_fix_owner_new_import/`

New package:

- `output/20260630_fix_owner/`
- `output/20260630_fix_owner_new_import/`

Dates used for guard checks:

```text
old backup date: 2026-05-23
old export cutoff: 2026-05-25
new export cutoff: 2026-06-30
```

The phrase `с 23 мая по 3 июня` was treated as the backup-to-backup
window `2026-05-23` to `2026-06-30`, because the new file is
`Fitnes-30-06-26.bak`.

## Summary

| File | Old rows | New rows | Delta | Old clients | New clients | Client delta | Common | Added | Removed | Changed common | Unchanged common | Suspicious changed |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Импорт заявок | 64934 | 65231 | 297 | 64934 | 65231 | 297 | 64773 | 458 | 161 | 2070 | 62703 | 0 |
| Пластиковые карты | 10890 | 10907 | 17 |  |  |  | 10099 | 808 | 791 | 285 | 9814 | 0 |
| Абонементы клиентов | 99383 | 98944 | -439 | 43137 | 43080 | -57 | 98875 | 69 | 508 | 5199 | 93676 | 0 |
| Шаблоны абонементов | 114 | 114 | 0 |  |  |  | 112 | 2 | 2 | 7 | 105 | 0 |
| Услуги клиентов | 529 | 528 | -1 | 472 | 472 | 0 | 510 | 18 | 19 | 16 | 494 | 0 |
| Шаблоны услуг | 51 | 51 | 0 |  |  |  | 51 | 0 | 0 | 1 | 50 | 0 |

## Interpretation

Main count changes are consistent with the newer backup and later cutoff:

- `import_заявки`: `+297` clients. There are `458` new exported client ids and
  `161` old exported client ids no longer exported.
- `plastic_cards`: `+17` rows. Since this XLSX has no `client_id`, rows are
  compared by normalized phone + FIO.
- `абонементы клиентов`: `-439` rows and `-57` row clients. Common contract rows
  are mostly stable: `93676` of `98875` common `contract_id` rows are byte-level
  identical at exported-field level.
- `шаблоны абонементов`: total stayed `114`; two names were renamed/replaced
  and seven shared template rows changed business values.
- `услуги клиентов`: `-1` row; unique client count stayed `472`.
- `шаблоны услуг`: total stayed `51`; one shared template changed `duration`.

Added/removed `import_заявки` rows were checked against full stage:

```text
added to new XLSX:
  not_in_old_stage_new_in_backup: 419
  old_stage_present_filtered_by_phone_dedupe_or_changed_winner: 16
  was_in_old_stage_but_old_export_filtered: 15
  old_stage_new_application_without_phone: 8

removed from new XLSX:
  new_stage_new_application_without_phone: 131
  new_stage_present_filtered_by_phone_dedupe_or_changed_winner: 30
```

So the new/removed application rows are explained by genuinely new stage rows
or by the same export filters already used in the old build: no-phone new
applications and same-phone dedupe winner changes.

For `абонементы клиентов`, removed rows were not random XLSX drift:

```text
added contract rows:
  existing_client_new_contract_or_reincluded: 57
  new_or_updated_date_after_old_backup: 11
  client_not_in_old_stage: 1

removed contract rows:
  client_still_in_new_stage_contract_removed_or_reclassified: 508
```

This means removed `contract_id` rows belong to clients still present in the
new stage, but the contract set was recalculated by the fresh source data and
latest rules.

## Drift Guard

For `import_заявки` and `абонементы клиентов`, the comparison also
checked the staging/source rows used to build the XLSX. Rows whose
export source fields stayed identical did not change in the XLSX.

- `Импорт заявок`: PASS; suspicious changed keys = `0`.
- `Пластиковые карты`: PASS; suspicious changed keys = `0`.
- `Абонементы клиентов`: PASS; suspicious changed keys = `0`.
- `Шаблоны абонементов`: PASS; suspicious changed keys = `0`.
- `Услуги клиентов`: PASS; suspicious changed keys = `0`.
- `Шаблоны услуг`: PASS; suspicious changed keys = `0`.

Conclusion: for the six requested XLSX, there are no unexplained changes among
common keys. Rows that should not change because their exported source fields
stayed the same did not change.

## Changed Field Highlights

### Импорт заявок

- top changed fields: `funnel:1570, funnel_step:1570, manager:576, филиал:529, create_date:363, phone:90, client_fio:85`
- reason flags: `stage_export_source_changed:2070, selected_subscription_changed:1333, owner_change_client:800, selected_subscription_sale_after_2026-05-23:646, same_subscription_crossed_cutoff_window:483, export_date_field_changed:363, client_created_after_2026-05-23:59, new_export_date_after_2026-05-23:59`
- details: `output/20260630_xlsx_comparison/import_zayavki__changed_common.csv`, `output/20260630_xlsx_comparison/import_zayavki__added.csv`, `output/20260630_xlsx_comparison/import_zayavki__removed.csv`

### Пластиковые карты

- top changed fields: `номер пластиковой карты:285`
- reason flags: `selected_card_changed_in_stage:285, selected_subscription_changed:191, owner_change_client:56`
- details: `output/20260630_xlsx_comparison/plastic_cards__changed_common.csv`, `output/20260630_xlsx_comparison/plastic_cards__added.csv`, `output/20260630_xlsx_comparison/plastic_cards__removed.csv`

### Абонементы клиентов

- top changed fields: `card:2351, manager:1770, freeze:550, end_date:508, create_date:479, contract_name:331, phone:273, amount_of_payments:168`
- reason flags: `membership_source_export_fields_changed:5199, client_or_card_fields_changed:3755, new_export_date_after_2026-05-23:1524, export_date_field_changed:976, owner_change_membership:492, money_fields_changed:170`
- details: `output/20260630_xlsx_comparison/membership_clients__changed_common.csv`, `output/20260630_xlsx_comparison/membership_clients__added.csv`, `output/20260630_xlsx_comparison/membership_clients__removed.csv`

### Шаблоны абонементов

- top changed fields: `freeze:4, duration:2, price:1`
- reason flags: `template_business_values_changed:7`
- details: `output/20260630_xlsx_comparison/membership_templates__changed_common.csv`, `output/20260630_xlsx_comparison/membership_templates__added.csv`, `output/20260630_xlsx_comparison/membership_templates__removed.csv`

### Услуги клиентов

- top changed fields: `manager:15, phone:1`
- reason flags: `service_client_fields_changed:16`
- details: `output/20260630_xlsx_comparison/service_clients__changed_common.csv`, `output/20260630_xlsx_comparison/service_clients__added.csv`, `output/20260630_xlsx_comparison/service_clients__removed.csv`

### Шаблоны услуг

- top changed fields: `duration:1`
- reason flags: `template_business_values_changed:1`
- details: `output/20260630_xlsx_comparison/service_templates__changed_common.csv`, `output/20260630_xlsx_comparison/service_templates__added.csv`, `output/20260630_xlsx_comparison/service_templates__removed.csv`
