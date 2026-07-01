# `price=0` + direct payment + заполненный `type_of_payment`

Срез: `2026-05-25 08:00`.

Проблема из ручных ответов:

- возврат/блокировка, где строка не является обычной оплаченной продажей;
- бесплатная неделя, где `price=0` правильный, а найденный direct-платеж не
  должен автоматически задавать `type_of_payment`.

Связанный ручной файл:

```text
output/20251115_0800_fix_owner_new_import/membership_import_representative_30_examples_20260525_0800-with-answers.xlsx
```

## Короткий вывод

Update `2026-06-24`: получены ответы бизнеса по файлу:

```text
output/20251115_0800_fix_owner_new_import/zero_price_direct_review_7_examples_20260525_0800 — копия.xlsx
```

Подробный разбор:

```text
docs/new-changes/prolem_2/11_manual_answers_7_examples_analysis.md
```

Новые ответы закрывают смысл остатка `61`:

- active full zero-direct без `Document131` refund - реальные оплатные строки,
  где оплата/цена ломаются из-за структуры подчиненности 1С
  (`Продажа -> Членство -> Изменение условий/Заморозки/Договор -> Оплата`);
- historical full zero-direct без `Document131` refund тоже может быть
  реальной оплатной строкой, не refund/free;
- `Абонемент Неделя Фитнес` с отдельной строкой `Доплата` - бесплатная
  недельная строка: `price=0`, `type_of_payment` нужно очищать;
- текущие правила по `НЕДЕЛЯ САЙТ` и `Document131` refund подтверждены, откат
  не нужен.

Важный технический нюанс перед внедрением: нельзя брать один
`matched_payment_amount` как полную оплату. SQL-проверка
`sql/73_zero_direct_payment_sum_probe.sql` показала, что в full zero-direct
без `Document131` refund одиночный matched-платеж отличается от строки продажи
в `24` строках, а сумма direct-платежей отличается от строки продажи в `13`
строках. Поэтому price нужно восстанавливать из `membership_sale_line_amount`,
а paid считать по сумме связанных платежей с отдельной политикой для
частичных оплат/переплат.

Исходный слой `price=0 + direct payment + type_of_payment оставлен` состоял из
`207` строк. После deep-dive два подтвержденных правила внедрены в основной
пайплайн и XLSX пересобран:

- `business_direct_free_site_week_sale_line_zero_blank_payment`: `4` строки
  `Абонемент НЕДЕЛЯ САЙТ`;
- `business_historical_document131_refund_zero_direct_blank_payment`: `176`
  historical direct-refund строк. Из них `142` раньше держали заполненный
  `type_of_payment`, еще `34` уже были blank из-за пустого raw method, но теперь
  получили правильную причину.

Текущий остаток `price=0 + direct payment + type_of_payment оставлен` после
пересборки: `61` строка.

| группа | rows | active | вывод |
|---|---:|---:|---|
| `full_active_zero_direct` | `44` | `44` | главный active-risk слой; это не похоже на возврат/блокировку или бесплатный trial |
| `full_finished_normal_dates_zero_direct` | `15` | `0` | historical full без связанного `Document131`; нужно отдельное решение по цене/служебности |
| `trial_week_direct_zero` | `2` | `0` | `Абонемент Неделя Фитнес`: целевая строка абонемента `0`, payment на строке `Доплата`; после ответа бизнеса очищать как бесплатную недельную строку |

Исходное разложение до внедрения правил:

| группа | rows | active | вывод |
|---|---:|---:|---|
| `full_active_zero_direct` | `44` | `44` | самый важный активный слой: это не похоже на возврат/блокировку; у всех есть positive sale-line и direct-платеж, у `43` есть посещения, `43` выбраны в `final_funnel_clients` |
| `full_finished_normal_dates_zero_direct` | `152` | `0` | исторический full-слой с нормальными датами; `136` строк имеют связанный `Document131` возврата |
| `full_service_dates_2001` | `1` | `0` | ручной пример Годаревой: `start=end=2001-01-01` плюс связанный `Document131` возврата |
| `trial_week_direct_zero` | `7` | `0` | недельные/короткие trial-строки; direct-платеж не всегда должен задавать `type_of_payment` |
| `unknown_review_required` | `3` | `0` | не full/trial; исторические строки, отдельно от активных membership |

Главный practical вывод:

1. Для активных `44` full-строк нельзя применять логику “бесплатно/возврат”.
   По данным 1С они выглядят как реальные активные оплаченные членства, у
   которых `rg_price=0` в регистре, но `Document154` и `Document152` содержат
   оплату/сумму. Ни одна из этих `44` строк не имеет связанного `Document131`
   возврата.
2. Для `НЕДЕЛЯ САЙТ` ручной пример подтверждается не только по одной строке:
   все `4` текущие direct-строки имеют нулевую целевую абонементную строку
   `Document154_VT1137`, а найденный payment относится к другой строке того же
   документа продажи (`Перчатки`, годовой абонемент или подарок). Поэтому
   правило внедрено: direct-платеж больше не задает `type_of_payment` самой
   бесплатной неделе.
3. Для возврата найден прямой источник в 1С: `Document131`
   (`Документ.ВозвратОтПокупателя`) ссылается на `Document154` продажи через
   поле `_Fld547_RRRef`. У Годаревой это refund-doc `00000000016`.
4. Для слова “блокировка” отдельный документ членства не найден. По ручному
   примеру машинный признак блокировочной/служебной строки: `start=end=2001-01-01`
   на full-членстве, `rg_price=0`, строка историческая, плюс связанный возврат.

## Артефакты проверки

SQL:

```text
sql/66_zero_price_direct_payment_probe.sql
sql/67_godareva_zero_direct_context.sql
sql/68_zero_direct_active_full_scale.sql
sql/69_zero_direct_trial_week_scale.sql
sql/70_zero_direct_refund_block_wide_probe.sql
sql/71_zero_direct_trial_sale_context.sql
```

Логи:

```text
logs/new-changes/prolem_2/66_zero_price_direct_payment_probe.txt
logs/new-changes/prolem_2/67_godareva_zero_direct_context.txt
logs/new-changes/prolem_2/68_zero_direct_active_full_scale.txt
logs/new-changes/prolem_2/69_zero_direct_trial_week_scale.txt
logs/new-changes/prolem_2/70_zero_direct_refund_block_wide_probe.txt
logs/new-changes/prolem_2/71_zero_direct_trial_sale_context.txt
```

CSV-аудит:

```text
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_payment_type_kept_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_payment_type_kept_summary.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_active_full_44_detail.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_summary.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_applied_overrides.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_applied_overrides_summary.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_audit.csv
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_summary.csv
```

Пересборка CSV-аудита:

```bash
python3 scripts/28_build_zero_price_direct_payment_audit.py
python3 scripts/29_build_zero_direct_active_full_detail_report.py
python3 scripts/30_build_zero_direct_refund_link_report.py
python3 scripts/33_build_zero_direct_trial_sale_context_report.py
```

## Почему старая логика дала проблему

До правки в `scripts/19_build_membership_import_xlsx.py` было так:

- `compute_money()` при `rg_price <= 0` всегда ставит
  `price=0`, `amount_of_payments=0`, `payment_left=0`;
- `business_zero_override_reason()` очищает `type_of_payment` для части
  `price=0` кейсов, но не для direct-платежей с заполненным raw method;
- затем `map_payment_type(matched_payment_method)` оставляет
  `безналичные`/`сбп` для direct-платежа.

Итог: если в 1С у абонемента цена `0`, но рядом есть direct `Document152`, в
нашем XLSX получается `price=0`, `paid=0`, но `type_of_payment=безналичные/сбп`.

Ручные ответы показали, что direct-платеж при `price=0` не всегда доказывает
обычную оплату членства.

## Ручной пример 1: `00000070045`, бесплатная неделя

Комментарий бизнеса:

```text
Бесплатная неделя
Цена "0"
```

Что видно в 1С:

| поле | значение |
|---|---|
| contract_id | `00000070045` |
| client_id | `000000237` |
| клиент | Акимова Александра Борисовна |
| название | `Абонемент НЕДЕЛЯ САЙТ` |
| product_class | `trial_or_guest` |
| sale_datetime | `2020-07-17 18:21:22` |
| start/end | `2020-07-17` - `2020-07-24` |
| duration_days | `8` |
| status | `Успех` |
| `InfoRg3060.rg_price` | `0` |
| `InfoRg3060.rg_paid_candidate` | `0` |
| `Document154_VT1137._Fld1140/_Fld1154/_Fld1160` | `0` |
| direct payment | `Document152 00000014187`, `25`, `Эквайринг, Карельский1` |
| visits | `2` |

Вывод: менеджер права по данным 1С. Абонементная строка реально нулевая:
нулевая цена в регистре и нулевая строка продажи. Direct-платеж `25` существует
и связан через `Document154`, но он не должен превращать бесплатную неделю в
платную строку и не должен задавать `type_of_payment` в нашем импорте.

Масштаб похожего недельного слоя:

```text
trial_week_direct_zero: 7 строк
```

Построчный отчет по этим `7` строкам:

```text
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_audit.csv
```

Разложение по строкам продажи 1С:

| contract_id | название | целевая строка абонемента | другие строки в sale doc | payment по sale doc | вывод |
|---|---|---:|---|---:|---|
| `00000070045` | `Абонемент НЕДЕЛЯ САЙТ` | `0` | `Перчатки` `25` | `25` | бесплатная неделя подтверждена: платеж не за абонемент |
| `00000070915` | `Абонемент НЕДЕЛЯ САЙТ` | `0` | `Абонемент МУЛЬТИКАРТА 12 месяцев` `00000070914`, строка `6999` | `5999` | бесплатная неделя в одном sale doc с платным годовым абонементом |
| `00000071040` | `Абонемент НЕДЕЛЯ САЙТ` | `0` | `Абонемент УЛЬТРА 12 месяцев` `00000071039` `6999` + `3 месяца в подарок` `0` | `5999` | бесплатная неделя в одном sale doc с платным годовым абонементом |
| `00000072190` | `Абонемент НЕДЕЛЯ САЙТ` | `0` | `3 месяца в подарок` `0` + `Абонемент УЛЬТРА 12 месяцев` `00000072191` `6999` | `5999` | бесплатная неделя в одном sale doc с платным годовым абонементом |
| `00000115678` | `Абонемент Неделя Фитнес` | `0` | `Доплата` `2000` | `4000` по двум платежам, текущий match `2000` | после ответа бизнеса: неделя бесплатная, payment относится к `Доплата`; очищать `type_of_payment` |
| `00000117756` | `Абонемент Неделя Фитнес` | `0` | `Доплата` `2000` | `2000` | по аналогии с подтвержденным `00000115678`: неделя бесплатная, payment относится к `Доплата`; очищать `type_of_payment` |
| `00000132241` | `Абонемент 2 недели Фитнес` | `490` | нет | `490` | не бесплатный кейс; есть связанный `Document131` refund |

Проверка подтверждает, что менеджерский комментарий “бесплатная неделя” по
`НЕДЕЛЯ САЙТ` основан на данных 1С: в `InfoRg3060` цена/оплата равны `0`, в
целевой строке `Document154_VT1137` сумма абонемента равна `0`, а `Document152`
payment подтянулся к нам только потому, что платеж связан с тем же документом
продажи, где лежит другая платная строка.

После ответа бизнеса safe-вывод расширен: при `price=0`, нулевой целевой
строке продажи и direct-платеже от того же sale doc надо очищать
`type_of_payment` не только у `НЕДЕЛЯ САЙТ`, но и у `Неделя Фитнес`, если
платеж относится к отдельной строке `Доплата`.

## Ручной пример 2: `00000041901`, возврат/блокировка

Комментарий бизнеса:

```text
Проведен возврат. Блокировка абонемента.
```

Что видно в 1С по самой строке:

| поле | значение |
|---|---|
| contract_id | `00000041901` |
| client_id | `000003758` |
| клиент | Годарева Ирина Викторовна |
| название | `Абонемент УЛЬТРА 12 месяцев` |
| product_class | `full_subscription` |
| sale_datetime | `2019-03-12 10:39:39` |
| start/end | `2001-01-01` - `2001-01-01` |
| duration_days | `1` в staging, `0` в `InfoRg3060` |
| `rg_price` | `0` |
| `rg_paid_candidate` | `0` |
| `rg_payment_count_candidate` | `4` |
| direct payments | `3750` + `1250`, операция `Оплата от клиента` |
| `Document154` sale line | `7499` |
| `Document131` refund | `00000000016`, `2019-03-12 10:45:22`, posted/unmarked |
| refund link | `Document131._Fld547_RRRef = sale_doc_ref 89089446913257BF41A9103427BFE793` |
| refund amount | `_Fld548=5000`, `_Fld549=7499` |
| visits | `10` |

Важная соседняя строка того же клиента:

| contract_id | sale_datetime | start/end | rg_price | direct payments | visits |
|---|---|---|---:|---:|---:|
| `00000041903` | `2019-03-12 00:00:00` / sale doc `10:49:58` | `2019-03-12` - `2020-03-11` | `7499` | `3750 + 1250 + 625 + 1874` | `108` |

Что искали:

- `Document152` operation/ref text с `Возврат`/`Блокировка`;
- комментарии `Document152`, `Document154`, `Document163`;
- `Reference52` metadata по объектам возврата/блокировки/заморозки;
- `Document131` (`ВозвратОтПокупателя`) по ссылкам на документ продажи;
- `Document6137` (`МассоваяЗаморозка`);
- target references в основных таблицах: `InfoRg3060`, `Document154`,
  `Document150`, `Document138`, табличные части `Document163`;
- справочники с описаниями `Возврат`/`Блокировка`.

Что найдено:

- по `00000041901` платежи `Document152` имеют operation `Оплата от клиента`,
  поэтому по payment operation возврат не виден;
- возврат найден отдельным документом `_Document131`:
  `00000000016`, posted/unmarked, `2019-03-12 10:45:22`;
- `_Document131` ссылается на продажу `00000000881` через `_Fld547_RRRef`;
- сумма возврата `_Fld548=5000` совпадает с суммой двух оплат `3750+1250`,
  `_Fld549=7499` совпадает с суммой строки продажи;
- в текстовых полях `Document152`/`Document154`/`Document163` по клиенту
  `возврат`/`блок` не найден;
- отдельный документ `МассоваяЗаморозка` есть в metadata как `_Document6137`,
  но таблица пустая (`0` строк);
- отдельного документа “Блокировка абонемента” в metadata не найдено; есть
  служебные регистры/константы блокировок, но не прямой документ членства;
- найден машинный служебный/блокировочный признак:
  `start_date=end_date=2001-01-01` при full-абонементе и цене `0`;
- рядом есть нормальное членство `00000041903` с тем же названием и нормальными
  датами/ценой;
- строка историческая, не active на cutoff; финальная воронка по клиенту
  выбрала другое, более позднее членство `00000068306`.

Вывод: менеджерский комментарий по возврату подтверждается 1С. Источник не
`Document152` payment operation, а отдельный `Document131`
`ВозвратОтПокупателя`, связанный с `Document154` продажи. Комментарий по
блокировке отдельным документом не подтвержден; вероятнее всего он виден в
интерфейсе по состоянию/датам членства. Для Годаревой надежный составной
признак:

```text
full_subscription
AND price=0
AND direct payment exists
AND Document131 refund linked to Document154 sale doc exists
AND start_date = '2001-01-01'
AND end_date = '2001-01-01'
AND not active on cutoff
```

В исходном слое `207` строк такой pattern нашел ровно `1` строку:
`00000041901`.

Важно: по `00000041901` есть `10` посещений. Поэтому это не кандидат на
автоматическое удаление всей строки как “мусора”. Если бизнес подтверждает
комментарий, безопаснее не удалять историческую строку, а оставить
`price=0`, `paid=0`, `payment_left=0` и очистить `type_of_payment`.

## `Document131` возврата по исходному слою `207`

Построчный отчет:

```text
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_audit.csv
```

Сводка:

| группа | refund linked | no refund |
|---|---:|---:|
| `full_active_zero_direct` | `0` | `44` |
| `full_finished_normal_dates_zero_direct` | `136` | `16` |
| `full_service_dates_2001` | `1` | `0` |
| `trial_week_direct_zero` | `1` | `6` |
| `unknown_review_required` | `3` | `0` |

Итого в исходных `207` строках до внедрения правил:

- `141` строка имеет связанный `Document131` возврата;
- все `141` имеют posted/unmarked refund-документ;
- активных строк с refund-документом: `0`;
- все `44` активные full-строки не имеют связанного refund-документа.

После внедрения SQL-признака в staging правило стало шире и точнее:
`176` historical zero-direct строк имеют linked posted/unmarked `Document131`
refund. В их числе `34` строки уже были с пустым raw method и не входили в
старый слой `207` как заполненный `type_of_payment`; они теперь тоже получили
правильную business-причину.

Текущий остаток после пересборки:

- `61` строка `price=0 + direct payment + type_of_payment оставлен`;
- среди них linked `Document131`: `0`;
- активных среди них: `44`, все full;
- non-active остаток до новых ответов: `15` historical full без refund + `2`
  `Неделя Фитнес`. После ответа бизнеса `Неделя Фитнес` закрывается как
  бесплатная недельная строка, а historical full без refund - как реальные
  оплатные строки с проблемной цепочкой 1С.

Практический вывод: для исторических zero-direct строк появился надежный
источник служебности/возврата. Такие строки не являются обычной оплаченной
продажей, даже если прямой `Document152` payment имеет operation
`Оплата от клиента`.

## Активные full-строки: главный риск

Активный слой:

```text
full_active_zero_direct: 44 строки
```

SQL-разрез:

| metric | rows |
|---|---:|
| active full rows | `44` |
| positive direct payment | `44` |
| positive `Document154` sale-line | `44` |
| rows with visits | `43` |
| selected in `final_funnel_clients` | `43` |

По статусам:

| status | rows | with visits | selected |
|---|---:|---:|---:|
| blank | `39` | `38` | `39` |
| `Контакт с клиентом` | `4` | `4` | `4` |
| `Успех` | `1` | `1` | `0` |

Построчный отчет для этих `44` active full-строк:

```text
output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_active_full_44_detail.csv
```

Проверка отчета:

- строк данных: `44`;
- колонок: `15`;
- `visit_docs > 0`: `43`;
- `sale_line_sum > 0`: `44`;
- `matched_payment_amount > 0`: `44`;
- `is_selected_subscription = 1`: `43`.

Вывод: активные `44` не похожи на возврат/блокировку или бесплатный trial.
Почти все используются как активное основание входа. У всех есть положительная
строка продажи и положительный direct payment.

Значит текущая проблема в активном слое, скорее всего, не `type_of_payment`, а
потерянный `price`: `rg_price=0`, но `Document154` / `Document152` показывают
реальную сумму.

Это нельзя чинить тем же правилом, что бесплатные недели. Для активных full
нужно отдельное решение:

```text
если full active, price=0, direct payment exists, sale_line_sum>0,
то можно ли восстанавливать price из Document154 sale_line_sum
и amount_of_payments из фактических платежей?
```

Основной XLSX не менялся для этих `44` строк: они остаются в открытом остатке.

## Что внедрено в пайплайн

### 1. `НЕДЕЛЯ САЙТ` direct zero

Внедренное правило:

```text
price=0
AND product_class='trial_or_guest'
AND contract_name='Абонемент НЕДЕЛЯ САЙТ'
AND direct payment exists
AND membership_sale_line_amount=0
THEN type_of_payment=''
```

Эффект на текущей выгрузке: `4` строки.

Почему не шире: есть `Неделя Фитнес` и `2 недели Фитнес`, где суммы direct
платежей выше; для них нужен отдельный бизнес-ответ.

### 2. Исторические строки со связанным `Document131` возврата

Внедренное правило:

```text
price=0
AND direct payment exists
AND not active on cutoff
AND posted/unmarked Document131 refund linked to Document154 sale doc exists
THEN type_of_payment=''
```

Эффект на текущей выгрузке: `176` строк, все исторические. Внутри них:

- `172` full_subscription;
- `3` unknown/non-full;
- `1` trial/short;
- `34` строки уже имели пустой raw method и пустой `type_of_payment`, но теперь
  получили точную business-причину; все `34` - full_subscription;
- `142` строки раньше держали заполненный `type_of_payment`, именно они
  уменьшили открытый слой `207 -> 61`; внутри них `138` full_subscription,
  `3` unknown/non-full и `1` trial/short.

Для строки Годаревой есть дополнительный признак блокировки:
`start_date=end_date=2001-01-01`. Но для большинства refund-строк даты
нормальные или коротко закрытые, поэтому `2001-01-01` нельзя использовать как
общее refund-правило.

Почему не удалять автоматически: у части строк есть посещения/исторический
след. Без отдельного бизнес-решения безопаснее очищать `type_of_payment`, а не
выкидывать строку из истории.

### 3. Активные full `price=0`

Не применять zero/free/refund-правила.

Нужен отдельный ручной/бизнес ответ: восстанавливать ли `price` по
`Document154` для `44` активных full-строк. Это сейчас самый важный слой внутри
проблемы `price=0 + direct payment`, потому что он влияет на активных клиентов.

## Открытые вопросы

1. Отдельно подтвердить, распространяется ли аналогичная очистка на
   `Абонемент Неделя Фитнес`, где целевая строка абонемента `0`, а payment
   относится к строке `Доплата`: текущий остаток `2` строки.
2. Отдельно решить `15` historical full-строк без связанного `Document131`:
   у них `price=0`, direct-платеж и заполненный `type_of_payment`, но refund
   source не найден.
3. Отдельно решить активные `44` full-строки: это не возвраты, не блокировки и
   не бесплатные недели; вероятно, там надо восстанавливать `price`, а не
   очищать способ оплаты.

## XLSX на 7 примеров для бизнес-разметки

Файл:

```text
output/20251115_0800_fix_owner_new_import/zero_price_direct_review_7_examples_20260525_0800.xlsx
```

Формат: один лист `Импорт_абонементы`, ровно `20` колонок основного
`fitbase_import_abonementy_clientov_20260525_0800.xlsx`, без служебных полей и
без дополнительных листов.

Все `7` contract_id не входят в прошлую representative-30 выборку.

| contract_id | статус вопроса | зачем включен |
|---|---|---|
| `00000138477` | закрыт ответом бизнеса | active full: фактическая оплата есть, payment висит через модификатор/заморозку; восстанавливать как оплатную строку |
| `00000135375` | закрыт ответом бизнеса | active full со статусом `Контакт с клиентом`: реальная оплатная строка с проблемной структурой 1С, не служебный мусор |
| `00000114583` | закрыт ответом бизнеса | historical full без linked `Document131`: договор создан до оплаты продажи; восстанавливать как оплатную historical строку |
| `00000115678` | закрыт ответом бизнеса | `Абонемент Неделя Фитнес`: целевая строка абонемента `0`, payment относится к строке `Доплата`; очищать `type_of_payment` как бесплатную недельную строку |
| `00000071040` | контроль закрытого правила | direct `Абонемент НЕДЕЛЯ САЙТ`: целевая строка абонемента `0`, payment относится к годовому абонементу в том же sale doc; текущее правило очищает `type_of_payment` |
| `00000125150` | контроль закрытого правила | historical full с linked posted/unmarked `Document131` refund; текущее правило очищает `type_of_payment` |
| `00000132241` | контроль закрытого правила | короткий абонемент с положительной строкой продажи `490` и linked `Document131` refund; это не бесплатный trial, очищается именно по refund-правилу |

После ручной разметки этого файла ожидаемые решения:

- подтвердить или запретить восстановление `price` для active full слоя;
- внедрить подтвержденное правило по `Неделя Фитнес`/`Доплата`;
- понять, что делать с historical full без `Document131`;
- перепроверить, что уже внедренные safe-правила по `НЕДЕЛЯ САЙТ` и
  `Document131` не требуют отката.
