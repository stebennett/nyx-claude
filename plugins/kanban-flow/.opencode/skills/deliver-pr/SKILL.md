---
name: deliver-pr
description: "Ship one PR in design or implementation mode. Design: rebase docs-only branch, verify docs-only diff, push, open design PR. Implementation/slice: rebase on main, confirm green, push, open PR. Only procedure permitted to mutate GitHub."
---

# deliver-pr

Ship one PR. The dispatch prompt names the **mode** (`design` or `implementation`), the card's
`worktree`, and the **path to a file containing the final PR body** — use it verbatim via
`--body-file`. The conductor has already committed the relevant docs onto the branch.

Invoke and follow **superpowers:finishing-a-development-branch**. Work in the card's `worktree`.

## Design mode (branch `<type>/NNN-slug-design`)

The branch holds `slice.md`, `design.md`, ADR files, and any early `feedback.md` — docs only,
no code.

1. Rebase on latest `main` (`git fetch origin && git rebase origin/main`); docs-only branches
   rebase cleanly — on a conflict you cannot cleanly resolve, `status: blocked` with the files.
2. Verify the diff is docs-only (`git diff origin/main...HEAD --name-only` → everything under
   `docs/`). Code in a design PR is a blocker, not something to ship.
3. Push: `git push -u origin <branch>`.
4. Open the PR: `{gh_command} pr create --base main --head <branch> --title "CARD-NNN — design: <title>" --body-file <path>` (`gh_command` from `config.md`).

## Implementation mode (branch `<type>/NNN-slug`, or a slice branch `<type>/NNN-slug-<k>`)

The branch holds the code plus `implement.md`/`verify.md`/`acceptance-review.md`/`pr-body.md` (and later
`feedback.md` entries), already committed. The procedure is identical whether this is a card's
only PR or one slice of several.

When it's a slice, your dispatch names `k` and `N`, and points at that slice's own worktree and
branch `<type>/NNN-slug-<k>` — cut by the conductor off fresh `origin/main` and already
populated with exactly that slice's files. On slice 1 only, the card's phase docs ride along.

1. Confirm you are in the right worktree (the slice's own, when this is a slice) and on the
   right branch. Rebase on latest `main`: `git fetch origin && git rebase origin/main`.
   Unresolvable conflict → `status: blocked` with the conflicting files.
2. Re-run the fast test/lint gates to confirm still green after rebase.
3. Push: `git push -u origin <branch>` (the slice branch name, when this is a slice).
4. Open the PR. Unsplit: `{gh_command} pr create --base main --head <branch> --title "CARD-NNN — <title>" --body-file <path>`. Slice: `{gh_command} pr create --base main --head <type>/NNN-slug-<k> --title "CARD-NNN — <title> (slice k of N)" --body-file <path>`. A slice PR's body must say which slice this is and name the card.
5. Note any CHANGELOG update the project convention requires.

**Never delete the original (unsplit) branch or its worktree — in any circumstance.** It is the
source of truth for every slice not yet shipped. Only the conductor tears it down once the last
slice merges. The slice's own branch is yours to finish; the original is never yours to touch.

## Return

- `status: complete`, `gate: none`, with the PR url in `summary`.
- `status: blocked` with `blockers` on rebase conflict, a failing post-rebase gate, or code found
  in a design branch.
- `phase_doc`:
  - **Implementation mode → `deliver.md`** (`## PR` url, `## Commit/changelog`, `## Post-merge`
    note). When this was a slice, say so in `deliver.md`: which slice, the card, and sibling
    slices. The conductor persists it to `main` under `deliver-<k>.md` for a slice,
    `deliver.md` otherwise.
  - **Design mode → omit `phase_doc` (return it empty).** There is nothing on `main` to persist
    it to; the design PR's url in `summary` is the record.
