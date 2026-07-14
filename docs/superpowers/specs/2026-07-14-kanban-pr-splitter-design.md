# pr-splitter — actioning an oversized PR

**Date:** 2026-07-14
**Status:** Approved — ready for implementation
**Plugin:** `plugins/kanban-flow`
**Depends on:** `feat/kanban-checker-agents` (the checker layer, `DLV-SIZE`, the pre-PR lens panel)

## Problem

`DLV-SIZE` measures an implementation PR's real changed lines and, on a breach, requires
`card-deliver-checker` to propose a concrete split — which commits or file groups become which
smaller PRs, in what order. That proposal is then surfaced to the driver and **nothing actions it.**

Worse, it is shaped for a system that does not exist: it proposes *PR-shaped* splits, but this
system's unit of work is a **card**, and a card maps 1:1 to an implementation PR. There is no
supported way to split a PR. The driver is handed a well-reasoned proposal with no mechanism to
execute it, which is a dressed-up way of saying it is a dead letter.

Only half of `DLV-SIZE` pays for itself today: `estimated_lines` vs `actual_lines` feeds `/retro`,
which fixes the **slicer's** under-estimation at source so the *next* card is split before any code
exists. That half works and stays.

This design makes the other half real.

## The model

**A card may now ship as several implementation PRs.** Each is independently reviewable,
independently green, and merges to `main` on its own. The card is `done` when all of them have
merged.

**`SLC-SIZE` is unchanged and still binding.** A card is still forced to split *before any code is
written* when it is projected over `size_limit`. `pr-splitter` is a **safety net for when that
estimate was wrong** — not a routine path, and not a licence for bigger cards. Its firing is a
signal that something went wrong upstream, and `/retro` mines exactly that.

## Where the split happens — before the PR, after the panel

The split fires at the **end of the `review` phase**, once the lens panel has passed, and **before
any PR exists**:

```
implement → test → review (lens panel, whole diff) → [split] → deliver → PR₁ … PRₙ
```

Two consequences, both load-bearing:

**Nothing a human is reading ever gets destroyed.** The split happens before `card-deliverer` opens
anything, so there is no PR to close, re-target, or rewrite. This is what makes an *automatic* split
(no driver gate) safe: the hazard it would otherwise carry does not exist.

**The split runs once, on final approved code.** Were the splitter to run *before* the panel, every
blocking finding would change the code and stale the carve — file sizes shift, a fix drags code
across a slice boundary, a slice tips over budget — forcing a re-split and re-review on every rework
pass. Panel-first has no such loop.

**And nothing is lost by reviewing the whole diff first.** `SPL-NO-LOSS` (below) requires the union
of the slices to equal the original branch diff *exactly*. The slices are therefore byte-for-byte the
code the panel already approved: the splitter is a **redistribution, not a rewrite**. A second panel
would re-read identical bytes with *less* context, and would never see the whole change — a defect
living in the interaction between slice 1 and slice 3 is invisible to any lens shown only one of
them. Splitting exists for the **human's** review load; the lens panel is not context-limited the way
a person is.

## `pr-splitter` (new agent)

A **producer**: it creates artifacts (branches and a shipping plan) and can be wrong. Model `sonnet`
— carving code along coherent seams is design work, not a lookup. Tools: `Read, Grep, Glob, Bash,
Skill` (it must run the project's gates to prove each slice is green).

**Dispatched** at `status: review`, panel passed, when the worktree diff
(`git diff --numstat main...HEAD`, minus `size_exclude`) exceeds `size_limit`.

**It does:**

1. Read the branch diff, `design.md` (acceptance criteria + task list), `implement.md`, `review.md`.
2. Carve the **changed files** into an ordered set of slices — each within `size_limit`, each a
   coherent unit a human can review alone, ordered so no slice depends on a later one.
3. **Prove each slice is independently green.** For slice *k*, build a scratch branch of
   `fresh main + the files of slices 1..k` — exactly what `main` will look like when slice *k*
   merges — and run the project's test and lint gates, capturing **real command output**.
4. Write `split.md`: the ordered slices (name, files, why, estimated lines, the green evidence).

**File-granular only.** A slice is a set of **whole files**. Slice *k*'s branch is
`fresh main + git checkout <original-branch> -- <slice k's files>`. A slice boundary can never fall
*inside* a file. Hunk-level surgery is out of scope: an agent carving reviewed code at hunk
granularity can silently produce a slice that compiles, passes, and is subtly wrong.

**Refusal is a first-class outcome.** If no carve leaves every slice green, or the code cannot be
divided without cutting a file (one enormous file; two features tangled in one module), `pr-splitter`
**refuses**: it returns `split: none` with the reason, the card ships as **one oversized PR**, and the
pump warns prominently. *An oversized PR is bad; a red `main` is worse.* The refusal is itself a
signal — entangled code — and `/retro` mines it.

## `card-split-checker` (new agent)

`pr-splitter` is a producer, so the doctrine binds: **every producer has a checker.** Model `sonnet`;
read-only tools (`Read, Grep, Glob, Bash, Skill` — Bash read-only, to re-derive diffs and read the
gate output the splitter captured).

New `## split` section in `CHECK-CRITERIA.md`, ids `SPL-*`:

| id | criterion | severity |
|---|---|---|
| `SPL-NO-LOSS` | the union of the slices equals the original branch diff **exactly** — nothing dropped, nothing invented | blocking |
| `SPL-GREEN` | each slice's green evidence is **real command output**, not a claim | blocking |
| `SPL-SIZE` | every slice is within `size_limit` | blocking |
| `SPL-ORDER` | no slice depends on a later one | blocking |
| `SPL-FILES` | whole files only; no file appears in two slices | blocking |
| `SPL-COHERENT` | each slice is reviewable on its own | advisory |

`SPL-NO-LOSS` is the one that matters. A splitter that silently drops code ships a broken card, and
it is also the guarantee that makes panel-first safe. The checker **re-derives** the union itself —
it never takes the splitter's word for it.

**After the check passes, the `[acceptance]` lens re-runs once per slice**, confirming each slice
traces to the acceptance criteria it claims. This is the cheap half that catches an incoherent carve
without paying for the whole panel N times.

## Shipping — sequential

Slice PRs ship **one at a time**, each cut from a `main` that already contains its predecessors:

- Slice *k*'s branch is `<type>/NNN-slug-<k>`, cut from **fresh `origin/main`**, populated with slice
  *k*'s files from the original branch, pushed, and opened as a PR by `card-deliverer`.
- When slice *k* merges, Reconcile cuts slice *k+1* from the **new** `main` and opens it.
- **The original branch stays alive** — it is the source of truth for every slice not yet shipped. It
  is deleted only when the last slice merges.

Each slice PR gets full CI and its own `card-deliver-checker` pass, so `DLV-BODY-TRUE` checks its body
and `DLV-SIZE` catches a slice that is *still* oversized.

**Never split a split.** A slice still over budget at deliver means the splitter failed — **park the
card** for the driver. No recursion, no infinite loop.

## Card state

`pr_url: ""` becomes:

```yaml
pr_urls: []           # implementation PRs, in shipping order. The card is done when ALL have merged.
split_slices: 0       # how many slices this card ships as. 0 = not split (one PR), N = split by pr-splitter.
```

A legacy `pr_url: <url>` migrates to `pr_urls: [<url>]` with `split_slices: 0` — a card that shipped
as one PR is the N=1 case, not a special case.

**`done` requires both:** every url in `pr_urls` has merged, **and**
`git diff main...<original-branch>` is empty. The second is a completeness backstop — it catches code
the splitter silently dropped even if `SPL-NO-LOSS` missed it, and it is checkable from disk.

**A PR closed unmerged → `status: blocked`**, naming which slice. The existing "PR closed without
merge" rule, extended to a list.

`check_budget` gains `split: 1` — a split that fails its check twice is not going to work on a third
try.

## `/retro`

Two new signals, both about the *slicer*, not the splitter:

- **How often `pr-splitter` fired.** Every firing is a card whose `estimated_lines` was wrong enough
  to need surgery after the fact — a slicer defect, and the fix belongs in the slicer's prompt.
- **How often it refused.** A refusal means the code could not be carved without cutting a file or
  going red: the card's implementation is entangled. That is a *design* signal — worth a `KNOWLEDGE`
  gotcha or a card, not a slicer fix.

`estimated_lines` vs `actual_lines` continues unchanged.

## Out of scope

- **Hunk-level splitting.** File-granular only; refuse otherwise.
- **Splitting a design PR.** Design PRs are docs; `DLV-SIZE` is already `na` on them.
- **Retroactively splitting the CARD.** The card keeps its identity and its acceptance criteria; only
  its delivery is split. Splitting the card would rewrite board history after the fact, and the
  criteria were never sliced that way.
- **Relaxing `SLC-SIZE`.** The pre-code ceiling stands. `pr-splitter` is a safety net, not a licence.
