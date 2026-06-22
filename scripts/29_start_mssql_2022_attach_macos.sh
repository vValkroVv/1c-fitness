#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/tmp/macos-backup/mssql-fitness-macos.env"
DATA_DIR="$ROOT_DIR/mssql-macos/data"
BACKUP_DIR="$ROOT_DIR/data"
CONTAINER_NAME="${MSSQL_2022_CONTAINER_NAME:-mssql-fitness-2022}"
NETWORK_NAME="${MSSQL_NETWORK_NAME:-fitness-macos-sql}"
SYSTEM_VOLUME="${MSSQL_2022_SYSTEM_VOLUME:-fitness_mssql_2022_system}"
HOST_PORT="${MSSQL_2022_HOST_PORT:-11434}"
IMAGE="${MSSQL_2022_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
DATABASE_NAME="${MSSQL_2022_DATABASE_NAME:-FitnessRestored_20260523_macos}"
MDF_PATH="${MSSQL_2022_MDF_PATH:-/restoredata/FitnessRestored_20260523_macos.mdf}"
LDF_PATH="${MSSQL_2022_LDF_PATH:-/restoredata/FitnessRestored_20260523_macos_log.ldf}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing SQL Server env file: $ENV_FILE" >&2
  exit 2
fi

if [[ ! -f "$DATA_DIR/FitnessRestored_20260523_macos.mdf" ]]; then
  echo "Missing restored MDF in $DATA_DIR" >&2
  exit 2
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME" >/dev/null
fi

docker volume create "$SYSTEM_VOLUME" >/dev/null

if ! docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  docker run -d \
    --platform linux/amd64 \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    --memory="${MSSQL_2022_CONTAINER_MEMORY:-6g}" \
    --cpus="${MSSQL_2022_CPUS:-4}" \
    --env-file "$ENV_FILE" \
    -p "127.0.0.1:$HOST_PORT:1433" \
    -v "$SYSTEM_VOLUME:/var/opt/mssql" \
    -v "$DATA_DIR:/restoredata" \
    -v "$BACKUP_DIR:/backup:ro" \
    "$IMAGE" >/dev/null
elif ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  docker start "$CONTAINER_NAME" >/dev/null
fi

docker network connect "$NETWORK_NAME" "$CONTAINER_NAME" >/dev/null 2>&1 || true

for _ in $(seq 1 90); do
  if SQLCMD_SERVER="$CONTAINER_NAME,1433" "$ROOT_DIR/scripts/macos_backup_sqlcmd.sh" -Q "SELECT @@VERSION" >/dev/null 2>&1; then
    break
  fi
  sleep 4
done

SQLCMD_SERVER="$CONTAINER_NAME,1433" "$ROOT_DIR/scripts/macos_backup_sqlcmd.sh" -Q "
IF DB_ID(N'$DATABASE_NAME') IS NULL
BEGIN
    CREATE DATABASE [$DATABASE_NAME]
    ON (FILENAME = N'$MDF_PATH'),
       (FILENAME = N'$LDF_PATH')
    FOR ATTACH;
END;
SELECT name, state_desc, compatibility_level
FROM sys.databases
WHERE name = N'$DATABASE_NAME';
"
