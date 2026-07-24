import unittest
from datetime import datetime, timezone

import report_usage as ru


class TestParseWindow(unittest.TestCase):
    def test_default_is_seven(self):
        self.assertEqual(ru.parse_window(None), 7)
        self.assertEqual(ru.parse_window(""), 7)

    def test_days_suffix(self):
        self.assertEqual(ru.parse_window("30d"), 30)
        self.assertEqual(ru.parse_window("1d"), 1)

    def test_bare_number(self):
        self.assertEqual(ru.parse_window("14"), 14)

    def test_invalid_raises(self):
        for bad in ("abc", "0d", "-3d", "7w", "d"):
            with self.assertRaises(ValueError):
                ru.parse_window(bad)


class TestParseTimestamp(unittest.TestCase):
    def test_zulu_suffix(self):
        dt = ru.parse_timestamp("2026-07-09T12:11:11.677Z")
        self.assertEqual(dt, datetime(2026, 7, 9, 12, 11, 11, 677000, tzinfo=timezone.utc))

    def test_explicit_offset(self):
        dt = ru.parse_timestamp("2026-07-09T13:11:11+01:00")
        self.assertEqual(dt.astimezone(timezone.utc).hour, 12)


if __name__ == "__main__":
    unittest.main()
