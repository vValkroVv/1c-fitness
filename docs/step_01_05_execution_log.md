# Execution Log: plan steps 1-5

Date: 2026-05-07
Workspace: `/root/workspace/1c-fitness`
Plan: `task-desc/fitness_updated_restore_to_fitbase_plan.md`
Scope: steps 1-5 inclusive

## Path adaptation

The source plan was written for `/mnt/fitness_sql/...` and an earlier server path
`/home/linuxadmin/Fitnes.bak`.

The canonical local backup path for this repository is:

```text
data/Fitnes.bak
```

For this repository run, paths are adapted as follows:

| Plan path | Local repository path |
|---|---|
| `/mnt/fitness_sql/backup/Fitnes.bak` | `data/Fitnes.bak` |
| `/mnt/fitness_sql/work/config` | `config/` |
| `/mnt/fitness_sql/work/sql` | `sql/` |
| `/mnt/fitness_sql/work/scripts` | `scripts/` |
| `/mnt/fitness_sql/work/docs` | `docs/` |
| `/mnt/fitness_sql/output` | `output/` |
| `/mnt/fitness_sql/logs` | `logs/` |
| `/mnt/fitness_sql/tmp` | `tmp/` |

## Step 1: goal confirmed

Goal understood: restore Microsoft SQL Server backup `Fitness`, discover the 1C
Fitness schema, extract the segment `Действующие клиенты`, apply business rules,
and produce two Fitbase XLSX files:

1. `fitbase_active_clients_import_zayavki_YYYYMMDD.xlsx`
2. `fitbase_active_clients_plastic_cards_YYYYMMDD.xlsx`

The source XLSX templates are present:

```text
task-desc/Копия Импорт_заявки.xlsx
task-desc/Пластиковая карта.xlsx
```

## Step 2: expected final result confirmed

The expected final artifact groups are understood:

- configuration files in `config/`;
- SQL files in `sql/`;
- reproducible processing scripts in `scripts/`;
- final XLSX files and validation reports in `output/`;
- runtime logs in `logs/`;
- process documentation in `docs/`.

Template check without installing dependencies:

```text
Копия Импорт_заявки.xlsx:
- sheet: Лист1
- first row technical headers:
  client_id, phone, client_fio, email, funnel, funnel_step, budget, create_date, manager
- second row Russian headers:
  Внутренний номер клиента, Телефон *, ФИО клиента *, Почта, Воронка *,
  Этап воронки *, Бюджет, Дата создания *, Менеджер
- row 3 contains an example and must be replaced by real data

Пластиковая карта.xlsx:
- sheet: Лист1
- headers:
  телефон, фио, номер пластиковой карты
```

`openpyxl` is not installed yet. This is not blocking for steps 1-5, but it will
be needed for the XLSX build script unless another XLSX writer is chosen.

## Step 3: restore environment check

Current environment:

```text
disk: /dev/vda1, 193G total, 177G available
RAM: 39Gi total, 37Gi available at check time
CPU: 8 cores
swap: 0B
```

This is consistent with the plan recommendation:

```text
Disk: about 200 GB
RAM: about 40 GB
CPU: 4+ vCPU
```

Important note: Docker and `sqlcmd` are not currently installed/found in PATH.
They are needed starting from step 6, not from steps 1-5.

## Step 4: repository directories prepared

Created or confirmed:

```text
config/
sql/
scripts/
docs/
output/
logs/
tmp/
```

The backup directory already existed:

```text
data/
```

## Step 5: backup presence and integrity check

The backup is already present locally, so no `rsync` copy was performed.
Avoiding a copy is intentional because the plan says to keep one backup instance.

Backup file:

```text
path: data/Fitnes.bak
size: 12,770,610,688 bytes
du size: 12G
modified: 2026-04-29 23:57:02 +0300
sha256: f42803d778ad59beb3dcce055f48d2dec379c8378c7c469b48407a3b50867651
```

The local backup size matches the plan/probe value:

```text
12,770,610,688 bytes
```

## Previous no-restore probe available

Previous SQL Server metadata probe artifacts are present in:

```text
inspection-data-base/fitnes_mssql_probe_20260504_201241_lxd/
```

The included final report confirms:

```text
DatabaseName: Fitness
backup set FILE position: 1
compressed: yes
checksum: yes
TDE/encryption signs: no
RESTORE HEADERONLY: success
RESTORE FILELISTONLY: success
RESTORE VERIFYONLY: success
estimated restored size: 78.33 GiB
```

No actual restore has been performed yet in this run.
