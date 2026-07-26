#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${FITNESS_SQL_PASSWORD:?Set FITNESS_SQL_PASSWORD for the restored SQL database}"

PYTHON_BIN="${PYTHON_BIN:-$ROOT_DIR/.venv/bin/python}"
SQL_SERVER="${FITNESS_SQL_SERVER:-127.0.0.1}"
SQL_PORT="${FITNESS_SQL_PORT:-1433}"
SQL_DATABASE="${FITNESS_SQL_DATABASE:-FitnessRestored}"
DATE_STAMP="20260630"
WORK_NAME="20260630_service_end_dates_fixed_20260727"
SOURCE_DELIVERY="$ROOT_DIR/../output/20260630_delivery_register_debts"
OUTPUT_DIR="$ROOT_DIR/../output/20260630_delivery_service_end_dates_fixed_20260727"
WORK_DIR="$ROOT_DIR/work/$WORK_NAME"
OWNER_NAME="fitbase_active_clients_import_zayavki_${DATE_STAMP}_all_funnels.xlsx"
SERVICE_NAME="fitbase_import_uslugi_clientov_${DATE_STAMP}.xlsx"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "Python environment not found: $PYTHON_BIN" >&2
  exit 2
fi
if [[ ! -f "$SOURCE_DELIVERY/$OWNER_NAME" ]]; then
  echo "Accepted source delivery is missing: $SOURCE_DELIVERY/$OWNER_NAME" >&2
  exit 2
fi
if [[ -d "$OUTPUT_DIR" ]] && [[ -n "$(find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "Immutable corrected delivery already exists: $OUTPUT_DIR" >&2
  exit 2
fi

mkdir -p "$WORK_DIR/owner"
if [[ -f "$WORK_DIR/owner/$OWNER_NAME" ]]; then
  if ! cmp -s "$SOURCE_DELIVERY/$OWNER_NAME" "$WORK_DIR/owner/$OWNER_NAME"; then
    echo "Existing owner input differs from the accepted delivery" >&2
    exit 2
  fi
else
  cp -p "$SOURCE_DELIVERY/$OWNER_NAME" "$WORK_DIR/owner/$OWNER_NAME"
fi

"$PYTHON_BIN" scripts/run_pipeline.py \
  --config config/pipeline_service_end_dates_20260630.yml \
  --server "$SQL_SERVER" \
  --port "$SQL_PORT" \
  --database "$SQL_DATABASE" \
  --start-at services_sql \
  --stop-after services_xlsx \
  --resume

"$PYTHON_BIN" scripts/build_service_end_date_delivery.py \
  --source-delivery "$SOURCE_DELIVERY" \
  --corrected-service "$WORK_DIR/imports/$SERVICE_NAME" \
  --output-dir "$OUTPUT_DIR" \
  --date-stamp "$DATE_STAMP"

cp "$WORK_DIR"/imports/reports/services_* "$OUTPUT_DIR/reports/"

"$PYTHON_BIN" scripts/validate_delivery.py \
  --output-dir "$OUTPUT_DIR" \
  --expected reference/expected_20260630_register_debts.yml \
  --report "$OUTPUT_DIR/reports/structural_validation.md" \
  --json-report "$OUTPUT_DIR/reports/structural_validation.json" \
  --enforce-reference-counts

echo "PASS: $OUTPUT_DIR"
