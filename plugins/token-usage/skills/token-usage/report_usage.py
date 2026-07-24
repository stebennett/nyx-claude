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
