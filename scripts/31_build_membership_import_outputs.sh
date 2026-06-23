#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOURCE_OUTPUT_ROOT="${MEMBERSHIP_SOURCE_OUTPUT_ROOT:-output/20251115_0800_fix_owner}"
OUTPUT_ROOT="${MEMBERSHIP_OUTPUT_ROOT:-output/20251115_0800_fix_owner_new_import}"
DATABASE_NAME="${MEMBERSHIP_DATABASE_NAME:-FitnessRestored_20260523_macos}"
SQLCMD_SERVER_NAME="${MEMBERSHIP_SQLCMD_SERVER:-mssql-fitness-2022,1433}"
DATE_STAMP="${MEMBERSHIP_DATE_STAMP:-20260525_0800}"

mkdir -p "$OUTPUT_ROOT/staging" "$OUTPUT_ROOT/reports" "logs/new-changes/prolem_2"

"$ROOT_DIR/scripts/29_start_mssql_2022_attach_macos.sh"

SQLCMD_SERVER="$SQLCMD_SERVER_NAME" \
  "$ROOT_DIR/scripts/macos_backup_sqlcmd.sh" \
  -d "$DATABASE_NAME" \
  -i /sql/31_build_membership_import_staging.sql \
  -W \
  -s "|" \
  -o /logs/new-changes/prolem_2/31_build_membership_import_staging.txt

tr -d '\000' \
  < logs/new-changes/prolem_2/31_build_membership_import_staging.txt \
  > logs/new-changes/prolem_2/31_build_membership_import_staging.clean.txt

read -r -d '' BCP_QUERY <<'SQL' || true
SELECT
    client_ref,
    client_id,
    original_client_ref,
    original_client_id,
    REPLACE(REPLACE(REPLACE(original_client_fio, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS original_client_fio,
    effective_client_ref,
    effective_client_id,
    REPLACE(REPLACE(REPLACE(effective_client_fio, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS effective_client_fio,
    owner_change_ref,
    owner_change_number,
    CONVERT(varchar(19), owner_change_datetime, 120) AS owner_change_datetime,
    owner_change_old_client_ref,
    owner_change_new_client_ref,
    REPLACE(REPLACE(REPLACE(owner_change_modifier_name, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS owner_change_modifier_name,
    owner_change_count_for_membership,
    subscription_ref,
    document_number,
    holder_client_ref,
    payer_client_ref,
    client_role_source,
    product_ref,
    product_code,
    REPLACE(REPLACE(REPLACE(subscription_name, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS subscription_name,
    product_class,
    is_full_subscription,
    is_trial_or_guest,
    is_subrent,
    is_limited_subrent,
    CONVERT(varchar(10), sale_date, 120) AS sale_date,
    CONVERT(varchar(19), sale_datetime, 120) AS sale_datetime,
    CONVERT(varchar(10), start_date, 120) AS start_date,
    CONVERT(varchar(10), end_date, 120) AS end_date,
    duration_days,
    status,
    booking_status_ref,
    booking_status_name,
    doc_posted,
    doc_marked,
    register_duration_days,
    is_active_on_cutoff,
    is_finished_before_cutoff,
    days_to_end,
    days_since_end,
    REPLACE(REPLACE(REPLACE(raw_club, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS raw_club,
    normalized_club,
    REPLACE(REPLACE(REPLACE(club_source, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS club_source,
    REPLACE(REPLACE(REPLACE(raw_source, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS raw_source,
    doc_duration_value,
    rg_duration_days,
    rg_freeze_days,
    rg_guests,
    rg_price,
    rg_paid_candidate,
    rg_payment_count_candidate,
    rg_visits_candidate_8007,
    rg_visits_candidate_8008,
    rg_visits_candidate_8009,
    subrent_visit_limit,
    subrent_active_by_dates_on_cutoff,
    subrent_finished_by_dates_before_cutoff,
    subrent_rg3336_receipt_qty,
    subrent_rg3336_expense_qty,
    subrent_rg3336_signed_balance,
    subrent_rg3336_visit_doc_expense_qty,
    subrent_rg3336_receipt_rows,
    subrent_rg3336_expense_rows,
    REPLACE(REPLACE(REPLACE(subrent_rg3336_case_group, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS subrent_rg3336_case_group,
    matched_payment_ref,
    CONVERT(varchar(19), matched_payment_datetime, 120) AS matched_payment_datetime,
    matched_payment_amount,
    REPLACE(REPLACE(REPLACE(matched_payment_method, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS matched_payment_method,
    REPLACE(REPLACE(REPLACE(matched_payment_operation, CHAR(9), N' '), CHAR(10), N' '), CHAR(13), N' ') AS matched_payment_operation,
    matched_payment_match_source,
    CONVERT(varchar(19), cutoff_at, 120) AS cutoff_at
FROM fitbase_part2.membership_import_facts
ORDER BY client_id, sale_datetime, subscription_ref
SQL

SQLCMD_SERVER="$SQLCMD_SERVER_NAME" \
  "$ROOT_DIR/scripts/macos_backup_bcp.sh" \
  "$BCP_QUERY" \
  queryout "/output/${OUTPUT_ROOT#output/}/staging/membership_import_facts.tsv" \
  -d "$DATABASE_NAME" \
  -w \
  -t $'\t' \
  -r $'\n'

python3 scripts/19_build_membership_import_xlsx.py \
  --source-output-dir "$SOURCE_OUTPUT_ROOT" \
  --output-dir "$OUTPUT_ROOT" \
  --date-stamp "$DATE_STAMP"

python3 scripts/20_validate_membership_import_xlsx.py \
  --source-output-dir "$SOURCE_OUTPUT_ROOT" \
  --output-dir "$OUTPUT_ROOT" \
  --date-stamp "$DATE_STAMP"
