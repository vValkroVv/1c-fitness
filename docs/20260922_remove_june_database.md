# Удаление июньской восстановленной базы — 22.09.2026

По прямому указанию пользователя удалена только база `FitnessRestored_20260630_original`, восстановленная из `data/Fitnes-30-06-26.bak`. Перед DROP DATABASE проверены UUID июньского backup в истории последнего полного восстановления и отсутствие подключений к удаляемой базе.

SQL Server удалил связанные MDF/LDF: `FitnessRestored_20260630_original_1.mdf` и `FitnessRestored_20260630_original_2.ldf`. Их суммарный размер составлял 84 104 183 808 байт (78,33 GiB). Отсутствие файлов проверено.

Сентябрьская база `FitnessRestored_20260630_macos` сохранена: ONLINE, MULTI_USER; контрольное чтение `_AccumRg3305` вернуло 799 437 строк. Запросов на изменение этой базы не выполнялось. Контейнер и общие runtime/секреты сохранены.

Все файлы в `data/` сохранены; перечень, размеры и mtime до и после совпали. Итоговые поставки в `output/`, исходные скрипты и исторические отчёты сохранены.

Удалены подтверждённые июньские временные копии пакета, превью и промежуточная поставка из `tmp/`:

- `tmp/20260630_delivery_service_end_dates_pre_audit_fix_20260727`
- `tmp/end-to-end-xlsx-20260630-full-cutoff-release-test`
- `tmp/end-to-end-xlsx-20260630-full-cutoff-release-test.zip`
- `tmp/end-to-end-xlsx-final-audit`
- `tmp/end-to-end-xlsx-final-audit.zip`
- `tmp/end-to-end-xlsx-humanized-audit`
- `tmp/end-to-end-xlsx-humanized-audit.zip`
- `tmp/end-to-end-xlsx-humanized-final`
- `tmp/end-to-end-xlsx-humanized-final.zip`
- `tmp/end-to-end-xlsx-nested-test.zip`
- `tmp/end-to-end-xlsx-release-test`
- `tmp/end-to-end-xlsx-test.zip`
- `tmp/preview_20260630_full_cutoff_20260714`
- `tmp/preview_20260630_full_cutoff_final_20260714`
- `tmp/service_end_dates_quicklook.AdlQ1p`

Общий размер удалённых временных файлов: 42,340,465 байт. Прочие временные файлы, включая сентябрьские и общие окружения, сохранены.

Подробный журнал и контрольный инвентарь: `logs/20260922_remove_june_database.json`.

После удаления `du -sh mssql-macos/data` показывает 78 GiB вместо 157 GiB, `tmp/` — 88 MiB вместо 129 MiB. При этом `df` пока не показывает возврат места в свободное пространство тома (доступно около 6 GiB). Причина удержания блоков не установлена; снимки APFS, Docker и прочие данные не удалялись.

## Причина удержания места установлена

Повторная диагностика `lsof -nP +L1` обнаружила оба удалённых июньских файла открытыми в процессе `com.apple.Virtualization.VirtualMachine`, PID 64159: дескриптор 38r — MDF 80 404 807 680 байт; 41r — LDF 3 699 376 128 байт. У обоих NLINK=0: файлы удалены, но блоки удерживаются открытыми дескрипторами виртуальной машины. Снимков APFS на томе Data нет; Docker.raw физически занимает 8,3 GiB. Для возврата места требуется закрытие этих дескрипторов; перезапуск Docker Desktop в этой диагностике не выполнялся, поскольку прервёт работу остальных контейнеров и сентябрьской базы.

## Перезапуск Docker по разрешению пользователя

Выполнен `docker desktop restart`. Контейнер PostgreSQL `cpaas-rag-v3-postgres-1` поднялся автоматически и прошёл healthcheck. `mssql-fitness-2022` запущен командой `docker start`. Сентябрьская база ONLINE, MULTI_USER; контрольное чтение вернуло 799 437 строк. Отсутствие июньской базы проверено через DB_ID. Два контейнера PostgreSQL v4/v5, остановленные шесть недель назад, оставлены в исходном состоянии.

Свободное место по `df -h` увеличилось с 5,5 GiB до 89 GiB. Сентябрьские данные и файлы backup не удалялись. Проверки SQL сохранены в `logs/20260922_docker_restart_checks.txt`.
