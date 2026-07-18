# devtools

Developer-workflow automation skills for Claude Code.

## renovator

Autonomously drains a repository's open [Renovate](https://docs.renovatebot.com/) dependency PRs. Each run is one full pass over the queue and is safe to run repeatedly (e.g. under `/loop`).

**v1 behavior:**
- **Merges** patch/minor Renovate PRs whose CI is green and whose branch is cleanly mergeable — one merge per pass, then rebases the rest so the next pass continues.
- **Parks** everything else — major versions, red CI, conflicts — with a label and a sticky status comment for review. (Automating those is planned for v2.)

Every candidate is classified independently twice — once by the orchestrator, once by the `renovate-merger` agent right before it merges — so an unattended merge only ever happens on a PR both agree is a safe, green, bot-authored patch/minor.

### Requirements
- `gh` CLI, authenticated (`gh auth status`).
- `jq`.
- The repo's CI reports status checks to GitHub.

### Usage
Invoke the `renovator` skill from within the target repository (its `origin` remote is the repo acted on).

### Configuration (optional)
Create `.claude/renovator.json` in the repo root to override defaults:

    {
      "renovate_authors": ["renovate[bot]"],
      "merge_method": "squash",
      "require_checks": true,
      "max_merges_per_pass": 1
    }

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | author logins that count as Renovate. Set this for self-hosted / on-prem Renovate whose bot login differs. |
| `merge_method` | `"squash"` | merge method passed to `gh pr merge`. |
| `require_checks` | `true` | when true, a PR with zero CI checks is skipped rather than merged. |
| `max_merges_per_pass` | `1` | merges performed per pass; the rest are rebased and picked up next pass. |

### PR annotations
`renovator` labels each PR it touches — `renovator:working` (being processed / lock), `renovator:skipped` (transient, will retry), `renovator:parked` (needs review) — and maintains a single sticky status comment per PR.
