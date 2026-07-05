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

TARGET_CONTAINER="${SQLCMD_SERVER%%,*}"
if docker ps --format '{{.Names}}' | grep -Fxq "$TARGET_CONTAINER" \
  && docker exec "$TARGET_CONTAINER" test -x /opt/mssql-tools18/bin/bcp >/dev/null 2>&1; then
  ARGS=("$@")
  OUTPUT_FILE=""
  CONTAINER_OUTPUT_FILE=""

  for idx in "${!ARGS[@]}"; do
    if [[ "${ARGS[$idx]}" == "queryout" ]]; then
      next_idx=$((idx + 1))
      if [[ "${ARGS[$next_idx]:-}" == /output/* ]]; then
        OUTPUT_FILE="$ROOT_DIR/output/${ARGS[$next_idx]#/output/}"
        CONTAINER_OUTPUT_FILE="/tmp/bcp_${TARGET_CONTAINER}_$$_${next_idx}.out"
        ARGS[$next_idx]="$CONTAINER_OUTPUT_FILE"
      fi
      break
    fi
  done

  if [[ -n "$OUTPUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
  fi

  docker exec "$TARGET_CONTAINER" /bin/bash -lc \
    'exec /opt/mssql-tools18/bin/bcp "$@" -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -u' \
    bcp "${ARGS[@]}"

  if [[ -n "$OUTPUT_FILE" ]]; then
    docker cp "$TARGET_CONTAINER:$CONTAINER_OUTPUT_FILE" "$OUTPUT_FILE"
    docker exec "$TARGET_CONTAINER" rm -f "$CONTAINER_OUTPUT_FILE" >/dev/null 2>&1 || true
  fi
  exit 0
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
