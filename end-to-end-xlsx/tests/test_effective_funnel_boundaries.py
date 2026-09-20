from __future__ import annotations

import importlib.util
import unittest
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reclassifier = load_module("effective_funnel_reclassifier", ROOT / "scripts/16_reclassify_part2_from_csv.py")
contract = load_module("effective_funnel_contract", ROOT / "scripts/cutoff_contract.py")


def final_client(source: dict[str, str], run: dict[str, object]):
    resolved = contract.resolve_cutoff(run, {"backup_finish_at": "2026-09-20 21:45:30"})
    effective = datetime.fromisoformat(resolved["cutoff_at"])
    subscriptions = reclassifier.reclassify_subscriptions([source], {}, set(), effective)
    history = reclassifier.build_client_history(
        [{"client_ref": "client-1", "client_id": "000000001"}], [], subscriptions, effective
    )
    _, selected = reclassifier.build_subscription_candidates(subscriptions)
    return reclassifier.build_final_rows(history, selected, [], effective.date())[0]


def membership(**changes: str) -> dict[str, str]:
    return {
        "client_ref": "client-1",
        "client_id": "000000001",
        "subscription_ref": "membership-1",
        "subscription_name": "Годовой",
        "product_class": "full_subscription",
        "sale_date": "2025-09-21",
        "sale_datetime": "2025-09-21 15:00:00",
        "start_date": "2025-09-21",
        "end_date": "2026-09-20",
        **changes,
    }


class EffectiveFunnelBoundaryTests(unittest.TestCase):
    def test_next_evening_reclassifies_expired_membership_without_shifting_dates(self):
        source = membership()
        before = final_client(source, {})
        after = final_client(source, {"effective_offset_days": 1})
        self.assertEqual(before["funnel"], "Действующие клиенты")
        self.assertEqual(before["days_to_end"], "0")
        self.assertEqual(after["funnel"], "Реактивация")
        self.assertEqual(after["days_since_end"], "1")
        self.assertEqual(after["cutoff_date"], "2026-09-21")
        for field in ["start_date", "end_date", "sale_date"]:
            self.assertEqual(before[f"selected_subscription_{field}"], source[field])
            self.assertEqual(after[f"selected_subscription_{field}"], source[field])

    def test_future_dated_source_record_uses_exact_selected_time(self):
        source = membership(
            sale_date="2026-09-21",
            sale_datetime="2026-09-21 21:45:30",
            start_date="2026-09-21",
            end_date="2027-09-20",
        )
        before = final_client(source, {"effective_at": "2026-09-21 21:45:29"})
        exact = final_client(source, {"effective_offset_days": 1})
        self.assertEqual(before["funnel"], "Новые заявки")
        self.assertEqual(before["full_subscription_count"], "0")
        self.assertEqual(exact["funnel"], "Действующие клиенты")
        self.assertEqual(exact["full_subscription_count"], "1")
        self.assertEqual(exact["selected_subscription_sale_date"], "2026-09-21")
        self.assertEqual(exact["selected_subscription_end_date"], "2027-09-20")


if __name__ == "__main__":
    unittest.main()
