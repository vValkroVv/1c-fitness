#!/usr/bin/env python3
"""Read-only reconciliation of clients without a membership-import row."""
from __future__ import annotations

from collections import Counter, defaultdict
import csv
import importlib.util
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "end-to-end-xlsx"
OUT = ROOT / "output/20260921_membership_coverage_audit"
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


def csv_rows(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        yield from csv.DictReader(handle)


def save(name, value):
    (OUT / name).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def workbook_ids(path, client_details=None):
    """Read the client_id column directly, without copying personal fields."""
    ids = set()
    row_count = 0
    with ZipFile(path) as archive:
        strings = []
        if "xl/sharedStrings.xml" in archive.namelist():
            for item in ET.fromstring(archive.read("xl/sharedStrings.xml")):
                strings.append("".join(item.itertext()))
        columns = {}
        with archive.open("xl/worksheets/sheet1.xml") as source:
            for _, row in ET.iterparse(source, events=("end",)):
                if row.tag != NS + "row":
                    continue
                number = int(row.attrib["r"])
                values = {}
                for cell in row:
                    address = cell.attrib["r"]
                    letter = address.rstrip("0123456789")
                    if number > 1 and letter not in columns:
                        continue
                    value = cell.findtext(NS + "v")
                    if cell.attrib.get("t") == "inlineStr":
                        value = "".join(cell.find(NS + "is").itertext())
                    elif cell.attrib.get("t") == "s":
                        value = strings[int(value)]
                    if number == 1 and value in ({"client_id", "funnel", "funnel_step"} if client_details is not None else {"client_id"}):
                        columns[letter] = value
                    elif number > 2 and letter in columns:
                        values[columns[letter]] = value
                if number > 2 and values.get("client_id"):
                    client_id = str(values["client_id"]).strip()
                    ids.add(client_id)
                    row_count += 1
                    if client_details is not None:
                        client_details[client_id] = values
                row.clear()
    if "client_id" not in columns.values():
        raise ValueError(f"Missing client_id header: {path}")
    return ids, row_count


def load_builder():
    sys.path.insert(0, str(PACKAGE / "scripts"))
    spec = importlib.util.spec_from_file_location("membership_coverage_builder", PACKAGE / "scripts/19_build_membership_import_xlsx.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def inspect_run(name, root, clients_xlsx, memberships_xlsx=None, raw_root=None):
    owner = {row["client_id"]: row for row in csv_rows(root / "owner/csv/final_funnel_clients.csv")}
    client_details = {}
    source_ids, source_row_count = workbook_ids(clients_xlsx, client_details)
    if memberships_xlsx:
        membership_ids, membership_count = workbook_ids(memberships_xlsx)
    else:
        membership_ids = set()
        membership_count = 0
        for row in csv_rows(root / "imports/staging/membership_import_rows.csv"):
            membership_ids.add(row["client_id"])
            membership_count += 1
    missing = source_ids - membership_ids
    raw_by_client = defaultdict(list)
    raw_by_ref = {}
    for row in csv_rows((raw_root or root) / "raw/staging/stg_subscriptions_all.csv"):
        if row["client_id"] in missing:
            raw_by_client[row["client_id"]].append(row)
            raw_by_ref[row["subscription_ref"]] = row
    reclassified_by_ref = {}
    for row in csv_rows(root / "owner/staging/stg_subscriptions_all.csv"):
        if row["client_id"] in missing:
            reclassified_by_ref[row["subscription_ref"]] = row
    facts_path = root / "imports/staging/membership_import_facts.tsv"
    fact_clients = Counter()
    if facts_path.exists():
        builder = load_builder()
        for fact in builder.read_facts(facts_path):
            if fact["client_id"] in missing:
                fact_clients[fact["client_id"]] += 1
    records = []
    all_missing_contracts = []
    for client_id in sorted(missing):
        selection = owner.get(client_id, {})
        contracts = raw_by_client[client_id]
        raw_selected = raw_by_ref.get(selection.get("selected_subscription_ref"), {})
        classified_selected = reclassified_by_ref.get(selection.get("selected_subscription_ref"), {})
        admitted = [r for r in contracts if r["product_class"] in ("full_subscription", "trial_or_guest") or "субаренд" in r["subscription_name"].lower()]
        record = {
            "client_id": client_id, "funnel": selection.get("funnel"),
            "funnel_step": selection.get("funnel_step"),
            "selected_subscription_ref": selection.get("selected_subscription_ref"),
            "selected_subscription_name": selection.get("selected_subscription_name"),
            "selected_start_date": selection.get("selected_subscription_start_date"),
            "selected_end_date": selection.get("selected_subscription_end_date"),
            "selected_raw_class": raw_selected.get("product_class"),
            "selected_owner_class": classified_selected.get("product_class"),
            "source_contract_count": len(contracts),
            "raw_class_counts": dict(Counter(r["product_class"] for r in contracts)),
            "source_products": sorted({r["subscription_name"] for r in contracts}),
            "source_contracts_admitted_by_membership_class_filter": len(admitted),
            "membership_fact_rows": fact_clients[client_id] if facts_path.exists() else None,
            "present_in_application_xlsx": True,
            "application_xlsx_funnel": client_details[client_id].get("funnel"),
            "application_xlsx_funnel_step": client_details[client_id].get("funnel_step"),
        }
        records.append(record)
        for row in contracts:
            all_missing_contracts.append({key: row[key] for key in ["client_id", "subscription_ref", "product_ref", "product_code", "subscription_name", "product_class", "sale_datetime", "start_date", "end_date", "is_active_on_cutoff", "is_finished_before_cutoff"]})
    summary = {
        "source": name, "application_xlsx": str(clients_xlsx.relative_to(ROOT)),
        "raw_source_csv": str(((raw_root or root) / "raw/staging/stg_subscriptions_all.csv").relative_to(ROOT)),
        "application_clients": len(source_ids), "application_rows": source_row_count,
        "membership_clients": len(membership_ids), "membership_rows": membership_count,
        "missing_clients": len(missing), "all_missing_clients_in_owner_csv": missing <= owner.keys(),
        "missing_by_funnel": dict(Counter(r["funnel"] for r in records)),
        "missing_by_stage": dict(Counter(r["funnel_step"] for r in records)),
        "missing_by_application_xlsx_funnel": dict(Counter(r["application_xlsx_funnel"] for r in records)),
        "missing_by_application_xlsx_stage": dict(Counter(r["application_xlsx_funnel_step"] for r in records)),
        "missing_by_selected_product": dict(Counter(r["selected_subscription_name"] for r in records)),
        "missing_by_selected_raw_class": dict(Counter(r["selected_raw_class"] for r in records)),
        "missing_by_selected_owner_class": dict(Counter(r["selected_owner_class"] for r in records)),
        "source_contracts_for_missing_clients": len(all_missing_contracts),
        "source_contracts_by_class": dict(Counter(r["product_class"] for r in all_missing_contracts)),
        "source_contracts_admitted_by_membership_class_filter": sum(r["source_contracts_admitted_by_membership_class_filter"] for r in records),
        "missing_clients_with_facts": len(fact_clients) if facts_path.exists() else None,
        "all_selected_names_akva": all("аква" in (r["selected_subscription_name"] or "").lower() for r in records),
        "all_source_contract_dates_ended_before_cutoff": all(r["end_date"] and r["end_date"] < owner[r["client_id"]]["cutoff_date"] for r in all_missing_contracts),
        "missing_selected_raw_rows": sum(r["selected_raw_class"] is None for r in records),
    }
    save(f"{name}_clients.json", records)
    save(f"{name}_contracts.json", all_missing_contracts)
    save(f"{name}_summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False), flush=True)
    return missing, records, source_ids, membership_ids


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    accepted_root = PACKAGE / "work/20260630_funnel_labels_20260820"
    accepted_delivery = ROOT / "output/20260630_delivery_funnel_labels_20260820"
    accepted = inspect_run("accepted_june", accepted_root,
        accepted_delivery / "fitbase_active_clients_import_zayavki_20260630_all_funnels.xlsx",
        accepted_delivery / "fitbase_import_abonementy_clientov_20260630.xlsx",
        PACKAGE / "work/20260630_full_cutoff")
    rehearsal_root = PACKAGE / "work/20260920_rehearsal_plus1"
    rehearsal = inspect_run("rehearsal_june_plus1", rehearsal_root,
        rehearsal_root / "owner/fitbase_active_clients_import_zayavki_20260701_all_funnels.xlsx")
    current_root = PACKAGE / "work/20260921_final_v2"
    current = inspect_run("september_final", current_root,
        current_root / "owner/fitbase_active_clients_import_zayavki_20260921_all_funnels.xlsx")
    comparisons = []
    for name, prior in [("accepted_june", accepted), ("rehearsal_june_plus1", rehearsal)]:
        before, _, before_source, before_membership = prior
        after, _, after_source, after_membership = current
        comparisons.append({
            "prior": name, "common_missing_count": len(before & after),
            "new_missing_ids": sorted(after - before),
            "no_longer_missing_ids": sorted(before - after),
            "prior_missing_now_has_membership": sorted(before & after_membership),
            "prior_missing_no_longer_in_applications": sorted(before - after_source),
            "current_missing_previously_had_membership": sorted(after & before_membership),
            "current_missing_previously_absent_from_applications": sorted(after - before_source),
        })
    save("comparisons.json", comparisons)
    print(json.dumps(comparisons, ensure_ascii=False), flush=True)
    export_excluded_history(current_root, current[0])
    explain_deltas(rehearsal_root, current_root, comparisons[1])


def export_excluded_history(root, missing):
    """Preserve historical source rows as a report, without inventing prices."""
    sys.path[:0] = [str(PACKAGE / "scripts"), str(ROOT / "scripts")]
    from database import ConnectionSettings, DatabaseClient
    from prepare_backup import query_dicts
    from run_fitbase_migration import read_sql_password
    raw = [row for row in csv_rows(root / "raw/staging/stg_subscriptions_all.csv") if row["client_id"] in missing]
    refs = {row["subscription_ref"] for row in raw}
    classified = {row["subscription_ref"]: row for row in csv_rows(root / "owner/staging/stg_subscriptions_all.csv") if row["subscription_ref"] in refs}
    quoted_refs = ",".join("'" + ref + "'" for ref in sorted(refs))
    sql = "SELECT CONVERT(varchar(32),_IDRRef,2) AS subscription_ref, LTRIM(RTRIM(_Number)) AS contract_id FROM dbo._Document163 WHERE CONVERT(varchar(32),_IDRRef,2) IN (" + quoted_refs + ") ORDER BY _Number OPTION (MAXDOP 2);\n"
    (OUT / "excluded_contract_numbers.sql").write_text(sql, encoding="utf-8")
    password = read_sql_password(ROOT / "tmp/macos-backup/mssql-fitness-macos.env")
    with DatabaseClient(ConnectionSettings(server="127.0.0.1", port=11435, database="FitnessRestored_20260630_macos", user="sa", password=password, query_timeout_seconds=120)) as db:
        numbers = query_dicts(db, sql)
    save("excluded_contract_numbers.json", numbers)
    number_by_ref = {row["subscription_ref"]: row["contract_id"] for row in numbers}
    assert number_by_ref.keys() == refs
    fields = ["client_id", "original_client_id", "effective_client_id", "subscription_ref", "product_ref", "product_code", "subscription_name", "sale_date", "sale_datetime", "start_date", "end_date", "duration_days", "status", "doc_posted", "doc_marked", "register_duration_days", "owner_change_ref", "owner_change_number", "owner_change_datetime", "raw_club", "normalized_club", "raw_source"]
    rows = []
    for row in sorted(raw, key=lambda r: (r["client_id"], r["sale_datetime"], r["subscription_ref"])):
        final = classified[row["subscription_ref"]]
        output = {field: row[field] for field in fields}
        output.update({
            "contract_id": number_by_ref[row["subscription_ref"]],
            "raw_product_class": row["product_class"], "final_product_class": final["product_class"],
            "raw_is_active_on_cutoff": row["is_active_on_cutoff"],
            "final_is_active_on_cutoff": final["is_active_on_cutoff"],
            "final_is_finished_before_cutoff": final["is_finished_before_cutoff"],
            "cutoff_at": "2026-09-21 20:12:12",
            "exclusion_reason": "raw_unknown_review_required_not_admitted_by_membership_sql31",
            "present_in_application_xlsx": "1",
        })
        rows.append(output)
    with (OUT / "excluded_history.csv").open("w", encoding="utf-8-sig", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)
    summary = {
        "clients": len(missing), "history_rows": len(rows), "unique_contracts": len(refs),
        "all_contract_numbers_resolved_in_source": len(number_by_ref) == len(refs),
        "raw_classes": dict(Counter(r["raw_product_class"] for r in rows)),
        "final_classes": dict(Counter(r["final_product_class"] for r in rows)),
        "final_active_rows": sum(r["final_is_active_on_cutoff"] == "1" for r in rows),
        "final_finished_rows": sum(r["final_is_finished_before_cutoff"] == "1" for r in rows),
        "history_by_product": dict(Counter(r["subscription_name"] for r in rows)),
        "decision_date": "2026-09-21",
        "decision": "User confirmed: preserve June rules and attach excluded history as a separate report.",
        "report_is_import_workbook": False,
        "amounts_invented": False,
    }
    assert len(rows) == 1806 and len(missing) == 766
    save("excluded_history_summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False), flush=True)


def explain_deltas(before_root, after_root, comparison):
    changed_ids = set(comparison["new_missing_ids"]) | set(comparison["no_longer_missing_ids"])
    columns = ["client_id", "contract_id", "contract_name", "_subscription_ref", "_product_class", "_owner_change_ref"]
    before_memberships = [{key: row[key] for key in columns} for row in csv_rows(before_root / "imports/staging/membership_import_rows.csv") if row["client_id"] in changed_ids]
    previous_refs = {row["_subscription_ref"] for row in before_memberships if row["_subscription_ref"]}
    after_memberships = [{key: row[key] for key in columns} for row in csv_rows(after_root / "imports/staging/membership_import_rows.csv") if row["client_id"] in changed_ids or row["_subscription_ref"] in previous_refs]
    source_columns = ["client_id", "original_client_id", "effective_client_id", "subscription_ref", "subscription_name", "product_class", "owner_change_ref", "owner_change_number", "owner_change_datetime", "sale_date", "end_date"]
    sources = {}
    for label, root in [("june", before_root), ("september", after_root)]:
        sources[label] = [{key: row[key] for key in source_columns} for row in csv_rows(root / "raw/staging/stg_subscriptions_all.csv") if row["client_id"] in changed_ids or row["subscription_ref"] in previous_refs]
    dedup_columns = ["client_id", "funnel", "funnel_step", "selected_subscription_ref", "selected_subscription_name", "winner_client_id", "dedupe_reason"]
    prior_dedup = [{key: row[key] for key in dedup_columns} for row in csv_rows(before_root / "owner/reports/phone_deduplication_removed_clients.csv") if row["client_id"] in comparison["new_missing_ids"]]
    save("changed_clients_evidence.json", {"before_memberships": before_memberships, "after_memberships": after_memberships, "source_rows": sources, "prior_phone_dedup_exclusions": prior_dedup})
    transferred = [row for row in after_memberships if row["contract_id"] == "00000133566"]
    assert len(transferred) == 1 and transferred[0]["client_id"] == "000053126"


if __name__ == "__main__":
    main()
