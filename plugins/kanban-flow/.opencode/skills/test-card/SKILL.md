---
name: test-card
description: "Run full test suite, coverage, property tests, lint/types gates, and optional test levels in a worktree. Classify every blocker as product/test/environment/flake per DIAGNOSIS.md. Environment lifecycle with trap-guarded teardown. Never fixes code."
---

# test-card

Independently verify the card's work in its `worktree`. Run gates and report facts; never change
behaviour or fix anything. Every failure must be **actionable**: exact command, exact failing
test/rule, output excerpt.

Invoke and follow **superpowers:verification-before-completion**. You need `design.md` (test
strategy) and `implement.md`; skip the spec. When your dispatch carries level commands, also
read the `.opencode/doctrine/testing/LEVELS.md` and `.opencode/doctrine/testing/DIAGNOSIS.md`
doctrine paths it provides.

## Procedure (run inside the worktree)

1. **Full test suite** — `just test` when a justfile exists, else the toolchain runner (pytest,
   vitest).
2. **Coverage** — confirm coverage meets `coverage_target` (and any card-specific target from
   `design.md`).
3. **Property tests** — confirm Hypothesis invariant tests for the card's logic run and pass.
4. **Lint & types** — `just lint` when present, else ruff, type-check strict on the core logic
   layer, eslint, prettier, `tsc --noEmit` as applicable to the card.
5. **Test levels (only when your dispatch carries level commands).** For each level `design.md`'s
   `### Levels` block marks **selected**, run its dispatched command verbatim as a separate named
   gate:
   - **Zero tests is a failure.** A selected level whose run reports zero tests
     collected/executed is a blocker. If the runner's output exposes no count, the exit code
     stays authoritative and you record the unparseable count as an advisory — never a silent
     pass, never a false block.
   - **Environment lifecycle** for levels marked `needs_env`: run `env.up`, poll `env.ready`
     until it exits 0 (bounded — ~2 minutes max, report a blocker if it doesn't, classification
     `environment`), run the level(s), then run `env.down` **from a shell trap so teardown
     fires on exit, failure, and interrupt** (e.g. `trap '<env.down command>' EXIT` set before
     `env.up`).
   - **Contract guard.** If the branch diff touches a declared seam's `schema` path (seam list
     in your dispatch) and no contract level ran and passed, that is a blocker.
6. Capture the exact command and a short output excerpt for each gate.

## Judgment rules

- A non-zero exit code is a failure no matter how the output reads.
- A flaky test is a failing test — never re-run to green, report it with both outputs.
- Coverage numbers come from the coverage tool's report line, not estimation.
- If a gate can't run at all (missing tool, broken env), that is itself a blocker — report it,
  don't skip the gate.
- **Classify every blocker** per `DIAGNOSIS.md` as `product | test | environment | flake` —
  prove which before writing it; an environment blocker names the environment, not the code.

## Return

- `status: complete`, `gate: none` only if every gate above passes.
- `status: blocked` with `blockers` listing each failing command, its output excerpt, and its
  classification, otherwise. One blocker per distinct failure.
- `phase_doc` is `verify.md` with sections: `## Suite`, `## Coverage`, `## Property tests`,
  `## Lint & types`, each showing the command and result — plus, when level commands were
  dispatched, `## Levels` with one `### <level>` subsection each: command, test count, result
  excerpt, and the classification of any failure. Budget ≤80 lines.
- You verify; you rarely decide. Return a `proposed_adrs` entry only if verification
  establishes a significant, durable decision worth recording.
