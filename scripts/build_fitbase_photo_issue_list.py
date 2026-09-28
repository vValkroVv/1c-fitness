#!/usr/bin/env python3
"""Build an actionable list of Fitbase photo presence and identity issues."""

from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
INPUT = ROOT / "output/20260923_fitbase_photo_audit/reconciliation_complete.csv"
OUTPUT = ROOT / "output/20260923_fitbase_photo_audit/photo_issues_presence.csv"
SUMMARY = ROOT / "output/20260923_fitbase_photo_audit/photo_issues_presence_summary.json"

ISSUE_CATEGORIES = {"missing", "unresolved"}
EXPECTED_ISSUE_COUNTS = {"missing": 224, "unresolved": 32}
EXPECTED_CARD_LINKED_PRESENT = 646
PRESENCE_REASON = "linked_by_unique_source_card_and_phone"

OUTPUT_FIELDS = [
    "category",
    "source_id",
    "source_name",
    "funnel",
    "phone",
    "assigned_phone",
    "source_all_phones",
    "photo_file",
    "fitbase_id",
    "fitbase_url",
    "reason",
    "match_method",
]


def main() -> None:
    with INPUT.open("r", newline="", encoding="utf-8-sig") as source:
        rows = list(csv.DictReader(source))

    category_counts = Counter(row.get("category", "") for row in rows)
    if category_counts["missing"] != EXPECTED_ISSUE_COUNTS["missing"]:
        raise ValueError(f"Expected 224 missing rows; found {category_counts['missing']}")
    if category_counts["unresolved"] != EXPECTED_ISSUE_COUNTS["unresolved"]:
        raise ValueError(
            f"Expected 32 unresolved rows; found {category_counts['unresolved']}"
        )

    card_linked_present = [
        row
        for row in rows
        if row.get("category") == "present" and row.get("reason") == PRESENCE_REASON
    ]
    if len(card_linked_present) != EXPECTED_CARD_LINKED_PRESENT:
        raise ValueError(
            "Expected 646 present records linked by unique source card and phone; "
            f"found {len(card_linked_present)}"
        )

    issues = [row for row in rows if row.get("category") in ISSUE_CATEGORIES]
    issue_counts = Counter(row["category"] for row in issues)
    source_ids = [row.get("source_id", "") for row in issues]
    confirmed_present_source_ids = {row.get("source_id", "") for row in card_linked_present}
    issue_present_overlap = confirmed_present_source_ids.intersection(source_ids)
    if len(issues) != 256:
        raise ValueError(f"Expected exactly 256 issues; found {len(issues)}")
    if len(source_ids) != len(set(source_ids)):
        raise ValueError("Issue list contains duplicate source IDs")
    if any(not source_id for source_id in source_ids):
        raise ValueError("Issue list contains an empty source ID")
    if any(row.get("category") == "present" for row in issues):
        raise ValueError("Present records must not be included in the issue list")
    if issue_present_overlap:
        raise ValueError(
            "Confirmed-present source IDs must be excluded: "
            + ", ".join(sorted(issue_present_overlap))
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", newline="", encoding="utf-8-sig") as target:
        writer = csv.DictWriter(target, fieldnames=OUTPUT_FIELDS, extrasaction="ignore")
        writer.writeheader()
        for row in issues:
            writer.writerow(
                {
                    "category": row.get("category", ""),
                    "source_id": row.get("source_id", ""),
                    "source_name": row.get("source_name", ""),
                    "funnel": row.get("funnel", ""),
                    "phone": row.get("source_phone", ""),
                    "assigned_phone": row.get("assigned_phone", ""),
                    "source_all_phones": row.get("source_all_phones", ""),
                    "photo_file": row.get("photo_file", ""),
                    "fitbase_id": row.get("fitbase_id", ""),
                    "fitbase_url": row.get("fitbase_url", ""),
                    "reason": row.get("reason", ""),
                    "match_method": row.get("match_method", ""),
                }
            )

    summary = {
        "input_file": str(INPUT.relative_to(ROOT)),
        "output_file": str(OUTPUT.relative_to(ROOT)),
        "input_rows": len(rows),
        "issue_rows": len(issues),
        "issue_counts": {
            "missing": issue_counts["missing"],
            "unresolved": issue_counts["unresolved"],
        },
        "unique_source_ids": len(set(source_ids)),
        "excluded_present_rows": category_counts["present"],
        "excluded_unique_card_phone_present_rows": len(card_linked_present),
        "excluded_unique_card_phone_present_source_id_overlap": len(issue_present_overlap),
    }
    SUMMARY.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
