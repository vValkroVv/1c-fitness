#!/usr/bin/env python3
"""Read-only review of missing client photos on other same-phone Fitbase cards."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import time
from collections import Counter
from pathlib import Path
from urllib.parse import urlsplit
from zipfile import ZipFile

import cv2
import numpy as np
import requests
from PIL import Image, ImageChops, ImageOps, ImageStat

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "output/20260923_fitbase_photo_audit"
ZIP = ROOT / "output/20260921_fitbase_for_customer/fitbase_client_photos_20260921.zip"
PREFIX = "fitbase_client_photos_20260921/photos/"


def sha(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def open_image(blob: bytes) -> Image.Image:
    with Image.open(io.BytesIO(blob)) as source:
        source.load()
        return ImageOps.exif_transpose(source).convert("RGB")


def normalized_error(a: Image.Image, b: Image.Image) -> float:
    a = a.resize((256, 192), Image.Resampling.LANCZOS)
    b = b.resize((256, 192), Image.Resampling.LANCZOS)
    return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean) / 3


def sift_evidence(a: Image.Image, b: Image.Image) -> dict:
    """Confirm shared scene even when Fitbase has cropped or resized it."""
    result = {"good_matches": 0, "inliers": 0, "inlier_ratio": 0.0,
              "source_span": 0.0, "remote_span": 0.0, "median_error_px": ""}
    detector = cv2.SIFT_create(nfeatures=2500)
    images = [cv2.cvtColor(np.asarray(im), cv2.COLOR_RGB2GRAY) for im in (a, b)]
    (ak, ad), (bk, bd) = [detector.detectAndCompute(im, None) for im in images]
    if ad is None or bd is None or len(ad) < 2 or len(bd) < 2:
        return result
    good = [m for m, n in cv2.BFMatcher(cv2.NORM_L2).knnMatch(ad, bd, k=2)
            if m.distance < 0.72 * n.distance]
    result["good_matches"] = len(good)
    if len(good) < 4:
        return result
    src = np.float32([ak[m.queryIdx].pt for m in good])
    dst = np.float32([bk[m.trainIdx].pt for m in good])
    homography, mask = cv2.findHomography(src, dst, cv2.RANSAC, 3.0,
                                          maxIters=3000, confidence=0.999)
    if homography is None or mask is None:
        return result
    selected = mask.ravel().astype(bool)
    count = int(selected.sum())
    result["inliers"] = count
    result["inlier_ratio"] = round(count / len(good), 4)
    if count < 4:
        return result
    src, dst = src[selected], dst[selected]
    ah, aw = images[0].shape
    bh, bw = images[1].shape
    result["source_span"] = round(min(float(np.ptp(src[:, 0])) / aw,
                                      float(np.ptp(src[:, 1])) / ah), 4)
    result["remote_span"] = round(min(float(np.ptp(dst[:, 0])) / bw,
                                      float(np.ptp(dst[:, 1])) / bh), 4)
    projected = cv2.perspectiveTransform(src.reshape(-1, 1, 2), homography)[:, 0, :]
    result["median_error_px"] = round(float(np.median(np.linalg.norm(projected - dst, axis=1))), 3)
    return result


def download(path: str, cache: Path, session: requests.Session) -> tuple[bytes, str]:
    parsed = urlsplit(path)
    if parsed.scheme or parsed.netloc or parsed.query or not parsed.path.startswith("/files/"):
        raise ValueError(f"Unexpected photo path: {path!r}")
    cache_file = cache / (sha(path.encode()) + ".jpg")
    if cache_file.is_file():
        return cache_file.read_bytes(), "cache"
    for attempt in range(3):
        try:
            response = session.get("https://files.fitbase.io" + path, timeout=30)
            response.raise_for_status()
            if len(response.content) > 25 * 1024 * 1024:
                raise ValueError("Remote image exceeds 25 MiB")
            open_image(response.content)
            cache_file.write_bytes(response.content)
            return response.content, "GET"
        except (requests.RequestException, OSError) as exc:
            if attempt == 2:
                raise RuntimeError(str(exc)) from exc
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reconciliation", type=Path, default=AUDIT / "reconciliation_complete.csv")
    parser.add_argument("--snapshot", type=Path, default=AUDIT / "api_snapshot.jsonl")
    parser.add_argument("--source-zip", type=Path, default=ZIP)
    parser.add_argument("--visual-verdicts", type=Path, default=AUDIT / "wrong_card_visual_verdicts.csv")
    parser.add_argument("--output-dir", type=Path, default=AUDIT)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)
    cache = args.output_dir / "wrong_card_photo_cache"
    cache.mkdir(exist_ok=True)
    with args.reconciliation.open(encoding="utf-8-sig", newline="") as handle:
        missing = [r for r in csv.DictReader(handle) if r["category"] == "missing"]
    if len(missing) != 224 or len({r["source_id"] for r in missing}) != 224:
        raise ValueError("Expected 224 unique missing clients in reconciliation_complete.csv")
    needed = {int(cid) for row in missing for cid in row["same_phone_other_name_ids"].split(";") if cid}
    cards = {}
    with args.snapshot.open(encoding="utf-8") as handle:
        for line in handle:
            obj = json.loads(line)
            if obj["id"] in needed:
                if obj["id"] in cards:
                    raise ValueError(f"Duplicate Fitbase ID {obj['id']}")
                cards[obj["id"]] = obj
    if set(cards) != needed:
        raise ValueError(f"Snapshot lacks {len(needed - set(cards))} candidate IDs")
    session = requests.Session()
    session.headers.update({"User-Agent": "Mozilla/5.0", "Accept": "image/*"})
    results = []
    remote_cache = {}
    with ZipFile(args.source_zip) as archive:
        for source in missing:
            ids = [int(x) for x in source["same_phone_other_name_ids"].split(";") if x]
            for cid in ids or [None]:
                card = cards.get(cid) if cid is not None else None
                path = card.get("photo") if card else None
                row = {"source_id": source["source_id"], "source_name": source["source_name"],
                       "missing_fitbase_id": source["fitbase_id"], "source_photo_file": source["photo_file"],
                       "other_fitbase_id": cid or "", "other_name": " ".join(str(card.get(k) or "").strip() for k in ("surname", "name", "patronymic")).strip() if card else "",
                       "other_photo_url": path or "", "source_sha256": "", "remote_sha256": "",
                       "source_size": "", "remote_size": "", "normalized_mae": "",
                       "good_matches": "", "inliers": "", "inlier_ratio": "",
                       "source_span": "", "remote_span": "", "median_error_px": "",
                       "retrieval": "", "visual_verdict": "", "visual_note": "",
                       "decision": "no_other_card" if cid is None else "other_card_has_no_photo",
                       "error": ""}
                if path:
                    try:
                        entry = PREFIX + source["photo_file"]
                        source_blob = archive.read(entry)
                        row["source_sha256"] = sha(source_blob)
                        if path not in remote_cache:
                            remote_cache[path] = download(path, cache, session)
                        remote_blob, retrieval = remote_cache[path]
                        row["remote_sha256"] = sha(remote_blob)
                        row["retrieval"] = retrieval
                        a, b = open_image(source_blob), open_image(remote_blob)
                        row["source_size"] = f"{a.width}x{a.height}"
                        row["remote_size"] = f"{b.width}x{b.height}"
                        mae = normalized_error(a, b)
                        row["normalized_mae"] = round(mae, 3)
                        row.update(sift_evidence(a, b))
                        geometric = (row["inliers"] >= 30 and row["inlier_ratio"] >= .75
                                     and row["source_span"] >= .15 and row["remote_span"] >= .15
                                     and row["median_error_px"] != "" and row["median_error_px"] <= 2)
                        if row["source_sha256"] == row["remote_sha256"]:
                            row["decision"] = "confirmed_wrong_card_photo_exact"
                        elif mae <= 3 and a.width * b.height == b.width * a.height:
                            row["decision"] = "confirmed_wrong_card_photo_resize"
                        elif geometric:
                            # Gym walls and posters can produce strong SIFT matches
                            # across portraits of different people.
                            row["decision"] = "scene_overlap_requires_visual_review"
                        else:
                            row["decision"] = "photo_not_confirmed_as_source"
                    except (KeyError, OSError, ValueError, RuntimeError, cv2.error) as exc:
                        row["decision"] = "comparison_error"
                        row["error"] = f"{type(exc).__name__}: {exc}"
                results.append(row)
    expected_pairs = sum(max(1, len([x for x in r["same_phone_other_name_ids"].split(";") if x])) for r in missing)
    if len(results) != expected_pairs or {r["source_id"] for r in results} != {r["source_id"] for r in missing}:
        raise AssertionError("Incomplete row coverage")
    with args.visual_verdicts.open(encoding="utf-8-sig", newline="") as handle:
        verdict_rows = list(csv.DictReader(handle))
    verdicts = {(r["source_id"], r["other_fitbase_id"]): r for r in verdict_rows}
    photographed_keys = {(r["source_id"], str(r["other_fitbase_id"]))
                         for r in results if r["other_photo_url"]}
    if len(verdicts) != len(verdict_rows) or set(verdicts) != photographed_keys:
        raise ValueError("Visual verdicts must cover each photographed pair exactly once")
    for row in results:
        if not row["other_photo_url"]:
            continue
        verdict = verdicts[(row["source_id"], str(row["other_fitbase_id"]))]
        if (verdict["source_sha256"] != row["source_sha256"]
                or verdict["remote_sha256"] != row["remote_sha256"]):
            raise ValueError(f"Image hash changed for source {row['source_id']}; repeat visual review")
        row["visual_verdict"] = verdict["visual_verdict"]
        row["visual_note"] = verdict["visual_note"]
        if verdict["visual_verdict"] == "different_people":
            if row["decision"].startswith("confirmed_wrong_card_photo"):
                raise ValueError(f"Pixel match conflicts with visual verdict for {row['source_id']}")
            row["decision"] = "visually_different_people"
        elif verdict["visual_verdict"] == "same_person_same_photo":
            if row["decision"] == "scene_overlap_requires_visual_review":
                row["decision"] = "confirmed_wrong_card_photo_crop"
        else:
            raise ValueError(f"Unexpected visual verdict: {verdict['visual_verdict']}")
    fields = list(results[0])
    target = args.output_dir / "wrong_card_photo_review.csv"
    with target.open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(results)
    counts = Counter(r["decision"] for r in results)
    confirmed = [r for r in results if r["decision"].startswith("confirmed_wrong_card_photo")]
    photographed = sum(bool(r["other_photo_url"]) for r in results)
    lines = ["# Проверка фото на других карточках с тем же телефоном", "",
             f"Исходные данные: `{args.reconciliation}`, `{args.snapshot}`, `{args.source_zip}`. "
             "Фото чужих карточек получены только через GET `files.fitbase.io` и сохранены в `wrong_card_photo_cache/`.", "",
             f"Покрытие: {len(missing)} клиентов без фото, {len(needed)} уникальных других карточек, "
             f"{len(results)} пар с учётом строк без кандидата. Из них {photographed} пар с фото; "
             f"ошибок сравнения: {counts['comparison_error']}.", "",
             f"**Подтверждённых ошибочных прикреплений: {len(confirmed)}.**", "",
             "Совпадение телефона само по себе не подтверждает ошибку. Подтверждение основано на одинаковом SHA-256, "
             "очень малой пиксельной ошибке при сохранении пропорций или SIFT-сопоставлении с визуальным подтверждением. "
             "Хеши изображений привязаны к ручным вердиктам в `wrong_card_visual_verdicts.csv`.", "",
             "Все 17 пар с фото просмотрены визуально: в каждом случае на снимках разные люди. "
             "Для пары 000022006 / 129131 алгоритм сопоставил общий фон (плакаты спортзала), "
             "но портреты относятся к разным людям.", ""]
    if confirmed:
        lines += ["| Исходный ID | Чужая карточка Fitbase | Основание |", "| --- | ---: | --- |"]
        lines += [f"| {r['source_id']} | {r['other_fitbase_id']} | {r['decision']} |" for r in confirmed]
        lines.append("")
    lines += ["Все пары и численные признаки приведены в `wrong_card_photo_review.csv`.", "",
              "Неподтверждённые пары означают лишь отсутствие доказанного совпадения в этих двух файлах; "
              "они не доказывают, что исходное фото не находится где-либо ещё."]
    (args.output_dir / "wrong_card_photo_review.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"missing": len(missing), "candidate_ids": len(needed), "pairs": len(results),
                      "photographed_pairs": photographed, "decisions": counts}, ensure_ascii=False, default=dict))


if __name__ == "__main__":
    main()
