# Реализация и валидация импорта услуг

Рабочий срез: `2026-05-25 08:00`.

## Скрипты

SQL:

- `sql/48_services_import_discovery.sql`
- `sql/50_services_source_probe.sql`
- `sql/51_find_reference_probe.sql`
- `sql/52_document154_client_field_probe.sql`
- `sql/53_service_package_balance_probe.sql`
- `sql/54_build_services_import_staging.sql`
- `sql/55_services_template_only_ref_search.sql`
- `sql/56_services_template_only_targeted_sources.sql`

Python/shell:

- `scripts/23_build_services_import_xlsx.py`
- `scripts/24_validate_services_import_xlsx.py`
- `scripts/32_build_services_import_outputs.sh`

Основной запуск:

```bash
scripts/32_build_services_import_outputs.sh
```

## Итоговые XLSX

- `output/20251115_0800_fix_owner_new_import/fitbase_import_uslugi_clientov_20260525_0800.xlsx`
- `output/20251115_0800_fix_owner_new_import/fitbase_import_shablony_uslug_20260525_0800.xlsx`

## Отчеты

- `output/20251115_0800_fix_owner_new_import/reports/services_build_report.md`
- `output/20251115_0800_fix_owner_new_import/reports/services_validation_report.md`
- `output/20251115_0800_fix_owner_new_import/reports/services_coverage_report.csv`
- `output/20251115_0800_fix_owner_new_import/reports/services_import_uncertainties.csv`
- `output/20251115_0800_fix_owner_new_import/reports/services_active_rows_audit.csv`

## Счетчики сборки

- источник клиентов: финальный `import_заявки` из
  `output/20251115_0800_fix_owner`;
- клиентов в источнике: `64 934`;
- raw service facts из SQL: `50 221`;
- клиентских строк в XLSX: `529`;
- активных клиентских строк: `352`;
- исторических fallback-строк: `176`;
- исторических fallback-строк вне `import_заявки`: `1`;
- шаблонов услуг: `51`;
- услуг с клиентскими строками: `44`;
- услуг только в шаблонах: `7`.

Типы оплаты в клиентском XLSX:

- `безналичные`: `501`;
- `наличные`: `13`;
- `сбп`: `9`;
- пусто: `6`.

Пустой `type_of_payment` есть только у строк с `price=0` и `amount_of_payment=0`:

- 5 строк `Заморозка абонемента 1 месяц`;
- 1 строка `Персональная тренировка VIP`.

Строк с `price>0` и пустым `type_of_payment` нет.

## Валидация

`scripts/24_validate_services_import_xlsx.py`:

```text
status: PASS
client rows: 529
template rows: 51
services represented in client rows: 44
duplicate service_id values: 0
template-only services: 7
errors: none
warnings:
- client rows outside final import_zayavki: 1
- services without client rows, template only: 7
```

Проверки:

- заголовки клиентского XLSX совпадают с шаблоном;
- заголовки шаблонов услуг совпадают с шаблоном;
- в шаблонах ровно 51 услуга и порядок совпадает с
  `new-changes/Услуги список нужных.xlsx`;
- в клиентском XLSX нет услуг вне списка 51;
- все клиенты клиентского XLSX входят в финальный `import_заявки`, кроме
  осознанного historical fallback вне `import_заявки` для `Утеря валика`;
- дублей `service_id` нет;
- обязательные поля заполнены.

## Fallback вне import_заявки

По дополнительному решению historical fallback больше не ограничивается
клиентами финального `import_заявки`.

Если по услуге нет активных и исторических строк среди финальных клиентов, но
есть реальная историческая продажа в 1С, строка добавляется в клиентский XLSX с
техническим менеджером:

```text
УТОЧНИТЬ: вне import_заявки
```

Так была добавлена услуга:

```text
Утеря валика
client_id: 000014428
client_fio: Поутанен Ирина Ивановна
sale date: 2020-01-14
price: 500
type_of_payment: безналичные
```

Валидация теперь считает клиента вне финального `import_заявки` предупреждением,
а не ошибкой, потому что это осознанный historical fallback.

## Услуги только в шаблонах

7 услуг не получили клиентские строки, потому что по ним не найдено продаж в
известных источниках продаж/услуг:

1. `Йога (персональная тренировка) 12 пос. (группа до 4 человек)`
2. `Йога (персональная тренировка) 12 пос. VIP (1 человек)`
3. `Йога (персональная тренировка) 8 пос. (группа до 4 человек)`
4. `Йога (персональная тренировка) 8 пос. VIP (1 человек)`
5. `Сайкл для начинающих без клубной карты`
6. `Пакет 10 ВИП (персональные тренировки)`
7. `Пакет 4 (персональные тренировки)`

Targeted-проверка этих 7 услуг показала `0` строк в:

- `dbo._Document154_VT1137`;
- `dbo._Document154_VT1181`;
- `dbo._Document154_VT1162`;
- `dbo._Document163`;
- основных ссылочных полях шапки `dbo._Document154`.

То есть реальные исторические клиентские примеры для этих 7 услуг в найденных
источниках отсутствуют. В клиентский XLSX искусственные строки по ним не
добавлялись.

## Принятые правила для fallback

Если у услуги нет активных строк среди финальных клиентов, но есть исторические
продажи финальных клиентов, в клиентский XLSX добавляется до 5 последних строк.

Для исторического fallback:

- `activation_date` = дата продажи, если нет реальной даты активации;
- `end_date` = дата продажи, если нет реальной даты окончания;
- `visits_left` = `0`, чтобы исторический пример не выглядел как текущий
  активный остаток.

Это отличается от активных пакетных услуг, где `visits_left` берется из
реального баланса `_AccumRg3336`.
