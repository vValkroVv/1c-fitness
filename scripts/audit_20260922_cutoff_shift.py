#!/usr/bin/env python3
"""Compare every saved import cell and source fact between September 21 and 22.

This audit reads saved artifacts only. It does not run production transformations
or edit either delivery. Detailed changes remain outside the customer package.
"""

import argparse
from collections import Counter
import csv
from datetime import datetime
import io
from itertools import zip_longest
import json
from pathlib import Path
import zipfile

import yaml

from audit_20260921_delivery import (
    Audit, csv_rows, digest, fact_fields, layout, normalized, workbook,
)

ROOT = Path(__file__).resolve().parents[1]
OLD_RUN, NEW_RUN = "20260921_final_v2", "20260922_final"
OLD_DAY, NEW_DAY = "2026-09-21", "2026-09-22"


def differences(before, after):
    return {
        key: {"before": normalized(before[key], key), "after": normalized(after[key], key)}
        for key in before
        if normalized(before[key], key) != normalized(after[key], key)
    }


def index_rows(rows, key):
    result = {}
    for row in rows:
        value = str(row[key] or "")
        if not value and key == "contract_id":
            value = "refuser:" + str(row["client_id"])
        if not value or value in result:
            raise ValueError(f"Missing or duplicate {key}: {value}")
        result[value] = row
    return result


def verify_payment_ties(audit, old_work, new_work, changes):
    """A TOP(1) tie may choose another ref only if every candidate value agrees."""
    ties = [row for row in changes if "matched_payment_ref" in row["changes"]]
    if not ties:
        return True
    refs = {ref for row in ties for ref in row["changes"]["matched_payment_ref"].values()}
    records = []
    for work in (old_work, new_work):
        with (work / "raw/staging/stg_sales_all.csv").open(encoding="utf-8-sig", newline="") as stream:
            rows = [row for row in csv.DictReader(stream) if row["sale_ref"] in refs]
        records.append(index_rows(rows, "sale_ref"))
    valid = records[0].keys() == records[1].keys() == refs
    evidence = []
    if valid:
        valid = records[0] == records[1]
        for row in ties:
            pair = row["changes"]["matched_payment_ref"]
            left, right = records[0][pair["before"]], records[1][pair["after"]]
            equal_values = {k: v for k, v in left.items() if k != "sale_ref"} == {k: v for k, v in right.items() if k != "sale_ref"}
            valid = valid and equal_values and left["sale_source"] == right["sale_source"] == "dbo._Document152"
            evidence.append({"document_number": row["document_number"], "references": pair,
                             "candidate_values_equal": equal_values, "candidate": {k: v for k, v in left.items() if k != "sale_ref"}})
    audit.check("Payment reference ties: both candidates exist unchanged in both snapshots and all their values agree", valid, cases=len(ties))
    audit.details["equivalent_payment_reference_ties"] = evidence
    return valid


def compare_facts(audit, old_work, new_work, kind, script, key):
    fields = fact_fields(ROOT / "end-to-end-xlsx/scripts" / script)
    counters, changes, rows = Counter(), [], 0
    state_fields = {
        "is_active_on_cutoff", "is_finished_before_cutoff", "days_to_end",
        "days_since_end", "subrent_active_by_dates_on_cutoff",
        "subrent_finished_by_dates_before_cutoff", "is_active_by_date",
    }
    paths = [work / f"imports/staging/{kind}_import_facts.tsv" for work in (old_work, new_work)]
    with paths[0].open(encoding="utf-16", newline="") as old, paths[1].open(encoding="utf-16", newline="") as new:
        for left, right in zip_longest(csv.reader(old, delimiter="\t"), csv.reader(new, delimiter="\t")):
            if left is None or right is None or len(left) != len(fields) or len(right) != len(fields):
                raise ValueError(f"{kind}: source row count or width changed")
            a, b = dict(zip(fields, left)), dict(zip(fields, right))
            if a[key] != b[key]:
                raise ValueError(f"{kind}: source order/key changed at row {rows + 1}")
            if a["cutoff_at"] != OLD_DAY + " 20:12:12" or b["cutoff_at"] != NEW_DAY + " 20:12:12":
                raise ValueError(f"{kind}: incorrect cutoff at row {rows + 1}")
            delta = differences(a, b)
            counters.update(delta.keys())
            material = {k: v for k, v in delta.items() if k not in {"cutoff_at", "days_to_end", "days_since_end"}}
            if material:
                changes.append({"key": a[key], "document_number": a.get("document_number", a.get("service_doc_number")),
                                "end_date": a.get("end_date", a.get("service_end_date")), "changes": material})
            rows += 1
    if kind == "membership" and verify_payment_ties(audit, old_work, new_work, changes):
        state_fields.add("matched_payment_ref")
    audit.check(f"{kind}: all source fact values unchanged except cutoff states and verified equivalent payment references",
                not (set(counters) - state_fields - {"cutoff_at"}), checked_rows=rows, changed_fields=dict(counters))
    audit.details[f"{kind}_fact_changes"] = changes


def photo_manifest(folder):
    path = next(folder.glob("fitbase_client_photos_*.zip"))
    with zipfile.ZipFile(path) as archive:
        names = [name for name in archive.namelist() if name.endswith("/_reports/manifest.csv")]
        if len(names) != 1:
            raise ValueError("Photo archive must have exactly one manifest")
        with archive.open(names[0]) as stream:
            return index_rows(list(csv.DictReader(io.TextIOWrapper(stream, encoding="utf-8-sig"))), "client_id")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=ROOT / "output/20260922_cutoff_shift_audit")
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    old_folder = ROOT / "output/20260921_fitbase_for_customer"
    new_folder = ROOT / "output/20260922_final_delivery"
    old_work, new_work = [ROOT / "end-to-end-xlsx/work" / run for run in (OLD_RUN, NEW_RUN)]
    old_status, new_status = [json.loads((work / "status.json").read_text()) for work in (old_work, new_work)]
    audit = Audit()
    contracts = [status["cutoff_contract"] for status in (old_status, new_status)]
    finish = datetime.fromisoformat(contracts[1]["backup_finish_at"])
    a, b = [datetime.fromisoformat(contract["cutoff_at"]) for contract in contracts]
    audit.check("Same actual backup; new cutoff is +48 hours from backup and +24 hours from previous delivery",
                contracts[0]["backup_finish_at"] == contracts[1]["backup_finish_at"] == "2026-09-20 20:12:12"
                and a.isoformat(" ") == OLD_DAY + " 20:12:12" and b.isoformat(" ") == NEW_DAY + " 20:12:12"
                and (b - finish).total_seconds() == 172800 and (b - a).total_seconds() == 86400)
    signatures = [{Path(k).name: v for k, v in status["input_hashes"].items() if Path(k).name != "expected.yml"} for status in (old_status, new_status)]
    audit.check("All signed business inputs and membership builder unchanged", signatures[0] == signatures[1], input_hashes=signatures)
    expected = [(ROOT / "end-to-end-xlsx/work/prepared" / run / "expected.yml").read_text() for run in (OLD_RUN, NEW_RUN)]
    audit.check("Expected manifest changes only cutoff, date stamps and run name",
                expected[0].replace(OLD_RUN, NEW_RUN).replace("20260921", "20260922").replace(OLD_DAY, NEW_DAY) == expected[1])
    configs = [yaml.safe_load((ROOT / "end-to-end-xlsx/work/prepared" / run / "pipeline.yml").read_text()) for run in (OLD_RUN, NEW_RUN)]
    for config in configs:
        for field in ("effective_at", "cutoff_at", "cutoff_date", "date_stamp", "work_name", "delivery_name"):
            config["run"].pop(field)
        config["validation"].pop("expected_manifest")
        config["backup"].pop("header_metadata_path")
    audit.check("Configuration differs only by requested cutoff and new output paths", configs[0] == configs[1])
    for side, folder, manifest_path in (
        ("previous", old_folder, ROOT / "output/20260921_final_v2_delivery/reports/delivery_manifest.json"),
        ("current", new_folder, new_folder / "reports/delivery_manifest.json"),
    ):
        manifest = json.loads(manifest_path.read_text())
        file_set = {p.name for p in folder.iterdir() if p.suffix in {".zip", ".xlsx"}}
        audit.check(f"{side}: exactly eight data files match manifest", len(file_set) == 8 and file_set == {r["name"] for r in manifest["files"]})
        audit.check(f"{side}: every saved data file retains verified SHA-256 and size", all(
            digest(folder / r["name"]) == r["sha256"] and (folder / r["name"]).stat().st_size == r["size_bytes"] for r in manifest["files"]))

    owners = [index_rows(csv_rows(work / "owner/csv/final_funnel_clients.csv"), "client_id") for work in (old_work, new_work)]
    audit.check("All source client IDs retained", owners[0].keys() == owners[1].keys(), clients=len(owners[1]))
    transitions = {key for key in owners[0] if owners[0][key]["funnel"] != owners[1][key]["funnel"]}
    audit.details["owner_funnel_transitions"] = [{"client_id": key, "before": owners[0][key]["funnel"],
        "after": owners[1][key]["funnel"], "last_end": owners[1][key]["selected_subscription_end_date"]} for key in sorted(transitions)]
    audit.check("Every source funnel transition is a membership expiring September 21", all(
        owners[0][key]["funnel"] == "Действующие клиенты" and owners[1][key]["funnel"] == "Реактивация"
        and owners[1][key]["selected_subscription_end_date"][:10] == OLD_DAY for key in transitions), changed_clients=len(transitions))

    books, deltas, counts = {}, {}, []
    for old in sorted(old_folder.glob("*.xlsx")):
        new = new_folder / old.name.replace("20260921", "20260922")
        header_count = 1 if "plastic_cards" in old.name or old.name.startswith("problem_") else 2
        left, right = workbook(old, header_count), workbook(new, header_count)
        audit.check(f"Same headers and layout: {new.name}",
                    [{k: r[k] for k in ("name", "columns", "headers", "header_formats")} for r in left["sheets"]]
                    == [{k: r[k] for k in ("name", "columns", "headers", "header_formats")} for r in right["sheets"]]
                    and layout(old) == layout(new))
        with zipfile.ZipFile(old) as old_zip, zipfile.ZipFile(new) as new_zip:
            audit.check(f"Same saved Excel styles: {new.name}", old_zip.read("xl/styles.xml") == new_zip.read("xl/styles.xml"))
        counts.append({"file": new.name, "before": len(left["data"]), "after": len(right["data"])})
        if "plastic_cards" in old.name:
            headers = left["sheets"][0]["headers"][0]
            counters = [Counter(tuple(normalized(row[k], k) for k in headers) for row in book["data"]) for book in (left, right)]
            removed, added = counters[0] - counters[1], counters[1] - counters[0]
            deltas["cards"] = {"removed": [list(row) for row in removed.elements()], "added": [list(row) for row in added.elements()]}
            books["cards"] = (left["data"], right["data"])
            continue
        key = ("client_id" if "zayavki" in old.name else "name" if "shablony" in old.name
               else "service_id" if "uslugi_clientov" in old.name else "contract_id")
        indexed = [index_rows(book["data"], key) for book in (left, right)]
        before, after = indexed
        changes = [{"key": k, "changes": differences(before[k], after[k])} for k in sorted(before.keys() & after.keys())]
        changes = [row for row in changes if row["changes"]]
        delta = {"added": sorted(after.keys() - before.keys()), "removed": sorted(before.keys() - after.keys()), "changed": changes,
                 "changed_fields": dict(Counter(f for row in changes for f in row["changes"]))}
        kind = ("applications" if key == "client_id" else "membership_templates" if "shablony_abonementov" in old.name
                else "service_templates" if key == "name" else "services" if key == "service_id"
                else "problem4" if old.name.startswith("problem_") else "memberships")
        deltas[kind], books[kind] = delta, indexed
        print(f"Compared {kind}: {len(before)} -> {len(after)}, changed={len(changes)}, added={len(delta['added'])}, removed={len(delta['removed'])}", flush=True)

    for kind in ("applications", "memberships", "membership_templates", "service_templates", "problem4"):
        delta = deltas[kind]
        audit.check(f"{kind}: no IDs added or lost", not delta["added"] and not delta["removed"])
    for kind in ("membership_templates", "service_templates", "problem4"):
        audit.check(f"{kind}: every saved cell unchanged", not deltas[kind]["changed"])
    app_changes = deltas["applications"]["changed"]
    audit.check("Applications change only funnel labels for expired memberships", all(
        set(row["changes"]) <= {"funnel", "funnel_step"} and row["key"] in transitions for row in app_changes))
    audit.details["delivered_funnel_transitions"] = [row["key"] for row in app_changes]
    before_apps, after_apps = books["applications"]
    audit.details["funnels"] = [{k: v for k, v in Counter(row["funnel"] for row in data.values()).items()} for data in (before_apps, after_apps)]
    expected_removed = Counter((normalized(before_apps[key]["phone"]), normalized(before_apps[key]["client_fio"]),
                                owners[0][key]["selected_card_number"]) for key in audit.details["delivered_funnel_transitions"])
    actual_removed = Counter(tuple(row) for row in deltas["cards"]["removed"])
    audit.check("Cards removed only for the delivered clients who moved to reactivation", actual_removed == expected_removed and not deltas["cards"]["added"], removed_cards=sum(actual_removed.values()))
    audit.check("Membership cells change only expired visit limits or existing no-source-date fallback", all(
        (set(row["changes"]) == {"visits_left"} and normalized(books["memberships"][0][row["key"]]["end_date"], "end_date") == OLD_DAY
         and row["changes"]["visits_left"]["after"] == "0")
        or (set(row["changes"]) == {"create_date"} and row["key"].startswith("refuser:")
            and row["changes"]["create_date"] == {"before": OLD_DAY, "after": NEW_DAY})
        for row in deltas["memberships"]["changed"]))
    service_delta = deltas["services"]
    audit.check("Services: only expired rows removed; surviving cells unchanged", not service_delta["added"] and not service_delta["changed"] and all(
        normalized(books["services"][0][key]["end_date"], "end_date") == OLD_DAY for key in service_delta["removed"]))
    audit.details["open_cases"] = {key: books["memberships"][1][key] for key in ("00000154220", "00000144499")}
    audit.check("Previously discussed contracts retained without changes", all(
        not differences(books["memberships"][0][key], books["memberships"][1][key]) for key in audit.details["open_cases"]))
    audit.details["workbook_counts"], audit.details["workbook_changes"] = counts, deltas

    compare_facts(audit, old_work, new_work, "membership", "19_build_membership_import_xlsx.py", "subscription_ref")
    compare_facts(audit, old_work, new_work, "services", "23_build_services_import_xlsx.py", "sale_line_id")
    photos = [photo_manifest(folder) for folder in (old_folder, new_folder)]
    audit.check("Photo clients retained", photos[0].keys() == photos[1].keys(), jpeg_files=len(photos[1]))
    photo_changes = [{"client_id": key, "changes": differences(photos[0][key], photos[1][key])} for key in photos[0].keys() & photos[1].keys()]
    photo_changes = [row for row in photo_changes if row["changes"]]
    audit.check("Photo bytes, filenames, phones and IDs unchanged; only expired clients change funnel", all(
        set(row["changes"]) == {"funnel"} and row["client_id"] in audit.details["delivered_funnel_transitions"] for row in photo_changes))
    audit.details["photo_changes"] = photo_changes
    audit.details["photo_funnels"] = [dict(Counter(row["funnel"] for row in p.values())) for p in photos]
    failures = [row for row in audit.checks if not row["pass"]]
    result = {"status": "FAIL" if failures else "PASS", "checks": audit.checks, "details": audit.details}
    (args.output / "audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2, default=str) + "\n")
    print(json.dumps({"status": result["status"], "checks": len(audit.checks), "failures": [r["check"] for r in failures], "counts": counts}, ensure_ascii=False), flush=True)
    return int(bool(failures))


if __name__ == "__main__":
    raise SystemExit(main())
