#!/usr/bin/env python3
"""Reconcile delivered photo clients against a read-only Fitbase API snapshot.

Matching requires both the complete client name and a phone in any contact.
This script never calls Fitbase or changes its data.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import sqlite3
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_INPUT = ROOT / "output/20260923_fitbase_photo_audit/api_snapshot.jsonl"
DEFAULT_OUTPUT = ROOT / "output/20260923_fitbase_photo_audit"
MANIFEST = ROOT / "output/20260922_fitbase_live_audit/photo_manifest.csv"
SOURCE = ROOT / "output/20260922_fitbase_live_audit/source.sqlite"
COHORT = ROOT / "output/20260922_fitbase_live_audit/blank_client_links/cohort.json"
CLIENT_URL = "https://fitnes-imperiya.fitbase.io/clients/view?id={}"


def name_key(value: Any) -> str:
    return " ".join(str(value or "").replace("ё", "е").replace("Ё", "Е").casefold().split())


def phone_key(value: Any) -> str:
    digits = re.sub(r"\D", "", str(value or ""))
    if len(digits) == 10:
        return "7" + digits
    if len(digits) == 11 and digits[0] == "8":
        return "7" + digits[1:]
    return digits


def source_phone_keys(value: Any) -> set[str]:
    return {number for part in re.split(r"[,;\n]+", str(value or "")) if (number := phone_key(part))}


def api_name(item: dict[str, Any]) -> str:
    return " ".join(str(item.get(field) or "").strip() for field in ("surname", "name", "patronymic")).strip()


def api_phones(item: dict[str, Any]) -> set[str]:
    result = set()
    for contact in item.get("contacts") or []:
        if not isinstance(contact, dict):
            continue
        contact_type = str(contact.get("contact_type") or "").casefold()
        if contact_type not in ("phone", "телефон", "1"):
            continue
        number = phone_key(contact.get("contact"))
        if number:
            result.add(number)
    return result


def photo_url(photo: Any) -> str:
    if isinstance(photo, str):
        return photo.strip()
    if isinstance(photo, dict):
        for key in ("url", "original", "full", "path", "src"):
            value = photo.get(key)
            if isinstance(value, str) and value.strip():
                return value.strip()
        # A nonempty object still signals a photo, although its URL is unknown.
        return ""
    return ""


def has_photo(photo: Any) -> bool:
    if photo is None or photo is False or photo == "":
        return False
    if isinstance(photo, (dict, list)):
        return bool(photo)
    return True


def load_snapshot(path: Path) -> tuple[dict[str, dict[str, Any]], list[int], int, str]:
    clients: dict[str, dict[str, Any]] = {}
    declared_totals: list[int] = []
    raw_items = 0
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for line_number, raw_line in enumerate(stream, 1):
            digest.update(raw_line)
            line = raw_line.decode("utf-8")
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as exc:
                raise ValueError(f"{path}:{line_number}: invalid JSON: {exc}") from exc
            if not isinstance(record, dict):
                raise ValueError(f"{path}:{line_number}: expected JSON object")
            if isinstance(record.get("items"), list):
                items = record["items"]
                if record.get("total_count") is not None:
                    declared_totals.append(int(record["total_count"]))
            else:
                items = [record]
            for item in items:
                if not isinstance(item, dict) or item.get("id") is None:
                    raise ValueError(f"{path}:{line_number}: client missing id")
                raw_items += 1
                identifier = str(item["id"])
                compact = {key: item.get(key) for key in ("name", "surname", "patronymic", "photo", "contacts")}
                if identifier in clients and clients[identifier] != compact:
                    raise ValueError(f"Fitbase id {identifier} has conflicting snapshot records")
                clients[identifier] = compact
    if not clients:
        raise ValueError("API snapshot has no clients")
    if declared_totals and (len(set(declared_totals)) != 1 or len(clients) != declared_totals[0]):
        raise ValueError(f"API snapshot incomplete: {len(clients)} unique IDs, declared totals {set(declared_totals)}")
    return clients, declared_totals, raw_items, digest.hexdigest()


def load_source() -> tuple[list[dict[str, str]], list[dict[str, str]], dict[str, str]]:
    with MANIFEST.open(newline="", encoding="utf-8-sig") as stream:
        manifest = list(csv.DictReader(stream))
    manifest_ids = [row["client_id"] for row in manifest]
    if len(manifest) != 35422 or len(set(manifest_ids)) != len(manifest_ids):
        raise ValueError(f"Photo manifest expected 35,422 unique source IDs; got {len(manifest)} rows / {len(set(manifest_ids))} IDs")
    with sqlite3.connect(SOURCE) as connection:
        leads = connection.execute("SELECT client_id, phone, client_fio FROM leads").fetchall()
    names: dict[str, str] = {}
    source_phones: dict[str, set[str]] = {}
    for client_id, phone, full_name in leads:
        if client_id in names:
            raise ValueError(f"Duplicate source lead ID: {client_id}")
        names[client_id] = full_name or ""
        source_phones[client_id] = source_phone_keys(phone)
    missing = set(manifest_ids) - names.keys()
    if missing:
        raise ValueError(f"Manifest IDs absent from leads: {len(missing)}")
    cohort = json.loads(COHORT.read_text(encoding="utf-8"))
    if not isinstance(cohort, list):
        raise ValueError("Cohort must be a JSON array")
    excluded_ids = {row["client_id"] for row in cohort if not row.get("source_memberships")}
    excluded_manifest = excluded_ids & set(manifest_ids)
    if len(excluded_ids) != 717 or len(excluded_manifest) != 646:
        raise ValueError(f"Expected 717 no-membership IDs / 646 in manifest; got {len(excluded_ids)} / {len(excluded_manifest)}")
    selected, excluded = [], []
    for row in manifest:
        source_id = row["client_id"]
        enriched = {
            "source_id": source_id,
            "source_name": names[source_id],
            "source_phone": phone_key(row["assigned_phone"]),
            "source_all_phones": ";".join(sorted(source_phones[source_id])),
            "assigned_phone": phone_key(row["assigned_phone"]),
            "funnel": row["funnel"],
            "photo_file": row["filename"],
        }
        if not enriched["source_phone"] or enriched["source_phone"] not in source_phones[source_id]:
            raise ValueError(f"Assigned photo phone absent from source lead for {source_id}")
        (excluded if source_id in excluded_ids else selected).append(enriched)
    if len(selected) != 34776 or len(excluded) != 646:
        raise ValueError(f"Expected 34,776 selected / 646 excluded, got {len(selected)} / {len(excluded)}")
    return selected, excluded, {"cohort_total": str(len(cohort)), "no_membership_total": str(len(excluded_ids))}


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    with path.open("w", newline="", encoding="utf-8-sig") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def reconcile(selected: list[dict[str, str]], clients: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    exact: dict[tuple[str, str], set[str]] = defaultdict(set)
    by_phone: dict[str, set[str]] = defaultdict(set)
    by_name: dict[str, set[str]] = defaultdict(set)
    for identifier, item in clients.items():
        full_name = name_key(api_name(item))
        phones = api_phones(item)
        if full_name:
            by_name[full_name].add(identifier)
        for phone in phones:
            by_phone[phone].add(identifier)
            if full_name:
                exact[(full_name, phone)].add(identifier)

    source_keys: dict[tuple[str, str], set[str]] = defaultdict(set)
    for row in selected:
        for phone in row["source_all_phones"].split(";"):
            if phone:
                source_keys[(name_key(row["source_name"]), phone)].add(row["source_id"])

    results = []
    for row in selected:
        name = name_key(row["source_name"])
        phones = {phone for phone in row["source_all_phones"].split(";") if phone}
        matches_set = set().union(*(exact.get((name, phone), set()) for phone in phones))
        matches = sorted(matches_set, key=lambda value: (not value.isdigit(), int(value) if value.isdigit() else value))
        phone_candidates = set().union(*(by_phone.get(phone, set()) for phone in phones))
        phone_conflicts = sorted(phone_candidates - matches_set)
        name_conflicts = sorted(by_name.get(name, set()) - matches_set) if name else []
        duplicate_sources = set().union(*(source_keys[(name, phone)] for phone in phones))
        target = clients[matches[0]] if len(matches) == 1 else None
        if len(matches) > 1 or (matches and len(duplicate_sources) > 1):
            category = "ambiguous"
            reason = "multiple_fitbase_exact_matches" if len(matches) > 1 else "multiple_source_clients_same_name_phone"
        elif target is None:
            category = "not_found"
            reason = "missing_source_name_or_phone" if not name or not phones else "no_exact_name_and_phone_match"
        else:
            category = "present" if has_photo(target.get("photo")) else "missing"
            reason = "exact_full_name_and_contact_phone"
        result = dict(row)
        result.update({
            "category": category,
            "reason": reason,
            "fitbase_id": matches[0] if target is not None else "",
            "fitbase_url": CLIENT_URL.format(matches[0]) if target is not None else "",
            "photo_url": photo_url(target.get("photo")) if target is not None else "",
            "exact_match_count": len(matches),
            "exact_fitbase_ids": ";".join(matches),
            "same_phone_other_name_ids": ";".join(phone_conflicts),
            "same_name_other_phone_ids": ";".join(name_conflicts),
            "same_identity_source_ids": ";".join(sorted(duplicate_sources)) if len(duplicate_sources) > 1 else "",
        })
        results.append(result)
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=DEFAULT_INPUT)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    selected, excluded, cohort_info = load_source()
    clients, declared_totals, raw_items, snapshot_sha256 = load_snapshot(args.snapshot)
    metadata_path = args.snapshot.with_name("api_snapshot_metadata.json")
    metadata_check = "metadata unavailable"
    if metadata_path.exists():
        metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
        if metadata.get("snapshot_file") == args.snapshot.name:
            if (metadata.get("snapshot_sha256") != snapshot_sha256 or
                    metadata.get("records_written") != raw_items or
                    metadata.get("unique_ids") != len(clients) or
                    metadata.get("total_count_reported") != len(clients) or
                    metadata.get("completeness_check") != "passed"):
                raise ValueError("API snapshot disagrees with fetch completeness metadata")
            metadata_check = "sha256, records, unique IDs, and reported total verified"
    if metadata_check == "metadata unavailable" and not declared_totals:
        raise ValueError("Cannot prove snapshot completeness: no matching metadata or declared total")
    results = reconcile(selected, clients)
    categories = Counter(row["category"] for row in results)
    if sum(categories.values()) != 34776:
        raise AssertionError("Reconciliation lost source clients")
    output_dir = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    result_fields = list(results[0])
    write_csv(output_dir / "reconciliation.csv", results, result_fields)
    write_csv(output_dir / "reconciliation_excluded.csv", excluded, list(excluded[0]))
    summary = {
        "method": "exact normalized complete surname name patronymic and any phone contact",
        "snapshot": str(args.snapshot),
        "snapshot_unique_client_ids": len(clients),
        "snapshot_raw_items": raw_items,
        "snapshot_sha256": snapshot_sha256,
        "snapshot_metadata_check": metadata_check,
        "snapshot_declared_total_counts": sorted(set(declared_totals)),
        "snapshot_exhaustive_check": metadata_check if metadata_check != "metadata unavailable" else "declared total verified",
        "manifest_rows": len(selected) + len(excluded),
        "selected_rows": len(selected),
        "excluded_no_membership_rows": len(excluded),
        "cohort": cohort_info,
        "categories": dict(sorted(categories.items())),
        "rows_with_phone_name_conflict": sum(bool(row["same_phone_other_name_ids"] or row["same_name_other_phone_ids"]) for row in results),
        "rows_with_duplicate_source_identity": sum(bool(row["same_identity_source_ids"]) for row in results),
        "uncertainty": [
            "Exact matching can miss spelling changes, transliteration, and changed phone numbers.",
            "A name-only or phone-only candidate is recorded as conflict evidence and is never counted as a match.",
            "Photo presence comes from the API photo field; image accessibility/content is not independently checked.",
        ],
    }
    (output_dir / "reconciliation_summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
