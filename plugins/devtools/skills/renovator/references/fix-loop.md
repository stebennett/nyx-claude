# renovator fix-loop doctrine

Shared by `renovate-ci-fixer` and `renovate-major-upgrader`. It defines how a fixer agent takes a Renovate PR that v1 parked and works it to green inside a worktree, bounded, then hands the outcome back to the `renovator` orchestrator. Your agent adds only its own front-loaded step (the major upgrader reads the changelog first); everything else is here.

You work ONE PR. You write code and run tests. You NEVER fake green. You never touch any PR but the one you were given, and you never merge, label, or comment — the orchestrator owns all of that.

## Input (from your dispatch)
- `pr` — the PR number.
- `bump` — `patch` | `minor` | `major`.
- `old_version` → `new_version` — the dependency transition.
- `fix_attempts` — max push→remote-CI cycles before you give up (default 3).
- `attempt` — how many push→remote-CI cycles have ALREADY been consumed on this PR by a prior interrupted dispatch (0 or absent on a fresh start). One dispatch owns the whole `fix_attempts` budget and normally runs to a terminal outcome; `attempt` exists only so a re-dispatch after an interruption (crash/timeout, or a Renovate rebase that reset the branch) does not exceed the total budget.

## Steps

### 1. Set up the worktree
Create a git worktree on the PR's head branch via the `superpowers:using-git-worktrees` skill. Work only inside it. Do not touch the main checkout.

### 2. Discover the test/build recipe
Find how to run the repo's checks locally, in priority order — stop at the first that yields runnable commands, but cross-check against the workflow files (they are what CI enforces):
1. `CLAUDE.md` / `AGENTS.md` — human-curated build/test/lint commands.
2. `README.md` / `CONTRIBUTING.md` — dev-setup and test instructions.
3. Project manifests — `package.json` scripts, `Makefile`/`justfile`, `pyproject.toml`/`tox.ini`, `cargo`, `go test ./...`.
4. `.github/workflows/*.yml` — the jobs triggered on this PR (`on: pull_request` / push to the default branch) and their `run:` steps + toolchain setup. This is what CI **actually enforces**.

Reconcile: use 1–3 for the ergonomic local commands, but make sure you reproduce what the workflow enforces. If they diverge, remote CI (step 5) is the final authority. If NO source yields a runnable recipe, go to step 7 (fallback).

### 3. Reproduce locally and iterate
Run the recipe in the worktree. On failure, make an adaptation change (step 4) and re-run the failing check. This is your cheap inner loop — keep it local, no pushing. Cap yourself: if about 10 local edits pass without the failure set shrinking, stop thrashing and terminate with outcome `needs-human`.

### 4. Change-scope guardrails
- **Allowed:** change call sites, configuration, and application code to adapt to the new dependency version. "Configuration" here means adapting config to the new dependency's real requirements (e.g. a required new option, an updated schema field) — NOT relaxing checks to get past a failure.
- **Tests — conditional:** you MAY edit a test ONLY when the dependency legitimately changed behavior (a renamed API, a changed default, a new required argument). Record a per-test justification in your `summary`. Set `touched_tests: true` if you edit ANY test file.
- **Forbidden — this is faking green, never do it:** deleting or skipping/`xfail`-ing a test to get past it; blanket suppress/ignore directives (`@ts-ignore`, broad `# noqa`, `eslint-disable`, `--no-verify`); loosening or removing an assertion without a documented dependency-behavior reason; commenting out failing code; relaxing check strictness at the CONFIG level to mask a failure — disabling a lint/type rule, lowering a coverage threshold, adding a skip/ignore-list entry, or raising a timeout to hide a real failure (these keep `touched_tests` false but still fake green).
- If the only path to green you can find is a forbidden change, STOP and return outcome `needs-human` — that is a human's call.

### 5. Confirm on remote CI
When the recipe passes locally, commit and push ONCE to the PR branch. Each push→CI cycle must add at least one NEW commit — do not amend or force-push over a commit from a previous cycle; the orchestrator counts your commits to track how much of the `fix_attempts` budget you have used. Wait for remote CI to settle (`gh pr checks <pr>`).
- Remote green → outcome `green`.
- Remote red where local passed → read the failure, do ONE more local iteration (step 3) informed by it, then push again. Each push consumes one `fix_attempts`.
- You stay in this one dispatch across all push→CI cycles, waiting for each remote result inline; you do not hand back between cycles.

### 6. Bounding
`fix_attempts` (default 3) caps the push→remote-CI cycles. Count both the pushes you make now and any already recorded in `attempt`; when the total reaches `fix_attempts` and CI is still red, STOP: outcome `exhausted`. Do not keep pushing.

### 7. Fallback — never fake green
If you cannot faithfully reproduce the checks locally (missing toolchain; the workflow needs services/secrets/containers; self-hosted runners; the recipe won't start for environment reasons):
- Fall back to making your best-reasoned change, pushing, and reading remote CI (still bounded by `fix_attempts`).
- If even that is impractical (you cannot tell what to change without running it), STOP: outcome `cannot-reproduce`.
Never claim green you did not observe on remote CI.

### 8. Hand the outcome back
Return exactly this to the orchestrator (one JSON object, no prose):
`{ "pr": <n>, "outcome": "green" | "exhausted" | "needs-human" | "cannot-reproduce", "touched_tests": <true|false>, "attempts": <k>, "summary": "<what you changed, and/or why it is stuck>" }`
- `green` — remote CI is green. The orchestrator decides merge vs review.
- `exhausted` — used all `fix_attempts`, still red; `summary` names the last failure.
- `needs-human` — reproducible but not safely fixable (a forbidden change would be required, or no safe fix found within the local budget); `summary` says what is blocking.
- `cannot-reproduce` — could not establish a reliable check; `summary` says why.
