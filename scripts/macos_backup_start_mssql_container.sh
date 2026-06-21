#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs/macos-backup"
TMP_DIR="$ROOT_DIR/tmp/macos-backup"
MSSQL_DIR="$ROOT_DIR/mssql-macos"
BACKUP_DIR="$ROOT_DIR/data"
ENV_FILE="$TMP_DIR/mssql-fitness-macos.env"

CONTAINER_NAME="${MSSQL_CONTAINER_NAME:-mssql-fitness-macos}"
NETWORK_NAME="${MSSQL_NETWORK_NAME:-fitness-macos-sql}"
BACKUP_FILE="${MSSQL_BACKUP_FILE:-Fitnes-23-05-26.bak}"
IMAGE="${MSSQL_IMAGE:-mcr.microsoft.com/azure-sql-edge:latest}"
MSSQL_PLATFORM="${MSSQL_PLATFORM:-linux/arm64/v8}"
HOST_PORT="${MSSQL_HOST_PORT:-11433}"
CONTAINER_MEMORY="${MSSQL_CONTAINER_MEMORY:-6g}"
SQL_MEMORY_LIMIT_MB="${MSSQL_MEMORY_LIMIT_MB:-4096}"
MSSQL_CPUS="${MSSQL_CPUS:-6}"
MSSQL_CAP_ADD="${MSSQL_CAP_ADD:-SYS_PTRACE}"
MSSQL_DATA_VOLUME="${MSSQL_DATA_VOLUME:-}"

mkdir -p "$LOG_DIR" "$TMP_DIR"

if [[ ! -f "$BACKUP_DIR/$BACKUP_FILE" ]]; then
  echo "Backup file not found: $BACKUP_DIR/$BACKUP_FILE" >&2
  exit 2
fi

if [[ ! -f "$ENV_FILE" ]]; then
  python3 - <<PY
from pathlib import Path
import secrets

alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%"
password = "Sql2026!" + "".join(secrets.choice(alphabet) for _ in range(24))
path = Path("$ENV_FILE")
path.write_text("\\n".join([
    "ACCEPT_EULA=Y",
    f"MSSQL_SA_PASSWORD={password}",
    "MSSQL_PID=Developer",
    "MSSQL_MEMORY_LIMIT_MB=$SQL_MEMORY_LIMIT_MB",
]) + "\\n")
path.chmod(0o600)
PY
fi

DATA_VOLUME_ARGS=()
if [[ -n "$MSSQL_DATA_VOLUME" ]]; then
  docker volume create "$MSSQL_DATA_VOLUME" > "$LOG_DIR/docker_volume_${CONTAINER_NAME}.txt"
  DATA_VOLUME_ARGS=(-v "$MSSQL_DATA_VOLUME:/var/opt/mssql")
else
  mkdir -p "$MSSQL_DIR"
  chmod -R u+rwX,g+rwX,o+rwX "$MSSQL_DIR"
  DATA_VOLUME_ARGS=(-v "$MSSQL_DIR:/var/opt/mssql")
fi

if ! docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
  docker network create "$NETWORK_NAME" > "$LOG_DIR/docker_network_create.txt"
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  if ! docker ps --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
    docker start "$CONTAINER_NAME" | tee "$LOG_DIR/docker_start_existing.txt"
  fi
  docker ps --filter "name=$CONTAINER_NAME" | tee "$LOG_DIR/docker_ps_mssql_macos.txt"
  exit 0
fi

docker run -d \
  --platform "$MSSQL_PLATFORM" \
  --name "$CONTAINER_NAME" \
  --hostname "$CONTAINER_NAME" \
  --network "$NETWORK_NAME" \
  --memory="$CONTAINER_MEMORY" \
  --cpus="$MSSQL_CPUS" \
  --cap-add "$MSSQL_CAP_ADD" \
  --env-file "$ENV_FILE" \
  -p "127.0.0.1:$HOST_PORT:1433" \
  "${DATA_VOLUME_ARGS[@]}" \
  -v "$BACKUP_DIR:/backup:ro" \
  "$IMAGE" \
  2>&1 | tee "$LOG_DIR/docker_run_mssql_macos.log"

docker ps --filter "name=$CONTAINER_NAME" | tee "$LOG_DIR/docker_ps_mssql_macos.txt"
