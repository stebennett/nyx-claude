# Design: `token-usage` plugin

**Date:** 2026-07-24
**Status:** Approved

## Purpose

Report how many tokens — input, output, cache read, cache write — have been
used per model over a recent time window, aggregated across all Claude Code
projects on the machine. Answers the question "how many tokens have I used this
week, broken down by model?"

## Data source

Claude Code writes one JSONL transcript per session under
`~/.claude/projects/<project-dir>/<session-id>.jsonl`. Each assistant turn is a
line with:

- `type`: `"assistant"`
- `timestamp`: ISO-8601 UTC, e.g. `"2026-07-09T12:11:11.677Z"`
- `message.model`: e.g. `"claude-opus-4-8"`, `"claude-fable-5"`
- `message.id`: unique per API response
- `message.usage`: object with
  - `input_tokens`
  - `output_tokens`
  - `cache_read_input_tokens`
  - `cache_creation_input_tokens` (the "cache write" total; already sums the
    1h and 5m ephemeral buckets)

No external API is required — the report is computed entirely from these local
files.

## Scope decisions

- **Coverage:** all projects (every `*.jsonl` under `~/.claude/projects/`),
  aggregated into a single table. No per-project breakdown.
- **Metrics:** the four raw token counts per model, plus totals. **Tokens only
  — no estimated cost column** (avoids maintaining a price table that drifts).
- **Window:** defaults to the last 7 days (rolling, ending now); accepts an
  optional override argument such as `14d` or `30d`.
- **Engine:** a bundled Python script does the parsing and aggregation. The
  skill just runs it and presents the output — Claude never hand-sums the
  transcripts (fast, reliable, cheap on context).

## Layout

New plugin in this marketplace:

```
plugins/token-usage/
  .claude-plugin/plugin.json          # manifest: name, version, description, author
  skills/token-usage/SKILL.md         # triggers + how to run the script and present output
  skills/token-usage/report_usage.py  # the engine
```

Plus a new entry in `.claude-plugin/marketplace.json` so Claude Code discovers
the plugin.

## The engine (`report_usage.py`)

- **Runtime:** `python3` standard library only — no third-party dependencies.
- **Argument:** optional window token. Format `<N>d` (days), e.g. `7d`
  (default), `14d`, `30d`. Invalid input → clear error message and non-zero
  exit.
- **Scan:** glob every `*.jsonl` under `~/.claude/projects/`, read line by
  line. Lines that are not valid JSON are silently skipped (transcripts can
  contain partial/interrupted writes).
- **Select:** lines that are assistant messages carrying a `message.usage`
  block, with `timestamp >= now − window`. Timestamps parsed as UTC.
- **Dedup:** track seen `message.id` values; count each unique id's usage once.
  Prevents double-counting when a session has been resumed, forked, or copied
  and the same API response appears in more than one transcript. Lines with no
  `message.id` are counted individually (no dedup key available).
- **Aggregate:** per model, sum the four token counts.
- **Sort:** models by total tokens descending.

### Output

Plain-text table with thousands separators, a header line stating the window
and date range and scope, and a `TOTAL` row:

```
Token usage — last 7 days (2026-07-17 → 2026-07-24), all projects

Model              Input    Output  Cache Read  Cache Write        Total
claude-opus-4-8  123,456    45,678  12,345,678      234,567   12,749,379
claude-fable-5    12,345     6,789     456,789       12,345      488,268
TOTAL            135,801    52,467  12,802,467      246,912   13,237,647
```

Column widths adapt to the data. `Total` per row = sum of the four counts.

## Error handling

- `~/.claude/projects/` missing or contains no matching lines in the window →
  print a clear "No usage data found for the last N days." message, exit 0.
- A model field that is absent or null → grouped under `unknown`.
- A malformed JSON line → skipped without failing the run.
- Invalid window argument → error message to stderr, non-zero exit.

## SKILL.md

- **Frontmatter:** `name: token-usage`; description triggering on phrasings
  like "how many tokens", "token usage", "usage by model", "token report",
  "tokens used this week".
- **Body:** instruct Claude to run
  `python3 "${CLAUDE_PLUGIN_ROOT}/skills/token-usage/report_usage.py" [window]`
  (default no arg = last 7 days; pass e.g. `30d` to override), then present the
  returned table to the user. Note the optional window argument in case the
  user asks for a different period.

## Out of scope (YAGNI)

- Cost estimation / pricing.
- Per-project or per-session breakdowns.
- Charts or non-tabular output.
- Filtering by a specific model or project.
- Calendar-week (vs rolling) windows.

These can be added later if wanted, but are deliberately excluded from the
first version.
