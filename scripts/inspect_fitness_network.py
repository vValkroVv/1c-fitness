#!/usr/bin/env python3
"""Capture packet headers and server TCP counters during a bounded rsync probe."""

import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True)
    parser.add_argument("--seconds", type=int, default=25)
    parser.add_argument("--proxy", action="store_true")
    args = parser.parse_args()
    if args.seconds < 5 or not args.label or any(c not in "abcdefghijklmnopqrstuvwxyz0123456789_-" for c in args.label):
        parser.error("Use a safe label and at least five seconds")
    root = Path(__file__).resolve().parents[1]
    os.chdir(root)
    logs = root / "logs"
    logs.mkdir(exist_ok=True)
    (root / "tmp").mkdir(exist_ok=True)
    children = []
    handles = []
    with tempfile.TemporaryDirectory(prefix="network_probe_", dir=root / "tmp") as temp:
        askpass = Path(temp) / "askpass.sh"
        askpass.write_text('#!/bin/sh\nprintf \'%s\\n\' "$PASS"\n')
        askpass.chmod(0o700)
        environment = dict(os.environ, SSH_ASKPASS=str(askpass), SSH_ASKPASS_REQUIRE="force", DISPLAY=":0")
        try:
            for interface, address in (("ppp0", os.environ["IP"]), ("en0", "94.140.224.135")):
                handle = (logs / f"{args.label}_{interface}.capture.log").open("wb")
                handles.append(handle)
                child = subprocess.Popen(["tcpdump", "-i", interface, "-nn", "-s", "96",
                                          "-w", str(logs / f"{args.label}_{interface}.pcap"),
                                          "host", address], stdout=handle, stderr=handle)
                children.append(child)
            remote_code = (
                "import subprocess,time\n"
                f"for i in range({args.seconds // 3 + 1}):\n"
                " print('SAMPLE',i,time.time(),flush=True)\n"
                " print(subprocess.check_output(['ss','-tin','dst','192.168.101.201'],text=True),flush=True)\n"
                " time.sleep(3)\n"
            )
            import shlex
            remote_command = "python3 -c " + shlex.quote(remote_code)
            handle = (logs / f"{args.label}_server_tcp.log").open("wb")
            handles.append(handle)
            monitor = subprocess.Popen(["ssh", "-b", "192.168.101.201", "-o", "ConnectTimeout=8",
                                        "-o", "StrictHostKeyChecking=yes", "-o", "NumberOfPasswordPrompts=1",
                                        f"{os.environ['LOGIN']}@{os.environ['IP']}", remote_command],
                                       stdin=subprocess.DEVNULL, stdout=handle, stderr=handle,
                                       env=environment, start_new_session=True)
            children.append(monitor)
            command = [sys.executable, "scripts/diagnose_backup_transfer.py", "--method", "rsync",
                       "--seconds", str(args.seconds), "--label", args.label]
            if args.proxy:
                command += ["--ssh-option", "ProxyCommand=nc -b ppp0 -s 192.168.101.201 %h %p"]
            subprocess.run(command, check=True)
            monitor.wait(timeout=15)
        finally:
            for child in children:
                if child.poll() is None:
                    child.send_signal(signal.SIGINT)
                    try:
                        child.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        child.wait()
            for handle in handles:
                handle.close()
    print(f"Packet headers and TCP snapshots saved with prefix logs/{args.label}_", flush=True)


if __name__ == "__main__":
    main()
