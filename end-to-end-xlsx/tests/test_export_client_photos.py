from __future__ import annotations

import csv
import importlib.util
import io
import struct
import sys
import tempfile
import unittest
import zipfile
import zlib
from pathlib import Path
from unittest.mock import patch

from openpyxl import Workbook
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "final_client_photo_exporter", ROOT / "scripts" / "41_export_active_client_photos_zip.py"
)
assert SPEC is not None and SPEC.loader is not None
photos = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = photos
SPEC.loader.exec_module(photos)


def image_payload(format_name: str = "JPEG") -> bytes:
    buffer = io.BytesIO()
    mode = "RGBA" if format_name == "PNG" else "RGB"
    color = (20, 40, 80, 0) if mode == "RGBA" else (20, 40, 80)
    Image.new(mode, (8, 6), color).save(buffer, format=format_name)
    return buffer.getvalue()


def wrapped_photo(payload: bytes) -> bytes:
    unpacked = struct.pack("<Q", 0) + bytes(4) + struct.pack("<Q", len(payload)) + payload
    compressor = zlib.compressobj(wbits=-15)
    wrapped = bytes(18) + compressor.compress(unpacked) + compressor.flush()
    return wrapped.hex().encode("ascii")


def meta(client_id: str, phone: str, extension: str = "jpg"):
    return photos.PhotoMeta(client_id, phone, "Reference65_main", extension, photos.normalize_phones(phone))


def client(client_id: str, phone: str, funnel: str = "Действующие абонементы"):
    return photos.DeliveredClient(client_id, phone, funnel, photos.normalize_phones(phone))


class FakeBcp:
    def __init__(self, rows: bytes):
        self.stdout = io.BytesIO(rows)
        self.stderr = io.BytesIO()
        self.returncode = 0

    def wait(self):
        return self.returncode

    def poll(self):
        return self.returncode

    def kill(self):
        self.returncode = -9


def bcp_row(item, payload: bytes) -> bytes:
    fields = [item.client_id, item.raw_phone, item.source, item.metadata_extension]
    return "\t".join(fields).encode("utf-8") + b"\t" + wrapped_photo(payload) + b"\n"


class PhotoScopeTests(unittest.TestCase):
    def test_uses_delivered_ids_and_phones_and_excludes_missing_invalid_or_unrequested(self):
        source = {
            "001": meta("001", "wrong SQL phone"),
            "002": meta("002", "89991112233"),
            "003": meta("003", ""),
            "004": meta("004", "123"),
            "006": meta("006", "89996667788"),
            "007": meta("007", "89990000001"),
        }
        delivered = {
            "001": client("001", "89991112233"),
            "002": client("002", "89992223344", "Реактивация"),
            "003": client("003", ""),
            "004": client("004", "123"),
            "005": client("005", "89995556677"),
            "006": client("006", "89996667788", "новые заявки"),
        }
        selected, excluded = photos.select_eligible_photos(source, delivered)
        self.assertEqual(set(selected), {"001", "002"})
        self.assertEqual(selected["001"].normalized_phones, ("79991112233",))
        self.assertEqual(selected["002"].normalized_phones, ("79992223344",))
        self.assertEqual(selected["001"].raw_phone, "wrong SQL phone")
        self.assertEqual({row["client_id"]: row["reason"] for row in excluded}, {
            "003": "missing_phone", "004": "invalid_phone", "005": "missing_or_unsupported_photo",
            "006": "outside_requested_funnels", "007": "not_in_delivered_workbook",
        })
        self.assertEqual(len(delivered), 6, "Photo exclusions must not mutate the workbook client set")

    def test_shared_valid_phones_preserve_all_images_without_collisions(self):
        source = {
            "003": meta("003", "89991112233"),
            "001": meta("001", "89991112233, 89992223344"),
            "002": meta("002", "89991112233"),
        }
        names = photos.assign_names(source)
        self.assertEqual(len({item.basename for item in names.values()}), 3)
        self.assertEqual(sum("__" in item.basename for item in names.values()), 1)
        self.assertEqual(names, photos.assign_names(dict(reversed(list(source.items())))))
        self.assertTrue(all(item.assigned_phone in source[key].normalized_phones for key, item in names.items()))

    def test_invalid_phone_cannot_get_fallback_filename(self):
        with self.assertRaisesRegex(ValueError, "Only valid-phone"):
            photos.assign_names({"001": meta("001", "123")})

    def test_workbook_reads_final_scope_and_leading_zero_ids(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "clients.xlsx"
            workbook = Workbook()
            sheet = workbook.active
            sheet.append(["client_id", "phone", "funnel"])
            sheet.append(["Внутренний номер клиента ", "Телефон *", "Воронка *"])
            sheet.append(["000001", "89991112233", "Реактивация"])
            workbook.save(path)
            loaded = photos.load_delivered_clients(path)
            self.assertEqual(set(loaded), {"000001"})
            self.assertEqual(loaded["000001"].funnel, "Реактивация")
            sheet.append(["000001", "89991112233", "Реактивация"])
            workbook.save(path)
            with self.assertRaisesRegex(ValueError, "more than once"):
                photos.load_delivered_clients(path)
            workbook.close()

    def test_sql_does_not_limit_original_funnel_before_workbook_reclassification(self):
        query = photos.sql_selected_union("TestDatabase", include_blob=True, cutoff_date="20260921")
        self.assertNotIn("a.funnel =", query)
        self.assertIn("20260921", query)
        self.assertIn("_Fld6769", query)
        self.assertEqual(query.count("DATALENGTH(i._Fld6769) > 0"), 2)

    def test_metadata_parse_failure_reaps_child_and_closes_pipes(self):
        process = FakeBcp(b"001\t\xff\tReference65_main\tjpg\n")
        with patch.object(photos, "start_bcp", return_value=process), patch.object(
            process, "wait", wraps=process.wait
        ) as wait:
            with self.assertRaises(UnicodeDecodeError):
                photos.load_metadata("sql-test", "unused fake query")
        wait.assert_called_once()
        self.assertTrue(process.stdout.closed)
        self.assertTrue(process.stderr.closed)


class JpegArchiveTests(unittest.TestCase):
    def test_container_decoding_and_transparent_png_conversion(self):
        original = image_payload("PNG")
        decoded, extension = photos.decode_1c_photo(wrapped_photo(original))
        self.assertEqual((decoded, extension), (original, "png"))
        with Image.open(io.BytesIO(photos.jpeg_payload(decoded, extension))) as converted:
            self.assertEqual((converted.format, converted.mode, converted.size), ("JPEG", "RGB", (8, 6)))
            self.assertEqual(converted.getpixel((0, 0)), (255, 255, 255))
        jpeg = image_payload()
        self.assertEqual(photos.jpeg_payload(jpeg, "jpg"), jpeg)

    def build(self, path: Path, *, bad_payload: bytes | None = None):
        source = {"001": meta("001", "89991112233"), "002": meta("002", "89991112233", "png")}
        delivered = {"001": client("001", "89991112233"), "002": client("002", "89991112233", "Реактивация")}
        excluded = [{"client_id": "003", "funnel": "Реактивация", "exported_phone": "", "reason": "missing_phone"}]
        stream = bcp_row(source["001"], bad_payload or image_payload()) + bcp_row(source["002"], image_payload("PNG"))
        # An excluded photo is intentionally undecodable. Exclusion happens before decoding.
        stream += bcp_row(meta("003", ""), b"not an image")
        with patch.object(photos, "start_bcp", return_value=FakeBcp(stream)):
            return photos.write_archive(
                container="sql-test", query="unused fake query", metadata=source,
                assignments=photos.assign_names(source), clients=delivered, exclusions=excluded,
                output_path=path, inner_dir="photos_20260921", cutoff_at="2026-09-21 21:03:05",
                backup_finish_at="2026-09-20 21:03:05", expected_count=2, overwrite=True,
            )

    def test_archive_reads_back_jpg_hashes_exclusions_and_independent_timestamps(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "photos.zip"
            result = self.build(path)
            self.assertEqual(result["photos"], 2)
            self.assertEqual(result["source_format_counts"], {"jpg": 1, "png": 1})
            self.assertEqual(result["phone_filename_exceptions"], 1)
            self.assertEqual(result["validation"]["decoded_images_check"], "PASS")
            with zipfile.ZipFile(path) as archive:
                images = [info for info in archive.infolist() if "/photos/" in info.filename and not info.is_dir()]
                self.assertEqual(len(images), 2)
                self.assertTrue(all(info.filename.endswith(".jpg") for info in images))
                self.assertTrue(all(info.date_time == (2026, 9, 21, 21, 3, 4) for info in images))
                for info in images:
                    with Image.open(io.BytesIO(archive.read(info))) as decoded:
                        self.assertEqual(decoded.format, "JPEG")
                readme = archive.read("photos_20260921/README.txt").decode("utf-8")
                self.assertIn("2026-09-20 21:03:05", readme)
                self.assertIn("2026-09-21 21:03:05", readme)
                excluded = archive.read("photos_20260921/_reports/excluded_clients.csv").decode("utf-8-sig")
                self.assertIn("missing_phone", excluded)
            self.assertFalse(path.with_name("photos.zip.partial").exists())

    def test_corrupt_photo_does_not_replace_previous_delivery(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "photos.zip"
            path.write_bytes(b"previous accepted archive")
            with self.assertRaises(ValueError):
                self.build(path, bad_payload=bytes.fromhex("FFD8FF") + b"corrupt JPEG")
            self.assertEqual(path.read_bytes(), b"previous accepted archive")
            self.assertFalse(path.with_name("photos.zip.partial").exists())

    def test_archive_validation_rejects_manifest_hash_mismatch(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "photos.zip"
            self.build(path)
            altered = Path(directory) / "tampered.zip"
            with zipfile.ZipFile(path) as source, zipfile.ZipFile(altered, "w") as target:
                for info in source.infolist():
                    payload = source.read(info)
                    if info.filename.endswith("manifest.csv"):
                        rows = list(csv.DictReader(io.StringIO(payload.decode("utf-8-sig"))))
                        rows[0]["sha256"] = "0" * 64
                        payload = photos.write_csv_bytes(rows, list(rows[0]))
                    target.writestr(info, payload)
            with self.assertRaisesRegex(RuntimeError, "SHA-256"):
                photos.validate_archive(altered, "photos_20260921", 2)


if __name__ == "__main__":
    unittest.main()
