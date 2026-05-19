#!/usr/bin/env python3
"""Compare Part 2 three-funnel counts with the external gym_sales.csv export."""

from __future__ import annotations

import argparse
import csv
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import date, datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RECLASSIFIER = ROOT / "scripts" / "16_reclassify_part2_from_csv.py"
FUNNEL_ORDER = ["Новые заявки", "Реактивация", "Действующие клиенты"]


def as_abs(path: str | Path) -> Path:
    p = Path(path)
    return p if p.is_absolute() else ROOT / p


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, object]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def parse_date(value: str) -> date | None:
    value = (value or "").strip()
    if not value:
        return None
    for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%d.%m.%Y %H:%M:%S", "%d.%m.%Y"):
        try:
            return datetime.strptime(value[:19], fmt).date()
        except ValueError:
            pass
    try:
        return datetime.fromisoformat(value).date()
    except ValueError:
        return None


def normalize_text(value: str) -> str:
    return (value or "").strip().casefold().replace("ё", "е")


def normalize_name(value: str) -> str:
    value = normalize_text(value)
    value = re.sub(r"[^0-9a-zа-я]+", " ", value)
    return re.sub(r"\s+", " ", value).strip()


def normalize_phones(value: str) -> set[str]:
    phones: set[str] = set()
    for part in re.split(r"[,;/]+", value or ""):
        digits = re.sub(r"\D", "", part)
        if len(digits) < 10:
            continue
        if len(digits) == 11 and digits[0] in {"7", "8"}:
            digits = digits[1:]
        elif len(digits) > 10:
            digits = digits[-10:]
        if len(digits) == 10:
            phones.add(digits)
    return phones


def client_key(row: dict[str, str]) -> str:
    phones = normalize_phones(row.get("phone", ""))
    name_norm = normalize_name(row.get("client_name", ""))
    birth_date = (row.get("birth_date") or "").strip()[:10]
    if phones:
        return f"phone_name:{sorted(phones)[0]}:{name_norm}"
    if name_norm and birth_date:
        return f"name_birth:{name_norm}:{birth_date}"
    if name_norm:
        return f"name:{name_norm}"
    return ""


def classify_product(product_name: str, max_duration_days: int | None) -> tuple[str, str]:
    """Mirror the SQL product-level rules for gym_sales product names."""
    name = normalize_text(product_name)
    max_duration = max_duration_days or 0
    has_full_keyword = any(token in name for token in ("абонемент", "мульти", "ультра", "членств"))
    has_trial_keyword = any(
        token in name
        for token in ("гост", "проб", "тест", "разов", "1 день", "один день", "7 дней", "недел")
    )
    has_full_exclude_keyword = any(token in name for token in ("переоформ", "перенос"))

    if has_full_keyword and max_duration >= 30 and not has_trial_keyword and not has_full_exclude_keyword:
        return "full_subscription", "full keyword + duration >= 30 + no trial/exclude keyword"
    if has_trial_keyword:
        return "trial_or_guest", "trial/guest/short keyword"
    if 1 <= max_duration <= 14:
        return "trial_or_guest", "short observed duration <= 14 days"
    return "other_sale", "not matched by full/trial rules in gym_sales"


def run_our_algorithm(args: argparse.Namespace, output_dir: Path) -> Path:
    stage_dir = output_dir / "our_algorithm" / "staging"
    reports_dir = output_dir / "our_algorithm" / "reports"
    cmd = [
        sys.executable,
        str(RECLASSIFIER),
        "--cutoff-date",
        args.cutoff_date,
        "--source-stage-dir",
        str(as_abs(args.source_stage_dir)),
        "--source-reports-dir",
        str(as_abs(args.source_reports_dir)),
        "--output-stage-dir",
        str(stage_dir),
        "--output-reports-dir",
        str(reports_dir),
        "--decisions",
        str(as_abs(args.decisions)),
    ]
    subprocess.run(cmd, cwd=ROOT, check=True)
    return stage_dir / "final_funnel_clients.csv"


def count_our_algorithm(final_csv: Path) -> Counter[str]:
    rows = read_csv(final_csv)
    return Counter(row.get("funnel", "") for row in rows)


def build_gym_sales_counts(gym_sales_csv: Path, cutoff: date, output_dir: Path) -> tuple[Counter[str], dict[str, object]]:
    rows = read_csv(gym_sales_csv)
    product_durations: defaultdict[str, list[int]] = defaultdict(list)
    sale_dates: list[date] = []

    for row in rows:
        sale_date = parse_date(row.get("sale_datetime", ""))
        valid_to = parse_date(row.get("valid_to", ""))
        row["_sale_date"] = sale_date.isoformat() if sale_date else ""
        row["_valid_to"] = valid_to.isoformat() if valid_to else ""
        if sale_date:
            sale_dates.append(sale_date)
        if sale_date and valid_to:
            product_durations[row.get("product_name", "")].append((valid_to - sale_date).days + 1)

    product_meta: dict[str, dict[str, object]] = {}
    for product_name in sorted({row.get("product_name", "") for row in rows}):
        durations = product_durations.get(product_name, [])
        max_duration = max(durations) if durations else None
        product_class, reason = classify_product(product_name, max_duration)
        product_meta[product_name] = {
            "product_name": product_name,
            "product_class": product_class,
            "classification_reason": reason,
            "max_duration_days": max_duration or "",
            "rows_total": 0,
            "rows_before_cutoff": 0,
            "clients_before_cutoff": 0,
        }

    clients: defaultdict[str, list[dict[str, object]]] = defaultdict(list)
    product_clients: defaultdict[str, set[str]] = defaultdict(set)
    class_rows = Counter()
    future_rows = 0
    missing_sale_date_rows = 0
    no_client_key_rows = 0

    for row in rows:
        product_name = row.get("product_name", "")
        product_meta[product_name]["rows_total"] = int(product_meta[product_name]["rows_total"]) + 1
        sale_date = parse_date(row.get("sale_datetime", ""))
        valid_to = parse_date(row.get("valid_to", ""))
        if sale_date is None:
            missing_sale_date_rows += 1
            continue
        if sale_date > cutoff:
            future_rows += 1
            continue
        key = client_key(row)
        if not key:
            no_client_key_rows += 1
            continue

        product_meta[product_name]["rows_before_cutoff"] = int(product_meta[product_name]["rows_before_cutoff"]) + 1
        product_clients[product_name].add(key)
        product_class = str(product_meta[product_name]["product_class"])
        class_rows[product_class] += 1
        clients[key].append(
            {
                "product_class": product_class,
                "sale_date": sale_date,
                "valid_to": valid_to,
            }
        )

    funnel_counts: Counter[str] = Counter()
    class_clients: defaultdict[str, set[str]] = defaultdict(set)
    for key, client_rows in clients.items():
        for row in client_rows:
            class_clients[str(row["product_class"])].add(key)
        full_rows = [row for row in client_rows if row["product_class"] == "full_subscription"]
        if any(row["valid_to"] and row["valid_to"] >= cutoff for row in full_rows):
            funnel_counts["Действующие клиенты"] += 1
        elif any(row["valid_to"] and row["valid_to"] < cutoff for row in full_rows):
            funnel_counts["Реактивация"] += 1
        else:
            funnel_counts["Новые заявки"] += 1

    product_rows = []
    for product_name, meta in product_meta.items():
        meta["clients_before_cutoff"] = len(product_clients.get(product_name, set()))
        product_rows.append(meta)
    product_rows.sort(
        key=lambda row: (
            str(row["product_class"]),
            -int(row["rows_before_cutoff"]),
            str(row["product_name"]),
        )
    )

    class_summary_rows = []
    for product_class in sorted(set(class_rows) | set(class_clients)):
        class_summary_rows.append(
            {
                "product_class": product_class,
                "rows_before_cutoff": class_rows[product_class],
                "clients_before_cutoff": len(class_clients[product_class]),
            }
        )

    write_csv(
        output_dir / "gym_sales_product_class_summary.csv",
        class_summary_rows,
        ["product_class", "rows_before_cutoff", "clients_before_cutoff"],
    )
    write_csv(
        output_dir / "gym_sales_product_classification.csv",
        product_rows,
        [
            "product_name",
            "product_class",
            "classification_reason",
            "max_duration_days",
            "rows_total",
            "rows_before_cutoff",
            "clients_before_cutoff",
        ],
    )

    metadata = {
        "gym_rows_total": len(rows),
        "gym_sale_min": min(sale_dates).isoformat() if sale_dates else "",
        "gym_sale_max": max(sale_dates).isoformat() if sale_dates else "",
        "gym_rows_after_cutoff": future_rows,
        "gym_rows_missing_sale_date": missing_sale_date_rows,
        "gym_rows_without_client_key": no_client_key_rows,
        "gym_clients_before_cutoff": len(clients),
        "gym_class_rows": dict(class_rows),
        "gym_product_class_count": dict(Counter(str(meta["product_class"]) for meta in product_meta.values())),
    }
    return funnel_counts, metadata


def write_report(
    report_path: Path,
    cutoff: str,
    output_dir: Path,
    our_counts: Counter[str],
    gym_counts: Counter[str],
    gym_metadata: dict[str, object],
) -> None:
    comparison_rows = build_comparison_rows(our_counts, gym_counts)
    lines = [
        "# Part 2 Gym Sales Mid-November Comparison",
        "",
        f"Run date: `{datetime.now().isoformat(timespec='seconds')}`",
        f"Cutoff date: `{cutoff}`",
        "",
        "The Part 2 side was recalculated with the same SQL-free reclassifier that rebuilds the three funnels from exported 1C staging CSVs. The gym_sales side uses only `data/gym_sales.csv`: client identity is `phone + normalized name`, product class is derived from product name and the product-level max duration, and only counts are compared.",
        "",
        "## Funnel Counts",
        "",
        "| Funnel | Part 2 algorithm | gym_sales.csv | Delta Part 2 - gym_sales |",
        "|---|---:|---:|---:|",
    ]
    for row in comparison_rows:
        lines.append(
            f"| {row['funnel']} | {row['part2_algorithm_count']} | {row['gym_sales_count']} | {row['delta_part2_minus_gym_sales']} |"
        )
    lines.extend(
        [
            "",
            "## gym_sales Coverage",
            "",
            f"- sale date range in CSV: `{gym_metadata['gym_sale_min']}` to `{gym_metadata['gym_sale_max']}`",
            f"- total rows in CSV: `{gym_metadata['gym_rows_total']}`",
            f"- rows after cutoff and ignored: `{gym_metadata['gym_rows_after_cutoff']}`",
            f"- unique clients before cutoff: `{gym_metadata['gym_clients_before_cutoff']}`",
            f"- rows without sale date: `{gym_metadata['gym_rows_missing_sale_date']}`",
            f"- rows without client key: `{gym_metadata['gym_rows_without_client_key']}`",
            "",
            "## Notes",
            "",
            "- `gym_sales.csv` is a sales export, not a full client directory. Because of that, it cannot reproduce the large `Новые заявки` population that exists in 1C without a full membership sale before the cutoff.",
            "- Active-client counts are close because both sources have explicit sale and `valid_to` dates for current memberships.",
            "- Product classification for `gym_sales.csv` intentionally keeps `...заморозки в подарок` as `full_subscription`, matching the current SQL rule where `замороз` is review-only, not an exclude keyword.",
            "",
            "## Written Files",
            "",
            f"- comparison counts: `{(output_dir / 'funnel_counts_comparison.csv').relative_to(ROOT)}`",
            f"- gym product class summary: `{(output_dir / 'gym_sales_product_class_summary.csv').relative_to(ROOT)}`",
            f"- gym product classification: `{(output_dir / 'gym_sales_product_classification.csv').relative_to(ROOT)}`",
            f"- Part 2 recalculated final stage: `{(output_dir / 'our_algorithm' / 'staging' / 'final_funnel_clients.csv').relative_to(ROOT)}`",
        ]
    )
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def build_comparison_rows(our_counts: Counter[str], gym_counts: Counter[str]) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for funnel in FUNNEL_ORDER:
        rows.append(
            {
                "funnel": funnel,
                "part2_algorithm_count": our_counts[funnel],
                "gym_sales_count": gym_counts[funnel],
                "delta_part2_minus_gym_sales": our_counts[funnel] - gym_counts[funnel],
            }
        )
    rows.append(
        {
            "funnel": "TOTAL",
            "part2_algorithm_count": sum(our_counts.values()),
            "gym_sales_count": sum(gym_counts.values()),
            "delta_part2_minus_gym_sales": sum(our_counts.values()) - sum(gym_counts.values()),
        }
    )
    return rows


def compare(args: argparse.Namespace) -> None:
    cutoff = date.fromisoformat(args.cutoff_date)
    output_dir = as_abs(args.output_dir)
    report_path = as_abs(args.report)
    final_csv = run_our_algorithm(args, output_dir)
    our_counts = count_our_algorithm(final_csv)
    gym_counts, gym_metadata = build_gym_sales_counts(as_abs(args.gym_sales_csv), cutoff, output_dir)
    comparison_rows = build_comparison_rows(our_counts, gym_counts)

    write_csv(
        output_dir / "funnel_counts_comparison.csv",
        comparison_rows,
        ["funnel", "part2_algorithm_count", "gym_sales_count", "delta_part2_minus_gym_sales"],
    )
    write_csv(
        output_dir / "part2_algorithm_funnel_counts.csv",
        [{"funnel": funnel, "count": our_counts[funnel]} for funnel in FUNNEL_ORDER],
        ["funnel", "count"],
    )
    write_csv(
        output_dir / "gym_sales_funnel_counts.csv",
        [{"funnel": funnel, "count": gym_counts[funnel]} for funnel in FUNNEL_ORDER],
        ["funnel", "count"],
    )
    write_report(report_path, args.cutoff_date, output_dir, our_counts, gym_counts, gym_metadata)

    print(f"cutoff_date={args.cutoff_date}")
    for row in comparison_rows:
        print(
            f"{row['funnel']}: part2={row['part2_algorithm_count']} "
            f"gym_sales={row['gym_sales_count']} "
            f"delta={row['delta_part2_minus_gym_sales']}"
        )
    print(f"report={report_path.relative_to(ROOT)}")
    print(f"output_dir={output_dir.relative_to(ROOT)}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cutoff-date", default="2025-11-15")
    parser.add_argument("--gym-sales-csv", default="data/gym_sales.csv")
    parser.add_argument("--source-stage-dir", default="output/part2_20260429/staging")
    parser.add_argument("--source-reports-dir", default="output/part2_20260429/reports")
    parser.add_argument("--decisions", default="config/product_reclassification_decisions.csv")
    parser.add_argument("--output-dir", default="output/part2_gym_sales_compare_20251115")
    parser.add_argument("--report", default="docs/part2_16_gym_sales_mid_november_compare.md")
    return parser.parse_args()


def main() -> None:
    compare(parse_args())


if __name__ == "__main__":
    main()
