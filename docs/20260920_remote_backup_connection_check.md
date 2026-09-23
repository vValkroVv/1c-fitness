# Remote backup connection check — 2026-09-20

## Connection

SSH authentication and remote commands succeeded using the credentials from
`.env` and the connection instructions in `AGENTS_local.md`. No credentials
were copied into this report.

- VPN `fitness`: connected.
- Source interface: `ppp0`, address `192.168.101.201`.
- SSH requires the explicit source binding `-b 192.168.101.201`.
- Remote hostname: `u26`.
- Observed server time: `2026-09-20 19:50:02 UTC`.

## File found

```text
path: /home/linuxadmin/Fitnes.bak
size_bytes: 13604230144
size_decimal_gb: 13.604230144
mtime_utc: 2026-09-20 17:12:12
readable_by_login: yes
```

A bounded scan for regular `*.bak` files under `/home`,
`/root/workspace/1c-fitness/data`, `/data`, `/mnt`, and `/srv` (maximum depth 4)
returned this one file. Missing or inaccessible directories were suppressed,
so this does not establish the absence of backups elsewhere on the server.

The June delivery report
`docs/step_29_remote_backup_20260630_connection_and_download.md` records the
same remote path with size `13137564672` bytes and modification time
`2026-06-30 20:27:03 UTC`. The current remote file has different metadata.
The existing local backups for May and June are present and were not modified.

## Confirmed requested date and verification limits

The user clarified that the requested date is September 20, 2026. Both the
session date and the server clock are September 20. The file found has a
September 20 modification time, matching the requested date; its actual
backup date has not yet been established.

Filesystem modification time is not `backup_finish_at`. The authoritative
value must be read from `RESTORE HEADERONLY.BackupFinishDate` before selecting
a migration cutoff or assigning a confirmed backup-date filename.

This task checked connectivity, file discovery, and read permission. It did
not download the file, compute its checksum, run SQL backup validation, restore
a database, or start the migration pipeline. The SQL backup's integrity and
actual backup finish time remain unverified.
