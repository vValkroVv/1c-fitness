#!/usr/bin/env python3
"""Integrate conservative unmatched-client review into the photo audit.

This is an offline step: it reads the reconciliation, review decisions, and a
complete saved API snapshot. It never calls Fitbase or changes Fitbase data.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_AUDIT_DIR = ROOT / "output/20260923_fitbase_photo_audit"
CLIENT_URL = "https://fitnes-imperiya.fitbase.io/clients/view?id={}"

EXPECTED_ORIGINAL = {"present": 33_860, "missing": 200, "ambiguous": 19, "not_found": 697}
EXPECTED_REVIEW = {
    "linked_by_unique_source_card_and_phone": 669,
    "unresolved": 47,
}
EXPECTED_FINAL = {"present": 34_506, "missing": 223, "unresolved": 47}


def read_csv(path: Path) -> tuple[list[dict[str, str]], list[str]]:
    with path.open(newline="", encoding="utf-8-sig") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames:
            raise ValueError(f"{path}: missing CSV header")
        rows = list(reader)
        if any(None in row for row in rows):
            raise ValueError(f"{path}: row has more columns than the header")
        return rows, list(reader.fieldnames)


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="raise")
        writer.writeheader()
        writer.writerows(rows)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def has_photo(photo: Any) -> bool:
    """Mirror the photo-presence rule used by the original reconciliation."""
    if photo is None or photo is False or photo == "":
        return False
    if isinstance(photo, (dict, list)):
        return bool(photo)
    return True


def photo_url(photo: Any) -> str:
    if isinstance(photo, str):
        return photo.strip()
    if isinstance(photo, dict):
        for key in ("url", "original", "full", "path", "src"):
            value = photo.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
    return ""


def read_api_photo_records(snapshot_path: Path, target_ids: set[str]) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Read and verify the complete JSONL snapshot, retaining reviewed IDs only."""
    metadata_path = snapshot_path.with_name("api_snapshot_metadata.json")
    if not metadata_path.is_file():
        raise ValueError(f"Missing API snapshot metadata: {metadata_path}")
    metadata = json.loads(metadata_path.read_text(encoding="utf-8"))

    digest = hashlib.sha256()
    all_ids: set[str] = set()
    selected: dict[str, dict[str, Any]] = {}
    raw_items = 0
    with snapshot_path.open("rb") as stream:
        for line_number, raw_line in enumerate(stream, 1):
            digest.update(raw_line)
            if not raw_line.strip():
                continue
            try:
                record = json.loads(raw_line.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError) as exc:
                raise ValueError(f"{snapshot_path}:{line_number}: invalid JSON: {exc}") from exc
            items = record.get("items") if isinstance(record, dict) else None
            if not isinstance(items, list):
                items = [record]
            for item in items:
                if not isinstance(item, dict) or item.get("id") is None:
                    raise ValueError(f"{snapshot_path}:{line_number}: client missing id")
                identifier = str(item["id"])
                raw_items += 1
                if identifier in all_ids:
                    raise ValueError(f"Duplicate Fitbase ID in API snapshot: {identifier}")
                all_ids.add(identifier)
                if identifier in target_ids:
                    selected[identifier] = item

    snapshot_hash = digest.hexdigest()
    expected_values = {
        "snapshot_file": snapshot_path.name,
        "snapshot_sha256": snapshot_hash,
        "records_written": raw_items,
        "unique_ids": len(all_ids),
        "total_count_reported": len(all_ids),
        "duplicate_ids": 0,
        "completeness_check": "passed",
    }
    mismatches = {
        key: {"metadata": metadata.get(key), "snapshot": value}
        for key, value in expected_values.items()
        if metadata.get(key) != value
    }
    if mismatches:
        raise ValueError(f"API snapshot disagrees with completeness metadata: {mismatches}")
    if target_ids - selected.keys():
        missing = sorted(target_ids - selected.keys())
        raise ValueError(f"Reviewed Fitbase IDs absent from API snapshot: {missing[:10]}")
    return selected, {
        "snapshot_file": snapshot_path.name,
        "snapshot_sha256": snapshot_hash,
        "snapshot_bytes": snapshot_path.stat().st_size,
        "snapshot_raw_items": raw_items,
        "snapshot_unique_ids": len(all_ids),
        "snapshot_metadata_check": "sha256, row count, unique IDs, total, and completeness verified",
    }


def candidate_ids(value: str) -> set[str]:
    return {part.strip() for part in value.split(";") if part.strip()}


def validate_review_link(row: dict[str, str]) -> None:
    confirmed_id = row["confirmed_fitbase_id"].strip()
    cards = candidate_ids(row["card_candidate_ids"])
    phones = candidate_ids(row["phone_candidate_ids"])
    if not confirmed_id:
        raise ValueError(f"{row['source_id']}: linked review has no confirmed Fitbase ID")
    if cards != {confirmed_id}:
        raise ValueError(f"{row['source_id']}: card candidate is not uniquely the confirmed ID: {cards}")
    if cards & phones != {confirmed_id}:
        raise ValueError(f"{row['source_id']}: card/phone intersection conflicts with confirmed ID")
    if row["confirmed_photo_present"] not in {"yes", "no"}:
        raise ValueError(f"{row['source_id']}: linked review has invalid photo flag")
    try:
        details = json.loads(row["candidate_details_json"])
    except json.JSONDecodeError as exc:
        raise ValueError(f"{row['source_id']}: invalid candidate_details_json: {exc}") from exc
    confirmed_details = [item for item in details if str(item.get("id")) == confirmed_id]
    if len(confirmed_details) != 1 or "card+phone" not in confirmed_details[0].get("basis", ""):
        raise ValueError(f"{row['source_id']}: candidate details do not support a unique card + phone link")


def finalize(
    original: list[dict[str, str]],
    original_fields: list[str],
    review: list[dict[str, str]],
    api_clients: dict[str, dict[str, Any]],
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], dict[str, Any]]:
    source_rows: dict[str, dict[str, str]] = {}
    for row in original:
        source_id = row["source_id"]
        if source_id in source_rows:
            raise ValueError(f"Duplicate source ID in original reconciliation: {source_id}")
        source_rows[source_id] = row
    if len(source_rows) != 34_776:
        raise ValueError(f"Expected 34,776 selected source IDs, got {len(source_rows)}")
    original_categories = Counter(row["category"] for row in original)
    if dict(original_categories) != EXPECTED_ORIGINAL:
        raise ValueError(f"Unexpected original category counts: {dict(original_categories)}")

    review_by_source: dict[str, dict[str, str]] = {}
    for row in review:
        source_id = row["source_id"]
        if source_id in review_by_source:
            raise ValueError(f"Duplicate source ID in unmatched review: {source_id}")
        if source_id not in source_rows:
            raise ValueError(f"Review source ID is absent from original reconciliation: {source_id}")
        original_row = source_rows[source_id]
        if row["original_category"] != original_row["category"]:
            raise ValueError(f"{source_id}: review category disagrees with original reconciliation")
        if row["original_exact_fitbase_ids"] != original_row["exact_fitbase_ids"]:
            raise ValueError(f"{source_id}: review exact Fitbase IDs disagree with original reconciliation")
        review_by_source[source_id] = row
    review_decisions = Counter(row["review_decision"] for row in review)
    if len(review) != 716 or dict(review_decisions) != EXPECTED_REVIEW:
        raise ValueError(f"Unexpected review decisions: {dict(review_decisions)}")
    if {row["original_category"] for row in review} != {"ambiguous", "not_found"}:
        raise ValueError("Review unexpectedly includes rows outside ambiguous/not_found")
    expected_review_ids = {row["source_id"] for row in original if row["category"] in {"ambiguous", "not_found"}}
    if set(review_by_source) != expected_review_ids:
        raise ValueError("Unmatched review does not cover every ambiguous and not_found source row")

    confirmed_rows: dict[str, dict[str, str]] = {}
    target_ids: set[str] = set()
    for row in review:
        if row["review_decision"] == "linked_by_unique_source_card_and_phone":
            validate_review_link(row)
            confirmed_id = row["confirmed_fitbase_id"].strip()
            if confirmed_id in confirmed_rows:
                raise ValueError(
                    f"Fitbase ID {confirmed_id} was confirmed for both "
                    f"{confirmed_rows[confirmed_id]['source_id']} and {row['source_id']}"
                )
            confirmed_rows[confirmed_id] = row
            target_ids.add(confirmed_id)
        elif row["review_decision"] == "unresolved":
            if row["confirmed_fitbase_id"].strip() or row["confirmed_photo_present"].strip():
                raise ValueError(f"{row['source_id']}: unresolved review has a confirmed match/photo")
        else:
            raise ValueError(f"{row['source_id']}: unsupported review decision {row['review_decision']!r}")

    # Existing assignments and recovered assignments must remain one-to-one.
    assigned_fitbase: dict[str, str] = {}
    for row in original:
        fitbase_id = row["fitbase_id"].strip()
        if fitbase_id:
            previous = assigned_fitbase.setdefault(fitbase_id, row["source_id"])
            if previous != row["source_id"]:
                raise ValueError(f"Original Fitbase ID {fitbase_id} maps to multiple source IDs")
    overlap = set(assigned_fitbase) & target_ids
    if overlap:
        raise ValueError(f"Reviewed Fitbase IDs conflict with existing assignments: {sorted(overlap)[:10]}")

    rows_by_source = {row["source_id"]: dict(row) for row in original}
    for row in original:
        row["match_method"] = row["reason"]

    photo_flag_counts: Counter[str] = Counter()
    recovered_present_ids: set[str] = set()
    for source_id, decision in review_by_source.items():
        row = rows_by_source[source_id]
        if decision["review_decision"] == "unresolved":
            row["category"] = "unresolved"
            row["match_method"] = "unresolved_manual_review"
            continue

        fitbase_id = decision["confirmed_fitbase_id"].strip()
        client = api_clients[fitbase_id]
        api_has_photo = has_photo(client.get("photo"))
        api_photo_url = photo_url(client.get("photo"))
        expected_photo = decision["confirmed_photo_present"] == "yes"
        if api_has_photo != expected_photo:
            raise ValueError(
                f"{source_id}: API photo presence disagrees with review for Fitbase ID {fitbase_id}"
            )
        photo_flag_counts["yes" if api_has_photo else "no"] += 1
        if api_has_photo and not api_photo_url:
            raise ValueError(f"{source_id}: API reports a photo but provides no photo_url for {fitbase_id}")

        row["category"] = "present" if api_has_photo else "missing"
        row["reason"] = "linked_by_unique_source_card_and_phone"
        row["fitbase_id"] = fitbase_id
        row["fitbase_url"] = CLIENT_URL.format(fitbase_id)
        row["photo_url"] = api_photo_url
        row["match_method"] = "unique_source_card_and_phone"
        if api_has_photo:
            recovered_present_ids.add(source_id)

    final_rows = [rows_by_source[row["source_id"]] for row in original]
    final_fitbase_assignments: dict[str, str] = {}
    for row in final_rows:
        fitbase_id = row["fitbase_id"].strip()
        if fitbase_id:
            previous = final_fitbase_assignments.setdefault(fitbase_id, row["source_id"])
            if previous != row["source_id"]:
                raise ValueError(f"Final Fitbase ID {fitbase_id} maps to multiple source IDs")
    final_categories = Counter(row["category"] for row in final_rows)
    if dict(final_categories) != EXPECTED_FINAL:
        raise ValueError(f"Unexpected final category counts: {dict(final_categories)}")
    if len(final_rows) != 34_776 or len({row["source_id"] for row in final_rows}) != 34_776:
        raise AssertionError("Final reconciliation lost or duplicated selected source IDs")

    extra_present = [row for row in final_rows if row["source_id"] in recovered_present_ids]
    if len(extra_present) != 646:
        raise AssertionError(f"Expected 646 recovered present rows for image comparison, got {len(extra_present)}")
    for row in extra_present:
        if not row["fitbase_id"] or not row["photo_url"]:
            raise AssertionError(f"Recovered present row lacks Fitbase ID or photo URL: {row['source_id']}")

    summary = {
        "method": "unique source card and phone, verified against the complete saved Fitbase API snapshot",
        "selected_rows": len(final_rows),
        "original_categories": dict(sorted(original_categories.items())),
        "review_rows": len(review),
        "review_decisions": dict(sorted(review_decisions.items())),
        "reviewed_photo_presence": dict(sorted(photo_flag_counts.items())),
        "final_categories": dict(sorted(final_categories.items())),
        "recovered_present_rows_for_image_comparison": len(extra_present),
        "recovered_missing_rows": photo_flag_counts["no"],
        "unresolved_rows": final_categories["unresolved"],
        "unique_source_ids": len({row["source_id"] for row in final_rows}),
        "unique_assigned_fitbase_ids": len(final_fitbase_assignments),
        "api_snapshot": {},
        "outputs": {
            "reconciliation_final_csv": "reconciliation_final.csv",
            "reconciliation_extra_present_csv": "reconciliation_extra_present.csv",
            "summary_json": "reconciliation_final_summary.json",
        },
        "notes": [
            "Original exact-name matching diagnostics are retained in their original columns.",
            "The 47 undecided review rows are categorized as unresolved.",
            "Recovered photo URLs are copied from the complete local API snapshot; no API calls or Fitbase writes are made.",
        ],
    }
    fields = list(original_fields)
    fields.append("match_method")
    return final_rows, extra_present, {"summary": summary, "fields": fields}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit-dir", type=Path, default=DEFAULT_AUDIT_DIR)
    parser.add_argument("--reconciliation", type=Path)
    parser.add_argument("--review", type=Path)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()

    audit_dir = args.audit_dir
    reconciliation_path = args.reconciliation or audit_dir / "reconciliation.csv"
    review_path = args.review or audit_dir / "unmatched_review.csv"
    snapshot_path = args.snapshot or audit_dir / "api_snapshot.jsonl"
    output_dir = args.output_dir or audit_dir

    original, original_fields = read_csv(reconciliation_path)
    review, review_fields = read_csv(review_path)
    required_original = {
        "source_id", "category", "reason", "fitbase_id", "fitbase_url", "photo_url", "exact_fitbase_ids"
    }
    required_review = {
        "source_id", "original_category", "original_exact_fitbase_ids", "review_decision",
        "confirmed_fitbase_id", "confirmed_photo_present", "card_candidate_ids", "phone_candidate_ids",
        "candidate_details_json",
    }
    if missing := required_original - set(original_fields):
        raise ValueError(f"Original reconciliation is missing required columns: {sorted(missing)}")
    if missing := required_review - set(review_fields):
        raise ValueError(f"Unmatched review is missing required columns: {sorted(missing)}")

    linked_ids = {
        row["confirmed_fitbase_id"].strip()
        for row in review
        if row["review_decision"] == "linked_by_unique_source_card_and_phone"
    }
    api_clients, snapshot_summary = read_api_photo_records(snapshot_path, linked_ids)
    final_rows, extra_present, result = finalize(original, original_fields, review, api_clients)
    result["summary"]["api_snapshot"] = snapshot_summary
    output_dir.mkdir(parents=True, exist_ok=True)

    final_path = output_dir / "reconciliation_final.csv"
    extra_path = output_dir / "reconciliation_extra_present.csv"
    summary_path = output_dir / "reconciliation_final_summary.json"
    write_csv(final_path, final_rows, result["fields"])
    write_csv(extra_path, extra_present, result["fields"])
    result["summary"]["output_sha256"] = {
        final_path.name: sha256_file(final_path),
        extra_path.name: sha256_file(extra_path),
    }
    summary_path.write_text(
        json.dumps(result["summary"], ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(json.dumps(result["summary"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
