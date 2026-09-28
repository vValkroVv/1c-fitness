#!/usr/bin/env python3
"""Offline geometric review of Fitbase photos whose aspect ratio changed.

Only a strong local-feature match confirms a shared crop. Failed matches stay
uncertain; a lack of SIFT features is not evidence that a photo changed.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path
from zipfile import ZipFile

try:
    import cv2
    import numpy as np
except ImportError as exc:
    raise SystemExit("Install opencv-python-headless (and its numpy dependency)") from exc


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "output/20260923_fitbase_photo_audit"
ZIP = ROOT / "output/20260921_fitbase_for_customer/fitbase_client_photos_20260921.zip"
ZIP_PREFIX = "fitbase_client_photos_20260921/photos/"
POSITIVE_IDS = ("000001799", "000004747", "000003654", "000003052",
                "000010034", "000024568")
MIN_INLIERS = 30
MIN_INLIER_RATIO = 0.75
MIN_AXIS_SPAN = 0.15
MAX_MEDIAN_REPROJECTION = 2.0
SEVERE_CROP_RETAINED_MAX = 0.60


def image(blob: bytes):
    return cv2.imdecode(np.frombuffer(blob, dtype=np.uint8), cv2.IMREAD_GRAYSCALE)


def features(gray, sift):
    if gray is None:
        return None
    points, descriptors = sift.detectAndCompute(gray, None)
    return gray.shape, points, descriptors


def compare(source, remote, matcher):
    result = {"good_matches": 0, "inliers": 0, "inlier_ratio": 0.0,
              "source_axis_span": 0.0, "remote_axis_span": 0.0,
              "median_reprojection_px": None, "source_area_retained": None,
              "crop_quality_review": "", "decision": "uncertain"}
    if source is None or remote is None:
        return result
    (sh, sw), sp, sd = source
    (rh, rw), rp, rd = remote
    if sd is None or rd is None or len(sd) < 2 or len(rd) < 2:
        return result
    pairs = matcher.knnMatch(sd, rd, k=2)
    good = [m for m, n in pairs if m.distance < 0.72 * n.distance]
    result["good_matches"] = len(good)
    if len(good) < MIN_INLIERS:
        return result
    src = np.float32([sp[m.queryIdx].pt for m in good])
    dst = np.float32([rp[m.trainIdx].pt for m in good])
    transform, mask = cv2.findHomography(
        src, dst, cv2.RANSAC, 3.0, maxIters=3000, confidence=0.999
    )
    if transform is None or mask is None:
        return result
    inlier = mask.ravel().astype(bool)
    count = int(inlier.sum())
    ratio = count / len(good)
    result["inliers"] = count
    result["inlier_ratio"] = round(ratio, 4)
    if count < 4:
        return result
    src_in = src[inlier]
    dst_in = dst[inlier]
    source_span = min(float(np.ptp(src_in[:, 0])) / sw,
                      float(np.ptp(src_in[:, 1])) / sh)
    remote_span = min(float(np.ptp(dst_in[:, 0])) / rw,
                      float(np.ptp(dst_in[:, 1])) / rh)
    projected = cv2.perspectiveTransform(src_in.reshape(-1, 1, 2), transform)
    error = float(np.median(np.linalg.norm(projected[:, 0, :] - dst_in, axis=1)))
    result.update(source_axis_span=round(source_span, 4),
                  remote_axis_span=round(remote_span, 4),
                  median_reprojection_px=round(error, 3))
    if (count >= MIN_INLIERS and ratio >= MIN_INLIER_RATIO
            and source_span >= MIN_AXIS_SPAN and remote_span >= MIN_AXIS_SPAN
            and error <= MAX_MEDIAN_REPROJECTION):
        # Project the remote viewport back onto the archived image. This
        # measures lost source area even when the remote image was resized.
        try:
            inverse = np.linalg.inv(transform)
            viewport = np.float32([[[0, 0]], [[rw, 0]], [[rw, rh]], [[0, rh]]])
            visible = cv2.perspectiveTransform(viewport, inverse)[:, 0, :]
            bounds = np.float32([[0, 0], [sw, 0], [sw, sh], [0, sh]])
            overlap, _ = cv2.intersectConvexConvex(bounds, visible)
        except (np.linalg.LinAlgError, cv2.error):
            return result
        retained = min(1.0, max(0.0, float(overlap) / (sw * sh)))
        result["decision"] = "confirmed_same_crop"
        result["source_area_retained"] = round(retained, 4)
        if retained < SEVERE_CROP_RETAINED_MAX:
            result["crop_quality_review"] = "severe_crop_review"
    return result


def remote_path(row, csv_path):
    raw = row.get("review_photo_path", "")
    if not raw:
        return None
    path = Path(raw)
    if path.is_absolute():
        return path
    # Comparator writes paths relative to the audit folder.
    return csv_path.parent / path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-csv", type=Path,
                        default=AUDIT / "image_comparison_progress.csv")
    parser.add_argument("--source-zip", type=Path, default=ZIP)
    parser.add_argument("--output-prefix", type=Path,
                        default=AUDIT / "crop_match_review")
    args = parser.parse_args()
    with args.input_csv.open(encoding="utf-8-sig", newline="") as handle:
        rows = list(csv.DictReader(handle))
    candidates = [r for r in rows if r.get("classification") in {"uncertain", "different"}
                  and r.get("same_aspect_ratio", "").lower() == "false"]
    sift = cv2.SIFT_create(nfeatures=2500)
    matcher = cv2.BFMatcher(cv2.NORM_L2)
    source_cache = {}
    remote_cache = {}
    output = []
    with ZipFile(args.source_zip) as archive:
        for row in candidates:
            item = {"source_id": row["source_id"], "fitbase_id": row["fitbase_id"],
                    "photo_file": row["photo_file"], "raw_classification": row["classification"],
                    "review_photo_path": row.get("review_photo_path", ""),
                    "status": "", "error": ""}
            entry = ZIP_PREFIX + row["photo_file"]
            path = remote_path(row, args.input_csv)
            if path is None or not path.is_file():
                item.update(status="remote_unavailable", error="saved remote JPEG missing",
                            decision="uncertain")
            else:
                try:
                    if entry not in source_cache:
                        source_cache[entry] = features(image(archive.read(entry)), sift)
                    if path not in remote_cache:
                        remote_cache[path] = features(image(path.read_bytes()), sift)
                    item.update(compare(source_cache[entry], remote_cache[path], matcher))
                    item["status"] = "compared"
                except (KeyError, OSError, cv2.error) as exc:
                    item.update(status="read_error", error=str(exc), decision="uncertain")
            output.append(item)
        by_id = {r["source_id"]: r for r in rows}
        controls = []
        for source_id in POSITIVE_IDS:
            row = by_id.get(source_id)
            if row is None:
                controls.append({"source_id": source_id, "kind": "positive", "status": "missing"})
                continue
            entry = ZIP_PREFIX + row["photo_file"]
            path = remote_path(row, args.input_csv)
            if path is None or not path.is_file():
                controls.append({"source_id": source_id, "kind": "positive", "status": "remote_unavailable"})
                continue
            if entry not in source_cache:
                source_cache[entry] = features(image(archive.read(entry)), sift)
            if path not in remote_cache:
                remote_cache[path] = features(image(path.read_bytes()), sift)
            for remote_id in POSITIVE_IDS:
                other = by_id.get(remote_id)
                other_path = remote_path(other, args.input_csv) if other else None
                if other_path is None or not other_path.is_file():
                    continue
                if other_path not in remote_cache:
                    remote_cache[other_path] = features(image(other_path.read_bytes()), sift)
                metric = compare(source_cache[entry], remote_cache[other_path], matcher)
                controls.append({"source_id": source_id, "remote_source_id": remote_id,
                                 "kind": "positive" if source_id == remote_id else "cross_pair_negative",
                                 "status": "compared", **metric})

    args.output_prefix.parent.mkdir(parents=True, exist_ok=True)
    csv_path = args.output_prefix.with_suffix(".csv")
    fields = ["source_id", "fitbase_id", "photo_file", "raw_classification",
              "review_photo_path", "status", "error", "good_matches", "inliers",
              "inlier_ratio", "source_axis_span", "remote_axis_span",
              "median_reprojection_px", "source_area_retained",
              "crop_quality_review", "decision"]
    with csv_path.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(output)
    positive = [c for c in controls if c.get("kind") == "positive" and c.get("status") == "compared"]
    negative = [c for c in controls if c.get("kind") == "cross_pair_negative"]
    tp = sum(c["decision"] == "confirmed_same_crop" for c in positive)
    fp = sum(c["decision"] == "confirmed_same_crop" for c in negative)
    confirmed = sum(r["decision"] == "confirmed_same_crop" for r in output)
    precision = f"{tp}/{tp + fp}" if tp + fp else "not estimable"
    report = {
        "input_csv": str(args.input_csv), "source_zip": str(args.source_zip),
        "input_rows": len(rows), "changed_aspect_candidates": len(candidates),
        "decisions": dict(Counter(r["decision"] for r in output)),
        "statuses": dict(Counter(r["status"] for r in output)),
        "thresholds": {"sift_features": 2500, "lowe_ratio": 0.72,
                       "ransac_reprojection_px": 3.0, "min_inliers": MIN_INLIERS,
                       "min_inlier_ratio": MIN_INLIER_RATIO,
                       "min_axis_span_each_image": MIN_AXIS_SPAN,
                       "max_median_reprojection_px": MAX_MEDIAN_REPROJECTION,
                       "severe_crop_retained_below": SEVERE_CROP_RETAINED_MAX},
        "controls": controls,
        "calibration": {"positive_detected": tp, "positive_compared": len(positive),
                        "negative_false_positive": fp, "negative_compared": len(negative),
                        "observed_precision": precision},
    }
    args.output_prefix.with_suffix(".json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    gaps = [r for r in output if r["status"] != "compared"]
    lines = ["# Offline crop match review", "",
             f"Input: `{args.input_csv}` ({len(rows)} rows).",
             f"Changed-aspect uncertain/raw different candidates: **{len(candidates)}**.",
             f"Confirmed same crop: **{confirmed}**; uncertain: **{len(output) - confirmed}**.",
             f"Severe crop quality review: **{sum(bool(r['crop_quality_review']) for r in output)}**.",
             "", "## Rule", "",
             "SIFT ratio 0.72 and homography RANSAC at 3 px. A confirmation requires "
             f"at least {MIN_INLIERS} inliers, ratio {MIN_INLIER_RATIO:.2f}, "
             f"inlier spans of {MIN_AXIS_SPAN:.0%} on both axes in both images, "
             f"and median reprojection error at most {MAX_MEDIAN_REPROJECTION:.1f} px. "
             "Every failed or unavailable match remains uncertain. A confirmed match with "
             f"less than {SEVERE_CROP_RETAINED_MAX:.0%} of the source area visible "
             "also receives a separate crop quality review flag. Geometric identity "
             "does not establish portrait usability.", "", "## Calibration", "",
             f"Visually confirmed crops detected: {tp}/{len(positive)}. "
             f"Cross-pair false confirmations: {fp}/{len(negative)}. "
             f"Observed precision on these controls: {precision}. "
             "This small control set does not establish population precision.", "",
             "| Source ID | Matches | Inliers | Ratio | Source retained | Quality flag | Decision |",
             "| --- | ---: | ---: | ---: | ---: | --- | --- |"]
    for c in positive:
        lines.append(f"| {c['source_id']} | {c['good_matches']} | "
                     f"{c['inliers']} | {c['inlier_ratio']:.3f} | "
                     f"{c['source_area_retained']} | {c['crop_quality_review']} | "
                     f"{c['decision']} |")
    lines += ["", "## Changed-aspect crops for review", "",
              "Every confirmed crop remains listed in the CSV. Quality flags indicate "
              "large image loss; a human should judge whether the portrait is usable.", "",
              "| Source ID | Fitbase ID | Source retained | Quality flag | Decision |",
              "| --- | --- | ---: | --- | --- |"]
    for r in output:
        lines.append(f"| {r['source_id']} | {r['fitbase_id']} | "
                     f"{r.get('source_area_retained', '') or ''} | "
                     f"{r['crop_quality_review']} | {r['decision']} |")
    lines += ["", "## Gaps", "",
              f"Unavailable or unreadable saved remote JPEGs: {len(gaps)}. "
              "Rerun with a later comparison CSV when downloads finish. "
              "Only changed-aspect uncertain/raw different rows are assessed; "
              "other rows retain their original classifications.", ""]
    args.output_prefix.with_suffix(".md").write_text("\n".join(lines), encoding="utf-8")
    print(f"{csv_path}: {confirmed}/{len(output)} confirmed; controls TP={tp}/{len(positive)}, FP={fp}/{len(negative)}")


if __name__ == "__main__":
    main()
