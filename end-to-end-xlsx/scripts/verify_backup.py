#!/usr/bin/env python3
"""Verify that a .bak file is the exact Fitnes-30-06-26.bak input."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]


def as_abs(path: str | Path) -> Path:
    value = Path(path)
    return value if value.is_absolute() else ROOT / value


def sha256(path: Path, block_size: int = 8 * 1024 * 1024) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(block_size):
            digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bak", help="Path to Fitnes-30-06-26.bak")
    parser.add_argument("--expected", default="reference/expected_20260630.yml")
    parser.add_argument(
        "--size-only", action="store_true", help="Skip the full SHA-256 pass"
    )
    args = parser.parse_args()

    backup_path = Path(args.bak).expanduser().resolve()
    expected = yaml.safe_load(as_abs(args.expected).read_text(encoding="utf-8"))[
        "backup"
    ]
    if not backup_path.is_file():
        raise FileNotFoundError(backup_path)

    actual_size = backup_path.stat().st_size
    expected_size = int(expected["size_bytes"])
    if actual_size != expected_size:
        print(f"verdict=FAIL size={actual_size} expected_size={expected_size}")
        return 1
    if args.size_only:
        print(f"verdict=PASS size={actual_size} sha256=SKIPPED")
        return 0

    actual_hash = sha256(backup_path)
    expected_hash = str(expected["sha256"]).lower()
    verdict = "PASS" if actual_hash == expected_hash else "FAIL"
    print(f"verdict={verdict} size={actual_size} sha256={actual_hash}")
    return 0 if verdict == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
