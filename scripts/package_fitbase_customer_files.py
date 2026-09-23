#!/usr/bin/env python3
"""Copy only the validated XLSX and photo ZIP into a customer folder/archive."""

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile


def file_hash(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--folder", type=Path, required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    folder, archive = args.folder.resolve(), args.archive.resolve()
    if folder.exists() or archive.exists():
        raise ValueError("Use new customer folder and archive paths")
    if folder.is_relative_to(source) or archive.is_relative_to(folder):
        raise ValueError("Keep the customer folder and archive separate from the source")
    manifest = json.loads((source / "reports/delivery_manifest.json").read_text())
    assert manifest["verdict"] == "PASS"
    assert (source / "READY.txt").read_text().splitlines()[0] == "PASS"
    entries = manifest["files"]
    names = [row["name"] for row in entries]
    assert len(names) == len(set(names)) == 8
    assert sum(Path(name).suffix == ".xlsx" for name in names) == 7
    assert sum(Path(name).suffix == ".zip" for name in names) == 1
    for row in entries:
        assert Path(row["name"]).name == row["name"]
        path = source / row["name"]
        assert path.stat().st_size == row["size_bytes"]
        assert file_hash(path) == row["sha256"]
    folder.mkdir(parents=True)
    for row in entries:
        destination = folder / row["name"]
        shutil.copy2(source / row["name"], destination)
        assert file_hash(destination) == row["sha256"]
    assert {p.name for p in folder.iterdir()} == set(names)
    temporary = archive.with_name(archive.name + ".partial")
    with zipfile.ZipFile(temporary, "x", compression=zipfile.ZIP_STORED, allowZip64=True) as output:
        for name in names:
            output.write(folder / name, arcname=name)
    with zipfile.ZipFile(temporary) as output:
        assert set(output.namelist()) == set(names) and len(output.infolist()) == 8
        for row in entries:
            digest = hashlib.sha256()
            with output.open(row["name"]) as stream:
                for block in iter(lambda: stream.read(8 * 1024 * 1024), b""):
                    digest.update(block)
            assert digest.hexdigest() == row["sha256"]
            assert file_hash(folder / row["name"]) == row["sha256"]
    checksum = file_hash(temporary)
    temporary.rename(archive)
    result = {
        "status": "PASS", "source": str(source), "customer_folder": str(folder),
        "customer_archive": str(archive), "files": entries,
        "file_count": 8, "archive_bytes": archive.stat().st_size,
        "archive_sha256": checksum, "cutoff_contract": manifest["cutoff_contract"],
        "verification": "All folder/ZIP file sets, sizes, SHA-256 and ZIP member CRC checked",
    }
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({k: v for k, v in result.items() if k != "files"}, ensure_ascii=False))


if __name__ == "__main__":
    main()
