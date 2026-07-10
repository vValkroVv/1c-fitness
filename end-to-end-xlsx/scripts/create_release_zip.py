#!/usr/bin/env python3
"""Create a customer-safe ZIP without backups, secrets, outputs, or work data."""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKIP_PARTS = {".venv", "__pycache__"}
SKIP_NAMES = {".env", ".DS_Store"}
RUNTIME_DIRS = {"logs", "output", "work"}


def include(path: Path) -> bool:
    relative = path.relative_to(ROOT)
    if any(part in SKIP_PARTS for part in relative.parts):
        return False
    if path.name in SKIP_NAMES or path.suffix in {".pyc", ".bak"}:
        return False
    if relative.parts and relative.parts[0] in RUNTIME_DIRS and path.name != ".gitkeep":
        return False
    return True


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        default=str(ROOT.parent / "end-to-end-xlsx.zip"),
        help="Destination ZIP path",
    )
    args = parser.parse_args()
    output = Path(args.output).expanduser().resolve()
    if output == ROOT or ROOT in output.parents:
        raise ValueError("Release ZIP must be created outside the package directory")
    output.parent.mkdir(parents=True, exist_ok=True)

    files = [
        path
        for path in ROOT.rglob("*")
        if path.is_file() and not path.is_symlink() and include(path)
    ]
    with zipfile.ZipFile(
        output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for path in sorted(files):
            archive.write(path, Path(ROOT.name) / path.relative_to(ROOT))
    print(f"zip={output}")
    print(f"files={len(files)}")
    print(f"bytes={output.stat().st_size}")


if __name__ == "__main__":
    main()
