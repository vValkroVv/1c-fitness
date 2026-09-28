#!/usr/bin/env python3
"""Fetch a complete read-only snapshot of the Fitbase v2 client endpoint."""

from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import random
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TOKEN_FILE = ROOT / "tmp/fitbase_api_read_token"
DEFAULT_OUTPUT_DIR = ROOT / "output/20260923_fitbase_photo_audit"
ENDPOINT = "https://api.fitbase.io/api/v2/client"
CLUB_HEADER_NAME = "club"
CLUB_HEADER_VALUE = "fitnes-imperiya"
RETRYABLE_STATUS = {408, 425, 429, 500, 502, 503, 504}


class SnapshotError(RuntimeError):
    """Raised when the API response cannot be proven to be a full snapshot."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def read_token(path: Path) -> str:
    if not path.is_file():
        raise SnapshotError(f"Token file does not exist: {path}")
    token = path.read_text(encoding="utf-8").strip()
    if not token:
        raise SnapshotError(f"Token file is empty: {path}")
    if "\n" in token or "\r" in token:
        raise SnapshotError("Token file must contain a single token line")
    return token[7:] if token.lower().startswith("bearer ") else token


def decode_response(raw: bytes, page: int, requested_page_size: int) -> dict:
    try:
        payload = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SnapshotError(f"Page {page}: response is not valid JSON") from exc
    if not isinstance(payload, dict):
        raise SnapshotError(f"Page {page}: expected a JSON object")
    required = {"items", "page", "page_size", "count", "total_count"}
    missing = required - payload.keys()
    if missing:
        raise SnapshotError(f"Page {page}: missing response fields: {', '.join(sorted(missing))}")
    if payload["page"] != page:
        raise SnapshotError(f"Page {page}: API returned page={payload['page']!r}")
    actual_page_size = payload["page_size"]
    if not isinstance(actual_page_size, int) or actual_page_size <= 0:
        raise SnapshotError(f"Page {page}: invalid page_size={actual_page_size!r}")
    if actual_page_size > requested_page_size:
        raise SnapshotError(f"Page {page}: API page_size exceeds requested value")
    if not isinstance(payload["items"], list):
        raise SnapshotError(f"Page {page}: items is not a list")
    if not isinstance(payload["count"], int) or payload["count"] != len(payload["items"]):
        raise SnapshotError(f"Page {page}: count does not match items length")
    if not isinstance(payload["total_count"], int) or payload["total_count"] < 0:
        raise SnapshotError(f"Page {page}: invalid total_count={payload['total_count']!r}")
    if payload["count"] > actual_page_size:
        raise SnapshotError(f"Page {page}: count exceeds page_size")
    for index, item in enumerate(payload["items"]):
        if not isinstance(item, dict) or item.get("id") is None:
            raise SnapshotError(f"Page {page}: item {index} is not an object with an id")
    return payload


def fetch_page(page: int, page_size: int, token: str, timeout: float, max_retries: int) -> tuple[int, dict, int]:
    query = urlencode({"page": page, "page_size": page_size})
    request = Request(
        f"{ENDPOINT}?{query}",
        headers={
            "Accept": "application/json",
            "Authorization": f"Bearer {token}",
            CLUB_HEADER_NAME: CLUB_HEADER_VALUE,
            "User-Agent": "fitbase-readonly-snapshot/1.0",
        },
        method="GET",
    )
    for attempt in range(max_retries + 1):
        try:
            with urlopen(request, timeout=timeout) as response:
                if response.status != 200:
                    raise SnapshotError(f"Page {page}: unexpected HTTP status {response.status}")
                payload = decode_response(response.read(), page, page_size)
                return page, payload, attempt
        except HTTPError as exc:
            status = exc.code
            retry_after = exc.headers.get("Retry-After") if exc.headers else None
            if status not in RETRYABLE_STATUS or attempt >= max_retries:
                # Deliberately omit exception text and URL to keep request details out of logs.
                raise SnapshotError(f"Page {page}: HTTP {status} after {attempt + 1} attempt(s)") from None
            try:
                wait_seconds = min(30.0, max(0.0, float(retry_after))) if retry_after else 0.0
            except ValueError:
                wait_seconds = 0.0
            delay = wait_seconds or min(20.0, 0.75 * (2 ** attempt) + random.uniform(0.0, 0.4))
            print(f"Retrying page {page} after HTTP {status} (attempt {attempt + 1}/{max_retries})", file=sys.stderr)
            time.sleep(delay)
        except (TimeoutError, URLError, ConnectionError) as exc:
            if attempt >= max_retries:
                reason = "timeout" if isinstance(exc, TimeoutError) else "network error"
                raise SnapshotError(f"Page {page}: {reason} after {attempt + 1} attempt(s)") from None
            delay = min(20.0, 0.75 * (2 ** attempt) + random.uniform(0.0, 0.4))
            print(f"Retrying page {page} after a network error (attempt {attempt + 1}/{max_retries})", file=sys.stderr)
            time.sleep(delay)
    raise AssertionError("retry loop exhausted")


def atomic_write_json(path: Path, payload: dict) -> None:
    encoded = (json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    fd, tmp_name = tempfile.mkstemp(prefix=f"{path.name}.", suffix=".tmp", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_path, path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()


def run_snapshot(args: argparse.Namespace) -> dict:
    token = read_token(args.token_file)
    args.output_dir.mkdir(parents=True, exist_ok=True)
    snapshot_path = args.output_dir / "api_snapshot.jsonl"
    metadata_path = args.output_dir / "api_snapshot_metadata.json"
    started_at = utc_now()
    started_clock = time.monotonic()
    total_retries = 0

    print("Fetching page 1...", flush=True)
    first_page, first, retries = fetch_page(1, args.page_size, token, args.timeout, args.max_retries)
    total_retries += retries
    expected_total = first["total_count"]
    effective_page_size = first["page_size"]
    page_count = max(1, math.ceil(expected_total / effective_page_size))
    responses: dict[int, dict] = {first_page: first}

    if page_count > 1:
        pages = range(2, page_count + 1)
        with ThreadPoolExecutor(max_workers=args.workers) as executor:
            futures = {
                executor.submit(fetch_page, page, args.page_size, token, args.timeout, args.max_retries): page
                for page in pages
            }
            done = 1
            for future in as_completed(futures):
                page, payload, retries = future.result()
                responses[page] = payload
                total_retries += retries
                done += 1
                if done % 25 == 0 or done == page_count:
                    print(f"Fetched {done}/{page_count} pages", flush=True)

    # Validate all pages and IDs before publishing a final artifact.
    if len(responses) != page_count or set(responses) != set(range(1, page_count + 1)):
        raise SnapshotError(f"Fetched {len(responses)} of {page_count} expected pages")
    ids: set[str] = set()
    items_by_page: dict[int, list[dict]] = {}
    observed_total = 0
    for page in range(1, page_count + 1):
        payload = responses[page]
        if payload["total_count"] != expected_total:
            raise SnapshotError(f"Page {page}: total_count changed during snapshot")
        if payload["page_size"] != effective_page_size:
            raise SnapshotError(f"Page {page}: page_size changed during snapshot")
        expected_count = min(effective_page_size, max(0, expected_total - (page - 1) * effective_page_size))
        if payload["count"] != expected_count:
            raise SnapshotError(f"Page {page}: expected {expected_count} items, got {payload['count']}")
        page_items = payload["items"]
        for item in page_items:
            client_id = str(item["id"])
            if client_id in ids:
                raise SnapshotError(f"Duplicate client id detected on page {page}: {client_id}")
            ids.add(client_id)
        observed_total += len(page_items)
        items_by_page[page] = page_items
    if observed_total != expected_total or len(ids) != expected_total:
        raise SnapshotError(f"Expected {expected_total} unique clients, received {observed_total}")

    hasher = hashlib.sha256()
    fd, tmp_name = tempfile.mkstemp(prefix=f"{snapshot_path.name}.", suffix=".tmp", dir=args.output_dir)
    tmp_path = Path(tmp_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            for page in range(1, page_count + 1):
                for item in items_by_page[page]:
                    line = (json.dumps(item, ensure_ascii=False, separators=(",", ":")) + "\n").encode("utf-8")
                    handle.write(line)
                    hasher.update(line)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_path, snapshot_path)
    finally:
        if tmp_path.exists():
            tmp_path.unlink()

    completed_at = utc_now()
    metadata = {
        "endpoint": ENDPOINT,
        "method": "GET",
        "club_header": {"name": CLUB_HEADER_NAME, "value": CLUB_HEADER_VALUE},
        "started_at_utc": started_at,
        "completed_at_utc": completed_at,
        "duration_seconds": round(time.monotonic() - started_clock, 3),
        "page_size_requested": args.page_size,
        "page_size_effective": effective_page_size,
        "page_count": page_count,
        "total_count_reported": expected_total,
        "records_written": observed_total,
        "unique_ids": len(ids),
        "duplicate_ids": 0,
        "retries": total_retries,
        "snapshot_file": snapshot_path.name,
        "snapshot_sha256": hasher.hexdigest(),
        "snapshot_bytes": snapshot_path.stat().st_size,
        "completeness_check": "passed",
    }
    atomic_write_json(metadata_path, metadata)
    return metadata


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--token-file", type=Path, default=DEFAULT_TOKEN_FILE)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--page-size", type=int, default=100)
    parser.add_argument("--workers", type=int, default=5)
    parser.add_argument("--max-retries", type=int, default=5)
    parser.add_argument("--timeout", type=float, default=60.0)
    args = parser.parse_args()
    if args.page_size < 1 or args.page_size > 100 or args.workers < 1 or args.workers > 12 or args.max_retries < 0 or args.timeout <= 0:
        parser.error("page size, workers, retry count, and timeout are outside valid bounds")
    try:
        metadata = run_snapshot(args)
    except (SnapshotError, OSError) as exc:
        print(f"Snapshot failed: {exc}", file=sys.stderr)
        return 1
    print(json.dumps(metadata, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
