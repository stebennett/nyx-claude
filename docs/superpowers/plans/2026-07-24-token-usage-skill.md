# token-usage Plugin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a `token-usage` plugin whose skill reports Claude Code token usage (input, output, cache read, cache write) per model across all projects over a time window (default last 7 days).

**Architecture:** A dependency-free `python3` script (`report_usage.py`) parses local session transcripts under `~/.claude/projects/**/*.jsonl`, dedups assistant messages by id, filters by timestamp, aggregates the four token counts per model, and prints a formatted table. A thin `SKILL.md` tells Claude to run the script and present its output. The plugin is registered in the marketplace manifest.

**Tech Stack:** Python 3 standard library only (`json`, `pathlib`, `datetime`, `sys`, `argparse`-free CLI); `unittest` for tests; Markdown/JSON plugin manifests.

## Global Constraints

- **Python: standard library only.** No third-party imports in `report_usage.py` — it must run on stock macOS `python3`.
- **Python version floor: 3.9** (stock macOS). Do NOT rely on `datetime.fromisoformat` handling a trailing `Z` — normalize `Z` → `+00:00` before parsing.
- **Tests use `unittest`** (stdlib), not pytest — the repo has no third-party test tooling.
- **Skill paths use `${CLAUDE_PLUGIN_ROOT}`** so they resolve regardless of install location.
- **Manifests:** `plugin.json` fields and shape match `plugins/code-safely-plugin/.claude-plugin/plugin.json`; author is `{ "name": "Steve Bennett" }`. Every new plugin MUST be registered in `.claude-plugin/marketplace.json` or it is not discovered.
- **All new script code lives under** `plugins/token-usage/skills/token-usage/`.

---

## File Structure

- `plugins/token-usage/.claude-plugin/plugin.json` — plugin manifest.
- `plugins/token-usage/skills/token-usage/SKILL.md` — skill: triggers + run instructions.
- `plugins/token-usage/skills/token-usage/report_usage.py` — the engine (parsing, aggregation, formatting, CLI).
- `plugins/token-usage/skills/token-usage/test_report_usage.py` — unittest suite.
- `.claude-plugin/marketplace.json` — modified to register the plugin.

`report_usage.py` is written as importable pure functions (`parse_window`, `parse_timestamp`, `extract_usage`, `aggregate`, `format_table`, `iter_records`, `main`) so each unit is tested without real files, with `main` accepting injectable `root` and `now` for integration tests.

---

### Task 1: Parsing helpers (`parse_window`, `parse_timestamp`)

**Files:**
- Create: `plugins/token-usage/skills/token-usage/report_usage.py`
- Test: `plugins/token-usage/skills/token-usage/test_report_usage.py`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `parse_window(arg: Optional[str]) -> int` — returns a positive day count. `None`/empty → `7`. Accepts `"<N>d"` or bare `"<N>"` (N ≥ 1). Raises `ValueError` on anything else.
  - `parse_timestamp(ts: str) -> datetime` — parses an ISO-8601 string (with trailing `Z` or explicit offset) into a timezone-aware UTC `datetime`.

- [ ] **Step 1: Write the failing test**

Create `plugins/token-usage/skills/token-usage/test_report_usage.py`:

```python
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'report_usage'` (or `AttributeError` once the file exists but functions don't).

- [ ] **Step 3: Write minimal implementation**

Create `plugins/token-usage/skills/token-usage/report_usage.py`:

```python
#!/usr/bin/env python3
"""Report Claude Code token usage per model over a time window.

Parses local session transcripts under ~/.claude/projects/**/*.jsonl and prints
a table of input / output / cache-read / cache-write tokens grouped by model.
Standard library only.
"""
from datetime import datetime, timezone


def parse_window(arg):
    """Return a positive integer day count. None/empty -> 7.

    Accepts '<N>d' or a bare '<N>' with N >= 1. Raises ValueError otherwise.
    """
    if arg is None or arg == "":
        return 7
    text = arg.strip().lower()
    if text.endswith("d"):
        text = text[:-1]
    if not text.isdigit():
        raise ValueError("window must be a positive number of days, e.g. '7d'")
    days = int(text)
    if days < 1:
        raise ValueError("window must be at least 1 day")
    return days


def parse_timestamp(ts):
    """Parse an ISO-8601 timestamp (trailing 'Z' allowed) to an aware UTC datetime."""
    normalized = ts.replace("Z", "+00:00")
    dt = datetime.fromisoformat(normalized)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: PASS (6 tests / 2 classes).

- [ ] **Step 5: Commit**

```bash
git add plugins/token-usage/skills/token-usage/report_usage.py plugins/token-usage/skills/token-usage/test_report_usage.py
git commit -m "feat(token-usage): add window and timestamp parsing helpers"
```

---

### Task 2: Usage extraction and aggregation (`extract_usage`, `aggregate`)

**Files:**
- Modify: `plugins/token-usage/skills/token-usage/report_usage.py`
- Test: `plugins/token-usage/skills/token-usage/test_report_usage.py`

**Interfaces:**
- Consumes: `parse_timestamp` (Task 1).
- Produces:
  - `extract_usage(record: dict) -> Optional[dict]` — for an assistant record carrying `message.usage`, returns `{"id", "model", "timestamp", "input", "output", "cache_read", "cache_write"}`; otherwise `None`. Missing model → `"unknown"`; missing `timestamp` → `None`; counts default to `0`.
  - `aggregate(records: Iterable[dict], cutoff: datetime) -> dict` — returns `{model: {"input", "output", "cache_read", "cache_write"}}`. Dedups by non-null `id`; drops records older than `cutoff` or with unparseable timestamps.

- [ ] **Step 1: Write the failing test**

Append to `test_report_usage.py`:

```python
from datetime import timedelta


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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: FAIL — `AttributeError: module 'report_usage' has no attribute 'extract_usage'`.

- [ ] **Step 3: Write minimal implementation**

Append to `report_usage.py`:

```python
def extract_usage(record):
    """Return a normalized usage dict for an assistant record, or None."""
    if not isinstance(record, dict) or record.get("type") != "assistant":
        return None
    message = record.get("message") or {}
    usage = message.get("usage")
    if not isinstance(usage, dict):
        return None
    timestamp = record.get("timestamp")
    if not timestamp:
        return None
    return {
        "id": message.get("id"),
        "model": message.get("model") or "unknown",
        "timestamp": timestamp,
        "input": usage.get("input_tokens") or 0,
        "output": usage.get("output_tokens") or 0,
        "cache_read": usage.get("cache_read_input_tokens") or 0,
        "cache_write": usage.get("cache_creation_input_tokens") or 0,
    }


def aggregate(records, cutoff):
    """Sum token counts per model, deduping by id and dropping records before cutoff."""
    seen = set()
    totals = {}
    for record in records:
        usage = extract_usage(record)
        if usage is None:
            continue
        try:
            when = parse_timestamp(usage["timestamp"])
        except (ValueError, TypeError):
            continue
        if when < cutoff:
            continue
        mid = usage["id"]
        if mid is not None:
            if mid in seen:
                continue
            seen.add(mid)
        bucket = totals.setdefault(
            usage["model"],
            {"input": 0, "output": 0, "cache_read": 0, "cache_write": 0},
        )
        for key in ("input", "output", "cache_read", "cache_write"):
            bucket[key] += usage[key]
    return totals
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: PASS (all Task 1 + Task 2 tests).

- [ ] **Step 5: Commit**

```bash
git add plugins/token-usage/skills/token-usage/report_usage.py plugins/token-usage/skills/token-usage/test_report_usage.py
git commit -m "feat(token-usage): extract and aggregate per-model usage"
```

---

### Task 3: Table formatting (`format_table`)

**Files:**
- Modify: `plugins/token-usage/skills/token-usage/report_usage.py`
- Test: `plugins/token-usage/skills/token-usage/test_report_usage.py`

**Interfaces:**
- Consumes: the `totals` dict shape from `aggregate` (Task 2).
- Produces:
  - `format_table(totals: dict, days: int, start: date, end: date) -> str` — a multi-line string: a header line naming the window/date-range/scope, a column header row (`Model  Input  Output  Cache Read  Cache Write  Total`), one row per model sorted by row total descending, and a `TOTAL` row. Integers are thousands-separated. Assumes `totals` is non-empty (empty is handled in `main`).

- [ ] **Step 1: Write the failing test**

Append to `test_report_usage.py`:

```python
from datetime import date


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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: FAIL — `AttributeError: module 'report_usage' has no attribute 'format_table'`.

- [ ] **Step 3: Write minimal implementation**

Append to `report_usage.py`:

```python
_COLUMNS = [
    ("model", "Model"),
    ("input", "Input"),
    ("output", "Output"),
    ("cache_read", "Cache Read"),
    ("cache_write", "Cache Write"),
    ("total", "Total"),
]


def _row_total(counts):
    return counts["input"] + counts["output"] + counts["cache_read"] + counts["cache_write"]


def format_table(totals, days, start, end):
    """Render the aggregated totals as a plain-text table (non-empty totals)."""
    rows = []
    for model in sorted(totals, key=lambda m: _row_total(totals[m]), reverse=True):
        counts = totals[model]
        rows.append({"model": model, **counts, "total": _row_total(counts)})

    grand = {key: sum(r[key] for r in rows) for key in ("input", "output", "cache_read", "cache_write", "total")}
    grand["model"] = "TOTAL"
    rows.append(grand)

    def cell(row, key):
        value = row[key]
        return value if key == "model" else "{:,}".format(value)

    widths = {}
    for key, label in _COLUMNS:
        widths[key] = max([len(label)] + [len(cell(row, key)) for row in rows])

    def render(row, align_left_first=True):
        parts = []
        for i, (key, _label) in enumerate(_COLUMNS):
            text = cell(row, key)
            if i == 0:
                parts.append(text.ljust(widths[key]))
            else:
                parts.append(text.rjust(widths[key]))
        return "  ".join(parts).rstrip()

    header_cells = []
    for i, (key, label) in enumerate(_COLUMNS):
        header_cells.append(label.ljust(widths[key]) if i == 0 else label.rjust(widths[key]))
    header_row = "  ".join(header_cells).rstrip()

    lines = [
        "Token usage — last {} days ({} → {}), all projects".format(days, start, end),
        "",
        header_row,
    ]
    lines.extend(render(row) for row in rows)
    return "\n".join(lines)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: PASS (all tests through Task 3).

- [ ] **Step 5: Commit**

```bash
git add plugins/token-usage/skills/token-usage/report_usage.py plugins/token-usage/skills/token-usage/test_report_usage.py
git commit -m "feat(token-usage): render aggregated totals as a table"
```

---

### Task 4: File scan and CLI glue (`iter_records`, `main`)

**Files:**
- Modify: `plugins/token-usage/skills/token-usage/report_usage.py`
- Test: `plugins/token-usage/skills/token-usage/test_report_usage.py`

**Interfaces:**
- Consumes: `parse_window`, `aggregate`, `format_table` (Tasks 1–3).
- Produces:
  - `iter_records(root: Path) -> Iterator[dict]` — yields parsed JSON objects from every `*.jsonl` under `root`, skipping blank lines, malformed JSON, and unreadable files.
  - `main(argv: List[str], root: Path = None, now: datetime = None, out=sys.stdout, err=sys.stderr) -> int` — orchestrates: parse window (bad → message to `err`, return `2`); default `root` = `~/.claude/projects`, default `now` = current UTC; missing root or empty totals → "No usage data found for the last N days." to `out`, return `0`; otherwise print the table, return `0`.

- [ ] **Step 1: Write the failing test**

Append to `test_report_usage.py`:

```python
import io
import json
import tempfile
from pathlib import Path


class TestIterRecords(unittest.TestCase):
    def test_reads_jsonl_and_skips_malformed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            sub = root / "proj"
            sub.mkdir()
            (sub / "a.jsonl").write_text(
                json.dumps({"type": "assistant", "n": 1}) + "\n"
                + "not json\n"
                + "\n"
                + json.dumps({"type": "user", "n": 2}) + "\n"
            )
            records = list(ru.iter_records(root))
            self.assertEqual([r["n"] for r in records], [1, 2])


class TestMain(unittest.TestCase):
    def _run(self, argv, root, now):
        out, err = io.StringIO(), io.StringIO()
        code = ru.main(argv, root=root, now=now, out=out, err=err)
        return code, out.getvalue(), err.getvalue()

    def test_reports_table(self):
        now = datetime(2026, 7, 24, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "s.jsonl").write_text(json.dumps(_assistant(
                "a", "claude-opus-4-8", "2026-07-20T00:00:00Z", inp=100, out=200)) + "\n")
            code, out, err = self._run([], root, now)
        self.assertEqual(code, 0)
        self.assertIn("claude-opus-4-8", out)
        self.assertIn("last 7 days", out)

    def test_window_override_excludes_old(self):
        now = datetime(2026, 7, 24, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "s.jsonl").write_text(json.dumps(_assistant(
                "a", "opus", "2026-07-10T00:00:00Z", inp=100)) + "\n")
            # 7-day default excludes Jul 10; 30d includes it.
            code7, out7, _ = self._run([], root, now)
            code30, out30, _ = self._run(["30d"], root, now)
        self.assertIn("No usage data", out7)
        self.assertIn("opus", out30)

    def test_missing_root(self):
        now = datetime(2026, 7, 24, tzinfo=timezone.utc)
        code, out, err = self._run([], Path("/no/such/dir/xyz"), now)
        self.assertEqual(code, 0)
        self.assertIn("No usage data", out)

    def test_bad_window(self):
        now = datetime(2026, 7, 24, tzinfo=timezone.utc)
        with tempfile.TemporaryDirectory() as tmp:
            code, out, err = self._run(["7w"], Path(tmp), now)
        self.assertEqual(code, 2)
        self.assertIn("window", err.lower())
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: FAIL — `AttributeError: module 'report_usage' has no attribute 'iter_records'`.

- [ ] **Step 3: Write minimal implementation**

Add `import json`, `import sys` and `from pathlib import Path` near the top of `report_usage.py` (below the existing `datetime` import), then append:

```python
def iter_records(root):
    """Yield parsed JSON objects from every *.jsonl under root, skipping bad lines/files."""
    for path in sorted(Path(root).rglob("*.jsonl")):
        try:
            with path.open("r", encoding="utf-8") as handle:
                for line in handle:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        yield json.loads(line)
                    except json.JSONDecodeError:
                        continue
        except OSError:
            continue


def main(argv, root=None, now=None, out=None, err=None):
    from datetime import timedelta

    if out is None:
        out = sys.stdout
    if err is None:
        err = sys.stderr
    if now is None:
        now = datetime.now(timezone.utc)
    if root is None:
        root = Path.home() / ".claude" / "projects"

    try:
        days = parse_window(argv[0] if argv else None)
    except ValueError as exc:
        print("error: {}".format(exc), file=err)
        return 2

    cutoff = now - timedelta(days=days)

    root = Path(root)
    totals = aggregate(iter_records(root), cutoff) if root.exists() else {}
    if not totals:
        print("No usage data found for the last {} days.".format(days), file=out)
        return 0

    print(format_table(totals, days, cutoff.date(), now.date()), file=out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: PASS (full suite).

- [ ] **Step 5: Smoke-test against real transcripts**

Run: `python3 plugins/token-usage/skills/token-usage/report_usage.py`
Expected: a table with real models (e.g. `claude-opus-4-8`, `claude-fable-5`) and a `TOTAL` row, OR "No usage data found for the last 7 days." Then try an override:
Run: `python3 plugins/token-usage/skills/token-usage/report_usage.py 30d`
Expected: header reads "last 30 days".

- [ ] **Step 6: Commit**

```bash
git add plugins/token-usage/skills/token-usage/report_usage.py plugins/token-usage/skills/token-usage/test_report_usage.py
git commit -m "feat(token-usage): scan transcripts and add CLI entry point"
```

---

### Task 5: Plugin manifest, skill, and marketplace registration

**Files:**
- Create: `plugins/token-usage/.claude-plugin/plugin.json`
- Create: `plugins/token-usage/skills/token-usage/SKILL.md`
- Modify: `.claude-plugin/marketplace.json`

**Interfaces:**
- Consumes: `report_usage.py` CLI (Task 4).
- Produces: a discoverable, installable `token-usage` plugin exposing the `token-usage` skill.

- [ ] **Step 1: Write the plugin manifest**

Create `plugins/token-usage/.claude-plugin/plugin.json`:

```json
{
  "name": "token-usage",
  "version": "0.1.0",
  "description": "Report Claude Code token usage (input, output, cache read, cache write) per model across all projects over a time window (default last 7 days).",
  "author": {
    "name": "Steve Bennett"
  }
}
```

- [ ] **Step 2: Write the skill**

Create `plugins/token-usage/skills/token-usage/SKILL.md`:

```markdown
---
name: token-usage
description: Use when the user asks how many tokens they have used, for a token usage report, or usage broken down by model (e.g. "how many tokens this week", "token usage by model", "tokens used in the last 30 days"). Reports input, output, cache-read, and cache-write tokens per model across all Claude Code projects.
---

# token-usage — report token usage by model

Report how many tokens have been used per model over a recent window, aggregated
across every Claude Code project on this machine.

## How to run

Run the bundled script with an optional window argument:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/skills/token-usage/report_usage.py" [WINDOW]
```

- No argument → last 7 days.
- `WINDOW` is `<N>d` or a bare number of days, e.g. `14d`, `30`, `90d`.

The script reads local session transcripts under `~/.claude/projects/`; it needs
no network access and only the Python 3 standard library.

## Presenting the result

Show the user the table the script prints verbatim (it already has a header
naming the window and date range, per-model rows, and a TOTAL row). If it prints
"No usage data found...", relay that. If the user asks for a different period,
re-run with the matching `WINDOW` argument.
```

- [ ] **Step 3: Register the plugin in the marketplace manifest**

In `.claude-plugin/marketplace.json`, add this object to the end of the `plugins` array (after the `devtools` entry, with a preceding comma):

```json
    {
      "name": "token-usage",
      "source": "./plugins/token-usage",
      "description": "Report Claude Code token usage (input, output, cache read, cache write) per model across all projects over a time window (default last 7 days)."
    }
```

- [ ] **Step 4: Validate JSON and skill wiring**

Run:
```bash
python3 -m json.tool .claude-plugin/marketplace.json > /dev/null && \
python3 -m json.tool plugins/token-usage/.claude-plugin/plugin.json > /dev/null && \
head -4 plugins/token-usage/skills/token-usage/SKILL.md && \
echo OK
```
Expected: no JSON errors, the SKILL.md frontmatter prints, and `OK`.

- [ ] **Step 5: Full test suite green**

Run: `cd plugins/token-usage/skills/token-usage && python3 -m unittest test_report_usage -v`
Expected: PASS (entire suite).

- [ ] **Step 6: Commit**

```bash
git add plugins/token-usage/.claude-plugin/plugin.json plugins/token-usage/skills/token-usage/SKILL.md .claude-plugin/marketplace.json
git commit -m "feat(token-usage): add plugin manifest, skill, and marketplace registration"
```

---

## Self-Review

**Spec coverage:**
- All-projects scope → `iter_records` globs all of `~/.claude/projects/` (Task 4). ✓
- Four token metrics + tokens only, no cost → `extract_usage`/`aggregate`/`format_table` (Tasks 2–3). ✓
- Default 7 days + override → `parse_window` + `main` window arg (Tasks 1, 4). ✓
- Bundled-script engine → `report_usage.py` run by SKILL.md (Tasks 1–5). ✓
- New plugin in marketplace → manifest + registration (Task 5). ✓
- Dedup by message id → `aggregate` (Task 2). ✓
- Error handling: missing dir / empty → no-data message (Task 4); malformed line skipped (`iter_records`, Task 4); unknown model (Task 2); bad window (Task 4). ✓
- Output: table, thousands separators, sorted desc, TOTAL row, window/date header (Task 3). ✓

**Placeholder scan:** No TBD/TODO; every code and command step is complete. ✓

**Type consistency:** `totals` shape `{model: {input, output, cache_read, cache_write}}` is produced by `aggregate` and consumed by `format_table` identically; the normalized usage dict keys (`id, model, timestamp, input, output, cache_read, cache_write`) match between `extract_usage` and `aggregate`; `main` uses `parse_window`, `iter_records`, `aggregate`, `format_table` with the signatures they were defined with. ✓
