#!/usr/bin/env python3
"""Measure a short download to a disposable file without touching data/."""

import argparse
import json
import os
from pathlib import Path
import shlex
import signal
import subprocess
import tempfile
import time


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--method", choices=("rsync", "scp", "sftp"), required=True)
    parser.add_argument("--bind", default="192.168.101.201", help="Source IP, or none")
    parser.add_argument("--seconds", type=float, default=20)
    parser.add_argument("--label", required=True)
    parser.add_argument("--ssh-option", action="append", default=[],
                        help="Additional OpenSSH option, e.g. ProxyCommand=nc -b ppp0 %%h %%p")
    parser.add_argument("--sftp-requests", type=int, help="Outstanding SFTP requests")
    args = parser.parse_args()
    if args.seconds <= 0:
        parser.error("--seconds must be positive")
    if not args.label or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in args.label):
        parser.error("--label must contain lowercase letters, digits, underscores or hyphens")
    for name in ("LOGIN", "IP", "PASS"):
        if not os.environ.get(name):
            parser.error(f"Export {name} from .env before running")

    root = Path(__file__).resolve().parents[1]
    (root / "tmp").mkdir(exist_ok=True)
    (root / "logs").mkdir(exist_ok=True)
    log_path = root / "logs" / f"transfer_probe_{args.label}.log"
    result_path = log_path.with_suffix(".json")
    options = ["-o", "ConnectTimeout=6", "-o", "ConnectionAttempts=1",
               "-o", "StrictHostKeyChecking=yes", "-o", "NumberOfPasswordPrompts=1"]
    if args.bind != "none":
        options += ["-o", f"BindAddress={args.bind}"]
    for option in args.ssh_option:
        options += ["-o", option]
    remote = f"{os.environ['LOGIN']}@{os.environ['IP']}:/home/linuxadmin/Fitnes.bak"

    with tempfile.TemporaryDirectory(prefix="transfer_probe_", dir=root / "tmp") as directory:
        directory = Path(directory)
        destination = directory / "sample.bak"
        askpass = directory / "askpass.sh"
        askpass.write_text('#!/bin/sh\nprintf \'%s\\n\' "$PASS"\n')
        askpass.chmod(0o700)
        environment = dict(os.environ, SSH_ASKPASS=str(askpass),
                           SSH_ASKPASS_REQUIRE="force", DISPLAY=":0")
        if args.method == "rsync":
            command = ["/usr/bin/rsync", "--partial", "--append", "--progress",
                       "-e", shlex.join(["ssh", *options]), remote, str(destination)]
        else:
            # OpenSSH scp uses SFTP by default; -O selects the legacy SCP protocol.
            command = ["scp", *(["-O"] if args.method == "scp" else []),
                       *options]
            if args.method == "sftp" and args.sftp_requests:
                command += ["-X", f"nrequests={args.sftp_requests}"]
            command += [remote, str(destination)]
        started = time.monotonic()
        stopped_by_probe = False
        with log_path.open("wb") as log:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL,
                                       stdout=log, stderr=subprocess.STDOUT,
                                       env=environment, start_new_session=True)
            try:
                try:
                    process.wait(timeout=args.seconds)
                except subprocess.TimeoutExpired:
                    stopped_by_probe = True
            finally:
                if process.poll() is None:
                    os.killpg(process.pid, signal.SIGINT)
                    try:
                        process.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
        elapsed = time.monotonic() - started
        size = destination.stat().st_size if destination.exists() else 0
        result = dict(label=args.label, method=args.method, bind=args.bind,
                      ssh_options=args.ssh_option, sftp_requests=args.sftp_requests,
                      seconds=round(elapsed, 3), bytes=size,
                      MiB_per_second=round(size / elapsed / 1048576, 3),
                      stopped_by_probe=stopped_by_probe, returncode=process.returncode,
                      log=str(log_path))
        result_path.write_text(json.dumps(result, indent=2) + "\n")
        print(json.dumps(result), flush=True)
        if not size:
            print(log_path.read_text(errors="replace")[-2500:], flush=True)


if __name__ == "__main__":
    main()
