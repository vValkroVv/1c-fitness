# Faster backup download — measured diagnosis and resumable command

Date: 2026-09-20. Source: `/home/linuxadmin/Fitnes.bak`, 13,604,230,144 bytes.
This is a transfer investigation, not SQL backup validation or a migration run.

## Result

The first concurrency benchmark reached **7.24 MiB/s aggregate** using 32
independent SSH connections, each explicitly bound to interface `ppp0` through
macOS `nc -b`. The original single rsync command measured 1.24–1.38 MiB/s.
The result is a short benchmark, not a guaranteed whole-file average.

The actual new downloader was then tested on 32 distinct 8 MiB ranges of
`Fitnes.bak`: **256 MiB received and SHA-256-verified in 37.406 seconds,
6.844 MiB/s**, including authentication, remote metadata checks, chunk
verification, and startup. This confirms the improvement in the delivered
downloader itself, not only in simultaneous rsync probes. The temporary
smoke-test chunks were removed; a full backup was not downloaded.

Sota Connect was not stopped, restarted, or reconfigured. The user's existing
partial `data/Fitnes-20-09-26.bak` was not used as a probe destination.

## Confirmed packet-size problem

Merely selecting the source IP with `ssh -b 192.168.101.201` did not cause
the connection to advertise an MSS appropriate for the fitness interface.
Packet captures showed:

| Observation | Original SSH source-IP binding | Explicit socket interface binding |
| --- | ---: | ---: |
| Local SYN advertised MSS | 1460 | 1240 |
| Server's active TCP data MSS | 1398 | 1228 |
| Typical inner IPv4 data packet length | 1450 bytes | 1280 bytes |
| Typical outer IPv4 packet lengths | 1500 + 56 bytes, fragmented | 1376 bytes, unfragmented |
| Outer IP fragments captured | 62,571 / 76,267 packets | 44 / 63,058 packets |
| One-stream throughput, observed run | 1.378 MiB/s | 1.929 MiB/s |

The observed `ppp0` MTU is 1280. The scoped connection advertised 1240,
which accounts for the minimum IPv4 and TCP headers. TCP timestamp options
further reduce its actual data MSS to 1228.

The outer captures include the small monitoring connection and other traffic
to the same VPN endpoint; the remaining 44 fragments cannot all be attributed
to the optimized download. This limitation does not change the major
difference in predominant packet sizes and fragmentation.

Active-flow server snapshots, taken before the transfer was stopped, also
showed fewer reordering observations (2,659 versus 109 in the last selected
samples). Retransmitted bytes were approximately 1.35% and 0.83% of bytes sent,
respectively. These are TCP retransmission counters, not a direct estimate of
physical-link packet loss. Stopped user sessions were excluded from these
comparisons.

The exact historical change since the June download is unknown: there is no
equivalent June packet capture. The evidence establishes a current
fragmentation problem and a measured workaround, not which software or
network setting originally changed.

## Disk, host limits, and remaining uncertainty

- Buffered reads of two 512 MiB backup regions: approximately 1,493–1,528 MiB/s.
- A 512 MiB aligned `O_DIRECT` read at offset 4 GiB: **699.2 MiB/s**, bypassing
  the server's normal file page cache. This does not bypass a hypervisor or
  storage-controller cache, but clearly exceeds the network transfer rate.
- A first `dd iflag=direct` attempt failed with invalid input. The successful
  replacement used page-aligned `mmap` memory with `os.readv`; the failed
  attempt was not treated as a disk-speed result.
- Server: 24 logical CPUs; low observed load, approximately 0.08 / 0.05 / 0.01.
- Server egress interface: `ens33`, MTU 1500; route to the VPN client through
  `192.168.2.254`.
- `tc`: ordinary `pfifo_fast`, no classes, no ingress/egress filters observed.
  No host traffic-control rate cap was found in these read-only checks.
- Server TCP congestion-control choices: `reno cubic`; current `cubic`.
- The server interface had historical RX drop counters. They do not identify
  where packets from this particular download were lost.
- The VPN gateway's configuration and counters were not available through
  the supplied file-server login. No claim is made that its limits, load, or
  upstream packet loss have been excluded.

The previous mobile-link comparison was slower (0.492 MiB/s). The later
successful optimization targets MSS/fragmentation and parallel TCP flows;
it does not require changing Sota or global routes/MTU settings.

## Parallelism measurements

Each stream downloaded into a separate disposable local file. SSH
authentications were staggered for the 16- and 32-stream runs. All streams
received data; no authentication failures occurred in those runs. Rates below
include startup and staggering overhead.

| Connections | Aggregate MiB/s |
| ---: | ---: |
| 1, explicit interface binding | 1.929–2.262 |
| 2 | 2.173 |
| 4 | 2.893 |
| 8 | 4.282 |
| 16 | 5.477 |
| 32 | 7.241 |

32 is the fastest configuration tested, not a proven absolute maximum.
At 7.24 MiB/s, payload transfer alone would take about 30 minutes for this
backup. Actual completion also depends on sustained network conditions,
chunk setup, local assembly, and checksum verification.

## Download command

Run from this repository while `fitness` is connected:

```bash
set -a
source .env
set +a
python3 scripts/download_backup_parallel.py \
  --output data/Fitnes-20-09-26.fast.bak \
  --jobs 32
```

The `.fast.bak` filename intentionally differs from the existing user-managed
partial download. The script refuses to overwrite any existing destination.
Do not resume the old rsync jobs at the same time, since they would compete
for bandwidth.

Interrupt with Ctrl+C and repeat the identical command to resume. Completed
64 MiB chunks are retained in `data/Fitnes-20-09-26.fast.bak.parts/` and checked
again before reuse. An incomplete chunk is downloaded again from its start.
The final `.bak` appears only after complete assembly and hash verification.

The script:

1. Locks its chunk directory against concurrent runs on the same destination.
2. Checks remote size, modification time, inode, and device before resuming.
3. Reads disjoint file ranges over independent SSH connections, without
   creating a second backup copy on the server or exposing a new server port.
4. Checks remote file identity before and after each read and compares each
   chunk's remote SHA-256 with the locally received data.
5. Assembles and verifies the complete SHA-256 against a fresh remote read.
6. Publishes the result without overwriting an existing file, writes a
   `.verified.json` receipt, and removes the downloaded chunk payloads.

Temporary storage peaks at about twice the backup size because assembly
coexists with the chunks. For this backup, allow roughly 26 GiB of free local
space before starting. The existing partial file is separate.

If one ordinary rsync connection is preferred, the tested interface binding
can also be used with its original resume flags:

```bash
rsync --partial --append --progress \
  -e 'ssh -o "ProxyCommand=nc -b ppp0 -s 192.168.101.201 %h %p" -o StrictHostKeyChecking=yes' \
  "$LOGIN@$IP:/home/linuxadmin/Fitnes.bak" \
  data/Fitnes-20-09-26.bak
```

Use that command only after terminating the old jobs targeting the same file.

## Verification

- Six local tests passed: complete-file integrity, short final chunk, reuse of
  verified chunks, recovery from a corrupt saved chunk, refusal to mix a
  changed source, refusal to publish a wrong full hash, and preservation of an
  existing destination (some checks share a test).
- Live SSH integration passed on a temporary 32 MiB server fixture: SIGINT
  produced exit 130, at least one verified chunk remained, restart finished
  with exit 0, and the complete local and remote SHA-256 matched.
- The integration fixture and its local data were removed after verification.
- A 32-worker smoke test on the actual backup passed: all 32 distinct chunks
  (256 MiB total) were verified, with 6.844 MiB/s overall throughput.
- These checks validate transfer behavior, not the SQL contents of Fitnes.bak.

## Artifacts

- `scripts/download_backup_parallel.py`: resumable verified downloader.
- `scripts/test_download_backup_parallel.py`: integrity and resume tests.
- `scripts/diagnose_backup_transfer.py`: bounded transfer benchmarks.
- `scripts/inspect_fitness_network.py`: packet headers and live TCP snapshots.
- `logs/fitness_packet_comparison.json`: capture and active-flow comparison.
- `logs/ordinary_observed_*.pcap`, `logs/nc_scoped_observed_*.pcap`: packet headers.
- `logs/fitness_parallel_{2,4,8,16,32}.json`: concurrency measurements.
- `logs/fitness_direct_read.json`: direct-I/O read result.
- `logs/fitness_server_storage_and_limits.log`: read-only host observations.
- `logs/fitness_parallel_live_validation.{json,log}`: actual interrupt/resume test.
- `logs/fitness_backup_32_stream_smoke.{json,log}`: actual backup chunk validation.

Background references: [Cisco L2TP MTU guidance](https://www.cisco.com/c/en/us/support/docs/dial-access/virtual-private-dialup-network-vpdn/24320-l2tp-mtu-tuning.html)
and the installed macOS `nc` manual, where `-b` binds the socket to an interface.

## Follow-up: more than 32 connections

At the user's request, `scripts/benchmark_backup_parallel.py` compared the
actual SSH reader after all connections had started receiving. A 20-second
measurement window excluded startup, so these steady rates should not be
directly compared with the earlier startup-inclusive rates.

| Connections | Steady MiB/s | Failed streams |
| ---: | ---: | ---: |
| 32 | 8.343 | 0 |
| 64 | 8.520 | 0 |
| 96 | 8.282 | 0 |

The 64-stream improvement was only about 2.1%, within the variation possible
in these short sequential probes. 96 did not improve the result. The user
chose 32 and started the downloader. The incomplete 128-stream test was
interrupted with SIGINT; its benchmark process and owned connections were
cleaned up. The user's downloader was left running.

The downloader default and accepted limit remain 32. Raw completed results:
`logs/fitness_steady_parallel_{32,64,96}.json`. No result is claimed for 128.
