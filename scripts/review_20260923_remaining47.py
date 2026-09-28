#!/usr/bin/env python3
"""Review unresolved photo-audit identities against local source and API data."""

import csv
import json
import re
import sqlite3
from collections import defaultdict
from decimal import Decimal
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "output/20260923_fitbase_photo_audit"
SOURCE = ROOT / "output/20260922_fitbase_live_audit/source.sqlite"


def ids(value):
    return [int(item) for item in value.split(";") if item]


def money(value):
    return Decimal(str(value).replace(",", ".")) if value else Decimal(0)


def main():
    with (AUDIT / "unmatched_review.csv").open(encoding="utf-8-sig", newline="") as file:
        rows = [row for row in csv.DictReader(file) if row["review_decision"] == "unresolved"]
    assert len(rows) == 47

    candidate_ids = {
        item
        for row in rows
        for column in ("card_candidate_ids", "phone_candidate_ids", "name_candidate_ids")
        for item in ids(row[column])
    }
    api = {}
    with (AUDIT / "api_snapshot.jsonl").open(encoding="utf-8") as file:
        for line in file:
            client = json.loads(line)
            if client["id"] in candidate_ids:
                api[client["id"]] = client
    assert len(api) == len(candidate_ids) == 53

    db = sqlite3.connect(SOURCE)
    db.row_factory = sqlite3.Row
    cards = [dict(card) for card in db.execute("SELECT * FROM cards")]
    source_phone_owners = defaultdict(set)
    for source in db.execute("SELECT client_id, phone FROM leads"):
        for part in (source["phone"] or "").split(","):
            phone = re.sub(r"\D", "", part)
            if len(phone) >= 10:
                source_phone_owners[phone[-10:]].add(source["client_id"])
    output = []
    for row in rows:
        source_id = row["source_id"]
        lead = db.execute("SELECT * FROM leads WHERE client_id = ?", (source_id,)).fetchone()
        assert lead is not None
        memberships = list(db.execute("SELECT * FROM memberships WHERE client_id = ?", (source_id,)))
        services = list(db.execute("SELECT * FROM services WHERE client_id = ?", (source_id,)))
        names = ids(row["name_candidate_ids"])
        phones = ids(row["phone_candidate_ids"])
        candidates = list(dict.fromkeys(ids(row["card_candidate_ids"]) + phones + names))
        card_rows = [card for card in cards if card["фио"].strip().casefold() == row["source_name"].strip().casefold()]
        bridge = [
            {"xlsx_row": card["_xlsx_row"], "card": card["номер пластиковой карты"], "phone": card["телефон"], "api_id": candidate}
            for card in card_rows
            for candidate in candidates
            if card["номер пластиковой карты"] and card["номер пластиковой карты"] == api[candidate]["card"]
        ]
        assert not lead["email"]
        assert all(api[item]["birth_date"] is None and not api[item]["custom_fields"] for item in candidates)
        amount = sum((money(item["amount_of_payments"]) for item in memberships), Decimal(0))
        amount += sum((money(item["amount_of_payment"]) for item in services), Decimal(0))
        source_phones = row["source_phones"].split(";")
        paid_matches = []
        for item in phones:
            client = api[item]
            api_name = " ".join(str(client[part] or "") for part in ("surname", "name", "patronymic")).strip()
            api_phones = {str(contact["contact"])[-10:] for contact in client["contacts"] if contact["contact_type"] == "phone"}
            shared = [phone for phone in source_phones if phone[-10:] in api_phones]
            if (
                amount > 0
                and money(client["purchase_amount"]) == amount
                and row["source_name"].casefold().startswith(api_name.casefold())
                and shared
                and all(source_phone_owners[phone[-10:]] == {source_id} for phone in shared)
            ):
                paid_matches.append(item)
        confirmed_id = str(paid_matches[0]) if len(paid_matches) == 1 else ""
        # The cards export contains no source client_id. An exact name is its only
        # bridge to the lead when the exported lead phone differs.
        reason = {
            "name_only_phone_differs": "Exact name only; source and API phones differ.",
            "same_name_multiple_api_clients": "Name belongs to multiple API clients; no matching source phone/card.",
            "phone_only_name_differs": "Phone only; API name differs from complete source name.",
            "shared_phone_multiple_api_clients": "Source phone is shared by multiple API clients.",
            "phone_and_name_point_to_different_api_clients": "Source phone and name point to different API clients.",
        }[row["review_cause"]]
        if bridge:
            reason += " Cards export matches API card and name, but links to source client by name alone."
        if amount == 0 and memberships:
            reason += " Source paid total is zero, so amount is not discriminating."
        if len(candidates) > 1 and amount > 0 and not confirmed_id:
            reason += " Paid total does not select one API client."
        output.append({
            "source_id": source_id,
            "source_name": row["source_name"],
            "source_phones": row["source_phones"],
            "source_lead_xlsx_row": row["source_lead_xlsx_row"],
            "source_lead_date": lead["create_date"],
            "source_branch": lead["филиал"],
            "source_email": lead["email"],
            "source_membership_count": len(memberships),
            "source_membership_contract_ids": ";".join(item["contract_id"] for item in memberships),
            "source_service_count": len(services),
            "source_service_ids": ";".join(item["service_id"] for item in services),
            "source_paid_total": str(amount),
            "review_cause": row["review_cause"],
            "candidate_ids": ";".join(map(str, candidates)),
            "candidate_details_json": json.dumps([
                {
                    "id": item,
                    "name": " ".join(str(api[item][part] or "") for part in ("surname", "name", "patronymic")).strip(),
                    "phones": [contact["contact"] for contact in api[item]["contacts"] if contact["contact_type"] == "phone"],
                    "emails": [contact["contact"] for contact in api[item]["contacts"] if contact["contact_type"] == "email"],
                    "card": api[item]["card"],
                    "birth_date": api[item]["birth_date"],
                    "lead_id": api[item]["lead_id"],
                    "created_at": api[item]["created_at"],
                    "club": api[item]["club"]["name"] if api[item]["club"] else None,
                    "purchase_amount": api[item]["purchase_amount"],
                    "photo_present": bool(api[item]["photo"]),
                }
                for item in candidates
            ], ensure_ascii=False),
            "cards_export_name_bridge_json": json.dumps(bridge, ensure_ascii=False),
            "independent_identifier_result": (
                "Positive source membership+service payments equal one phone-and-name-compatible API purchase_amount; source phone unique in leads"
                if confirmed_id else "No discriminating independent source-to-API identifier"
            ),
            "decision": "linked_by_phone_name_prefix_and_paid_total" if confirmed_id else "unresolved",
            "confirmed_fitbase_id": confirmed_id,
            "confirmed_photo_present": "yes" if confirmed_id and api[int(confirmed_id)]["photo"] else ("no" if confirmed_id else ""),
            "unresolved_reason": "" if confirmed_id else reason,
        })
    db.close()
    path = AUDIT / "remaining47_review.csv"
    with path.open("w", encoding="utf-8-sig", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=output[0].keys())
        writer.writeheader()
        writer.writerows(output)
    print(f"Wrote {len(output)} unresolved rows to {path}")


if __name__ == "__main__":
    main()
