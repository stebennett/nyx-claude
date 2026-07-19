# devtools

Developer-workflow automation skills for Claude Code.

## renovator

Autonomously drains a repository's open [Renovate](https://docs.renovatebot.com/) dependency PRs. Each run is one full pass over the queue and is safe to run repeatedly (e.g. under `/loop`).

**v1 behavior:**
- **Merges** patch/minor Renovate PRs whose CI is green and whose branch is cleanly mergeable — one merge per pass, then rebases the rest so the next pass continues.
- **Parks** everything else — major versions, red CI, conflicts — with a label and a sticky status comment for review. (Automating those is planned for v2.)

Every candidate is classified independently twice — once by the orchestrator, once by the `renovate-merger` agent right before it merges — so an unattended merge only ever happens on a PR both agree is a safe, green, bot-authored patch/minor.

### v2 — automatic fix-loops (major upgrades & red CI)

For the PRs v1 parks, renovator can work them to green inside a git worktree before merging or handing back:

- **Red CI on a patch/minor PR** → `renovate-ci-fixer` (sonnet) discovers the repo's test recipe (from CLAUDE.md / README / manifests / the GitHub workflow), iterates locally, and confirms on remote CI. If it reaches green by **adaptation only** (no test edits), the PR auto-merges via the same `renovate-merger` gate as v1. If the fix had to edit a test, it parks for your review instead.
- **Major-version PR** → `renovate-major-upgrader` (opus) reads the changelog/release notes for breaking changes first, then runs the same loop. A green result **always parks for your diff review** — a major upgrade never auto-merges.
- **Stuck** (attempts exhausted, or CI can't be reproduced locally) → parked with a summary of what was tried.

renovator never "fakes green": it will not delete/skip a test or suppress an error to force a merge — that becomes a park for a human.

New labels: `renovator:fixing` (a fix-loop is in progress), `renovator:review` (fixed, awaiting your diff review).

### Requirements
- `gh` CLI, authenticated (`gh auth status`).
- `jq`.
- The repo's CI reports status checks to GitHub.

### Usage
Invoke the `renovator` skill from within the target repository (its `origin` remote is the repo acted on).

### Configuration (optional)
Run `/renovator-init` to scaffold `.claude/renovator.json` interactively — it detects the Renovate bot login from your open PRs and prompts for the key knobs. Or create the file by hand:

Create `.claude/renovator.json` in the repo root to override defaults:

    {
      "renovate_authors": ["renovate[bot]"],
      "merge_method": "squash",
      "require_checks": true,
      "max_merges_per_pass": 1,
      "enable_ci_fixer": true,
      "enable_major_upgrader": true,
      "fix_attempts": 3
    }

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | author logins that count as Renovate. Set this for self-hosted / on-prem Renovate whose bot login differs. |
| `merge_method` | `"squash"` | merge method passed to `gh pr merge`. |
| `require_checks` | `true` | when true, a PR with zero CI checks is skipped rather than merged. |
| `max_merges_per_pass` | `1` | merges performed per pass; the rest are rebased and picked up next pass. |
| `enable_ci_fixer` | `true` | attempt automatic red-CI fixes on patch/minor PRs |
| `enable_major_upgrader` | `true` | attempt automatic major-version upgrades |
| `fix_attempts` | `3` | max push→remote-CI cycles a fixer runs before parking |

> ⚠️ Setting `require_checks: false` lets renovator merge dependency PRs that have **no CI signal at all**, unattended. Only relax it for repos where that is genuinely safe.

### PR annotations
`renovator` labels each PR it touches: `renovator:working` (momentary lock while merging a green PR), `renovator:skipped` (transient; will retry), `renovator:fixing` (a fix-loop is in progress), `renovator:review` (fixed by renovator; awaiting your diff review), and `renovator:parked` (needs a human). It maintains a single sticky status comment per PR.
