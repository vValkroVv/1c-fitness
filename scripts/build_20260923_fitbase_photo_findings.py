#!/usr/bin/env python3
"""Build the final offline Fitbase photo findings and crop inventory."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_AUDIT = ROOT / "output/20260923_fitbase_photo_audit"
DEFAULT_OUTPUT = DEFAULT_AUDIT
DEFAULT_MANIFEST = ROOT / "output/20260922_fitbase_live_audit/photo_manifest.csv"
DEFAULT_COHORT = ROOT / "output/20260922_fitbase_live_audit/blank_client_links/cohort.json"

EXPECTED_RECONCILIATION = {"present": 34_520, "missing": 224, "unresolved": 32}
EXPECTED_COMPARISONS = {"similar": 34_518, "different": 1, "download_error": 1}
EXPECTED_ISSUE_COUNTS = {
    "missing_photo": 224,
    "wrong_photo": 1,
    "broken_photo_url": 1,
    "severe_crop": 2,
    "identity_unresolved": 32,
}
EXPECTED_WRONG_PHOTO_ID = "000065590"
EXPECTED_BROKEN_LINK_ID = "000067760"
EXPECTED_SEVERE_CROP_IDS = {"000024568", "000028166"}

ISSUE_ORDER = {name: index for index, name in enumerate(EXPECTED_ISSUE_COUNTS, 1)}
DISCREPANCY_FIELDS = [
    "source_id", "source_name", "source_phone", "source_all_phones", "funnel",
    "source_jpeg", "issue_type", "priority", "action_required", "evidence_status",
    "evidence_details", "evidence_reference", "reconciliation_category", "fitbase_id",
    "fitbase_card_url", "fitbase_photo_url", "resolved_photo_url",
    "photo_comparison_classification", "download_status", "error_type", "error_detail",
    "source_sha256", "fitbase_photo_sha256", "source_dimensions", "fitbase_dimensions",
    "crop_source_area_retained", "crop_quality_review", "crop_review_photo_path",
    "remaining47_review_cause", "remaining47_candidate_ids", "identity_unresolved_reason",
]
CROP_FIELDS = [
    "source_id", "source_name", "source_phone", "source_all_phones", "funnel",
    "source_jpeg", "fitbase_id", "fitbase_card_url", "fitbase_photo_url",
    "resolved_photo_url", "crop_class", "severity", "evidence_status", "evidence_details",
    "raw_classification", "decision", "comparison_classification", "same_aspect_ratio",
    "source_width", "source_height", "fitbase_width", "fitbase_height",
    "good_matches", "inliers", "inlier_ratio", "source_axis_span", "remote_axis_span",
    "median_reprojection_px", "source_area_retained", "crop_quality_review",
    "review_photo_path", "crop_evidence_path", "source_sha256", "fitbase_photo_sha256",
]


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        reader = csv.DictReader(stream)
        if not reader.fieldnames:
            raise ValueError(f"{path}: missing CSV header")
        rows = list(reader)
        if any(None in row for row in rows):
            raise ValueError(f"{path}: row has extra fields")
        return rows


def write_csv(path: Path, rows: list[dict[str, Any]], fields: list[str]) -> None:
    with path.open("w", encoding="utf-8-sig", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fields, extrasaction="raise")
        writer.writeheader()
        writer.writerows(rows)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def by_unique_source(rows: list[dict[str, str]], label: str) -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for row in rows:
        source_id = row.get("source_id", "").strip()
        if not source_id:
            raise ValueError(f"{label}: blank source_id")
        if source_id in result:
            raise ValueError(f"{label}: duplicate source_id {source_id}")
        result[source_id] = row
    return result


def read_excluded_source_ids(manifest_path: Path, cohort_path: Path) -> set[str]:
    manifest_rows = read_csv(manifest_path)
    manifest_ids = {row["client_id"].strip() for row in manifest_rows}
    if len(manifest_rows) != 35_422 or len(manifest_ids) != 35_422:
        raise ValueError(
            f"Source photo manifest must contain 35,422 unique IDs; "
            f"got {len(manifest_rows)} rows / {len(manifest_ids)} IDs"
        )
    cohort = json.loads(cohort_path.read_text(encoding="utf-8"))
    if not isinstance(cohort, list):
        raise ValueError(f"{cohort_path}: expected a JSON array")
    no_membership_ids = {
        str(row["client_id"]).strip()
        for row in cohort
        if isinstance(row, dict) and not row.get("source_memberships")
    }
    if len(no_membership_ids) != 717:
        raise ValueError(f"Expected 717 excluded cohort IDs, got {len(no_membership_ids)}")
    excluded_manifest_ids = no_membership_ids & manifest_ids
    if len(excluded_manifest_ids) != 646:
        raise ValueError(
            f"Expected 646 excluded source IDs in photo manifest, got {len(excluded_manifest_ids)}"
        )
    return excluded_manifest_ids


def dimensions(row: dict[str, str], width: str, height: str) -> str:
    if not row.get(width) or not row.get(height):
        return ""
    return f"{row[width]}x{row[height]}"


def issue_row(
    source: dict[str, str], issue_type: str, comparison: dict[str, str] | None = None,
    crop: dict[str, str] | None = None,
) -> dict[str, Any]:
    comparison = comparison or {}
    crop = crop or {}
    evidence_reference = comparison.get("issue_evidence_path", "")
    issue_detail = ""
    evidence_status = ""
    priority = "high"
    action = ""
    if issue_type == "missing_photo":
        evidence_status = "missing_confirmed_by_reconciliation"
        issue_detail = "В карточке совпавшего клиента поле фото пустое; исходный JPEG есть в поставке."
        evidence_reference = "reconciliation_complete.csv"
        action = "Загрузить исходный JPEG в указанную карточку и проверить отображение."
    elif issue_type == "wrong_photo":
        evidence_status = "wrong_photo_confirmed_by_byte_comparison_and_live_UI_review"
        issue_detail = "В карточке показан другой человек; это подтверждено сравнением JPEG и проверкой в UI."
        action = "Заменить фото исходным JPEG и проверить карточку."
    elif issue_type == "broken_photo_url":
        evidence_status = "photo_URL_returns_HTTP_404_and_live_UI_review_confirms_broken_image"
        issue_detail = "Ссылка на фото возвращает HTTP 404; в UI видно битое изображение."
        evidence_reference = "; ".join(filter(None, [evidence_reference, "ui_broken_photo.json"]))
        action = "Восстановить файл или загрузить исходный JPEG и проверить отображение."
    elif issue_type == "severe_crop":
        retained = crop.get("source_area_retained", "")
        evidence_status = "same_image_confirmed; severe_crop_flagged_for_manual_correction"
        issue_detail = (
            f"Это исходное фото, но в аватаре осталось только {retained} площади кадра; "
            "при проверке UI лицо сильно обрезано."
        )
        evidence_reference = "; ".join(filter(None, [evidence_reference, crop.get("review_photo_path", "")]))
        action = "Исправить кадрирование или повторно загрузить фото так, чтобы лицо было видно."
    elif issue_type == "identity_unresolved":
        priority = "blocked_identity_review"
        evidence_status = "identity_unresolved_after_manual_evidence_review"
        issue_detail = "Не удалось надёжно связать исходного клиента с одной карточкой Fitbase."
        evidence_reference = "remaining47_review.csv; reconciliation_complete.csv"
        action = "Установить нужную карточку по независимым данным до изменения фото."
    else:
        raise ValueError(f"Unsupported issue type: {issue_type}")

    return {
        "source_id": source["source_id"],
        "source_name": source.get("source_name", ""),
        "source_phone": source.get("source_phone", ""),
        "source_all_phones": source.get("source_all_phones", ""),
        "funnel": source.get("funnel", ""),
        "source_jpeg": source.get("photo_file", ""),
        "issue_type": issue_type,
        "priority": priority,
        "action_required": action,
        "evidence_status": evidence_status,
        "evidence_details": issue_detail,
        "evidence_reference": evidence_reference,
        "reconciliation_category": source.get("category", ""),
        "fitbase_id": source.get("fitbase_id", ""),
        "fitbase_card_url": source.get("fitbase_url", ""),
        "fitbase_photo_url": source.get("photo_url", ""),
        "resolved_photo_url": comparison.get("resolved_photo_url", ""),
        "photo_comparison_classification": comparison.get("final_classification", ""),
        "download_status": comparison.get("download_status", ""),
        "error_type": comparison.get("error_type", ""),
        "error_detail": comparison.get("error_detail", ""),
        "source_sha256": comparison.get("source_sha256", ""),
        "fitbase_photo_sha256": comparison.get("remote_sha256", ""),
        "source_dimensions": dimensions(comparison, "source_width", "source_height"),
        "fitbase_dimensions": dimensions(comparison, "remote_width", "remote_height"),
        "crop_source_area_retained": crop.get("source_area_retained", ""),
        "crop_quality_review": crop.get("crop_quality_review", ""),
        "crop_review_photo_path": crop.get("review_photo_path", ""),
        "remaining47_review_cause": source.get("remaining47_review_cause", ""),
        "remaining47_candidate_ids": source.get("remaining47_candidate_ids", ""),
        "identity_unresolved_reason": source.get("remaining47_unresolved_reason", ""),
    }


def build(args: argparse.Namespace) -> dict[str, Any]:
    reconciliation_path = args.audit_dir / "reconciliation_complete.csv"
    comparison_path = args.audit_dir / "image_comparison_final_34520.csv"
    crop_path = args.audit_dir / "crop_match_review_final.csv"
    summary_path = args.audit_dir / "image_comparison_final_34520_summary.json"
    reconciliation = by_unique_source(read_csv(reconciliation_path), "reconciliation")
    comparisons = by_unique_source(read_csv(comparison_path), "image comparison")
    crops = by_unique_source(read_csv(crop_path), "crop review")

    reconciliation_counts = Counter(row["category"] for row in reconciliation.values())
    if dict(reconciliation_counts) != EXPECTED_RECONCILIATION:
        raise ValueError(f"Unexpected final reconciliation categories: {dict(reconciliation_counts)}")
    present_ids = {source_id for source_id, row in reconciliation.items() if row["category"] == "present"}
    if set(comparisons) != present_ids:
        raise ValueError(
            f"Image comparison must cover all and only present rows; "
            f"missing={len(present_ids - set(comparisons))}, extra={len(set(comparisons) - present_ids)}"
        )
    comparison_counts = Counter(row.get("final_classification", "") for row in comparisons.values())
    if dict(comparison_counts) != EXPECTED_COMPARISONS:
        raise ValueError(f"Unexpected final image comparison classifications: {dict(comparison_counts)}")
    if any(row.get("final_classification") == "uncertain" for row in comparisons.values()):
        raise ValueError("Final image comparison contains uncertain rows")

    crop_confirmed = {
        source_id for source_id, row in comparisons.items()
        if row.get("crop_match_status") == "confirmed_same_crop"
    }
    if set(crops) != crop_confirmed or len(crops) != 164:
        raise ValueError(
            f"Crop review must match all 164 confirmed crop rows; "
            f"review={len(crops)}, comparison={len(crop_confirmed)}, "
            f"missing={len(crop_confirmed - set(crops))}, extra={len(set(crops) - crop_confirmed)}"
        )
    for source_id, crop in crops.items():
        if crop.get("decision") != "confirmed_same_crop":
            raise ValueError(f"{source_id}: crop review did not confirm same image")
        comparison = comparisons[source_id]
        source = reconciliation[source_id]
        if comparison.get("same_aspect_ratio", "").casefold() != "false":
            raise ValueError(f"{source_id}: confirmed crop does not have a changed aspect ratio")
        if crop.get("fitbase_id") != source.get("fitbase_id") or crop.get("photo_file") != source.get("photo_file"):
            raise ValueError(f"{source_id}: crop review client/source identity differs from reconciliation")
        if comparison.get("crop_match_status") != "confirmed_same_crop":
            raise ValueError(f"{source_id}: comparison does not confirm the crop")

    excluded_ids = read_excluded_source_ids(args.source_manifest, args.exclusion_cohort)
    target_ids = set(reconciliation)
    overlap = excluded_ids & target_ids
    if overlap:
        raise ValueError(f"Excluded source IDs appear in target reconciliation: {sorted(overlap)[:10]}")

    wrong_ids = {
        source_id for source_id, row in comparisons.items()
        if row.get("issue_status") == "wrong_photo"
    }
    broken_ids = {
        source_id for source_id, row in comparisons.items()
        if row.get("issue_status") == "broken_photo_url"
    }
    severe_crop_ids = {
        source_id for source_id, row in crops.items()
        if row.get("crop_quality_review") == "severe_crop_review"
    }
    if wrong_ids != {EXPECTED_WRONG_PHOTO_ID}:
        raise ValueError(f"Unexpected wrong-photo IDs: {sorted(wrong_ids)}")
    if broken_ids != {EXPECTED_BROKEN_LINK_ID}:
        raise ValueError(f"Unexpected broken-link IDs: {sorted(broken_ids)}")
    if severe_crop_ids != EXPECTED_SEVERE_CROP_IDS:
        raise ValueError(f"Unexpected severe-crop IDs: {sorted(severe_crop_ids)}")

    issue_rows: list[dict[str, Any]] = []
    for source_id, source in reconciliation.items():
        if source["category"] == "missing":
            if source.get("photo_url", "").strip():
                raise ValueError(f"{source_id}: category=missing but Fitbase photo URL is not empty")
            issue_rows.append(issue_row(source, "missing_photo"))
        elif source["category"] == "unresolved":
            if any(source.get(key, "").strip() for key in ("fitbase_id", "fitbase_url", "photo_url")):
                raise ValueError(f"{source_id}: unresolved identity has an assigned Fitbase client/photo")
            issue_rows.append(issue_row(source, "identity_unresolved"))

    for source_id in sorted(wrong_ids):
        row = comparisons[source_id]
        if row.get("final_classification") != "different":
            raise ValueError(f"{source_id}: wrong-photo status lacks a different-image classification")
        issue_rows.append(issue_row(reconciliation[source_id], "wrong_photo", row))
    for source_id in sorted(broken_ids):
        row = comparisons[source_id]
        if row.get("download_status") != "404":
            raise ValueError(f"{source_id}: broken-link status lacks HTTP 404 evidence")
        issue_rows.append(issue_row(reconciliation[source_id], "broken_photo_url", row))
    for source_id in sorted(severe_crop_ids):
        comparison = comparisons[source_id]
        crop = crops[source_id]
        if crop.get("crop_quality_review") != "severe_crop_review":
            raise ValueError(f"{source_id}: severe-crop row lacks crop review flag")
        issue_rows.append(issue_row(reconciliation[source_id], "severe_crop", comparison, crop))

    issue_rows.sort(key=lambda row: (ISSUE_ORDER[row["issue_type"]], row["source_id"]))
    issue_counts = Counter(row["issue_type"] for row in issue_rows)
    if dict(issue_counts) != EXPECTED_ISSUE_COUNTS:
        raise ValueError(f"Unexpected actionable finding counts: {dict(issue_counts)}")
    issue_ids = [row["source_id"] for row in issue_rows]
    if len(issue_rows) != 260 or len(set(issue_ids)) != 260:
        raise ValueError(f"Expected 260 unique actionable rows, got {len(issue_rows)} rows / {len(set(issue_ids))} IDs")
    if not set(issue_ids) <= target_ids:
        raise ValueError("At least one issue source ID is absent from the target reconciliation")
    if set(issue_ids) & excluded_ids:
        raise ValueError("At least one actionable issue is in the excluded 646 source IDs")

    crop_rows = []
    for source_id, crop in crops.items():
        source = reconciliation[source_id]
        comparison = comparisons[source_id]
        severity = "severe" if source_id in severe_crop_ids else "routine"
        crop_rows.append({
            "source_id": source_id,
            "source_name": source.get("source_name", ""),
            "source_phone": source.get("source_phone", ""),
            "source_all_phones": source.get("source_all_phones", ""),
            "funnel": source.get("funnel", ""),
            "source_jpeg": source.get("photo_file", ""),
            "fitbase_id": source.get("fitbase_id", ""),
            "fitbase_card_url": source.get("fitbase_url", ""),
            "fitbase_photo_url": source.get("photo_url", ""),
            "resolved_photo_url": comparison.get("resolved_photo_url", ""),
            "crop_class": "severe_crop" if severity == "severe" else "routine_crop",
            "severity": severity,
            "evidence_status": "same_image_confirmed_severe_crop" if severity == "severe" else "same_image_confirmed_routine_crop",
            "evidence_details": (
                f"Retains {crop.get('source_area_retained', '')} of the source image area; "
                + ("severe crop review required." if severity == "severe" else "routine aspect-ratio crop.")
            ),
            "raw_classification": crop.get("raw_classification", ""),
            "decision": crop.get("decision", ""),
            "comparison_classification": comparison.get("final_classification", ""),
            "same_aspect_ratio": comparison.get("same_aspect_ratio", ""),
            "source_width": comparison.get("source_width", ""),
            "source_height": comparison.get("source_height", ""),
            "fitbase_width": comparison.get("remote_width", ""),
            "fitbase_height": comparison.get("remote_height", ""),
            "good_matches": crop.get("good_matches", ""),
            "inliers": crop.get("inliers", ""),
            "inlier_ratio": crop.get("inlier_ratio", ""),
            "source_axis_span": crop.get("source_axis_span", ""),
            "remote_axis_span": crop.get("remote_axis_span", ""),
            "median_reprojection_px": crop.get("median_reprojection_px", ""),
            "source_area_retained": crop.get("source_area_retained", ""),
            "crop_quality_review": crop.get("crop_quality_review", ""),
            "review_photo_path": crop.get("review_photo_path", ""),
            "crop_evidence_path": comparison.get("issue_evidence_path", ""),
            "source_sha256": comparison.get("source_sha256", ""),
            "fitbase_photo_sha256": comparison.get("remote_sha256", ""),
        })
    crop_rows.sort(key=lambda row: row["source_id"])
    crop_counts = Counter(row["crop_class"] for row in crop_rows)
    if len(crop_rows) != 164 or dict(crop_counts) != {"routine_crop": 162, "severe_crop": 2}:
        raise ValueError(f"Unexpected crop inventory counts: {dict(crop_counts)}")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    discrepancies_output = args.output_dir / "photo_discrepancies.csv"
    crops_output = args.output_dir / "photo_crops_all.csv"
    summary_output = args.output_dir / "photo_discrepancies_summary.json"
    write_csv(discrepancies_output, issue_rows, DISCREPANCY_FIELDS)
    write_csv(crops_output, crop_rows, CROP_FIELDS)

    source_files = [reconciliation_path, comparison_path, crop_path, summary_path,
                    args.source_manifest, args.exclusion_cohort]
    summary = {
        "build": "build_20260923_fitbase_photo_findings.py",
        "scope": "offline findings only; no API requests or Fitbase mutations",
        "target_reconciliation_rows": len(reconciliation),
        "target_reconciliation_categories": dict(sorted(reconciliation_counts.items())),
        "present_rows_covered_by_image_comparison": len(comparisons),
        "image_comparison_final_classification": dict(sorted(comparison_counts.items())),
        "actionable_discrepancy_rows": len(issue_rows),
        "actionable_discrepancy_counts": dict(sorted(issue_counts.items())),
        "crop_inventory_rows": len(crop_rows),
        "crop_inventory_counts": dict(sorted(crop_counts.items())),
        "excluded_source_ids_in_manifest": len(excluded_ids),
        "excluded_source_ids_in_target": len(overlap),
        "actionable_source_ids_unique": len(set(issue_ids)),
        "all_issue_ids_in_target": set(issue_ids) <= target_ids,
        "crop_review_decisions": dict(sorted(Counter(r.get("decision", "") for r in crops.values()).items())),
        "inputs": {
            str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path): sha256_file(path)
            for path in source_files
        },
        "outputs": {
            "photo_discrepancies.csv": {
                "rows": len(issue_rows), "sha256": sha256_file(discrepancies_output),
            },
            "photo_crops_all.csv": {
                "rows": len(crop_rows), "sha256": sha256_file(crops_output),
            },
        },
    }
    summary_output.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--audit-dir", type=Path, default=DEFAULT_AUDIT)
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--source-manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--exclusion-cohort", type=Path, default=DEFAULT_COHORT)
    args = parser.parse_args()
    summary = build(args)
    print(json.dumps({
        "actionable_discrepancy_rows": summary["actionable_discrepancy_rows"],
        "actionable_discrepancy_counts": summary["actionable_discrepancy_counts"],
        "crop_inventory_rows": summary["crop_inventory_rows"],
        "crop_inventory_counts": summary["crop_inventory_counts"],
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
