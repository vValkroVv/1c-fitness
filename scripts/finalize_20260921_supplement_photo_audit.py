#!/usr/bin/env python3
"""Finalize the read-only audit of the 371-client photo supplement."""

from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "output/20260923_fitbase_photo_audit"
SUPPLEMENT = AUDIT / "supplement_371"
SOURCE_ZIP = ROOT / "output/20260921_phone_dedup_supplement_371/fitbase_client_photos_20260921.zip"

# These five borderline cases were reviewed against the original and downloaded
# images. The first, third and fifth are resizing/re-encoding; the fourth is a
# crop of the same portrait. Osipova's portrait is a different person.
REVIEWED = {
    "000025562": "same_photo_reencoded",
    "000041964": "wrong_person_photo",
    "000047117": "same_photo_resized",
    "000048569": "same_photo_cropped",
    "000049499": "same_photo_resized",
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path: Path, rows: list[dict[str, str]], fields: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    reconciliation = read_csv(SUPPLEMENT / "reconciliation.csv")
    comparisons = {row["source_id"]: row for row in read_csv(SUPPLEMENT / "image_comparison.csv")}
    if len(reconciliation) != 244 or len(comparisons) != 126:
        raise ValueError("Unexpected supplement reconciliation or comparison row count")
    rows: list[dict[str, str]] = []
    for row in reconciliation:
        result = dict(row)
        comparison = comparisons.get(row["source_id"])
        if row["category"] == "missing":
            outcome = "missing_photo"
        elif row["category"] == "unresolved":
            outcome = "identity_unresolved"
        elif comparison is None:
            raise ValueError(f"No comparison for {row['source_id']}")
        elif row["source_id"] in REVIEWED:
            outcome = REVIEWED[row["source_id"]]
        elif comparison["classification"] in ("similar", "exact"):
            outcome = "same_photo"
        else:
            raise ValueError(f"Unreviewed image result: {row['source_id']}")
        result["photo_outcome"] = outcome
        result["comparison_classification"] = comparison["classification"] if comparison else ""
        result["remote_sha256"] = comparison["remote_sha256"] if comparison else ""
        result["mae_rgb_255"] = comparison["mae_rgb_255"] if comparison else ""
        result["dhash_hamming_64"] = comparison["dhash_hamming_64"] if comparison else ""
        rows.append(result)
    if Counter(row["photo_outcome"] for row in rows)["wrong_person_photo"] != 1:
        raise ValueError("Wrong-person photo review missing")

    fields = list(rows[0])
    write_csv(SUPPLEMENT / "photo_results.csv", rows, fields)
    issues = [row for row in rows if row["photo_outcome"] in
              ("missing_photo", "wrong_person_photo", "identity_unresolved")]
    write_csv(SUPPLEMENT / "photo_discrepancies.csv", issues, fields)

    main_issues = read_csv(AUDIT / "photo_discrepancies.csv")
    combined_fields = ["delivery"] + list(main_issues[0])
    combined = [{"delivery": "main_20260921", **row} for row in main_issues]
    for row in issues:
        issue_type = "wrong_photo" if row["photo_outcome"] == "wrong_person_photo" else row["photo_outcome"]
        combined.append({
            "delivery": "phone_dedup_supplement_371",
            "source_id": row["source_id"],
            "source_name": row["source_name"],
            "source_phone": row["source_phones"].split(";")[0],
            "source_all_phones": row["source_phones"],
            "funnel": row["funnel"],
            "source_jpeg": row["photo_file"],
            "issue_type": issue_type,
            "priority": "high" if issue_type != "identity_unresolved" else "review",
            "action_required": (
                "Загрузить исходный JPEG в указанную карточку и проверить отображение."
                if issue_type == "missing_photo" else
                "Заменить чужое фото исходным JPEG и проверить отображение."
                if issue_type == "wrong_photo" else
                "Уточнить, какая из карточек соответствует исходному клиенту."
            ),
            "evidence_status": "confirmed_by_api_and_image_comparison" if issue_type == "wrong_photo"
            else "missing_confirmed_by_reconciliation" if issue_type == "missing_photo"
            else "identity_not_proven",
            "evidence_details": (
                "Фото другого человека; исходник и фото Fitbase просмотрены, UI подтвердил карточку и URL."
                if issue_type == "wrong_photo" else
                "В сопоставленной карточке поле фото пустое, исходный JPEG есть в дополнительном архиве."
                if issue_type == "missing_photo" else
                "Общий телефон, другая/пустая карточка или несовпадающее ФИО не позволяют доказать связь."
            ),
            "evidence_reference": "supplement_371/photo_results.csv",
            "reconciliation_category": row["category"],
            "fitbase_id": row["fitbase_id"],
            "fitbase_card_url": row["fitbase_url"],
            "fitbase_photo_url": row["photo_url"],
            "resolved_photo_url": "https://files.fitbase.io" + row["photo_url"] if row["photo_url"].startswith("/files/") else "",
            "photo_comparison_classification": row["comparison_classification"],
            "source_sha256": row["source_sha256"],
            "fitbase_photo_sha256": row["remote_sha256"],
            "remaining47_candidate_ids": row["exact_candidate_ids"] or row["same_name_candidate_ids"] or row["same_phone_candidate_ids"],
            "identity_unresolved_reason": "shared_phone_or_incomplete_identity" if issue_type == "identity_unresolved" else "",
        })
    write_csv(AUDIT / "photo_discrepancies_combined.csv", combined, combined_fields)
    summary = {
        "main_source_jpegs_in_scope": 34776,
        "supplement_clients": 371,
        "supplement_source_jpegs": len(rows),
        "supplement_without_source_photo": 127,
        "supplement_photo_outcomes": dict(Counter(row["photo_outcome"] for row in rows)),
        "supplement_issues": len(issues),
        "combined_source_jpegs_in_scope": 34776 + len(rows),
        "combined_issue_rows": len(combined),
        "combined_issue_types": dict(Counter(row["issue_type"] for row in combined)),
        "source_archive": str(SOURCE_ZIP.relative_to(ROOT)),
        "snapshot": "output/20260923_fitbase_photo_audit/api_snapshot.jsonl",
    }
    (SUPPLEMENT / "final_summary.json").write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
