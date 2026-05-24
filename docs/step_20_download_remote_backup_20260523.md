# Step 20: download remote backup for 2026-05-23

Date: 2026-05-24

## Goal

Download the new remote backup marked `23-05-26` into the local repository
`data/` directory without overwriting the existing `data/Fitnes.bak`.

## Source and destination

```text
source: linuxadmin@192.168.2.36:/home/linuxadmin/Fitnes-23-05-26.bak
destination: data/Fitnes-23-05-26.bak
```

The SSH connection was bound to the `fitness` VPN source address because the
default host route was going through another VPN interface.

## Transfer

Used `rsync` with resumable partial transfer:

```text
rsync --partial --append --progress -e "ssh -b 192.168.101.201 ..." \
  linuxadmin@192.168.2.36:/home/linuxadmin/Fitnes-23-05-26.bak \
  data/
```

The local `rsync` version does not support `--append-verify`, so `--append`
was used and the completed file was verified separately with SHA-256.

## Verification

```text
local_path: data/Fitnes-23-05-26.bak
remote_path: /home/linuxadmin/Fitnes-23-05-26.bak
size_bytes: 12909315072
sha256: 0964142666cd98da0cd1d72340e8399e329d348a44ccefa0033f2fbf2933f191
```

The local and remote SHA-256 hashes match.

## Logs

```text
logs/download_fitnes_20260523_local_check.txt
logs/download_fitnes_20260523_remote_check.txt
```
