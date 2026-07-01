# Problem 2 execution log

Рабочий срез: `2026-05-25 08:00`.

Источник клиентов для нового импорта абонементов:

- `output/20251115_0800_fix_owner/fitbase_active_clients_import_zayavki_20260525_0800_all_funnels.xlsx`

Важно: `output/20251115_0800_fix_owner/staging/final_funnel_clients.csv`
использован только как вспомогательный источник выбранной карты. Этот CSV
содержит полный stage на `72 862` клиента и не является финальным источником
состава клиентов после XLSX-фильтров и phone-dedup.

## Команды

Полный воспроизводимый запуск:

```bash
scripts/31_build_membership_import_outputs.sh
```

Отдельные шаги пайплайна:

```bash
SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/31_build_membership_import_staging.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/31_build_membership_import_staging.txt

python3 scripts/19_build_membership_import_xlsx.py \
  --source-output-dir output/20251115_0800_fix_owner \
  --output-dir output/20251115_0800_fix_owner_new_import

python3 scripts/20_validate_membership_import_xlsx.py \
  --source-output-dir output/20251115_0800_fix_owner \
  --output-dir output/20251115_0800_fix_owner_new_import
```

## Результат

Итоговые XLSX:

- `output/20251115_0800_fix_owner_new_import/fitbase_import_abonementy_clientov_20260525_0800.xlsx`
- `output/20251115_0800_fix_owner_new_import/fitbase_import_shablony_abonementov_20260525_0800.xlsx`

Ключевые отчеты:

- `output/20251115_0800_fix_owner_new_import/reports/validation_report.md`
- `output/20251115_0800_fix_owner_new_import/reports/validation_recheck.md`
- `output/20251115_0800_fix_owner_new_import/reports/rassrochka_validation.md`
- `output/20251115_0800_fix_owner_new_import/reports/membership_import_uncertainties.csv`
- `output/20251115_0800_fix_owner_new_import/reports/zero_price_report.csv`

## Итоговые счетчики

- финальные клиенты из XLSX: `64 934`
- клиенты с хотя бы одной строкой абонемента: `43 254`
- клиенты без строк абонементов: `21 680`
- строки клиентских абонементов: `99 399`
- строки шаблонов абонементов: `114`
- дубли `contract_id`: `0`
- названия абонементов без шаблона: `0`
- `payment_type`: `безналичные` - `66 604`, `сбп` - `1 488`,
  пусто - `31 307`
- статус независимой XLSX-проверки: `PASS`

## Зафиксированные неопределенности

- `payment_type` пустой в `31 307` строках после фикса прямой связи
  `Document152 -> Document154 -> Document163`: `24 807` без платежного
  документа, `6 500` с пустым или немаппируемым способом оплаты.
- `price=0` в `29 338` строках. Часть строк бесплатная, но много старых
  полноценных абонементов с датой продажи `2018-01-01`; нужна бизнес-проверка,
  можно ли оставлять `0` или нужно заменять на цену шаблона.
- на первом проходе `visits_left` для ограниченной субаренды был оставлен
  пустым и строки были помечены в `membership_import_uncertainties.csv`;
  позднее для активных ограниченных строк найден источник списаний
  `dbo._Document150` + `dbo._AccumRg3336`, см. раздел ниже.

## 2026-06-22: разбор `visits_left` для субаренды

Запущен узкий SQL-discovery:

```bash
SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/37_subrent_visits_left_discovery.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/37_subrent_visits_left_discovery.txt
```

Итог:

- детальный разбор записан в
  `docs/new-changes/prolem_2/current_subrent_visits_left_state.md`;
- финальный XLSX содержит `1 707` строк субаренды: `779` безлимитных и `928`
  ограниченных;
- из `928` ограниченных строк только `12` активны на cutoff `2026-05-25`;
- `_InfoRg3060._Fld8007/_Fld8008/_Fld8009` не подходят как `visits_left`;
- `_AccumRg3233` матчится с документами субаренды, но является денежным
  регистром продажи, не регистром остатков посещений;
- `_AccumRg3206` матчится только по клиенту и не дает связи с конкретной
  субарендой.

Дополнительный targeted-разбор активных ограниченных строк:

```bash
SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/39_document150_active_subrent_probe.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/39_document150_active_subrent_probe.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/40_document150_subrent_visit_counts.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/40_document150_subrent_visit_counts.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/41_document150_recorder_movement_probe.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/41_document150_recorder_movement_probe.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/42_accumrg3336_subrent_visit_movement_probe.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/42_accumrg3336_subrent_visit_movement_probe.txt
```

Итог дополнительного разбора:

- `dbo._Document150` найден как документ прохода/посещения:
  `_Fld991_RRRef` матчится с `subscription_ref`, `_Fld989_RRRef` с клиентом;
- все `87` проходов активных `12` ограниченных строк имеют движения в
  `dbo._AccumRg3336`;
- в `dbo._AccumRg3336` каждая активная строка имеет `_RecordKind = 1`,
  `_Active = 0x01`, `_Fld3337_RRRef = subscription_ref`, `_Fld3339 = 1.000`;
- первичный расчет активных строк через расход дал те же числа:
  лимит `133`, списано `87`, остаток `46`;
- ниже этот вывод уточнен до правильного правила: считать не только расход,
  а знаковый баланс `_AccumRg3336` на размерности `_Fld3338_TYPE = 0x01`;
- для закрытой истории нужны отдельные правила, потому что среди старых
  финальных строк есть `61` аномалия регистра.

## 2026-06-22: уточнение баланса `_AccumRg3336` по размерности

После первого разбора проверен не только расход от `_Document150`, но и полный
баланс регистра `_AccumRg3336`.

Команды:

```bash
SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/43_accumrg3336_full_balance_probe.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/43_accumrg3336_full_balance_probe.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/44_accumrg3336_dimension_probe.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/44_accumrg3336_dimension_probe.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/45_accumrg3336_correct_dimension_sequence.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/45_accumrg3336_correct_dimension_sequence.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/46_accumrg3336_correct_dimension_historical_validation.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/46_accumrg3336_correct_dimension_historical_validation.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
  scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/47_accumrg3336_correct_dimension_balance_rows.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/47_accumrg3336_correct_dimension_balance_rows.txt
```

Итог:

- физической таблицы итогов для `3336` нет: в базе найдена только
  `dbo._AccumRg3336`;
- сырой баланс `_AccumRg3336` по одному `subscription_ref` использовать нельзя:
  у активных `12` строк лимит из названий `133`, но сырой приход по всем
  размерностям `266`;
- причина удвоения: вторая размерность `_Fld3338_TYPE = 0x08` дублирует
  приход лимита и не списывается посещениями;
- правильная размерность посещений:
  `_Fld3338_TYPE = 0x01`, `_Fld3338_RTRef = 0x00000000`,
  `_Fld3338_RRRef = 0x00000000000000000000000000000000`;
- по правильной размерности активные `12` строк дают приход `133`, расход
  `87`, остаток `46`;
- последовательность движения подтверждена: например `15 -> 14 -> 13` и
  `12 -> 11 -> ... -> 0`;
- все финальные `928` ограниченных строк сматчились с SQL-балансом;
- финальное разложение: `867` clean, `39` receipt_not_equal_name_limit,
  `13` no_register_movements, `9` negative_balance;
- все `12` активных финальных строк находятся в clean-группе; все `61`
  аномальные строки относятся к закрытой истории.

## 2026-06-23: правило `Смена владельца подарочной карты`

После ручной проверки кейсов `00000100483` и `00000130311` подтверждено, что
модификатор `_Document138` `Смена владельца подарочной карты` тоже переносит
владельца членства. Правило добавлено в основной staging SQL:

```text
sql/part2_03_build_three_funnel_staging.sql
```

Используемый фильтр:

```sql
LTRIM(RTRIM(mod._Description)) IN (
    N'Смена владельца',
    N'Смена владельца подарочной карты'
)
```

Команды пересборки:

```bash
PART2_SQLCMD=scripts/macos_backup_sqlcmd.sh \
SQLCMD_SERVER='mssql-fitness-2022,1433' \
scripts/11_export_part2_stage.py \
  --database FitnessRestored_20260523_macos \
  --cutoff-date '2026-05-25' \
  --cutoff-at '2026-05-25 08:00:00' \
  --backup-finish-at '2026-05-23 23:17:17' \
  --output-run-label '20251115_0800_fix_owner_gift_owner_change_rebuild' \
  --output-dir 'output/20251115_0800_fix_owner_new_import/_tmp_owner_change_rebuild/staging' \
  --reports-dir 'output/20251115_0800_fix_owner_new_import/_tmp_owner_change_rebuild/reports' \
  --logs-dir 'logs/new-changes/prolem_2'

MEMBERSHIP_SOURCE_OUTPUT_ROOT='output/20251115_0800_fix_owner' \
MEMBERSHIP_OUTPUT_ROOT='output/20251115_0800_fix_owner_new_import' \
MEMBERSHIP_DATABASE_NAME='FitnessRestored_20260523_macos' \
MEMBERSHIP_SQLCMD_SERVER='mssql-fitness-2022,1433' \
MEMBERSHIP_DATE_STAMP='20260525_0800' \
scripts/31_build_membership_import_outputs.sh
```

Контрольные счетчики после пересборки:

- `fitbase_part2.stg_membership_owner_changes`: `4 552` строк;
- `Смена владельца подарочной карты`: `3 771` строк;
- effective latest `Смена владельца подарочной карты`: `3 673` строк;
- `fitbase_part2.membership_import_facts`: `100 399` строк до фильтра
  итоговым `import_заявки`;
- основной клиентский XLSX абонементов: `99 387` строк;
- шаблоны абонементов: `114` строк;
- validation: `PASS`, duplicate `contract_id`: `0`.

Точечные проверки в новом основном XLSX:

| contract_id | Результат |
| --- | --- |
| `00000100483` | теперь `000054013`, Коновалов Никита Витальевич |
| `00000130311` | теперь `000061275`, Сергеева Ирина Борисовна |

Representative/test XLSX `membership_import_representative_30_examples_20260525_0800.xlsx`
намеренно не пересобирался.

## 2026-06-22: регенерация XLSX с `visits_left`

Принято бизнес-правило: все просроченные ограниченные субаренды получают
`visits_left = 0`; активные ограниченные субаренды получают реальный остаток
по балансу `_AccumRg3336`; безлимитная субаренда остается пустой.

Изменения в пайплайне:

- `sql/31_build_membership_import_staging.sql` добавляет поля баланса
  `_AccumRg3336` по правильной размерности `_Fld3338_TYPE = 0x01`;
- `scripts/31_build_membership_import_outputs.sh` экспортирует эти поля в
  `membership_import_facts.tsv`;
- `scripts/19_build_membership_import_xlsx.py` заполняет `visits_left`:
  active limited = баланс регистра, expired limited = `0`, unlimited = blank.

Запуск:

```bash
scripts/31_build_membership_import_outputs.sh
```

Итог validation:

- `client membership rows`: `99 399`;
- `membership template rows`: `114`;
- `duplicate contract_id count`: `0`;
- `contract names missing in template file`: `0`;
- `status`: `PASS`.

Проверка `visits_left`:

- ограниченная субаренда: `928`;
- пустых `visits_left` среди ограниченной субаренды: `0`;
- `business_expired_limited_subrent_zero_visits_left`: `916`;
- `rg3336_correct_dimension_balance`: `12`;
- безлимитная субаренда с пустым `visits_left`: `779`;
- активные остатки: `0, 0, 2, 3, 2, 2, 3, 8, 5, 7, 11, 3`.

Новые итоговые файлы:

- `output/20251115_0800_fix_owner_new_import/fitbase_import_abonementy_clientov_20260525_0800.xlsx`;
- `output/20251115_0800_fix_owner_new_import/fitbase_import_shablony_abonementov_20260525_0800.xlsx`.

## 2026-06-22: прочитаны ответы бизнеса по 25 примерам `price/payment_type`

Входной файл:

```text
output/20251115_0800_fix_owner_new_import/payment_price_manual_review_examples_20260525_0800-with-answers.xlsx
```

Особенность файла: подготовленные колонки `correct_price`,
`correct_payment_type`, `comment` остались пустыми; ответы внесены в две
безымянные колонки в конце файла.

Проверено:

- `25` строк на листе `manual_review_25`;
- все `25` строк сопоставлены с текущим staging по `contract_id`;
- для каждой строки подтянуты `matched_payment_ref`,
  `matched_payment_amount`, `matched_payment_method`,
  `matched_payment_match_source`.

Главные выводы:

- `9` строк `price>0 + direct payment + raw method пустой` подтверждены как
  `Оплата наличными через эммулятор`; это дает правило
  `type_of_payment = наличные` для текущей группы `2 941` строк;
- `НЕДЕЛЯ САЙТ price=0` в проверенных no-payment и fallback-кейсах
  подтверждена как бесплатная неделя; для таких строк `type_of_payment`
  должен быть пустой;
- `НЕДЕЛЯ ФИТНЕСА БЕСПЛАТНО price=0` с fallback-платежом подтверждена как
  бесплатная;
- full-абонементы с `price=0` не нужно автоматически восстанавливать из
  шаблона: проверенные строки включают корпоративных клиентов, ввод начальных
  остатков и модификаторы;
- для full `price=0` с fallback-платежом найден смешанный слой: один пример -
  ложный fallback корпоративного клиента, один пример - реальный платный
  модификатор `Ультра 3 -> Ультра 12`. Нужен дополнительный признак
  модификатора/переоформления.

Подробная сводка дописана в:

```text
docs/new-changes/prolem_2/current_payment_price_state.md
```

## 2026-06-22: внедрение ответов бизнеса по `price/payment_type`

Изменения в коде:

- `scripts/19_build_membership_import_xlsx.py`:
  - direct-платежи `price>0` с пустым raw method маппятся в `наличные`;
  - `Абонемент НЕДЕЛЯ САЙТ` и
    `Абонемент НЕДЕЛЯ ФИТНЕСА БЕСПЛАТНО` при `price=0` и не-direct матче
    вынесены в подтвержденные бесплатные исключения;
  - full `price=0` без найденного платежа вынесены в отдельное
    бизнес-исключение
    `business_full_zero_no_payment_initial_balance_corporate_or_modifier`.

Запуск:

```bash
scripts/31_build_membership_import_outputs.sh
```

Итог validation:

- `client membership rows`: `99 399`;
- `membership template rows`: `114`;
- `duplicate contract_id count`: `0`;
- `contract names missing in template file`: `0`;
- `status`: `PASS`.

Итоговые `payment_type`:

- `безналичные`: `67 249`;
- `наличные`: `2 941`;
- `сбп`: `1 484`;
- blank: `27 725`.

Эффект по проблемным группам:

- `price>0 + direct raw method пустой`: `2 941 -> 0`;
- `price=0 + пустой payment_type + платеж не найден`: `3 919 -> 288`;
- `price=0 + payment_type уже замаплен`: `3 156 -> 1 948`;
- non-business строки с любой проблемой `price/payment_type`: `10 527 -> 2 648`.

Сформирован детальный отчет открытых строк:

```text
output/20251115_0800_fix_owner_new_import/reports/payment_price_residual_after_manual_rules.csv
```

Обновлены:

- `docs/new-changes/prolem_2/current_payment_price_state.md`;
- `docs/new-changes/prolem_2/04_open_problems_to_resolve.md`;
- `docs/new-changes/prolem_2/02_implementation_and_validation.md`.

## 2026-06-22: финальные бизнес-решения по остаткам `price/payment_type`

Внедрены дополнительные правила:

- `288` строк `price=0`, платеж не найден: оставляем `price=0` и пустой
  `type_of_payment`;
- `1 741` строк `price=0` с fallback `payment_type`: очищаем
  `type_of_payment`;
- `207` строк `price=0` с direct-платежом и заполненным `payment_type`:
  старое решение было оставить как есть; после ручных ответов
  `2026-06-23/24` этот слой переведен в открытый контрольный;
- `327` строк `price>0`, платеж не найден: ставим `type_of_payment =
  наличные`;
- `85` строк `price=0`, платеж найден, raw method пустой: оставляем
  `type_of_payment` пустым.

Техническая деталь: `51` строка из группы `85` попала в общее правило
fallback `business_zero_fallback_payment_type_blank`, еще `34` direct-строки
получили отдельное правило `business_zero_raw_blank_payment_type_blank`.

Изменения:

- `scripts/19_build_membership_import_xlsx.py` обновлен новыми правилами;
- `scripts/21_build_payment_price_manual_review_examples.py` теперь строит
  новую выборку `30` кейсов после правил.

Запуск:

```bash
scripts/31_build_membership_import_outputs.sh
python3 scripts/21_build_payment_price_manual_review_examples.py
```

Итог validation:

- `client membership rows`: `99 399`;
- `membership template rows`: `114`;
- `duplicate contract_id count`: `0`;
- `contract names missing in template file`: `0`;
- `status`: `PASS`.

Итоговые `payment_type`:

- `безналичные`: `65 539`;
- `наличные`: `3 268`;
- `сбп`: `1 453`;
- blank: `29 139`.

Проверка финальных правил:

- `business_zero_no_payment_blank_payment_type`: `288`;
- `business_zero_fallback_payment_type_blank`: `1 792`;
- `zero direct payment_type kept`: `207`;
- `positive no payment -> cash`: `327`;
- `business_zero_raw_blank_payment_type_blank`: `34`.

Новые файлы:

- `output/20251115_0800_fix_owner_new_import/payment_price_manual_review_examples_30_after_rules_20260525_0800.xlsx`;
- `output/20251115_0800_fix_owner_new_import/reports/payment_price_final_rule_check.csv`.

## 2026-06-22: корректная репрезентативная выборка 30 строк

Предыдущий файл `payment_price_manual_review_examples_30_after_rules...` был
выборкой для проверки правил `price/payment_type` и содержал колонки
`question_for_manual_check`, `correct_price`, `correct_payment_type`,
`comment`. Для проверки всей финальной выгрузки это неверный формат.

Создан новый воспроизводимый скрипт:

```text
scripts/22_build_membership_representative_examples.py
```

Запуск:

```bash
python3 scripts/22_build_membership_representative_examples.py
```

Новый XLSX:

```text
output/20251115_0800_fix_owner_new_import/membership_import_representative_30_examples_20260525_0800.xlsx
```

Проверка:

- `30` data rows;
- `20` колонок;
- колонки ровно как в основном
  `fitbase_import_abonementy_clientov_20260525_0800.xlsx`;
- нет `question_for_manual_check`, `correct_price`,
  `correct_payment_type`, `comment`;
- сохранены английская и русская строки заголовков из основного XLSX.

Описание состава выборки:

```text
docs/new-changes/prolem_2/representative_30_examples_20260525_0800.md
```

Покрытие:

- массовые full-абонементы `УЛЬТРА` и `МУЛЬТИКАРТА`;
- `безналичные`, `наличные`, `сбп`, blank;
- direct/fallback/no-payment;
- partial paid, рассрочка, owner-change;
- основные zero-price бизнес-правила;
- subrent unlimited/active limited/expired limited;
- солярий и короткий платный trial/guest.

## 2026-06-23: разобраны ручные ответы по representative 30

Входной файл с комментариями:

```text
output/20251115_0800_fix_owner_new_import/membership_import_representative_30_examples_20260525_0800-with-answers.xlsx
```

Зафиксирован подробный разбор:

```text
docs/new-changes/prolem_2/07_representative_30_manual_answers_followup.md
```

Что подтверждено:

- `00000130311` после нового owner-change правила находится у
  `Сергеева Ирина Борисовна`;
- `00000100483` после нового owner-change правила находится у
  `Коновалов Никита Витальевич`;
- `00000130469` уже корректно находился у `Борщевская Анастасия Кирилловна`
  через обычную `Смена владельца`;
- direct-платежи с пустым raw method и `price>0` подтверждают правило
  `type_of_payment=наличные`;
- бесплатные/пробные/корпоративные zero-price строки в ручных примерах в
  основном подтверждены.

Новые остаточные группы из ручных комментариев:

- `327` строк `D_positive_no_payment_cash_327`: ручной пример
  `00000145048` оказался лишней/неудаленной продажей, при этом в группе
  `200` строк активны по cutoff и `67` строк находятся в пересечениях, где у
  клиента больше одного активного full-абонемента;
- `207` строк `C_zero_direct_payment_type_kept_207`: ручные примеры показали
  возврат/блокировку (`00000041901`) и бесплатную неделю
  (`00000070045`), поэтому слой нельзя считать полностью закрытым;
- `21` рассрочка требует точечной проверки бизнес-смысла `payment_left` и
  `type_of_payment`;
- по техническим raw method остается конфликт между прежним массовым решением
  `-> безналичные` и одним ручным комментарием про наличные через эмулятор;
- `Розничный клиент` / возвраты через эмулятор: `47` исторических строк,
  активных по cutoff нет;
- по субаренде `visits_left` новых проблем нет, но есть один точечный конфликт
  по `type_of_payment` (`00000149696`: вручную указаны наличные, текущая
  строка `безналичные`).

## 2026-06-23: расследован кейс Поповой `00000145048`

Задача: понять, по каким признакам менеджер определила
`00000145048` как лишнюю/неудаленную продажу.

Созданы probe SQL:

```text
sql/60_popova_00000145048_extra_sale_probe.sql
sql/61_popova_00000145048_access_and_scale_probe.sql
```

Логи:

```text
logs/new-changes/prolem_2/60_popova_00000145048_extra_sale_probe.clean.txt
logs/new-changes/prolem_2/61_popova_00000145048_access_and_scale_probe.clean.txt
```

Подробный отчет:

```text
docs/new-changes/prolem_2/08_popova_00000145048_extra_sale.md
```

Ключевые факты:

- в backup `00000145048` еще проведен и не помечен на удаление:
  `_Document163._Posted = 0x01`, `_Marked = 0x00`;
- статус `00000145048` в `InfoRg3060`: `Контакт с клиентом`;
- прямого платежа `Document152` по `00000145048` нет;
- posted платежей Поповой вокруг `2026-01-05` не найдено;
- посещений по `00000145048`: `0`;
- у Поповой есть другое активное членство `00000139985`:
  `2025-09-04` - `2026-10-04`, платеж `13990`, статус `Успех`,
  `21` посещение;
- оба членства используют карту `115000239319`;
- финальная воронка выбрала `00000145048`, потому что ранжирование активных
  full-абонементов идет по `end_date DESC`; при этом был выставлен warning
  `multiple_active_subscriptions;`.

Масштаб похожего риска в текущей группе `D_positive_no_payment_cash_327`:

- всего строк: `327`;
- активны по cutoff: `200`;
- full_subscription: `309`;
- имеют другой active full у того же клиента: `97`;
- одновременно активны и имеют другой active full: `67`;
- статусы группы: blank `253`, `Отказ` `32`, `Контакт с клиентом` `22`,
  `Успех` `16`, `Бронь абонемента` `4`.

Предварительный безопасный следующий шаг: собрать ручную проверку по `67`
активным no-payment full строкам, где у клиента есть другой active full, с
добавленными признаками платежей, посещений, статуса, карты и overlap.

## 2026-06-24: полная база по паттерну `активный сейчас + Контакт с клиентом`

Дополнены SQL-проверки:

```text
sql/62_popova_similar_contact_next_cases.sql
sql/63_contact_next_current_active_examples.sql
```

Логи:

```text
logs/new-changes/prolem_2/62_popova_similar_contact_next_cases.clean.txt
logs/new-changes/prolem_2/63_contact_next_current_active_examples.clean.txt
```

Документ обновлен:

```text
docs/new-changes/prolem_2/08_popova_00000145048_extra_sale.md
```

Основные результаты по `fitbase_part2.membership_import_facts`:

- full-абонементов в staging: статусы blank `51 780`, `Успех` `16 474`,
  `Отказ` `15 099`, `Контакт с клиентом` `2 277`,
  `Бронь абонемента` `379`;
- active full на cutoff: blank `10 674`, `Успех` `392`,
  `Контакт с клиентом` `297`, `Бронь абонемента` `115`,
  `Отказ` `53`;
- later/full строки у клиентов, где уже есть другой active full на cutoff:
  blank `530`, `Бронь абонемента` `5`, `Контакт с клиентом` `4`,
  `Успех` `4`, `Отказ` `2`;
- строгих кейсов `есть активный full сейчас + следующий/later full в статусе
  Контакт с клиентом`: `4` строки / `4` клиента;
- из этих `4`: `2` без платежа, `2` без платежа и без посещений;
- по более широкому критерию `Контакт с клиентом` + другое full-членство
  покрывает дату старта: `20` строк / `20` клиентов;
- самый сильный поповский паттерн
  `Контакт с клиентом + нет платежа + нет посещений + другое full-членство
  имеет платеж или посещения`: `1` строка, сама Попова `00000145048`.

## 2026-06-24: strict-исключение active/later `Контакт с клиентом`

В основной пайплайн абонементов добавлено правило:

- если у клиента есть full-абонемент, активный на cutoff `2026-05-25 08:00`;
- и есть следующий/later full-абонемент этого же клиента в статусе
  `Контакт с клиентом`;
- later-строка исключается из клиентского XLSX абонементов.

Изменен файл:

```text
scripts/19_build_membership_import_xlsx.py
```

Новый audit-файл:

```text
output/20251115_0800_fix_owner_new_import/staging/membership_import_excluded_rows.csv
```

Исключено `4` строки:

| contract_id | клиент |
|---|---|
| `00000145048` | Попова Ирина Борисовна |
| `00000142081` | Казанчук Владимир Николаевич |
| `00000138047` | Артамонова Анна Юрьевна |
| `00000137201` | Рахова Анастасия Леонидовна |

Пересборка:

```bash
MEMBERSHIP_SOURCE_OUTPUT_ROOT='output/20251115_0800_fix_owner' \
MEMBERSHIP_OUTPUT_ROOT='output/20251115_0800_fix_owner_new_import' \
MEMBERSHIP_DATE_STAMP='20260525_0800' \
python3 scripts/19_build_membership_import_xlsx.py \
  --source-output-dir output/20251115_0800_fix_owner \
  --output-dir output/20251115_0800_fix_owner_new_import \
  --date-stamp 20260525_0800

python3 scripts/20_validate_membership_import_xlsx.py \
  --source-output-dir output/20251115_0800_fix_owner \
  --output-dir output/20251115_0800_fix_owner_new_import \
  --date-stamp 20260525_0800
```

Итог validation:

- `client membership rows`: `99 383`;
- `membership template rows`: `114`;
- `duplicate contract_id count`: `0`;
- `contract names missing in template file`: `0`;
- `exclude_active_later_contact_full`: `4`;
- payment types: blank `29 139`, `наличные` `3 266`,
  `безналичные` `65 526`, `сбп` `1 452`;
- independent XLSX recheck: `PASS`.

Дополнительная проверка финального XLSX подтвердила, что `contract_id`
`00000145048`, `00000142081`, `00000138047`, `00000137201` больше не
присутствуют в `fitbase_import_abonementy_clientov_20260525_0800.xlsx`.

Обновлены документы:

- `docs/new-changes/prolem_2/07_representative_30_manual_answers_followup.md`;
- `docs/new-changes/prolem_2/08_popova_00000145048_extra_sale.md`.

## 2026-06-24: deep-dive по оставшимся no-payment cash active-overlap

После strict-исключения проверен остаток `price>0`, платеж не найден,
`type_of_payment=наличные`, где у клиента в текущем финальном XLSX есть другое
active/not-finished full-членство.

Добавлен SQL для подсчета посещений по абонементам:

```text
sql/64_membership_visit_counts_by_subscription.sql
sql/65_no_payment_cash_active_overlap_probe.sql
```

Запуск:

```bash
SQLCMD_SERVER='mssql-fitness-2022,1433' \
scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/64_membership_visit_counts_by_subscription.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/64_membership_visit_counts_by_subscription.txt

SQLCMD_SERVER='mssql-fitness-2022,1433' \
scripts/macos_backup_sqlcmd.sh \
  -d FitnessRestored_20260523_macos \
  -i /sql/65_no_payment_cash_active_overlap_probe.sql \
  -W -s '|' \
  -o /logs/new-changes/prolem_2/65_no_payment_cash_active_overlap_probe.txt
```

Новые audit-отчеты:

```text
output/20251115_0800_fix_owner_new_import/reports/no_payment_cash_active_full_overlap_current_final.csv
output/20251115_0800_fix_owner_new_import/reports/no_payment_cash_active_full_overlap_deep_audit.csv
```

Скрипты пересборки audit/review:

```bash
python3 scripts/26_build_no_payment_cash_active_overlap_audit.py
python3 scripts/25_build_no_payment_cash_active_overlap_review.py
```

Review XLSX для бизнеса:

```text
output/20251115_0800_fix_owner_new_import/no_payment_cash_active_full_overlap_review_20260525_0800.xlsx
```

Подробный документ:

```text
docs/new-changes/prolem_2/09_no_payment_cash_active_overlap_deep_dive.md
```

Итоги:

- в текущем финальном XLSX осталось `325` no-payment cash строк;
- из них `63` строки / `46` клиентов имеют другое active/not-finished
  full-членство в текущем финальном XLSX;
- прямых строк из этих `63` в ручном representative-файле больше нет:
  Попова уже удалена strict-правилом;
- `52` строки без посещений по спорному абонементу;
- `11` строк имеют посещения по спорному абонементу, автоматически удалять
  нельзя;
- posted платежей клиента в `sale_datetime +/- 14 дней` не найдено ни по одной
  из `63` строк;
- у всех `63` есть связанный документ продажи `Document154`, но это
  подтверждает только заведенную продажу, не оплату;
- все `63` строки относятся к `Действующие клиенты`;
- `23` спорные строки выбраны в `final_funnel_clients` как
  `selected_subscription`;
- у `32` строк best-other членство выбрано как `selected_subscription`;
- `4` строки со статусом `Отказ`/`Бронь абонемента` без платежа и без
  посещений - самый безопасный следующий кандидат на правило, но для
  воспроизводимого удаления нужно добавить `visit_docs` в staging;
- `21` строка started/no-payment/no-visits/other-basis - главный слой для
  ручной бизнес-проверки;
- `7` строк выглядят как дубли с одинаковыми датами и требуют отдельной
  политики дедупликации;
- основной XLSX на этом шаге не пересобирался: нового правила с такой же
  доказательной силой, как strict-паттерн Поповой, пока нет.

## 2026-06-24 - диагностический XLSX на 7 примеров для проблем 08-09

Создан воспроизводимый builder:

```bash
python3 scripts/27_build_no_payment_cash_active_overlap_7_examples.py
```

Выходной файл:

```text
output/20251115_0800_fix_owner_new_import/no_payment_cash_active_full_overlap_7_examples_20260525_0800.xlsx
```

Проверка:

- один лист `Импорт_абонементы`;
- `7` строк данных;
- `20` колонок, заголовки полностью совпадают с основным
  `fitbase_import_abonementy_clientov_20260525_0800.xlsx`;
- дополнительных колонок и вкладок нет;
- выбранные contract_id:
  `00000149776`, `00000150179`, `00000134419`, `00000143904`,
  `00000150540`, `00000149797`, `00000142446`.

Что покрывают примеры:

- сильный `Бронь`/`Отказ` без платежа и посещений при наличии другого basis;
- слабый `Отказ`, где одного статуса может быть недостаточно;
- started/no-payment/no-visits со статусом `Успех`;
- blank status, где best-other выбран воронкой и имеет платеж/посещения;
- будущий старт после cutoff;
- дубль одинаковых дат с разным названием;
- контрольный keep-кейс: `Отказ`, но по спорной строке есть посещения.

Основной XLSX на этом шаге не пересобирался. Тестовый файл сделан в том же
формате, что основной импорт абонементов; после бизнес-проверки этих строк
можно будет добавить подтвержденные правила.

## 2026-06-24: deep-dive по `price=0` + direct payment + заполненный `type_of_payment`

Разобран слой `C_zero_direct_payment_type_kept_207`, который раньше был
оставлен как direct-платежный. Ручные ответы показали, что это не единый
безопасный слой: среди примеров есть бесплатная неделя и
возврат/блокировка.

Добавлены SQL/probe:

```text
sql/66_zero_price_direct_payment_probe.sql
sql/67_godareva_zero_direct_context.sql
sql/68_zero_direct_active_full_scale.sql
sql/69_zero_direct_trial_week_scale.sql
sql/70_zero_direct_refund_block_wide_probe.sql
```

Логи:

```text
logs/new-changes/prolem_2/66_zero_price_direct_payment_probe.txt
logs/new-changes/prolem_2/67_godareva_zero_direct_context.txt
logs/new-changes/prolem_2/68_zero_direct_active_full_scale.txt
logs/new-changes/prolem_2/69_zero_direct_trial_week_scale.txt
logs/new-changes/prolem_2/70_zero_direct_refund_block_wide_probe.txt
```

Audit CSV:

```text
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_payment_type_kept_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_payment_type_kept_summary.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_active_full_44_detail.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_summary.csv
```

Builder:

```bash
python3 scripts/28_build_zero_price_direct_payment_audit.py
python3 scripts/29_build_zero_direct_active_full_detail_report.py
python3 scripts/30_build_zero_direct_refund_link_report.py
```

Документ:

```text
docs/new-changes/prolem_2/10_zero_price_direct_payment_deep_dive.md
```

Итоговое разложение `207` строк:

| группа | rows | active | вывод |
|---|---:|---:|---|
| `full_active_zero_direct` | `44` | `44` | главный active-risk слой; у всех есть positive sale-line/direct payment, у `43` есть посещения и `43` выбраны в `final_funnel_clients` |
| `full_finished_normal_dates_zero_direct` | `152` | `0` | исторический full-слой с нормальными датами; `136` строк имеют связанный `Document131` возврата |
| `full_service_dates_2001` | `1` | `0` | ручной пример Годаревой `00000041901`: `start=end=2001-01-01` плюс связанный `Document131` возврата |
| `trial_week_direct_zero` | `7` | `0` | недельные/короткие trial-строки, direct-платеж не всегда должен задавать `type_of_payment` |
| `unknown_review_required` | `3` | `0` | исторические non-full/non-trial строки |

Что подтверждено по ручным примерам:

- `00000070045` / `Абонемент НЕДЕЛЯ САЙТ`: в 1С цена в регистре и строка
  продажи равны `0`, поэтому менеджерский комментарий `Бесплатная неделя`
  подтверждается данными. Direct-платеж `25` рядом не должен автоматически
  задавать `type_of_payment`.
- `00000041901` / Годарева: payment operation в `Document152` не возвратная,
  там `Оплата от клиента`. Реальный источник возврата найден отдельно:
  `_Document131` (`Документ.ВозвратОтПокупателя`) номер `00000000016`,
  posted/unmarked, `2019-03-12 10:45:22`, ссылка на sale doc через
  `_Fld547_RRRef`, сумма возврата `5000`, сумма продажи `7499`.
  Для “блокировки” отдельный документ членства не найден; machine-признак
  ручного кейса: full `price=0`, direct payment, `start=end=2001-01-01`,
  historical, связанный `Document131`.

Refund-link summary по исходным `207` строкам до safe-правок:

- `141` строка имеет связанный `Document131` возврата;
- все `141` имеют posted/unmarked refund-документ;
- активных строк с `Document131` возврата: `0`;
- все `44` active full-строки не имеют связанного refund-документа.

Главный active-вывод: `44` активные full-строки нельзя чистить по логике
бесплатной недели или возврата. Они похожи на реальные активные членства, где
`rg_price=0`, но `Document154` и `Document152` содержат положительную
сумму/оплату. Для них нужен отдельный бизнес-ответ: восстанавливать ли `price`
из `Document154 sale_line_sum` и оплату из фактических direct-платежей.

Построчный active-report проверен:

- строк данных: `44`;
- `visit_docs > 0`: `43`;
- `sale_line_sum > 0`: `44`;
- `matched_payment_amount > 0`: `44`;
- `is_selected_subscription = 1`: `43`.

Основной XLSX на этом шаге не пересобирался.

## 2026-06-24: добивка `trial_week_direct_zero` внутри zero-direct

Задача: проверить, на каких данных 1С основан комментарий менеджера
`Бесплатная неделя` и почему direct-платеж не должен задавать
`type_of_payment` для `Абонемент НЕДЕЛЯ САЙТ`.

SQL:

```text
sql/71_zero_direct_trial_sale_context.sql
```

Лог:

```text
logs/new-changes/prolem_2/71_zero_direct_trial_sale_context.txt
```

CSV:

```text
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_summary.csv
```

## 2026-06-24: разбор остаточных блоков из representative-30 кроме 08-10

Проверены текущие строки
`output/20251115_0800_fix_owner_new_import/staging/membership_import_rows.csv`
после последней пересборки membership XLSX.

Выводы зафиксированы в:

```text
docs/new-changes/prolem_2/07_representative_30_manual_answers_followup.md
docs/new-changes/prolem_2/04_open_problems_to_resolve.md
```

Кратко:

- named-рассрочки: `21` строка, все активны на cutoff; технически источник
  оплаты найден у всех, но `18` строк с положительным `payment_left` остаются
  на бизнес-контроле;
- широкий слой `payment_left > 0`: `1 089` строк, из них `315` активны на
  cutoff и `1 071` строк не имеют слова `рассрочка` в названии;
- технические raw method: закрыты бизнес-решением как `безналичные`;
- `Розничный клиент`: `47` строк, активных `0`; `35` строк надежно выделяются
  как historical refund через linked posted/unmarked `Document131`;
- субаренда: `visits_left` закрыт; общая проблема не подтверждена, есть только
  один ручной конфликт по `type_of_payment`.

## 2026-06-24: закрыты technical raw/subrent type и создан review XLSX для `payment_left`/retail

Приняты решения:

- technical raw method `Для ошибок...` и
  `БАР ИП Иконников Андрей Анатольевич` оставляем в массовом правиле
  `type_of_payment=безналичные`;
- по субаренде спорный ручной комментарий не распространяем массово:
  активные строки остаются в текущей логике `безналичные`, основной активный
  контроль по субаренде - корректный `visits_left`.

Кодовая логика уже соответствовала этим решениям:

- `scripts/19_build_membership_import_xlsx.py::map_payment_type()` маппит
  `для ошибок` и `бар ип иконников андрей анатольевич` в `безналичные`;
- активная ограниченная субаренда получает `visits_left` из регистра
  `_AccumRg3336`, а `type_of_payment` идет через общий маппинг платежа.

Пересборка:

```bash
MEMBERSHIP_SOURCE_OUTPUT_ROOT='output/20251115_0800_fix_owner' \
MEMBERSHIP_OUTPUT_ROOT='output/20251115_0800_fix_owner_new_import' \
MEMBERSHIP_DATABASE_NAME='FitnessRestored_20260523_macos' \
MEMBERSHIP_SQLCMD_SERVER='mssql-fitness-2022,1433' \
MEMBERSHIP_DATE_STAMP='20260525_0800' \
scripts/31_build_membership_import_outputs.sh
```

Результат:

- основной XLSX: `99 383` строки;
- шаблоны: `114` строк;
- duplicate `contract_id`: `0`;
- missing template names: `0`;
- recheck status: `PASS`;
- payment types: blank `29 285`, `наличные` `3 266`,
  `безналичные` `65 383`, `сбп` `1 449`.

Контроль closed-блоков после пересборки:

| блок | rows | active | проверка |
|---|---:|---:|---|
| `Для ошибок, атол 30Ф,Кульманова А.В. ИП` | `2 354` | `833` | `price>0 + blank type = 0` |
| `Для ошибок, Кульманова А.В. ИП` | `870` | `0` | `price>0 + blank type = 0` |
| `БАР ИП Иконников Андрей Анатольевич` | `44` | `5` | `price>0 + blank type = 0` |
| субаренда | `1 707` | `33` | `price>0 + blank type = 0`, active `price>0 + blank type = 0` |

Создан review XLSX на `7` строк по оставшимся темам `payment_left > 0` и
`Розничный клиент`:

```text
output/20251115_0800_fix_owner_new_import/payment_left_retail_review_7_examples_20260525_0800.xlsx
```

Формат: один лист `Импорт_абонементы`, те же `20` колонок, что в основном
клиентском XLSX, `7` строк данных, без технических колонок и дополнительных
листов.

Скрипт:

```text
scripts/35_build_payment_left_retail_review_7_examples.py
```

## 2026-06-24: XLSX на 7 zero-direct примеров для разметки

Создан файл:

```text
output/20251115_0800_fix_owner_new_import/zero_price_direct_review_7_examples_20260525_0800.xlsx
```

Скрипт:

```bash
python3 scripts/34_build_zero_direct_review_7_examples.py
```

Формат файла: один лист `Импорт_абонементы`, ровно `20` колонок основного
импорта абонементов, без дополнительных листов и без служебных полей.

Выборка:

| contract_id | покрытие |
|---|---|
| `00000138477` | open active full, типичный lost-price candidate |
| `00000135375` | open active full со статусом `Контакт с клиентом` |
| `00000114583` | open historical full без linked `Document131` refund |
| `00000115678` | open `Неделя Фитнес`/`Доплата` |
| `00000071040` | control closed `НЕДЕЛЯ САЙТ` sale-line-zero rule |
| `00000125150` | control closed full `Document131` refund rule |
| `00000132241` | control closed short membership `Document131` refund rule |

Все `7` строк не входят в прошлую representative-30 выборку.

Пересборка:

```bash
python3 scripts/33_build_zero_direct_trial_sale_context_report.py
```

Результат:

| вывод | rows |
|---|---:|
| `free_site_week_confirmed_by_1c_sale_line` | `4` |
| `target_week_line_zero_but_payment_is_on_doplata` | `2` |
| `not_free_week_target_line_positive_document131_refund_exists` | `1` |

Главный вывод: для всех `4` текущих direct-строк
`Абонемент НЕДЕЛЯ САЙТ` целевая строка абонемента в `Document154_VT1137`
равна `0`. Найденный payment связан с тем же sale doc, но относится к другой
строке (`Перчатки`, годовой абонемент или подарок). Поэтому менеджерский
комментарий по бесплатной неделе подтвержден данными 1С: `type_of_payment` для
таких строк нужно очищать после принятия правила.

`Абонемент Неделя Фитнес`: `2` строки имеют нулевую целевую строку абонемента,
а payment относится к строке `Доплата`. Это похожий технический механизм, но
не подтвержден тем же бизнес-комментарием, поэтому оставлен отдельным открытым
вопросом.

## 2026-06-24: внедрены safe-правила zero-direct и пересобран XLSX

В основной пайплайн добавлены признаки:

- `membership_sale_line_amount`;
- `membership_sale_line_count`;
- `document131_refund_count`;
- `document131_posted_unmarked_refund_count`.

Изменены:

```text
sql/31_build_membership_import_staging.sql
scripts/31_build_membership_import_outputs.sh
scripts/19_build_membership_import_xlsx.py
scripts/30_build_zero_direct_refund_link_report.py
scripts/33_build_zero_direct_trial_sale_context_report.py
```

Внедренные правила:

```text
business_direct_free_site_week_sale_line_zero_blank_payment:
price=0 + direct payment + Абонемент НЕДЕЛЯ САЙТ + membership_sale_line_amount=0
=> type_of_payment=''

business_historical_document131_refund_zero_direct_blank_payment:
price=0 + direct payment + not active + posted/unmarked Document131 refund linked to Document154 sale doc
=> type_of_payment=''
```

Команда пересборки:

```bash
MEMBERSHIP_SOURCE_OUTPUT_ROOT='output/20251115_0800_fix_owner' \
MEMBERSHIP_OUTPUT_ROOT='output/20251115_0800_fix_owner_new_import' \
MEMBERSHIP_DATABASE_NAME='FitnessRestored_20260523_macos' \
MEMBERSHIP_SQLCMD_SERVER='mssql-fitness-2022,1433' \
MEMBERSHIP_DATE_STAMP='20260525_0800' \
scripts/31_build_membership_import_outputs.sh
```

Результат валидации:

- клиентский XLSX: `99 383` строки;
- шаблоны: `114` строк;
- duplicate `contract_id`: `0`;
- missing template names: `0`;
- validation status: `PASS`;
- payment types: blank `29 285`, наличные `3 266`, безналичные `65 383`,
  сбп `1 449`.

Новые zero-direct счетчики:

| показатель | rows |
|---|---:|
| исходный слой `price=0 + direct + type_of_payment заполнен` | `207` |
| применено `НЕДЕЛЯ САЙТ` sale-line-zero override | `4` |
| применено historical `Document131` refund override всего | `176` |
| из `Document131` override раньше имели заполненный raw method/type | `142` |
| из `Document131` override уже были raw blank/type blank | `34` |
| текущий остаток `price=0 + direct + type_of_payment заполнен` | `61` |

Текущий остаток `61`:

- `44` active full-строки: не похожи на refund/free, требуется решение по
  восстановлению `price`;
- `15` historical full-строк без linked `Document131` refund;
- `2` `Абонемент Неделя Фитнес`, где целевая строка абонемента `0`, а payment
  относится к строке `Доплата`.

Точечные проверки после пересборки:

- `00000041901` Годарева: `type_of_payment` пустой,
  `_business_override=business_historical_document131_refund_zero_direct_blank_payment`;
- `00000070045`, `00000070915`, `00000071040`, `00000072190`
  `Абонемент НЕДЕЛЯ САЙТ`: `type_of_payment` пустой,
  `_business_override=business_direct_free_site_week_sale_line_zero_blank_payment`;
- `00000115678`, `00000117756` `Абонемент Неделя Фитнес` остаются в остатке с
  `type_of_payment=безналичные`;
- `00000132241` `Абонемент 2 недели Фитнес`: очищен по `Document131` refund.

Обновленные отчеты:

```text
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_payment_type_kept_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_payment_type_kept_summary.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_summary.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_applied_overrides.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_applied_overrides_summary.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_summary.csv
```

## 2026-06-24: разбор ответов бизнеса по трем файлам на 7 примеров

Получены копии с ответами бизнеса:

```text
output/20251115_0800_fix_owner_new_import/no_payment_cash_active_full_overlap_7_examples_20260525_0800 — копия.xlsx
output/20251115_0800_fix_owner_new_import/zero_price_direct_review_7_examples_20260525_0800 — копия.xlsx
output/20251115_0800_fix_owner_new_import/payment_left_retail_review_7_examples_20260525_0800 — копия.xlsx
```

Создан общий подробный разбор:

```text
docs/new-changes/prolem_2/11_manual_answers_7_examples_analysis.md
```

Обновлены старые документы, чтобы не осталось устаревших выводов:

```text
docs/new-changes/prolem_2/07_representative_30_manual_answers_followup.md
docs/new-changes/prolem_2/09_no_payment_cash_active_overlap_deep_dive.md
docs/new-changes/prolem_2/10_zero_price_direct_payment_deep_dive.md
```

Дополнительные SQL-проверки:

```text
sql/72_no_payment_manual_answers_probe.sql
logs/new-changes/prolem_2/72_no_payment_manual_answers_probe.clean.txt

sql/73_zero_direct_payment_sum_probe.sql
logs/new-changes/prolem_2/73_zero_direct_payment_sum_probe.clean.txt
```

Главные выводы:

- no-payment active overlap оказался смешанным: из `7` примеров `4` лишние
  продажи, `3` нужно переносить/у них есть оплата; массовое исключение по
  `Отказ`/`Бронь`, future-start или visits не внедрять;
- `00000142446` показал, что `visit_docs > 0` не является абсолютным
  keep-фактором: бизнес все равно пометил строку как лишнюю продажу;
- zero-direct full без `Document131` refund нужно восстанавливать как
  оплатные строки; `НЕДЕЛЯ САЙТ` и `Document131` правила подтверждены;
- `Абонемент Неделя Фитнес` с `Доплата` считать бесплатной недельной строкой:
  `price=0`, `type_of_payment` пустой;
- named-рассрочки с `payment_left` подтверждены как корректные;
- non-named `payment_left` может быть ложным долгом из-за вспомогательной
  продажи/эмулятора;
- `Розничный клиент` бизнес сказал не выгружать целиком.
