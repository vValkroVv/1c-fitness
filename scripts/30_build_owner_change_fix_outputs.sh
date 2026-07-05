#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_ROOT="${OWNER_FIX_OUTPUT_ROOT:-output/20251115_0800_fix_owner}"
DATABASE_NAME="${OWNER_FIX_DATABASE_NAME:-FitnessRestored_20260523_macos}"
SQLCMD_SERVER_NAME="${OWNER_FIX_SQLCMD_SERVER:-mssql-fitness-2022,1433}"
CUTOFF_DATE="${OWNER_FIX_CUTOFF_DATE:-2026-05-25}"
CUTOFF_AT="${OWNER_FIX_CUTOFF_AT:-2026-05-25 08:00:00}"
BACKUP_FINISH_AT="${OWNER_FIX_BACKUP_FINISH_AT:-2026-05-23 23:17:17}"
DATE_STAMP="${OWNER_FIX_DATE_STAMP:-20260525_0800}"
RUN_LABEL="${OWNER_FIX_RUN_LABEL:-20251115_0800_fix_owner_raw}"
LOGS_DIR="${OWNER_FIX_LOGS_DIR:-logs}"

MSSQL_2022_DATABASE_NAME="$DATABASE_NAME" \
MSSQL_2022_MDF_PATH="/restoredata/${DATABASE_NAME}.mdf" \
MSSQL_2022_LDF_PATH="/restoredata/${DATABASE_NAME}_log.ldf" \
  "$ROOT_DIR/scripts/29_start_mssql_2022_attach_macos.sh"

PART2_SQLCMD=scripts/macos_backup_sqlcmd.sh \
SQLCMD_SERVER="$SQLCMD_SERVER_NAME" \
scripts/11_export_part2_stage.py \
  --database "$DATABASE_NAME" \
  --cutoff-date "$CUTOFF_DATE" \
  --cutoff-at "$CUTOFF_AT" \
  --backup-finish-at "$BACKUP_FINISH_AT" \
  --output-run-label "$RUN_LABEL" \
  --output-dir "$OUTPUT_ROOT/raw/staging" \
  --reports-dir "$OUTPUT_ROOT/raw/reports" \
  --logs-dir "$LOGS_DIR"

scripts/16_reclassify_part2_from_csv.py \
  --cutoff-date "$CUTOFF_DATE" \
  --cutoff-at "$CUTOFF_AT" \
  --source-stage-dir "$OUTPUT_ROOT/raw/staging" \
  --source-reports-dir "$OUTPUT_ROOT/raw/reports" \
  --output-stage-dir "$OUTPUT_ROOT/staging" \
  --output-reports-dir "$OUTPUT_ROOT/reports" \
  --decisions config/product_reclassification_decisions.csv

rm -f \
  "$OUTPUT_ROOT/fitbase_active_clients_import_zayavki_${DATE_STAMP}__all_funnels.xlsx" \
  "$OUTPUT_ROOT/fitbase_active_clients_import_zayavki_${DATE_STAMP}_all_funnels.xlsx" \
  "$OUTPUT_ROOT/fitbase_active_clients_plastic_cards_${DATE_STAMP}__all_funnels.xlsx" \
  "$OUTPUT_ROOT/fitbase_active_clients_plastic_cards_${DATE_STAMP}_all_funnels.xlsx"

python3 scripts/17_build_part2_combined_xlsx.py \
  --cutoff-date "$CUTOFF_DATE" \
  --date-stamp "$DATE_STAMP" \
  --stage-dir "$OUTPUT_ROOT/staging" \
  --output-dir "$OUTPUT_ROOT" \
  --reports-dir "$OUTPUT_ROOT/reports" \
  --csv-dir "$OUTPUT_ROOT/csv" \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --managers-config config/managers_by_club.yml \
  --branches-config config/branches_by_club.yml \
  --fitbase-label-mode customer_20260520_single_stage \
  --main-require-phone-for-new-applications \
  --main-transfer-new-applications-to-memberships \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription

python3 scripts/18_validate_combined_single_stage_outputs.py \
  --cutoff-date "$CUTOFF_DATE" \
  --date-stamp "$DATE_STAMP" \
  --stage-dir "$OUTPUT_ROOT/staging" \
  --output-dir "$OUTPUT_ROOT" \
  --reports-dir "$OUTPUT_ROOT/reports" \
  --main-template "task-desc/Копия Импорт_заявки.xlsx" \
  --cards-template "task-desc/Пластиковая карта.xlsx" \
  --branches-config config/branches_by_club.yml \
  --main-require-phone-for-new-applications \
  --main-transfer-new-applications-to-memberships \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription

mv -f \
  "$OUTPUT_ROOT/fitbase_active_clients_import_zayavki_${DATE_STAMP}__all_funnels.xlsx" \
  "$OUTPUT_ROOT/fitbase_active_clients_import_zayavki_${DATE_STAMP}_all_funnels.xlsx"
mv -f \
  "$OUTPUT_ROOT/fitbase_active_clients_plastic_cards_${DATE_STAMP}__all_funnels.xlsx" \
  "$OUTPUT_ROOT/fitbase_active_clients_plastic_cards_${DATE_STAMP}_all_funnels.xlsx"
