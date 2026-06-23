# SQL discovery: membership import

База: `FitnessRestored_20260523_macos` в контейнере `mssql-fitness-2022`.

Логи discovery:

- `logs/new-changes/prolem_2/30_membership_import_discovery.clean.txt`
- `logs/new-changes/prolem_2/31_build_membership_import_staging.clean.txt`

## Найденные источники

Основной SQL staging:

- `fitbase_part2.stg_subscriptions_all`
- `fitbase_part2.stg_sales_all`
- `fitbase_part2.stg_membership_owner_changes`

Исходные таблицы 1С:

- `dbo._Document163` - документ членства/продажи абонемента;
- `dbo._InfoRg3060` - регистр с датами, ценой, заморозкой и платежными
  кандидатами;
- `dbo._Document152` - платежные документы, уже попадают в
  `fitbase_part2.stg_sales_all`.

## Решения по полям

| Поле XLSX | Источник/правило |
|---|---|
| `contract_id` | `dbo._Document163._Number`; проверка уникальности на итоговом XLSX дала `0` дублей |
| `client_id` | эффективный владелец из `stg_subscriptions_all.client_id`, после owner-change |
| `client_fio`, `phone`, `create_date`, `manager` | финальный XLSX `import_заявки` из `output/20251115_0800_fix_owner` |
| `card` | `selected_card_number` из stage для того же `client_id` |
| `contract_name` | `stg_subscriptions_all.subscription_name`; затем канонизируется к имени в шаблонах |
| `payment_date` | `stg_subscriptions_all.sale_date` |
| `activation_date` | `stg_subscriptions_all.start_date`, кроме технического `2001-01-01`, который считается пустым |
| `end_date` | `stg_subscriptions_all.end_date`, кроме технического `2001-01-01`, который считается пустым |
| `duration` | `dbo._Document163._Fld1481`; для недельных/коротких абонементов `0` |
| `duration_type` | всегда `месяц` |
| `freeze` | `dbo._InfoRg3060._Fld3068`, если значение положительное |
| `guests` | пусто, потому что гостевые визиты не используются |
| `visits_left` | для активной ограниченной субаренды считается как знаковый баланс `dbo._AccumRg3336` по размерности `_Fld3338_TYPE = 0x01` и пустым `_Fld3338_RTRef/_Fld3338_RRRef`; для просроченной ограниченной субаренды ставится `0`; для безлимитной субаренды остается пустым |
| `price` | `dbo._InfoRg3060._Fld3070` |
| `amount_of_payments` | `dbo._InfoRg3060._Fld3072`, если поле положительное; для рассрочек с пустым `_Fld3072` используется ближайший платеж `dbo._Document152`; для не-рассрочек без `_Fld3072` предполагается полная оплата |
| `payment_left` | `price - amount_of_payments`; рассрочка помечается только если пусты и `_Fld3072`, и найденный платеж |
| `type_of_payment` | ближайший платеж из `stg_sales_all` / `dbo._Document152`, затем маппинг в `наличные`, `безналичные`, `сбп` |

## Состав строк

В SQL staging включены:

- `full_subscription`;
- `trial_or_guest`;
- `субаренда` по названию, даже если старая классификация относила ее к
  `other_sale`/`unknown_review_required`.

Счетчики SQL staging до фильтра финального XLSX:

- всего: `100 399`
- `full_subscription`: `86 010`
- `trial_or_guest`: `12 575`
- субаренда: `1 814`
- строки со сменой владельца: `725`

После фильтра по финальному XLSX осталось `99 399` строк.

## Оставшиеся нерешенные источники

1. Тип оплаты не всегда восстанавливается, потому что платежный документ не
   всегда найден рядом с датой продажи или способ оплаты не маппится.
2. Старые строки с датой `2018-01-01` часто имеют `price=0` в найденном
   источнике цены.
