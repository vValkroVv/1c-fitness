"""Business boundary and provenance checks for explicit import actuality."""

import importlib.util
import sys
import unittest
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))
from cutoff_contract import resolve_cutoff


class CutoffContractTests(unittest.TestCase):
    def test_legacy_default_keeps_exact_backup_second(self):
        run = {}
        result = resolve_cutoff(run, {"backup_finish_at": "2026-06-30 23:27:03"})
        self.assertEqual(result["cutoff_at"], "2026-06-30 23:27:03")
        self.assertEqual(result["backup_finish_at"], result["cutoff_at"])
        self.assertEqual(result["date_stamp"], "20260630")

    def test_next_evening_crosses_month_without_changing_provenance(self):
        run = {"effective_offset_days": 1}
        result = resolve_cutoff(run, {"backup_finish_at": "2026-06-30 23:27:03"})
        self.assertEqual(result["cutoff_at"], "2026-07-01 23:27:03")
        self.assertEqual(result["backup_finish_at"], "2026-06-30 23:27:03")
        self.assertEqual(result["cutoff_date"], "2026-07-01")
        self.assertEqual(result["date_stamp"], "20260701")
        self.assertEqual(result["effective_shift_seconds"], "86400")

    def test_exact_evening_is_configurable_to_second(self):
        result = resolve_cutoff({"effective_at": "2026-09-21 21:15:07"},
                                {"backup_finish_at": "2026-09-20 20:34:12"})
        self.assertEqual(result["cutoff_at"], "2026-09-21 21:15:07")
        self.assertEqual(result["backup_finish_at"], "2026-09-20 20:34:12")

    def test_stale_or_conflicting_dates_cannot_pass(self):
        backup = {"backup_finish_at": "2026-06-30 23:27:03"}
        for field, value in [
            ("cutoff_at", "2026-06-30 23:27:03"), ("date_stamp", "20260630"),
            ("cutoff_date", "2026-06-30"), ("backup_finish_at", "2026-07-01 23:27:03"),
            ("membership_cutoff_at", "2026-06-30 23:27:03"),
            ("services_cutoff_at", "2026-06-30 23:27:03"),
            ("photos_cutoff_at", "2026-06-30 23:27:03"),
        ]:
            with self.subTest(field=field), self.assertRaises(ValueError):
                resolve_cutoff({"effective_offset_days": 1, field: value}, backup)
        with self.assertRaises(ValueError):
            resolve_cutoff({"cutoff_at": "2026-07-01 23:27:03"}, backup)
        with self.assertRaises(ValueError):
            resolve_cutoff({"effective_at": "2026-07-01 23:27:03", "effective_offset_days": 1}, backup)

    def test_invalid_datetime_and_offsets_fail_before_sql(self):
        for value in ("2026-09-21", "2026-09-21 24:00:00", "2026-02-30 00:00:00", "2026-9-21 1:00:00"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                resolve_cutoff({"effective_at": value}, {"backup_finish_at": "2026-09-20 20:00:00"})
        for value in ("NaN", "Infinity", "invalid", "0.00000001"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                resolve_cutoff({"effective_offset_days": value}, {"backup_finish_at": "2026-09-20 20:00:00"})


if __name__ == "__main__":
    unittest.main()
