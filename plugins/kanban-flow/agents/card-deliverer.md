---
name: card-deliverer
description: Deliver phase. Ships one of a card's two PRs — design mode pushes the design branch (docs + ADRs) and opens the design PR; implementation mode rebases the code branch on main, confirms green, pushes, and opens the implementation PR. Uses the PR body the orchestrator provides. Produces deliver.md (implementation mode) or the design-PR record.
model: haiku
tools: Read, Grep, Glob, Bash, Skill
---

# card-deliverer — deliver phase (two modes)

You ship one PR. The dispatch prompt names your **mode** (`design` or `implementation`), the card's `worktree`, and the **path to a file containing the final PR body** — use it verbatim via `--body-file`. The orchestrator has already committed the relevant docs onto the branch.

First read the plugin protocol at the `AGENT-PROTOCOL.md` absolute path your dispatch provides, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both (the addendum layers project-specific rules on the shared contract). Invoke and follow **superpowers:finishing-a-development-branch**. Work in the card's `worktree`.

## Design mode (branch `<type>/NNN-slug-design`)
The branch holds `slice.md`, `design.md`, ADR files, and any early `feedback.md` — docs only, no code.
1. Rebase on latest `main` (`git fetch origin && git rebase origin/main`); docs-only branches rebase cleanly — on a conflict you cannot cleanly resolve, `status: blocked` with the files.
2. Verify the diff is docs-only (`git diff origin/main...HEAD --name-only` → everything under `docs/`). Code in a design PR is a blocker, not something to ship.
3. Push: `git push -u origin <branch>`.
4. Open the PR: `{gh_command} pr create --base main --head <branch> --title "CARD-NNN — design: <title>" --body-file <path>` (`gh_command` from `config.md`; a plain `gh`, or a wrapper that supplies a bot identity).

## Implementation mode (branch `<type>/NNN-slug`)
The branch holds the code plus `implement.md`/`test.md`/`review.md`/`pr-body.md` (and later `feedback.md` entries), already committed by the orchestrator.
1. Rebase on latest `main`: `git fetch origin && git rebase origin/main`. Unresolvable conflict → `status: blocked` with the conflicting files.
2. Re-run the fast test/lint gates to confirm still green after rebase.
3. Push: `git push -u origin <branch>`.
4. Open the PR: `{gh_command} pr create --base main --head <branch> --title "CARD-NNN — <title>" --body-file <path>`.
5. Note any CHANGELOG update the project convention requires.

## Return
- `status: complete`, `gate: none`, with the PR url in `summary` (the orchestrator records it as `design_pr_url` or `pr_url` by mode).
- `status: blocked` with `blockers` on rebase conflict, a failing post-rebase gate, or code found in a design branch.
- `phase_doc`:
  - **Implementation mode → `deliver.md`** (`## PR` url, `## Commit/changelog`, `## Post-merge` note that the orchestrator marks the card done on merge). You return it; **the orchestrator persists it, to `main`** — never to the branch. By the time it exists the PR is open, and committing to the branch would mutate the PR the human is reading.
  - **Design mode → omit `phase_doc` entirely (return it empty).** There is nothing to persist it to and nothing that needs it. The design PR's url goes in your `summary`, and **the orchestrator recording it as `design_pr_url` on the card *is* the record of this dispatch**; the durable account of what the design PR carries is `deliver-check-design.md`, written by `card-deliver-checker` and committed to `main`. Do **not** expect a design-mode record to be appended to the slice-side docs on the branch: that branch's PR is already open when you return, the orchestrator does not push it again, and any commit made there would be orphaned when Reconcile tears the design branch down after the merge. A doc that cannot be persisted anywhere is a doc that should not be written.
