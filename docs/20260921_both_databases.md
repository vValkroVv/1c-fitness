# Both restored databases, 2026-09-21

The user requires both June and September databases to remain available.
Replacing the June SQL copy during the initial September restore was an
execution mistake. June has been restored again from its preserved backup
into a separate database. September was retained without another restore.

| Backup | SQL database | Actual backup finish | State |
| --- | --- | --- | --- |
| `Fitnes-30-06-26.bak` | `FitnessRestored_20260630_original` | 2026-06-30 23:27:03 | ONLINE, MULTI_USER |
| `Fitnes-20-09-26.fast.bak` | `FitnessRestored_20260630_macos` | 2026-09-20 20:12:12 | ONLINE, MULTI_USER |

The September database retains its old technical name; choose the database
using this mapping, not the date embedded in that name. No database rename
or modification of msdb restore history was performed. Both backups and old
deliveries remain on disk. Future backups must restore into separate
databases, without replacing either of these copies.

## Recovery and verification

The June backup passed SHA-256 calculation, HEADERONLY, FILELISTONLY, and
VERIFYONLY before restoration. SHA-256:
`7e684086442f0eeac44014b9f5170da5c2873620c57788dbc59f58efed1d0810`.

The initial preparation client lost its SQL session while the new June target
remained RESTORING. The root cause was not established. After checking that
there was no active restore or client SQL session, the waiting Python process
was interrupted. Restoration was repeated through sqlcmd inside the SQL
container, reusing only the incomplete June target and its new files.
The retry exited 0 and processed 7,031,669 pages in 114.008 seconds.

June files:

- `mssql-macos/data/FitnessRestored_20260630_original_1.mdf`
- `mssql-macos/data/FitnessRestored_20260630_original_2.ldf`

Both latest full restores were independently matched against HEADERONLY by
source database, backup position, finish time, and UUID:

- June: `0c28175b-e208-4768-99f7-8b50a1687d3a`.
- September: `8e76ec9f-004f-4291-9842-92017c8e9f53`.

The June database has 2,503 user tables and 19,421 columns. Actual COUNT_BIG
reads of `dbo._AccumRg3305` succeeded in both databases: 783,690 rows in June,
799,437 in September. Free host disk space after both restores: about 24 GiB.

Final checks used sqlcmd inside the container. A separate Python TDS connection
from the Mac timed out during prelogin; host connectivity must be checked
before the next Python export. No VPN settings were changed.

June is restored to its original backup contents. Derived staging created
after the original June restore is not part of that backup and has not been
rebuilt. Previous exported deliveries are preserved. The successful September
physical integrity check remains documented in the September restore report;
it was not repeated because September was unchanged by this recovery.

## Evidence

- `logs/20260921_recover_june.log`: first attempt, interrupted client.
- `logs/20260921_recover_june_retry.log`: successful SQL restore.
- `logs/20260921_both_databases_checks.txt`: early access attempt while restoring.
- `logs/20260921_both_databases_checks_final.txt`: final successful access checks.
- `logs/20260921_both_databases_identity.json`: both source identities, PASS.
- `end-to-end-xlsx/work/prepared/20260921_recover_june/backup_metadata.json`:
  source checks and recovery audit, status `RECOVERED_BY_SQLCMD`.

The interrupted preparation did not generate a June pipeline configuration.
This does not affect the restored database. A later June export can prepare
a new run with `--use-existing` and the June database name above.
