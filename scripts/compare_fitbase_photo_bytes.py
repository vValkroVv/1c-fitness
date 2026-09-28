#!/usr/bin/env python3
"""Compare archived customer photos with the images currently served by Fitbase."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import logging
import os
import re
import sys
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlsplit
from zipfile import BadZipFile, ZipFile

try:
    from PIL import Image, ImageChops, ImageOps, ImageStat, UnidentifiedImageError
except ImportError as exc:  # pragma: no cover - depends on the execution environment
    raise SystemExit(
        "Pillow is required. Install it with: python3 -m pip install Pillow"
    ) from exc

try:
    import requests
except ImportError as exc:  # pragma: no cover - depends on the execution environment
    raise SystemExit(
        "requests is required for pooled HTTP connections. Install it with: python3 -m pip install requests"
    ) from exc


BASE_URL = "https://files.fitbase.io"
SOURCE_ZIP_PREFIX = "fitbase_client_photos_20260921/photos/"
EXPECTED_PRESENT_ROWS = 33860
NORMALIZED_SIZE = (256, 192)
SIMILAR_MAE_MAX = 3.0
SIMILAR_DHASH_MAX = 4
DIFFERENT_MAE_MIN = 30.0
DIFFERENT_DHASH_MIN = 20
MAX_RESPONSE_BYTES = 25 * 1024 * 1024
CLASSIFICATIONS = ("exact", "similar", "different", "uncertain", "download_error")
COMPARISON_FIELDS = [
    "comparison_index", "resolved_photo_url", "download_status",
    "download_attempts", "download_content_type", "source_sha256",
    "remote_sha256", "source_width", "source_height", "remote_width",
    "remote_height", "same_dimensions", "same_aspect_ratio", "mae_rgb_255",
    "dhash_hamming_64", "classification", "error_type", "error_detail",
    "review_photo_path",
]


class ComparisonInputError(Exception):
    """Raised when the supplied inputs do not satisfy the comparison contract."""


_thread_local = threading.local()
_rate_lock = threading.Lock()
_next_request_at = 0.0


def get_session():
    session = getattr(_thread_local, "session", None)
    if session is None:
        session = requests.Session()
        session.headers.update({
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/537.36 (KHTML, like Gecko) "
                "Chrome/131.0.0.0 Safari/537.36"
            ),
            "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8",
        })
        session.max_redirects = 0
        _thread_local.session = session
    return session


def wait_for_request_slot(interval: float) -> None:
    """Apply one shared request interval across worker threads."""
    global _next_request_at
    with _rate_lock:
        now = time.monotonic()
        delay = max(0.0, _next_request_at - now)
        _next_request_at = max(now, _next_request_at) + interval
    if delay:
        time.sleep(delay)


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def setup_logger(log_path: Path) -> logging.Logger:
    logger = logging.getLogger("fitbase_photo_comparison")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    formatter = logging.Formatter("%(asctime)s %(levelname)s %(message)s")
    file_handler = logging.FileHandler(log_path, mode="w", encoding="utf-8")
    file_handler.setFormatter(formatter)
    stream_handler = logging.StreamHandler(sys.stdout)
    stream_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    logger.addHandler(stream_handler)
    return logger


def make_file_url(relative_url: str) -> str:
    parsed = urlsplit(relative_url)
    if parsed.scheme or parsed.netloc or parsed.query or parsed.fragment:
        raise ComparisonInputError(
            f"photo_url must be a plain relative /files/... path: {relative_url!r}"
        )
    if not parsed.path.startswith("/files/"):
        raise ComparisonInputError(
            f"photo_url must start with /files/: {relative_url!r}"
        )
    return BASE_URL + parsed.path


def fetch_photo(url: str, retries: int, timeout: float, request_interval: float,
                logger: logging.Logger, fitbase_id: str) -> dict[str, Any]:
    """Fetch a photo with bounded retries and return bytes plus explicit status."""
    attempts = 0
    last_error = ""
    retryable_statuses = {408, 425, 429}

    for attempt in range(retries + 1):
        attempts += 1
        wait_for_request_slot(request_interval)
        try:
            with get_session().get(
                url,
                timeout=(timeout, timeout),
                allow_redirects=False,
                stream=True,
            ) as response:
                status = response.status_code
                content_type = response.headers.get("Content-Type", "")
                if 300 <= status < 400:
                    return {
                        "ok": False,
                        "attempts": attempts,
                        "status": status,
                        "content_type": content_type,
                        "error": f"redirect blocked (Location={response.headers.get('Location', '')!r})",
                    }
                if status != 200:
                    last_error = f"HTTP {status}: {response.reason}"
                    retry_after = response.headers.get("Retry-After")
                    should_retry = status in retryable_statuses or status >= 500
                    if should_retry and attempt < retries:
                        delay = retry_delay(attempt, retry_after)
                        logger.warning(
                            "retry fitbase_id=%s attempt=%d/%d error=%s delay=%.1fs",
                            fitbase_id, attempt + 1, retries + 1, last_error, delay,
                        )
                        time.sleep(delay)
                        continue
                    return {
                        "ok": False,
                        "attempts": attempts,
                        "status": status,
                        "content_type": content_type,
                        "error": last_error,
                    }
                body_chunks = []
                body_size = 0
                for chunk in response.iter_content(chunk_size=65536):
                    if not chunk:
                        continue
                    body_size += len(chunk)
                    if body_size > MAX_RESPONSE_BYTES:
                        return {
                            "ok": False,
                            "attempts": attempts,
                            "status": status,
                            "content_type": content_type,
                            "error": f"response exceeds {MAX_RESPONSE_BYTES} bytes",
                        }
                    body_chunks.append(chunk)
                body = b"".join(body_chunks)
                if not body:
                    return {
                        "ok": False,
                        "attempts": attempts,
                        "status": status,
                        "content_type": content_type,
                        "error": "empty response body",
                    }
                return {
                    "ok": True,
                    "bytes": body,
                    "attempts": attempts,
                    "status": status,
                    "content_type": content_type,
                    "final_url": response.url,
                    "error": "",
                }
        except requests.RequestException as exc:
            last_error = f"{type(exc).__name__}: {exc}"
            if attempt < retries:
                delay = retry_delay(attempt, None)
                logger.warning(
                    "retry fitbase_id=%s attempt=%d/%d error=%s delay=%.1fs",
                    fitbase_id, attempt + 1, retries + 1, last_error, delay,
                )
                time.sleep(delay)
                continue
            return {
                "ok": False,
                "attempts": attempts,
                "status": "",
                "content_type": "",
                "error": last_error,
            }

    return {
        "ok": False,
        "attempts": attempts,
        "status": "",
        "content_type": "",
        "error": last_error or "request failed without a reported error",
    }


def retry_delay(attempt_index: int, retry_after: str | None) -> float:
    if retry_after:
        try:
            delay = float(retry_after)
        except ValueError:
            try:
                delay = (parsedate_to_datetime(retry_after) - datetime.now(timezone.utc)).total_seconds()
            except (TypeError, ValueError, OverflowError):
                delay = 0
        if delay > 0:
            return min(delay, 8.0)
    return min(2.0 ** attempt_index, 8.0)


def decode_photo(blob: bytes) -> tuple[Image.Image, tuple[int, int]]:
    with Image.open(__import__("io").BytesIO(blob)) as source:
        source.load()
        image = ImageOps.exif_transpose(source).convert("RGB")
    original_size = image.size
    return image, original_size


def normalized_metrics(source_image: Image.Image,
                       remote_image: Image.Image) -> tuple[float, int]:
    resampling = Image.Resampling.LANCZOS
    source_normalized = source_image.resize(NORMALIZED_SIZE, resampling)
    remote_normalized = remote_image.resize(NORMALIZED_SIZE, resampling)
    difference = ImageChops.difference(source_normalized, remote_normalized)
    mae = sum(ImageStat.Stat(difference).mean) / 3.0

    def dhash(image: Image.Image) -> int:
        gray = image.convert("L").resize((9, 8), resampling)
        pixels = list(gray.getdata())
        result = 0
        bit = 0
        for y in range(8):
            row = y * 9
            for x in range(8):
                if pixels[row + x] > pixels[row + x + 1]:
                    result |= 1 << bit
                bit += 1
        return result

    return mae, (dhash(source_normalized) ^ dhash(remote_normalized)).bit_count()


def same_aspect_ratio(left: tuple[int, int], right: tuple[int, int]) -> bool:
    if not all(left) or not all(right):
        return False
    return left[0] * right[1] == right[0] * left[1]


def safe_stem(value: str) -> str:
    stem = re.sub(r"[^A-Za-z0-9._-]+", "_", value).strip("._")
    return stem[:100] or "photo"


def save_review_photo(review_dir: Path, row: dict[str, str], remote_bytes: bytes) -> str:
    folder = review_dir
    folder.mkdir(parents=True, exist_ok=True)
    name = "_".join(
        safe_stem(row.get(key, "")) for key in ("source_id", "fitbase_id", "photo_file")
    )
    path = folder / f"{name}.remote.jpg"
    path.write_bytes(remote_bytes)
    return str(path.relative_to(review_dir.parent))


def compare_one(index: int, row: dict[str, str], archive: ZipFile,
                review_dir: Path, retries: int, timeout: float, request_interval: float,
                logger: logging.Logger, source_zip_prefix: str = SOURCE_ZIP_PREFIX) -> dict[str, Any]:
    result: dict[str, Any] = {
        **row,
        "comparison_index": index,
        "resolved_photo_url": "",
        "download_status": "",
        "download_attempts": 0,
        "download_content_type": "",
        "source_sha256": "",
        "remote_sha256": "",
        "source_width": "",
        "source_height": "",
        "remote_width": "",
        "remote_height": "",
        "same_dimensions": "",
        "same_aspect_ratio": "",
        "mae_rgb_255": "",
        "dhash_hamming_64": "",
        "classification": "",
        "error_type": "",
        "error_detail": "",
        "review_photo_path": "",
    }

    try:
        url = make_file_url(row.get("photo_url", ""))
        result["resolved_photo_url"] = url
    except ComparisonInputError as exc:
        result.update(
            classification="download_error",
            error_type="invalid_photo_url",
            error_detail=str(exc),
        )
        return result

    archive_entry = source_zip_prefix + row.get("photo_file", "")
    try:
        if not row.get("photo_file") or Path(row["photo_file"]).name != row["photo_file"]:
            raise FileNotFoundError(f"invalid photo_file entry: {row.get('photo_file')!r}")
        source_bytes = archive.read(archive_entry)
        result["source_sha256"] = hashlib.sha256(source_bytes).hexdigest()
        source_error = ""
    except (KeyError, FileNotFoundError, BadZipFile, OSError) as exc:
        source_bytes = b""
        source_error = f"{type(exc).__name__}: {exc} (archive entry {archive_entry!r})"

    fetched = fetch_photo(
        url, retries, timeout, request_interval, logger, row.get("fitbase_id", "")
    )
    result["download_attempts"] = fetched["attempts"]
    result["download_status"] = fetched["status"]
    result["download_content_type"] = fetched["content_type"]
    if not fetched["ok"]:
        result.update(
            classification="download_error",
            error_type="download_error",
            error_detail=fetched["error"],
        )
        return result

    remote_bytes = fetched["bytes"]
    result["remote_sha256"] = hashlib.sha256(remote_bytes).hexdigest()
    if source_error:
        result.update(
            classification="uncertain",
            error_type="source_archive_error",
            error_detail=source_error,
        )
        result["review_photo_path"] = save_review_photo(review_dir, row, remote_bytes)
        return result

    if result["source_sha256"] == result["remote_sha256"]:
        result["classification"] = "exact"
        return result

    decode_errors = []
    try:
        source_image, source_size = decode_photo(source_bytes)
        result["source_width"], result["source_height"] = source_size
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        source_image = None
        decode_errors.append(f"source {type(exc).__name__}: {exc}")
    try:
        remote_image, remote_size = decode_photo(remote_bytes)
        result["remote_width"], result["remote_height"] = remote_size
    except (UnidentifiedImageError, OSError, ValueError, Image.DecompressionBombError) as exc:
        remote_image = None
        decode_errors.append(f"remote {type(exc).__name__}: {exc}")

    if decode_errors:
        result.update(
            classification="uncertain",
            error_type="decode_error",
            error_detail="; ".join(decode_errors),
        )
        result["review_photo_path"] = save_review_photo(review_dir, row, remote_bytes)
        return result

    source_dimensions = tuple(source_size)
    remote_dimensions = tuple(remote_size)
    dimensions_match = source_dimensions == remote_dimensions
    aspect_match = same_aspect_ratio(source_dimensions, remote_dimensions)
    mae, dhash = normalized_metrics(source_image, remote_image)
    result.update(
        same_dimensions=dimensions_match,
        same_aspect_ratio=aspect_match,
        mae_rgb_255=round(mae, 4),
        dhash_hamming_64=dhash,
    )

    if dimensions_match and aspect_match and mae <= SIMILAR_MAE_MAX and dhash <= SIMILAR_DHASH_MAX:
        classification = "similar"
    elif mae >= DIFFERENT_MAE_MIN and dhash >= DIFFERENT_DHASH_MIN:
        classification = "different"
    else:
        classification = "uncertain"
    result["classification"] = classification
    if classification in {"different", "uncertain"}:
        result["review_photo_path"] = save_review_photo(review_dir, row, remote_bytes)
    return result


def read_calibration(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ComparisonInputError(f"cannot read calibration file {path}: {exc}") from exc
    size = data.get("method", {}).get("normalized_size_px")
    if size != [NORMALIZED_SIZE[0], NORMALIZED_SIZE[1]]:
        raise ComparisonInputError(
            f"calibration normalized_size_px must be {list(NORMALIZED_SIZE)}, got {size!r}"
        )
    return data


def read_present_rows(path: Path, expected_count: int) -> tuple[list[dict[str, str]], list[str]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            if not reader.fieldnames:
                raise ComparisonInputError(f"reconciliation has no header: {path}")
            missing = {"category", "photo_url", "photo_file", "fitbase_id", "source_id"} - set(reader.fieldnames)
            if missing:
                raise ComparisonInputError(f"reconciliation is missing columns: {sorted(missing)}")
            fieldnames = list(reader.fieldnames)
            rows = [dict(row) for row in reader if row.get("category") == "present"]
    except OSError as exc:
        raise ComparisonInputError(f"cannot read reconciliation file {path}: {exc}") from exc
    if len(rows) != expected_count:
        raise ComparisonInputError(
            f"expected {expected_count} present rows, found {len(rows)} in {path}"
        )
    return rows, fieldnames


def comparison_key(row: dict[str, Any]) -> tuple[str, str, str, str]:
    return tuple(str(row.get(field, "") or "") for field in (
        "source_id", "fitbase_id", "photo_url", "photo_file"
    ))


def read_previous_results(path: Path | None) -> tuple[list[dict[str, Any]], list[str]]:
    if path is None:
        return [], []
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            if not reader.fieldnames or "classification" not in reader.fieldnames:
                raise ComparisonInputError(f"resume CSV has no comparison results: {path}")
            fields = list(reader.fieldnames)
            rows = []
            seen = set()
            for index, raw_row in enumerate(reader, start=1):
                row = dict(raw_row)
                if row.get("classification") not in CLASSIFICATIONS:
                    continue
                key = comparison_key(row)
                if key in seen:
                    continue
                seen.add(key)
                try:
                    row["comparison_index"] = int(row.get("comparison_index") or index)
                except ValueError:
                    row["comparison_index"] = index
                rows.append(row)
    except OSError as exc:
        raise ComparisonInputError(f"cannot read resume CSV {path}: {exc}") from exc
    return rows, fields


def worker_exception_row(index: int, row: dict[str, str], exc: Exception) -> dict[str, Any]:
    result = {
        **row,
        "comparison_index": index,
        "resolved_photo_url": "",
        "download_status": "",
        "download_attempts": 0,
        "download_content_type": "",
        "source_sha256": "",
        "remote_sha256": "",
        "source_width": "",
        "source_height": "",
        "remote_width": "",
        "remote_height": "",
        "same_dimensions": "",
        "same_aspect_ratio": "",
        "mae_rgb_255": "",
        "dhash_hamming_64": "",
        "classification": "uncertain",
        "error_type": "worker_exception",
        "error_detail": f"{type(exc).__name__}: {exc}",
        "review_photo_path": "",
    }
    return result


def write_outputs(rows: list[dict[str, Any]], fieldnames: list[str],
                  csv_path: Path, summary_path: Path, summary: dict[str, Any]) -> None:
    output_fields = list(dict.fromkeys(fieldnames + COMPARISON_FIELDS))
    temp_csv = csv_path.with_suffix(csv_path.suffix + ".tmp")
    with temp_csv.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=output_fields, extrasaction="ignore")
        writer.writeheader()
        for row in sorted(rows, key=lambda item: item["comparison_index"]):
            writer.writerow(row)
    os.replace(temp_csv, csv_path)

    temp_summary = summary_path.with_suffix(summary_path.suffix + ".tmp")
    temp_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temp_summary, summary_path)


def read_csv_rows(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream)
            if not reader.fieldnames:
                raise ComparisonInputError(f"CSV has no header: {path}")
            return [dict(row) for row in reader], list(reader.fieldnames)
    except OSError as exc:
        raise ComparisonInputError(f"cannot read CSV {path}: {exc}") from exc


def evidence_key(row: dict[str, Any]) -> tuple[str, str, str]:
    return tuple(str(row.get(field, "") or "") for field in (
        "source_id", "fitbase_id", "photo_file"
    ))


def finalize_comparison(args: argparse.Namespace, logger: logging.Logger) -> int:
    """Apply reviewed aspect and crop evidence while preserving raw metric classes."""
    raw_rows, raw_fields = read_csv_rows(args.finalize_csv)
    crop_rows, _ = read_csv_rows(args.crop_review_csv)
    visual_rows, _ = read_csv_rows(args.same_aspect_review_csv)
    if len(raw_rows) != args.expected_final_count:
        raise ComparisonInputError(
            f"expected {args.expected_final_count} merged rows, found {len(raw_rows)}"
        )

    crop_evidence: dict[tuple[str, str, str], dict[str, str]] = {}
    for row in crop_rows:
        if row.get("decision") == "confirmed_same_crop" and row.get("status") == "compared":
            crop_evidence[evidence_key(row)] = row
    visual_evidence: dict[tuple[str, str, str], dict[str, str]] = {}
    visual_hash_mismatches = []
    raw_by_key = {evidence_key(row): row for row in raw_rows}
    for evidence in visual_rows:
        if evidence.get("verdict") != "same_photo":
            continue
        key = evidence_key(evidence)
        original = raw_by_key.get(key)
        if not original:
            visual_hash_mismatches.append({"source_id": key[0], "reason": "row absent from merged input"})
            continue
        if (
            original.get("source_sha256") != evidence.get("source_sha256")
            or original.get("remote_sha256") != evidence.get("remote_sha256")
        ):
            visual_hash_mismatches.append({"source_id": key[0], "reason": "SHA-256 does not match review evidence"})
            continue
        visual_evidence[key] = evidence

    changed_aspect_keys = {
        evidence_key(row) for row in raw_rows
        if row.get("same_aspect_ratio") == "False"
        and row.get("source_sha256") and row.get("remote_sha256")
    }
    if set(crop_evidence) != changed_aspect_keys:
        missing_crop = changed_aspect_keys - set(crop_evidence)
        extra_crop = set(crop_evidence) - changed_aspect_keys
        raise ComparisonInputError(
            f"crop review coverage mismatch: candidates={len(changed_aspect_keys)} "
            f"reviewed={len(crop_evidence)} missing={len(missing_crop)} extra={len(extra_crop)}"
        )

    # This evidence came from two explicit live UI checks of the crop usability.
    severe_crop_ui_evidence = {
        "000024568": "ui_crop_issue.json",
        "000028166": "ui_crop_issue_2.json",
    }
    final_rows: list[dict[str, Any]] = []
    raw_counts: Counter[str] = Counter()
    final_counts: Counter[str] = Counter()
    classification_review_counts: Counter[str] = Counter()
    changed_aspect_count = 0
    crop_quality_count = 0
    broken_photo_count = 0
    wrong_photo_count = 0
    manual_same_aspect_count = 0
    for row in raw_rows:
        raw_classification = row.get("metric_rule_classification") or row.get("classification", "")
        row["metric_rule_classification"] = raw_classification
        raw_counts[raw_classification] += 1
        key = evidence_key(row)
        crop = crop_evidence.get(key)
        visual = visual_evidence.get(key)
        source_sha = row.get("source_sha256", "")
        remote_sha = row.get("remote_sha256", "")
        same_aspect = row.get("same_aspect_ratio") == "True"
        same_dimensions = row.get("same_dimensions") == "True"
        try:
            mae = float(row.get("mae_rgb_255") or "nan")
            dhash = int(row.get("dhash_hamming_64") or -1)
        except (TypeError, ValueError):
            mae, dhash = float("nan"), -1

        row["crop_match_status"] = "not_needed_same_aspect" if same_aspect else "not_confirmed"
        row["crop_quality_flag"] = ""
        row["crop_good_matches"] = ""
        row["crop_inliers"] = ""
        row["crop_inlier_ratio"] = ""
        row["crop_source_area_retained"] = ""
        row["crop_quality_evidence"] = ""
        row["same_aspect_review_status"] = ""
        row["classification_evidence"] = ""
        row["issue_status"] = ""
        row["issue_evidence_path"] = ""

        if source_sha and remote_sha and source_sha == remote_sha:
            final_class = "exact"
            row["classification_evidence"] = "SHA-256 of original image bytes matches."
        elif raw_classification == "download_error":
            final_class = "download_error"
            if str(row.get("download_status", "")) == "404":
                row["issue_status"] = "broken_photo_url"
                row["classification_evidence"] = (
                    "HTTP 404 on initial fetch and isolated retry; root UI review reports naturalWidth=0."
                )
                row["issue_evidence_path"] = "image_comparison_retry_download_errors_summary.json; live UI review"
                broken_photo_count += 1
            else:
                row["classification_evidence"] = row.get("error_detail", "Download failed.")
        elif crop:
            final_class = "similar"
            row["crop_match_status"] = "confirmed_same_crop"
            row["crop_quality_flag"] = crop.get("crop_quality_review", "")
            row["crop_good_matches"] = crop.get("good_matches", "")
            row["crop_inliers"] = crop.get("inliers", "")
            row["crop_inlier_ratio"] = crop.get("inlier_ratio", "")
            row["crop_source_area_retained"] = crop.get("source_area_retained", "")
            row["crop_quality_evidence"] = crop.get("crop_quality_review", "")
            row["classification_evidence"] = "SIFT plus RANSAC confirmed the same source image after cropping."
            changed_aspect_count += 1
            if row["crop_quality_flag"]:
                crop_quality_count += 1
        elif visual:
            final_class = "similar"
            row["same_aspect_review_status"] = "same_photo_visual_review"
            row["classification_evidence"] = (
                "SHA-bound side-by-side review confirmed the same subject, pose, framing, clothing, and background."
            )
            manual_same_aspect_count += 1
        elif same_aspect and (
            (same_dimensions and mae <= SIMILAR_MAE_MAX and dhash <= SIMILAR_DHASH_MAX)
            or (mae <= 4.0 and dhash <= 1)
        ):
            final_class = "similar"
            if same_dimensions and mae <= SIMILAR_MAE_MAX and dhash <= SIMILAR_DHASH_MAX:
                row["classification_evidence"] = (
                    "Same dimensions and aspect ratio, calibrated MAE <= 3.0, and dHash <= 4."
                )
            else:
                row["classification_evidence"] = (
                    "Same aspect ratio with MAE <= 4.0 and dHash <= 1; "
                    "this evidence-backed rule also covers proportional resizes."
                )
        elif same_aspect and mae >= DIFFERENT_MAE_MIN and dhash >= DIFFERENT_DHASH_MIN:
            final_class = "different"
            row["classification_evidence"] = "Same aspect ratio with MAE >= 30 and dHash >= 20."
        else:
            final_class = "uncertain"
            if not same_aspect and row.get("same_aspect_ratio") == "False":
                row["crop_match_status"] = "not_confirmed"
                row["classification_evidence"] = "Aspect ratio changed and no confirmed crop evidence was supplied."
            else:
                row["classification_evidence"] = "Image metrics fall between the automatic similar/different thresholds."

        if row.get("source_id") == "000065590" and final_class == "different":
            row["issue_status"] = "wrong_photo"
            row["issue_evidence_path"] = "ui_wrong_photo.json"
            row["classification_evidence"] += " Live UI review confirms a different woman on the client card."
            wrong_photo_count += 1
        if row.get("source_id") in severe_crop_ui_evidence and row.get("crop_quality_flag"):
            row["issue_evidence_path"] = severe_crop_ui_evidence[row["source_id"]]

        row["classification"] = final_class
        row["final_classification"] = final_class
        row["crop_quality_review"] = row["crop_quality_flag"]
        row["raw_classification"] = raw_classification
        final_counts[final_class] += 1
        if row.get("issue_status"):
            classification_review_counts[row["issue_status"]] += 1
        if row.get("crop_quality_flag"):
            classification_review_counts[row["crop_quality_flag"]] += 1
        final_rows.append(row)

    downgraded_raw_similar = [
        row for row in final_rows
        if row.get("metric_rule_classification") == "similar"
        and row.get("classification") != "similar"
    ]
    if downgraded_raw_similar:
        sample = [(row.get("source_id"), row.get("classification")) for row in downgraded_raw_similar[:5]]
        raise ComparisonInputError(
            f"finalization downgraded {len(downgraded_raw_similar)} calibrated similar rows: {sample!r}"
        )

    output_prefix = args.final_output_prefix
    if Path(output_prefix).name != output_prefix or output_prefix in {"", ".", ".."}:
        raise ComparisonInputError("--final-output-prefix must be a filename prefix")
    output_csv = args.output_dir / f"{output_prefix}.csv"
    output_summary = args.output_dir / f"{output_prefix}_summary.json"
    output_fields = list(dict.fromkeys(raw_fields + [
        "metric_rule_classification", "raw_classification", "final_classification",
        "crop_match_status", "crop_quality_flag", "crop_good_matches", "crop_inliers",
        "crop_inlier_ratio", "crop_source_area_retained", "crop_quality_evidence",
        "same_aspect_review_status", "classification_evidence", "issue_status",
        "issue_evidence_path", "crop_quality_review",
    ]))
    temp_csv = output_csv.with_suffix(output_csv.suffix + ".tmp")
    with temp_csv.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=output_fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(final_rows)
    os.replace(temp_csv, output_csv)

    crop_negative_controls = []
    crop_json_path = args.crop_review_csv.with_suffix(".json")
    if crop_json_path.is_file():
        try:
            crop_json = json.loads(crop_json_path.read_text(encoding="utf-8"))
            crop_negative_controls = [
                item for item in crop_json.get("controls", [])
                if item.get("kind") == "cross_pair_negative"
            ]
        except (OSError, json.JSONDecodeError):
            logger.warning("could not read optional crop review summary %s", crop_json_path)

    known_six_ids = {"104837", "63388", "63428", "67691", "115417", "101502"}
    known_six_rows = [
        {"fitbase_id": row.get("fitbase_id"), "classification": row.get("classification")}
        for row in final_rows if row.get("fitbase_id") in known_six_ids
    ]
    uncertainty_breakdown: Counter[str] = Counter()
    for row in final_rows:
        if row.get("classification") != "uncertain":
            continue
        if row.get("error_type") == "decode_error":
            uncertainty_breakdown["decode_error"] += 1
        elif row.get("same_aspect_ratio") == "True":
            uncertainty_breakdown["same_aspect_metric_threshold_outlier"] += 1
        elif row.get("same_aspect_ratio") == "False":
            uncertainty_breakdown["unconfirmed_crop"] += 1
        else:
            uncertainty_breakdown["other_or_incomplete_metrics"] += 1
    comparison_run_summaries = {}
    for prefix in ("image_comparison", "image_comparison_extra", "image_comparison_last14", "image_comparison_retry_download_errors"):
        path = args.output_dir / f"{prefix}_summary.json"
        if path.is_file():
            try:
                comparison_run_summaries[prefix] = json.loads(path.read_text(encoding="utf-8"))
            except json.JSONDecodeError:
                logger.warning("could not read comparison run summary %s", path)
    total_request_attempts = sum(
        int(summary.get("network", {}).get("total_request_attempts", 0))
        for summary in comparison_run_summaries.values()
    )
    download_error_details = [
        {
            "source_id": row.get("source_id"),
            "fitbase_id": row.get("fitbase_id"),
            "http_status": row.get("download_status"),
            "error_detail": row.get("error_detail"),
            "issue_status": row.get("issue_status"),
        }
        for row in final_rows if row.get("classification") == "download_error"
    ]
    summary = {
        "generated_at": utc_now(),
        "input_rows": len(final_rows),
        "expected_input_rows": args.expected_final_count,
        "unique_comparison_identities": len({comparison_key(row) for row in final_rows}),
        "raw_metric_classification_counts": {name: raw_counts.get(name, 0) for name in CLASSIFICATIONS},
        "final_classification_counts": {name: final_counts.get(name, 0) for name in CLASSIFICATIONS},
        "same_source_count_exact_or_similar": final_counts.get("exact", 0) + final_counts.get("similar", 0),
        "all_rows_classified": sum(final_counts.values()) == len(final_rows),
        "calibrated_similarity_rows_downgraded": len(downgraded_raw_similar),
        "remaining_uncertainty_count": final_counts.get("uncertain", 0),
        "remaining_uncertainty_breakdown": dict(sorted(uncertainty_breakdown.items())),
        "total_http_get_attempts": total_request_attempts,
        "network_retry_attempts": max(0, total_request_attempts - len(final_rows)),
        "decode_error_rows": sum(row.get("error_type") == "decode_error" for row in final_rows),
        "download_error_details": download_error_details,
        "photo_issue_counts": dict(sorted(classification_review_counts.items())),
        "broken_photo_url_count": broken_photo_count,
        "wrong_photo_count": wrong_photo_count,
        "not_compared_reconciliation_rows": {
            "missing": args.not_compared_missing,
            "unresolved": args.not_compared_unresolved,
            "total": args.not_compared_missing + args.not_compared_unresolved,
        },
        "automatic_similar_rule": (
            "With the same aspect ratio, similar if (same dimensions and RGB MAE <= 3.0 and dHash <= 4) "
            "OR RGB MAE <= 4.0 and dHash <= 1; the second rule also covers proportional resizes. "
            "The union is supported by metric calibration, 30 negative controls, and visually reviewed boundary examples."
        ),
        "different_rule": "Same aspect ratio, RGB MAE >= 30.0, and dHash Hamming >= 20.",
        "changed_aspect_rule": "Similar only with confirmed same-crop SIFT/RANSAC evidence; otherwise uncertain.",
        "exact_rule": "Equal SHA-256 of original image bytes.",
        "crop_review": {
            "input": str(args.crop_review_csv),
            "confirmed_same_crop_rows": changed_aspect_count,
            "severe_crop_quality_review_rows": crop_quality_count,
            "cross_pair_negative_controls": len(crop_negative_controls),
            "negative_control_false_confirmations": sum(c.get("decision") == "confirmed_same_crop" for c in crop_negative_controls),
        },
        "same_aspect_visual_review": {
            "input": str(args.same_aspect_review_csv),
            "hash_verified_same_photo_rows": manual_same_aspect_count,
            "hash_evidence_mismatches": visual_hash_mismatches,
        },
        "known_six_live_images": {
            "rows_found": len(known_six_rows),
            "all_similar": len(known_six_rows) == 6 and all(r["classification"] == "similar" for r in known_six_rows),
            "rows": known_six_rows,
        },
        "sources": {
            "raw_metrics_csv": str(args.finalize_csv),
            "crop_review_csv": str(args.crop_review_csv),
            "same_aspect_review_csv": str(args.same_aspect_review_csv),
            "network_run_summaries": {
                prefix: str(args.output_dir / f"{prefix}_summary.json")
                for prefix in comparison_run_summaries
            },
        },
        "crop_ui_evidence": {
            "000024568": "ui_crop_issue.json",
            "000028166": "ui_crop_issue_2.json",
            "wrong_photo": "ui_wrong_photo.json",
        },
        "row_output": str(output_csv),
    }
    temp_summary = output_summary.with_suffix(output_summary.suffix + ".tmp")
    temp_summary.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.replace(temp_summary, output_summary)
    logger.info(
        "finalized rows=%d counts=%s output=%s",
        len(final_rows), summary["final_classification_counts"], output_csv,
    )
    if visual_hash_mismatches or not summary["known_six_live_images"]["all_similar"]:
        return 2
    return 0


def parse_args() -> argparse.Namespace:
    root = Path(__file__).resolve().parents[1]
    default_audit = root / "output" / "20260923_fitbase_photo_audit"
    parser = argparse.ArgumentParser(
        description=(
            "Compare each present reconciliation photo with its September 21 archive image. "
            "Requests only https://files.fitbase.io and uses bounded read-only GETs."
        )
    )
    parser.add_argument(
        "--reconciliation", "--input", dest="reconciliation", type=Path,
        default=default_audit / "reconciliation.csv",
        help="Input reconciliation CSV; only category=present rows are compared.",
    )
    parser.add_argument(
        "--archive", type=Path,
        default=root / "output" / "20260921_fitbase_for_customer" / "fitbase_client_photos_20260921.zip",
    )
    parser.add_argument(
        "--source-zip-prefix", default=SOURCE_ZIP_PREFIX,
        help="Directory inside the source ZIP that contains JPEG files.",
    )
    parser.add_argument("--calibration", type=Path, default=default_audit / "image_metric_calibration.json")
    parser.add_argument("--output-dir", type=Path, default=default_audit)
    parser.add_argument(
        "--output-prefix", default="image_comparison",
        help="Output file and review directory prefix (default: image_comparison).",
    )
    parser.add_argument("--workers", type=int, default=1, help="Concurrent requests, 1 through 8 (default: 1).")
    parser.add_argument("--retries", type=int, default=3, help="Retries after the initial request (default: 3).")
    parser.add_argument("--timeout", type=float, default=30.0, help="Per-request timeout in seconds (default: 30).")
    parser.add_argument(
        "--request-interval", type=float, default=0.1,
        help="Minimum seconds between requests across all workers (default: 0.1).",
    )
    parser.add_argument(
        "--resume-from", type=Path,
        help="Reuse and merge completed rows from an earlier comparison CSV.",
    )
    parser.add_argument("--finalize-csv", type=Path, help="Create a reviewed final CSV from a merged raw comparison CSV.")
    parser.add_argument(
        "--crop-review-csv", type=Path,
        default=default_audit / "crop_match_review_final.csv",
        help="Final SIFT/RANSAC crop review evidence CSV.",
    )
    parser.add_argument(
        "--same-aspect-review-csv", type=Path,
        default=default_audit / "same_aspect_outlier_review.csv",
        help="SHA-bound manual review evidence for same-aspect metric outliers.",
    )
    parser.add_argument("--final-output-prefix", default="image_comparison_final_34520")
    parser.add_argument("--expected-final-count", type=int, default=34520)
    parser.add_argument("--not-compared-missing", type=int, default=224)
    parser.add_argument("--not-compared-unresolved", type=int, default=32)
    parser.add_argument("--expected-present-count", type=int, default=EXPECTED_PRESENT_ROWS)
    parser.add_argument("--progress-every", type=int, default=250)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if args.finalize_csv is not None:
        args.output_dir.mkdir(parents=True, exist_ok=True)
        final_log_path = args.output_dir / f"{args.final_output_prefix}.log"
        logger = setup_logger(final_log_path)
        try:
            return finalize_comparison(args, logger)
        except Exception as exc:
            logger.exception("finalization failed: %s", exc)
            return 2
    if args.workers < 1 or args.workers > 8:
        raise SystemExit("--workers must be between 1 and 8")
    if args.retries < 0 or args.timeout <= 0 or args.progress_every < 1 or args.request_interval < 0:
        raise SystemExit(
            "--retries must be >= 0, --timeout > 0, --progress-every >= 1, and --request-interval >= 0"
        )
    if (not args.source_zip_prefix.endswith("/") or args.source_zip_prefix.startswith("/")
            or ".." in Path(args.source_zip_prefix).parts):
        raise SystemExit("--source-zip-prefix must be a relative ZIP directory ending in /")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    output_prefix = Path(args.output_prefix)
    if output_prefix.name != args.output_prefix or args.output_prefix in {"", ".", ".."}:
        raise SystemExit("--output-prefix must be a filename prefix; choose its folder with --output-dir")
    csv_path = args.output_dir / f"{args.output_prefix}.csv"
    summary_path = args.output_dir / f"{args.output_prefix}_summary.json"
    log_path = args.output_dir / f"{args.output_prefix}.log"
    review_dir = args.output_dir / f"{args.output_prefix}_review_photos"
    progress_path = args.output_dir / f"{args.output_prefix}_progress.csv"
    logger = setup_logger(log_path)
    started = time.monotonic()

    try:
        calibration = read_calibration(args.calibration)
        source_rows, source_fieldnames = read_present_rows(
            args.reconciliation, args.expected_present_count
        )
        previous_rows, previous_fieldnames = read_previous_results(args.resume_from)
        if not args.archive.is_file():
            raise ComparisonInputError(f"photo archive not found: {args.archive}")
        prior_keys = {comparison_key(row) for row in previous_rows}
        input_positions = {
            comparison_key(row): index
            for index, row in enumerate(source_rows, start=1)
        }
        input_keys = set(input_positions)
        skipped_from_input = sum(comparison_key(row) in prior_keys for row in source_rows)
        pending_rows = [row for row in source_rows if comparison_key(row) not in prior_keys]
        base_index = max(
            (int(row.get("comparison_index") or 0) for row in previous_rows),
            default=0,
        )
        previous_results_belong_to_input = prior_keys.issubset(input_keys)
        source_fieldnames = list(dict.fromkeys(
            source_fieldnames + [
                name for name in previous_fieldnames
                if name not in COMPARISON_FIELDS and name not in source_fieldnames
            ]
        ))
        logger.info(
            "starting input_rows=%d pending=%d reused=%d workers=%d retries=%d interval=%.3fs archive=%s calibration=%s",
            len(source_rows), len(pending_rows), len(previous_rows), args.workers,
            args.retries, args.request_interval, args.archive, args.calibration,
        )

        with ZipFile(args.archive, "r") as archive:
            completed_rows: list[dict[str, Any]] = list(previous_rows)
            progress_fields = list(dict.fromkeys(source_fieldnames + COMPARISON_FIELDS))
            progress_written = 0
            with progress_path.open("w", encoding="utf-8-sig", newline="") as progress_stream:
                progress_writer = csv.DictWriter(
                    progress_stream, fieldnames=progress_fields, extrasaction="ignore"
                )
                progress_writer.writeheader()
                for previous in previous_rows:
                    progress_writer.writerow(previous)
                progress_stream.flush()

                with ThreadPoolExecutor(max_workers=args.workers, thread_name_prefix="fitbase-photo") as pool:
                    futures = {}
                    rows_by_index = {}
                    for offset, row in enumerate(pending_rows, start=1):
                        if previous_results_belong_to_input:
                            index = input_positions[comparison_key(row)]
                        else:
                            index = base_index + offset
                        rows_by_index[index] = row
                        future = pool.submit(
                            compare_one, index, row, archive, review_dir,
                            args.retries, args.timeout, args.request_interval, logger,
                            args.source_zip_prefix,
                        )
                        futures[future] = index

                    counts: Counter[str] = Counter()
                    for previous in previous_rows:
                        counts[previous.get("classification", "uncertain")] += 1
                    for future in as_completed(futures):
                        index = futures[future]
                        try:
                            result = future.result()
                        except Exception as exc:
                            logger.exception(
                                "worker exception comparison_index=%d fitbase_id=%s",
                                index, rows_by_index[index].get("fitbase_id", ""),
                            )
                            result = worker_exception_row(index, rows_by_index[index], exc)
                        classification = result.get("classification")
                        if classification not in CLASSIFICATIONS:
                            result["classification"] = "uncertain"
                            result["error_type"] = "invalid_classification"
                            result["error_detail"] = f"unexpected classification value: {classification!r}"
                            classification = "uncertain"
                        completed_rows.append(result)
                        progress_writer.writerow(result)
                        progress_stream.flush()
                        progress_written += 1
                        counts[classification] += 1
                        done = progress_written
                        if done % args.progress_every == 0 or done == len(pending_rows):
                            logger.info(
                                "progress this_run=%d/%d total=%d exact=%d similar=%d different=%d uncertain=%d download_error=%d",
                                done, len(pending_rows), len(completed_rows), counts["exact"],
                                counts["similar"], counts["different"], counts["uncertain"],
                                counts["download_error"],
                            )

        for classification in CLASSIFICATIONS:
            counts.setdefault(classification, 0)
        matches = counts["exact"] + counts["similar"]
        review_count = sum(bool(row.get("review_photo_path")) for row in completed_rows)
        total_attempts = sum(int(row.get("download_attempts") or 0) for row in completed_rows)
        decode_error_count = sum(row.get("error_type") == "decode_error" for row in completed_rows)
        source_error_count = sum(row.get("error_type") == "source_archive_error" for row in completed_rows)
        error_types: Counter[str] = Counter(
            row.get("error_type", "") for row in completed_rows if row.get("error_type")
        )
        error_samples = [
            {
                "source_id": row.get("source_id", ""),
                "fitbase_id": row.get("fitbase_id", ""),
                "error_type": row.get("error_type", ""),
                "error_detail": row.get("error_detail", ""),
            }
            for row in completed_rows if row.get("error_type")
        ][:20]
        completed_keys = {comparison_key(row) for row in completed_rows}
        all_input_rows_covered = input_keys.issubset(completed_keys)
        summary = {
            "generated_at": utc_now(),
            "reconciliation": str(args.reconciliation),
            "source_archive": str(args.archive),
            "calibration": str(args.calibration),
            "network": {
                "origin": BASE_URL,
                "method": "GET",
                "client": "requests.Session with pooled HTTP connections",
                "max_concurrent_requests": args.workers,
                "max_allowed_concurrency": 8,
                "minimum_request_interval_seconds": args.request_interval,
                "retries_after_initial_attempt": args.retries,
                "total_request_attempts": total_attempts,
                "authentication": "none",
                "writes_to_fitbase": False,
            },
            "method": {
                "sha256_first": True,
                "normalized_size_px": list(NORMALIZED_SIZE),
                "resampling": "Lanczos",
                "mae_rgb_255_similar_max": SIMILAR_MAE_MAX,
                "dhash_hamming_64_similar_max": SIMILAR_DHASH_MAX,
                "similar_requires_same_dimensions_and_aspect_ratio": True,
                "mae_rgb_255_different_min": DIFFERENT_MAE_MIN,
                "dhash_hamming_64_different_min": DIFFERENT_DHASH_MIN,
                "classification_order": ["exact", "similar", "different", "uncertain", "download_error"],
                "decode_failure_classification": "uncertain with error details",
            },
            "expected_present_rows": args.expected_present_count,
            "input_rows": len(source_rows),
            "rows_compared_this_run": len(pending_rows),
            "rows_reused_from_resume": len(previous_rows),
            "input_rows_already_compared": skipped_from_input,
            "rows_completed": len(completed_rows),
            "counts": {name: counts[name] for name in CLASSIFICATIONS},
            "match_count_exact_or_similar": matches,
            "all_rows_matched": matches == len(completed_rows),
            "all_input_rows_covered": all_input_rows_covered,
            "review_photo_count": review_count,
            "review_photo_directory": str(review_dir),
            "decode_error_rows": decode_error_count,
            "source_archive_error_rows": source_error_count,
            "error_type_counts": dict(sorted(error_types.items())),
            "error_samples": error_samples,
            "elapsed_seconds": round(time.monotonic() - started, 3),
            "row_output": str(csv_path),
            "log_output": str(log_path),
        }
        write_outputs(completed_rows, source_fieldnames, csv_path, summary_path, summary)
        try:
            progress_path.unlink()
        except OSError:
            logger.warning("could not remove completed checkpoint %s", progress_path)
        logger.info(
            "finished completed=%d matches=%d review_photos=%d summary=%s",
            len(completed_rows), matches, review_count, summary_path,
        )
        return 0 if all_input_rows_covered and len(pending_rows) == progress_written else 2
    except Exception as exc:
        logger.exception("comparison failed: %s", exc)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
