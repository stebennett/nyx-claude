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

## pr-reviewer

Reviews a repository's open pull requests and merges the ones that are ready. Each invocation is one full pass over the queue and is safe to run repeatedly (e.g. under `/loop`). A three-lens agent panel (`requirements`, `correctness`, `craft`) reviews each candidate PR's diff independently, an adjudicator reconciles their findings into a single verdict, and the pass posts one GitHub review with inline comments before either requesting changes with concrete recommendations or approving and merging. `pr-reviewer` is a sibling to `renovator`, not a replacement: `renovator` owns dependency PRs, `pr-reviewer` owns everything else, and the two never touch the same PR.

### Usage
Invoke the `pr-reviewer` skill from within the target repository, or pass an argument naming a different target. Bare invocation (no argument) runs a queue pass over the current repo's open PRs; naming one PR reviews it directly, bypassing `require_label`, the `reviewer:parked` exclusion, `exclude_authors`, and all three triage skips (an unchanged head SHA, the `max_rounds` park, and a CI-pending defer). Two exclusions are **never** bypassed, in either mode: a draft, and an author in `renovate_authors` — naming such a PR is a hard stop, because a draft has not been offered for review yet, and a Renovate PR belongs to `renovator` — the two skills never touch the same PR. The `max_review_lines` ceiling and every merge gate also still apply in full.

| argument | `target_repo` | `target_pr` | mode |
|---|---|---|---|
| *(none)* | origin of the cwd repo | — | queue pass |
| `42` (all digits) | origin of the cwd repo | `42` | single PR |
| `https://github.com/o/r/pull/42` | `o/r` | `42` | single PR |
| `o/r#42` | `o/r` | `42` | single PR |
| `https://github.com/o/r` | `o/r` | — | queue pass |
| `git@github.com:o/r.git` | `o/r` | — | queue pass |
| `o/r` | `o/r` | — | queue pass |

A repo URL, bare `owner/repo`, or SSH remote names a target that is not the cwd's own repo. That target is cloned bloblessly (`--filter=blob:none`, no file contents until needed) into a scratch directory reused across the pass; the working directory's own repo is never fetched into, never branched, and never checked out against — it is invisible to a remote-target pass.

### The three lenses
Every candidate PR is reviewed by three independent agents, dispatched in parallel, each blind to the other two and to the diff outside its own lens:

| lens | question | blocks on |
|---|---|---|
| `requirements` | Does the diff do what the resolved requirements say — all of it, and nothing undisclosed? | A requirement with no implementing code; behaviour that contradicts stated intent; an undisclosed behavioural change no requirement asked for. |
| `correctness` | Edge cases, error paths, boundaries, concurrency, resource lifecycle — the failure modes a happy-path read misses. | A concrete failure scenario: named inputs or state that produce a stated wrong output or crash. |
| `craft` | Simplicity, style, and consistency with the surrounding code. | Needless complexity a reader must hold in their head; duplication of an existing utility instead of reuse; a convention break that would mislead the next reader into copying it. |

The craft lens's blocking bar is deliberately high, so most craft findings are advisory by design — calibration, not volume, is where that lens earns its keep.

### How it decides
`request-changes` requires at least one surviving blocking finding carrying a stated consequence; there is no other path to it — not volume of advisory findings, not a hunch. Otherwise the verdict is `approve`, and any surviving advisory findings still go out as inline comments on the approving review: an approve is the absence of anything that blocks, not the absence of comments.

### Merge gates
An `approve` verdict only reaches an unattended merge once all four gates hold: CI green and the PR cleanly mergeable, no unresolved human review thread, the diff within `max_merge_lines`, and merge permission held on the target repo. `pr-merger`, a separate agent, independently re-verifies the three gates where a wrong pass would cause a bad merge — CI green and cleanly mergeable, no unresolved human threads, and within `max_merge_lines` — so two independent agreements, the reviewing pass's and the merger's, gate every unattended merge; a disagreement between them always resolves by parking, never by merging anyway. Merge permission is established once, in preflight, rather than re-checked at merge time: lacking it can only fail a merge, never wrongly complete one, and `pr-merger` already handles that case by aborting rather than reporting success when `gh pr merge` exits non-zero.

Two distinct size ceilings apply, with different effects: a PR within `max_merge_lines` is reviewed fully but merged only if every other gate also holds; a PR over `max_merge_lines` but within `max_review_lines` is still reviewed fully and commented on, but never merged unattended. A PR over `max_review_lines` is parked unreviewed, with a review comment saying to split the PR — an honest refusal beats a shallow rubber-stamp of a diff too large to hold in mind.

### Self-review
GitHub rejects an `APPROVE` or `REQUEST_CHANGES` review event from a PR's own author. On a PR you authored, the review posts as a plain `COMMENT` instead, and the actual verdict travels in a hidden marker on the review body's first line (`<!-- pr-reviewer: verdict=... round=... sha=... -->`) rather than in GitHub's review state. Installing this repo's `github-app-identity` plugin gives `gh` a distinct App identity, so `pr-reviewer` posts as an account other than the one that opened the PR — restoring real `APPROVE` and `REQUEST_CHANGES` records even when it is reviewing its own work.

### Requirements
- `gh` CLI, authenticated (`gh auth status`).
- `jq`.
- `git`.

### Configuration
Create `.claude/pr-reviewer.json` in the **target repository's** root to override defaults — it is always read from the repo being reviewed, never from the working directory a remote-target pass happens to run in:

    {
      "renovate_authors": ["renovate[bot]"],
      "exclude_authors": [],
      "require_label": null,
      "max_reviews_per_pass": 3,
      "max_merges_per_pass": 1,
      "max_rounds": 3,
      "merge_method": "squash",
      "max_merge_lines": 800,
      "max_review_lines": 3000,
      "ignore_paths": ["*.lock", "package-lock.json", "**/generated/**"],
      "update_branch_after_merge": false,
      "clone_cache_dir": null
    }

| knob | default | meaning |
|---|---|---|
| `renovate_authors` | `["renovate[bot]"]` | authors excluded so `renovator` keeps its own queue |
| `exclude_authors` | `[]` | additional author logins to skip |
| `require_label` | `null` | when set, only PRs carrying this label are eligible |
| `max_reviews_per_pass` | `3` | PRs reviewed per pass |
| `max_merges_per_pass` | `1` | merges per pass |
| `max_rounds` | `3` | request-changes rounds before parking |
| `merge_method` | `"squash"` | method passed to `gh pr merge` |
| `max_merge_lines` | `800` | above this: review fully, never merge unattended |
| `max_review_lines` | `3000` | above this: park unreviewed with "split this PR" |
| `ignore_paths` | `["*.lock", "package-lock.json", "**/generated/**"]` | excluded from the diff and from both line counts |
| `update_branch_after_merge` | `false` | whether to `gh pr update-branch` remaining approved PRs after a merge |
| `clone_cache_dir` | `null` | persistent clone cache for remote targets; `null` uses the session scratchpad |

### PR annotations
`pr-reviewer` labels each PR it touches with one of two mutually exclusive labels: `reviewer:working` (a momentary lock held while one PR is being processed, so an overlapping run or a `/loop` re-entry cannot double-process it — released when the PR is done, always, including on failure) and `reviewer:parked` (terminal — excluded from future selection until a human clears the label by hand to re-enable review). Unlike `renovator`, it maintains no sticky status comment: GitHub's own reviews API already holds the round count, the last-reviewed SHA, and the prior verdict (via the hidden marker), so there is no separate state to keep in sync.
