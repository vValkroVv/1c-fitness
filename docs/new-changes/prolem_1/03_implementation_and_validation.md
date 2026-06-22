# Owner-change implementation and validation

Дата: `2026-06-22`

## Изменения пайплайна

Обновлен SQL stage:

```text
sql/part2_03_build_three_funnel_staging.sql
```

Добавлено:

- `fitbase_part2.stg_membership_owner_changes`;
- temp-слой `#latest_membership_owner_changes`;
- audit-поля в `fitbase_part2.stg_subscriptions_all`:
  - `original_client_ref/id/fio`;
  - `effective_client_ref/id/fio`;
  - `owner_change_ref/number/datetime`;
  - `owner_change_old_client_ref`;
  - `owner_change_new_client_ref`;
  - `owner_change_modifier_name`;
  - `owner_change_count_for_membership`.

`client_ref` в `stg_subscriptions_all` теперь равен effective owner:

- если есть owner-change по этому членству до cutoff, берется последний новый владелец;
- иначе остается старый источник из `_Document163`.

Product-sale строки `_Document163` в `stg_sales_all` также используют effective
owner для того же membership_ref. Payment-sale документы не переносились.

Обновлен экспорт:

```text
scripts/11_export_part2_stage.py
scripts/16_reclassify_part2_from_csv.py
```

Добавлены воспроизводимые скрипты:

```text
scripts/29_start_mssql_2022_attach_macos.sh
scripts/30_build_owner_change_fix_outputs.sh
```

## Сборка

Raw stage:

```text
output/20251115_0800_fix_owner/raw/staging
output/20251115_0800_fix_owner/raw/reports
```

Final stage/reports:

```text
output/20251115_0800_fix_owner/staging
output/20251115_0800_fix_owner/reports
```

Итоговые XLSX:

```text
output/20251115_0800_fix_owner/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
output/20251115_0800_fix_owner/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx
```

Канонические файлы отдачи после переименования:

```text
output/20251115_0800_fix_owner/fitbase_active_clients_import_zayavki_20260525_0800_all_funnels.xlsx
output/20251115_0800_fix_owner/fitbase_active_clients_plastic_cards_20260525_0800_all_funnels.xlsx
```

## Row counts

Raw stage:

```text
stg_clients: 72862
stg_client_contacts: 66838
stg_products: 1672
stg_membership_owner_changes: 781
stg_subscriptions_all: 115204
stg_sales_all: 504728
stg_plastic_cards: 106116
client_history_summary: 72862
subscription_candidates_ranked: 86010
selected_subscriptions: 46527
selected_cards: 72862
final_funnel_clients: 72862
```

Final XLSX build:

```text
source_rows: 72862
main_xlsx_rows: 64934
cards_xlsx_rows: 10890
phone_deduplication_removed_rows: 2390
```

Штатная валидация:

```text
verdict: PASS
errors: 0
warnings: 6
report: output/20251115_0800_fix_owner/reports/validation_report.md
```

## Named-case validation

| Клиент | Было | Стало |
| --- | --- | --- |
| Успенский Леонид Владимирович | `Новые заявки`, без выбранного членства | `Действующие клиенты`, членство `96AFCE6501B2EE5D46D58F59CD08E816`, `Абонемент Ультра 15 месяцев (подарок)` |
| Василевская Вера Михайловна | `Реактивация`, старое закрытое членство | `Действующие клиенты`, членство `AC6821C9CA0E5EDC43E262BF4F962AA7`, `Абонемент МУЛЬТИКАРТА 12 месяцев (подарок)` |
| Натарьев Григорий Павлович | удерживал переданное членство Успенского | переданное членство снято; остался действующим по другому членству |
| Филюк Владислав Андреевич | удерживал часть переданной истории | переданное членство снято; остался действующим по другому членству |
| Россиева София Сергеевна | не найдена в текущем stage | не менялась: документ `56554` после cutoff/backup |
| Бламберус Михаил Александрович | `Новые заявки` | не менялся: в `_Document138` нет членского owner-change на cutoff |

## Дельта stage

По `final_funnel_clients.csv` изменилось `889` клиентов. Все изменившиеся
клиенты входят в множество:

- старых владельцев из owner-change;
- новых владельцев из owner-change;
- исходных владельцев членств, если по одному членству было несколько
  owner-change и последний old_owner уже не равен исходному клиенту продажи.

Проверка:

```text
changed final clients: 889
changed not in all old/new/original owner-change client set: 0
```

То есть дельта ограничена owner-change-цепочками и пересчетом их последствий.
