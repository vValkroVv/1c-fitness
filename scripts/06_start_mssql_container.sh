#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/logs"
TMP_DIR="$ROOT_DIR/tmp"
MSSQL_DIR="$ROOT_DIR/mssql"
BACKUP_DIR="$ROOT_DIR/data"
ENV_FILE="$TMP_DIR/mssql-fitness.env"
CONTAINER_NAME="${MSSQL_CONTAINER_NAME:-mssql-fitness}"
ARCH="$(uname -m)"

if [[ -n "${MSSQL_IMAGE:-}" ]]; then
  IMAGE="$MSSQL_IMAGE"
else
  case "$ARCH" in
    aarch64|arm64)
      IMAGE="mcr.microsoft.com/azure-sql-edge:latest"
      ;;
    *)
      IMAGE="mcr.microsoft.com/mssql/server:2022-latest"
      ;;
  esac
fi

mkdir -p "$LOG_DIR" "$TMP_DIR" "$MSSQL_DIR"

PLATFORM_ARGS=()
ULIMIT_ARGS=()
if [[ -z "${MSSQL_PLATFORM:-}" && "$IMAGE" == *"azure-sql-edge"* && ( "$ARCH" == "aarch64" || "$ARCH" == "arm64" ) ]]; then
  MSSQL_PLATFORM="linux/arm64/v8"
fi

if [[ -n "${MSSQL_PLATFORM:-}" ]]; then
  PLATFORM_ARGS=(--platform "$MSSQL_PLATFORM")
else
  case "$ARCH" in
    x86_64|amd64)
      ;;
    *)
      if [[ "${ALLOW_AMD64_EMULATION:-0}" != "1" ]]; then
        cat >&2 <<MSG
This host is $ARCH. The default image $IMAGE is expected to be linux/amd64.
Set MSSQL_IMAGE and MSSQL_PLATFORM explicitly for a native image, or set
ALLOW_AMD64_EMULATION=1 to force linux/amd64 through QEMU.
MSG
        exit 42
      fi
      PLATFORM_ARGS=(--platform linux/amd64)
      ;;
  esac
fi

if [[ -n "${MSSQL_STACK_ULIMIT:-}" ]]; then
  ULIMIT_ARGS=(--ulimit "stack=$MSSQL_STACK_ULIMIT")
fi

if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" && "${ALLOW_AMD64_EMULATION:-0}" == "1" ]]; then
      cat >&2 <<MSG
SQL Server container image $IMAGE is linux/amd64, but this host is $ARCH.
Use an amd64/x86_64 VPS for the restore workflow. Running this 78 GiB restore
under CPU emulation is not recommended.
MSG
fi

if [[ ! -f "$BACKUP_DIR/Fitnes.bak" ]]; then
  echo "Backup file not found: $BACKUP_DIR/Fitnes.bak" >&2
  exit 2
fi

if docker ps -a --format '{{.Names}}' | grep -Fxq "$CONTAINER_NAME"; then
  echo "Container already exists: $CONTAINER_NAME" >&2
  echo "Remove it manually if you need a clean recreate." >&2
  exit 3
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
    "MSSQL_MEMORY_LIMIT_MB=28672",
]) + "\\n")
path.chmod(0o600)
PY
fi

chown -R 10001:0 "$MSSQL_DIR" 2>/dev/null || true
chmod -R u+rwX,g+rwX "$MSSQL_DIR"

docker run -d \
  "${PLATFORM_ARGS[@]}" \
  --name "$CONTAINER_NAME" \
  --hostname "$CONTAINER_NAME" \
  --memory=34g \
  --cpus=6 \
  "${ULIMIT_ARGS[@]}" \
  --env-file "$ENV_FILE" \
  -p 127.0.0.1:1433:1433 \
  -v "$MSSQL_DIR:/var/opt/mssql" \
  -v "$BACKUP_DIR:/backup:ro" \
  "$IMAGE" \
  2>&1 | tee "$LOG_DIR/step06_docker_run_mssql.log"

docker ps --filter "name=$CONTAINER_NAME" | tee "$LOG_DIR/step06_docker_ps_running.log"
