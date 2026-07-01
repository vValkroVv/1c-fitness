# XLSX по активным проблемам действующих клиентов

Дата сборки: `2026-06-24`.

Срез: `2026-05-25 08:00`.

Цель: подготовить отдельные XLSX по трем активным проблемам, которые могут
повлиять на перенос действующих клиентов. Формат файлов такой же, как у
основного `fitbase_import_abonementy_clientov_20260525_0800.xlsx`: один лист
`Импорт_абонементы`, те же `20` колонок, без дополнительных диагностических
полей.

Скрипт пересборки:

```text
scripts/36_build_active_problem_case_workbooks.py
```

Команда:

```bash
python3 scripts/36_build_active_problem_case_workbooks.py
```

## Файлы

| проблема | файл | rows | clients |
|---|---|---:|---:|
| активное/будущее членство, платеж не найден, сейчас стоит `наличные` | `output/20251115_0800_fix_owner_new_import/active_problem_1_no_payment_cash_198_cases_20260525_0800.xlsx` | `198` | `181` |
| активный full-абонемент с `price=0`, хотя direct-платеж есть | `output/20251115_0800_fix_owner_new_import/active_problem_2_zero_price_direct_full_44_cases_20260525_0800.xlsx` | `44` | `44` |
| активный клиент с non-named `payment_left > 0` | `output/20251115_0800_fix_owner_new_import/active_problem_3_non_named_payment_left_297_cases_20260525_0800.xlsx` | `297` | `296` |

## Критерии отбора

### 1. No-payment cash active

Попадает строка, если:

- это full-членство;
- оно не закончилось на `2026-05-25`;
- `price > 0`;
- в текущей выгрузке стоит `type_of_payment = наличные`;
- платежный документ не найден.

Это широкий слой `198` строк. Внутри него есть наиболее подозрительный
active-overlap слой `63` строки, но в файл положены все `198`, потому что
задача была собрать все кейсы по проблеме.

### 2. Zero-price direct active full

Попадает строка, если:

- это full-членство;
- оно активно на `2026-05-25`;
- `price = 0`;
- direct-платеж к продаже найден;
- нет posted/unmarked `Document131` возврата;
- `type_of_payment` уже заполнен.

Это `44` активные full-строки, где абонемент может уехать в Fitbase как
бесплатный, хотя в 1С есть оплата.

### 3. Non-named payment_left active

Попадает строка, если:

- членство/услуга не закончилась на `2026-05-25`;
- `payment_left > 0`;
- в названии нет слова `рассроч`.

Это `297` строк, где текущий долг может быть ложным. После разборов по
`14_payment_left_auxiliary_operation_5_clients.md` важно, что у всех этих
строк есть direct-платежи к продаже, а у `277` текущий `payment_left` примерно
равен сумме direct-платежей. Поэтому этот файл нужен не только для поиска
вспомогательной операции, но и для проверки правила расчета денег.

## Проверка

Проверено после сборки:

| файл | rows | unique contract_id | лишние колонки | пересечения с другими файлами |
|---|---:|---:|---:|---:|
| problem 1 | `198` | `198` | `0` | `0` |
| problem 2 | `44` | `44` | `0` | `0` |
| problem 3 | `297` | `297` | `0` | `0` |

Все три файла содержат только колонки основного импорта:

```text
contract_id, client_id, phone, client_fio, contract_name, card, duration,
duration_type, create_date, payment_date, activation_date, end_date, freeze,
guests, visits_left, price, amount_of_payments, payment_left, type_of_payment,
manager
```
