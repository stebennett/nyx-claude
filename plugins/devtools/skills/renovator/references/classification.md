# Renovate PR classification

`renovator` sorts each open Renovate PR into ONE bucket from two axes — **bump type** and **CI status**.

## Bump type — from the PR title

Renovate titles are structured. Extract the old and new versions and compare them as semver `MAJOR.MINOR.PATCH`:

- `MAJOR` differs → **major**
- `MAJOR` equal, `MINOR` differs → **minor**
- `MAJOR` and `MINOR` equal, `PATCH` differs → **patch**

**Ambiguity rule (conservative):** if the old and new versions cannot BOTH be extracted and compared with confidence — digests, pinned SHAs, version ranges, non-semver tags, or a grouped PR whose members bump differently — classify as **major** (the park bucket). Never guess "safe".

**Grouped PRs** (several deps in one PR): if ANY member is major or unparseable, the whole PR is **major**.

When the title names only the new version, read the old version from the dependency's current entry in the manifest/lockfile on the base branch. If that cannot be read confidently, treat as ambiguous → **major**.

### Worked examples
| Title | old → new | bump |
|---|---|---|
| `Update dependency lodash to v4.17.21` | 4.17.20 → 4.17.21 (old from lockfile) | patch |
| `chore(deps): update react to 18.3.0` | 18.2.0 → 18.3.0 | minor |
| `Update dependency next to v15` | 14.2.0 → 15.0.0 | major |
| `fix(deps): update dependency axios from 1.6.2 to 1.6.8` | 1.6.2 → 1.6.8 | patch |
| `Update actions/checkout digest to a1b2c3d` | digest, no semver | major (ambiguous) |
| `Update dependency foo (major)` grouped with `bar (patch)` | mixed | major |

## CI status — from the check rollup
Each `statusCheckRollup` entry is either a **CheckRun** (has `status`+`conclusion`) or a legacy **StatusContext** (has `state`). Read `conclusion` (or `status` while still running) for CheckRuns and `state` for StatusContexts, then classify the rollup:
- **red** — any entry is `FAILURE`/`ERROR`/`CANCELLED`/`TIMED_OUT`/`ACTION_REQUIRED`/`STARTUP_FAILURE`.
- **pending** — no red, but any entry is still settling: `QUEUED`/`IN_PROGRESS`/`PENDING`/`WAITING`/`STALE`.
- **green** — no red, no pending, AND at least one entry is `SUCCESS`. `SKIPPED`/`NEUTRAL` entries are non-blocking but do not count as the required success.
- **no signal** — the rollup is empty, or has entries but none is `SUCCESS` (e.g. all `SKIPPED`/`NEUTRAL`): treat as zero-checks — **pending** when `require_checks` is true (default), otherwise **green** (the relaxed `require_checks` path).

> When `require_checks` is false, a patch/minor PR with zero checks resolves to green → `GREEN_SAFE` and is merged — this is the intended effect of relaxing `require_checks`. The `renovate-merger` agent applies the same `require_checks` rule as its final gate, so the two never disagree.

## Bucket = f(bump, CI)
|  | green | red | pending |
|---|---|---|---|
| **patch / minor** | `GREEN_SAFE` | `RED` | `PENDING` |
| **major / ambiguous** | `MAJOR` | `MAJOR` | `MAJOR` |

Bucket → action:
- `GREEN_SAFE` → dispatch `renovate-merger` (subject to `max_merges_per_pass`).
- `MAJOR` → park (v1) / dispatch major-upgrader (v2).
- `RED` → park (v1) / dispatch ci-fixer (v2).
- `PENDING` → skip this pass; re-evaluated next pass.
