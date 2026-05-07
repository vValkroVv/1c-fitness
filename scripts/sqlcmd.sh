#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/tmp/mssql-fitness.env"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing SQL Server env file: $ENV_FILE" >&2
  echo "Start SQL Server first with scripts/06_start_mssql_container.sh" >&2
  exit 2
fi

docker run --rm \
  --platform linux/amd64 \
  --network host \
  --env-file "$ENV_FILE" \
  -v "$ROOT_DIR/sql:/sql" \
  -v "$ROOT_DIR/logs:/logs" \
  -v "$ROOT_DIR/output:/output" \
  -v "$ROOT_DIR/data:/backup:ro" \
  mcr.microsoft.com/mssql-tools \
  /bin/bash -lc 'exec /opt/mssql-tools/bin/sqlcmd -S "${SQLCMD_SERVER:-127.0.0.1,1433}" -U sa -P "$MSSQL_SA_PASSWORD" "$@"' \
  sqlcmd "$@"
