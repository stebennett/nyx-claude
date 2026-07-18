# renovator fix-loop doctrine

Shared by `renovate-ci-fixer` and `renovate-major-upgrader`. It defines how a fixer agent takes a Renovate PR that v1 parked and works it to green inside a worktree, bounded, then hands the outcome back to the `renovator` orchestrator. Your agent adds only its own front-loaded step (the major upgrader reads the changelog first); everything else is here.

You work ONE PR. You write code and run tests. You NEVER fake green. You never touch any PR but the one you were given, and you never merge, label, or comment — the orchestrator owns all of that.

## Input (from your dispatch)
- `pr` — the PR number.
- `bump` — `patch` | `minor` | `major`.
- `old_version` → `new_version` — the dependency transition.
- `fix_attempts` — max push→remote-CI cycles before you give up (default 3).
- `attempt` — which attempt this is (1-based); the orchestrator increments it across passes.

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
Run the recipe in the worktree. On failure, make an adaptation change (step 4) and re-run the failing check. This is your cheap inner loop — keep it local, no pushing. Cap yourself: if roughly ~10 local edits pass without the failure set shrinking, stop thrashing and move toward park.

### 4. Change-scope guardrails
- **Allowed:** change call sites, configuration, and application code to adapt to the new dependency version.
- **Tests — conditional:** you MAY edit a test ONLY when the dependency legitimately changed behavior (a renamed API, a changed default, a new required argument). Record a per-test justification in your `summary`. Set `touched_tests: true` if you edit ANY test file.
- **Forbidden — this is faking green, never do it:** deleting or skipping/`xfail`-ing a test to get past it; blanket suppress/ignore directives (`@ts-ignore`, broad `# noqa`, `eslint-disable`, `--no-verify`); loosening or removing an assertion without a documented dependency-behavior reason; commenting out failing code.
- If the only path to green you can find is a forbidden change, STOP and park — that is a human's call.

### 5. Confirm on remote CI
When the recipe passes locally, commit and push ONCE to the PR branch. Wait for remote CI to settle (`gh pr checks <pr>`).
- Remote green → outcome `green`.
- Remote red where local passed → read the failure, do ONE more local iteration (step 3) informed by it, then push again. Each push consumes one `fix_attempts`.

### 6. Bounding
`fix_attempts` (default 3) caps the push→remote-CI cycles. When they are used up and CI is still red, STOP: outcome `exhausted`. Do not keep pushing.

### 7. Fallback — never fake green
If you cannot faithfully reproduce the checks locally (missing toolchain; the workflow needs services/secrets/containers; self-hosted runners; the recipe won't start for environment reasons):
- Fall back to making your best-reasoned change, pushing, and reading remote CI (still bounded by `fix_attempts`).
- If even that is impractical (you cannot tell what to change without running it), STOP: outcome `cannot-reproduce`.
Never claim green you did not observe on remote CI.

### 8. Hand the outcome back
Return exactly this to the orchestrator (one JSON object, no prose):
`{ "pr": <n>, "outcome": "green" | "exhausted" | "cannot-reproduce", "touched_tests": <true|false>, "attempts": <k>, "summary": "<what you changed, and/or why it is stuck>" }`
- `green` — remote CI is green. The orchestrator decides merge vs review.
- `exhausted` — used all `fix_attempts`, still red; `summary` names the last failure.
- `cannot-reproduce` — could not establish a reliable check; `summary` says why.
