---
name: kanban
description: Orchestrate the kanban board: reconcile merged PRs, schedule ready cards, run each through slice→design→implement→test→review→deliver via the card-* agents. Sole writer of BOARD.md, KNOWLEDGE.md, card.md. Safe under /loop. Run under Opus.
---

# /kanban — orchestrator & dashboard

You drive cards through the board. `/refine` and `/requirement` create and edit cards **while in
`backlog`**; once a card leaves backlog you are its **sole writer** — as of `docs/cards/BOARD.md` and
`docs/cards/KNOWLEDGE.md` throughout. `/requirement` reaches cards beyond backlog only by queueing an
amendment for you to apply (§0). No phase agent writes these files; agents return `result` blocks and
you persist everything they produce.

**Every card ships a design PR, then its implementation — ONE PR, or, when oversized, SEVERAL.** The
**design PR** (branch `<type>/NNN-slug-design`) carries `slice.md`, `design.md`, ADRs, gate feedback so
decisions land on `main` early. The **implementation PR** (branch `<type>/NNN-slug`, cut from `main`
*after* the design PR merges) carries the code plus `implement.md`/`test.md`/`review.md`. The human
merging each PR is that half's review gate. At the end of `review`, once the lens panel passes, an
oversized branch dispatches **`pr-splitter`**, which carves it into N slices; the card ships **N
implementation PRs, one at a time**, so `pr_url` is **`pr_urls` — an ordered list** (§5;
`references/split-shipping.md`). `done` = every url merged AND the original branch has nothing left; an
unsplit card has one `pr_urls` entry (the N=1 case).

**Direct-to-`main` commits are limited to, exhaustively:** `card.md`/`BOARD.md`/`KNOWLEDGE.md` state,
the milestone swap on splits, a split parent's terminal `slice.md`/`slice-check.md`, the deliver check
docs and `deliver.md` (`-<k>` per slice — produced *after* their PR is open), and post-PR `feedback.md`.
Nothing else. Every other phase doc lives on the card's current branch. **The slice phase has no
branch/worktree**, so `slice.md`/`slice-check.md` are written into `<board_dir>/CARD-NNN-slug/` **in the
primary checkout, UNCOMMITTED**, until the design transition (§5) copies them onto the design branch —
**never to `main`** (RATIONALE: the `DLV-DOCS` livelock), except a **split parent** (terminal record).

Each invocation runs one **pump cycle**: reconcile → load → render → resolve gates/blockers → schedule
& advance (in waves) → re-render → report. A card stops mid-lifecycle only at a manual gate,
`needs-input`, an exhausted rework budget, an open PR awaiting merge, or `done` — safe under `/loop`.

## 0. Reconcile (self-healing state)

Card state must survive lost commits and merges that happen while no pump runs. Before anything else:

1. `git fetch origin main` and inspect `git log origin/main` for merge subjects matching
   `CARD-NNN … (#N)`.
2. **Design PR merged** (matches a card's `design_pr_url`, or subject contains `design:`): tear down
   the design branch/worktree, create the **implementation branch** `<type>/NNN-slug` and worktree off
   fresh `origin/main`, update `branch`/`worktree`, set `status: implement` (keep `design_pr_url`),
   **reset `reworks.deliver` to `0`** (a new PR gets its own `check_budget.deliver`; RATIONALE). Card
   continues in §5.

   **Reconcile never advances a card out of `blocked` while leaving the blocker set.** A `blocked` card
   gets the bookkeeping (record the merge, tear down branch/worktree, keep the urls), then the status is
   decided explicitly. If the merge answers the blocker — a failing/red-CI blocker, an
   exhausted-check-budget blocker, or a `check failed — <id> (self-fix did not clear it)` park (all
   blockers on *that* PR) — **clear `blocker` and advance**, naming it in the report. If it says nothing
   about the blocker — `requirement changed — REQ-NNN`, a `DLV-PURITY` park, a driver-set blocker —
   **the card stays `blocked`** and the report says why.
3. **Implementation PR merged** (matches a `pr_urls` entry, or a non-design `CARD-NNN` subject). Let
   `N = split_slices` (0/1 → one PR) and `k` = the merged url's **1-based position in `pr_urls`**
   (shipping order = slice number). Record the merge, keep every url, **tear nothing down yet**.
   **Un-actioned findings** (each merged implementation PR): `review.md` advisories no branch commit
   answered, no review-complete signal before the merge → surface each (§7) as *"un-actioned findings on
   merged CARD-NNN — candidate defect cards"*; don't reopen or block. Then:
   - **More slices remain** (`N ≥ 2` and `k < N`) → **not** done. Tear down **only that slice's**
     branch/worktree (`<type>/NNN-slug-<k>`); **leave `status: deliver`** and the **original branch and
     worktree ALIVE** (source of truth for unshipped slices). **Reset `reworks.deliver` AND
     `reworks.implement` to `0`** in the same commit (RATIONALE). §5's deliver row cuts **slice `k+1`
     from the NEW `main`** and opens it. Report `CARD-NNN — PR k/N merged, opening slice k+1`.
   - **That was the last PR** (`k = N`, or `N` is 0/1) → **the completeness backstop runs BEFORE any
     teardown** (it checks the original branch/worktree). Quick probe: `git -C <worktree> diff --numstat
     origin/main...<original-branch>` (excluding `size_exclude`). **Empty → complete:** `status: done`,
     `phase: done`, `delivered` = merge date; **append the card's `/retro` line** to
     `<board_dir>/RETRO-INBOX.md` in this same state commit — `CARD-NNN | delivered YYYY-MM-DD | reworks
     {slice:_,design:_,implement:_,split:_,deliver:_} | elapsed Nd | est/actual lines E/A | slices N |
     human-comments M` (M = human PR-comment count across both PRs). Then tear down the original worktree,
     delete the original branch **locally and on `origin`** (the only moment either may be deleted) and
     any leftover slice worktrees. **Non-empty is not yet a verdict** (squash/rebase leaves the merge base behind) → **read
     `references/reconcile-edge-cases.md`** for the two-direction procedure.
4. For every card, check **every** not-yet-merged url (`design_pr_url` + each `pr_urls` entry):
   `{gh_command} pr view <url> --json state,mergedAt`. `MERGED` → apply step 2/3. `CLOSED` (unmerged)
   → **read `references/reconcile-edge-cases.md`** (closed-PR recovery — a naive unblock skips the
   closed slice).
5. **Normalize legacy state** — scalar `pr_url`, `status: plan`, a verdict-less `test.md`/`review.md`,
   `split_slices: 1`, a `reworks` scalar, a `retro:` field, a non-enum status → **read
   `references/reconcile-edge-cases.md`**. None present → skip.
6. **Drain the amendment queue** — `{board_dir}/AMENDMENTS.md` non-empty → **read
   `references/reconcile-edge-cases.md`**. Absent → skip.
7. Note any other drift you can't self-heal (a card id in a merged PR with no card dir, a worktree
   with no card) in the report — don't guess.

**Trigger:** a CLOSED-unmerged PR, an `AMENDMENTS.md` block, any legacy field, or a non-empty
completeness backstop → **read `references/reconcile-edge-cases.md`** before acting.

## 0.5 Idle fast path

After the cheap reconcile probes and **before** §1's full card parse, run only these checks:
- **Merges:** the §0 step 1 fetch + merge-subject scan — did any `design_pr_url`/`pr_urls` url land?
- **PR states, CI, reviews:** one `{gh_command} pr view <url> --json state,statusCheckRollup,reviews,comments`
  per not-yet-merged url (one call each) — any newly `MERGED`/`CLOSED`? any open PR with a **failing
  check**, or a **human review/`REVIEWED` comment not yet addressed** (no top-level
  `[kanban] review addressed — <id>` marker for it — §6b step 4 posts one per completed signal)?
- **Card frontmatter + doc presence** (status/blocker, plus phase-/check-doc presence via `ls` and their
  `verdict:` headers — **not** a full parse): any card dispatchable (a `backlog` card with deps `done`
  and a free WIP slot; an in-flight card whose next phase doc is absent, or whose check doc reads
  `verdict: fail`)? Any card needing the driver (a gate awaiting an answer, a `blocked` card, a
  `needs-input`)? Is `AMENDMENTS.md` non-empty?

**If ALL hold** — no merge, no open PR failing CI or with an unaddressed review, nothing dispatchable, no
gate/blocker/amendment for the driver, every in-flight card awaiting human/CI — **print `idle — M in
flight awaiting human/CI, K in backlog` and STOP** (skip the re-render unless state changed). **Any false
→ full pump** (§1 on). When in doubt, run the full pump.

## 1. Load state

Read `{board_dir}/config.md` first — the tunables (`spec_path`, `gh_command`, `wip_limit`, `gates`,
`checks`, `check_budget`, `size_limit`, `size_exclude`, `layers`, `gate_layer`, `adr_dir`,
`coverage_target`). Never hardcode. Defaults: missing `checks` producer → `on` (**incl.
`checks.split`**); missing `check_budget` producer → `2` (`deliver` and **`split`** → `1`); missing
`size_limit` → `500`; `board_dir` → `docs/cards`. Read every `docs/cards/CARD-*/card.md` and parse
frontmatter (missing `started`/`delivered`/`design_pr_url`/`estimated_lines`/`actual_lines` → empty).
**`pr_urls` is an ordered list** of implementation PR urls in shipping order; **`split_slices`** is how
many slices the card ships as (absent/`0` → one PR; `1` reads as `0`). **`reworks` is a per-producer
map** (`{slice, design, implement, split, deliver}`; missing `split` → `0`). **`review_lenses_failed`
is a list of lens names** — absent/empty → run the full panel (the safe default). Source of truth. Read
`docs/cards/KNOWLEDGE.md`. Read `docs/cards/MILESTONES.md` (authored by `/refine`; you never write it):
parse `## M<N> — <title>` headings and each `**Cards:**` line into a `card → milestone index` map
(document order = delivery order; no milestone → ∞); progress = done / total members.

**Load the criterion id set — actually READ the files, once per pump.** Read
`${CLAUDE_PLUGIN_ROOT}/templates/checks/ids.md` (~200 tokens) and every `## Check criteria — <target>`
section of `<board_dir>/PROTOCOL-ADDENDUM.md` (absent → no `LOCAL-` ids), and **hold the id set per
target** — `intake` | `slice` | `design` | `split` | `deliver` — each being its `ids.md` ids
(`INT-*`/`SLC-*`/`DSG-*`/`SPL-*`/`DLV-*`) **plus** the addendum's `LOCAL-` ids for that target. **This
read makes §5's completeness valve real** — the valve rejects any checker result whose `criteria:` map
omits an id of its target's set (RATIONALE).

Resolve the **plugin doctrine directory** once: `${CLAUDE_PLUGIN_ROOT}/templates/`. Pass absolute paths
from it into every dispatch (§5) — agents never read a `docs/cards/` copy. **Template resolution:** for
`card-template.md`/`pr-template.md`/`design-pr-template.md`, use `config.md`'s
`template_overrides[<name>]` if set (repo-relative), else `${CLAUDE_PLUGIN_ROOT}/templates/<name>`.
**Migration check:** compare `config.md`'s `kanban_flow_version` to the installed plugin version and
scan `<board_dir>` for leftover plugin-owned copies (`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`,
`card-template.md`, `pr-template.md`, `design-pr-template.md`, excluding any in `template_overrides`) —
behind, or any unregistered copy → set `migration_needed` (§7).

## 2. Render the board (sole writer)

Rewrite `BOARD.md`: one bullet per card under the column matching its `status`, showing `CARD-NNN —
title · phase · branch` (suffix `[M<N>]`), plus the blocker for blocked cards, `(awaiting input)`, the
PR link for open PRs (`design PR #N open` / `PR #N open`), and `· checking <phase>` when a producer has
returned but its checker has not yet run/passed. **A split card shows shipping progress** off
`pr_urls`/`split_slices`: `PR 2/3 open`, `PR 2/3 merged — opening 3/3`, `split: 3 slices` (at `review`,
no PR yet); an unsplit card shows `PR #N open` (never `1/1`). A card parked on an exhausted budget shows
its blocker with the failing ids (`check failed — DSG-AC-COVERED, DSG-SCOPE`). Columns: Backlog, Slice,
Design, Implement, Test, Review, Deliver, Blocked, Done, Split, Superseded. `status: split` → `## Split`
as `CARD-NNN — title → split into …` (terminal); `status: superseded` → `## Superseded` as `CARD-NNN —
title → superseded by REQ-NNN` (terminal). Update header counts and `last rendered`. **If any `checks`
producer is `off`, put it in the header** (`⚠ checks disabled: design — cards reaching the design PR
unchecked`). Render the derived **`## Milestones`**: `M<N> — <title> · <done>/<total> · <not
started|in progress|complete>`, from card status — never edit `MILESTONES.md`.

Tunables (from `config.md`, authoritative): **WIP limit** (`wip_limit`, default 3); **gate policy**
(`gates`, e.g. `slice=auto · design=pr · deliver=auto`). Per gate: `slice` = `auto` (apply splits
immediately) or `manual` (stop). `design` = `pr` (no stop — the design PR *is* the review), `domain`
(stop before the design PR for `gate_layer` cards only), or `manual` (stop for every card). `deliver` =
`auto` (open without stopping) or `manual` (present the body first). Missing → `slice=auto`, `design=pr`,
`deliver=auto`.

## 3. Resolve gates & blockers first

- **Blocked cards:** show the blocker; ask the driver (re-dispatch with guidance, edit the card, or
  leave parked). Unattended: leave parked, continue.

**A gate never fires on an unchecked producer result.** §3 runs *before* §5, so both gates below carry
the check in their predicate: **the producer's check must have passed** (`<phase>-check.md` `verdict:
pass`) **or `checks.<producer>` must be `off`**. Otherwise leave the card to §5, which dispatches the
checker first.

- **Slice gate** (a slicer proposed a split **and the slice check passed** — `slice-check.md` `verdict:
  pass`, or `checks.slice: off`): `slice=auto` → apply the split immediately (carve-out below), report
  prominently. `slice=manual` → present children + `dependents_rewire`; driver picks `approve` / `revise
  (feedback)` / `keep-as-one` (→ `right_sized: true`, design transition in §5).
  - **Carve-out (sole-writer):** create each child `docs/cards/CARD-NNN-slug/card.md` from
    `card-template.md` (§1 resolution; ids continue from the current max) — **instantiation strips the
    template's frontmatter comments, so the child `card.md` carries bare frontmatter** — with `status:
    backlog`,
    **`right_sized: true`**, **`estimated_lines` copied from that child's `proposed_cards` entry** (the
    only moment it can be recorded; `DLV-SIZE`/`/retro` depend on it), the proposed
    `layer`/`type`/`depends_on` (sibling titles → new ids), and `## Notes` `Split out of <parent-id>`;
    apply `dependents_rewire`; swap parent for children on the milestone's `**Cards:**` line (mechanical
    only); parent → `status: split` with `## Notes` `Split into <ids>`, and commit **whichever of its
    `slice.md`/`slice-check.md` exist** directly to `main` (terminal records; *whichever*, because
    `checks.slice: off` means no `slice-check.md`). Commit `chore(kanban): split CARD-NNN into …`.
- **Design stop** (only when policy is `domain`/`manual`, the card qualifies, **and the design check
  passed** — `design-check.md` `verdict: pass`, or `checks.design: off`): present the `design.md`
  summary + open questions **before the design PR opens**. Driver picks `approve` (→ open) / `revise
  (feedback)` (→ re-dispatch `card-designer`) / `stop`. Under `design=pr` there is no stop.
- **Deliver gate** (`status: deliver`, **no PR currently open** — `len(pr_urls) == 0` unsplit, or `<
  split_slices` with every url so far merged): assemble **the next PR's** body (fill `pr-template.md`,
  §1 resolution) into `card_dir/pr-body.md` in **that PR's worktree** (a slice PR's is created at
  split-shipping step 1) — for a split card **slice `k`'s** body (the slice's files and the criteria
  *it* claims from `split.md`, as `CARD-NNN — <title> (slice k
  of N)` naming the siblings). `deliver=auto` → dispatch `card-deliverer`; `deliver=manual` → present
  the body first. **If the last `pr_urls` url names a PR still open, it is open — §6; never re-dispatch
  `card-deliverer` for it.** The gate fires once per PR.

**Driver input is durable (retro fuel).** Before acting on any driver response — a gate decision,
revise feedback, `open_questions` answers, unblock guidance, a keep-as-one rationale, a policy
override — append it **verbatim** to `card_dir/feedback.md` under `## YYYY-MM-DD · <phase> · <what was
asked>` (board-level → `docs/cards/feedback.md`). Pre-design-PR entries ride the design PR; later
entries ride the implementation branch; post-PR entries commit to `main`.

## 4. Schedule

- A `backlog` card is **ready** when every id in `depends_on` is `done`.
- Count in-flight cards (status in slice|design|implement|test|review|deliver). A card with an open PR
  (design, implementation, **or any slice PR**) holds its WIP slot until merged. **A split card holds
  its slot for the whole sequence.** `split`/`superseded` are terminal — neither holds a slot nor is
  scheduled. While in-flight < WIP limit and ready cards remain, **start** the next ready card,
  ordering by **`(milestone_index, layer_rank, card_id)`** ascending (layer rank from `config.layers`;
  missing → infer from title; no milestone → ∞). Soft milestone preference — never idle a free slot.
- **Starting a card:** set `started` to today. If `right_sized: true` already (intake or split child),
  skip slice → design transition (§5) directly. Otherwise `status: slice` (no branch/worktree yet).
- **Dangling dependency:** a `backlog` card whose `depends_on` names a `superseded` card can never
  become ready. Surface as drift, leave parked, tell the driver to fix with `/requirement` — never
  silently treat the dead dependency as satisfied.

## 5. Advance in-flight cards (chain until a stop)

Advance every in-flight card **as far as it can go this pump**, in waves: dispatch all dispatchable
cards' agents in parallel (one Agent-tool message), process each `result` **serially**, apply
transitions, dispatch the next wave. A card stops at a manual gate, `needs-input`, `blocked`, budget
exhausted, an open PR awaiting merge, or `done`.

**Dispatch vs. handle:** phase-doc presence in the card's `card_dir` decides — absent → dispatch;
present → handle. **Which `card_dir`:** the card's **worktree** once one exists (from the design
transition on); during `slice` there is none — key on the **primary checkout** (where
`slice.md`/`slice-check.md` sit uncommitted). The deliver check docs are on `main`. **"Handle" never
means "advance on presence alone":** every doc that can carry blocking findings carries a **`verdict:
pass|fail` header** (the check docs, and `test.md`/`review.md` too), and the *verdict* picks the row.
**Nothing load-bearing is held across a dispatch** — the next pump sees only disk, so anything that must
survive is on disk before the dispatch.

**Order the writes so every on-disk state is distinguishable, and delete evidence only when its
replacement exists.**

| on disk | means | do |
|---|---|---|
| producer doc, **no** check doc | not yet checked | dispatch the **checker** |
| producer doc + check doc `verdict: pass` | checked, cleared | advance (gate, transition) |
| producer doc + check doc **`verdict: fail`**, budget left | **rework in flight** | re-dispatch the **producer** with that doc's findings |
| producer doc + check doc **`verdict: fail`**, budget spent | parked | leave alone (`blocked`) |

**`test.md` and `review.md` are check docs in everything but name** — `card-tester` and the lens panel
*are* `card-implementer`'s checkers, so their docs carry the same `verdict: pass|fail` header and four
states. The rows below key on `status` (the failing doc goes onto the implementation *branch*; the
rework state — `status: implement`, `reworks.implement++`, `review_lenses_failed` — goes to `main`).

| on disk | means | do |
|---|---|---|
| `status: test`, **no** `test.md` | not yet tested | dispatch **`card-tester`** |
| `status: test` + `test.md` `verdict: pass` | gates green | advance to `review` |
| `status: test` + `test.md` **`verdict: fail`**, `reworks.implement < check_budget.implement` | **rework in flight** | re-dispatch **`card-implementer`** with that doc's failing gates |
| `status: test` + `test.md` **`verdict: fail`**, budget spent | parked | leave alone (`blocked`) |
| `status: review`, **no** `review.md` | panel never run | dispatch the **full panel** |
| `status: review` + `review.md` **`verdict: fail`**, `reworks.implement < check_budget.implement` | **rework in flight** | re-dispatch **`card-implementer`** with that doc's blocking findings; the state commit that increments `reworks.implement` also writes **`review_lenses_failed`**, read off which `## [<lens>]` sections carry them |
| `status: review` + `review.md` **`verdict: fail`**, budget spent | parked | leave alone (`blocked`) |
| `status: review` + `review.md` `verdict: pass`, but **some panel lens has no `## [<lens>]` section** (equivalently: `review_lenses_failed` non-empty) | **panel incomplete** | dispatch **exactly the missing lenses**; **merge** their sections into the existing `review.md` |
| `status: review` + `review.md` `verdict: pass`, **every panel lens has a section** | panel clean **and complete** | clear `review_lenses_failed` to `[]`, then **measure the branch diff and run the split sub-step** (below) |

The split sub-step is the last thing `review` does; the card stays at **`status: review`** throughout
(there is no `split` status).

| on disk (`status: review`, `review.md` `verdict: pass` and complete) | means | do |
|---|---|---|
| branch diff ≤ `size_limit`, **or** `checks.split: off` | nothing to split | advance to `deliver` (`split_slices: 0`); `checks.split: off` on an oversized diff → say so loudly (§7) |
| diff > `size_limit`, `checks.split: on`, **no** `split.md` | oversized, not yet carved | dispatch **`pr-splitter`** |
| `split.md` present, **no** `split-check.md` | carved, not yet checked | dispatch **`card-split-checker`** |
| `split.md` + `split-check.md` **`verdict: fail`**, `reworks.split < check_budget.split` | **rework in flight** | re-dispatch **`pr-splitter`** with that doc's blocking findings verbatim |
| `split.md` + `split-check.md` **`verdict: fail`**, budget spent | parked | leave alone (`blocked` — `check failed — <SPL-* ids>`) |
| `split.md` (`split_slices: 0`, or a stray `1` — a **refusal**) + `split-check.md` `verdict: pass` | the code cannot be carved | record `split_slices: 0`, advance to `deliver` — **one oversized PR**, warned (§7) |
| `split.md` (N ≥ 2) + `split-check.md` `verdict: pass`, **no** `split-acceptance.md` | carve cleared; slices not yet traced | record `split_slices: N` **and push the original branch to `origin`**, then dispatch the **`[acceptance]` lens once per slice, in slice mode** |
| `split-acceptance.md` `verdict: pass` | every slice traces to its claimed criteria | advance to `deliver` — the card ships **N** PRs |
| `split-acceptance.md` **`verdict: fail`**, `reworks.split < check_budget.split` | **rework in flight** (the carve, not the code) | re-dispatch **`pr-splitter`** with the failing acceptance findings verbatim |
| `split-acceptance.md` **`verdict: fail`**, budget spent | parked | leave alone (`blocked`) |

**Size measurement:** once `review.md` is `verdict: pass` and complete, sum `added + deleted` over the
branch diff (`origin/main...<branch>` — naming the branch, never `HEAD`), excluding `size_exclude`
paths, versus `size_limit`. **Trigger: pass+complete and diff
> `size_limit` (or `split_slices ≥ 2` at deliver, or any slice PR open) → read
`references/split-shipping.md` before acting** (measurement commands, split-layer dispatch, slice
shipping steps 0–4).

**Precedence: a `verdict: fail` wins over every other review row.** `review_lenses_failed` only selects
lenses; the incomplete-panel row is stated two ways ("a lens with no section" / "`review_lenses_failed`
non-empty") — if they disagree, believe the file.

**The check-doc discipline (canonical).** `reworks.<producer>` is incremented once, in the commit that
records the failing verdict (re-dispatching against the same doc *resumes* the loop, not a new one). On
`verdict: fail` you increment it and **leave the failing check doc in place** (the rework's input);
delete it **only in the commit that persists the reworked producer doc** — **never before its
replacement exists** (else the state equals *never checked* and an interrupted pump re-dispatches the
*checker* against unreworked work). A `checks: off` policy skips the check (warned, §7); checkers never
trigger a gate.

### Key states

The dispatch/model table says which agent fires per status; the state tables say when. This section
carries only the transition mechanics not on those tables. Rework re-dispatches the *producer* with the
blocking findings verbatim (the stale check doc deleted when the new phase doc is persisted, §5
discipline); the slicer's dispatch adds the card's **dependents**, and a slice-check `verdict: pass`
records `estimated_lines`. Returned phase docs commit to the **implementation branch**.

- **Design transition** (slice right-sized *and checked*, or a `right_sized: true` start): `git fetch
  origin main`, create branch `<type>/NNN-slug-design` + worktree **off fresh `origin/main`** via
  superpowers:using-git-worktrees, set `branch`/`worktree`, **copy whichever of
  `slice.md`/`slice-check.md` exist** from the primary checkout into the worktree's
  `docs/cards/CARD-NNN-slug/`, **commit them on the design branch**, `status: design`, then remove the
  redundant uncommitted originals — the only path either doc has onto the design branch (`DLV-DOCS`
  requires each one a running check produced). (A `right_sized: true` start has neither doc;
  `checks.slice: off` has `slice.md` only — neither absence is a `DLV-DOCS` finding.)
- **Design-check `verdict: pass`** → route the ADRs (step 3 — **the one and only ADR routing point for
  the design phase**), then the gate; **design stop** pending per policy → §3.
- **Open the design PR** (`status: design` + checked + gate passed + `design_pr_url` empty): persist
  `design.md`, `design-check.md` (and any `feedback.md`) to the branch; assemble the body from
  `design-pr-template.md` (§1 resolution); dispatch `card-deliverer` in **design mode** (push + open PR
  titled `CARD-NNN — design: <title>`). **The ADRs are already on the branch — do not route them
  again** (a second routing burns a second ADR number). Record `design_pr_url`; the design PR's deliver
  check runs next (`deliver-check-design.md`); the card awaits merge (§6). Merged → Reconcile (§0 step
  2) creates the implementation branch, `status: implement`.
- `implement`/`test`/`review`: dispatch per the table when the phase doc is absent; on `complete`
  advance. `review.md` `verdict: pass` and complete → **the split sub-step**
  (`references/split-shipping.md`) decides advance-to-`deliver`-now or carve-first.
**Deliver rows** (`status: deliver`, no PR currently open):
- **`split_slices: 0`** → deliver gate (§3) → `card-deliverer` in **implementation mode** on the card's
  own branch → **append the returned url to `pr_urls`** → dispatch card-deliver-checker in
  implementation mode → §6.
- **`split_slices: N ≥ 2`** → the card ships **N PRs, sequentially, one open at a time**; `k =
  len(pr_urls) + 1`. **Preparing slice `k` is your work** — **read `references/split-shipping.md`**
  (steps 0–4).

**Deliver check** (PR open + its check doc absent + `checks.deliver: on`): dispatch
card-deliver-checker in the PR's mode. **Persist under the name for its mode (and slice); never take
the filename on faith** — `deliver-check-design.md` (design), `deliver-check.md` (implementation,
unsplit), **`deliver-check-<k>.md` for slice `k`** (`k = len(pr_urls)`); a shared name leaves the design
check re-armed and slices 2..N unchecked. Record `actual_lines` from the implementation-mode check
(split card: slice 1's; note later slices in the report). `verdict: pass` → §6. **A `DLV-SIZE` advisory
breach is a `pass`** — surface its proposed split (§7); on a **slice PR** a breach means the split
failed `SPL-SIZE` → **park the card** (never split a split).

**A failing deliver check never re-dispatches `card-deliverer`** (no rework mode). Route each blocking
finding by what fixes it and which PR (delete the stale doc only in the commit that persists the fix):
- **`DLV-CI`** → §6a (either PR): a fail whose only blocking finding is `DLV-CI` **enters §6**, spends
  no budget, does not park; §6a triages, then deletes the doc and re-runs the check on green CI.
- **Self-fix, capped at ONE attempt per criterion per PR, no budget** (RATIONALE): `DLV-BASE`/
  `DLV-BODY-TRUE` on either PR (`{gh_command} pr edit --base main` / `--body-file`), `DLV-DOCS` on the
  design PR (commit the missing doc to the design branch). Before fixing, record `self-fix YYYY-MM-DD ·
  <id> · <PR mode> — <change>` on `## Notes` in the same commit that fixes and deletes the doc. **Same
  criterion failing again after that entry → park** (`check failed — <id> (self-fix did not clear it)`).
- **Needing a commit** (`DLV-DOCS`/`DLV-PURITY`/`DLV-BODY-TRUE` with the criterion genuinely absent, on
  the implementation PR) → **`card-implementer` in rework mode**, spends `reworks.deliver`; **on a slice
  PR, into slice `k`'s worktree and branch** (`references/split-shipping.md`). On the **design PR** —
  never `card-implementer`: `DLV-PURITY` should be impossible → `status: blocked`; `card-designer`
  (spends `reworks.deliver`) only for a design-*content* finding.
- Budget exhausted → `status: blocked` with the failing ids.

**`check_budget.deliver` is per PR**; the single `reworks.deliver` key is **reset to `0` at every PR
boundary** by Reconcile (§0 steps 2, 3), and **`reworks.implement` resets on a slice boundary** (§6a
spends it per slice PR). (RATIONALE.)

| status / condition | dispatch | model |
|---|---|---|
| slice, `slice.md` absent | card-slicer | sonnet |
| slice, `slice.md` present, `slice-check.md` absent | card-slice-checker | sonnet |
| design, `design.md` absent | card-designer | opus |
| design, `design.md` present, `design-check.md` absent | card-design-checker | opus |
| implement, `implement.md` absent (or a failing `test.md`/`review.md` present) | card-implementer | sonnet |
| test, `test.md` absent | card-tester | haiku |
| review, **`review.md` absent** | **card-lens-reviewer × lenses, in parallel** (only `review_lenses_failed`, if set) | per-lens (Section 5, review panel) |
| review, panel passed, diff > `size_limit`, `split.md` absent | **pr-splitter** | sonnet |
| review, `split.md` present, `split-check.md` absent | **card-split-checker** | sonnet |
| review, split check passed with N ≥ 2, `split-acceptance.md` absent | **card-lens-reviewer × N, in SLICE MODE** — lens `acceptance`, **one per slice**, in parallel, each carrying `slice: k`, `slices: N`, slice `k`'s path list + change types, and `split.md` | sonnet — narrow trace re-check; code already opus-reviewed (RATIONALE) |
| deliver (design PR, implementation PR, **or slice PR `k`**) | card-deliverer | haiku |
| design PR open, `deliver-check-design.md` absent | card-deliver-checker (design mode) | sonnet |
| implementation PR open, `deliver-check.md` absent (**slice PR `k` open, `deliver-check-<k>.md` absent**) | card-deliver-checker (implementation mode) | sonnet |
| **open slice PR `k` needs a commit** (§6a CI rework, §6b addressing, a `DLV-*` finding routed to the implementer) | card-implementer — **dispatched into slice `k`'s worktree, on slice `k`'s branch**, never the card's | sonnet |

**Re-dispatches and reworks use the same agent's model row; a partial panel re-run uses the per-lens
models for exactly the lenses in `review_lenses_failed`.**

(`card-intake-checker` is dispatched by `/refine` and `/requirement`, not by you.)

**Model pinning:** you run under Opus; every dispatch passes the table's `model` explicitly so no agent
inherits the session model. **`card-deliver-checker` is `sonnet`, not `haiku`** (`DLV-BODY-TRUE`
claim-by-claim diff-reading and a `DLV-SIZE` breach's split proposal are judgement/design work, and it
is the last check before a human merges); `card-deliverer` stays `haiku`. In every dispatch prompt
include `card_id`, `card_dir`, the full `card.md`, and **only the phase docs the phase needs**.

**Producers:** slicer → none; designer → slice.md; implementer → design.md (+ findings on rework);
tester → design.md's test strategy + implement.md; **the lens panel** → design.md + implement.md +
test.md, plus **the branch by name** (diffs `origin/main...<branch>`, never `HEAD`) — and **in slice
mode** additionally `slice: k`, `slices: N`, that slice's path list + change types, the criteria it
claims, `split.md`, the original branch by name; **`pr-splitter`** and its inputs →
`references/split-shipping.md`; deliverer → the PR body file path and mode, and for a slice PR the slice
worktree, slice branch, and `k of N`.

**Checkers** get the producer's *inputs* and its *output* — never its reasoning. **Every input a
criterion depends on must be passed.** These lists are the contract; each checker's agent file states
the same list — they must agree byte-for-byte:
- **card-slice-checker** → `card.md`, the **spec** (`spec_path` — it derives its own slice verdict from
  the spec before reading the slicer's), `slice.md`, the slicer's `proposed_cards` /
  `dependents_rewire` / `estimated_lines`, the card's **dependents** (`SLC-REWIRE`), `MILESTONES.md`,
  `size_limit`, `size_exclude`.
- **card-design-checker** → `card.md`, `slice.md`, `design.md` — **including its `## Proposed ADRs`
  section, which is where the ADR proposals come from** (`DSG-ADR-NEEDED` cannot be verdicted without
  them; read from the file, never a `proposed_adrs` list in memory) — the **spec sections `design.md`
  cites**, **`KNOWLEDGE.md`** (`DSG-KNOWLEDGE`), and the **ADR index** (`docs/adrs/README.md` —
  `DSG-ADR-NEEDED`).
- **card-split-checker** → `card.md`, the `worktree` and **the original branch BY NAME** — it
  re-derives the change set itself, `git diff --no-renames --name-status origin/main...<original-branch>`
  (the same `--no-renames` the splitter used), because `SPL-NO-LOSS` is worthless taken on trust —
  `split.md`, `design.md`, `implement.md`, `review.md`, `size_limit`, `size_exclude`. **The branch must
  be named, and the checker told `HEAD` is not to be trusted** (RATIONALE: HEAD-distrust). It runs
  **no** gates and builds **no** worktrees.
- **card-deliver-checker** → `card.md`, **the url of the PR it is checking** (split card: the last
  `pr_urls` entry), the PR **mode** (design | implementation), the `worktree` that PR was built in (the
  slice worktree for a slice PR), `gh_command`, `size_limit`, `size_exclude`, the card's
  `estimated_lines`, **and the `checks` policy** (or `DLV-DOCS` blocks on a doc a disabled check never
  wrote). **For a slice PR, additionally `k of N` and that the card's phase docs ride slice 1** —
  expect `implement.md`/`test.md`/`review.md` on slice 1's PR; on slices 2..N their absence is not a
  finding.

Include `worktree` once it exists. **Always include the doctrine paths** every agent reads:
`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md` and the repo's `<board_dir>/PROTOCOL-ADDENDUM.md`.
**Every `card-*-checker` dispatch additionally carries `${CLAUDE_PLUGIN_ROOT}/templates/checks/_method.md`
plus its own target's `${CLAUDE_PLUGIN_ROOT}/templates/checks/<target>.md`** (intake→`intake.md`,
slice→`slice.md`, design→`design.md`, split→`split.md`, deliver→`deliver.md`).

### The review panel (status: review)

`card-implementer`'s checker is `card-tester`, then this panel — run on the **branch diff in the
worktree, before any PR opens**. At `status: review` with **`review.md` absent** (present → the state
table handles it; never re-dispatch over a `review.md`), dispatch one `card-lens-reviewer` **per lens,
in parallel**, each given `lens`, `worktree`, **the card's `branch` by name** (diffs
`origin/main...<branch>`, never `HEAD`), `card_id`, `card.md`, `design.md`, `implement.md`, `test.md`,
and the doctrine paths (`AGENT-PROTOCOL.md`, `lenses/_shared.md`, its own `lenses/<lens>.md` — never
another's, `<board_dir>/PROTOCOL-ADDENDUM.md`). Assemble the panel from the changed files (`git -C
<worktree> diff --name-only origin/main...<branch>`).

| lens | dispatch when | model |
|---|---|---|
| acceptance | always | opus |
| design | always | opus |
| functionality | always | opus |
| security | always | opus |
| simplicity | always | sonnet |
| tests | always | sonnet |
| readability | always | sonnet |
| python | diff touches `*.py` | sonnet |
| typescript | diff touches `*.ts` / `*.tsx` | sonnet |

**Filter by `config.review_panel` (missing → `full`).** `standard` = acceptance,
functionality, tests, security + language lenses; `light` = acceptance, functionality + language
lenses. A `gate_layer` card under `standard`/`light` reviews, but report §7 warns `⚠ CARD-NNN
(gate_layer) reviewed under review_panel: <tier>`.

**Which lenses run is read off the card, never remembered.** `review_lenses_failed` empty/absent → the
full panel (filtered by the diff); non-empty → exactly those lenses (every other already passed and its
section still sits in `review.md`). The per-slice `[acceptance]` re-run after a carve is the same agent
in **slice mode** (`references/split-shipping.md`) — without the slice inputs it degrades to N identical
whole-diff reviews, a gate that cannot fail.

**Persisting the panel — you stamp the verdict, and on a partial re-run you MERGE, never overwrite.** A
**full run** (`review_lenses_failed` empty/absent) concatenates every lens's `phase_doc` into
`card_dir/review.md`. A **partial re-run** reads the `review.md` already on the branch (the rework loop
left the passing lenses' sections as the merge target) and puts the re-run lenses' sections back,
leaving every other untouched — never erasing the rest of the record. **Stamp `verdict: pass|fail`
yourself** (the agents return `### Blocking`/`### Advisory` findings): `fail` iff any `## [<lens>]`
section carries a blocking finding; commit on the implementation branch. Then follow Process-result
step 4 (rework on `fail`, recording `review_lenses_failed`; on `pass` clear it only if complete and
hand to the split sub-step). The panel does not wait for CI — `card-tester` already ran the suite.

### Process each `result` (you persist everything)

1. Parse the fenced `result` YAML.
2. Write `phase_doc` to the card's `card_dir` **in its current worktree** and commit it on the card's
   branch; rework passes overwrite the doc. **Slice phase exception:** a `status: slice` card has no
   worktree/branch — `slice.md`/`slice-check.md` are written to the primary checkout **UNCOMMITTED**,
   committed once onto the design branch by the design transition (a split parent's go direct to
   `main`). **Three carve-outs from "commit on the branch", only three:** (a) the deliver check docs
   and (b) `deliver.md` commit to `main`; (c) the deliver checker's doc is named for its **mode/slice**
   (`deliver-check-design.md` / `deliver-check.md` / `deliver-check-<k>.md`; `deliver.md` →
   `deliver-<k>.md`) — never take the filename on faith. **You stamp `verdict: pass|fail` on `test.md`,
   `review.md` and `split-acceptance.md`** (`fail` iff a gate failed / any lens (or slice) section
   carries a blocking finding). **A producer's rework result deletes the check doc it answers in the
   same commit**, never earlier. A partial lens re-run **merges** into `review.md` (review-panel §).
   Persist `estimated_lines` (from card-slicer) and `actual_lines` (from card-deliver-checker) onto
   `card.md` — `/retro` fuel.
3. **Route `knowledge`:** append `repo` entries under the right `KNOWLEDGE.md` section — `Conventions |
   Gotchas | Glossary` only, prefix `[CARD-NNN]` (no Decisions — those are ADRs) — committed to `main`;
   `personal` entries → the Claude project memory directory.
   **Route `proposed_adrs`** via the **`adr`** skill (`card_id`, today's ISO date, the list, the card's
   **worktree** as write target — ADRs land on the current branch and merge via its PR). **Design-phase
   ADRs are held on disk until the design check passes** (the `adr` skill reserves a number on write;
   never write one a checker may reject) — the proposals live in **`design.md`'s `## Proposed ADRs`
   section**, routed from that section, never a remembered list: on **`verdict: pass`** (or
   `checks.design: off`) parse `## Proposed ADRs` off disk and route only the proposals the card's
   `adrs:` list does not already account for (idempotent — `adrs:` is written *as part of* routing); on
   **`verdict: fail`** route nothing. **Numbering:** `NNNN = max(files under docs/adrs/ on main, every
   id in any card's adrs: list) + 1`; appending the id to `adrs:` reserves it before the file merges.
4. **Apply the transition** (persist first, steps 1–3; the state tables carry the rework mechanics):
   - `needs-input` → surface `open_questions`, re-dispatch on answers; unattended, leave & continue.
   - `blocked` from **implementer** → `status: blocked`. From **`pr-splitter`** (couldn't build its
     throwaway worktree with the FULL change — broken env, not entangled code) → `status: blocked` with
     the real output; no rework, NOT a refusal (`references/split-shipping.md`); never call it "refused".
   - `blocked`/blocking finding from **tester or the panel WHOLE-DIFF** → rework `card-implementer` per
     the state table (increment `reworks.implement`, leave the failing doc, re-dispatch with findings
     merged; else `blocked`). **From the panel, the same commit writes `review_lenses_failed`** (the
     failing lenses; cleared to `[]` when clean) and clears the stale findings thus: `test.md` **deleted
     outright**; `review.md` **stripped** (remove only the `review_lenses_failed` `## [<lens>]` sections,
     restamp survivor `verdict: pass`; delete outright if none survive), the stripped `review.md`
     **committed on the implementation branch** — the missing sections, not the verdict, mark the panel
     **incomplete**.
   - **Panel SLICE-MODE** finding reworks **`pr-splitter`** (spends `reworks.split`), NOT
     `card-implementer` — read the mode (`references/split-shipping.md`).
   - **Reject an INCOMPLETE checker result (before drop & verdict):** its `criteria:` map must verdict
     **every** id in its target's `ids.md` line + addendum `LOCAL-` ids; compare against the set you hold
     from §1. Missing any → **MALFORMED**: don't advance/gate/persist, re-dispatch naming the omitted ids;
     costs the producer nothing (no `reworks`/`check_budget`, no park); a persistent skimmer → drift (§7).
   - **Drop findings with no `location` (after completeness, before verdict):** if none blocking remain,
     verdict is `pass` — persist the ADJUSTED verdict (`verdict: pass — adjusted by the orchestrator`) +
     a `## Dropped findings` section (each verbatim + why); a drop leaving blockers keeps `verdict: fail`.
   - `verdict: fail` from **any checker** (surviving the drop) → rework its producer per the check-doc
     discipline: **slice → `card-slicer`; design → `card-designer`; split → `pr-splitter`** (from
     `split-check.md` *or* `split-acceptance.md`; a **refusal** spends nothing); **deliver → *not*
     `card-deliverer`**, route per the deliver rows. Budget spent → `status: blocked` `check failed —
     <ids>`. **Advisory findings never rework.**
   - **A producer's `complete` does not advance the card — its checker does:** for
     `card-slicer`/`card-designer`, persist then (if `checks: on`) dispatch the checker and apply nothing
     else this wave; only `checks: off` advances immediately (report says unchecked). **`card-deliverer`
     is the exception — record its `complete` immediately** (append the url — it is the deliver-check
     precondition, and a defer ships slice `k` twice).
   - `verdict: pass` from a **checker** → producer cleared; record `estimated_lines`/`actual_lines`, then
     apply the row matching the producer's earlier `gate`. **The `gate` rows match a PRODUCER `result`
     only** (checkers return `phase: check` `gate: none`, handled by the verdict rows): `gate: slice` →
     slice gate (§3); `gate: none` from **card-slicer** → `right_sized: true`, design transition; `gate:
     design` → design stop (§3) then design-PR step; `gate: none` from **implementer/tester/panel/`pr-splitter`**
     → advance & continue (panel → split sub-step, not `deliver`; `pr-splitter` → split applies
     automatically; tester/panel only on your stamped `pass`, panel only on a `complete` `review.md`).
     `gate: none` ≠ "clean" or "finished".
   - `complete` from **deliverer** → record url into `design_pr_url` (design) or **append to `pr_urls`**
     (implementation, incl. slices, shipping order); implementation mode commits `deliver.md` → `main`
     (`deliver-<k>.md`); design mode persists no `phase_doc`. Next wave dispatches `card-deliver-checker`.
5. Commit state changes (`card.md`, `BOARD.md`, `KNOWLEDGE.md`) to `main` with a Conventional Commit
   (`chore(kanban): …`), ending with the project `Co-Authored-By` trailer, and **push** (`git push
   origin main`; on rejection retry after `git pull --rebase origin main`).
   **Stage the exact paths you intend to commit — always `git add <path> …`, naming each file. Never
   `git add -A`, `git add .`, `git add <board_dir>/`, or `git commit -am`.** This is the mechanic that
   keeps the slice docs off `main`: a `status: slice` card's `slice.md`/`slice-check.md` sit
   deliberately untracked in the same directory as the `card.md` this step commits, and a blanket stage
   sweeps them onto `main` (the `DLV-DOCS` livelock; RATIONALE).
   If pushes to `main` are refused by branch protection, say so in the report.

## 6. PR open — CI gate, review-complete addressing

A card with an open PR holds its WIP slot until merged (§4); the review panel already ran (§5), so §6 is
CI, the human's review, and addressing it. **On a slice PR** (`k = len(pr_urls)`, one open at a time)
everything here applies unchanged per slice, and **every dispatch carries slice `k`'s branch/worktree,
never the card's** (`references/split-shipping.md`).

**Entry:** a card enters §6 when its deliver check returns `verdict: pass`, when `checks.deliver` is
`off`, **or when its only blocking deliver finding is `DLV-CI`** (not a park, no budget — §6a triages
it). Any *other* blocking deliver finding routes per §5 first.

### 6a. CI gate — nothing else happens on the PR until checks pass

Every pump, before addressing, check the PR's CI: `{gh_command} pr checks <url>`.
- **No checks configured** → proceed (the gate requires nothing *failing*, not that checks exist).
- **Pending / running** → do nothing this pump; report "CI running".
- **All green** → proceed to 6b. **If the card arrived on a `DLV-CI` failure**, delete the deliver
  check doc (per mode/slice) and let the next pump re-run the deliver check against green CI.
- **Failing** → read the real logs (`gh run view <run-id> --log-failed`) and classify:
  - **Actionable** (branch-caused): dispatch `card-implementer` in rework mode with job + step + log
    excerpt (design PR: `card-designer`), PR open; **on a slice PR into slice `k`'s worktree/branch**
    (`references/split-shipping.md`). Consumes the producer's budget (implementation-PR →
    `reworks.implement`, reset per slice; design-PR → `reworks.design`); exhausted → `blocked`.
  - **Infrastructure** (Actions outage, runner provisioning, stuck/cancelled checks, rate limiting):
    flag it, `gh run rerun <run-id> --failed`, note the retry (date + reason) on `## Notes`, re-check
    next pump. After **3** without progress → `status: blocked` ("CI infrastructure unavailable"). Never
    treat a red PR as reviewable.
  - **Ambiguous / flaky** (failed once, passes locally, no relevant diff): infrastructure treatment
    first; a second consecutive failure of the same job is real.

### 6b. Address loop (every pump per open PR, CI green)

Nothing is actioned until the human signals the review is **complete**; then every comment they
authored is addressed. Never act before the signal.
1. **Detect the review-complete signal** — either: a **submitted review** by a non-app user
   (`.../pulls/{n}/reviews`) with state `COMMENTED`/`CHANGES_REQUESTED`/`APPROVED` (`PENDING` never
   counts); or a top-level comment whose trimmed body equals `REVIEWED` (case-insensitive) by a non-app
   user (`.../issues/{n}/comments`). No signal → do nothing; report "awaiting review".
2. **Assemble the actionable set** — every **human-authored** item the signal authorises, skipping any
   already carrying a `[kanban]` reply/marker: human-authored inline comments (`.../pulls/{n}/comments`)
   and each human-submitted review's non-empty summary body (idempotency keyed to the review id via a
   top-level `[kanban]` marker). "App" = the identity the flow posts as; else human. Exclude the
   `REVIEWED` comment. **Scope by signal:** a submitted review authorises only its own inline comments +
   body; a `REVIEWED` comment authorises every loose inline comment at/before its timestamp.
3. **Dispatch. Implementation PR:** `card-implementer` in PR-comment mode with the items verbatim (id,
   path, line, body; review-body items flagged as summary) — fixes exactly those (test-first), runs the
   fast gates, commits, pushes. **On a SLICE PR, into slice `k`'s worktree and branch**
   (`references/split-shipping.md`). **Design PR:** re-dispatch `card-designer`; commit its revised
   `design.md` (and any superseding ADR proposals via `adr` routing) to the design branch and push.
4. **Reply once per item** — in its thread (`.../pulls/{n}/comments/{id}/replies`) or a top-level
   `[kanban]` comment (review body): `[kanban] Addressed in <commit-url> — <explanation>` (`<commit-url>`
   = full `https://github.com/{owner}/{repo}/commit/<sha>`). For an item returned in `blockers`, reply
   `[kanban] Not actioned — <reason>` and surface it. One reply per item. **Never resolve threads**,
   never approve or dismiss. **Once every item a signal authorised has its reply, post ONE top-level
   `[kanban] review addressed — <review id | REVIEWED@<timestamp>>` marker** (idempotent: skip if that
   marker already exists) — threaded replies are invisible to `--json comments`, and this marker is what
   lets §0.5's probe read the signal as addressed instead of re-running a full pump every cycle.

These fixes are human-directed and consume no rework budget. Merge detection stays with Reconcile (§0).
A healthy card needs exactly three human actions: merge the design PR, complete a review (or comment
`REVIEWED`), merge the implementation PR.

## 7. Report

Print a concise digest: what advanced (and how far it chained), design PRs opened/merged,
implementation PRs opened (**split card: `slice k/N`**), what was auto-reworked (card, findings,
`reworks`), what awaits a gate/input/merge, splits, amendments applied (card, action, REQ), blocks,
free slots, per-milestone progress.

**The split layer** — every item is `/retro` fuel, the first two also the driver's decision:
- **Splits performed:** `CARD-NNN — branch diff <lines> > size_limit <n> → split into N slices`, and
  where shipping is up to (`PR 2/3 open`). Every firing is a card the slicer under-estimated.
- **Refusals — PROMINENTLY, reason VERBATIM:** `⚠ CARD-NNN — pr-splitter REFUSED to split a
  <lines>-line branch: "<reason>". It ships as ONE oversized PR (<url>).` **An oversized PR is bad; a
  red `main` is worse.**
- **Split-layer ENVIRONMENT failure** (`pr-splitter` returned `blocked`): `⚠ CARD-NNN — pr-splitter
  could not BUILD its scratch worktree with the whole change applied. Broken environment, not entangled
  code.` Quote the command/output. **Never report as a refusal**, never say "entangled".
- **Slice PR still oversized** (`DLV-SIZE` on slice `k/N`): the split failed and was not retried (never
  split a split) — a `pr-splitter` defect; the driver decides.
- **Completeness backstop failure** — **loudest item:** `🛑 CARD-NNN — all N slice PRs merged, but
  <original-branch> still holds changes main does not: <unshipped content / deletions>. WORK WAS LOST —
  the splitter dropped it and SPL-NO-LOSS missed it. Branch preserved (local + origin).` Name paths and
  directions.
- **Original branch pushed** on a recorded split; **orphan slice PR adopted** (a pump died after `gh pr
  create`; adopted not re-created, `deliver.md` missing); **superseded card with a merged slice** (`⚠
  CARD-NNN superseded, slices 1..k of N MERGED — main holds a PARTIAL change; <original-branch> carries
  slices k+1..N, NOT deleted`); `checks.split: off` on an oversized branch.

Flow metrics per finished card (`started → delivered` elapsed, `reworks`); **ADRs written this pump**
(`ADR-NNNN — title → CARD-NNN`, and which PR carries each); `MILESTONES.md` drift (surface, don't
edit); if `migration_needed` (§1): **"Un-migrated doctrine copies or a stale `kanban_flow_version` —
run `/migrate`."** **Every 5 cards done**, suggest `/retro`.

**Check layer:** which checks ran and their verdicts; any producer reworked by its checker (card, ids,
`reworks.<producer>`); any card parked on an exhausted budget; any **deliver finding you fixed
yourself** (the edit + re-check verdict) or **parked on a self-fix that did not clear**; any **checker
re-dispatched for a malformed result** (card, checker, omitted ids); any **`DLV-CI` handed to §6a**; any
**legacy `test.md`/`review.md` deleted** for no `verdict:` (§0). Name every card that advanced
**unchecked** (`checks` policy `off`), and surface a `DLV-SIZE` breach **prominently** with the proposed
split verbatim. **If any `checks` producer is `off`, warn every pump** — name it and the consequence
(`slice=off`: *`size_limit` unenforced before code, only `DLV-SIZE`'s after-the-fact warning remains*;
`split=off`: *an oversized branch is never carved*).

## Rules

Canonical statements live at their usage site in the body; these are the invariants worth a standalone
reminder.

- Sole writer, once a card leaves backlog, of `card.md`, `BOARD.md`, `KNOWLEDGE.md`, and `docs/adrs/`
  (via the `adr` skill only — agents propose, never write). `/refine`/`/requirement` own backlog cards
  and `MILESTONES.md` (your only `MILESTONES.md` edit is the parent→children split swap). **Never write
  `spec_path`.**
- Two PRs per card **at minimum**, in order: the design PR merges **before** the implementation branch
  is cut. Never bundle code into a design PR. An oversized branch ships implementation as **N PRs**.
  `superseded` is terminal like `split` (set only by draining an amendment, §0).
- **`done` needs both halves:** every `pr_urls` url merged **AND** the completeness backstop passes,
  **before any teardown** — either direction non-empty is a serious defect (§0 step 3;
  `references/reconcile-edge-cases.md`). **Never delete the original branch before the backstop passes**
  — it is the sole copy of every unshipped slice, pushed to `origin` when the split is recorded; a
  superseded card with any merged slice keeps it too. [dangerous invariant]
- **`--no-renames` on every split-layer `--name-status`** — a rename is always `D old` + `A new`,
  `SPL-FILES` keeps both halves in one slice, nothing consumes an `R`. [dangerous invariant; canonical:
  `references/split-shipping.md`]
- **A stale check doc is deleted only in the commit that persists the work answering it** — its presence
  distinguishes "rework in flight" (re-dispatch the **producer**) from "never checked" (dispatch the
  **checker**); same for `test.md`/`review.md`. [dangerous invariant; canonical: §5]
- **Slice docs are never committed to `main`** (except a split parent's) — stage exact paths, never `git
  add -A`. [dangerous invariant; canonical: intro + §5 step 5]
- **Ground truth is never taken from `HEAD`** — every split-layer diff names the branch; the split
  layer never recurses (`references/split-shipping.md`). **Self-fix deliver remedies capped at one
  attempt per criterion per PR** (no budget, so the `## Notes` entry + cap is the only bound).
  **`card-deliverer` has no rework mode**; `DLV-CI` → §6a.
- **Every doc that can carry blocking findings carries a `verdict: pass|fail`**, stamped by you; presence
  alone never advances a card. **A checker's result must verdict every criterion or it is malformed**
  (you hold the id set from §1). **A gate never fires on an unchecked producer result.** **Checkers are
  terminal.** Every producer is checked before its gate unless `checks.<producer>` is `off` — say so
  loudly every pump.
- **`review_lenses_failed` lives on the card**, written with the `reworks.implement` it caused; only
  those lenses re-run (empty → full panel), the rework loop **strips** their sections from `review.md`
  and the re-run **merges** back, never overwriting; a `review.md` missing a section is incomplete.
- **A card must be recoverable from disk alone** — nothing load-bearing held across a dispatch (ADR
  proposals in `design.md`'s `## Proposed ADRs`, findings in the check doc).
- PR comments actioned only after a review-complete signal, on green CI; every human comment answered
  with a `[kanban]` reply, never resolving/approving/dismissing. **No agent comments on a PR.**
- All branches off `main`; all PRs target `main` — a slice branch cut from a fresh `origin/main` already
  holding its predecessors. Phase docs ride their half's PR; the **deliver checks and `deliver.md`
  commit to `main`**, named by mode and slice.
