import importlib.util
import json
import stat
import tempfile
import unittest
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC
from pathlib import Path


SCRIPT = Path(__file__).parent.parent / "scripts" / "export-diagnostic-report.py"
SPEC = importlib.util.spec_from_file_location("report_export", SCRIPT)
assert SPEC and SPEC.loader
REPORT_EXPORT = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(REPORT_EXPORT)


class ReportExportTests(unittest.TestCase):
    def test_export_is_private_atomic_and_creates_directory_on_request(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "missing" / "reports"
            self.assertFalse(directory.exists())

            basename = REPORT_EXPORT.export_reports(
                {"report": {"schemaVersion": 1, "status": "passed"}, "text": "Status: passed"},
                directory,
            )

            export_directory = directory / basename
            json_path = export_directory / "report.json"
            text_path = export_directory / "report.md"
            self.assertEqual(json.loads(json_path.read_text()), {"schemaVersion": 1, "status": "passed"})
            self.assertEqual(text_path.read_text(), "Status: passed\n")
            self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(export_directory.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE(json_path.stat().st_mode), 0o600)
            self.assertEqual(stat.S_IMODE(text_path.stat().st_mode), 0o600)
            self.assertEqual(list(directory.glob(".*")), [])

    def test_rejects_symlinked_directory_component(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / "target"
            target.mkdir()
            link = root / "reports"
            link.symlink_to(target, target_is_directory=True)
            with self.assertRaises(OSError):
                REPORT_EXPORT.export_reports({"report": {}, "text": ""}, link)
            self.assertEqual(list(target.iterdir()), [])

    def test_concurrent_exports_use_distinct_complete_directories(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "reports"
            with ThreadPoolExecutor(max_workers=2) as executor:
                first_future = executor.submit(
                    REPORT_EXPORT.export_reports, {"report": {"run": 1}, "text": "one"}, directory
                )
                second_future = executor.submit(
                    REPORT_EXPORT.export_reports, {"report": {"run": 2}, "text": "two"}, directory
                )
                first = first_future.result()
                second = second_future.result()
            self.assertNotEqual(first, second)
            self.assertEqual(json.loads((directory / first / "report.json").read_text()), {"run": 1})
            self.assertEqual((directory / first / "report.md").read_text(), "one\n")
            self.assertEqual(json.loads((directory / second / "report.json").read_text()), {"run": 2})
            self.assertEqual((directory / second / "report.md").read_text(), "two\n")

    def test_publication_never_replaces_an_existing_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "reports"
            directory.mkdir()
            token = "fixedtoken"
            fixed_now = REPORT_EXPORT.datetime.now(UTC)
            timestamp = fixed_now.strftime("%Y%m%d-%H%M%S")
            basename = f"diagnostic-{timestamp}-{token}"
            existing = directory / basename
            existing.mkdir()
            marker = existing / "keep"
            marker.write_text("original")
            original_token_hex = REPORT_EXPORT.secrets.token_hex
            original_datetime = REPORT_EXPORT.datetime
            REPORT_EXPORT.datetime = type("FixedDateTime", (), {"now": staticmethod(lambda _: fixed_now)})
            REPORT_EXPORT.secrets.token_hex = lambda _: token
            try:
                with self.assertRaises(FileExistsError):
                    REPORT_EXPORT.export_reports({"report": {}, "text": ""}, directory)
            finally:
                REPORT_EXPORT.secrets.token_hex = original_token_hex
                REPORT_EXPORT.datetime = original_datetime
            self.assertEqual(marker.read_text(), "original")

    def test_rejects_unexpected_payload_without_creating_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary) / "reports"
            with self.assertRaises(ValueError):
                REPORT_EXPORT.export_reports({"report": {}, "text": "", "path": "/tmp"}, directory)
            self.assertFalse(directory.exists())


if __name__ == "__main__":
    unittest.main()
