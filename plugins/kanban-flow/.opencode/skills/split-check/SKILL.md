---
name: split-check
description: "Check pilot's carve against SPL-* criteria. Re-derive change set from NAMED ORIGINAL BRANCH with --no-renames on every --name-status. Verify SPL-NO-LOSS (set-equality both directions), SPL-GREEN, SPL-SIZE, SPL-ORDER, SPL-FILES, SPL-COHERENT. Read-only Bash."
---

# split-check

Check ONE carve. Read `checks/_method.md` (the discipline and the return format) and obey it
exactly.

You have `Bash`, and it is strictly read-only. You re-derive diffs and read the gate output
`pilot` captured in `split.md`. You run no test/lint gates, build no scratch worktrees,
create no branches, and touch no GitHub.

Read: `checks/_method.md` and `checks/split.md` (absolute paths in your dispatch; layer any
`## Check criteria — split` addendum on top), `PROTOCOL-ADDENDUM.md` if present. Then your inputs: the **named original branch**, `split.md`, `design.md`,
`implement.md`, `acceptance-review.md`, and `size_limit` / `size_exclude`.

## Derive ground truth from the NAMED ORIGINAL BRANCH — never from `HEAD`

```bash
git -C <worktree> fetch origin main
git -C <worktree> diff --no-renames --name-status origin/main...<original-branch>   # paths AND types
git -C <worktree> diff --numstat                  origin/main...<original-branch>   # the sizes
```

`--no-renames` on every `--name-status` (yours and the splitter's): the change-type vocabulary
is `A`/`M`/`D` only — nothing downstream can consume an `R` — so a rename is always `D old` +
`A new`, and the unit of a slice is a **path plus its change type**. Both derivations say
`--no-renames`, so the set comparison is mechanical.

## Work the split criteria

Work the `## split` criteria by the Walk in `checks/split.md` (derive your own carve before
reading `split.md`, then build the `(path, change-type)` sets and diff):

1. **`SPL-NO-LOSS`** — build the original branch's `(path, type)` set and the union of the
   slices' declared sets, and report **both** set differences with counts — even when both are
   empty. A `D` path no slice deletes is lost work exactly as much as a dropped file. A path in
   both sets with a *different* change type is a failure too.
2. **`SPL-GREEN` — judge the evidence, do not re-run it.** For each slice, confirm `split.md`
   carries a pasted command plus its real output, run against the scratch build the spec
   requires (throwaway worktree off fresh `origin/main`, bootstrapped, slices `1..k`'s
   added/modified checked out and their deleted paths `git rm`'d). Without proof the worktree
   builds *with the whole change applied*, flag it blocking `SPL-GREEN`.
3. **`SPL-SIZE`** — sum `added + deleted` per slice from its own path list against
   `origin/main` (excluding `size_exclude`), computed by **you**, not copied from `split.md`.
4. **`SPL-ORDER`, `SPL-FILES`, `SPL-COHERENT`** per `checks/split.md` — deletions are ordered
   too, and a rename's two halves (`D old` + `A new`) must sit in one slice. Zero appearances
   of a path is `SPL-NO-LOSS`; two or more is `SPL-FILES`.
5. **A refusal (`split_slices: 0`) is checked, not waved through.** Verify the entanglement
   `## Verdict` names is real and checkable against the original diff.
6. **Verdict every criterion** — `pass`/`fail`/`na`, each with evidence of what you re-derived
   (for `SPL-NO-LOSS`/`SPL-SIZE`, the numbers). Findings only where you can cite a location in
   `split.md` or the change set.

## Return

- `verdict: pass` (`status: complete`, `gate: none`, `phase: check`, `checks: split`) when no
  finding is blocking. The orchestrator then hands the slices to `pilot` in order and
  re-runs the `[acceptance]` lens once per slice.
- `verdict: fail` when any finding is blocking — the orchestrator re-dispatches `pilot`
  with your findings verbatim, up to the `split` check budget, then the card falls back to
  `pilot`'s refusal path and ships as one oversized PR.
- `phase_doc` is `split-check.md`: `## Verdict`, `## Criteria` (the full table — id, verdict,
  evidence), `## Coverage reconciliation` (your own re-derived `(path, change type)` sets and
  both set differences — the numbers, naming the `--no-renames` git command against the
  original branch), `## Blocking findings`, `## Advisory findings`.
- `status: needs-input` only if you cannot check at all (`split.md` missing, the original
  branch unreadable or unnamed in your dispatch). A carve you disagree with is a `fail`.
- Add `knowledge` entries for recurring carve traps worth teaching `pilot` (scope: repo,
  section: Gotchas).
