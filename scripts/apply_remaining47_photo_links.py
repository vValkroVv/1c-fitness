#!/usr/bin/env python3
"""Apply the 15 confirmed phone/name/payment links to the saved photo audit.

This reproducible offline step reads the reconciliation, manual review, and a
complete saved Fitbase API snapshot. It never calls Fitbase or changes the
reconciliation input. Review evidence is copied into prefixed output columns.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_AUDIT_DIR = ROOT / "output/20260923_fitbase_photo_audit"
CLIENT_URL = "https://fitnes-imperiya.fitbase.io/clients/view?id={}"
LINK_DECISION = "linked_by_phone_name_prefix_and_paid_total"
UNRESOLVED_DECISION = "unresolved"
EXPECTED_INPUT_CATEGORIES = {"present": 34_506, "missing": 223, "unresolved": 47}
EXPECTED_REVIEW_DECISIONS = {LINK_DECISION: 15, UNRESOLVED_DECISION: 32}
EXPECTED_FINAL_CATEGORIES = {"present": 34_520, "missing": 224, "unresolved": 32}


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
    """Use the same photo-presence rule as the existing reconciliation step."""
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


def read_api_photo_records(
    snapshot_path: Path, target_ids: set[str]
) -> tuple[dict[str, dict[str, Any]], dict[str, Any]]:
    """Verify all snapshot records and retain the reviewed Fitbase IDs."""
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
    actual = {
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
        for key, value in actual.items()
        if metadata.get(key) != value
    }
    if mismatches:
        raise ValueError(f"API snapshot disagrees with completeness metadata: {mismatches}")
    if target_ids - selected.keys():
        missing = sorted(target_ids - selected.keys())
        raise ValueError(f"Reviewed Fitbase IDs absent from API snapshot: {missing[:10]}")

    return selected, {
        "file": snapshot_path.name,
        "sha256": snapshot_hash,
        "bytes": snapshot_path.stat().st_size,
        "records": raw_items,
        "unique_ids": len(all_ids),
        "metadata_check": "sha256, row count, unique IDs, total, and completeness verified",
    }


def split_ids(value: str) -> set[str]:
    return {part.strip() for part in value.split(";") if part.strip()}


def validate_review_link(row: dict[str, str]) -> None:
    source_id = row["source_id"]
    fitbase_id = row["confirmed_fitbase_id"].strip()
    if not fitbase_id:
        raise ValueError(f"{source_id}: linked review has no confirmed Fitbase ID")
    if fitbase_id not in split_ids(row["candidate_ids"]):
        raise ValueError(f"{source_id}: confirmed ID is absent from candidate_ids")
    if row["confirmed_photo_present"] not in {"yes", "no"}:
        raise ValueError(f"{source_id}: linked review has invalid photo flag")
    if not row["independent_identifier_result"].strip():
        raise ValueError(f"{source_id}: linked review has no independent identifier evidence")
    try:
        details = json.loads(row["candidate_details_json"])
    except json.JSONDecodeError as exc:
        raise ValueError(f"{source_id}: invalid candidate_details_json: {exc}") from exc
    matches = [item for item in details if str(item.get("id")) == fitbase_id]
    if len(matches) != 1:
        raise ValueError(f"{source_id}: candidate details do not contain exactly one confirmed ID")
    detail_photo = bool(matches[0].get("photo_present"))
    if detail_photo != (row["confirmed_photo_present"] == "yes"):
        raise ValueError(f"{source_id}: candidate detail photo flag disagrees with review")


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
            raise ValueError(f"Duplicate source ID in reconciliation input: {source_id}")
        source_rows[source_id] = row
    input_categories = Counter(row["category"] for row in original)
    if len(original) != 34_776 or dict(input_categories) != EXPECTED_INPUT_CATEGORIES:
        raise ValueError(
            f"Unexpected reconciliation input: rows={len(original)}, categories={dict(input_categories)}"
        )

    review_by_source: dict[str, dict[str, str]] = {}
    for row in review:
        source_id = row["source_id"]
        if source_id in review_by_source:
            raise ValueError(f"Duplicate source ID in remaining47 review: {source_id}")
        if source_id not in source_rows:
            raise ValueError(f"Review source ID is absent from reconciliation input: {source_id}")
        if source_rows[source_id]["category"] != "unresolved":
            raise ValueError(f"{source_id}: reviewed source row is not currently unresolved")
        review_by_source[source_id] = row
    decisions = Counter(row["decision"] for row in review)
    if len(review) != 47 or dict(decisions) != EXPECTED_REVIEW_DECISIONS:
        raise ValueError(f"Unexpected remaining47 review decisions: {dict(decisions)}")
    unresolved_ids = {row["source_id"] for row in original if row["category"] == "unresolved"}
    if set(review_by_source) != unresolved_ids:
        raise ValueError("Review does not cover exactly the unresolved reconciliation input rows")

    target_ids: set[str] = set()
    id_to_review: dict[str, dict[str, str]] = {}
    for row in review:
        if row["decision"] == LINK_DECISION:
            validate_review_link(row)
            fitbase_id = row["confirmed_fitbase_id"].strip()
            if fitbase_id in id_to_review:
                raise ValueError(
                    f"Fitbase ID {fitbase_id} is confirmed for both "
                    f"{id_to_review[fitbase_id]['source_id']} and {row['source_id']}"
                )
            id_to_review[fitbase_id] = row
            target_ids.add(fitbase_id)
        elif row["decision"] == UNRESOLVED_DECISION:
            if row["confirmed_fitbase_id"].strip() or row["confirmed_photo_present"].strip():
                raise ValueError(f"{row['source_id']}: unresolved row has confirmed match/photo")
        else:
            raise ValueError(f"{row['source_id']}: unsupported decision {row['decision']!r}")

    existing_fitbase_ids: dict[str, str] = {}
    for row in original:
        fitbase_id = row["fitbase_id"].strip()
        if fitbase_id:
            previous = existing_fitbase_ids.setdefault(fitbase_id, row["source_id"])
            if previous != row["source_id"]:
                raise ValueError(f"Input Fitbase ID {fitbase_id} maps to multiple source IDs")
    overlap = set(existing_fitbase_ids) & target_ids
    if overlap:
        raise ValueError(f"Reviewed Fitbase IDs conflict with current assignments: {sorted(overlap)[:10]}")

    # Keep source order and columns; add all 47 review fields with a clear prefix
    # so the paid-total matching evidence remains attached to its source row.
    evidence_fields = [f"remaining47_{field}" for field in review[0]]
    fields = list(original_fields) + evidence_fields
    rows_by_source: dict[str, dict[str, Any]] = {}
    for row in original:
        copied = dict(row)
        for field in evidence_fields:
            copied[field] = ""
        rows_by_source[row["source_id"]] = copied

    reviewed_photos: Counter[str] = Counter()
    present_source_ids: set[str] = set()
    for source_id, decision in review_by_source.items():
        result = rows_by_source[source_id]
        for key, value in decision.items():
            result[f"remaining47_{key}"] = value
        if decision["decision"] == UNRESOLVED_DECISION:
            continue

        fitbase_id = decision["confirmed_fitbase_id"].strip()
        client = api_clients[fitbase_id]
        api_photo = client.get("photo")
        api_has_photo = has_photo(api_photo)
        api_photo_url = photo_url(api_photo)
        expected_photo = decision["confirmed_photo_present"] == "yes"
        if api_has_photo != expected_photo:
            raise ValueError(
                f"{source_id}: snapshot photo presence disagrees with review for Fitbase ID {fitbase_id}"
            )
        if api_has_photo and not api_photo_url:
            raise ValueError(f"{source_id}: snapshot reports a photo without a usable photo URL")
        if not api_has_photo and api_photo_url:
            raise ValueError(f"{source_id}: snapshot photo URL is set while photo is considered missing")

        reviewed_photos["yes" if api_has_photo else "no"] += 1
        result["category"] = "present" if api_has_photo else "missing"
        result["reason"] = LINK_DECISION
        result["fitbase_id"] = fitbase_id
        result["fitbase_url"] = CLIENT_URL.format(fitbase_id)
        result["photo_url"] = api_photo_url
        result["match_method"] = LINK_DECISION
        if api_has_photo:
            present_source_ids.add(source_id)

    final_rows = [rows_by_source[row["source_id"]] for row in original]
    final_categories = Counter(row["category"] for row in final_rows)
    if dict(final_categories) != EXPECTED_FINAL_CATEGORIES:
        raise ValueError(f"Unexpected completed category counts: {dict(final_categories)}")
    if len(final_rows) != 34_776 or len({row["source_id"] for row in final_rows}) != 34_776:
        raise AssertionError("Completed reconciliation lost or duplicated selected source IDs")
    final_assignments: dict[str, str] = {}
    for row in final_rows:
        fitbase_id = row["fitbase_id"].strip()
        if fitbase_id:
            previous = final_assignments.setdefault(fitbase_id, row["source_id"])
            if previous != row["source_id"]:
                raise ValueError(f"Final Fitbase ID {fitbase_id} maps to multiple source IDs")

    present_supplement = [row for row in final_rows if row["source_id"] in present_source_ids]
    if len(present_supplement) != 14:
        raise ValueError(f"Expected 14 newly present photos, got {len(present_supplement)}")
    if len(final_assignments) != len(existing_fitbase_ids) + 15:
        raise AssertionError("Final unique Fitbase assignment count did not increase by 15")
    for row in present_supplement:
        if not row["fitbase_id"] or not row["photo_url"]:
            raise AssertionError(f"Present supplement row lacks Fitbase ID or photo URL: {row['source_id']}")

    summary = {
        "method": LINK_DECISION,
        "evidence_basis": (
            "Compatible source/API phone and API name prefix, plus source membership/service paid total "
            "matching the unique compatible API purchase_amount, as recorded row by row in remaining47_ evidence columns."
        ),
        "selected_rows": len(final_rows),
        "input_categories": dict(sorted(input_categories.items())),
        "review_rows": len(review),
        "review_decisions": dict(sorted(decisions.items())),
        "linked_photo_presence_from_snapshot": dict(sorted(reviewed_photos.items())),
        "final_categories": dict(sorted(final_categories.items())),
        "newly_present_rows_for_image_comparison": len(present_supplement),
        "newly_missing_rows": reviewed_photos["no"],
        "unresolved_rows": final_categories["unresolved"],
        "unique_source_ids": len({row["source_id"] for row in final_rows}),
        "unique_assigned_fitbase_ids": len(final_assignments),
        "api_snapshot": {},
        "outputs": {
            "complete_csv": "reconciliation_complete.csv",
            "summary_json": "reconciliation_complete_summary.json",
            "present_supplement_csv": "reconciliation_last14_present.csv",
        },
        "notes": [
            "The 15 reviewed links use the accepted independent paid-total evidence recorded in remaining47_review.csv.",
            "Snapshot photo presence and photo_url are checked against the review decision before assigning present/missing.",
            "The 32 unresolved review rows remain unresolved.",
            "The input reconciliation, saved review, and local API snapshot are read-only inputs; no Fitbase calls or writes are made.",
        ],
    }
    return final_rows, present_supplement, fields, summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit-dir", type=Path, default=DEFAULT_AUDIT_DIR)
    parser.add_argument("--reconciliation", type=Path)
    parser.add_argument("--review", type=Path)
    parser.add_argument("--snapshot", type=Path)
    parser.add_argument("--output-dir", type=Path)
    args = parser.parse_args()

    audit_dir = args.audit_dir
    reconciliation_path = args.reconciliation or audit_dir / "reconciliation_final.csv"
    review_path = args.review or audit_dir / "remaining47_review.csv"
    snapshot_path = args.snapshot or audit_dir / "api_snapshot.jsonl"
    output_dir = args.output_dir or audit_dir
    input_hash_before = sha256_file(reconciliation_path)

    original, original_fields = read_csv(reconciliation_path)
    review, review_fields = read_csv(review_path)
    required_original = {
        "source_id", "category", "reason", "fitbase_id", "fitbase_url", "photo_url", "match_method"
    }
    required_review = {
        "source_id", "decision", "confirmed_fitbase_id", "confirmed_photo_present",
        "candidate_ids", "candidate_details_json", "independent_identifier_result",
    }
    if missing := required_original - set(original_fields):
        raise ValueError(f"Reconciliation input lacks columns: {sorted(missing)}")
    if missing := required_review - set(review_fields):
        raise ValueError(f"Review input lacks columns: {sorted(missing)}")

    target_ids = {
        row["confirmed_fitbase_id"].strip()
        for row in review
        if row["decision"] == LINK_DECISION
    }
    api_clients, snapshot_summary = read_api_photo_records(snapshot_path, target_ids)
    final_rows, present_supplement, fields, summary = finalize(
        original, original_fields, review, api_clients
    )
    summary["api_snapshot"] = snapshot_summary

    output_dir.mkdir(parents=True, exist_ok=True)
    complete_path = output_dir / "reconciliation_complete.csv"
    present_path = output_dir / "reconciliation_last14_present.csv"
    summary_path = output_dir / "reconciliation_complete_summary.json"
    write_csv(complete_path, final_rows, fields)
    write_csv(present_path, present_supplement, fields)
    if sha256_file(reconciliation_path) != input_hash_before:
        raise AssertionError("Reconciliation input changed while applying review links")

    # Read back the generated deliverables so row counts and the one-row missing
    # outcome are verified from the actual files written to disk.
    complete_check, _ = read_csv(complete_path)
    present_check, _ = read_csv(present_path)
    categories = Counter(row["category"] for row in complete_check)
    if len(complete_check) != 34_776 or dict(categories) != EXPECTED_FINAL_CATEGORIES:
        raise AssertionError(f"Written completed CSV has unexpected counts: {dict(categories)}")
    if len(present_check) != 14 or any(row["category"] != "present" for row in present_check):
        raise AssertionError("Written image-comparison supplement is not exactly 14 present rows")
    summary["input_sha256"] = {
        reconciliation_path.name: input_hash_before,
        review_path.name: sha256_file(review_path),
    }
    summary["output_sha256"] = {
        complete_path.name: sha256_file(complete_path),
        present_path.name: sha256_file(present_path),
    }
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
