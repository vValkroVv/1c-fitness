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
| Импорт заявок | 64934 | 65231 | 297 | 64934 | 65231 | 297 | 64773 | 458 | 161 | 7480 | 57293 | 0 |
| Пластиковые карты | 10890 | 10907 | 17 |  |  |  | 10099 | 808 | 791 | 285 | 9814 | 0 |
| Абонементы клиентов | 99383 | 98944 | -439 | 43137 | 43080 | -57 | 98875 | 69 | 508 | 11154 | 87721 | 0 |
| Шаблоны абонементов | 114 | 114 | 0 |  |  |  | 112 | 2 | 2 | 7 | 105 | 0 |
| Услуги клиентов | 529 | 528 | -1 | 472 | 472 | 0 | 510 | 18 | 19 | 59 | 451 | 0 |
| Шаблоны услуг | 51 | 51 | 0 |  |  |  | 51 | 0 | 0 | 1 | 50 | 0 |

## Interpretation

Main count changes are consistent with the newer backup, the later
cutoff, and the explicit `Карельский -> Ровио` remap:

- `import_заявки`: `+297` rows/clients. There are `458` new exported client ids and `161` old exported client ids no longer exported.
- `plastic_cards`: `+17` rows. Since this XLSX has no `client_id`, rows are compared by normalized phone + FIO.
- `абонементы клиентов`: `-439` rows and `-57` row clients. Common contract rows are mostly stable: `87721` of `98875` common `contract_id` rows are byte-level identical at exported-field level.
- `шаблоны абонементов`: total stayed `114`; `7` shared template rows changed business values.
- `услуги клиентов`: `-1` row; unique client count stayed `472`.
- `шаблоны услуг`: total stayed `51`; `1` shared template changed business values.

The higher `changed_common` count versus the pre-Karelsky check is expected:
closed `Карельский` rows are now normalized to `Ровио, 3`, so shared rows also
receive Rovio managers instead of the former fallback manager.

Top changed fields confirm that this is primarily a manager remap:

- `import_заявки`: `manager:6042, funnel:1570, funnel_step:1570, филиал:529, create_date:363, phone:90, client_fio:85`
- `абонементы клиентов`: `manager:7749, card:2351, freeze:550, end_date:508, create_date:479, contract_name:331, phone:273, amount_of_payments:168`
- `услуги клиентов`: `manager:58, phone:1`

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
stayed the same did not change; the additional manager deltas are the intended
`Карельский -> Ровио` rule.

## Changed Field Highlights

### Импорт заявок

- top changed fields: `manager:6042, funnel:1570, funnel_step:1570, филиал:529, create_date:363, phone:90, client_fio:85`
- reason flags: `stage_export_source_changed:7480, selected_subscription_changed:1354, owner_change_client:1234, selected_subscription_sale_after_2026-05-23:646, same_subscription_crossed_cutoff_window:484, export_date_field_changed:363, client_created_after_2026-05-23:59, new_export_date_after_2026-05-23:59`
- details: `output/20260630_xlsx_comparison/import_zayavki__changed_common.csv`, `output/20260630_xlsx_comparison/import_zayavki__added.csv`, `output/20260630_xlsx_comparison/import_zayavki__removed.csv`

### Пластиковые карты

- top changed fields: `номер пластиковой карты:285`
- reason flags: `selected_card_changed_in_stage:285, selected_subscription_changed:191, owner_change_client:56`
- details: `output/20260630_xlsx_comparison/plastic_cards__changed_common.csv`, `output/20260630_xlsx_comparison/plastic_cards__added.csv`, `output/20260630_xlsx_comparison/plastic_cards__removed.csv`

### Абонементы клиентов

- top changed fields: `manager:7749, card:2351, freeze:550, end_date:508, create_date:479, contract_name:331, phone:273, amount_of_payments:168`
- reason flags: `membership_source_export_fields_changed:11154, client_or_card_fields_changed:9720, new_export_date_after_2026-05-23:1564, export_date_field_changed:976, owner_change_membership:772, money_fields_changed:170`
- details: `output/20260630_xlsx_comparison/membership_clients__changed_common.csv`, `output/20260630_xlsx_comparison/membership_clients__added.csv`, `output/20260630_xlsx_comparison/membership_clients__removed.csv`

### Шаблоны абонементов

- top changed fields: `freeze:4, duration:2, price:1`
- reason flags: `template_business_values_changed:7`
- details: `output/20260630_xlsx_comparison/membership_templates__changed_common.csv`, `output/20260630_xlsx_comparison/membership_templates__added.csv`, `output/20260630_xlsx_comparison/membership_templates__removed.csv`

### Услуги клиентов

- top changed fields: `manager:58, phone:1`
- reason flags: `service_client_fields_changed:59`
- details: `output/20260630_xlsx_comparison/service_clients__changed_common.csv`, `output/20260630_xlsx_comparison/service_clients__added.csv`, `output/20260630_xlsx_comparison/service_clients__removed.csv`

### Шаблоны услуг

- top changed fields: `duration:1`
- reason flags: `template_business_values_changed:1`
- details: `output/20260630_xlsx_comparison/service_templates__changed_common.csv`, `output/20260630_xlsx_comparison/service_templates__added.csv`, `output/20260630_xlsx_comparison/service_templates__removed.csv`
