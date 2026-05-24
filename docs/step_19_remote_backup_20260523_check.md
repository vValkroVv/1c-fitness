# Step 19: remote backup check for 2026-05-23

Date: 2026-05-24

## Goal

Check the remote server for a new Microsoft SQL Server backup marked
`23-05-26`.

## Connection notes

- VPN `fitness` was connected.
- The default route to the server was not using the `fitness` PPP interface
  because another VPN route was active.
- SSH worked when bound explicitly to the `fitness` source address/interface.
- Direct access to `/root/workspace/1c-fitness` as `linuxadmin` was denied.

## Result

Found the expected backup:

```text
path: /home/linuxadmin/Fitnes-23-05-26.bak
size_bytes: 12909315072
size_human: 13G
mtime_utc: 2026-05-23 20:17:17 +0000
owner: linuxadmin:linuxadmin
mode: -rw-rw-r--
```

Existing older backup on the same server:

```text
path: /home/linuxadmin/Fitnes.bak
size_bytes: 12770610688
mtime_utc: 2026-04-29 20:57:02 +0000
owner: linuxadmin:linuxadmin
mode: -rw-rw-r--
```

## Notes

The file was only checked for presence, name, size, ownership, and modified
time. It was not copied locally and was not validated with SQL `RESTORE`
commands during this check.
