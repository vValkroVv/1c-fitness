#!/usr/bin/env python3
"""Prepare a two-contract manual owner-transfer review from verified audits."""

import csv
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
REPORTS = ROOT / "output/20260923_delta_from_20260920/reports/imports"
OLD_MEMBERS = ROOT / "end-to-end-xlsx/work/20260922_final/imports/staging/membership_import_rows.csv"
TARGET = ROOT / "output/20260923_delta_from_20260920/reports/katya/owner_transfers_spec.json"


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))


def main() -> None:
    transfers = read_csv(REPORTS / "new_client_prior_contract_transfers.csv")
    if len(transfers) != 2:
        raise RuntimeError(f"Expected exactly two owner transfers, got {len(transfers)}")
    wanted = {row["contract_id"] for row in transfers}
    if len(wanted) != 2:
        raise RuntimeError("Owner-transfer contract IDs are not unique")
    previous = {row["contract_id"]: row for row in read_csv(OLD_MEMBERS) if row["contract_id"] in wanted}
    if set(previous) != wanted:
        raise RuntimeError("Transferred contracts must exist in the previous delivery")

    result = []
    for transfer in sorted(transfers, key=lambda row: row["contract_id"]):
        old = previous[transfer["contract_id"]]
        for key in ("old_client_id", "subscription_ref"):
            old_key = "client_id" if key == "old_client_id" else "_subscription_ref"
            if transfer[key] != old[old_key]:
                raise RuntimeError(f"Prior {key} mismatch for {transfer['contract_id']}")
        if old["contract_name"] == "" or transfer["new_client_id"] == "":
            raise RuntimeError("Owner transfer has missing required details")
        result.append({
            "review_status": "Проверить вручную в Fitbase",
            "old_client_id": transfer["old_client_id"],
            "old_client_fio": transfer["old_client_fio"],
            "new_client_id": transfer["new_client_id"],
            "new_client_fio": transfer["new_client_fio"],
            "contract_id": transfer["contract_id"],
            "contract_name": old["contract_name"],
            "subscription_ref": transfer["subscription_ref"],
            "original_sale_date": old["payment_date"],
            "transfer_datetime": transfer["transfer_datetime"],
            "price": float(old["price"]),
            "paid_before": float(old["amount_of_payments"]),
            "old_card": old["card"],
            "new_lead_funnel": transfer["new_lead_funnel"],
            "action": "Сверить текущего владельца договора; не загружать его как новую покупку",
        })
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    TARGET.write_text(json.dumps({"rows": result}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Prepared {len(result)} owner transfers: {TARGET}")


if __name__ == "__main__":
    main()
