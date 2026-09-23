#!/usr/bin/env python3
"""Forward a loopback TCP port to SQL through Docker exec's binary stdin/stdout.

Use when Docker Desktop's published port stalls before TDS prelogin. This does
not change SQL, Docker networking, or VPN settings and never reads credentials.
Stop this foreground process after the export; the listener then disappears.
"""

import argparse
import select
import socketserver
import subprocess


REMOTE = """
import os, select, socket
connection = socket.create_connection(('127.0.0.1', 1433), timeout=15)
connection.settimeout(None)
try:
    while True:
        ready, _, _ = select.select([0, connection], [], [])
        if 0 in ready:
            chunk = os.read(0, 65536)
            if not chunk:
                break
            connection.sendall(chunk)
        if connection in ready:
            chunk = connection.recv(65536)
            if not chunk:
                break
            while chunk:
                chunk = chunk[os.write(1, chunk):]
finally:
    connection.close()
"""


class Bridge(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        process = subprocess.Popen(
            ["docker", "exec", "-i", self.server.container, "python3", "-u", "-c", REMOTE],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, bufsize=0,
        )
        try:
            while True:
                ready, _, _ = select.select([self.request, process.stdout], [], [])
                if self.request in ready:
                    chunk = self.request.recv(65536)
                    if not chunk:
                        break
                    while chunk:
                        written = process.stdin.write(chunk)
                        if not written:
                            raise BrokenPipeError("Docker input closed")
                        chunk = chunk[written:]
                if process.stdout in ready:
                    chunk = process.stdout.read(65536)
                    if not chunk:
                        break
                    self.request.sendall(chunk)
        except (BrokenPipeError, ConnectionResetError):
            pass
        finally:
            process.stdin.close()
            process.stdout.close()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.terminate()
                process.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", default="mssql-fitness-2022")
    parser.add_argument("--port", type=int, default=11435)
    args = parser.parse_args()
    with Bridge(("127.0.0.1", args.port), Handler) as server:
        server.container = args.container
        print(f"SQL bridge listening on 127.0.0.1:{args.port} via {args.container}", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass


if __name__ == "__main__":
    main()
