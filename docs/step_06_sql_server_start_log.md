# Execution Log: step 6 SQL-compatible server startup

Date: 2026-05-07
Workspace: `/root/workspace/1c-fitness`
Plan step: `## 6. Поднять SQL Server для восстановления`

## What was executed

Docker was installed through Ubuntu packages:

```text
apt-get update
apt-get install -y docker.io
systemctl enable --now docker
```

Docker status after installation:

```text
Docker version: 29.1.3
service status: active
```

Runtime directories were prepared:

```text
mssql/
logs/
tmp/
```

`.gitignore` was updated to keep runtime SQL Server data out of git:

```text
mssql/
tmp/
```

The original SQL Server images were checked first:

```text
mcr.microsoft.com/mssql/server:2022-latest
mcr.microsoft.com/mssql/server:2019-latest
mcr.microsoft.com/mssql/server:2017-latest
```

The current VPS is ARM64:

```text
host architecture: aarch64 / arm64
```

Official `mcr.microsoft.com/mssql/server` images are AMD64-only. QEMU/binfmt was
installed and tested, but the SQL Server engine containers crashed under
emulation. Because the instruction is a working plan rather than a strict version
requirement, the runtime was adapted to the native ARM64 Microsoft SQL-compatible
image:

```text
mcr.microsoft.com/azure-sql-edge:latest
```

This image starts as:

```text
Microsoft Azure SQL Edge Developer (RTM) - 15.0.2000.1574 (ARM64)
```

Container startup was completed with repository-local paths:

```text
container name: mssql-fitness
SQL Server volume: /root/workspace/1c-fitness/mssql -> /var/opt/mssql
backup mount: /root/workspace/1c-fitness/data -> /backup:ro
port bind: 127.0.0.1:1433:1433
memory: 34g container limit
SQL memory limit: 28672 MB
CPU: 6
```

## Result

SQL-compatible server is running:

```text
container: mssql-fitness
image: mcr.microsoft.com/azure-sql-edge:latest
status: Up
port: 127.0.0.1:1433 -> 1433/tcp
```

Readiness was confirmed by logs:

```text
SQL Server is now ready for client connections
```

The backup is visible in the container through a read-only mount:

```text
/backup/Fitnes.bak
size: 12G
mount: read-only
```

`sqlcmd` is not present inside the Azure SQL Edge container. For reproducibility,
`scripts/sqlcmd.sh` runs Microsoft `mssql-tools` as a separate AMD64 tools
container through QEMU and connects to `127.0.0.1:1433`.

SQL connectivity was verified:

```text
scripts/sqlcmd.sh -Q "SELECT @@VERSION AS version"
```

Result:

```text
Microsoft Azure SQL Edge Developer (RTM) - 15.0.2000.1574 (ARM64)
Linux (Ubuntu 18.04.6 LTS aarch64) <ARM64>
```

The SA password is stored only in ignored runtime file:

```text
tmp/mssql-fitness.env
```

## Logs

Saved logs:

```text
logs/step06_apt_update.log
logs/step06_apt_install_docker.log
logs/step06_docker_enable.log
logs/step06_docker_version.log
logs/step06_docker_status.log
logs/step06_docker_info.log
logs/step06_docker_run_mssql.log
logs/step06_mssql_container_logs_tail.log
logs/step06_mssql_image_manifest_verbose.json
logs/step06_docker_ps_after_cleanup.log
logs/step06_docker_images.log
logs/step06_qemu_install.log
logs/step06_qemu_alpine_amd64_test.log
logs/step06_start_script_azure_sql_edge_arm64_no_ulimit.log
logs/step06_azure_sql_edge_persistent_logs_wait.log
logs/step06_sqlcmd_wrapper_select_version.log
logs/step06_backup_mount_check.log
logs/step06_docker_image_cleanup.log
logs/step06_docker_images_after_cleanup.log
logs/step06_df_after_image_cleanup.log
```

Unused failed-trial images (`mssql/server` 2017/2019/2022 and `alpine`) were
removed after the working runtime was confirmed. Remaining Docker images:

```text
mcr.microsoft.com/azure-sql-edge:latest
mcr.microsoft.com/mssql-tools:latest
```

## Remaining risk for next step

The runtime is SQL-compatible and responds to queries, but it is Azure SQL Edge
15.0 ARM64 rather than full SQL Server 2022 Developer. The next step must verify
backup compatibility using `RESTORE HEADERONLY`, `RESTORE FILELISTONLY`, and
`RESTORE VERIFYONLY` before attempting full restore.

## Reproducible script

Created/updated:

```text
scripts/06_start_mssql_container.sh
scripts/sqlcmd.sh
```

`scripts/06_start_mssql_container.sh` now chooses
`mcr.microsoft.com/azure-sql-edge:latest` by default on ARM64 and
`mcr.microsoft.com/mssql/server:2022-latest` by default on AMD64. It also accepts
overrides through `MSSQL_IMAGE`, `MSSQL_PLATFORM`, and `MSSQL_CONTAINER_NAME`.

`scripts/sqlcmd.sh` wraps `mssql-tools` and can run SQL scripts or ad-hoc
queries against the local server.
