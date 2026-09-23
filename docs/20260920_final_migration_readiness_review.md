# Final migration readiness review — 20 September 2026

Reviewed `20260920_final_migration_plan.md`, the entry wrapper, backup preparation,
pipeline orchestration, photo preflight, test records and rehearsal artifacts at
commit `436ce6a` on `main`. The working tree was clean before this review.

## Decision

The documented fresh-run path is implemented and rehearsed. Processing the new
backup can begin when it arrives, subject to its own backup, capacity and data
checks. Preparation is not fully complete for recovery: the two findings below
remain open. This review did not restore a database or change pipeline code.

## Findings

### 1. High: resume does not recheck the restored backup identity

`end-to-end-xlsx/scripts/run_pipeline.py:1017` skips all steps before `start_at`,
including `preflight`, where `verify_restored_backup` checks the latest UUID in
msdb. The resume signature covers configuration and selected control files,
but not the current restored database or ownership of shared staging.

Concrete trigger: run A passes preflight and fails at `owner_sql`; the same
technical database is subsequently replaced with backup B; A resumes at
`owner_sql` using its unchanged configuration. It can rebuild B's data while
recording A's backup metadata. The photo preflight checks staging timestamps,
which this resumed run writes from A's configuration; it does not independently
check the restore UUID. The documented prohibition on simultaneous runs does not
cover this sequential replacement case.

Before treating resume as generally safe, recheck restore provenance before any
resumed SQL/photo work and verify that reused staging belongs to this run.
Until then, resume only while the restored database and staging remain untouched
since the failed run. If another restore or staging run occurred, use a fresh
full run with verified provenance rather than a later-stage resume.

### 2. Medium: section 6 does not cover preparation/restore failures

`end-to-end-xlsx/scripts/prepare_backup.py:309` reserves the preparation directory
with `exist_ok=False`. It writes `pipeline.yml` only at the end (`:437`). A failure
during hashing, SQL checks or restore therefore normally leaves
`work/prepared/<run-name>/backup_metadata.json`, without a pipeline configuration
or `work/<run-name>/status.json`. Neither the section 6 resume command nor simply
repeating the original command with the same name works in that state.

The runbook needs a separate recovery branch:

- Inspect the preparation audit and actual SQL state first; retain failed-run evidence.
- If failure preceded restore, fix the cause and retry with a fresh run name.
- If the intended backup is already restored and ONLINE, retry preparation with
  a fresh run name and `--use-existing`, which verifies the actual restore UUID.
- If restore failed and the database is not ONLINE, inspect and recover that SQL
  state before retrying. The guarded replacement helper itself requires ONLINE;
  ordinary pipeline resume cannot repair an incomplete restore.
- Use the documented `--resume-config` path only after successful preparation
  and creation of pipeline status, subject to finding 1.

## Verified evidence

- `python3 scripts/run_fitbase_migration.py --help` works in the pinned environment.
- SQL container `mssql-fitness-2022` is running on `127.0.0.1:11434`.
  Its `/backup` and `/restoredata` mounts match the plan.
- A read-only SQL check confirms the June database is ONLINE, MULTI_USER,
  compatibility 130, with the expected latest full-restore UUID and timestamp.
  There were no other user sessions in that database during the check.
- Existing MDF/LDF allocation is approximately 78.3 GiB. Free host space is now
  approximately **41 GiB**, compared with the plan's earlier 52 GiB observation.
  A parallel full restore does not fit. Replacement capacity must be recalculated
  after downloading the new backup, allowing for file growth, staging and output.
- The rehearsal completed all 17 steps. Its 7 XLSX and photo ZIP still match all
  8 recorded sizes and SHA-256 hashes. All 4 recorded configuration-input hashes
  also match current files. The READY marker and manifest report PASS.
- Photo validation records 34,535 JPEGs and PASS for CRC, decoding, unique paths
  and manifest hashes. Full photo decoding was not repeated in this review;
  the ZIP's unchanged SHA-256 confirms it is the validated artifact.
- The saved unit-test log records 75 passing tests. The isolated restore and
  replacement smoke reports record successful provenance checks, file reuse,
  replacement of 2 rows with 3, and return to MULTI_USER. These completed checks
  were not rerun because the relevant implementation has not changed.
- Manager assignment, the +24-hour cutoff rehearsal, original operation dates,
  accepted financial/service fixes and the two expected financial boundary
  changes are documented in the existing rehearsal reports.

## Work that necessarily waits for the new backup

1. Receive the complete file and check remaining capacity.
2. Validate its real HEADERONLY/FILELISTONLY/VERIFYONLY results and restore identity.
3. Execute the full pipeline with the agreed effective time and a unique run name.
4. Review new-data exceptions, including contract 151350, manager/funnel counts,
   photo exclusions and September 20/21 boundary examples.
5. Deliver only after this new run produces PASS, READY and matching file hashes.

Only the May and June full backup files were present in `data/` during review.
Readiness of the September data itself cannot yet be established.
