# Problem 1 execution log

Дата выполнения: `2026-06-22`

## Контекст

- Рабочий cutoff: `2026-05-25 08:00:00`.
- Backup/restore источник: `FitnessRestored_20260523_macos`.
- Корневые финальные XLSX не изменялись:
  - `fitbase_active_clients_import_zayavki_20260525_0800_all_funnels.xlsx`
  - `fitbase_active_clients_plastic_cards_20260525_0800_all_funnels.xlsx`
- Новый выход: `output/20251115_0800_fix_owner/`.

## SQL runtime

Изначально использовался восстановленный macOS Azure SQL Edge ARM64 runtime
`mssql-fitness-macos` на `127.0.0.1:11433`.

Во время широкого discovery по всем `_Document*` Azure SQL Edge упал с
`SIGABRT / S_SbtUnimplementedInstruction`. После пересоздания контейнера
Azure SQL Edge продолжил падать на старте `master`, до открытия SQL listener.

Чтобы не уходить от базы и продолжить работу только через SQL, поднят отдельный
контейнер:

```text
container: mssql-fitness-2022
image: mcr.microsoft.com/mssql/server:2022-latest
platform: linux/amd64
host port: 127.0.0.1:11434
database: FitnessRestored_20260523_macos
attach files: mssql-macos/data/FitnessRestored_20260523_macos.mdf/.ldf
```

Проверка после attach:

```text
state: ONLINE
compatibility_level: 130
user_tables: 2503
user_columns: 19421
```

Воспроизводимый старт/attach: `scripts/29_start_mssql_2022_attach_macos.sh`.

## Выполненные шаги

1. Извлечены скриншоты из `new-changes/Примеры ФИО (смена владельца).docx`.
2. `textutil` извлек только заголовки, поэтому ключевые поля вычитаны по изображениям вручную.
3. Найдена фактическая таблица документа смены владельца: `dbo._Document138`.
4. Найдены поля:
   - `_Fld762RRef`: старый клиент;
   - `_Fld767RRef`: новый владелец;
   - `_Fld763RRef`: членство/документ `_Document163`;
   - `_Fld764RRef`: модификатор, для членств `Смена владельца`.
5. Добавлен stage `fitbase_part2.stg_membership_owner_changes`.
6. В `fitbase_part2.stg_subscriptions_all` добавлен effective owner по последней смене владельца до cutoff.
7. Product-sale строки `_Document163` в `fitbase_part2.stg_sales_all` также переведены на effective owner.
8. Пересобраны raw stage, reclassified stage, combined XLSX и validation.

## Команды

Полная воспроизводимая команда:

```bash
scripts/30_build_owner_change_fix_outputs.sh
```

Фактические итоговые XLSX:

```text
output/20251115_0800_fix_owner/fitbase_active_clients_import_zayavki_20260525_0800__all_funnels.xlsx
output/20251115_0800_fix_owner/fitbase_active_clients_plastic_cards_20260525_0800__all_funnels.xlsx
```

После штатной validation wrapper переименовывает эти файлы в имена,
сопоставимые с корневыми финальными XLSX:

```text
output/20251115_0800_fix_owner/fitbase_active_clients_import_zayavki_20260525_0800_all_funnels.xlsx
output/20251115_0800_fix_owner/fitbase_active_clients_plastic_cards_20260525_0800_all_funnels.xlsx
```
