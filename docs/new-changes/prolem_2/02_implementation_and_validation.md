# Implementation and validation

## Созданные файлы

SQL:

- `sql/30_membership_import_discovery.sql`
- `sql/31_build_membership_import_staging.sql`

Скрипты:

- `scripts/macos_backup_bcp.sh`
- `scripts/19_build_membership_import_xlsx.py`
- `scripts/20_validate_membership_import_xlsx.py`
- `scripts/31_build_membership_import_outputs.sh`

Output:

- `output/20251115_0800_fix_owner_new_import/fitbase_import_abonementy_clientov_20260525_0800.xlsx`
- `output/20251115_0800_fix_owner_new_import/fitbase_import_shablony_abonementov_20260525_0800.xlsx`
- `output/20251115_0800_fix_owner_new_import/staging/membership_import_facts.tsv`
- `output/20251115_0800_fix_owner_new_import/staging/membership_import_rows.csv`
- `output/20251115_0800_fix_owner_new_import/staging/membership_template_rows.csv`

Reports:

- `output/20251115_0800_fix_owner_new_import/reports/validation_report.md`
- `output/20251115_0800_fix_owner_new_import/reports/validation_recheck.md`
- `output/20251115_0800_fix_owner_new_import/reports/rassrochka_validation.md`
- `output/20251115_0800_fix_owner_new_import/reports/membership_import_uncertainties.csv`
- `output/20251115_0800_fix_owner_new_import/reports/zero_price_report.csv`

## XLSX validation

Независимый валидатор:

```bash
python3 scripts/20_validate_membership_import_xlsx.py \
  --source-output-dir output/20251115_0800_fix_owner \
  --output-dir output/20251115_0800_fix_owner_new_import
```

Результат:

```text
status: PASS
client rows: 99399
template rows: 114
source final clients: 64934
row clients: 43254
duplicate contract_id values: 0
missing template names: 0
```

Проверено:

- технические заголовки клиентского XLSX совпадают с шаблоном на 20 колонок;
- технические заголовки шаблонов абонементов совпадают с целевым порядком на
  12 колонок, включая `branches_access`;
- все `client_id` в клиентском файле входят в финальный XLSX заявок;
- `contract_id` уникальны;
- каждый `contract_name` клиентского файла есть в файле шаблонов;
- обязательные поля по локальной проверке не пустые.

## Бизнес-проверки

Смена владельца:

- SQL staging использует эффективного владельца из уже исправленного
  `stg_subscriptions_all`.
- В staging до финального XLSX-фильтра найдено `725` строк со сменой владельца.

Рассрочка:

- строк с маркером `рассрочка`: `21`;
- строк с положительным `payment_left`: `18`;
- строк, где название содержит `рассрочка`, но `_Fld3072 = 0`: `3`;
- для этих 3 строк найден ближайший платеж `dbo._Document152`, поэтому они
  больше не требуют ручной проверки;
- строк, где не найден ни `_Fld3072`, ни платежный fallback: `0`.

Шаблоны:

- уникальные шаблоны строятся по нормализованному названию;
- если для одного названия встречается несколько вариантов цены/длительности,
  используется вариант последней продажи, а конфликт пишется в
  `membership_import_uncertainties.csv`;
- `branches_access = Все` для названий с `мультикарта`, иначе `Продажа`;
- для ограниченной субаренды `visits` в шаблоне берется из названия
  (`8/12/15 посещений`).

## Проверка `Импорт_шаблоны_абонементов.xlsx`

Файл:

- `output/20251115_0800_fix_owner_new_import/fitbase_import_shablony_abonementov_20260525_0800.xlsx`

Итоговая техническая проверка:

- строк данных: `114`;
- уникальных названий шаблонов: `114`;
- дублей `name`: `0`;
- названий из клиентского импорта без шаблона: `0`;
- шаблонов, которые не используются в клиентском импорте: `0`;
- обязательные поля `branches_access`, `name`, `price`, `duration`,
  `duration_type` заполнены во всех строках;
- отрицательных `price`/`duration`: `0`;
- `duration_type`: везде `месяц`;
- `branches_access`: `Все` для `29` мультикарт, `Продажа` для `85`
  остальных шаблонов.

Поле `visits` заполнено только для ограниченной субаренды:

- `СУБАРЕНДА 8 посещений` -> `8`;
- `СУБАРЕНДА 10 посещений` -> `10`;
- `СУБАРЕНДА 12 посещений` -> `12`;
- `СУБАРЕНДА 15 посещений` -> `15`;
- `СУБАРЕНДА 20 посещений` -> `20`.

Осознанные допущения по шаблонам:

1. Для `90` названий найдено несколько исторических вариантов
   цены/длительности/заморозки/доступа. В итоговый файл выводится один
   шаблон на одно название, выбран вариант последней продажи. Все такие случаи
   зафиксированы как `template_variants_collapsed_to_latest_sale` в
   `membership_import_uncertainties.csv`.
2. `visits` не заполняется автоматически для всех названий, где в тексте есть
   слово `посещений`. Сейчас это сделано только для ограниченной субаренды.
   Если бизнес-правило должно быть шире, отдельно проверить:
   `Абонемент УЛЬТРА 1 МЕСЯЦ 8 посещений` (`771` строка в клиентском
   импорте), `Абонемент УЛЬТРА 1 МЕСЯЦ 12 посещений` (`692`),
   `АБОНЕМЕНТ лимфодренажная тренировка (10 посещений),1 мес.` (`54`),
   `Пробное посещение АКВА` (`48`), `Разовое посещение АКВА` (`69`).
3. Опциональные поля `guests`, `first_visit_activation`, `archive`,
   `category`, `legal_entity` оставлены пустыми, потому что надежного источника
   и обязательного бизнес-правила для них в текущей инструкции нет.

## Осознанные ограничения

1. `payment_type` пустой в `29 139` строках итоговой XLSX; все эти строки в
   текущей сборке являются бизнес-исключениями. Non-business пустого
   `payment_type`: `0`.
2. `price=0` в `29 346` строках. Значительная часть закрыта бизнес-правилами:
   старый 2018 full/gift пласт, подтвержденные бесплатные недели и full
   `price=0` без платежа. Дополнительно закрыты `price=0` без платежа,
   `price=0` с fallback-платежом и `price=0` с пустым raw method.
   Контрольный non-business слой: `207` строк `price=0` с direct-платежом,
   где `payment_type` оставлен как есть.
3. `visits_left` по ограниченной субаренде закрыт в текущей сборке:
   `12` активных строк заполнены балансом `_AccumRg3336`, `916`
   просроченных строк заполнены `0`, безлимитная субаренда оставлена пустой.
