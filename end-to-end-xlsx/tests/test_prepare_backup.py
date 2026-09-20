from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
SPEC = importlib.util.spec_from_file_location("prepare_backup_test_module", ROOT / "scripts/prepare_backup.py")
assert SPEC is not None and SPEC.loader is not None
prepare = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(prepare)


def backup_header(position: int = 1):
    return {
        "Position": position, "BackupType": 1,
        "BackupFinishDate": datetime(2026, 6, 30, 23, 27, 3),
        "DatabaseName": "Fitness", "BackupSetGUID": "11111111-2222-3333-4444-555555555555",
        "CompatibilityLevel": 130,
    }


def backup_identity():
    return {
        "file_name": "new.bak", "size_bytes": 123, "sha256": "a" * 64,
        "database_name_in_backup": "Fitness", "backup_finish_at": "2026-06-30 23:27:03",
        "backup_set_uuid": "11111111-2222-3333-4444-555555555555", "position": 1,
    }


class EffectiveSnapshotTests(unittest.TestCase):
    def test_plus_one_day_preserves_evening_and_crosses_month(self):
        finish = datetime(2026, 6, 30, 23, 27, 3)
        self.assertEqual(prepare.effective_timestamp(finish, None, 1), datetime(2026, 7, 1, 23, 27, 3))
        self.assertEqual(finish, datetime(2026, 6, 30, 23, 27, 3))

    def test_explicit_time_and_default_backup_snapshot(self):
        finish = datetime(2026, 9, 20, 20, 17, 4)
        self.assertEqual(prepare.effective_timestamp(finish, None, None), finish)
        self.assertEqual(prepare.effective_timestamp(finish, "2026-09-21 22:00:00", None), datetime(2026, 9, 21, 22))

    def test_conflicting_options_and_ambiguous_precision_are_rejected(self):
        with self.assertRaisesRegex(ValueError, "mutually exclusive"):
            prepare.effective_timestamp(datetime(2026, 9, 20), "2026-09-21 21:00:00", 1)
        for value in ("2026-09-20T20:00:00+03:00", "2026-09-20 20:00:00.333", "2026-09-20", "2026-09-20T20:00:00"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                prepare.timestamp(value)


class BackupMetadataTests(unittest.TestCase):
    def test_selects_position_instead_of_first_backup(self):
        first = backup_header(1)
        second = backup_header(2)
        second["BackupFinishDate"] = datetime(2026, 9, 20, 20)
        self.assertIs(prepare.select_backup_header([first, second], 2), second)

    def test_missing_duplicate_incremental_and_damaged_sets_fail(self):
        cases = [([], 1), ([backup_header(), backup_header()], 1),
                 ([dict(backup_header(), BackupType=5)], 1),
                 ([dict(backup_header(), IsDamaged=True)], 1),
                 ([dict(backup_header(), BackupSetGUID=None)], 1)]
        for headers, position in cases:
            with self.subTest(headers=headers), self.assertRaises(ValueError):
                prepare.select_backup_header(headers, position)

    def test_new_manifest_keeps_structures_without_june_counts(self):
        expected = prepare.new_expected_manifest(backup_identity(), datetime(2026, 9, 21, 20), "fresh", "151350")
        self.assertEqual(expected["backup"]["backup_finish_at"], "2026-06-30 23:27:03")
        self.assertEqual(len(expected["files"]), 7)
        for name, spec in expected["files"].items():
            self.assertIn("20260921", name)
            self.assertNotIn("20260630", name)
            self.assertNotIn("data_rows", spec)
        isolated = next(spec for name, spec in expected["files"].items() if name.startswith("problem_"))
        self.assertEqual(isolated["contract_ids"], ["00000151350"])

    def test_manifest_can_omit_explicit_problem_case(self):
        expected = prepare.new_expected_manifest(backup_identity(), datetime(2026, 9, 21), "fresh", "")
        self.assertEqual(len(expected["files"]), 6)
        self.assertEqual(expected["problem_contracts"]["unique_total"], 0)

    def test_host_backup_fingerprint(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "backup.bak"
            path.write_bytes(b"abc")
            self.assertEqual(prepare.file_identity(path), (3, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
            path.write_bytes(b"")
            with self.assertRaisesRegex(ValueError, "empty"):
                prepare.file_identity(path)


class RestoreSafetyTests(unittest.TestCase):
    def test_replacement_reuses_registered_paths_and_counts_only_growth(self):
        requested = [
            {"logical_name": "data", "server_path": "/restoredata/new_1.mdf", "type": "D", "size_bytes": 300},
            {"logical_name": "log", "server_path": "/restoredata/new_2.ldf", "type": "L", "size_bytes": 50},
        ]
        existing = [
            {"logical_name": "data", "server_path": "/restoredata/old.mdf", "type": "D", "size_bytes": 200},
            {"logical_name": "log", "server_path": "/restoredata/old.ldf", "type": "L", "size_bytes": 100},
        ]
        moves, growth = prepare.replacement_moves(requested, existing, "/restoredata")
        self.assertEqual(growth, 100)
        self.assertEqual(moves[0]["server_path"], "/restoredata/old.mdf")
        self.assertEqual(moves[1]["server_path"], "/restoredata/old.ldf")
        sql, _ = prepare.restore_sql("Target", "/backup/new.bak", 1, moves, replace_existing=True)
        self.assertIn(", REPLACE", sql)
        for invalid_existing in (existing[:1], [dict(existing[0], server_path="/other/data.mdf"), existing[1]], [dict(existing[0], type="L"), existing[1]]):
            with self.subTest(existing=invalid_existing), self.assertRaises(ValueError):
                prepare.replacement_moves(requested, invalid_existing, "/restoredata")

    def test_replacement_rejects_unrecognized_databases_and_remote_sql(self):
        for database, server in (("master", "localhost"), ("LiveFitness", "127.0.0.1"), ("FitnessRestored_fixture", "sql.remote")):
            with self.subTest(database=database, server=server), self.assertRaises(ValueError):
                prepare.inspect_replacement(object(), database, server, [], "/restoredata")

    def test_multiple_logical_files_have_unique_moves_and_parameterized_paths(self):
        filelist = [
            {"Type": "D", "FileId": 1, "Size": 100, "LogicalName": "main'file"},
            {"Type": "D", "FileId": 3, "Size": 200, "LogicalName": "secondary"},
            {"Type": "L", "FileId": 2, "Size": 300, "LogicalName": "log"},
        ]
        moves = prepare.restore_moves(filelist, "NewBackup", "/restoredata")
        self.assertEqual([move["server_path"] for move in moves], ["/restoredata/NewBackup_1.mdf", "/restoredata/NewBackup_3.ndf", "/restoredata/NewBackup_2.ldf"])
        sql, parameters = prepare.restore_sql("NewBackup", "/backup/Fit's.bak", 2, moves)
        self.assertNotIn("Fit's", sql)
        self.assertNotIn("main'file", sql)
        self.assertEqual(parameters[:2], ["/backup/Fit's.bak", 2])
        self.assertIn("main'file", parameters)
        self.assertNotIn("REPLACE", sql)
        self.assertNotIn("DROP", sql)

    def test_unsafe_or_incomplete_filelists_rejected(self):
        data = {"Type": "D", "FileId": 1, "Size": 100, "LogicalName": "data"}
        log = {"Type": "L", "FileId": 2, "Size": 100, "LogicalName": "log"}
        for filelist, database, directory in [
            ([data, log], "../database", "/restoredata"),
            ([data, log], "database", "/restoredata/../data"),
            ([data], "database", "/restoredata"),
            ([data, dict(log, FileId=1)], "database", "/restoredata"),
            ([data, dict(log, Type="S")], "database", "/restoredata"),
        ]:
            with self.subTest(filelist=filelist, database=database, directory=directory), self.assertRaises(ValueError):
                prepare.restore_moves(filelist, database, directory)

    def test_restore_identity_requires_the_actual_uuid_and_latest_full_restore(self):
        expected = backup_identity()
        row = {
            "restore_history_id": 42, "state_desc": "ONLINE", "restore_type": "D",
            "database_name_in_backup": "Fitness", "backup_finish_at": datetime(2026, 6, 30, 23, 27, 3),
            "backup_set_uuid": expected["backup_set_uuid"], "backup_position": 1,
        }
        with patch.object(prepare, "query_dicts", return_value=[row]) as query:
            self.assertIs(prepare.verify_restored_backup(object(), "Target", expected), row)
            self.assertIn("ORDER BY history.restore_history_id DESC", query.call_args.args[1])
            self.assertEqual(query.call_args.args[2], ("Target",))
        for key, value in [("backup_set_uuid", "another-backup"), ("backup_finish_at", datetime(2026, 7, 1)), ("state_desc", "RESTORING"), ("restore_type", "L"), ("backup_position", 2)]:
            with self.subTest(key=key), patch.object(prepare, "query_dicts", return_value=[dict(row, **{key: value})]), self.assertRaises(RuntimeError):
                prepare.verify_restored_backup(object(), "Target", expected)
        with patch.object(prepare, "query_dicts", return_value=[]), self.assertRaisesRegex(RuntimeError, "provenance"):
            prepare.verify_restored_backup(object(), "Target", expected)


if __name__ == "__main__":
    unittest.main()
