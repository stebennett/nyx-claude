import unittest
from datetime import datetime, timezone, timedelta, date

import report_usage as ru


def _assistant(mid, model, ts, inp=0, out=0, cr=0, cw=0):
    return {
        "type": "assistant",
        "timestamp": ts,
        "message": {
            "id": mid,
            "model": model,
            "usage": {
                "input_tokens": inp,
                "output_tokens": out,
                "cache_read_input_tokens": cr,
                "cache_creation_input_tokens": cw,
            },
        },
    }


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


class TestExtractUsage(unittest.TestCase):
    def test_extracts_counts(self):
        u = ru.extract_usage(_assistant("a", "claude-opus-4-8", "2026-07-20T00:00:00Z",
                                        inp=10, out=20, cr=30, cw=40))
        self.assertEqual(u["input"], 10)
        self.assertEqual(u["output"], 20)
        self.assertEqual(u["cache_read"], 30)
        self.assertEqual(u["cache_write"], 40)
        self.assertEqual(u["model"], "claude-opus-4-8")
        self.assertEqual(u["id"], "a")

    def test_non_assistant_returns_none(self):
        self.assertIsNone(ru.extract_usage({"type": "user", "message": {"content": "hi"}}))

    def test_missing_usage_returns_none(self):
        self.assertIsNone(ru.extract_usage({"type": "assistant", "message": {"model": "x"}}))

    def test_missing_model_is_unknown(self):
        u = ru.extract_usage({"type": "assistant", "timestamp": "2026-07-20T00:00:00Z",
                              "message": {"usage": {"input_tokens": 1}}})
        self.assertEqual(u["model"], "unknown")

    def test_missing_timestamp_returns_none(self):
        self.assertIsNone(ru.extract_usage({"type": "assistant",
                                            "message": {"model": "x", "usage": {"input_tokens": 1}}}))


class TestAggregate(unittest.TestCase):
    def setUp(self):
        self.cutoff = datetime(2026, 7, 17, tzinfo=timezone.utc)

    def test_sums_per_model(self):
        records = [
            _assistant("a", "opus", "2026-07-20T00:00:00Z", inp=10, out=1),
            _assistant("b", "opus", "2026-07-21T00:00:00Z", inp=5, out=2),
            _assistant("c", "fable", "2026-07-22T00:00:00Z", inp=3, out=4),
        ]
        totals = ru.aggregate(records, self.cutoff)
        self.assertEqual(totals["opus"], {"input": 15, "output": 3, "cache_read": 0, "cache_write": 0})
        self.assertEqual(totals["fable"], {"input": 3, "output": 4, "cache_read": 0, "cache_write": 0})

    def test_dedups_by_id(self):
        records = [
            _assistant("dup", "opus", "2026-07-20T00:00:00Z", inp=10),
            _assistant("dup", "opus", "2026-07-20T00:00:00Z", inp=10),
        ]
        self.assertEqual(ru.aggregate(records, self.cutoff)["opus"]["input"], 10)

    def test_filters_before_cutoff(self):
        records = [_assistant("old", "opus", "2026-07-01T00:00:00Z", inp=99)]
        self.assertEqual(ru.aggregate(records, self.cutoff), {})

    def test_skips_unparseable_timestamp(self):
        records = [_assistant("bad", "opus", "not-a-date", inp=99)]
        self.assertEqual(ru.aggregate(records, self.cutoff), {})

    def test_null_id_not_deduped(self):
        records = [
            _assistant(None, "opus", "2026-07-20T00:00:00Z", inp=5),
            _assistant(None, "opus", "2026-07-20T00:00:00Z", inp=5),
        ]
        self.assertEqual(ru.aggregate(records, self.cutoff)["opus"]["input"], 10)


class TestFormatTable(unittest.TestCase):
    def _table(self):
        totals = {
            "claude-opus-4-8": {"input": 123456, "output": 45678, "cache_read": 12345678, "cache_write": 234567},
            "claude-fable-5": {"input": 12345, "output": 6789, "cache_read": 456789, "cache_write": 12345},
        }
        return ru.format_table(totals, 7, date(2026, 7, 17), date(2026, 7, 24))

    def test_header_names_window_and_scope(self):
        out = self._table()
        self.assertIn("last 7 days", out)
        self.assertIn("2026-07-17", out)
        self.assertIn("2026-07-24", out)
        self.assertIn("all projects", out)

    def test_has_column_headers(self):
        out = self._table()
        for col in ("Model", "Input", "Output", "Cache Read", "Cache Write", "Total"):
            self.assertIn(col, out)

    def test_thousands_separated(self):
        self.assertIn("12,345,678", self._table())

    def test_sorted_by_total_desc(self):
        out = self._table()
        self.assertLess(out.index("claude-opus-4-8"), out.index("claude-fable-5"))

    def test_total_row_sums_all(self):
        out = self._table()
        # opus total 12,749,379 + fable total 488,268 = 13,237,647
        self.assertIn("13,237,647", out)
        self.assertIn("TOTAL", out)


if __name__ == "__main__":
    unittest.main()
