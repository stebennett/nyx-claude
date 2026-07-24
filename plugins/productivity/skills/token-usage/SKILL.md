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
