# Независимая проверка сентябрьской поставки

Результат: **PASS**. Проверок: 67, ошибок: 0.

Backup завершён: `2026-09-20 20:12:12`. Единый срез: `2026-09-22 20:12:12`.

Июньская поставка использована для проверки структуры, заголовков и сохранения явно закреплённых параметров шаблонов. Числа строк сентября сверены с текущей выгрузкой, а не с июньскими количествами.

| Файл | Июнь | Сентябрь | Столбцов |
| --- | ---: | ---: | ---: |
| fitbase_active_clients_import_zayavki_20260922_all_funnels.xlsx | 39550 | 40508 | 10 |
| fitbase_active_clients_plastic_cards_20260922_all_funnels.xlsx | 11024 | 11095 | 3 |
| fitbase_import_abonementy_clientov_20260922.xlsx | 121461 | 124988 | 22 |
| fitbase_import_shablony_abonementov_20260922.xlsx | 119 | 122 | 12 |
| fitbase_import_shablony_uslug_20260922.xlsx | 51 | 51 | 9 |
| fitbase_import_uslugi_clientov_20260922.xlsx | 522 | 516 | 17 |
| problem_4_subrent_visits_left_contract_151350_1_case_20260922.xlsx | 1 | 1 | 22 |

Проверены все строки и листы, ID, телефоны, детерминированный менеджер каждого клиента во всех слоях, филиалы, подписи воронок, связи с шаблонами, полное разделение main/problem4, суммы и даты staging, а также SHA-256 передаваемых файлов.

Граница окончания абонементов 2026-09-21/2026-09-22: 64 клиентов. Данные примеров: `output/20260922_delivery_audit/audit.json`.

| Контроль | Результат |
| --- | --- |
| Фактическое время backup | PASS |
| Согласованный единый срез | PASS |
| READY и manifest имеют PASS | PASS |
| Manifest охватывает все передаваемые файлы | PASS |
| SHA-256 и размер: fitbase_active_clients_import_zayavki_20260922_all_funnels.xlsx | PASS |
| SHA-256 и размер: fitbase_active_clients_plastic_cards_20260922_all_funnels.xlsx | PASS |
| SHA-256 и размер: fitbase_client_photos_20260922.zip | PASS |
| SHA-256 и размер: fitbase_import_abonementy_clientov_20260922.xlsx | PASS |
| SHA-256 и размер: fitbase_import_shablony_abonementov_20260922.xlsx | PASS |
| SHA-256 и размер: fitbase_import_shablony_uslug_20260922.xlsx | PASS |
| SHA-256 и размер: fitbase_import_uslugi_clientov_20260922.xlsx | PASS |
| SHA-256 и размер: problem_4_subrent_visits_left_contract_151350_1_case_20260922.xlsx | PASS |
| Структура и заголовки как в июне: fitbase_active_clients_import_zayavki_20260922_all_funnels.xlsx | PASS |
| Нет формул, Excel-ошибок и пустых строк: fitbase_active_clients_import_zayavki_20260922_all_funnels.xlsx | PASS |
| Структура и заголовки как в июне: fitbase_active_clients_plastic_cards_20260922_all_funnels.xlsx | PASS |
| Нет формул, Excel-ошибок и пустых строк: fitbase_active_clients_plastic_cards_20260922_all_funnels.xlsx | PASS |
| Структура и заголовки как в июне: fitbase_import_abonementy_clientov_20260922.xlsx | PASS |
| Нет формул, Excel-ошибок и пустых строк: fitbase_import_abonementy_clientov_20260922.xlsx | PASS |
| Структура и заголовки как в июне: fitbase_import_shablony_abonementov_20260922.xlsx | PASS |
| Нет формул, Excel-ошибок и пустых строк: fitbase_import_shablony_abonementov_20260922.xlsx | PASS |
| Структура и заголовки как в июне: fitbase_import_shablony_uslug_20260922.xlsx | PASS |
| Нет формул, Excel-ошибок и пустых строк: fitbase_import_shablony_uslug_20260922.xlsx | PASS |
| Структура и заголовки как в июне: fitbase_import_uslugi_clientov_20260922.xlsx | PASS |
| Нет формул, Excel-ошибок и пустых строк: fitbase_import_uslugi_clientov_20260922.xlsx | PASS |
| Структура и заголовки как в июне: problem_4_subrent_visits_left_contract_151350_1_case_20260922.xlsx | PASS |
| Нет формул, Excel-ошибок и пустых строк: problem_4_subrent_visits_left_contract_151350_1_case_20260922.xlsx | PASS |
| Ровно семь ожидаемых XLSX | PASS |
| problem4 содержит только договор 151350 | PASS |
| Заявки: уникальные client_id | PASS |
| Заявки: детерминированный общий пул менеджеров | PASS |
| Заявки: только допустимые филиалы | PASS |
| Абонементы и problem4: уникальные contract_id | PASS |
| Абонементы и problem4: детерминированный общий пул менеджеров | PASS |
| Абонементы и problem4: только допустимые филиалы | PASS |
| Услуги: уникальные service_id | PASS |
| Услуги: детерминированный общий пул менеджеров | PASS |
| Услуги: только допустимые филиалы | PASS |
| Менеджер каждого клиента одинаков во всех слоях | PASS |
| Нет повторов нормализованных телефонов заявок | PASS |
| Согласованные подписи воронок | PASS |
| Абонементы: все названия есть в шаблонах | PASS |
| Абонементы: имена шаблонов уникальны | PASS |
| Услуги: все названия есть в шаблонах | PASS |
| Услуги: имена шаблонов уникальны | PASS |
| Шаблоны: все явные canonical attrs сохранены | PASS |
| Шаблоны: общие явные решения совпадают с принятой июньской поставкой | PASS |
| Все ячейки main + problem4 совпадают с полным staging без потерь | PASS |
| Абонементы: сумма price совпадает с staging | PASS |
| Абонементы: сумма amount_of_payments совпадает с staging | PASS |
| Абонементы: сумма payment_left совпадает с staging | PASS |
| Финальная копия совпадает с проверенным imports: fitbase_import_shablony_abonementov_20260922.xlsx | PASS |
| Финальная копия совпадает с проверенным imports: fitbase_import_shablony_uslug_20260922.xlsx | PASS |
| Финальная копия совпадает с проверенным imports: fitbase_import_uslugi_clientov_20260922.xlsx | PASS |
| Все ожидаемые заявки переданы после известных исключений | PASS |
| Все отказники присутствуют в абонементах | PASS |
| Все поля заявок совпадают с актуальным owner CSV | PASS |
| Карты соответствуют только передаваемым действующим клиентам | PASS |
| Граница 2026-09-21/2026-09-22: предыдущий день истёк, текущий действует | PASS |
| Единый cutoff: raw/staging/staging_run_metadata.csv | PASS |
| Единый cutoff: owner/staging/staging_run_metadata.csv | PASS |
| Каждый клиент owner имеет дату единого среза | PASS |
| membership: каждый SQL fact имеет единый cutoff | PASS |
| membership: операции не позже cutoff | PASS |
| services: каждый SQL fact имеет единый cutoff | PASS |
| services: операции не позже cutoff | PASS |
| Даты каждой услуги совпадают с поштучным аудитом источника | PASS |
| Цена и остатки каждой услуги совпадают с поштучным аудитом | PASS |

Предупреждения (не ошибки):
- problem_4_subrent_visits_left_contract_151350_1_case_20260922.xlsx: ширины столбцов, высоты первых строк или закрепление областей отличаются от июня; требуется просмотр.
- Заявки сохраняют согласованные исключения телефонов: пустых 441, непустых без валидного номера 201. Это не ошибка XLSX; такие телефоны не подходят для фото.

Сверка CSV/TSV доказывает сохранность текущей выгрузки. Независимая проверка исходной SQL-базы выполняется отдельно; этот скрипт не утверждает правильность SQL только на основании совпадения с CSV.
