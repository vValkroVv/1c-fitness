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
  оставляем как есть;
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
