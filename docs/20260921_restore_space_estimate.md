# Restore space estimate — 2026-09-21

Source: `data/Fitnes-20-09-26.fast.bak`.
Read `RESTORE FILELISTONLY ... WITH FILE = 1` on the existing SQL Server 2022
container and compared its `Size` values with `sys.master_files` for
`FitnessRestored_20260630_macos`. No database restore or replacement was run.

| Logical file | Bytes | GiB |
| --- | ---: | ---: |
| Fitness | 80404807680 | 74.883 |
| Fitness_log | 3699376128 | 3.445 |

- Total restored file allocation: **78.328 GiB** (84,104,183,808 bytes).
- Existing June SQL files have exactly the same declared sizes.
- Positive file growth for the planned replacement: **0 bytes**.
- Runner safety margin: **2 GiB**.
- Restore into a separate database needs **80.328 GiB**
  of additional free space, including the runner margin.
- Reusing the existing June SQL files needs **2.000 GiB**
  of additional free space according to the runner's growth calculation.
- Free host space at measurement: **37.370 GiB**.

The planned replacement fits this disk-space check; creating a second full
SQL copy alongside June does not. These values describe file allocation and
the preparation script's minimum margin, not a bound on later staging/log
or export growth. They are disk-space figures, not RAM requirements.

The `.bak` has already been downloaded and occupies additional disk space;
its existing size is already reflected in the measured free space.

This check ran FILELISTONLY only. HEADERONLY, VERIFYONLY, source identity and
all other restore preconditions remain part of the migration preparation.
Actual BackupFinishDate and the migration cutoff were not inferred from the
filename or modification time.

Evidence:

- `logs/20260921_backup_restore_sizes.txt`
- `logs/20260921_restore_space_estimate.json`
- `end-to-end-xlsx/scripts/prepare_backup.py`: `replacement_moves` and
  `RESTORE_MARGIN_BYTES`.

Microsoft documents the file-size fields in
[RESTORE FILELISTONLY](https://learn.microsoft.com/sql/t-sql/statements/restore-statements-filelistonly-transact-sql).
