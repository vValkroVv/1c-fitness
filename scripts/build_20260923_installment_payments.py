#!/usr/bin/env python3
"""Build the September installment reconciliation as a manual review dataset.

The XLSX is authored by write_20260923_installment_payments.mjs. This script
keeps the SQL extraction and accounting joins explicit and reproducible.
"""

from __future__ import annotations

import csv
import importlib.util
import json
import os
import subprocess
import sys
import re
import zipfile
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PACKAGE = ROOT / "end-to-end-xlsx"
OLD = PACKAGE / "work/20260922_final/imports/staging"
SUPPLEMENT = PACKAGE / "work/20260921_final_v2/imports/staging"
SUPPLEMENT_XLSX = ROOT / "output/20260921_phone_dedup_supplement_371/fitbase_import_abonementy_clientov_20260921.xlsx"
NEW = PACKAGE / "work/20260923_restore_verified/imports/staging"
REPORTS = ROOT / "output/20260923_delta_from_20260920/reports/payments"
OLD_FINISH = "2026-09-20 20:12:12"
OLD_EFFECTIVE = "2026-09-22 20:12:12"
SUPPLEMENT_EFFECTIVE = "2026-09-21 20:12:12"
NEW_FINISH = "2026-09-23 23:36:39"
DB = "FitnessRestored_20260923_macos"


def load_builder():
    path = PACKAGE / "scripts/19_build_membership_import_xlsx.py"
    spec = importlib.util.spec_from_file_location("membership_builder_for_delta_payments", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def dec(value):
    return Decimal(str(value or "0").replace(",", "."))


def number(value):
    return float(value.quantize(Decimal("0.01")))


def read_delivered_xlsx(path):
    """Read the actual delivered workbook using the XLSX standard library parts."""
    ns = {"x": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    with zipfile.ZipFile(path) as archive:
        strings = ET.fromstring(archive.read("xl/sharedStrings.xml"))
        shared = ["".join(t.text or "" for t in si.findall(".//x:t", ns))
                  for si in strings.findall("x:si", ns)]
        sheet = ET.fromstring(archive.read("xl/worksheets/sheet1.xml"))
    values = []
    for row in sheet.findall(".//x:sheetData/x:row", ns):
        cells = {}
        for cell in row.findall("x:c", ns):
            column = re.match(r"[A-Z]+", cell.attrib["r"]).group()
            index = 0
            for letter in column:
                index = index * 26 + ord(letter) - 64
            raw = cell.find("x:v", ns)
            if raw is None:
                inline = cell.find("x:is", ns)
                value = "" if inline is None else "".join(t.text or "" for t in inline.findall(".//x:t", ns))
            elif cell.attrib.get("t") == "s":
                value = shared[int(raw.text)]
            else:
                value = raw.text or ""
            cells[index - 1] = value
        values.append([cells.get(i, "") for i in range(22)])
    headers = values[0]
    if headers[:3] != ["tag", "contract_id", "client_id"]:
        raise RuntimeError("Unexpected supplement workbook headers")
    return [dict(zip(headers, row)) for row in values[2:]]


def previous_contracts(builder):
    main_rows = [r for r in read_csv(OLD / "membership_import_rows.csv") if r.get("_subscription_ref")]
    main_facts = {r["subscription_ref"]: r for r in builder.read_facts(OLD / "membership_import_facts.tsv")}
    supplement_facts = builder.read_facts(SUPPLEMENT / "membership_import_facts.tsv")
    if {r["cutoff_at"] for r in supplement_facts} != {SUPPLEMENT_EFFECTIVE}:
        raise RuntimeError("Supplement facts have mixed/wrong cutoff")
    if {r["cutoff_at"] for r in main_facts.values()} != {OLD_EFFECTIVE}:
        raise RuntimeError("Main previous facts have mixed/wrong cutoff")
    by_contract = defaultdict(list)
    for fact in supplement_facts:
        by_contract[(fact["document_number"], fact["client_id"])].append(fact)
    supplied = []
    for old in read_delivered_xlsx(SUPPLEMENT_XLSX):
        key = (old["contract_id"], old["client_id"])
        candidates = by_contract.get(key, [])
        if len(candidates) != 1:
            raise RuntimeError(f"Supplement contract cannot be uniquely linked to source facts: {key}: {len(candidates)}")
        fact = candidates[0]
        supplied.append((old, fact))
    if len(supplied) != 879:
        raise RuntimeError(f"Unexpected supplement membership count: {len(supplied)}")
    combined = {}
    counts = Counter()
    def add(old, fact, source, cutoff):
        ref = old.get("_subscription_ref") or fact.get("subscription_ref", "")
        key = ("ref", ref) if ref else ("contract", old["contract_id"], old["client_id"])
        if key in combined:
            prior = combined[key]
            if any(str(prior[0].get(field, "")) != str(old.get(field, "")) for field in
                   ("contract_id", "client_id", "price", "amount_of_payments", "payment_left")):
                raise RuntimeError(f"Conflicting prior delivered contract: {key}")
            counts["duplicate_same_contract"] += 1
            return
        old = dict(old, _subscription_ref=ref)
        combined[key] = (old, fact, source, cutoff)
        counts[source] += 1
    for old in main_rows:
        add(old, main_facts.get(old["_subscription_ref"], {}), "main_20260922", OLD_EFFECTIVE)
    for old, fact in supplied:
        add(old, fact, "supplement_371_20260921", SUPPLEMENT_EFFECTIVE)
    return list(combined.values()), counts


def register_movements():
    # Source values are 1C SQL datetime values. Keep their local wall time.
    sql = f"""
SET NOCOUNT ON;
SELECT CONVERT(varchar(32),_Fld3308_RRRef,2),
       CONVERT(varchar(8),_RecorderTRef,2),
       CONVERT(varchar(32),_RecorderRRef,2),
       CONVERT(varchar(20),_LineNo),
       CONVERT(varchar(19),CASE WHEN _Period>'3000-01-01' THEN DATEADD(year,-2000,_Period) ELSE _Period END,120),
       CONVERT(varchar(1),_RecordKind),
       CONVERT(varchar(32),CAST(_Fld3311 AS decimal(15,2)))
FROM dbo._AccumRg3305
WHERE _Active=0x01 AND _Fld3308_RTRef=0x0000009A
  AND CASE WHEN _Period>'3000-01-01' THEN DATEADD(year,-2000,_Period) ELSE _Period END > '{OLD_FINISH}'
  AND CASE WHEN _Period>'3000-01-01' THEN DATEADD(year,-2000,_Period) ELSE _Period END <= '{NEW_FINISH}'
ORDER BY _Fld3308_RRRef,_Period,_RecorderRRef,_LineNo;
"""
    env = dict(os.environ, SQLCMD_SERVER="mssql-fitness-2022,1433")
    proc = subprocess.run(
        [str(ROOT / "scripts/macos_backup_sqlcmd.sh"), "-d", DB,
         "-Q", sql, "-s", "\t", "-W", "-h", "-1"],
        capture_output=True, text=True, env=env, check=True,
    )
    rows = []
    for line in proc.stdout.splitlines():
        fields = line.split("\t")
        if len(fields) != 7 or len(fields[0]) != 32:
            continue
        sale_ref, recorder_type, recorder_ref, line_no, at, kind, amount = fields
        rows.append(dict(sale_ref=sale_ref, recorder_type=recorder_type,
                         recorder_ref=recorder_ref, line_no=line_no,
                         movement_at=at, kind=kind, amount=number(dec(amount))))
    return rows


def build():
    REPORTS.mkdir(parents=True, exist_ok=True)
    builder = load_builder()
    previous, source_counts = previous_contracts(builder)
    new_facts = {r["subscription_ref"]: r for r in builder.read_facts(NEW / "membership_import_facts.tsv")}
    new_by_contract = defaultdict(list)
    for fact in new_facts.values():
        new_by_contract[(fact.get("document_number", ""), fact.get("client_id", ""))].append(fact)
    if len(new_facts) == 0 or len(previous) == 0:
        raise RuntimeError("Membership facts missing")
    if {r["cutoff_at"] for r in new_facts.values()} != {NEW_FINISH}:
        raise RuntimeError("New membership facts have mixed/wrong cutoff")
    movements = register_movements()
    by_sale = defaultdict(list)
    for row in movements:
        by_sale[row["sale_ref"]].append(row)
    details = []
    included_movements = []
    issues = []
    for old, prior, old_source, previous_effective_at in previous:
        ref = old["_subscription_ref"]
        fact = new_facts.get(ref) if ref else None
        if not fact:
            candidates = new_by_contract.get((old["contract_id"], old["client_id"]), [])
            if len(candidates) > 1:
                raise RuntimeError(f"Ambiguous new contract fallback: {old['contract_id']}, {old['client_id']}")
            fact = candidates[0] if candidates else None
        if not fact:
            if "рассроч" in old["contract_name"].lower() or dec(old["payment_left"]) > 0:
                issues.append({"subscription_ref": ref, "issue": "previous_contract_absent_from_new_facts"})
                details.append(dict(
                    review_status="CONTRACT_ABSENT_FROM_NEW_FACTS", subscription_ref=ref,
                    previous_delivery=old_source, previous_effective_at=previous_effective_at,
                    contract_id=old["contract_id"], client_id=old["client_id"],
                    client_fio=old["client_fio"], contract_name=old["contract_name"],
                    sale_doc_ref=prior.get("financial_sale_document_ref", ""),
                    sale_datetime=prior.get("financial_sale_document_datetime", ""),
                    old_price=number(dec(old["price"])), new_price=None, price_delta=None,
                    old_paid=number(dec(old["amount_of_payments"])), new_paid=None, paid_delta=None,
                    old_debt=number(dec(old["payment_left"])), new_debt=None, debt_delta=None,
                    payments_before_previous_effective=None,
                    payments_after_previous_effective=None,
                    charge_movements=None, payment_movement_count=None,
                    old_money_source=old.get("_money_source") or "delivered_supplement_xlsx", new_money_source="",
                    old_register_allocation=prior.get("financial_register_allocation_unambiguous", ""),
                    new_register_allocation="",
                    old_register_paid=number(dec(prior.get("financial_register_payment_sum"))),
                    new_register_paid=None,
                    old_register_debt=number(dec(prior.get("financial_register_signed_debt"))),
                    new_register_debt=None, new_register_last_at="",
                ))
            continue
        new_price, new_paid, new_debt, source = builder.compute_money(fact)
        override = builder.business_zero_override_reason(fact, new_price)
        if override:
            new_price = new_paid = new_debt = Decimal("0")
            source = override
        old_price = dec(old["price"])
        old_paid = dec(old["amount_of_payments"])
        old_debt = dec(old["payment_left"])
        if not ("рассроч" in old["contract_name"].lower() or
                "рассроч" in fact["subscription_name"].lower() or
                old_debt > 0 or new_debt > 0):
            continue
        sale_ref = fact.get("financial_sale_document_ref") or prior.get("financial_sale_document_ref", "")
        lines = by_sale.get(sale_ref, []) if sale_ref else []
        payment_lines = [x for x in lines if x["kind"] == "0"]
        before = sum((dec(x["amount"]) for x in payment_lines if x["movement_at"] <= previous_effective_at), Decimal("0"))
        after = sum((dec(x["amount"]) for x in payment_lines if x["movement_at"] > previous_effective_at), Decimal("0"))
        charges = sum((dec(x["amount"]) for x in lines if x["kind"] == "1"), Decimal("0"))
        paid_delta = new_paid - old_paid
        unambiguous = fact.get("financial_register_allocation_unambiguous") == "1"
        if not sale_ref:
            status = "NO_SALE_DOCUMENT_LINK"
        elif not unambiguous:
            status = "AMBIGUOUS_REGISTER_ALLOCATION"
        elif paid_delta == 0 and not payment_lines:
            status = "NO_PAYMENT_CHANGE"
        elif paid_delta == before + after and paid_delta >= 0:
            status = "MOVEMENTS_MATCH_DELTA__OLD_SNAPSHOT_NOT_ROW_VERIFIED"
        else:
            status = "UNRESOLVED_DELTA_VS_MOVEMENTS"
        row = dict(
            review_status=status, subscription_ref=ref, previous_delivery=old_source,
            previous_effective_at=previous_effective_at, contract_id=old["contract_id"],
            client_id=old["client_id"], client_fio=old["client_fio"],
            contract_name=fact["subscription_name"], sale_doc_ref=sale_ref,
            sale_datetime=fact.get("financial_sale_document_datetime", ""),
            old_price=number(old_price), new_price=number(new_price), price_delta=number(new_price-old_price),
            old_paid=number(old_paid), new_paid=number(new_paid), paid_delta=number(paid_delta),
            old_debt=number(old_debt), new_debt=number(new_debt), debt_delta=number(new_debt-old_debt),
            payments_before_previous_effective=number(before), payments_after_previous_effective=number(after),
            charge_movements=number(charges), payment_movement_count=len(payment_lines),
            old_money_source=old.get("_money_source") or "delivered_supplement_xlsx", new_money_source=source,
            old_register_allocation=prior.get("financial_register_allocation_unambiguous", ""),
            new_register_allocation=fact.get("financial_register_allocation_unambiguous", ""),
            old_register_paid=number(dec(prior.get("financial_register_payment_sum"))),
            new_register_paid=number(dec(fact.get("financial_register_payment_sum"))),
            old_register_debt=number(dec(prior.get("financial_register_signed_debt"))),
            new_register_debt=number(dec(fact.get("financial_register_signed_debt"))),
            new_register_last_at=fact.get("financial_register_last_movement_datetime", ""),
        )
        details.append(row)
        for movement in lines:
            period = ("before_previous_effective" if movement["movement_at"] <= previous_effective_at
                      else "after_previous_effective")
            included_movements.append(dict(subscription_ref=ref, contract_id=old["contract_id"],
                                           client_id=old["client_id"], previous_delivery=old_source,
                                           previous_effective_at=previous_effective_at,
                                           **movement, period=period))
    details.sort(key=lambda r: (r["review_status"], r["client_id"], r["contract_id"]))
    included_movements.sort(key=lambda r: (r["client_id"], r["contract_id"], r["movement_at"], r["recorder_ref"], r["line_no"]))
    summary = dict(old_backup_finish_at=OLD_FINISH, old_published_effective_at=OLD_EFFECTIVE,
                   supplement_published_effective_at=SUPPLEMENT_EFFECTIVE,
                   previous_delivered_contracts_by_source=dict(source_counts),
                   previous_sources="Main 2026-09-22 and supplement 371 2026-09-21; upload status of supplement unconfirmed.",
                   new_backup_finish_at=NEW_FINISH, previous_contracts_reviewed=len(details),
                   contracts_absent_from_new_facts=sum(r["review_status"] == "CONTRACT_ABSENT_FROM_NEW_FACTS" for r in details),
                   absent_contracts_old_unpaid_total=number(sum((dec(r["old_debt"]) for r in details if r["review_status"] == "CONTRACT_ABSENT_FROM_NEW_FACTS"), Decimal("0"))),
                   linked_register_movements=len(included_movements),
                   statuses=dict(Counter(r["review_status"] for r in details)),
                   total_paid_delta=number(sum((dec(r["paid_delta"]) for r in details), Decimal("0"))),
                   movement_payment_sum=number(sum((dec(r["amount"]) for r in included_movements if r["kind"] == "0"), Decimal("0"))),
                   limitation="Old SQL row-level register snapshot unavailable; movement membership in old snapshot cannot be independently proven.")
    (REPORTS / "reconciliation.json").write_text(json.dumps({"summary":summary,"contracts":details,"movements":included_movements,"issues":issues},ensure_ascii=False,indent=2),encoding="utf-8")
    (REPORTS / "summary.json").write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding="utf-8")
    print(json.dumps(summary,ensure_ascii=False))


if __name__ == "__main__":
    build()
