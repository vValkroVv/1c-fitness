# Step 29: remote backup 2026-06-30 connection and download

Date: 2026-07-05

## Goal

Connect to the remote server from `AGENTS_local.md`, identify the new backup in
`/home/linuxadmin`, document the working connection details, and download the
backup into local `data/` without overwriting previous `.bak` files.

## Connection finding

The values `LOGIN`, `IP`, and `PASS` are loaded from `.env`.

The server is reachable only when SSH is bound to the VPN PPP source address:

```sh
set -a; . ./.env; set +a
ssh -b 192.168.101.201 "$LOGIN@$IP"
```

Observed local VPN interfaces:

```text
ppp0 inet 192.168.101.201 --> 192.168.101.254
utun6 inet 172.16.0.1 --> 172.16.0.1
```

When connecting without `-b 192.168.101.201`, or when binding to `172.16.0.1`,
TCP connect to `22/tcp` succeeds, but SSH is reset before authentication:

```text
kex_exchange_identification: read: Connection reset by peer
Connection reset by 192.168.2.36 port 22
```

With `ssh -b 192.168.101.201`, SSH reaches password authentication and accepts
the password from `PASS`.

## Remote backup found

The new file is not date-stamped remotely; it is the current `/home/linuxadmin/Fitnes.bak`.

```text
path: /home/linuxadmin/Fitnes.bak
size_bytes: 13137564672
size_human: 13G
mtime_utc: 2026-06-30 20:27:03 +0000
owner: linuxadmin:linuxadmin
mode: -rw-rw-r--
```

The server time during the check was:

```text
2026-07-05 13:34:21 +0000 UTC
```

## Local destination

Previous local backup already exists:

```text
data/Fitnes-23-05-26.bak
```

The new remote file has the generic name `Fitnes.bak`, so the local download is
date-stamped to preserve older backups:

```text
data/Fitnes-30-06-26.bak
```

## Download command

The local `rsync` is old (`openrsync`, protocol 29, rsync-compatible 2.6.9), so
the actual command used the older supported flags `--partial --append --progress`.
It did not use `--append-verify` or newer `--info` options.

```sh
set -a; . ./.env; set +a
rsync --partial --append --progress \
  -e "ssh -b 192.168.101.201 -o StrictHostKeyChecking=accept-new" \
  "$LOGIN@$IP:/home/linuxadmin/Fitnes.bak" \
  data/Fitnes-30-06-26.bak
```

The transfer completed successfully with `rsync` exit code `0`.

Final `rsync` progress line:

```text
13137564672 100% 8.73MB/s 00:23:55 (xfer#1, to-check=0/1)
```

## Verification

Status: `PASS`.

Local file:

```text
path: data/Fitnes-30-06-26.bak
size_bytes: 13137564672
sha256: 7e684086442f0eeac44014b9f5170da5c2873620c57788dbc59f58efed1d0810
```

Remote file:

```text
path: /home/linuxadmin/Fitnes.bak
size_bytes: 13137564672
mtime_utc: 2026-06-30 20:27:03.000000000 +0000
owner: linuxadmin:linuxadmin
mode: 664
sha256: 7e684086442f0eeac44014b9f5170da5c2873620c57788dbc59f58efed1d0810
```

The local and remote sizes match. The local and remote SHA-256 hashes match.

## Logs

Logs:

```text
logs/download_fitnes_20260630_rsync.txt
logs/download_fitnes_20260630_remote_check.txt
logs/download_fitnes_20260630_local_check.txt
logs/download_fitnes_20260630_remote_sha256.txt
```
