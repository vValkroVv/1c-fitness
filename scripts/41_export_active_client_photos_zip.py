#!/usr/bin/env python3
"""Export active-client photos from the restored 1C database into one ZIP.

The SQL backup does not store client photos as plain JPEG columns.  The file
payload is wrapped in a small 1C container and stored in ``_InfoRg6767``.  This
script selects exactly one usable photo per active client, decodes the
container, gives the image a deterministic phone-based name, and writes a
validated ZIP without creating a directory full of personal photos on disk.

The archive contains a manifest because two data-quality cases cannot satisfy
the ideal ``<phone>.jpg`` rule literally:

* two clients can share the same normalized phone;
* a client card can contain no valid phone at all.

Those cases receive an explicit client-ID suffix so no image is overwritten.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys
import zlib
import zipfile
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "output" / "test_active_client_photos_20260630.zip"
DEFAULT_INNER_DIR = "test_active_client_photos_20260630"
DEFAULT_CONTAINER = "mssql-fitness-2022"
DEFAULT_DATABASE = "FitnessRestored_20260630_macos"
DEFAULT_CUTOFF_AT = "2026-06-30 23:27:03"
DEFAULT_EXPECTED_COUNT = 10_926
BACKUP_HEADER_LOG = ROOT / "logs" / "macos-backup" / "restore_headeronly_20260630.txt"

PHONE_SPLIT_RE = re.compile(r"[,;]\s*")
SAFE_IDENTIFIER_RE = re.compile(r"^[A-Za-z0-9_]+$")
SAFE_CONTAINER_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
ZIP_TIMESTAMP = (2026, 6, 30, 23, 27, 2)  # ZIP stores seconds with 2-second precision.
IMAGE_SIGNATURES: tuple[tuple[bytes, str], ...] = (
    (bytes.fromhex("FFD8FF"), "jpg"),
    (bytes.fromhex("89504E470D0A1A0A"), "png"),
    (b"BM", "bmp"),
    (b"GIF8", "gif"),
)


@dataclass(frozen=True)
class PhotoMeta:
    client_id: str
    raw_phone: str
    source: str
    metadata_extension: str
    normalized_phones: tuple[str, ...]


@dataclass(frozen=True)
class NameAssignment:
    basename: str
    assigned_phone: str
    status: str


def require_safe_identifier(value: str, label: str) -> str:
    """Allow only the identifier subset needed by the known runtime names."""

    if not SAFE_IDENTIFIER_RE.fullmatch(value):
        raise ValueError(f"Unsafe {label}: {value!r}")
    return value


def require_safe_container(value: str) -> str:
    """Validate a Docker container name passed as a direct argv element."""

    if not SAFE_CONTAINER_RE.fullmatch(value):
        raise ValueError(f"Unsafe container name: {value!r}")
    return value


def normalize_phone_token(value: str) -> str:
    """Normalize Russian mobile/telephone numbers like the accepted XLSX pipeline."""

    digits = re.sub(r"\D+", "", value or "")
    if len(digits) == 11 and digits[0] in {"7", "8"}:
        return "7" + digits[1:]
    if len(digits) == 10:
        return "7" + digits
    return ""


def normalize_phones(value: str) -> tuple[str, ...]:
    """Return unique valid phones while preserving their order in the client card."""

    result: list[str] = []
    for token in PHONE_SPLIT_RE.split(value or ""):
        phone = normalize_phone_token(token)
        if phone and phone not in result:
            result.append(phone)
    return tuple(result)


def report_text(value: str) -> str:
    """Keep CSV rows one-line and make embedded NUL values visible."""

    return (value or "").replace("\x00", "\\0").replace("\t", " ").replace("\r", " ").replace("\n", " ")


def sql_selected_union(database: str, *, include_blob: bool, cutoff_date: str) -> str:
    """Build the accepted one-photo-per-active-client SQL selection.

    Newer records expose their main file through ``_Fld3834 -> Reference65``.
    Older records expose the in-backup migrated copy through
    ``_Fld9193 -> Reference115``.  Both payloads live in ``_InfoRg6767``.
    """

    db = f"[{require_safe_identifier(database, 'database name')}]"
    phone_sql = (
        "REPLACE(REPLACE(REPLACE(c._Fld3832, CHAR(9), N' '), "
        "CHAR(10), N' '), CHAR(13), N' ')"
    )
    blob_column = ", i._Fld6769 AS blob_value" if include_blob else ""

    newer = f"""
        SELECT
            c._Code AS client_id,
            {phone_sql} AS raw_phone,
            N'Reference65_main' AS photo_source,
            LOWER(f._Fld3884) AS metadata_extension
            {blob_column}
        FROM {db}.dbo._Reference64 AS c
        JOIN {db}.fitbase_part2.final_funnel_clients AS a
          ON a.client_ref = CONVERT(varchar(32), c._IDRRef, 2)
        JOIN {db}.dbo._Reference65 AS f
          ON c._Fld3834_RTRef = 0x00000041
         AND f._IDRRef = c._Fld3834_RRRef
        JOIN {db}.dbo._InfoRg6767 AS i
          ON i._Fld6768_RTRef = 0x00000041
         AND i._Fld6768_RRRef = f._IDRRef
        WHERE a.funnel = N'Действующие клиенты'
          AND a.cutoff_date = CONVERT(date, '{cutoff_date}', 112)
          AND LOWER(f._Fld3884) IN (N'jpg', N'jpeg', N'png', N'bmp', N'gif')
    """
    older = f"""
        SELECT
            c._Code AS client_id,
            {phone_sql} AS raw_phone,
            N'Reference115_copy' AS photo_source,
            LOWER(f._Fld4606) AS metadata_extension
            {blob_column}
        FROM {db}.dbo._Reference64 AS c
        JOIN {db}.fitbase_part2.final_funnel_clients AS a
          ON a.client_ref = CONVERT(varchar(32), c._IDRRef, 2)
        JOIN {db}.dbo._Reference115 AS f
          ON c._Fld3834_RTRef = 0x00000073
         AND c._Fld9193_RTRef = 0x00000073
         AND f._IDRRef = c._Fld9193_RRRef
        JOIN {db}.dbo._InfoRg6767 AS i
          ON i._Fld6768_RTRef = 0x00000073
         AND i._Fld6768_RRRef = f._IDRRef
        WHERE a.funnel = N'Действующие клиенты'
          AND a.cutoff_date = CONVERT(date, '{cutoff_date}', 112)
          AND LOWER(f._Fld4606) IN (N'jpg', N'jpeg', N'png', N'bmp', N'gif')
    """

    columns = "client_id, raw_phone, photo_source, metadata_extension"
    if include_blob:
        columns += ", blob_value"
    query = f"""
        SELECT {columns}
        FROM (
            {newer}
            UNION ALL
            {older}
        ) AS selected
        ORDER BY TRY_CONVERT(bigint, client_id), client_id
    """
    return " ".join(query.split())


def bcp_command(container: str, query: str) -> list[str]:
    """Run BCP inside the existing SQL Server container and stream UTF-8 rows."""

    require_safe_container(container)
    return [
        "docker",
        "exec",
        container,
        "/bin/bash",
        "-lc",
        'exec /opt/mssql-tools18/bin/bcp "$@" -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -u',
        "bcp",
        query,
        "queryout",
        "/dev/stdout",
        "-c",
        "-C",
        "65001",
        "-t",
        "\t",
        "-r",
        "\n",
    ]


def start_bcp(container: str, query: str) -> subprocess.Popen[bytes]:
    """Start BCP with stdout available as a row stream."""

    process = subprocess.Popen(
        bcp_command(container, query),
        cwd=ROOT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if process.stdout is None or process.stderr is None:  # pragma: no cover - defensive
        process.kill()
        raise RuntimeError("Could not open BCP pipes")
    return process


def finish_bcp(process: subprocess.Popen[bytes], unexpected_lines: Sequence[bytes]) -> None:
    """Check BCP completion after its data stream has been consumed."""

    stderr = process.stderr.read().decode("utf-8", errors="replace")
    return_code = process.wait()
    if return_code != 0:
        details = stderr.strip() or b"\n".join(unexpected_lines[-10:]).decode("utf-8", errors="replace")
        raise RuntimeError(f"BCP failed with exit code {return_code}: {details}")
    if unexpected_lines:
        sample = b"\n".join(unexpected_lines[:3]).decode("utf-8", errors="replace")
        raise RuntimeError(f"Unexpected BCP output while reading data rows: {sample}")


def is_bcp_status_line(line: bytes) -> bool:
    stripped = line.strip()
    return (
        not stripped
        or stripped.startswith(b"Starting copy")
        or b" rows copied." in stripped
        or b" rows successfully bulk-copied to host-file." in stripped
        or stripped.startswith(b"Network packet size")
        or stripped.startswith(b"Clock Time")
    )


def load_metadata(container: str, query: str) -> dict[str, PhotoMeta]:
    """Read the small metadata pass used to assign unique archive filenames."""

    process = start_bcp(container, query)
    metadata: dict[str, PhotoMeta] = {}
    unexpected: list[bytes] = []
    assert process.stdout is not None
    for raw_line in process.stdout:
        line = raw_line.rstrip(b"\r\n")
        fields = line.split(b"\t")
        if len(fields) != 4:
            if not is_bcp_status_line(line):
                unexpected.append(line[:500])
            continue
        client_id, raw_phone, source, extension = (field.decode("utf-8", errors="strict") for field in fields)
        if client_id in metadata:
            process.kill()
            raise RuntimeError(f"Client {client_id} was selected more than once")
        metadata[client_id] = PhotoMeta(
            client_id=client_id,
            raw_phone=raw_phone,
            source=source,
            metadata_extension=extension,
            normalized_phones=normalize_phones(raw_phone),
        )
    finish_bcp(process, unexpected)
    return metadata


def assign_names(metadata: dict[str, PhotoMeta]) -> dict[str, NameAssignment]:
    """Maximize unique exact-phone filenames before applying exception suffixes."""

    # Phone conflicts form small components in this dataset.  A standard
    # augmenting-path matching lets a multi-phone client move to an alternate
    # number so a single-phone client can still keep an exact filename.
    sys.setrecursionlimit(max(50_000, len(metadata) * 3))
    phone_owner: dict[str, str] = {}

    def augment(client_id: str, visited_phones: set[str]) -> bool:
        for phone in metadata[client_id].normalized_phones:
            if phone in visited_phones:
                continue
            visited_phones.add(phone)
            previous = phone_owner.get(phone)
            if previous is None or augment(previous, visited_phones):
                phone_owner[phone] = client_id
                return True
        return False

    ordered_clients = sorted(
        metadata,
        key=lambda client_id: (
            len(metadata[client_id].normalized_phones) or 10**9,
            int(client_id) if client_id.isdigit() else 10**18,
            client_id,
        ),
    )
    for client_id in ordered_clients:
        if metadata[client_id].normalized_phones:
            augment(client_id, set())

    matched_phone_by_client = {client_id: phone for phone, client_id in phone_owner.items()}
    assignments: dict[str, NameAssignment] = {}
    for client_id, item in metadata.items():
        assigned_phone = matched_phone_by_client.get(client_id, "")
        if assigned_phone:
            status = (
                "exact_primary_phone"
                if assigned_phone == item.normalized_phones[0]
                else "exact_alternate_phone"
            )
            basename = assigned_phone
        elif item.normalized_phones:
            assigned_phone = item.normalized_phones[0]
            status = "duplicate_phone_client_id_suffix"
            basename = f"{assigned_phone}__{client_id}"
        else:
            raw_digits = re.sub(r"\D+", "", item.raw_phone or "")
            if raw_digits:
                status = "invalid_phone_client_id_fallback"
                basename = f"INVALID_PHONE_{raw_digits[:40]}__{client_id}"
            else:
                status = "missing_phone_client_id_fallback"
                basename = f"NO_PHONE__{client_id}"
        assignments[client_id] = NameAssignment(
            basename=basename,
            assigned_phone=assigned_phone,
            status=status,
        )

    basenames = [item.basename for item in assignments.values()]
    if len(basenames) != len(set(basenames)):
        raise RuntimeError("Phone filename assignment still contains collisions")
    return assignments


def decode_1c_photo(hex_value: bytes) -> tuple[bytes, str]:
    """Decode one ``_InfoRg6767._Fld6769`` 1C container."""

    try:
        wrapped = bytes.fromhex(hex_value.decode("ascii"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise ValueError("Photo BLOB is not valid hexadecimal BCP output") from exc
    if len(wrapped) < 19:
        raise ValueError(f"Photo BLOB is too short: {len(wrapped)} bytes")

    try:
        unpacked = zlib.decompress(wrapped[18:], -15)
    except zlib.error as exc:
        raise ValueError("Cannot inflate the 1C photo container") from exc
    if len(unpacked) < 20:
        raise ValueError(f"Inflated 1C photo container is too short: {len(unpacked)} bytes")

    metadata_length = struct.unpack("<Q", unpacked[:8])[0]
    payload_header = 8 + metadata_length
    if payload_header + 12 > len(unpacked):
        raise ValueError("1C metadata length points outside the inflated container")
    payload_length = struct.unpack("<Q", unpacked[payload_header + 4 : payload_header + 12])[0]
    payload = unpacked[payload_header + 12 : payload_header + 12 + payload_length]
    if len(payload) != payload_length:
        raise ValueError(f"Photo payload is truncated: expected {payload_length}, got {len(payload)}")

    for signature, extension in IMAGE_SIGNATURES:
        if payload.startswith(signature):
            return payload, extension
    raise ValueError(f"Unknown decoded image signature: {payload[:16].hex()}")


def zip_info(path: str, *, directory: bool = False) -> zipfile.ZipInfo:
    """Create deterministic ZIP metadata for files and explicit directories."""

    normalized = path.rstrip("/") + "/" if directory else path
    info = zipfile.ZipInfo(normalized, ZIP_TIMESTAMP)
    info.create_system = 3
    if directory:
        info.external_attr = (0o40755 << 16) | 0x10
        info.compress_type = zipfile.ZIP_STORED
    else:
        info.external_attr = 0o100644 << 16
        info.compress_type = zipfile.ZIP_DEFLATED
    return info


def write_csv_bytes(rows: Sequence[dict[str, object]], fieldnames: Sequence[str]) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=fieldnames, extrasaction="ignore", lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue().encode("utf-8-sig")


def write_archive(
    *,
    container: str,
    query: str,
    metadata: dict[str, PhotoMeta],
    assignments: dict[str, NameAssignment],
    output_path: Path,
    inner_dir: str,
    cutoff_at: str,
    expected_count: int,
    overwrite: bool,
) -> dict[str, object]:
    """Stream BCP photo rows directly into a temporary ZIP and atomically publish it."""

    if output_path.exists() and not overwrite:
        raise FileExistsError(f"Output already exists (use --overwrite intentionally): {output_path}")
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = output_path.with_name(output_path.name + ".partial")
    if temp_path.exists():
        temp_path.unlink()

    process = start_bcp(container, query)
    unexpected: list[bytes] = []
    manifest_rows: list[dict[str, object]] = []
    seen_clients: set[str] = set()
    seen_paths: set[str] = set()
    status_counts: Counter[str] = Counter()
    format_counts: Counter[str] = Counter()
    source_counts: Counter[str] = Counter()
    total_payload_bytes = 0

    try:
        with zipfile.ZipFile(
            temp_path,
            mode="w",
            compression=zipfile.ZIP_DEFLATED,
            compresslevel=6,
            allowZip64=True,
            strict_timestamps=True,
        ) as archive:
            for directory in (inner_dir, f"{inner_dir}/photos", f"{inner_dir}/_reports"):
                archive.writestr(zip_info(directory, directory=True), b"")

            assert process.stdout is not None
            for raw_line in process.stdout:
                line = raw_line.rstrip(b"\r\n")
                fields = line.split(b"\t", 4)
                if len(fields) != 5:
                    if not is_bcp_status_line(line):
                        unexpected.append(line[:500])
                    continue

                client_id = fields[0].decode("utf-8", errors="strict")
                raw_phone = fields[1].decode("utf-8", errors="strict")
                source = fields[2].decode("utf-8", errors="strict")
                metadata_extension = fields[3].decode("utf-8", errors="strict")
                blob_hex = fields[4]

                if client_id in seen_clients:
                    raise RuntimeError(f"Duplicate photo row for client {client_id}")
                item = metadata.get(client_id)
                assignment = assignments.get(client_id)
                if item is None or assignment is None:
                    raise RuntimeError(f"Photo row has no metadata/name assignment: {client_id}")
                if (raw_phone, source, metadata_extension) != (
                    item.raw_phone,
                    item.source,
                    item.metadata_extension,
                ):
                    raise RuntimeError(f"Metadata changed between BCP passes for client {client_id}")

                payload, detected_extension = decode_1c_photo(blob_hex)
                relative_path = f"{inner_dir}/photos/{assignment.basename}.{detected_extension}"
                if relative_path in seen_paths:
                    raise RuntimeError(f"Duplicate archive path: {relative_path}")

                archive.writestr(
                    zip_info(relative_path),
                    payload,
                    compress_type=zipfile.ZIP_DEFLATED,
                    compresslevel=6,
                )
                digest = hashlib.sha256(payload).hexdigest()
                manifest_rows.append(
                    {
                        "filename": relative_path.removeprefix(f"{inner_dir}/photos/"),
                        "client_id": client_id,
                        "assigned_phone": assignment.assigned_phone,
                        "raw_phone": report_text(raw_phone),
                        "naming_status": assignment.status,
                        "photo_source": source,
                        "metadata_extension": metadata_extension,
                        "detected_extension": detected_extension,
                        "bytes": len(payload),
                        "sha256": digest,
                    }
                )
                seen_clients.add(client_id)
                seen_paths.add(relative_path)
                status_counts[assignment.status] += 1
                format_counts[detected_extension] += 1
                source_counts[source] += 1
                total_payload_bytes += len(payload)

            finish_bcp(process, unexpected)
            if len(seen_clients) != expected_count:
                raise RuntimeError(f"Expected {expected_count} photos, wrote {len(seen_clients)}")
            if seen_clients != set(metadata):
                missing = sorted(set(metadata) - seen_clients)
                extra = sorted(seen_clients - set(metadata))
                raise RuntimeError(f"Photo/metadata client mismatch: missing={missing[:10]}, extra={extra[:10]}")

            manifest_rows.sort(key=lambda row: (int(str(row["client_id"])), str(row["filename"])))
            manifest_fields = [
                "filename",
                "client_id",
                "assigned_phone",
                "raw_phone",
                "naming_status",
                "photo_source",
                "metadata_extension",
                "detected_extension",
                "bytes",
                "sha256",
            ]
            exceptions = [row for row in manifest_rows if not str(row["naming_status"]).startswith("exact_")]
            archive.writestr(
                zip_info(f"{inner_dir}/_reports/manifest.csv"),
                write_csv_bytes(manifest_rows, manifest_fields),
                compress_type=zipfile.ZIP_DEFLATED,
                compresslevel=6,
            )
            archive.writestr(
                zip_info(f"{inner_dir}/_reports/phone_filename_exceptions.csv"),
                write_csv_bytes(exceptions, manifest_fields),
                compress_type=zipfile.ZIP_DEFLATED,
                compresslevel=6,
            )
            readme = f"""Тестовая выгрузка фотографий действующих клиентов

backup: data/Fitnes-30-06-26.bak
cutoff_at: {cutoff_at}
photos: {len(manifest_rows)}

Имена:
- обычный случай: <нормализованный телефон>.jpg
- общий телефон: <телефон>__<ID клиента>.jpg
- невалидный телефон: INVALID_PHONE_<цифры>__<ID клиента>.jpg
- телефон отсутствует: NO_PHONE__<ID клиента>.jpg

Подробное соответствие и SHA-256 каждого фото: _reports/manifest.csv
Исключения из правила точного телефонного имени:
_reports/phone_filename_exceptions.csv
"""
            archive.writestr(
                zip_info(f"{inner_dir}/README.txt"),
                readme.encode("utf-8"),
                compress_type=zipfile.ZIP_DEFLATED,
                compresslevel=6,
            )

        if output_path.exists() and overwrite:
            output_path.unlink()
        temp_path.replace(output_path)
    except Exception:
        if process.poll() is None:
            process.kill()
            process.wait()
        temp_path.unlink(missing_ok=True)
        raise

    return {
        "photos": len(seen_clients),
        "payload_bytes": total_payload_bytes,
        "format_counts": dict(sorted(format_counts.items())),
        "source_counts": dict(sorted(source_counts.items())),
        "naming_status_counts": dict(sorted(status_counts.items())),
        "phone_filename_exceptions": sum(
            count for status, count in status_counts.items() if not status.startswith("exact_")
        ),
    }


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_archive(path: Path, inner_dir: str, expected_count: int) -> dict[str, object]:
    """Read the completed ZIP back and validate every photo entry and CRC."""

    photo_prefix = f"{inner_dir}/photos/"
    with zipfile.ZipFile(path, "r") as archive:
        bad_crc = archive.testzip()
        if bad_crc is not None:
            raise RuntimeError(f"ZIP CRC validation failed at {bad_crc}")
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise RuntimeError("ZIP contains duplicate entry paths")
        photo_infos = [
            info
            for info in archive.infolist()
            if info.filename.startswith(photo_prefix)
            and not info.is_dir()
            and Path(info.filename).suffix.lower() in {".jpg", ".png", ".bmp", ".gif"}
        ]
        if len(photo_infos) != expected_count:
            raise RuntimeError(f"ZIP contains {len(photo_infos)} photos, expected {expected_count}")

        signature_counts: Counter[str] = Counter()
        for info in photo_infos:
            with archive.open(info, "r") as handle:
                head = handle.read(16)
            for signature, extension in IMAGE_SIGNATURES:
                if head.startswith(signature):
                    signature_counts[extension] += 1
                    break
            else:
                raise RuntimeError(f"Unknown image signature after ZIP readback: {info.filename}")

        manifest_name = f"{inner_dir}/_reports/manifest.csv"
        with archive.open(manifest_name, "r") as handle:
            text = io.TextIOWrapper(handle, encoding="utf-8-sig", newline="")
            manifest_count = sum(1 for _ in csv.DictReader(text))
        if manifest_count != expected_count:
            raise RuntimeError(f"Manifest contains {manifest_count} rows, expected {expected_count}")

        total_uncompressed = sum(info.file_size for info in photo_infos)
        total_compressed = sum(info.compress_size for info in photo_infos)

    return {
        "zip_bytes": path.stat().st_size,
        "zip_sha256": sha256_file(path),
        "photo_entries": len(photo_infos),
        "manifest_rows": manifest_count,
        "photo_uncompressed_bytes": total_uncompressed,
        "photo_compressed_bytes": total_compressed,
        "signature_counts": dict(sorted(signature_counts.items())),
        "crc_check": "PASS",
        "unique_paths_check": "PASS",
    }


def run_preflight(database: str, container: str, cutoff_at: str) -> None:
    """Enforce the repository's single-cutoff contract before exporting PII."""

    cutoff = datetime.strptime(cutoff_at, "%Y-%m-%d %H:%M:%S")
    cutoff_date = cutoff.strftime("%Y%m%d")
    db = require_safe_identifier(database, "database name")
    if not BACKUP_HEADER_LOG.is_file():
        raise FileNotFoundError(f"Backup header log is missing: {BACKUP_HEADER_LOG}")
    header_text = BACKUP_HEADER_LOG.read_text(encoding="utf-8", errors="replace")
    if cutoff_at not in header_text:
        raise RuntimeError(f"BackupFinishDate {cutoff_at} is not present in {BACKUP_HEADER_LOG}")

    sql = " ".join(
        f"""
        SET NOCOUNT ON;
        USE [{db}];
        DECLARE @cutoff_at datetime2(0) = CONVERT(datetime2(0), '{cutoff_at}', 120);
        DECLARE @cutoff_date date = CONVERT(date, '{cutoff_date}', 112);
        IF DB_NAME() <> N'{db}' THROW 51000, 'Unexpected database', 1;
        IF EXISTS (
            SELECT 1 FROM fitbase_part2.final_funnel_clients
            WHERE cutoff_date <> @cutoff_date OR cutoff_date IS NULL
        ) THROW 51001, 'final_funnel_clients cutoff mismatch', 1;
        IF EXISTS (
            SELECT 1 FROM fitbase_part2.membership_import_facts
            WHERE cutoff_at <> @cutoff_at OR cutoff_at IS NULL
        ) THROW 51002, 'membership cutoff mismatch', 1;
        IF EXISTS (
            SELECT 1 FROM fitbase_part2.services_import_facts
            WHERE cutoff_at <> @cutoff_at OR cutoff_at IS NULL
        ) THROW 51003, 'services cutoff mismatch', 1;
        IF NOT EXISTS (
            SELECT 1 FROM fitbase_part2.final_funnel_clients
            WHERE funnel = N'Действующие клиенты' AND cutoff_date = @cutoff_date
        ) THROW 51004, 'No active-client rows at requested cutoff', 1;
        SELECT 'cutoff_contract' AS check_name, 'PASS' AS result;
        """.split()
    )
    env = os.environ.copy()
    env["SQLCMD_SERVER"] = f"{container},1433"
    subprocess.run(
        [
            str(ROOT / "scripts" / "macos_backup_sqlcmd.sh"),
            "-d",
            db,
            "-b",
            "-Q",
            sql,
        ],
        cwd=ROOT,
        env=env,
        check=True,
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--container", default=DEFAULT_CONTAINER)
    parser.add_argument("--database", default=DEFAULT_DATABASE)
    parser.add_argument("--cutoff-at", default=DEFAULT_CUTOFF_AT)
    parser.add_argument("--expected-photo-count", type=int, default=DEFAULT_EXPECTED_COUNT)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--inner-dir", default=DEFAULT_INNER_DIR)
    parser.add_argument("--overwrite", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_.-]+", args.inner_dir):
        raise ValueError(f"Unsafe ZIP inner directory: {args.inner_dir!r}")
    cutoff = datetime.strptime(args.cutoff_at, "%Y-%m-%d %H:%M:%S")
    cutoff_date = cutoff.strftime("%Y%m%d")
    output_path = args.output if args.output.is_absolute() else ROOT / args.output

    run_preflight(args.database, args.container, args.cutoff_at)
    metadata_query = sql_selected_union(args.database, include_blob=False, cutoff_date=cutoff_date)
    photo_query = sql_selected_union(args.database, include_blob=True, cutoff_date=cutoff_date)
    metadata = load_metadata(args.container, metadata_query)
    if len(metadata) != args.expected_photo_count:
        raise RuntimeError(
            f"Expected {args.expected_photo_count} selected photo rows, found {len(metadata)}"
        )
    assignments = assign_names(metadata)

    build_summary = write_archive(
        container=args.container,
        query=photo_query,
        metadata=metadata,
        assignments=assignments,
        output_path=output_path,
        inner_dir=args.inner_dir,
        cutoff_at=args.cutoff_at,
        expected_count=args.expected_photo_count,
        overwrite=args.overwrite,
    )
    validation = validate_archive(output_path, args.inner_dir, args.expected_photo_count)
    result = {
        "status": "PASS",
        "output": str(output_path),
        "inner_directory": args.inner_dir,
        "cutoff_at": args.cutoff_at,
        "build": build_summary,
        "validation": validation,
    }
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
