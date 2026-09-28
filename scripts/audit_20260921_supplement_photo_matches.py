#!/usr/bin/env python3
"""Match the 371-client photo supplement to a read-only Fitbase client snapshot."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
from collections import Counter, defaultdict
from pathlib import Path
from zipfile import ZipFile

import openpyxl


ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / "end-to-end-xlsx/work/20260921_phone_dedup_supplement_371"
DELIVERY = ROOT / "output/20260921_phone_dedup_supplement_371"
AUDIT = ROOT / "output/20260923_fitbase_photo_audit"
PREFIX = "fitbase_client_photos_20260921_supplement_371/photos/"


def normal_name(value: str) -> str:
    return " ".join(str(value or "").casefold().replace("ё", "е").split())


def normal_phones(value: str) -> set[str]:
    result = set()
    for part in re.split(r"[,;\n]+", str(value or "")):
        digits = re.sub(r"\D", "", part)
        if len(digits) == 10:
            digits = "7" + digits
        elif len(digits) == 11 and digits.startswith("8"):
            digits = "7" + digits[1:]
        if len(digits) == 11 and digits.startswith("7"):
            result.add(digits)
    return result


def read_source() -> tuple[dict[str, dict], list[dict], dict[str, set[str]]]:
    with (WORK / "selected_clients.csv").open(encoding="utf-8-sig", newline="") as stream:
        selected = {row["client_id"]: row for row in csv.DictReader(stream)}
    if len(selected) != 371:
        raise ValueError(f"Expected 371 selected clients, got {len(selected)}")

    archive = DELIVERY / "fitbase_client_photos_20260921.zip"
    with ZipFile(archive) as z:
        member = next((name for name in z.namelist() if name.endswith("manifest.csv")), None)
        if member is None:
            raise ValueError("Photo ZIP has no manifest.csv")
        manifest = list(csv.DictReader(io.StringIO(z.read(member).decode("utf-8-sig"))))
        members = set(z.namelist())
        for row in manifest:
            path = PREFIX + row["filename"]
            if path not in members:
                raise ValueError(f"Missing JPEG in supplement ZIP: {path}")
    ids = [row["client_id"] for row in manifest]
    if len(manifest) != 244 or len(set(ids)) != 244 or not set(ids) <= set(selected):
        raise ValueError("Expected 244 unique photo IDs within selected 371 clients")

    main_manifest = AUDIT.parent / "20260922_fitbase_live_audit/photo_manifest.csv"
    with main_manifest.open(encoding="utf-8-sig", newline="") as stream:
        main_ids = {row["client_id"] for row in csv.DictReader(stream)}
    if main_ids & set(ids):
        raise ValueError("Main and supplement photo source IDs overlap")

    workbook = openpyxl.load_workbook(
        DELIVERY / "fitbase_import_abonementy_clientov_20260921.xlsx",
        read_only=True,
        data_only=True,
    )
    cards: dict[str, set[str]] = defaultdict(set)
    card_owners: dict[str, set[str]] = defaultdict(set)
    for row in list(workbook.active.values)[2:]:
        if row[2] and row[6]:
            client_id, card = str(row[2]), str(row[6])
            cards[client_id].add(card)
            card_owners[card].add(client_id)
    workbook.close()
    if any(len(owners) != 1 for owners in card_owners.values()):
        raise ValueError("Supplement card is assigned to multiple source clients")
    return selected, manifest, cards


def read_fitbase(snapshot: Path) -> tuple[dict[str, dict], dict, dict, dict]:
    metadata = json.loads(snapshot.with_name("api_snapshot_metadata.json").read_text())
    by_id: dict[str, dict] = {}
    by_name: dict[str, set[str]] = defaultdict(set)
    by_phone: dict[str, set[str]] = defaultdict(set)
    by_card: dict[str, set[str]] = defaultdict(set)
    digest = hashlib.sha256()
    with snapshot.open("rb") as stream:
        for line in stream:
            digest.update(line)
            item = json.loads(line)
            ident = str(item["id"])
            if ident in by_id:
                raise ValueError(f"Duplicate Fitbase ID: {ident}")
            name = normal_name(" ".join(str(item.get(k) or "") for k in ("surname", "name", "patronymic")))
            phones = set()
            for contact in item.get("contacts") or []:
                if contact.get("contact_type") == "phone":
                    phones |= normal_phones(contact.get("contact", ""))
            record = {
                "id": ident, "name": name, "phones": phones,
                "card": str(item.get("card") or ""),
                "photo": str(item.get("photo") or ""),
            }
            by_id[ident] = record
            by_name[name].add(ident)
            for phone in phones:
                by_phone[phone].add(ident)
            if record["card"]:
                by_card[record["card"]].add(ident)
    if digest.hexdigest() != metadata["snapshot_sha256"] or len(by_id) != metadata["total_count_reported"]:
        raise ValueError("Fitbase snapshot hash or row count differs from its metadata")
    return by_id, by_name, by_phone, by_card


def reconcile(selected: dict, manifest: list[dict], cards: dict, live: tuple) -> list[dict]:
    by_id, by_name, by_phone, by_card = live
    results = []
    for photo in manifest:
        source_id = photo["client_id"]
        source = selected[source_id]
        name = normal_name(source["client_fio"])
        phones = normal_phones(source["phones"])
        phone_candidates = set().union(*(by_phone[p] for p in phones)) if phones else set()
        exact = by_name[name] & phone_candidates
        card_candidates = set().union(*(by_card[c] for c in cards[source_id])) if cards[source_id] else set()
        card_phone = card_candidates & phone_candidates
        target_id = ""
        method = ""
        if len(exact) == 1:
            target_id = next(iter(exact))
            method = "unique_full_name_and_phone"
        elif len(card_phone) == 1:
            candidate = next(iter(card_phone))
            candidate_name = by_id[candidate]["name"]
            if candidate_name and (candidate_name in name or name in candidate_name):
                target_id = candidate
                method = "unique_source_card_and_phone_with_compatible_name"

        target = by_id.get(target_id) if target_id else None
        category = "present" if target and target["photo"] else "missing" if target else "unresolved"
        results.append({
            "source_id": source_id,
            "source_name": source["client_fio"],
            "source_phones": ";".join(sorted(phones)),
            "funnel": source["funnel"],
            "photo_file": photo["filename"],
            "source_sha256": photo["sha256"],
            "source_cards": ";".join(sorted(cards[source_id])),
            "category": category,
            "match_method": method,
            "fitbase_id": target_id,
            "fitbase_url": f"https://fitnes-imperiya.fitbase.io/clients/view?id={target_id}" if target else "",
            "photo_url": target["photo"] if target else "",
            "fitbase_card": target["card"] if target else "",
            "card_conflict": bool(target and cards[source_id] and target["card"] not in cards[source_id]),
            "exact_candidate_ids": ";".join(sorted(exact)),
            "card_phone_candidate_ids": ";".join(sorted(card_phone)),
            "same_name_candidate_ids": ";".join(sorted(by_name[name])),
            "same_phone_candidate_ids": ";".join(sorted(phone_candidates)),
        })

    assigned = [row["fitbase_id"] for row in results if row["fitbase_id"]]
    if len(assigned) != len(set(assigned)):
        raise ValueError("Multiple source photos map to the same Fitbase client")
    return results


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", type=Path, default=AUDIT / "api_snapshot.jsonl")
    parser.add_argument("--output-dir", type=Path, default=AUDIT / "supplement_371")
    args = parser.parse_args()
    selected, manifest, cards = read_source()
    rows = reconcile(selected, manifest, cards, read_fitbase(args.snapshot))
    args.output_dir.mkdir(parents=True, exist_ok=True)
    path = args.output_dir / "reconciliation.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    counts = Counter(row["category"] for row in rows)
    summary = {
        "source": str(DELIVERY / "fitbase_client_photos_20260921.zip"),
        "snapshot": str(args.snapshot),
        "source_clients": len(selected),
        "source_jpegs": len(manifest),
        "clients_without_source_jpeg": len(selected) - len(manifest),
        "match_categories": dict(counts),
        "match_methods": dict(Counter(row["match_method"] for row in rows)),
        "card_conflicts": sum(row["card_conflict"] for row in rows),
        "rows": len(rows),
        "output": str(path),
    }
    (args.output_dir / "reconciliation_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
