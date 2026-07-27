# Поставка с достоверной задолженностью менеджера

- Дата сборки: `2026-07-23`
- Backup: `data/Fitnes-30-06-26.bak`
- Единый cutoff: `2026-06-30 23:27:03`
- Базовая поставка: `output/20260630_delivery_manager_fixes_v2/`
- Новая поставка: `output/20260630_delivery_manager_debts_applied/`

## Применённое бизнес-правило

Правило применено только к договорам problem1–3:

1. если человек есть в `Задолженности клиентов 30.06.2026.xlsx`, в договор
   переносятся `Продано`, `Оплачено`, `Задолженность` из строки его продажи;
2. если человека в отчёте нет, устанавливается:

```text
price = 12000
amount_of_payments = 12000
payment_left = 0
```

Менялись только эти три поля. Все остальные значения договоров оставлены
без изменений.

Problem4 не исправлялся: договор `00000151350` отсутствует в clean membership
и сохранён отдельным XLSX без побайтовых изменений.

## Результат

| группа | всего | из XLSX менеджера | fallback |
| --- | ---: | ---: | ---: |
| problem1 | `10` | `1` | `9` |
| problem2 | `41` | `0` | `41` |
| problem3 | `203` | `191` | `12` |
| **всего** | **254** | **192** | **62** |

Все `254` договора problem1–3 возвращены в clean membership. Из них:

- у `165` договоров реально изменилось хотя бы одно финансовое поле;
- у `89` значения уже совпадали с новым правилом;
- изменено `326` финансовых ячеек;
- не финансовых изменений: `0`;
- неаудированных финансовых изменений: `0`.

Новые суммы по обработанным договорам:

| источник | price | amount_of_payments | payment_left |
| --- | ---: | ---: | ---: |
| XLSX менеджера | `2 351 510` | `1 553 110` | `931 367` |
| fallback | `744 000` | `744 000` | `0` |
| **всего** | **3 095 510** | **2 297 110** | **931 367** |

Таким образом, все люди из достоверного менеджерского отчёта переносятся с
указанной там задолженностью. У отсутствующих в отчёте долг равен нулю.

## Итоговые XLSX

В корне новой папки лежат `7` XLSX:

| файл | строк данных |
| --- | ---: |
| `fitbase_active_clients_import_zayavki_20260630_all_funnels.xlsx` | `39550` |
| `fitbase_active_clients_plastic_cards_20260630_all_funnels.xlsx` | `11024` |
| `fitbase_import_abonementy_clientov_20260630.xlsx` | `121461` |
| `fitbase_import_shablony_abonementov_20260630.xlsx` | `119` |
| `fitbase_import_shablony_uslug_20260630.xlsx` | `51` |
| `fitbase_import_uslugi_clientov_20260630.xlsx` | `522` |
| `problem_4_subrent_visits_left_contract_151350_1_case_20260630.xlsx` | `1` |

Пять основных XLSX, которые не относятся к клиентским абонементам, и
problem4 скопированы из базовой поставки побайтно.

## Дополнительная таблица fallback

По отдельному запросу создан файл:

```text
output/20260630_delivery_manager_debts_applied/additional/
fitbase_import_abonementy_clientov_fallback_12000_12000_0_62_cases_20260630.xlsx
```

В нём ровно `62` строки договоров из основной таблицы, для которых применено
правило `12000 / 12000 / 0`. Строки побайтно по значениям совпадают с
соответствующими строками основной таблицы. У одного клиента два договора,
поэтому в файле `62` договора и `61` уникальный `client_id`; строки намеренно
не объединялись.

## Проверки

| проверка | результат |
| --- | --- |
| Python compile | `PASS` |
| unit tests | `16/16 PASS` |
| общий структурный валидатор | `PASS` |
| независимая построчная сверка membership | `PASS` |
| состав итоговых XLSX | `PASS`, `6 clean + 1 problem4` |
| problem1–3 присутствуют в clean ровно один раз | `PASS`, `254/254` |
| problem4 отсутствует в clean | `PASS`, `1/1` |
| изменения вне трёх финансовых колонок | `0` |
| формулы / пустые строки / неожиданные филиалы | `0` |
| Quick Look thumbnails | `7/7` созданы |

Аудит каждой строки и машинные отчёты лежат в:

```text
output/20260630_delivery_manager_debts_applied/reports/
```

## Воспроизведение

Из папки `end-to-end-xlsx/`:

```shell
.venv/bin/python scripts/build_manager_debt_delivery.py \
  --config config/manager_debt_resolution_20260630.yml

.venv/bin/python scripts/validate_delivery.py \
  --output-dir ../output/20260630_delivery_manager_debts_applied \
  --expected reference/expected_20260630_manager_debts_applied.yml \
  --report ../output/20260630_delivery_manager_debts_applied/reports/structural_validation.md \
  --json-report ../output/20260630_delivery_manager_debts_applied/reports/structural_validation.json \
  --enforce-reference-counts

.venv/bin/python scripts/validate_manager_debt_delivery.py \
  --config config/manager_debt_resolution_20260630.yml \
  --expected reference/expected_20260630_manager_debts_applied.yml \
  --report ../output/20260630_delivery_manager_debts_applied/reports/independent_validation.md \
  --json-report ../output/20260630_delivery_manager_debts_applied/reports/independent_validation.json
```

Сборщик не перезаписывает существующую выходную папку. Для нового immutable
прогона нужно указать новое имя `output.directory` в конфиге.

Все значимые входы закреплены SHA-256: менеджерский отчёт, полный membership,
его шаблон и десять XLSX базовой поставки. Cutoff дополнительно сверяется с
пинованным manifest исходной поставки.
