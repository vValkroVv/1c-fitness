# Backup transfer speed investigation — 2026-09-20

Later packet captures identified an MSS/fragmentation problem and a faster
configuration. See `docs/20260920_fast_backup_download.md` for the final
diagnosis, measured 32-stream result, and verified resumable downloader.
The observations below preserve the earlier investigation stages.

## Scope

Investigate the reported download speed of approximately 1 MB/s without
changing VPN settings, interrupting user processes, or writing to the partial
backup. Credentials were loaded from `.env`, never included in this report.

## Local transfer state

Two user-started rsync processes (7951 and 13357) and their SSH children were
in process state `T` (stopped). Both target `data/Fitnes-20-09-26.bak`.
The partial file was 63,799,296 bytes when inspected. These processes were
left untouched. Do not resume both against the same destination file.

The installed client is Apple openrsync, protocol 29, rsync 2.6.9-compatible.
Its local manual documents `--append`, whole-file checksum verification,
`--compress`, and `--compress-level`. No newer rsync executable was found in
the usual Homebrew locations. Remote rsync is 3.4.1, protocol 32.

## Network and server observations

- `fitness` and Sota Connect are both connected.
- The unscoped default route uses `utun5`.
- The route to `192.168.2.36` scoped to `ppp0` uses `ppp0`, MTU 1280.
- The fitness VPN endpoint `94.140.224.135` has an explicit route through
  `en0` and the local gateway. These routing observations do not support
  claiming that the fitness tunnel itself is nested inside Sota Connect.
- SSH bound to `192.168.101.201` connects successfully.
- Ten bound ICMP probes: 0% loss, RTT min/average/max 24.183/39.363/113.844 ms.
  This small sample cannot exclude loss during a sustained transfer.
- Server load average: 0.11, 0.06, 0.01.
- The stopped transfers' TCP statistics include retransmissions and
  reordering, but their receive-window limitation is confounded by the
  stopped clients and cannot establish the original speed bottleneck.

## Compression samples

Three 4 MiB regions were read on the server at offsets 0, 6,802,115,072, and
13,600,035,840, then compressed with zlib level 1. Compressed/original ratios
were 0.986, 0.967, and 0.985; each took about 0.18 seconds.

These samples suggest only 1–3% savings from compression. They do not justify
recommending `-z` as a substantial speed improvement for this particular file.
No claim about the SQL backup's compression flag was established.

## SSH throughput probes

Probe payloads were discarded locally, never written to the partial backup.
Timing includes SSH authentication and connection setup. Compression was
disabled. All results below have successful process exits.

| Probe | Payload | Elapsed seconds | MiB/s |
| --- | ---: | ---: | ---: |
| Default cipher selection, first probe | 8 MiB | 6.981 | 1.146 |
| AES-128-GCM, first probe | 8 MiB | 4.124 | 1.940 |
| AES-128-GCM, repeat | 16 MiB | 14.674 | 1.090 |
| Default cipher selection, repeat | 16 MiB | 14.344 | 1.115 |
| Four independent SSH streams, aggregate | 4 × 4 MiB | 8.502 | 1.882 |

The final four-stream test counted exactly 4,194,304 received bytes per
stream and verified all four exits. An earlier parallel timing probe did
not report per-stream completion and is excluded from the verified results.

The apparent first AES advantage did not survive the reversed-order repeat.
Four streams produced a modest short-probe improvement, but did not restore
the historical approximately 8.73 MB/s in the June download report. These
short probes are not a controlled sustained-throughput comparison.

## Conclusion and next steps

Low throughput reproduces outside rsync, with no destination disk writes.
Changing rsync flags or SSH ciphers has not demonstrated a reliable fix.
The network/VPN path is the main suspect, but these observations cannot
locate the limiting segment or conclusively exclude remote storage effects.

The useful next controlled checks are the same download over Ethernet or
another internet connection, then a fitness VPN reconnect and repeat.
Disabling Sota temporarily can be a separate comparison, but it is not an
established fix and was not done automatically. A server/network-side VPN
or outbound-bandwidth check is warranted if alternate client links remain
slow. Avoid changing MTU or routing without a separate measurement.

Keep one writer to the partial file. If a job was stopped with Ctrl+Z,
bring it to the foreground using `fg %<job-number>` from its owning shell
and terminate it with Ctrl+C before starting a replacement download.
The existing rsync `--partial --append` command remains suitable for resume.

## Sources consulted

- Official rsync manual: https://download.samba.org/pub/rsync/rsync.1
  (compression and append verification behavior).
- Official OpenSSH configuration manual: https://man.openbsd.org/ssh_config
  (compression, cipher selection, and IPQoS).
- Installed `man rsync` and `ssh -G` output were used to check local behavior;
  documentation for newer rsync/OpenSSH releases was not assumed to match
  the installed client.

## Retest after the user reconnected fitness

The user requested new measurements after reconnecting `fitness`, then
explicitly instructed not to touch Sota Connect. No Sota stop/start commands
were issued, and its settings were not changed.

Added `scripts/diagnose_backup_transfer.py` to run bounded transfer probes
into separate temporary directories. It reads exported credentials, uses a
temporary SSH askpass helper without embedding the password, records JSON
results and transfer logs in `logs/`, and removes only its own temporary
payloads. It does not write to `data/` or control VPN connections.

| Method | Probe elapsed | Received bytes | MiB/s |
| --- | ---: | ---: | ---: |
| rsync, `--partial --append --progress`, bound to fitness | 20.007 s | 26,017,792 | 1.240 |
| Legacy SCP (`scp -O`), bound to fitness | 20.008 s | 24,674,304 | 1.176 |
| SFTP (default `scp`), bound to fitness | 20.009 s | 23,761,920 | 1.133 |
| rsync without source binding | 5.040 s | 0 | 0 |

Each successful transfer probe was intentionally interrupted after 20
seconds, so its nonzero termination code is expected. These are throughput
measurements, not complete-download or backup-integrity checks. The rsync
transfer flags match the historical command; the diagnostic SSH command uses
the existing trusted host key, a connection timeout, and the equivalent
`BindAddress` setting. Measurements include connection/authentication time.

The unbound attempt failed before authentication with
`kex_exchange_identification: read: Connection reset by peer`.

The local Wi-Fi interface `en0` was active. Ethernet adapter interfaces
`en4`, `en5`, and `en6` were inactive, so an alternative physical internet
connection was not available to test automatically.

Results are consistent with the earlier low throughput. Neither the fitness
reconnect nor a change of transfer protocol demonstrated an improvement.
Keep rsync for its resume support. Testing another physical internet link
or investigating the VPN/server uplink remains necessary to localize the
network bottleneck; this retest did not establish its exact cause.

Result files:

- `logs/transfer_probe_fitness_reconnected_rsync.json`
- `logs/transfer_probe_fitness_reconnected_scp.json`
- `logs/transfer_probe_fitness_reconnected_sftp.json`
- `logs/transfer_probe_fitness_unbound.json`

Matching `.log` files contain process output.

## Mobile internet comparison

After the user switched to mobile internet, the same 20-second rsync probe
was repeated with source binding `192.168.101.201`. The active local address
changed to `172.20.10.9`; the route to the fitness endpoint `94.140.224.135`
used `en0` through mobile gateway `172.20.10.1`. Both VPNs were connected;
neither was modified by this test.

- Elapsed: 20.009 seconds, including connection/authentication.
- Received: 10,321,920 bytes.
- Throughput: **0.492 MiB/s**, versus **1.240 MiB/s** on the previous link.
- The mobile probe was about 2.5 times slower in this short comparison.
- Expected controlled interruption: rsync exit 20 after the time limit.
- Result: `logs/transfer_probe_mobile_fitness_rsync.json` and matching `.log`.

Mobile internet did not improve the transfer. These measurements do not
pinpoint the slow segment, but the previous internet link was faster in the
tested conditions. All payloads were written to the probe's own temporary
directory; the partial backup in `data/` was not used as a destination.
