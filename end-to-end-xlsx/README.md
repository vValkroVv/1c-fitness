# Выгрузка 9 XLSX из backup Fitness

Эта папка собирает девять файлов для импорта в Fitbase из базы 1С Fitness.
Результат повторяет проверенную выгрузку от 30 июня 2026 года: шесть обычных
XLSX и три отдельных файла с договорами, которые нужно разобрать вручную.

Если вы открыли проект впервые, разбираться во всех номерных скриптах не надо.
Для обычного запуска нужны три вещи:

1. настройки подключения в `config/pipeline.yml`;
2. команда `python scripts/run_pipeline.py`;
3. готовые файлы в `output/20260630_delivery_without_active_problems/`.

Я специально оставил один нормальный вход: `run_pipeline.py`. Остальные
скрипты запускает он сам, вручную их обычно не трогают.

## Что лежит в папке

```text
end-to-end-xlsx/
├── README.md                     эта инструкция
├── requirements.txt             версии Python-библиотек
│
├── config/                       настройки и согласованные бизнес-правила
│   ├── pipeline.yml              подключение к SQL Server и даты срезов
│   ├── branches_by_club.yml      соответствие клуба филиалу Fitbase
│   ├── managers_by_club.yml      менеджеры по клубам
│   └── product_reclassification_decisions.csv  ручные решения по продуктам
│
├── scripts/
│   ├── run_pipeline.py           главный скрипт, запускать его
│   ├── verify_backup.py          проверка размера и SHA-256 backup
│   ├── clean_runtime.py          удаление созданных work/logs/output
│   ├── create_release_zip.py     ZIP без данных клиентов и паролей
│   ├── database.py               подключение к SQL Server и экспорт данных
│   └── остальные *.py            внутренние этапы сборки и проверки XLSX
│
├── sql/                          запросы к восстановленной базе 1С
├── templates/                    семь исходных XLSX-шаблонов Fitbase
├── reference/                    контрольные числа для backup 2026-06-30
├── docs/                         подробности по restore, полям и правилам
│
├── work/                         промежуточные CSV, TSV и отчёты
├── logs/                         логи SQL и Python
└── output/                       готовые девять XLSX
```

Каталоги `work`, `logs` и `output` до первого запуска почти пустые. Это
нормально. Пайплайн создаст в них нужные подпапки сам.

### Что можно менять

Для запуска на восстановленной копии того же backup обычно меняют только блок
`sql` в `config/pipeline.yml` и задают пароль через переменную среды.

Даты срезов, SQL, шаблоны и CSV с классификацией продуктов менять не стоит.
Именно на этих файлах получена и проверена выгрузка `20260630`. Если изменить
их, результат уже не обязан совпасть с контрольными девятью файлами.

### Где искать результат и ошибки

| Что нужно | Где лежит |
| --- | --- |
| готовые XLSX | `output/20260630_delivery_without_active_problems/` |
| итоговый отчёт | `work/20260630/reports/validation_report.md` |
| последний выполненный этап | `work/20260630/status.json` |
| общий лог | `logs/20260630/pipeline.log` |
| лог конкретного этапа | `logs/20260630/<имя_этапа>.log` |

## Что требуется на входе

Нужен файл `Fitnes-30-06-26.bak`, восстановленный в Microsoft SQL Server.
Способ восстановления не важен: SSMS, T-SQL, Docker или отдельный сервер. Сам
пакет SQL Server не устанавливает и backup не восстанавливает, потому что пути
к MDF/LDF и устройство среды везде разные.

После restore база должна быть доступна по TCP. Также понадобятся:

- SQL-логин с доступом к восстановленной базе;
- `SELECT` на исходные таблицы `dbo`;
- право создавать и удалять служебные таблицы в схеме `fitbase_part2`;
- Python 3.11 или 3.12;
- 2-3 ГБ свободного места под промежуточные файлы.

Лучше работать с отдельной восстановленной копией, а не с рабочей базой 1С.
Исходные таблицы пайплайн не меняет, но служебную схему `fitbase_part2`
пересоздаёт при каждом полном запуске.

## Быстрый запуск

Все команды ниже выполняются из корня `end-to-end-xlsx`.

### 1. Создать Python-окружение

```shell
python -m venv .venv
```

Linux или macOS:

```shell
.venv/bin/python -m pip install -r requirements.txt
```

Windows PowerShell:

```powershell
.venv\Scripts\python.exe -m pip install -r requirements.txt
```

ODBC, `sqlcmd` и `bcp` не нужны. Скрипт подключается к SQL Server через
Python-библиотеку `python-tds`.

### 2. Указать SQL Server

Откройте `config/pipeline.yml` и заполните блок `sql`:

```yaml
sql:
  server: "127.0.0.1"
  port: 1433
  database: "FitnessRestored"
  user: "sa"
  password_env: "FITNESS_SQL_PASSWORD"
```

Пароля в конфиге быть не должно. Перед запуском положите его в переменную
`FITNESS_SQL_PASSWORD`.

Linux или macOS:

```shell
export FITNESS_SQL_PASSWORD='ваш-пароль'
```

Windows PowerShell:

```powershell
$env:FITNESS_SQL_PASSWORD = 'ваш-пароль'
```

Если SQL Server находится не на этой машине, подключайтесь к нему через
закрытую сеть или VPN. Для подключения с проверкой сертификата в конфиге есть
параметры `tls_ca_file` и `tls_validate_host`.

### 3. Запустить сборку

Linux или macOS:

```shell
.venv/bin/python scripts/run_pipeline.py
```

Windows PowerShell:

```powershell
.venv\Scripts\python.exe scripts\run_pipeline.py
```

Адрес базы можно передать прямо в командной строке. Это удобно, если не хочется
править YAML:

```shell
python scripts/run_pipeline.py \
  --server sql.example.local \
  --port 1433 \
  --database FitnessRestored \
  --user sa
```

В конце нормального прогона будут две строки:

```text
delivery_validate: verdict=PASS
PIPELINE PASS delivery=.../output/20260630_delivery_without_active_problems
```

Если `PASS` нет, файлы заказчику передавать рано. Сначала откройте
`work/20260630/status.json`, затем лог упавшего этапа в `logs/20260630/`.

## Какие файлы получатся

| Файл | Строк данных |
| --- | ---: |
| `fitbase_active_clients_import_zayavki_20260630_all_funnels.xlsx` | 39 524 |
| `fitbase_active_clients_plastic_cards_20260630_all_funnels.xlsx` | 10 907 |
| `fitbase_import_abonementy_clientov_20260630.xlsx` | 119 817 |
| `fitbase_import_shablony_abonementov_20260630.xlsx` | 114 |
| `fitbase_import_shablony_uslug_20260630.xlsx` | 51 |
| `fitbase_import_uslugi_clientov_20260630.xlsx` | 522 |
| `problem_1_no_payment_cash_3_cases_20260630.xlsx` | 3 |
| `problem_2_zero_price_direct_full_41_cases_20260630.xlsx` | 41 |
| `problem_3_non_named_payment_left_179_cases_20260630.xlsx` | 179 |

В чистом файле абонементов нет 223 договоров из трёх проблемных файлов. Эти
договоры не потеряны: они лежат рядом отдельными XLSX, чтобы их можно было
разобрать вручную.

## Проверка исходного backup

Для точного повторения нужен именно этот файл:

```text
name:   Fitnes-30-06-26.bak
size:   13137564672 bytes
sha256: 7e684086442f0eeac44014b9f5170da5c2873620c57788dbc59f58efed1d0810
```

Проверить его можно так:

```shell
python scripts/verify_backup.py /путь/к/Fitnes-30-06-26.bak
```

До restore нужно также выполнить `RESTORE HEADERONLY`, `RESTORE FILELISTONLY`
и `RESTORE VERIFYONLY`. Команды и ожидаемые значения записаны в
[`docs/01_restore_contract.md`](docs/01_restore_contract.md).

## Если запуск прервался

Повторный запуск без параметров очищает предыдущие промежуточные данные для
этого среза и начинает работу заново.

Чтобы продолжить с конкретного этапа, используйте `--resume`:

```shell
python scripts/run_pipeline.py \
  --resume \
  --start-at membership_sql
```

Список этапов:

```shell
python scripts/run_pipeline.py --help
```

Параметр `--skip-reference-counts` нужен только для исследования другого
backup. С ним структура файлов всё ещё проверяется, но точные количества строк
не сверяются. Такой результат уже не повторяет выгрузку `20260630`.

## Как подготовить папку к передаче

После тестового запуска в `work`, `logs` и `output` остаются данные клиентов.
Удалить их можно одной командой:

```shell
python scripts/clean_runtime.py
```

Чтобы не собирать ZIP вручную, используйте:

```shell
python scripts/create_release_zip.py
```

Скрипт не кладёт в архив `.bak`, пароли, логи, промежуточные CSV/TSV и готовые
XLSX. В ZIP остаются только код, настройки, шаблоны и документация.

## Документы по отдельным темам

- [`docs/01_restore_contract.md`](docs/01_restore_contract.md): какой backup
  нужен и что проверить после restore;
- [`docs/02_runbook.md`](docs/02_runbook.md): этапы пайплайна и продолжение
  после сбоя;
- [`docs/03_business_rules.md`](docs/03_business_rules.md): правила воронок,
  абонементов, услуг и трёх проблемных групп;
- [`docs/04_source_mapping.md`](docs/04_source_mapping.md): физические таблицы и
  поля 1С;
- [`docs/05_validation.md`](docs/05_validation.md): что именно проверяют
  валидаторы;
- [`docs/06_troubleshooting.md`](docs/06_troubleshooting.md): типичные ошибки и
  куда смотреть;
- [`docs/07_package_manifest.md`](docs/07_package_manifest.md): полный список
  файлов пакета.
