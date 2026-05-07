#!/usr/bin/env bash
set -u -o pipefail

WORK='/probe'
BAK='/var/opt/mssql/backup/Fitnes.bak'
SQLC='fitnes_mssql_probe_sql'
NET='fitnes_probe_internal'
IMAGE='mcr.microsoft.com/mssql/server:2022-latest'
PASS="$(cat /probe/tmp/sa_password.txt)"
SQLCMD_KIND=''
SQLCMD_PATH=''

exec > >(tee -a "$WORK/logs/lxd_inner.log") 2>&1

echo "Inside LXD: $(date -Is)"
uname -a | tee "$WORK/results/04_lxd_uname.txt"
cat /etc/os-release | tee "$WORK/results/04_lxd_os_release.txt"
ls -lh "$BAK" | tee "$WORK/results/04_bak_visible_in_lxd.txt"
stat "$BAK" | tee "$WORK/results/04_bak_stat_in_lxd.txt"

for i in $(seq 1 90); do
  if getent hosts archive.ubuntu.com >/dev/null 2>&1; then
    break
  fi
  sleep 2
  if [ "$i" -eq 90 ]; then
    echo 'DNS/network inside LXD is not ready' | tee "$WORK/results/04_lxd_network_error.txt"
    exit 1
  fi
done

apt-get update > "$WORK/logs/05_apt_update.txt" 2>&1
DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io python3 ca-certificates curl > "$WORK/logs/06_apt_install_docker_python.txt" 2>&1
(systemctl enable --now docker > "$WORK/logs/07_docker_enable.txt" 2>&1 || service docker start > "$WORK/logs/07_docker_service_start.txt" 2>&1 || (nohup dockerd > "$WORK/logs/07_dockerd_nohup.txt" 2>&1 &))

for i in $(seq 1 90); do
  if docker info > "$WORK/results/08_docker_info.txt" 2>&1; then
    break
  fi
  sleep 2
  if [ "$i" -eq 90 ]; then
    echo 'Docker inside LXD did not become ready' | tee "$WORK/results/08_docker_not_ready.txt"
    exit 1
  fi
done

docker version | tee "$WORK/results/08_docker_version.txt"
docker pull "$IMAGE" > "$WORK/logs/09_docker_pull_mssql.txt" 2>&1
(docker network rm "$NET" >/dev/null 2>&1 || true)
docker network create --internal "$NET" | tee "$WORK/results/10_docker_network.txt"
(docker rm -f "$SQLC" >/dev/null 2>&1 || true)

docker run \
  --name "$SQLC" \
  --hostname "$SQLC" \
  --network "$NET" \
  -e ACCEPT_EULA=Y \
  -e MSSQL_SA_PASSWORD="$PASS" \
  -e MSSQL_PID=Developer \
  -v "$BAK:$BAK:ro" \
  -v /probe/queries:/probe/queries:ro \
  -d "$IMAGE" | tee "$WORK/results/11_sql_container_id.txt"

docker ps -a | tee "$WORK/results/11_docker_ps_after_run.txt"
docker exec "$SQLC" bash -lc "ls -lh '$BAK'; stat '$BAK'" > "$WORK/results/12_bak_inside_sql_container.txt" 2>&1 || true

find_sqlcmd_in_sql_container() {
  docker exec "$SQLC" bash -lc 'for p in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd /usr/bin/sqlcmd; do if [ -x "$p" ]; then echo "$p"; exit 0; fi; done; exit 1' 2>/dev/null
}

sqlcmd_exec() {
  local input="$1"
  local output="$2"
  if [ "$SQLCMD_KIND" = 'inside18' ]; then
    docker exec "$SQLC" "$SQLCMD_PATH" -S localhost -U sa -P "$PASS" -C -b -r1 -W -s '|' -w 65535 -i "$input" > "$output" 2>&1
  elif [ "$SQLCMD_KIND" = 'inside17' ]; then
    docker exec "$SQLC" "$SQLCMD_PATH" -S localhost -U sa -P "$PASS" -C -b -r1 -W -s '|' -w 65535 -i "$input" > "$output" 2>&1 \
      || docker exec "$SQLC" "$SQLCMD_PATH" -S localhost -U sa -P "$PASS" -b -r1 -W -s '|' -w 65535 -i "$input" > "$output" 2>&1
  else
    docker run --rm --network "$NET" -v /probe/queries:/probe/queries:ro mcr.microsoft.com/mssql-tools /opt/mssql-tools/bin/sqlcmd -S "$SQLC" -U sa -P "$PASS" -b -r1 -W -s '|' -w 65535 -i "$input" > "$output" 2>&1
  fi
}

READY=0
for i in $(seq 1 180); do
  SQLCMD_PATH="$(find_sqlcmd_in_sql_container || true)"
  if [ -n "$SQLCMD_PATH" ]; then
    case "$SQLCMD_PATH" in
      *tools18*) SQLCMD_KIND='inside18' ;;
      *) SQLCMD_KIND='inside17' ;;
    esac
    printf '%s\n' "$SQLCMD_KIND:$SQLCMD_PATH" > "$WORK/results/13_sqlcmd_location.txt"
    if sqlcmd_exec /probe/queries/version.sql "$WORK/results/14_sql_version.txt"; then
      READY=1
      break
    fi
  fi
  if [ "$i" -eq 60 ]; then
    docker logs "$SQLC" > "$WORK/logs/13_sql_container_logs_wait_60.txt" 2>&1 || true
  fi
  sleep 2
done

if [ "$READY" -ne 1 ]; then
  echo 'sqlcmd not found/SQL Server not ready inside SQL image; trying external mssql-tools image' | tee "$WORK/results/13_sqlcmd_fallback.txt"
  docker pull mcr.microsoft.com/mssql-tools > "$WORK/logs/13_docker_pull_mssql_tools.txt" 2>&1 || true
  SQLCMD_KIND='tools_container'
  for i in $(seq 1 90); do
    if sqlcmd_exec /probe/queries/version.sql "$WORK/results/14_sql_version.txt"; then
      READY=1
      break
    fi
    sleep 2
  done
fi

if [ "$READY" -ne 1 ]; then
  docker logs "$SQLC" > "$WORK/logs/13_sql_container_logs_not_ready.txt" 2>&1 || true
  echo 'SQL Server did not become ready' | tee "$WORK/results/final_report.md"
  exit 1
fi

echo "SQLCMD_KIND=$SQLCMD_KIND" | tee "$WORK/results/13_sqlcmd_kind.txt"

set +e
sqlcmd_exec /probe/queries/headeronly.sql "$WORK/results/20_restore_headeronly.txt"
HEADER_EXIT=$?
echo "$HEADER_EXIT" > "$WORK/results/20_restore_headeronly.exit"
set -e

python3 - <<'PY' > /probe/tmp/selected_position.txt
from pathlib import Path

def parse_table(path):
    text = Path(path).read_text(errors='replace').splitlines()
    header_i = None
    for i, line in enumerate(text):
        s = line.strip('\ufeff').strip()
        if not s or s.startswith('Msg ') or s.startswith('Changed database'):
            continue
        if '|' in s and not set(s.replace('|','').strip()) <= {'-'}:
            header_i = i
            break
    if header_i is None:
        return []
    headers = [h.strip() for h in text[header_i].split('|')]
    rows = []
    for line in text[header_i+1:]:
        s = line.strip()
        if not s or s.startswith('(') or s.startswith('Msg '):
            continue
        if '|' not in line:
            continue
        cells = [c.strip() for c in line.split('|')]
        if set(''.join(cells).strip()) <= {'-'}:
            continue
        if len(cells) < len(headers):
            cells += [''] * (len(headers) - len(cells))
        rows.append(dict(zip(headers, cells[:len(headers)])))
    return rows
rows = parse_table('/probe/results/20_restore_headeronly.txt')
selected = '1'
for row in rows:
    desc = (row.get('BackupTypeDescription') or '').lower()
    btype = (row.get('BackupType') or '').strip()
    pos = (row.get('Position') or '').strip()
    if pos and (btype == '1' or 'database' in desc or 'full' in desc):
        selected = pos
        break
if rows and not selected:
    selected = (rows[0].get('Position') or '1').strip() or '1'
print(selected)
PY
FILE_POS="$(tr -dc '0-9' < "$WORK/tmp/selected_position.txt")"
if [ -z "$FILE_POS" ]; then FILE_POS=1; fi
echo "$FILE_POS" | tee "$WORK/results/21_selected_file_position.txt"

cat > "$WORK/queries/filelistonly.sql" <<SQL
RESTORE FILELISTONLY FROM DISK = N'/var/opt/mssql/backup/Fitnes.bak' WITH FILE = ${FILE_POS};
GO
SQL
cat > "$WORK/queries/verifyonly.sql" <<SQL
RESTORE VERIFYONLY FROM DISK = N'/var/opt/mssql/backup/Fitnes.bak' WITH FILE = ${FILE_POS};
GO
SQL

set +e
sqlcmd_exec /probe/queries/filelistonly.sql "$WORK/results/22_restore_filelistonly.txt"
FILELIST_EXIT=$?
echo "$FILELIST_EXIT" > "$WORK/results/22_restore_filelistonly.exit"
sqlcmd_exec /probe/queries/verifyonly.sql "$WORK/results/23_restore_verifyonly.txt"
VERIFY_EXIT=$?
echo "$VERIFY_EXIT" > "$WORK/results/23_restore_verifyonly.exit"
set -e

docker logs "$SQLC" > "$WORK/logs/99_sql_container_logs_final.txt" 2>&1 || true

python3 - <<'PY'
from pathlib import Path
import re

WORK = Path('/probe')
R = WORK / 'results'
BAK = '/home/linuxadmin/Fitnes.bak'

def read(path):
    p = Path(path)
    return p.read_text(errors='replace') if p.exists() else ''

def parse_table(path):
    text = Path(path).read_text(errors='replace').splitlines() if Path(path).exists() else []
    header_i = None
    for i, line in enumerate(text):
        s = line.strip('\ufeff').strip()
        if not s or s.startswith('Msg ') or s.startswith('Changed database'):
            continue
        if '|' in s and not set(s.replace('|','').strip()) <= {'-'}:
            header_i = i
            break
    if header_i is None:
        return [], []
    headers = [h.strip() for h in text[header_i].split('|')]
    rows = []
    for line in text[header_i+1:]:
        s = line.strip()
        if not s or s.startswith('(') or s.startswith('Msg '):
            continue
        if '|' not in line:
            continue
        cells = [c.strip() for c in line.split('|')]
        if set(''.join(cells).strip()) <= {'-'}:
            continue
        if len(cells) < len(headers):
            cells += [''] * (len(headers) - len(cells))
        rows.append(dict(zip(headers, cells[:len(headers)])))
    return headers, rows

def first(row, *names):
    for n in names:
        v = row.get(n)
        if v not in (None, '', 'NULL'):
            return v
    return ''

def yn(v):
    s = str(v).strip().lower()
    if s in ('1', 'true', 'yes', 'да'):
        return 'да'
    if s in ('0', 'false', 'no', 'нет'):
        return 'нет'
    if s in ('', 'null', 'none'):
        return 'непонятно'
    return str(v)

def gib(n):
    try:
        return int(n) / 1024**3
    except Exception:
        return 0.0

stat = read(R/'00_stat.txt')
size_match = re.search(r'Size:\s*(\d+)', stat)
backup_size = int(size_match.group(1)) if size_match else 0
modify_match = re.search(r'Modify:\s*([^\n]+)', stat)
modify = modify_match.group(1).strip() if modify_match else ''
free_gib = read(R/'00_free_gib.txt').strip().split('=')[-1] if (R/'00_free_gib.txt').exists() else ''

_, hrows = parse_table(R/'20_restore_headeronly.txt')
_, frows = parse_table(R/'22_restore_filelistonly.txt')
version_txt = read(R/'14_sql_version.txt')
header_exit = read(R/'20_restore_headeronly.exit').strip()
filelist_exit = read(R/'22_restore_filelistonly.exit').strip()
verify_exit = read(R/'23_restore_verifyonly.exit').strip()
verify_txt = read(R/'23_restore_verifyonly.txt')
selected = read(R/'21_selected_file_position.txt').strip() or '1'

hrow = {}
for row in hrows:
    if (row.get('Position') or '').strip() == selected:
        hrow = row
        break
if not hrow and hrows:
    hrow = hrows[0]

data_bytes = 0
log_bytes = 0
file_lines = []
for row in frows:
    typ = (row.get('Type') or '').strip()
    sz = int(row.get('Size') or 0) if (row.get('Size') or '').strip().isdigit() else 0
    if typ == 'L':
        log_bytes += sz
    else:
        data_bytes += sz
    file_lines.append(f"| {row.get('LogicalName','')} | {row.get('PhysicalName','')} | {typ} | {sz} | {gib(sz):.2f} |")

total_bytes = data_bytes + log_bytes
recommended = max(0, total_bytes * 1.25 / 1024**3)
current_home_ok = 'да' if free_gib.isdigit() and recommended and int(free_gib) >= recommended else 'нет'

compressed = yn(first(hrow, 'Compressed'))
checksums = yn(first(hrow, 'HasBackupChecksums'))
enc_fields = [first(hrow, 'KeyAlgorithm'), first(hrow, 'EncryptorThumbprint'), first(hrow, 'EncryptorType')]
if any(v and v.upper() != 'NULL' for v in enc_fields):
    encrypted = 'да'
elif hrow:
    encrypted = 'нет'
else:
    encrypted = 'непонятно'

verify_success = verify_exit == '0' and ('Msg ' not in verify_txt)
verify_result = 'success' if verify_success else 'error'
verify_short = verify_txt.strip() or '(empty output)'
if len(verify_short) > 4000:
    verify_short = verify_short[:4000] + '\n... output truncated in final report; see 23_restore_verifyonly.txt'

server_version_line = ''
for line in version_txt.splitlines():
    if 'Microsoft SQL Server' in line:
        server_version_line = line.strip()
        break

software_version = '.'.join(x for x in [first(hrow,'SoftwareVersionMajor'), first(hrow,'SoftwareVersionMinor'), first(hrow,'SoftwareVersionBuild')] if x)

md = []
md.append('# Fitness MSSQL no-restore probe result')
md.append('')
md.append('## Ключевой вывод')
md.append('')
if header_exit == '0':
    md.append('SQL Server смог прочитать backup metadata через `RESTORE HEADERONLY`.')
else:
    md.append('SQL Server НЕ смог прочитать backup metadata через `RESTORE HEADERONLY`.')
if filelist_exit == '0':
    md.append('SQL Server смог прочитать список файлов базы через `RESTORE FILELISTONLY`.')
else:
    md.append('SQL Server НЕ смог прочитать список файлов базы через `RESTORE FILELISTONLY`.')
md.append(f'`RESTORE VERIFYONLY`: {verify_result}.')
md.append('')
md.append('На текущем этапе восстановление базы НЕ выполнялось.')
md.append('Backup проверен только на уровне metadata/readability.')
md.append('Список таблиц и данные клиентов без восстановления базы получить нельзя.')
md.append('')
md.append('## 1. Backup-файл')
md.append('')
md.append(f'- путь: `{BAK}`')
md.append(f'- размер backup-файла: {backup_size} bytes ({backup_size / 1024**3:.2f} GiB)' if backup_size else '- размер backup-файла: не удалось определить')
md.append(f'- дата изменения файла: {modify or "не удалось определить"}')
md.append('')
md.append('## 2. SQL Server metadata')
md.append('')
md.append(f'- SQL Server смог прочитать backup header: {"да" if header_exit == "0" else "нет"}')
md.append(f'- количество backup sets внутри `.bak`: {len(hrows) if hrows else "не удалось определить"}')
md.append(f'- выбранный backup set / FILE position: {selected}')
md.append(f'- DatabaseName: `{first(hrow, "DatabaseName") or "не удалось определить"}`')
md.append(f'- BackupType: `{first(hrow, "BackupType") or "не удалось определить"}`')
md.append(f'- BackupTypeDescription: `{first(hrow, "BackupTypeDescription") or "не удалось определить"}`')
md.append(f'- BackupStartDate: `{first(hrow, "BackupStartDate") or "не удалось определить"}`')
md.append(f'- BackupFinishDate: `{first(hrow, "BackupFinishDate") or "не удалось определить"}`')
md.append(f'- DatabaseVersion: `{first(hrow, "DatabaseVersion") or "не удалось определить"}`')
md.append(f'- SQL Server version, которой был создан backup: `{software_version or "не удалось определить"}`')
md.append(f'- SQL Server engine для проверки: `{server_version_line or "см. results/14_sql_version.txt"}`')
md.append(f'- compressed: {compressed}')
md.append(f'- encrypted/TDE: {encrypted}')
md.append(f'- checksum в backup: {checksums}')
md.append('')
md.append('## 3. Оценка размера восстановления')
md.append('')
md.append('| LogicalName | PhysicalName | Type | Size bytes | Size GiB |')
md.append('|---|---|---:|---:|---:|')
md.extend(file_lines if file_lines else ['| не удалось прочитать | | | | |'])
md.append('')
md.append(f'- сумма data files: {data_bytes} bytes ({gib(data_bytes):.2f} GiB)')
md.append(f'- сумма log files: {log_bytes} bytes ({gib(log_bytes):.2f} GiB)')
md.append(f'- общий estimated restore size: {total_bytes} bytes ({gib(total_bytes):.2f} GiB)')
md.append(f'- минимальный рекомендуемый объем отдельного restore-volume: {recommended:.2f} GiB (оценка: restore size * 1.25)')
md.append(f'- свободно на текущем `/home`: {free_gib or "не удалось определить"} GiB')
md.append('')
md.append('## 4. Проверка читаемости')
md.append('')
md.append(f'- RESTORE VERIFYONLY выполнен: {"да" if verify_exit != "" else "нет"}')
md.append(f'- результат: {verify_result}')
md.append(f'- exit code: `{verify_exit or "нет"}`')
if not verify_success:
    md.append('')
    md.append('Точный вывод ошибки/команды:')
    md.append('')
    md.append('```text')
    md.append(verify_short)
    md.append('```')
else:
    md.append('')
    md.append('Вывод команды:')
    md.append('')
    md.append('```text')
    md.append(verify_short)
    md.append('```')
md.append('')
md.append('## 5. Решение')
md.append('')
md.append(f'- можно ли восстанавливать на текущий `/home`: {current_home_ok}')
md.append('- можно ли проверять таблицы без restore: нет')
md.append('- что нужно для проверки таблиц: отдельный диск/volume + тестовый `RESTORE DATABASE`')
md.append('- следующий шаг: подготовить volume нужного размера или запросить у заказчика SQL Server/1C-выгрузку в читаемом формате')
md.append('')
md.append('## 6. Артефакты')
md.append('')
md.append('- `results/20_restore_headeronly.txt`')
md.append('- `results/22_restore_filelistonly.txt`')
md.append('- `results/23_restore_verifyonly.txt`')
md.append('- `logs/session.log`')
md.append('- `logs/lxd_inner.log`')
md.append('')
md.append('## 7. Ограничение')
md.append('')
md.append('`RESTORE DATABASE` не выполнялся. Таблицы, схема 1C и клиентские данные на этом этапе не извлекались.')

(R/'final_report.md').write_text('\n'.join(md) + '\n')
print(R/'final_report.md')
print(f'TOTAL_RESTORE_GIB={gib(total_bytes):.2f}')
print(f'RECOMMENDED_VOLUME_GIB={recommended:.2f}')
print(f'VERIFY_STATUS={verify_result}')
PY
