#!/usr/bin/env python3
"""Package a READY delivery and verify every archived file before publication."""

import argparse
import hashlib
import json
from pathlib import Path
import zipfile


def sha256(path):
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--delivery", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    delivery, output = args.delivery.resolve(strict=True), args.output.resolve()
    if output.is_relative_to(delivery) or output.exists():
        raise ValueError("Use a new archive path outside the delivery directory")
    manifest = json.loads((delivery / "reports/delivery_manifest.json").read_text())
    if manifest["verdict"] != "PASS" or (delivery / "READY.txt").read_text().splitlines()[0] != "PASS":
        raise ValueError("Delivery has not passed its publication checks")
    actual = {p.name for p in delivery.iterdir() if p.suffix in {".xlsx", ".zip"}}
    if actual != {row["name"] for row in manifest["files"]}:
        raise ValueError("Unexpected or missing delivery artifacts")
    for entry in manifest["files"]:
        path = delivery / entry["name"]
        if path.stat().st_size != entry["size_bytes"] or sha256(path) != entry["sha256"]:
            raise ValueError(f"Artifact changed after validation: {path.name}")
    paths = sorted(p for p in delivery.rglob("*") if p.is_file())
    fingerprints = {str(p.relative_to(delivery)): sha256(p) for p in paths}
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".partial")
    try:
        with zipfile.ZipFile(temporary, "x", compression=zipfile.ZIP_STORED, allowZip64=True) as archive:
            for path in paths:
                archive.write(path, arcname=str(path.relative_to(delivery)))
        with zipfile.ZipFile(temporary) as archive:
            if set(archive.namelist()) != set(fingerprints):
                raise ValueError("Archive members differ from the verified file set")
            for name, expected in fingerprints.items():
                result = hashlib.sha256()
                with archive.open(name) as handle:
                    for block in iter(lambda: handle.read(8 * 1024 * 1024), b""):
                        result.update(block)
                if result.hexdigest() != expected:
                    raise ValueError(f"Archived file differs: {name}")
                if sha256(delivery / name) != expected:
                    raise ValueError(f"Source changed during packaging: {name}")
        archive_hash = sha256(temporary)
        temporary.rename(output)
        output.with_suffix(output.suffix + ".sha256").write_text(
            f"{archive_hash}  {output.name}\n", encoding="utf-8"
        )
        print(json.dumps({"status": "PASS", "archive": str(output), "files": len(paths),
                          "size_bytes": output.stat().st_size, "sha256": archive_hash}, ensure_ascii=False))
    except Exception:
        # Preserve a failed partial archive for diagnosis; never publish it.
        raise


if __name__ == "__main__":
    main()
