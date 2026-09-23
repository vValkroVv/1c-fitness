#!/usr/bin/env python3
"""Download verified chunks over independent SSH connections; resume completed chunks."""

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import fcntl
import getpass
import hashlib
import json
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile
import threading
import time


REMOTE_CODE = r'''
import hashlib,json,os,sys
request=json.loads(sys.argv[1])
path=request['path']
def identity(s):
 return {'size':s.st_size,'mtime_ns':s.st_mtime_ns,'inode':s.st_ino,'device':s.st_dev}
if request['action']=='stat':
 print(json.dumps(identity(os.stat(path))))
else:
 with open(path,'rb',buffering=0) as source:
  expected=request['identity']
  if identity(os.fstat(source.fileno()))!=expected or identity(os.stat(path))!=expected:
   raise RuntimeError('Remote file changed')
  digest=hashlib.sha256()
  if request['action']=='part':
   source.seek(request['offset'])
   remaining=request['length']
   while remaining:
    data=source.read(min(1024*1024,remaining))
    if not data: raise RuntimeError('Unexpected EOF')
    digest.update(data)
    sys.stdout.buffer.write(data)
    remaining-=len(data)
   sys.stdout.buffer.flush()
  else:
   while True:
    data=source.read(8*1024*1024)
    if not data: break
    digest.update(data)
  if identity(os.fstat(source.fileno()))!=expected or identity(os.stat(path))!=expected:
   raise RuntimeError('Remote file changed while reading')
  if request['action']=='part':
   print('PART_SHA256='+digest.hexdigest(),file=sys.stderr,flush=True)
  else:
   print(digest.hexdigest(),flush=True)
'''


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def write_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


class SSHClient:
    """Keep credentials out of arguments and stop only this client's processes."""

    def __init__(self, login, host, password, interface, bind, directory):
        helper = directory / "askpass.sh"
        helper.write_text('#!/bin/sh\nprintf \'%s\\n\' "$FITNESS_DOWNLOAD_PASSWORD"\n')
        helper.chmod(0o700)
        self.environment = dict(os.environ, FITNESS_DOWNLOAD_PASSWORD=password,
                                SSH_ASKPASS=str(helper), SSH_ASKPASS_REQUIRE="force", DISPLAY=":0")
        proxy = shlex.join(["/usr/bin/nc", "-b", interface, "-s", bind, "%h", "%p"])
        self.command = ["ssh", "-o", f"ProxyCommand={proxy}",
                        "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=10",
                        "-o", "ConnectionAttempts=1", "-o", "NumberOfPasswordPrompts=1",
                        "-o", "ServerAliveInterval=10", "-o", "ServerAliveCountMax=3",
                        "-o", "Compression=no", f"{login}@{host}"]
        self.lock = threading.Lock()
        self.processes = set()
        self.cancelled = threading.Event()
        self.next_start = 0.0

    def run(self, remote_command, output=None, timeout=900):
        # Stagger authentications to avoid flooding sshd's MaxStartups limit.
        with self.lock:
            delay = max(0, self.next_start - time.monotonic())
            self.next_start = max(self.next_start, time.monotonic()) + 0.15
        if self.cancelled.wait(delay):
            raise RuntimeError("Download cancelled")
        with self.lock:
            if self.cancelled.is_set():
                raise RuntimeError("Download cancelled")
            process = subprocess.Popen([*self.command, remote_command], stdin=subprocess.DEVNULL,
                                       stdout=output if output is not None else subprocess.PIPE,
                                       stderr=subprocess.PIPE, env=self.environment, start_new_session=True)
            self.processes.add(process)
        try:
            stdout, stderr = process.communicate(timeout=timeout)
            if process.returncode:
                raise RuntimeError(stderr.decode(errors="replace").strip() or f"SSH exit {process.returncode}")
            return stdout, stderr
        finally:
            if process.poll() is None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                except ProcessLookupError:
                    pass
            with self.lock:
                self.processes.discard(process)

    def request(self, request, output=None):
        command = shlex.join(["python3", "-c", REMOTE_CODE, json.dumps(request)])
        return self.run(command, output)

    def cancel(self):
        self.cancelled.set()
        with self.lock:
            for process in self.processes:
                if process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass


def download(args, client):
    output = args.output.resolve()
    if output.exists():
        raise RuntimeError(f"Destination already exists; refusing to overwrite: {output}")
    parts = output.with_name(output.name + ".parts")
    parts.mkdir(parents=True, exist_ok=True)
    with (parts / "lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("Another downloader owns this destination") from exc
        identity = json.loads(client.request({"action": "stat", "path": args.remote})[0])
        manifest = {"version": 1, "host": args.host, "remote": args.remote,
                    "identity": identity, "part_bytes": args.part_mib * 1048576}
        manifest_path = parts / "manifest.json"
        if manifest_path.exists():
            if json.loads(manifest_path.read_text()) != manifest:
                raise RuntimeError("Source or chunk size changed; use a different output filename")
        else:
            write_json(manifest_path, manifest)
        size, chunk = identity["size"], manifest["part_bytes"]
        count = (size + chunk - 1) // chunk
        completed = {}
        pending = []
        for index in range(count):
            path = parts / f"{index:06d}.part"
            metadata = path.with_suffix(".json")
            expected_size = min(chunk, size - index * chunk)
            valid = False
            if path.exists() and metadata.exists():
                try:
                    record = json.loads(metadata.read_text())
                    valid = (record["offset"] == index * chunk and record["length"] == expected_size
                             and path.stat().st_size == expected_size
                             and sha256_file(path) == record["sha256"])
                except (KeyError, ValueError):
                    valid = False
            if valid:
                completed[index] = record
            else:
                pending.append(index)
        selected = pending[:args.stop_after_parts] if args.stop_after_parts else pending
        remaining = sum(min(chunk, size - index * chunk) for index in selected)
        # Full completion temporarily needs the chunks plus the assembled output.
        required = remaining + (size if len(selected) == len(pending) else 0)
        if shutil.disk_usage(parts).free < required + 64 * 1048576:
            raise RuntimeError(f"Not enough disk space: need approximately {required / 1024**3:.2f} GiB free")
        print(f"Source: {size:,} bytes; verified chunks: {len(completed)}/{count}; workers: {args.jobs}", flush=True)
        started = time.monotonic()
        transferred = 0

        def fetch(index):
            path = parts / f"{index:06d}.part"
            temporary = path.with_suffix(".partial")
            length = min(chunk, size - index * chunk)
            request = {"action": "part", "path": args.remote, "identity": identity,
                       "offset": index * chunk, "length": length}
            for attempt in range(3):
                try:
                    with temporary.open("wb") as destination:
                        _, stderr = client.request(request, destination)
                    hashes = [line.split("=", 1)[1] for line in stderr.decode().splitlines()
                              if line.startswith("PART_SHA256=")]
                    digest = sha256_file(temporary)
                    if temporary.stat().st_size != length or hashes != [digest]:
                        raise RuntimeError(f"Chunk {index}: size or SHA-256 mismatch")
                    record = {"offset": index * chunk, "length": length, "sha256": digest}
                    temporary.replace(path)
                    write_json(path.with_suffix(".json"), record)
                    return index, record
                except (RuntimeError, subprocess.TimeoutExpired):
                    if attempt == 2 or client.cancelled.wait(attempt + 1):
                        raise

        pool = ThreadPoolExecutor(max_workers=args.jobs)
        try:
            futures = [pool.submit(fetch, index) for index in selected]
            for future in as_completed(futures):
                index, record = future.result()
                completed[index] = record
                transferred += record["length"]
                elapsed = time.monotonic() - started
                print(f"Verified {len(completed)}/{count} chunks; {transferred / elapsed / 1048576:.2f} MiB/s", flush=True)
        except BaseException:
            client.cancel()
            raise
        finally:
            pool.shutdown(wait=True, cancel_futures=True)
        if len(completed) != count:
            print("Stopped at the requested chunk limit; repeat the command to resume.", flush=True)
            return
        print("Assembling the file and checking the complete SHA-256...", flush=True)
        assembled = parts / "assembled.tmp"
        digest = hashlib.sha256()
        with assembled.open("wb") as destination:
            for index in range(count):
                with (parts / f"{index:06d}.part").open("rb") as source:
                    for block in iter(lambda: source.read(8 * 1024 * 1024), b""):
                        destination.write(block)
                        digest.update(block)
            destination.flush()
            os.fsync(destination.fileno())
        remote_hash = client.request({"action": "hash", "path": args.remote, "identity": identity})[0].decode().strip()
        if digest.hexdigest() != remote_hash or assembled.stat().st_size != size:
            raise RuntimeError("Complete file SHA-256 or size mismatch; output not published")
        receipt = {**manifest, "sha256": remote_hash, "output": str(output)}
        # Hard-link publication fails atomically if another process created output.
        os.link(assembled, output)
        assembled.unlink()
        write_json(output.with_name(output.name + ".verified.json"), receipt)
        for index in range(count):
            (parts / f"{index:06d}.part").unlink()
            (parts / f"{index:06d}.json").unlink()
        print(f"Verified download complete: {output}\nSHA-256: {remote_hash}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--remote", default="/home/linuxadmin/Fitnes.bak")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--jobs", type=int, default=32)
    parser.add_argument("--part-mib", type=int, default=64)
    parser.add_argument("--stop-after-parts", type=int, help="Stop after this many new chunks (for diagnostics)")
    parser.add_argument("--host", default=os.environ.get("IP"))
    parser.add_argument("--login", default=os.environ.get("LOGIN"))
    parser.add_argument("--interface", default="ppp0")
    parser.add_argument("--bind", default="192.168.101.201")
    args = parser.parse_args()
    if not args.host or not args.login:
        parser.error("Export IP and LOGIN from .env, or pass --host and --login")
    if not 1 <= args.jobs <= 32 or args.part_mib < 1 or (args.stop_after_parts is not None and args.stop_after_parts < 1):
        parser.error("Use 1–32 workers, a positive chunk size and a positive chunk limit")
    password = os.environ.get("PASS") or getpass.getpass("SSH password: ")
    try:
        with tempfile.TemporaryDirectory(prefix="fitness_ssh_") as directory:
            client = SSHClient(args.login, args.host, password, args.interface, args.bind, Path(directory))
            try:
                download(args, client)
            finally:
                client.cancel()
    except KeyboardInterrupt:
        print("\nInterrupted. Verified chunks are saved; repeat the same command to resume.", flush=True)
        raise SystemExit(130)
    except (RuntimeError, OSError, ValueError, subprocess.TimeoutExpired) as exc:
        parser.exit(1, f"Error: {exc}\n")


if __name__ == "__main__":
    main()
