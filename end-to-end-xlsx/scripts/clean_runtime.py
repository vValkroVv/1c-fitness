#!/usr/bin/env python3
"""Remove generated work, logs, and XLSX files without touching package inputs."""

from __future__ import annotations

import shutil
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def main() -> None:
    for directory_name in ("work", "logs", "output"):
        directory = ROOT / directory_name
        for child in directory.iterdir():
            if child.name == ".gitkeep":
                continue
            if child.is_symlink() or child.is_file():
                child.unlink()
            else:
                shutil.rmtree(child)
        print(f"cleaned={directory}")
    for cache in ROOT.rglob("__pycache__"):
        if cache.is_dir() and not cache.is_symlink():
            shutil.rmtree(cache)
    for compiled in ROOT.rglob("*.py[co]"):
        compiled.unlink()
    print("cleaned=python caches")


if __name__ == "__main__":
    main()
