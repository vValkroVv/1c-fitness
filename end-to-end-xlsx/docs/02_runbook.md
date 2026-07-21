# Что происходит во время запуска

Для обычной работы достаточно команды из README. Этот файл пригодится, если
нужно понять, на каком этапе упал процесс и откуда его продолжить.

## Обычный полный прогон

1. Проверьте `.bak` через `scripts/verify_backup.py`.
2. Восстановите его в SQL Server.
3. Заполните SQL-подключение в `config/pipeline_manager_fixes_20260630.yml`.
4. Задайте `FITNESS_SQL_PASSWORD`.
5. Запустите `scripts/run_pipeline.py --config config/pipeline_manager_fixes_20260630.yml`.
6. Дождитесь `delivery_validate: verdict=PASS`.
7. Заберите десять файлов из `output/20260630_delivery_manager_fixes_v2/`.

На этом всё. Номерные Python-скрипты вручную запускать не нужно.

## Из каких этапов состоит сборка

| Этап | Что происходит | Что остаётся на диске |
| --- | --- | --- |
| `preflight` | Проверка базы, compatibility level и исходных таблиц 1С | `database_preflight.md` |
| `owner_sql` | SQL-стейджинг клиентов, продаж, абонементов, карт и смен владельца | таблицы `fitbase_part2.*` |
| `owner_export` | Выгрузка 13 промежуточных SQL-таблиц | CSV в `work/.../raw/staging/` |
| `reclassify` | Применение согласованных решений по продуктам | `work/.../owner/staging/` |
| `main_xlsx` | Заявки и пластиковые карты плюс их проверка | первые 2 XLSX |
| `membership_sql` | Связи абонементов с продажами, оплатами и возвратами | `membership_import_facts` |
| `membership_export` | Выгрузка 101 436 фактов по абонементам | UTF-16 TSV |
| `membership_xlsx` | Полный импорт абонементов и 119 шаблонов | ещё 2 XLSX |
| `services_sql` | Факты по 51 нужной услуге | `services_import_facts` |
| `services_export` | Выгрузка 50 710 фактов по услугам | UTF-16 TSV |
| `services_xlsx` | Клиентские услуги и шаблоны услуг | ещё 2 XLSX |
| `problem_xlsx` | Отбор трёх финансовых групп спорных договоров | 3 временных XLSX |
| `delivery` | Добавление problem4 для `151350` и удаление 255 спорных договоров из clean | итоговые 6 + 4 XLSX |
| `validate` | Проверка имён, строк, колонок, филиалов и договоров | `validation_report.md` |

## Где виден прогресс

Общий журнал:

```text
logs/20260630_manager_fixes_v2/pipeline.log
```

Состояние запуска в JSON:

```text
work/20260630_manager_fixes_v2/status.json
```

У каждого этапа есть свой файл в `logs/20260630_full_cutoff/`. Если процесс остановился,
сначала смотрите `status.json`, потом лог указанного там этапа. Полный traceback
тоже сохраняется в status.

## Остановиться после конкретного этапа

Это бывает полезно при разборе SQL или промежуточных CSV:

```shell
python scripts/run_pipeline.py --stop-after owner_export
```

В таком режиме программа пишет `PIPELINE STOPPED`, а не `PIPELINE PASS`. Это не
ошибка, просто до финальных XLSX она ещё не дошла.

## Продолжить после сбоя

Например, если поправили проблему на этапе `reclassify`:

```shell
python scripts/run_pipeline.py \
  --resume \
  --start-at reclassify
```

`--resume` не очищает уже созданный `work`. Поэтому начинайте с этапа, для
которого все предыдущие входные файлы точно существуют. Если в этом есть
сомнения, проще сделать полный запуск без `--resume`.

## Передать подключение в командной строке

```shell
python scripts/run_pipeline.py \
  --server 10.0.0.25 \
  --port 1433 \
  --database FitnessRestored \
  --user migration_user
```

Пароль можно прочитать из отдельного локального файла:

```shell
python scripts/run_pipeline.py --password-file /безопасный/путь/sql-password.txt
```

Не кладите этот файл внутрь `end-to-end-xlsx` и тем более в ZIP для заказчика.

## Запустить всё заново

Обычный запуск без `--resume` удаляет старые данные текущего среза из
`work/20260630_manager_fixes_v2`, `logs/20260630_manager_fixes_v2` и папки с готовыми XLSX. Это нужно, чтобы в
новую сборку случайно не попал файл от прошлого запуска.

Полностью очистить рабочие каталоги можно отдельно:

```shell
python scripts/clean_runtime.py
```
