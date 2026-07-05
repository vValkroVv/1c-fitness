# Новый backup 2026-06-30: команды пересборки

## 1. Owner-change / import_заявки / пластиковые карты

```bash
OWNER_FIX_OUTPUT_ROOT=output/20260630_fix_owner \
OWNER_FIX_DATABASE_NAME=FitnessRestored_20260630_macos \
OWNER_FIX_SQLCMD_SERVER=mssql-fitness-2022,1433 \
OWNER_FIX_CUTOFF_DATE=2026-06-30 \
OWNER_FIX_CUTOFF_AT="2026-06-30 23:27:03" \
OWNER_FIX_BACKUP_FINISH_AT="2026-06-30 23:27:03" \
OWNER_FIX_DATE_STAMP=20260630 \
OWNER_FIX_RUN_LABEL=20260630_fix_owner_raw \
OWNER_FIX_LOGS_DIR=logs/new-backup-30-06/owner_change \
scripts/30_build_owner_change_fix_outputs.sh
```

## 2. Импорт абонементов

```bash
MEMBERSHIP_SOURCE_OUTPUT_ROOT=output/20260630_fix_owner \
MEMBERSHIP_OUTPUT_ROOT=output/20260630_fix_owner_new_import \
MEMBERSHIP_DATABASE_NAME=FitnessRestored_20260630_macos \
MEMBERSHIP_SQLCMD_SERVER=mssql-fitness-2022,1433 \
MEMBERSHIP_DATE_STAMP=20260630 \
MEMBERSHIP_LOG_ROOT=logs/new-backup-30-06/membership \
scripts/31_build_membership_import_outputs.sh
```

## 3. Импорт услуг

```bash
SERVICES_SOURCE_OUTPUT_ROOT=output/20260630_fix_owner \
SERVICES_OUTPUT_ROOT=output/20260630_fix_owner_new_import \
SERVICES_DATABASE_NAME=FitnessRestored_20260630_macos \
SERVICES_SQLCMD_SERVER=mssql-fitness-2022,1433 \
SERVICES_DATE_STAMP=20260630 \
SERVICES_LOG_ROOT=logs/new-backup-30-06/services \
scripts/32_build_services_import_outputs.sh
```

## 4. Active-problem XLSX

```bash
ACTIVE_PROBLEM_OUTPUT_DIR=output/20260630_fix_owner_new_import \
ACTIVE_PROBLEM_DATE_STAMP=20260630 \
ACTIVE_PROBLEM_CUTOFF_DATE=2026-06-30 \
python3 scripts/36_build_active_problem_case_workbooks.py
```
