"""Integrity and resume checks using the real remote reader over a local process."""

import argparse
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from download_backup_parallel import REMOTE_CODE, download, sha256_file


class LocalTransport:
    def __init__(self):
        self.part_offsets = []
        self.bad_full_hash = False
        import threading
        self.cancelled = threading.Event()

    def request(self, request, output=None):
        if request["action"] == "part":
            self.part_offsets.append(request["offset"])
        result = subprocess.run([sys.executable, "-c", REMOTE_CODE, json.dumps(request)],
                                stdout=output if output is not None else subprocess.PIPE,
                                stderr=subprocess.PIPE)
        if result.returncode:
            raise RuntimeError(result.stderr.decode())
        if self.bad_full_hash and request["action"] == "hash":
            return b"0" * 64, result.stderr
        return result.stdout, result.stderr

    def cancel(self):
        self.cancelled.set()


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source.bak"
        self.source.write_bytes(os.urandom(2 * 1048576 + 137))
        self.output = self.root / "download.bak"
        self.args = argparse.Namespace(output=self.output, remote=str(self.source), host="local-test",
                                       part_mib=1, jobs=2, stop_after_parts=None)
        self.client = LocalTransport()

    def run_download(self):
        with contextlib.redirect_stdout(io.StringIO()):
            download(self.args, self.client)

    def test_complete_hash_and_short_last_chunk(self):
        self.run_download()
        self.assertEqual(self.output.read_bytes(), self.source.read_bytes())
        receipt = json.loads(self.output.with_name(self.output.name + ".verified.json").read_text())
        self.assertEqual(receipt["sha256"], sha256_file(self.source))

    def test_resume_does_not_fetch_verified_chunk_again(self):
        self.args.stop_after_parts = 1
        self.run_download()
        self.assertFalse(self.output.exists())
        self.client.part_offsets.clear()
        self.args.stop_after_parts = None
        self.run_download()
        self.assertNotIn(0, self.client.part_offsets)
        self.assertEqual(self.output.read_bytes(), self.source.read_bytes())

    def test_corrupt_saved_chunk_is_downloaded_again(self):
        self.args.stop_after_parts = 1
        self.run_download()
        part = self.root / "download.bak.parts" / "000000.part"
        with part.open("r+b") as stream:
            stream.write(b"CORRUPTED")
        self.client.part_offsets.clear()
        self.args.stop_after_parts = None
        self.run_download()
        self.assertIn(0, self.client.part_offsets)
        self.assertEqual(self.output.read_bytes(), self.source.read_bytes())

    def test_changed_remote_source_refuses_resume(self):
        self.args.stop_after_parts = 1
        self.run_download()
        with self.source.open("ab") as stream:
            stream.write(b"changed")
        with self.assertRaisesRegex(RuntimeError, "Source or chunk size changed"):
            self.run_download()
        self.assertFalse(self.output.exists())

    def test_bad_full_hash_does_not_publish_output(self):
        self.client.bad_full_hash = True
        with self.assertRaisesRegex(RuntimeError, "Complete file SHA-256"):
            self.run_download()
        self.assertFalse(self.output.exists())

    def test_existing_output_is_not_overwritten(self):
        self.output.write_bytes(b"existing download")
        with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
            self.run_download()
        self.assertEqual(self.output.read_bytes(), b"existing download")


if __name__ == "__main__":
    unittest.main()
