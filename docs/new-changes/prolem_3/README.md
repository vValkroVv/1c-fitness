# Отчеты по проблеме 3

Сюда складывать все отчеты при выполнении плана:

- `docs/new-changes/03_services_import_plan.md`

Ожидаемые материалы: SQL-discovery, coverage по 51 услуге, fallback по
историческим примерам, список услуг без данных, итоговая валидация XLSX услуг.

Текущая реализация:

- `00_execution_log.md` - ход выполнения и основные счетчики.
- `01_sql_discovery_services.md` - найденные SQL-источники услуг.
- `02_implementation_and_validation.md` - скрипты, итоговые XLSX и validation.
- `03_active_services_focus.md` - отдельный разбор текущих активных услуг,
  потому что это самая важная часть задачи.
- `04_services_manual_review_examples.md` - состав тестового XLSX на 20 строк
  для ручной проверки активных и исторических услуг.

Основной воспроизводимый запуск:

```bash
scripts/32_build_services_import_outputs.sh
```
