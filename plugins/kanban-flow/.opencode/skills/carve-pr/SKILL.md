---
name: carve-pr
description: "Carve an oversized reviewed branch into ordered whole-file slices. Inventory changed paths with change types (A/M/D, --no-renames), bootstrap a throwaway worktree, prove each slice independently green, refuse when no carve works. Never touches the card's own worktree."
---

# carve-pr — safety net for an oversized branch

Carve the branch into ordered file-granular slices and prove each independently green. You run
at the **end of the review phase**, once the lens panel has passed and **before any PR exists**
— your dispatch fires only when the branch diff (minus `size_exclude`) breached `size_limit`.

**State the principle first: an oversized PR is bad; a red `main` is worse.** If you cannot
carve a green split, refuse — the correct output for entangled code, not a failure.

Read the branch diff, `design.md`, `implement.md`, and `review.md`. You carve
code the lens panel already approved — not a second chance to change it.

## Three inviolable rules

**1. Ground truth comes from the NAMED ORIGINAL BRANCH — never from `HEAD`.**

```bash
git -C <worktree> fetch origin main
git -C <worktree> diff --no-renames --name-status origin/main...<original-branch>   # the change set
git -C <worktree> diff --numstat                  origin/main...<original-branch>   # the sizes
```

**2. `--no-renames` is on EVERY `--name-status` you run.** The change-type vocabulary is
`A`/`M`/`D` only. A rename is always `D old` + `A new`.

**3. You do NOT do branch surgery in the card's worktree.** Every scratch build happens in a
**throwaway worktree** you create, bootstrap, and remove yourself. The card's own worktree
stays on the original branch, untouched.

## Procedure

1. **Inventory the changed PATHS — with their change types.** Run the two diffs from rule 1
   (exactly `A`/`M`/`D`, no `R`). Exclude `size_exclude`. The unit of a slice is a changed
   PATH with its change type, never a bare filename. A deleted path is a change like any other.

2. **Carve into an ordered set of slices.** A slice is a set of whole paths, each with its
   change type — never a hunk. Group paths that are one coherent unit a human could review
   alone, keep each slice's `added + deleted` under `size_limit`, and order them so no earlier
   slice references something only a later slice introduces. Both halves of a rename (`D old` +
   `A new`) go in the SAME slice. If a path cannot be assigned without splitting the file, go
   to step 6.

3. **Bootstrap the throwaway worktree and prove the ENVIRONMENT builds — before you judge any
   slice.** A fresh worktree off `origin/main` has no installed dependencies.

   ```bash
   git -C <worktree> fetch origin main
   TMP=/tmp/kanban-split-<card_id>
   git -C <worktree> worktree remove --force "$TMP" 2>/dev/null || true
   git -C <worktree> worktree prune
   git -C <worktree> worktree add --detach "$TMP" origin/main
   ```

   Then apply the WHOLE original change (added/modified checked out, deleted `git rm`'d, as
   step 4 does), bootstrap, and run the gates:

   - **Bootstrap** = the project's install/setup step: `just setup`/`just install` when a
     justfile defines one, else the toolchain's own (`npm ci`, `uv sync`, `poetry install`,
     `go mod download`, `bundle install`, `cargo fetch`).
   - **Gates** = the same commands `verifier` runs.

   Green → the environment is sound, proceed to step 4. Red → the ENVIRONMENT is broken, not
   the code: return `status: blocked` with the command and its real output in `blockers`.
   Never return a refusal or name a path "entangled" here.

4. **Materialize and prove each slice green, in order — in that THROWAWAY worktree.** For slice
   *k*, build what `main` will actually look like once slice *k* merges: fresh `origin/main`,
   plus slices `1..k`'s added/modified paths, minus their deleted paths, and nothing from
   `k+1..N`.

   ```bash
   TMP=/tmp/kanban-split-<card_id>
   git -C "$TMP" checkout --detach origin/main
   git -C "$TMP" reset --hard origin/main
   git -C "$TMP" clean -fd -e node_modules -e .venv -e venv -e target -e vendor
   git -C "$TMP" checkout <original-branch> -- <added/modified paths of slices 1..k>
   git -C "$TMP" rm -r --quiet -- <deleted paths of slices 1..k>
   ```

   If a slice's paths change the dependency manifests, re-run the bootstrap after the checkout.
   **Deleted paths are `git rm`'d — say so in your evidence.** Then run the real test/lint
   gates against that worktree and paste the exact command and real output for `split.md`. Then
   remove the worktree.

5. **A red slice stops the carve — it is not patched.** Try a different boundary (grouping,
   order) with whole-file moves only; if none makes every slice green, go to step 6.

6. **Refuse when no carve works** — a first-class outcome. Refuse when no grouping keeps every
   slice within `size_limit` without cutting a file, or the paths are so cross-referential that
   any whole-file boundary leaves a slice that cannot build alone. On refusal: `split_slices:
   0`, no slices, `## Verdict` names the specific entanglement. **`split_slices: 1` is a
   refusal too** — return `split_slices: 0`.

## Return

- `status: complete`, `gate: none`, `phase: review`.
- On a successful carve (N ≥ 2): top-level `split_slices: N`, plus the slice definitions (name,
  the path list with each path's change type — `added` / `modified` / `deleted`, estimated
  lines).
- On refusal: `split_slices: 0`, no slice list.
- On a bootstrap failure: `status: blocked` (step 3) — not a refusal; `blockers` carries the
  command and its real output.
- `phase_doc` is `split.md`:
  - `## Verdict` — split into N slices, or refused (with the reason).
  - `## Environment` — the bootstrap command and gate output from step 3.
  - `## Slices` — one subsection per slice: name, the exact path list with change types, why
    they cohere, estimated lines, and the real gate output that proved it green. State which
    paths were checked out and which `git rm`'d.
  - `## Order` — the shipping order and, per slice after the first, what earlier slice it
    depends on.
  - `## Coverage` — the `(path, change type)` set from step 1 vs. the union of every slice's
    set, side by side with both set differences (original \ union, union \ original — both must
    be empty).
- You create no branches, no lasting worktrees, no commits, no PRs, and touch no GitHub. The
  throwaway worktree is removed before you return.
- Add `knowledge` entries when the carve or refusal teaches how this codebase gets entangled
  (scope: repo, section: Gotchas).
