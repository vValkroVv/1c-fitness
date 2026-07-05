#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE_OUTPUT_ROOT="${SERVICES_SOURCE_OUTPUT_ROOT:-output/20251115_0800_fix_owner}"
OUTPUT_ROOT="${SERVICES_OUTPUT_ROOT:-output/20251115_0800_fix_owner_new_import}"
DATABASE_NAME="${SERVICES_DATABASE_NAME:-FitnessRestored_20260523_macos}"
SQLCMD_SERVER_NAME="${SERVICES_SQLCMD_SERVER:-mssql-fitness-2022,1433}"
DATE_STAMP="${SERVICES_DATE_STAMP:-20260525_0800}"
LOG_ROOT="${SERVICES_LOG_ROOT:-logs/new-changes/prolem_3}"

mkdir -p "$OUTPUT_ROOT/staging" "$OUTPUT_ROOT/reports" "$LOG_ROOT"

MSSQL_2022_DATABASE_NAME="$DATABASE_NAME" \
MSSQL_2022_MDF_PATH="/restoredata/${DATABASE_NAME}.mdf" \
MSSQL_2022_LDF_PATH="/restoredata/${DATABASE_NAME}_log.ldf" \
  "$ROOT_DIR/scripts/29_start_mssql_2022_attach_macos.sh"

SQLCMD_SERVER="$SQLCMD_SERVER_NAME" \
  "$ROOT_DIR/scripts/macos_backup_sqlcmd.sh" \
  -d "$DATABASE_NAME" \
  -i /sql/54_build_services_import_staging.sql \
  -W \
  -s "|" \
  -o "/${LOG_ROOT}/54_build_services_import_staging.txt"

tr -d '\000' \
  < "$LOG_ROOT/54_build_services_import_staging.txt" \
  > "$LOG_ROOT/54_build_services_import_staging.clean.txt"

read -r -d '' BCP_QUERY <<'SQL' || true
SELECT
    service_order,
    REPLACE(REPLACE(REPLACE(service_name, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS service_name,
    product_ref,
    product_code,
    REPLACE(REPLACE(REPLACE(product_name, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS product_name,
    sale_doc_ref,
    sale_number,
    sale_line_no,
    sale_line_id,
    CONVERT(varchar(19), sale_datetime, 120) AS sale_datetime,
    CONVERT(varchar(10), sale_date, 120) AS sale_date,
    sale_client_ref,
    sale_client_id,
    REPLACE(REPLACE(REPLACE(sale_client_fio, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS sale_client_fio,
    REPLACE(REPLACE(REPLACE(sale_client_phone, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS sale_client_phone,
    linked_service_doc_ref,
    linked_object_rtref,
    service_doc_number,
    CONVERT(varchar(19), service_doc_datetime, 120) AS service_doc_datetime,
    service_doc_holder_ref,
    service_doc_holder_id,
    REPLACE(REPLACE(REPLACE(service_doc_holder_fio, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS service_doc_holder_fio,
    CONVERT(varchar(10), service_start_date, 120) AS service_start_date,
    CONVERT(varchar(10), service_end_date, 120) AS service_end_date,
    service_doc_duration_value,
    service_doc_posted,
    service_doc_marked,
    line_quantity,
    line_total_amount,
    unit_price,
    vat_amount,
    REPLACE(REPLACE(REPLACE(line_comment, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS line_comment,
    rg_duration_days,
    rg_price,
    rg_paid_candidate,
    rg_payment_count_candidate,
    rg_visits_candidate_8007,
    rg_visits_candidate_8008,
    rg_visits_candidate_8009,
    rg3336_receipt_qty,
    rg3336_expense_qty,
    rg3336_signed_balance,
    rg3336_movement_rows,
    rg3336_receipt_rows,
    rg3336_expense_rows,
    has_linked_service_doc,
    is_active_by_balance,
    is_active_by_date,
    is_active_on_cutoff,
    payment_ref,
    CONVERT(varchar(19), payment_datetime, 120) AS payment_datetime,
    payment_amount,
    REPLACE(REPLACE(REPLACE(payment_method, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS payment_method,
    REPLACE(REPLACE(REPLACE(payment_operation, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS payment_operation,
    payment_match_source,
    CONVERT(varchar(19), cutoff_at, 120) AS cutoff_at,
    raw_source
FROM fitbase_part2.services_import_facts
ORDER BY service_order, sale_datetime, sale_doc_ref, sale_line_no
SQL

SQLCMD_SERVER="$SQLCMD_SERVER_NAME" \
  "$ROOT_DIR/scripts/macos_backup_bcp.sh" \
  "$BCP_QUERY" \
  queryout "/output/${OUTPUT_ROOT#output/}/staging/services_import_facts.tsv" \
  -d "$DATABASE_NAME" \
  -w \
  -t $'\t' \
  -r $'\n'

python3 scripts/23_build_services_import_xlsx.py \
  --source-output-dir "$SOURCE_OUTPUT_ROOT" \
  --output-dir "$OUTPUT_ROOT" \
  --date-stamp "$DATE_STAMP"

python3 scripts/24_validate_services_import_xlsx.py \
  --source-output-dir "$SOURCE_OUTPUT_ROOT" \
  --output-dir "$OUTPUT_ROOT" \
  --date-stamp "$DATE_STAMP"
