---
name: deliver-check
description: "Check ONE open PR against DLV-* criteria. Gather evidence with read-only gh/git commands, work deliver criteria (handling slice vs unsplit modes), verdict every criterion, and return a phase_doc named by mode. Does not mutate GitHub or write files."
---

# deliver-check

Check ONE open PR against the deliver criteria defined in `checks/deliver.md`. This is a read-only
procedure — run `gh` and `git` read commands only, never comment, approve, request changes, or merge.

## Protocol bootstrap

Read `checks/_method.md` (the discipline and the return format) and `checks/deliver.md` (absolute paths
in your dispatch; layer any `## Check criteria — deliver` addendum on top).

Your dispatch gives you: `card.md`, the `pr_url`, the PR **mode** (`design` | `implementation`), the
`worktree`, `gh_command`, `size_limit` and `size_exclude` (the ceiling and exclusions for `DLV-SIZE`),
the card's `estimated_lines` (what the slicer projected — report actual against it), and the `checks`
policy (which producers' checks are `on`). If an input a criterion needs is absent, say so in that
criterion's evidence — never verdict `pass` on evidence you were never given.

## Gather evidence

```bash
{gh_command} pr view <pr_url> --json baseRefName,headRefName,body,state,files
{gh_command} pr checks <pr_url>
git -C <worktree> fetch origin main
git -C <worktree> diff --numstat origin/main...<the PR's branch>
```

**Name the PR's branch** — the one your dispatch gave you (a slice PR's is the slice branch
`<type>/NNN-slug-<k>`, not the card's original branch) — never `HEAD`. Paste real output into
your evidence.

## Slice PR awareness

When your dispatch names `k` of `N`, you are checking a slice PR. The `worktree` you were handed is
that slice's own worktree, built off `main` plus only slice `k`'s files. Three criteria change shape:

## Work the deliver criteria

Work each criterion per `checks/deliver.md`. `DLV-BASE`, `DLV-PURITY` and `DLV-CI` read as
written there (CI fails only on *red*, not pending).

**`DLV-BODY-TRUE`** — judge each body claim against the diff. On a slice PR, a body states
`slice k of N` and only that slice's share of the card's acceptance criteria; a slice that does
not implement every card criterion is correct, not partial — but a claim its files do not serve
is still blocking.

**`DLV-SIZE`** (implementation PRs only; `na` on a design PR). Report `actual_lines: <N>`
whether breach or not. On an **unsplit** PR a breach is `advisory`: propose a concrete split
(which commits/file groups become which smaller PRs, in what order). On a **slice** PR a breach
is `blocking` — `pilot` carved it under `size_limit` and `pilot` confirmed it,
so a still-oversized slice means the splitter failed. Report actual vs. limit, propose no further
split. **Never split a split.**

**`DLV-DOCS`** — expected phase docs ride the PR (design PR: `slice.md`, `design.md`,
`slice-check.md`, `design-check.md`, ADRs; implementation PR: `implement.md`, `test.md`,
`review.md`), except a doc whose check is `off`. On a slice PR these ride only slice 1 — absence
from slice 2+ is expected, which is why your dispatch tells you `k`.

Verdict every criterion with evidence — real command output, not a summary. Every id in your
section, none omitted; use `na` with evidence for why rather than dropping a row.

## Return

- `verdict: pass` (`status: complete`, `gate: none`, `phase: check`, `checks: deliver`) when no
  finding is blocking — including an unsplit `DLV-SIZE` breach (advisory). A slice `DLV-SIZE`
  breach is blocking, so no `pass` alongside it.
- `verdict: fail` when any finding is blocking. Write each finding to name the artifact at fault;
  the orchestrator routes it accordingly (fixing PR metadata, committing a missing phase doc,
  re-dispatching the producer, or parking the card — never re-running `pilot` on an
  already-split card).
- `phase_doc` is named for your mode and slice: **`deliver-check-design.md`** (design),
  **`deliver-check.md`** (implementation, unsplit), or **`deliver-check-<k>.md`** (slice `k`).
  Sections: `## Verdict`, `## Criteria` (the full table — id, verdict, evidence with real
  command output), `## Size` (`actual_lines`, the excluded paths, and against `estimated_lines`),
  `## Blocking findings`, `## Advisory findings` (an unsplit `DLV-SIZE` breach's proposed split
  lives here in full; a slice `DLV-SIZE` breach lives in `## Blocking findings` instead).
- `status: blocked` only if you cannot check at all (`{gh_command}` failing, PR unreachable) —
  an infrastructure failure. Unlike sibling checkers' `needs-input`, this parks the card rather
  than posing a question.
- Add `knowledge` entries for recurring delivery traps worth teaching earlier phases (scope:
  repo, section: Gotchas).
