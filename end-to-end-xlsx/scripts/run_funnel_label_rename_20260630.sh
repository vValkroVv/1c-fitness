#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
DATE_STAMP="20260630"
WORK_NAME="20260630_funnel_labels_20260820"
SOURCE_OWNER_WORK="$ROOT_DIR/work/20260630_register_debts/owner"
SOURCE_DELIVERY="$ROOT_DIR/../output/20260630_delivery_service_end_dates_fixed_20260727"
WORK_DIR="$ROOT_DIR/work/$WORK_NAME"
WORK_OWNER="$WORK_DIR/owner"
OUTPUT_DIR="$ROOT_DIR/../output/20260630_delivery_funnel_labels_20260820"
LOG_DIR="$ROOT_DIR/logs/$WORK_NAME"
OWNER_DOUBLE="fitbase_active_clients_import_zayavki_${DATE_STAMP}__all_funnels.xlsx"
OWNER_NAME="fitbase_active_clients_import_zayavki_${DATE_STAMP}_all_funnels.xlsx"
CARDS_DOUBLE="fitbase_active_clients_plastic_cards_${DATE_STAMP}__all_funnels.xlsx"
CARDS_NAME="fitbase_active_clients_plastic_cards_${DATE_STAMP}_all_funnels.xlsx"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Python environment not found: $PYTHON_BIN" >&2
  exit 2
fi
if [[ ! -f "$SOURCE_OWNER_WORK/staging/final_funnel_clients.csv" ]]; then
  echo "Accepted owner staging is missing: $SOURCE_OWNER_WORK/staging/final_funnel_clients.csv" >&2
  exit 2
fi
if [[ ! -f "$SOURCE_DELIVERY/$OWNER_NAME" ]]; then
  echo "Accepted source delivery is missing: $SOURCE_DELIVERY/$OWNER_NAME" >&2
  exit 2
fi
if [[ -d "$WORK_DIR" ]] && [[ -n "$(find "$WORK_DIR" -mindepth 1 -print -quit)" ]]; then
  echo "Immutable label work directory already exists: $WORK_DIR" >&2
  exit 2
fi
if [[ -d "$OUTPUT_DIR" ]] && [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -print -quit)" ]]; then
  echo "Immutable label delivery already exists: $OUTPUT_DIR" >&2
  exit 2
fi

mkdir -p "$LOG_DIR" "$WORK_OWNER"
exec > >(tee "$LOG_DIR/pipeline.log") 2>&1

cp -Rp "$SOURCE_OWNER_WORK/staging" "$WORK_OWNER/staging"
cp -Rp "$SOURCE_OWNER_WORK/reports" "$WORK_OWNER/reports"
cp -Rp "$SOURCE_OWNER_WORK/csv" "$WORK_OWNER/csv"

"$PYTHON_BIN" scripts/17_build_part2_combined_xlsx.py \
  --cutoff-date "2026-06-30" \
  --date-stamp "$DATE_STAMP" \
  --stage-dir "$WORK_OWNER/staging" \
  --output-dir "$WORK_OWNER" \
  --reports-dir "$WORK_OWNER/reports" \
  --csv-dir "$WORK_OWNER/csv" \
  --main-template "$ROOT_DIR/templates/import_zayavki.xlsx" \
  --cards-template "$ROOT_DIR/templates/plastic_cards.xlsx" \
  --managers-config "$ROOT_DIR/config/managers_by_club.yml" \
  --branches-config "$ROOT_DIR/config/branches_by_club.yml" \
  --fitbase-label-mode "customer_20260520_single_stage" \
  --main-require-phone-for-new-applications \
  --main-transfer-new-applications-to-memberships \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription

"$PYTHON_BIN" scripts/18_validate_combined_single_stage_outputs.py \
  --cutoff-date "2026-06-30" \
  --date-stamp "$DATE_STAMP" \
  --stage-dir "$WORK_OWNER/staging" \
  --output-dir "$WORK_OWNER" \
  --reports-dir "$WORK_OWNER/reports" \
  --main-template "$ROOT_DIR/templates/import_zayavki.xlsx" \
  --cards-template "$ROOT_DIR/templates/plastic_cards.xlsx" \
  --branches-config "$ROOT_DIR/config/branches_by_club.yml" \
  --main-require-phone-for-new-applications \
  --main-transfer-new-applications-to-memberships \
  --cards-funnel-filter "Действующие клиенты" \
  --dedupe-by-phone-keep-latest-subscription

mv "$WORK_OWNER/$OWNER_DOUBLE" "$WORK_OWNER/$OWNER_NAME"
mv "$WORK_OWNER/$CARDS_DOUBLE" "$WORK_OWNER/$CARDS_NAME"

"$PYTHON_BIN" scripts/build_funnel_label_delivery.py \
  --source-delivery "$SOURCE_DELIVERY" \
  --corrected-owner "$WORK_OWNER/$OWNER_NAME" \
  --output-dir "$OUTPUT_DIR" \
  --date-stamp "$DATE_STAMP"

cp -p "$WORK_OWNER/reports/validation_report.md" \
  "$OUTPUT_DIR/reports/funnel_label_owner_validation.md"
cp -p "$WORK_OWNER/reports/fitbase_funnel_distribution.csv" \
  "$OUTPUT_DIR/reports/funnel_label_funnel_distribution.csv"
cp -p "$WORK_OWNER/reports/single_stage_distribution.csv" \
  "$OUTPUT_DIR/reports/funnel_label_single_stage_distribution.csv"

"$PYTHON_BIN" scripts/validate_delivery.py \
  --output-dir "$OUTPUT_DIR" \
  --expected reference/expected_20260630_register_debts.yml \
  --report "$OUTPUT_DIR/reports/structural_validation.md" \
  --json-report "$OUTPUT_DIR/reports/structural_validation.json" \
  --enforce-reference-counts

echo "PASS: $OUTPUT_DIR"
