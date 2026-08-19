---
name: implement-card
description: "Implement one card TDD in three modes: Fresh (execute design task list), Rework (fix blocking tester/reviewer/CI findings), PR-comment (address human review comments). Uses Conventional Commits, stays in scope, runs gates before returning."
---

# implement-card

Build the card's `design.md` implementation task list to green. All file changes happen inside
the card's `worktree` (absolute paths under it) — never touch the primary working tree.

Read `design.md`, and only the spec sections `design.md` cites. Before implementing
an unfamiliar pattern, invoke the **board-knowledge** skill with your query — it checks
project conventions, gotchas, and glossary.

**When something blocks you — a finding that reveals the design is wrong, a comment you cannot
do as asked, a task needing files outside the design's list — stop and return `status: blocked`
(or the item in `blockers`) with the evidence. Never improvise a redesign or expand scope.**

## Three dispatch modes

- **Fresh:** execute the design task list from the top.
- **Rework:** the dispatch prompt includes blocking findings from the tester, the reviewer, or a
  failing CI run (job, step, log excerpt). Fix exactly those findings (test-first where a
  finding is a behaviour bug: reproduce it with a failing test, then fix). For a CI failure,
  reproduce it locally in the worktree first — run the failing command; if you cannot reproduce
  it, say so in `blockers` with both outputs rather than fixing blind. When the dispatch says
  the card's PR is already open, `git push` the branch after your gates pass.
- **PR-comment:** the dispatch prompt includes the review-complete comment set (id, path, line,
  body; review-body items flagged as summary) — every human-authored comment. Fix exactly those
  — test-first for behaviour changes, direct edit for nits — run the fast test/lint gates,
  commit, and `git push` the card branch (it already tracks the remote). Never touch the PR
  threads themselves (per protocol — the orchestrator replies, the human resolves). A comment
  that is wrong or can't be done as asked goes in `blockers` with your reasoning.

## Procedure

1. Invoke and follow the **superpowers:test-driven-development** skill — for each design task:
   failing test → confirm red → minimal code → confirm green → refactor → commit.
2. Use **Conventional Commits**; commit after each green task (frequent small commits), ending
   each message with the project `Co-Authored-By` trailer.
3. Stay within the card's scope (`design.md` in/out of scope).
4. Run the project's fast test command as you go (`just test` when a justfile defines it, else
   the toolchain runner). Before returning, run the card-relevant lint/type gates too.

## Craft heuristics

- **Never weaken a test to make it pass.** If a test seems wrong, check it against `design.md`
  and the cited spec section.
- **Trust the red.** Run the exact failing test first; run the full suite before returning. A
  test that passes before you've written its code is broken — fix it first.
- Core-logic tests need no mocks — if you're reaching for one inside the pure logic layer, the
  code under test has I/O where it shouldn't.
- Hypothesis in CI: fixed seeds/profiles, constrained strategies, mind the deadline setting — a
  slow strategy is a flake factory.

## Return

- `status: complete`, `gate: none` when all design tasks (or all rework findings) are
  implemented and the card's own tests are green.
- `status: blocked` with `blockers` (command + output excerpt) if you cannot proceed.
- `phase_doc` is `implement.md` with sections: `## What changed` (bullets), `## Deviations from
  design`, `## Commits` (hashes + subjects). On rework, add `## Rework` (which findings were
  addressed and how). On PR-comment mode, add `## PR comments addressed` (comment id → commit
  sha + one line).
- Add `knowledge` entries for gotchas discovered (scope: repo, Gotchas) or tooling preferences
  (scope: personal).
