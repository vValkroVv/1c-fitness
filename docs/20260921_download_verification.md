# Completed backup download verification — 2026-09-21

Status: **PASS**.

The downloader has already assembled one complete file:

`data/Fitnes-20-09-26.fast.bak`

No second assembly or duplicate copy was necessary.

- Local size: **13,604,230,144 bytes**.
- Remote source: `/home/linuxadmin/Fitnes.bak`.
- Remote size matches the local file and the downloader receipt exactly.
- Independently recalculated the entire local file with `shasum -a 256`.
- Independently recalculated the entire remote file with `sha256sum`.
- Both hashes match each other and `data/Fitnes-20-09-26.fast.bak.verified.json`.
- Remote size, mtime, inode and device stayed unchanged during the hash check.
- No `.part` or `.partial` payload files remain in the downloader's chunk directory;
  only `manifest.json` and `lock` remain.

SHA-256:

```text
a65f21760209e60ac3b2ffc49a15a9a308e02dd75ffeb5829c342c9d98170f52
```

The older `data/Fitnes-20-09-26.bak` is a separate incomplete rsync download
of 63,799,296 bytes. It was preserved and must not be used as the complete
backup. Use the verified `.fast.bak` file above.

This verifies complete transfer and assembly of the source bytes. SQL backup
structure, `BackupFinishDate`, and restore compatibility were not checked in
this task. Those require the separate SQL backup validation stage.

Evidence:

- `logs/20260921_download_remote_sha256.json`
- `logs/20260921_download_verification.json`
- `data/Fitnes-20-09-26.fast.bak.verified.json`
