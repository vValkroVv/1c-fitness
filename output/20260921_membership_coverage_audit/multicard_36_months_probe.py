"""Read-only, product-scoped evidence; never writes source data or workbooks."""
import ast
import csv
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parent
NAME = "Абонемент МУЛЬТИКАРТА 36 месяцев"
GENERATOR = ROOT / "end-to-end-xlsx/scripts/19_build_membership_import_xlsx.py"
sys.path.insert(0, str(GENERATOR.parent))
spec = importlib.util.spec_from_file_location("multicard_generator", GENERATOR)
generator = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = generator
spec.loader.exec_module(generator)

def subset(row, fields):
    return {field: row.get(field) for field in fields}

def workbook_matches(path):
    ns = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}
    records = []
    with ZipFile(path) as archive:
        strings = []
        if "xl/sharedStrings.xml" in archive.namelist():
            strings = ["".join(si.itertext()) for si in ET.fromstring(archive.read("xl/sharedStrings.xml"))]
        for member in archive.namelist():
            if not member.startswith("xl/worksheets/sheet") or not member.endswith(".xml"):
                continue
            rows = []
            for row in ET.fromstring(archive.read(member)).findall(".//m:row", ns):
                cells = {}
                for cell in row.findall("m:c", ns):
                    if cell.get("t") == "inlineStr":
                        value = "".join(cell.find("m:is", ns).itertext())
                    else:
                        value = cell.findtext("m:v", default="", namespaces=ns)
                        if cell.get("t") == "s":
                            value = strings[int(value)]
                    cells[cell.get("r")] = value
                if NAME in cells.values() or int(row.get("r")) <= 2:
                    rows.append({"row": int(row.get("r")), "cells": cells})
            records.append({"member": member, "rows": rows})
    return records

fields = "subscription_ref document_number client_id product_ref product_code subscription_name product_class sale_date sale_datetime start_date end_date duration_days register_duration_days doc_duration_value rg_duration_days rg_freeze_days rg_price membership_sale_line_amount doc_posted doc_marked".split()
row_fields = "contract_id client_id contract_name duration duration_type create_date payment_date activation_date end_date freeze price _subscription_ref _product_ref _duration_source _money_source _business_override".split()
result = {"name": NAME, "runs": {}}
for run in ["20260920_rehearsal_plus1", "20260921_final_v2"]:
    staging = ROOT / "end-to-end-xlsx/work" / run / "imports/staging"
    facts = [r for r in generator.read_facts(staging / "membership_import_facts.tsv") if r["subscription_name"].strip() == NAME]
    with (staging / "membership_import_rows.csv").open(encoding="utf-8-sig", newline="") as handle:
        rows = [subset(r, row_fields) for r in csv.DictReader(handle) if r["contract_name"].strip() == NAME]
    with (staging / "membership_template_rows.csv").open(encoding="utf-8-sig", newline="") as handle:
        templates = [r for r in csv.DictReader(handle) if r["name"].strip() == NAME]
    result["runs"][run] = {
        "facts_count": len(facts), "rows_count": len(rows), "facts": [],
        "rows": rows, "templates": templates,
    }
    for fact in facts:
        record = subset(fact, fields)
        record["recomputed_duration"] = generator.compute_duration_months(fact)
        result["runs"][run]["facts"].append(record)

accepted = ROOT / "output/20260630_delivery_funnel_labels_20260820/fitbase_import_shablony_abonementov_20260630.xlsx"
result["accepted_june_template_xlsx"] = {"path": str(accepted.relative_to(ROOT)), "matches": workbook_matches(accepted)}
config = ROOT / "end-to-end-xlsx/config/membership_template_canonicalization.csv"
with config.open(encoding="utf-8-sig", newline="") as handle:
    result["matching_config_rows"] = [r for r in csv.DictReader(handle) if NAME.casefold() in json.dumps(r, ensure_ascii=False).casefold()]

historic_source = subprocess.check_output(["git", "show", "5863388:end-to-end-xlsx/scripts/19_build_membership_import_xlsx.py"], cwd=ROOT, text=True)
def function_ast(source, name):
    return ast.dump(next(node for node in ast.parse(source).body if isinstance(node, ast.FunctionDef) and node.name == name))
result["compute_duration_months_matches_accepted_commit_5863388"] = function_ast(historic_source, "compute_duration_months") == function_ast(GENERATOR.read_text(), "compute_duration_months")

from database import ConnectionSettings, DatabaseClient
sys.path.insert(0, str(ROOT / "scripts"))
from run_fitbase_migration import read_sql_password
password = read_sql_password(ROOT / "tmp/macos-backup/mssql-fitness-macos.env")
sql_path = OUT / "multicard_36_months_source.sql"
sql = sql_path.read_text()
result["raw_source_queries"] = {}
for database in ["FitnessRestored_20260630_original", "FitnessRestored_20260630_macos"]:
    settings = ConnectionSettings(server="127.0.0.1", port=11435,
                                  database=database, user="sa", password=password,
                                  query_timeout_seconds=60)
    with DatabaseClient(settings) as connection:
        with connection.connection.cursor() as cursor:
            cursor.execute(sql)
            columns = [column[0] for column in cursor.description]
            raw_rows = [dict(zip(columns, row)) for row in cursor.fetchall()]
    result["raw_source_queries"][database] = {"sql_file": str(sql_path.relative_to(ROOT)), "row_count": len(raw_rows), "rows": raw_rows}

destination = OUT / "multicard_36_months_evidence.json"
destination.write_text(json.dumps(result, ensure_ascii=False, indent=2, default=str) + "\n")
print(json.dumps(result, ensure_ascii=False, indent=2, default=str))
