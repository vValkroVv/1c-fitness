# Перенос `Новые заявки / Неразобранные` в абонементы с тегом

Дата реализации: `2026-07-06`

## Требование

По уточнению заказчика:

- брать клиентов именно из финального XLSX `import_заявки`;
- клиентов из `новые заявки / неразобранные` полностью убрать из этого XLSX;
- всех этих клиентов внести только в `Импорт_абонементы_клиентов.xlsx`;
- добавить в эту таблицу первый столбец `tag` / `Тег`;
- значение тега для перенесенных клиентов: `отказники`;
- остальные столбцы абонементов сдвинуть вправо.

## Реализованное правило

Порядок в пайплайне:

1. Строим полный `final_funnel_clients.csv`.
2. Применяем старое правило: `Новые заявки` без телефона не идут в финальный
   `import_заявки`.
3. Применяем same-phone dedup.
4. После этих финальных фильтров выделяем оставшиеся `Новые заявки /
   Неразобранные`.
5. Эти строки пишем в:

```text
output/20260630_fix_owner/csv/new_application_refusers.csv
```

6. Из финального `fitbase_active_clients_import_zayavki_20260630_all_funnels.xlsx`
   они удаляются.
7. Импорт абонементов читает union:
   - финальный `import_заявки` после удаления отказников;
   - `new_application_refusers.csv`.
8. Все строки абонементов отказников получают `tag=отказники`.
9. Если у отказника нет ни одного абонементного факта, добавляется одна
   клиентская строка-заглушка: `tag=отказники`, клиентские поля заполнены,
   абонементные поля пустые.

## Кодовые точки

- `scripts/17_build_part2_combined_xlsx.py`
  - выделяет финальных отказников;
  - пишет `new_application_refusers.csv`;
  - удаляет их из финального `import_заявки`.
- `scripts/18_validate_combined_single_stage_outputs.py`
  - проверяет, что отказники не остались в `import_заявки`;
  - проверяет состав `new_application_refusers.csv`.
- `scripts/19_build_membership_import_xlsx.py`
  - добавляет первую колонку `tag`;
  - читает отказников как дополнительный источник клиентов;
  - добавляет строки-заглушки для отказников без абонементов.
- `scripts/20_validate_membership_import_xlsx.py`
  - проверяет union источника;
  - разрешает пустые абонементные поля только для строк-заглушек
    `tag=отказники`.
- `scripts/30_build_owner_change_fix_outputs.sh`
  - включает новое правило в полный owner-change/заявочный прогон.

## Контрольные счетчики 20260630

```text
source final_funnel_clients: 73292
old final import_zayavki before this rule: 65231
new final import_zayavki after this rule: 39524
new_application_refusers.csv rows: 25707
new_application_refusers unique client_id: 25707
```

Импорт абонементов:

```text
source union clients: 65231
client membership rows: 120040
refuser source clients: 25707
refuser clients present in membership rows: 25707
refuser tagged rows: 26950
refuser real membership rows: 5854
refuser placeholder rows: 21096
duplicate nonblank contract_id values: 0
missing template names: 0
validation: PASS
```

Финальный `import_заявки`:

```text
Действующие абонементы / Все действующие абонементы: 10907
Реактивация(годовые абонементы) / Все закрытые абонементы: 28617
новые заявки / неразобранные: 0
validation: PASS
```

## Независимая проверка

Проверено отдельным чтением XLSX/CSV:

```text
membership first headers: tag, contract_id, client_id, phone, client_fio
missing_refuser_ids_in_membership: 0
unexpected_tag_ids: 0
check: PASS
```
