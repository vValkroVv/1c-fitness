# Зачем нужен каждый файл

Короткая версия есть в README. Здесь список подробнее, на случай если нужно
проверить ZIP или разобраться во внутреннем этапе.

## Скрипты, которые запускает человек

| Файл | Когда нужен |
| --- | --- |
| `scripts/run_pipeline.py` | полный прогон от восстановленной базы до итоговых XLSX по конфигу |
| `scripts/compare_manager_debt_to_register.py` | контрольная сверка регистрового баланса и новой выгрузки с менеджерским XLSX |
| `scripts/build_manager_debt_delivery.py` | исторический post-processing менеджерского XLSX для problem1–3 |
| `scripts/validate_manager_debt_delivery.py` | историческая проверка manager-based поставки и fallback-правила |
| `scripts/build_fallback_membership_subset.py` | историческая отдельная таблица 62 fallback-договоров |
| `scripts/verify_backup.py` | проверка размера и SHA-256 `.bak` |
| `scripts/clean_runtime.py` | удаление `work`, `logs` и `output` перед передачей папки |
| `scripts/create_release_zip.py` | создание ZIP без данных клиентов и секретов |

Для обычной выгрузки запускайте только `run_pipeline.py`. В актуальном конфиге
он сам рассчитывает деньги из регистра и запускает менеджерскую сверку.

## Настройки

| Файл | Что в нём лежит |
| --- | --- |
| `config/pipeline.yml` | адрес SQL Server, метаданные backup, единый cutoff и имя output |
| `config/pipeline_register_debts_20260630.yml` | актуальная 7-файловая сборка с долгами из `_AccumRg3305` |
| `config/pipeline_manager_fixes_20260630.yml` | историческая 10-файловая сборка до исправления долгов |
| `config/manager_debt_resolution_20260630.yml` | историческая manager-based поставка с fallback `12000 / 12000 / 0` |
| `config/membership_template_canonicalization.csv` | явные варианты конфликтующих шаблонов абонементов |
| `config/product_reclassification_decisions.csv` | решения по спорным продуктам |
| `config/managers_by_club.yml` | список менеджеров каждого клуба |
| `config/branches_by_club.yml` | перевод внутреннего названия клуба в филиал Fitbase |

При переносе на другую машину обычно меняется только SQL-блок в
`pipeline_register_debts_20260630.yml`. Остальные настройки влияют на
бизнес-результат.

## SQL-запросы

| Файл | Что строит |
| --- | --- |
| `sql/part2_03_build_three_funnel_staging.sql` | клиентов, контакты, продукты, смены владельца, воронки и карты |
| `sql/31_build_membership_import_staging.sql` | факты по абонементам, оплатам, возвратам и посещениям |
| `sql/54_build_services_import_staging.sql` | продажи, оплаты и остатки услуг |
| `sql/export_membership_import_facts.sql` | поля и порядок колонок в membership TSV |
| `sql/export_services_import_facts.sql` | поля и порядок колонок в services TSV |

Все запросы читают `dbo` и пишут только в служебную схему `fitbase_part2`.

## Шаблоны Excel

```text
templates/import_zayavki.xlsx
templates/plastic_cards.xlsx
templates/membership_clients.xlsx
templates/membership_templates.xlsx
templates/service_clients.xlsx
templates/service_templates.xlsx
templates/services_required.xlsx
```

Первые шесть файлов задают колонки, русские заголовки и форматы Excel.
`services_required.xlsx` содержит согласованный список из 51 услуги.

Шаблоны лучше не открывать и не пересохранять без необходимости. Excel иногда
меняет внутреннюю структуру файла, хотя визуально книга выглядит так же.

## Почему в `scripts` столько номерных файлов

Это отдельные этапы старого рабочего пайплайна, собранные в одну переносимую
папку:

```text
12_build_part2_three_funnel_xlsx.py
16_reclassify_part2_from_csv.py
17_build_part2_combined_xlsx.py
18_validate_combined_single_stage_outputs.py
19_build_membership_import_xlsx.py
20_validate_membership_import_xlsx.py
23_build_services_import_xlsx.py
24_validate_services_import_xlsx.py
36_build_active_problem_case_workbooks.py
```

Номера сохранены, чтобы код можно было сопоставить с историей разработки.
`run_pipeline.py` сам передаёт этим скриптам пути и параметры.

Ещё три файла обслуживают общий запуск:

| Файл | Что делает |
| --- | --- |
| `scripts/database.py` | подключается к SQL Server, разбивает SQL по `GO` и пишет CSV/TSV |
| `scripts/build_delivery.py` | собирает 6 обычных XLSX; при закрытых problem1–3 оставляет только problem4 |
| `scripts/validate_delivery.py` | проверяет готовую папку перед передачей |

## Контрольные данные

В `reference/expected_20260630_manager_fixes_v2.yml` записаны:

- размер и SHA-256 backup;
- имена десяти файлов;
- ожидаемые строки и колонки;
- общее число спорных договоров;
- четыре допустимых филиала.

Это не выгрузка клиентов. Персональных данных в `reference` нет.

В `reference/expected_20260630_register_debts.yml` закреплены состав актуальной
семифайловой поставки, ожидаемое число строк и единственный problem4. Сам
менеджерский XLSX не является источником контрольных значений поставки:
пайплайн использует его только для validation-only сверки 274 продаж.

## Чего в ZIP быть не должно

Скрипт `create_release_zip.py` исключает:

- `.bak` и файлы восстановленной базы;
- `.env` и SQL-пароли;
- готовые XLSX;
- промежуточные CSV и TSV;
- рабочие логи;
- локальное `.venv` и Python cache.

В архиве остаётся только то, что нужно для нового запуска: код, SQL, настройки,
шаблоны, контрольный YAML и документация.
