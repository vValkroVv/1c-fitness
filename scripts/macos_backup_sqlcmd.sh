#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/tmp/macos-backup/mssql-fitness-macos.env"
NETWORK_NAME="${MSSQL_NETWORK_NAME:-fitness-macos-sql}"
SQLCMD_SERVER="${SQLCMD_SERVER:-mssql-fitness-macos,1433}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing SQL Server env file: $ENV_FILE" >&2
  echo "Start SQL Server first with scripts/macos_backup_start_mssql_container.sh" >&2
  exit 2
fi

TARGET_CONTAINER="${SQLCMD_SERVER%%,*}"
if docker ps --format '{{.Names}}' | grep -Fxq "$TARGET_CONTAINER" \
  && docker exec "$TARGET_CONTAINER" test -x /opt/mssql-tools18/bin/sqlcmd >/dev/null 2>&1; then
  ARGS=()
  STDIN_FILE=""
  OUTPUT_FILE=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i)
        if [[ "${2:-}" == /sql/* ]]; then
          STDIN_FILE="$ROOT_DIR/sql/${2#/sql/}"
          ARGS+=("-i" "/dev/stdin")
          shift 2
        else
          ARGS+=("$1" "$2")
          shift 2
        fi
        ;;
      -o)
        if [[ "${2:-}" == /logs/* ]]; then
          OUTPUT_FILE="$ROOT_DIR/logs/${2#/logs/}"
          shift 2
        else
          ARGS+=("$1" "$2")
          shift 2
        fi
        ;;
      *)
        ARGS+=("$1")
        shift
        ;;
    esac
  done

  if [[ -n "$STDIN_FILE" && ! -f "$STDIN_FILE" ]]; then
    echo "SQL file not found: $STDIN_FILE" >&2
    exit 2
  fi

  if [[ -n "$OUTPUT_FILE" ]]; then
    mkdir -p "$(dirname "$OUTPUT_FILE")"
    if [[ -n "$STDIN_FILE" ]]; then
      docker exec -i "$TARGET_CONTAINER" /bin/bash -lc \
        'exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C "$@"' \
        sqlcmd "${ARGS[@]}" < "$STDIN_FILE" > "$OUTPUT_FILE"
    else
      docker exec "$TARGET_CONTAINER" /bin/bash -lc \
        'exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C "$@"' \
        sqlcmd "${ARGS[@]}" > "$OUTPUT_FILE"
    fi
  elif [[ -n "$STDIN_FILE" ]]; then
    docker exec -i "$TARGET_CONTAINER" /bin/bash -lc \
      'exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C "$@"' \
      sqlcmd "${ARGS[@]}" < "$STDIN_FILE"
  else
    docker exec "$TARGET_CONTAINER" /bin/bash -lc \
      'exec /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C "$@"' \
      sqlcmd "${ARGS[@]}"
  fi
  exit $?
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
  /bin/bash -lc 'exec /opt/mssql-tools/bin/sqlcmd -S "$SQLCMD_SERVER" -U sa -P "$MSSQL_SA_PASSWORD" "$@"' \
  sqlcmd "$@"
