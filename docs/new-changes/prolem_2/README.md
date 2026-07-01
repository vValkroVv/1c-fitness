# Отчеты по проблеме 2

Сюда складывать все отчеты при выполнении плана:

- `docs/new-changes/02_membership_import_plan.md`

Ожидаемые материалы: SQL-discovery, маппинг полей, проверки рассрочки, отчеты по
вычисленным значениям, итоговая валидация XLSX абонементов.

Текущая реализация:

- `00_execution_log.md` - что запускалось и итоговые счетчики.
- `01_sql_discovery_membership.md` - найденные SQL-источники и решения по
  полям.
- `02_implementation_and_validation.md` - созданные скрипты, output и
  результаты проверки.
- `03_followup_answers_2026-06-22.md` - разбор пустого `payment_type`,
  `price=0`, субаренды и рассрочек после дополнительной проверки.
- `04_open_problems_to_resolve.md` - отдельный список проблем для постепенного
  решения.
- `current_payment_price_state.md` - единая текущая рабочая сводка по
  `payment_type` и `price=0`: принятые бизнес-правила, новое разложение
  остатка и детальный разбор основных кейсов. Использовать этот файл как
  основной для дальнейшего исправления.
- `current_subrent_visits_left_state.md` - текущий детальный разбор
  `visits_left` для субаренды: масштаб, активные/закрытые строки,
  найденный источник остатка через баланс `dbo._AccumRg3336` по правильной
  размерности, расчет активных остатков и правило `0` для просроченной
  ограниченной субаренды.
- `05_tarasenko_00000100483_owner_change.md` - точечная проверка
  подозрительного абонемента `00000100483` у Тарасенко. Найден пропущенный
  тип owner-change `Смена владельца подарочной карты`; после пересборки
  основного XLSX строка переехала к Коновалову.
- `06_sergeev_00000130311_owner_change.md` - проверка строки
  `00000130311` из representative sample. Подтверждено, что текущая строка
  ошибочно была у Сергеева Юрия; после пересборки основного XLSX строка
  переехала к Сергеевой Ирине. Representative/test XLSX не пересобирался.
- `07_representative_30_manual_answers_followup.md` - разбор ручных ответов
  по `membership_import_representative_30_examples_20260525_0800-with-answers.xlsx`:
  что подтверждено, что уже закрыто owner-change правилом, и какие остаточные
  группы требуют решения (`327` no-payment cash, исходные `207` zero direct,
  `payment_left > 0`/рассрочки, `Розничный клиент`). Technical raw method
  закрыты как `безналичные`, субаренда по `type_of_payment` оставлена в
  текущей логике `безналичные`. Новый XLSX на `7` строк для разметки
  `payment_left > 0` и `Розничный клиент`:
  `output/20251115_0800_fix_owner_new_import/payment_left_retail_review_7_examples_20260525_0800.xlsx`;
  пересборка: `scripts/35_build_payment_left_retail_review_7_examples.py`.
- `08_popova_00000145048_extra_sale.md` - детальный разбор ручного комментария
  по Поповой Ирине / `00000145048`: почему бизнес увидел лишнюю продажу,
  какие признаки есть в 1С, почему наша воронка выбрала ложное членство, и
  как искать похожие случаи в группе `D_positive_no_payment_cash_327`.
  Обновление `2026-06-24`: добавлен подсчет по полной базе для паттерна
  `активный full сейчас + следующий/later full в статусе Контакт с клиентом`;
  строгих строк `4`, все `4` исключены из основного XLSX правилом
  `exclude_active_later_contact_full`; самый сильный поповский паттерн найден
  только у Поповой.
- `09_no_payment_cash_active_overlap_deep_dive.md` - deep-dive по оставшимся
  no-payment cash строкам с active/not-finished full пересечениями после
  strict-фикса: `63` строки / `46` клиентов, разложение по посещениям,
  nearby-платежам, статусам, дублям и приоритетам ручного/автоматического
  решения. Сформирован review XLSX:
  `output/20251115_0800_fix_owner_new_import/no_payment_cash_active_full_overlap_review_20260525_0800.xlsx`.
  Дополнительно сформирован XLSX на `7` примеров в обычном формате основного
  импорта для разметки правил по проблемам `08`/`09`:
  `output/20251115_0800_fix_owner_new_import/no_payment_cash_active_full_overlap_7_examples_20260525_0800.xlsx`.
  Пересборка: `scripts/26_build_no_payment_cash_active_overlap_audit.py`,
  затем `scripts/25_build_no_payment_cash_active_overlap_review.py` и
  `scripts/27_build_no_payment_cash_active_overlap_7_examples.py`.
  Update `2026-06-24`: ответы бизнеса по копии файла показали, что этот слой
  смешанный; массовое исключение по `Отказ`/`Бронь`, future-start или visits
  не внедрять без новой базы/нового payment matcher-а.
- `10_zero_price_direct_payment_deep_dive.md` - deep-dive по исходным `207` строкам
  `price=0 + direct payment + заполненный type_of_payment` после ручных
  ответов. Safe-правки внедрены в основной пайплайн: `4` direct-строки
  `НЕДЕЛЯ САЙТ` очищены как бесплатные недели по нулевой целевой строке
  `Document154_VT1137`; `176` historical zero-direct строк очищены по
  posted/unmarked `Document131` refund. Текущий остаток `price=0 + direct +
  заполненный type_of_payment`: `61` строка (`44` active full, `15`
  historical full без refund, `2` `Неделя Фитнес`/`Доплата`). Пересборка audit CSV:
  `scripts/28_build_zero_price_direct_payment_audit.py`.
  Построчный active-report для `44` full-строк:
  `scripts/29_build_zero_direct_active_full_detail_report.py` ->
  `output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_active_full_44_detail.csv`.
  Refund-link report: `scripts/30_build_zero_direct_refund_link_report.py` ->
  `output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_refund_link_audit.csv`.
  Applied overrides report:
  `output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_applied_overrides.csv`.
  Weekly/trial sale-context report: `scripts/33_build_zero_direct_trial_sale_context_report.py` ->
  `output/20251115_0800_fix_owner_new_import/reports/zero_price_direct_trial_sale_context_audit.csv`.
  Он фиксирует, что все `4` direct-строки `Абонемент НЕДЕЛЯ САЙТ` имеют
  нулевую целевую строку `Document154_VT1137`, а payment относится к другой
  строке того же sale doc; `2` строки `Абонемент Неделя Фитнес` похожи
  технически, но требуют отдельного бизнес-ответа по строке `Доплата`.
  XLSX на `7` новых примеров для бизнес-разметки:
  `output/20251115_0800_fix_owner_new_import/zero_price_direct_review_7_examples_20260525_0800.xlsx`;
  пересборка: `scripts/34_build_zero_direct_review_7_examples.py`.
- `11_manual_answers_7_examples_analysis.md` - общий разбор ответов бизнеса
  по трем файлам на `7` примеров: no-payment active overlap,
  zero-price direct payment, `payment_left`/рассрочки и `Розничный клиент`.
  Файл фиксирует новые выводы: no-payment слой смешанный и требует новой базы
  или matcher-а; zero-direct full без refund нужно восстанавливать как
  оплатные строки; `Неделя Фитнес` с `Доплата` очищать как бесплатную
  недельную строку; named-рассрочки корректны; retail-клиента не выгружать.
- `12_active_only_problem_scope.md` - active-only срез по проблемам из `07`:
  что реально может повлиять на перенос действующих клиентов. Основные
  активные риски: `198` active no-payment cash (`63` из них в детальном
  active-overlap), `44` active zero-direct full и `297` active non-named
  `payment_left > 0`.
- `13_1c_report_sources_discovery.md` - поиск SQL-источников для тех же
  клиентских отчетных блоков, которые менеджер смотрит в 1С: структура
  подчиненности, история операций и регистры оплат. Вывод: структуру можно
  восстановить через `Document163/154/152/138/131`, бизнес-операции по
  членству лежат в `_Document138`, платежные/долговые движения - в
  `_AccumRg3305`; полная `_DataHistory*` история изменений в бэкапе пустая.
- `14_payment_left_auxiliary_operation_5_clients.md` - точечный разбор `5`
  активных non-named `payment_left > 0` клиентов. Найдено, что во многих
  случаях текущий `payment_left` совпадает с суммой direct-платежей к продаже:
  проблема не только во вспомогательной продаже/эмуляторе, но и в том, что
  `rg_paid_candidate` нельзя всегда трактовать как уже оплаченную сумму.
  Массовая проверка: у всех `297` строк есть direct-платежи; у `277` сумма
  direct-платежей примерно равна текущему `payment_left`.
- `15_active_problem_case_workbooks.md` - сборка трех XLSX по всем активным
  кейсам из текущих открытых проблем: `198` no-payment cash, `44`
  zero-price direct active full и `297` non-named `payment_left`. Все файлы
  сделаны в обычном формате основного импорта: один лист, те же `20` колонок,
  без диагностических полей.

Основной воспроизводимый запуск:

```bash
scripts/31_build_membership_import_outputs.sh
```
