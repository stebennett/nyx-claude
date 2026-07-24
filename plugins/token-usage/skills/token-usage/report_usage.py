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
