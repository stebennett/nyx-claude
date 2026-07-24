#!/usr/bin/env python3
"""Report Claude Code token usage per model over a time window.

Parses local session transcripts under ~/.claude/projects/**/*.jsonl and prints
a table of input / output / cache-read / cache-write tokens grouped by model.
Standard library only.
"""
from datetime import datetime, timezone
import json
import sys
from pathlib import Path


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
        except (OSError, UnicodeDecodeError):
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
