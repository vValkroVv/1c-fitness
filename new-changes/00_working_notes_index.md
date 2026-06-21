# Рабочие заметки по новым изменениям

Дата последнего перечитывания: 2026-06-21
Дата фиксации ответов заказчика: 2026-06-22

## Зачем этот файл

Эти заметки нужны как промежуточная рабочая память по папке `new-changes/`.
Сюда и в соседние MD нужно записывать вопросы, риски и спорные места сразу,
как они возникают при разборе. Это не финальная документация пайплайна, а
чеклист для аккуратной реализации.

## Связанные рабочие файлы

1. `new-changes/01_owner_change_intermediate_questions.md`
   - смена владельца;
   - почему текущие XLSX неправильно определяют действующих клиентов;
   - что нужно найти в 1С перед правкой SQL/staging.

2. `new-changes/02_membership_import_intermediate_questions.md`
   - новый импорт абонементов клиентов;
   - шаблоны абонементов;
   - рассрочка, долги, оплаты;
   - вопросы по duration, freeze, visits, branch access.

3. `new-changes/03_services_import_intermediate_questions.md`
   - новый импорт услуг клиентов;
   - шаблоны услуг;
   - список 51 услуги;
   - активные услуги и fallback на исторические примеры.

4. `new-changes/04_customer_answers_2026-06-22.md`
   - сырые ответы заказчика на вопросы A/B/C/D;
   - эти ответы считаются текущими бизнес-решениями для реализации.

## Зафиксированные решения от 2026-06-22

- Рабочий срез: `2026-05-25 08:00`. В логике данных считаем, что работаем
  именно на момент выгрузки, а не на фактическую июньскую дату.
- Источник клиентов для новых импортов: финальный `import_заявки` после всех
  фильтров и phone-dedup.
- Зафиксированные финальные файлы в корне репозитория:
  - `fitbase_active_clients_import_zayavki_20260525_0800_all_funnels.xlsx`
  - `fitbase_active_clients_plastic_cards_20260525_0800_all_funnels.xlsx`
- Клиенты, которых нет в финальном `import_заявки`, не должны попадать в новые
  файлы абонементов и услуг.
- Менеджер в новых импортах должен совпадать с менеджером из финального
  `import_заявки`.
- Новые импорты делаем отдельными XLSX. Старые файлы не ломаем, но исправление
  смены владельца должно применяться в базовой логике пайплайна.
- Тестовую загрузку в Fitbase выполняет пользователь. Наша зона ответственности:
  исправить owner-change и сформировать 4 новых XLSX плюс отчеты.

## Что перечитано в этом проходе

Новые материалы:

- `new-changes/change-name.md`
- `new-changes/Примеры ФИО (смена владельца).docx`
- `new-changes/import_abon_client_clarification.md`
- `new-changes/new-conversation-import-zayavli.md`
- `new-changes/clarification-rassrochka.md`
- `new-changes/Rassrochka_1_S_Fitnes_po_deystvuyuschemu_chlenstvu_s_prosrochkoy_platezha.docx`
- `new-changes/Rassrochka_1_S_Fitnes_po_zakrytomu_chlenstvu.docx`
- `new-changes/Rassrochka_1_S_Fitnes_po_deystvuyuschemu_chlenstvu_bez_prosrochki_platezha.docx`
- `new-changes/Импорт_абонементы_клиентов.xlsx`
- `new-changes/Импорт_шаблоны_абонементов.xlsx`
- `new-changes/Импорт_шаблоны_абонементов.xlsx  -  только для чтения - Excel (Сбой активации продукта).jpg`
- `new-changes/import_yslygi_clarification.md`
- `new-changes/new-conversation-import-yslygi.md`
- `new-changes/Импорт_услуги_клиентов.xlsx`
- `new-changes/Импорт_шаблоны_услуг.xlsx`
- `new-changes/Услуги список нужных.xlsx`

Текущая документация пайплайна:

- `docs/step_22_part2_20260525_0800_build.md`
- `docs/step_23_part2_20260525_0800_final_validation.md`
- `docs/step_25_part2_20260525_export_filters.md`
- `docs/step_26_part2_20260525_phone_deduplication.md`
- `docs/step_27_part2_20260525_branch_column.md`
- `docs/step_28_blamberus_owner_change_investigation.md`
- `docs/new_changes_01_owner_change_plan.md`
- `docs/new_changes_02_membership_import_plan.md`
- `docs/new_changes_03_services_import_plan.md`

Ключевые места реализации:

- `sql/part2_03_build_three_funnel_staging.sql`
- `scripts/11_export_part2_stage.py`
- `scripts/12_build_part2_three_funnel_xlsx.py`
- `scripts/16_reclassify_part2_from_csv.py`
- `scripts/17_build_part2_combined_xlsx.py`
- `scripts/18_validate_combined_single_stage_outputs.py`
- `config/table_mapping.yml`
- `config/product_reclassification_decisions.csv`
- `config/managers_by_club.yml`
- `config/branches_by_club.yml`

## Текущий технический блокер

На момент этого прохода Docker daemon не запущен:

```text
Cannot connect to the Docker daemon at unix:///Users/valerii.kropotin/.docker/run/docker.sock.
```

Поэтому прямой SQL-discovery по восстановленной базе пока не выполнен. Все
вопросы, где ниже написано `нужно закрыть SQL-discovery`, требуют запуска
`mssql-fitness` и поиска фактических 1С-таблиц/полей.

## Главная последовательность работ

1. Сначала исправить смену владельца в staging-слое.
2. После этого пересобрать и проверить текущие XLSX заявок/карт.
3. Потом строить импорт абонементов, потому что он зависит от правильного
   владельца членства.
4. Потом строить импорт услуг, потому что услуги частично пересекаются с
   классификацией продуктов и требуют отдельной discovery-логики.
