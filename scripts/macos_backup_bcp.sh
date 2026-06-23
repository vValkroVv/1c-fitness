#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/tmp/macos-backup/mssql-fitness-macos.env"
NETWORK_NAME="${MSSQL_NETWORK_NAME:-fitness-macos-sql}"
SQLCMD_SERVER="${SQLCMD_SERVER:-mssql-fitness-macos,1433}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing SQL Server env file: $ENV_FILE" >&2
  echo "Start SQL Server first with scripts/macos_backup_start_mssql_container.sh or scripts/29_start_mssql_2022_attach_macos.sh" >&2
  exit 2
fi

docker run --rm \
  --platform linux/amd64 \
  --network "$NETWORK_NAME" \
  --env-file "$ENV_FILE" \
  -e "SQLCMD_SERVER=$SQLCMD_SERVER" \
  -v "$ROOT_DIR/sql:/sql:ro" \
  -v "$ROOT_DIR/logs:/logs" \
  -v "$ROOT_DIR/output:/output" \
  -v "$ROOT_DIR/data:/backup:ro" \
  mcr.microsoft.com/mssql-tools \
  /bin/bash -lc 'exec /opt/mssql-tools/bin/bcp "$@" -S "$SQLCMD_SERVER" -U sa -P "$MSSQL_SA_PASSWORD"' \
  bcp "$@"
