#!/usr/bin/env python3
"""Compare steady SSH throughput after every connection has started receiving."""

import argparse
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import threading
import time

from download_backup_parallel import REMOTE_CODE, SSHClient


def benchmark(client, streams, seconds, root, label, identity):
    request = {"action": "part", "path": "/home/linuxadmin/Fitnes.bak", "identity": identity,
               "offset": 0, "length": identity["size"]}
    command = [*client.command, shlex.join(["python3", "-c", REMOTE_CODE, json.dumps(request)])]
    processes, threads, handles = [], [], []
    received = [0] * streams
    first_byte = [None] * streams
    reader_errors = []
    lock = threading.Lock()
    started = time.monotonic()

    def receive(index, process):
        try:
            while block := os.read(process.stdout.fileno(), 65536):
                with lock:
                    received[index] += len(block)
                    if first_byte[index] is None:
                        first_byte[index] = time.monotonic() - started
        except OSError as exc:
            with lock:
                reader_errors.append(str(exc))

    try:
        for index in range(streams):
            handle = (root / "logs" / f"{label}_{streams}_{index}.stderr.log").open("wb")
            handles.append(handle)
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=handle, env=client.environment, start_new_session=True)
            processes.append(process)
            thread = threading.Thread(target=receive, args=(index, process), daemon=True)
            thread.start()
            threads.append(thread)
            time.sleep(0.15)
        ready_deadline = time.monotonic() + 20
        while time.monotonic() < ready_deadline:
            if all(value is not None for value in first_byte) or any(p.poll() is not None for p in processes):
                break
            time.sleep(0.1)
        time.sleep(3)
        with lock:
            before = sum(received)
        measurement_start = time.monotonic()
        time.sleep(seconds)
        measurement_elapsed = time.monotonic() - measurement_start
        with lock:
            after = sum(received)
            per_stream = received.copy()
        failed = [i for i, process in enumerate(processes) if process.poll() is not None]
        result = {"streams": streams, "measurement_seconds": measurement_elapsed,
                  "steady_MiB_per_second": (after - before) / measurement_elapsed / 1048576,
                  "overall_MiB_per_second": after / (time.monotonic() - started) / 1048576,
                  "total_bytes_received": after, "per_stream_bytes": per_stream,
                  "first_byte_seconds": first_byte, "failed_streams": failed,
                  "reader_errors": reader_errors, "all_streams_received": all(per_stream)}
        (root / "logs" / f"{label}_{streams}.json").write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps({key: value for key, value in result.items()
                          if key not in ("per_stream_bytes", "first_byte_seconds")}), flush=True)
        return result
    finally:
        for process in processes:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for process in processes:
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait()
        for thread in threads:
            thread.join(timeout=5)
        for process in processes:
            process.stdout.close()
        for handle in handles:
            handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--streams", type=int, nargs="+", default=[32, 64, 96, 128])
    parser.add_argument("--seconds", type=int, default=20)
    parser.add_argument("--label", default="fitness_steady_parallel")
    args = parser.parse_args()
    if any(not 1 <= value <= 128 for value in args.streams) or args.seconds < 5:
        parser.error("Use 1–128 streams and at least five seconds")
    if not args.label or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in args.label):
        parser.error("Use a safe label")
    root = Path(__file__).resolve().parents[1]
    (root / "logs").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="fitness_parallel_benchmark_") as directory:
        client = SSHClient(os.environ["LOGIN"], os.environ["IP"], os.environ["PASS"],
                           "ppp0", "192.168.101.201", Path(directory))
        try:
            identity = json.loads(client.request({"action": "stat", "path": "/home/linuxadmin/Fitnes.bak"})[0])
            for streams in args.streams:
                result = benchmark(client, streams, args.seconds, root, args.label, identity)
                if result["failed_streams"] or not result["all_streams_received"]:
                    print("Stopping escalation after connection failures.", flush=True)
                    break
        finally:
            client.cancel()


if __name__ == "__main__":
    main()
