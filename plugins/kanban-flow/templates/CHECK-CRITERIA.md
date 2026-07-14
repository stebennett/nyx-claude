# Check criteria

One `card-*-checker` agent is dispatched per producer. Each checker reads the shared **Method**
section plus **only its own target's section**. Criterion ids are **stable and permanent** — `/retro`
aggregates verdicts by id across cards, so an id is never renamed, reused, or renumbered once
shipped. Retiring a criterion means deleting its row, never repurposing its id.

Read this file at the absolute path your dispatch provides. Then layer the repo's
`PROTOCOL-ADDENDUM.md` `## Check criteria — <target>` section on top, if present: those are
project-specific criteria, carry a `LOCAL-` id prefix, and are owned by `/retro`. Criteria in *this*
file are plugin-owned and are never edited by `/retro`.

## Method (every checker — this is how you avoid rubber-stamping)

1. **Derive independently, then compare — and note that the artifact contains the producer's
   reasoning, so the discipline is on you.** You are given the producer's *inputs* and its *output*.
   The output is not a bare answer: `slice.md` and `design.md` argue their case, and reading that
   argument first is the fastest way to end up agreeing with it. Nothing withholds it from you, so
   the defence is **procedural**: form your own answer **from the inputs, before you open the
   artifact** — what tasks *should* this design have, how big *should* this card be — write it down,
   and only then read the producer's and diff the two. A disagreement you reached independently is a
   finding; a disagreement you failed to think of because the producer's rationale was persuasive is
   the failure mode this whole layer exists to prevent.
2. **Verdict every criterion — and know that this is checked.** Return a row for every id in your
   section (plus every `LOCAL-` id the addendum adds) — `pass`, `fail`, or `na`. An omission is a
   **malformed result**: the orchestrator holds the same id set it handed you, compares your table
   against it, and on any missing id **does not advance the card, does not apply the gate, and
   re-dispatches you** with the omitted ids named. A `pass` over a partial table is not a pass. `na`
   needs evidence for *why* it does not apply.
3. **Evidence, not adjectives.** Each verdict's `evidence` says what you checked and what you found,
   citing a line: `"design.md:31-58 — 6 tasks; AC-3 (offline retry) maps to none"`. Never
   `"looks complete"`. A passing criterion with no evidence of the check is a skim, and `/retro` will
   read it as one.
4. **Every finding cites a location.** A finding with no `location` is invalid and the orchestrator
   drops it. If you cannot point at a line, you do not have a finding — you have a suspicion. Say so
   in the evidence and pass.
5. **The blocking bar.** `blocking` means: shipping this artifact as-is causes a defect, a rework, or
   a lie. Everything else is `advisory`. Do not inflate — a blocking finding costs the producer a
   rework loop from a finite budget, and a card that burns its budget on nits parks for the driver.
6. **Rebuttal test.** Before writing a blocking finding, imagine the producer's strongest one-line
   defence ("the spec explicitly scopes that out", "that's covered by task 4"). If the defence wins,
   drop it. If you cannot tell, make it advisory.

## intake

Checks the card set proposed by `/refine` or `/requirement`, **before** the driver sees it. Your
inputs: the spec (at `spec_path`), the proposed cards, the milestone plan, the existing board, and
`size_limit` / `size_exclude` (for `INT-SIZED`).

| id | criterion | severity when failed |
|---|---|---|
| `INT-AC-OBSERVABLE` | every acceptance criterion is observable and testable — it names something you could watch happen, not an intent | blocking |
| `INT-REQ-RESOLVES` | every `reqs` id exists in the spec and is not superseded | blocking |
| `INT-VERTICAL` | each card is a vertical slice with user-visible value, not a horizontal layer task | blocking |
| `INT-COVERAGE` | the card set covers the requirement — nothing in the REQ is unclaimed by any card | blocking |
| `INT-NO-OVERLAP` | no two cards claim the same work | blocking |
| `INT-DAG` | `depends_on` is acyclic and every id names a real card or a proposed sibling | blocking |
| `INT-MILESTONE` | every card sits in exactly one milestone, and no card depends on a card in a later milestone | blocking |
| `INT-SIZED` | **no proposed card is projected to exceed `size_limit`** (see *The intake size estimate* below) | blocking |

**Walk:** Read the requirement(s) first and list, in your own words, the observable behaviours it
demands. Only then read the proposed cards. Map behaviours → cards: an unclaimed behaviour is
`INT-COVERAGE`; two cards claiming one behaviour is `INT-NO-OVERLAP`. Then read each acceptance
criterion and ask *what would I run to see this?* — "the system is robust" fails `INT-AC-OBSERVABLE`;
"a request with no auth header returns 401" passes. Build the `depends_on` graph by hand and walk it
for cycles and for milestone-order violations. Finally, size every card (below).

### The intake size estimate (`INT-SIZED`)

**A card the intake skill marks `right_sized: true` skips the slice phase entirely.** It therefore
never meets `SLC-SIZE`, never gets an `estimated_lines`, and is never sized again before its code is
written — the only size enforcement left to it is `DLV-SIZE`, which is *advisory* and fires after the
fact, on a PR that is already open. **You are that card's only pre-code size check.** This is the same
argument the split carve-out makes for giving a split *child* an `estimated_lines` ("no slicer will
ever run on it again"), and it applies here for exactly the same reason.

**Method — identical to `SLC-SIZE`'s.** For **each proposed card**: walk its acceptance criteria and
name the files that must change. Use `Grep`/`Glob` on the real codebase — find the modules that
already exist, and judge each as *new file* vs *edit*. Estimate changed lines per file, **counting
tests** (this project is TDD; a test file roughly matches the code it drives). Sum them. Show the
per-file working in your `evidence` — a bare number is not evidence. Only `size_exclude` paths are
omitted (lock files, vendored deps — `config.md`). Tests count.

**Any card whose estimate exceeds `size_limit`** (`config.md`, default 500) → **blocking.** The intake
skill must slice that card smaller and re-check; each resulting card is subject to `INT-SIZED` in turn,
so splitting one over-budget card into two over-budget cards does not pass either.

**Return `estimated_lines` for every proposed card** in your `phase_doc` — whether or not it breaches.
The intake skill persists it onto the card it writes, so a card that arrives at the board already
right-sized still carries a size estimate: `DLV-SIZE` has a baseline to report `actual_lines` against,
and `/retro`'s under-estimation signal can see the card at all. Leave it empty at intake and it is
empty forever.

**Don't flag:** an estimate that stays comfortably under the limit but that you would have pitched
somewhat differently (you are checking for a *ceiling breach* and for defensible reasoning, not
auditing arithmetic); a card whose size you cannot estimate because the codebase does not exist yet
(a greenfield first card) — say so in the evidence, give your best bound from the acceptance criteria
alone, and only fail it if even that bound breaches.

**Don't flag:** card granularity you would have chosen differently but that meets `INT-VERTICAL`
(taste is not a defect); a card whose acceptance criteria are thin *because the requirement is thin*
— that is a spec problem, and belongs in your `phase_doc` prose, not as a card finding.

## slice

Checks `card-slicer`. Your inputs: `card.md`, the spec, `slice.md`, the slicer's `proposed_cards` /
`dependents_rewire` / `estimated_lines`, and the card's dependents.

| id | criterion | severity when failed |
|---|---|---|
| `SLC-VERDICT` | the keep-as-one call is justified, or the split is genuinely necessary — not splitting for its own sake | blocking |
| `SLC-SIZE` | **no card is projected to exceed `size_limit`** (see *The size estimate* below) | blocking |
| `SLC-CHILD-VERTICAL` | each proposed child is itself a vertical slice with observable behaviour | blocking |
| `SLC-CHILD-AC` | each child's acceptance criteria are observable and faithfully inherited from the parent | blocking |
| `SLC-NO-LOSS` | the union of the children covers the parent — nothing was dropped in the split | blocking |
| `SLC-REWIRE` | `dependents_rewire` names **every** card that `depends_on` the parent, with correct new deps | blocking |
| `SLC-DAG` | child `depends_on` is acyclic and references only siblings or real cards | blocking |

### The size estimate (`SLC-SIZE`)

**Produce your own estimate before reading the slicer's.** That is the whole point of a checker — a
number you inherit is a number you have not checked.

Method: for each card (the parent on a keep-as-one verdict; each child on a split), walk its
acceptance criteria and name the files that must change. Use `Grep`/`Glob` on the real codebase —
find the modules that already exist, and judge each as *new file* vs *edit*. Estimate changed lines
per file, **counting tests** (this project is TDD; a test file roughly matches the code it drives).
Sum them. Show the per-file working in your `evidence` — a bare number is not evidence.

Compare with the slicer's `estimated_lines`. Two things fail:
- **Your estimate for any card exceeds `size_limit`** (`config.md`, default 500) → **blocking. The
  card must be split.** The slicer is re-dispatched and must produce children instead. Each child is
  then subject to `SLC-SIZE` in turn, so a split into two over-budget children does not pass either.
- **The slicer's estimate is indefensible against yours** (wildly optimistic with no reasoning you
  can reconstruct) → blocking even if both numbers land under the limit, because the next card will
  be estimated the same way.

Only `size_exclude` paths are omitted from the count (lock files, vendored deps — see `config.md`).
Tests count.

**Don't flag:** an estimate that differs from yours by a modest margin and stays well under the limit
(you are checking for a *ceiling breach* and for *reasoning*, not auditing arithmetic); a keep-as-one
verdict on a genuinely atomic invariant (the slicer's own doctrine says prefer right-sized when
borderline — respect it unless the size estimate says otherwise).

## design

Checks `card-designer`. Your inputs: `card.md`, `slice.md`, `design.md`, the spec sections it cites,
`KNOWLEDGE.md`, and the ADR index.

| id | criterion | severity when failed |
|---|---|---|
| `DSG-AC-COVERED` | every acceptance criterion maps to at least one design task | blocking |
| `DSG-SPEC-FIDELITY` | `## Spec references` cite real spec sections, and the design contradicts none of them | blocking |
| `DSG-TASK-TDD` | the task list is file-level and TDD-ordered — a test precedes the code it drives | blocking |
| `DSG-DOCTRINE` | where the card's domain touches them, the design honours standing doctrine (below) | blocking |
| `DSG-ADR-NEEDED` | expensive-to-reverse decisions are proposed as ADRs, and none duplicates or silently contradicts a standing one | blocking |
| `DSG-KNOWLEDGE` | the design does not re-tread a gotcha already recorded in `KNOWLEDGE.md` | advisory |
| `DSG-SCOPE` | in/out of scope is explicit, and nothing in the design falls outside the card's acceptance criteria | blocking |
| `DSG-NO-CODE` | the design branch is docs-only — the design proposes no code files as *written*, only as tasks | blocking |

**`DSG-DOCTRINE` — what to check.** This is where `AGENT-PROTOCOL.md`'s Doctrine section stops being
advice and becomes something verified. For each doctrine rule, decide whether the card's domain
touches it; if it does, the design must say how it is honoured, and `na` is only correct when it
genuinely does not apply:
- **Spec outranks training** — the design cites the spec for every rule it implements, not memory.
- **Numeric precision** — any money/precision value: the project's decimal/rounding primitive is
  named, never a language default or binary float.
- **Parallel derived values** — where the spec defines two related computed quantities, the design
  names *which one* each consumer gets.
- **As-of semantics** — per-record figures come from the record's stored snapshot, not live reference
  data; replay order is deterministic (date, then id).
- **Determinism** — fixed clock, fixed seed, ordered queries, no network in tests.

**Walk:** Read `card.md`'s acceptance criteria and write your own list of the tasks you would expect,
*before* reading `design.md`'s task list. Then read the design. Map criteria → tasks (a criterion
with no task is `DSG-AC-COVERED`); map tasks → criteria (a task serving no criterion is `DSG-SCOPE`).
Open every spec section cited and confirm it says what the design claims. Read `docs/adrs/README.md`
before judging `DSG-ADR-NEEDED`.

**Don't flag:** a design choice you would have made differently that satisfies the criteria and
violates no doctrine (`DSG-*` is not a taste review — the lens panel reviews the code later); missing
generality the spec does not ask for (YAGNI is working); an ADR-worthy decision the design *does*
propose as an ADR.

## deliver

Checks `card-deliverer`, after the PR is open. Your inputs: `card.md`, the PR url and its mode
(design | implementation), the PR body, the branch, and the **`checks` policy** — a check that is
`off` never wrote its check doc, and its absence is not a finding.

| id | criterion | severity when failed |
|---|---|---|
| `DLV-BASE` | the PR targets `main` and was cut from the right branch | blocking |
| `DLV-BODY-TRUE` | every claim in the PR body is supported by the diff; no claimed acceptance criterion is unimplemented | blocking |
| `DLV-SIZE` | **actual changed lines are within `size_limit`** (implementation PRs only — see below) | **advisory, escalated** |
| `DLV-DOCS` | the phase docs that should ride this PR are on it — design PR: `slice.md`, `design.md`, `slice-check.md`, `design-check.md`, ADRs; implementation PR: `implement.md`, `test.md`, `review.md`. **A check doc is expected only when its check is `on`** (`checks` in your dispatch): a disabled check writes no doc, and a right-sized card never sliced, so neither absence is a finding | blocking |
| `DLV-PURITY` | a design PR carries no code; an implementation PR carries no unrelated changes | blocking |
| `DLV-CI` | CI is green or running; the PR was not opened on a known-red branch | blocking |

**Evidence commands** (read-only — you never mutate GitHub):
```bash
{gh_command} pr view <url> --json baseRefName,headRefName,body,state,files
{gh_command} pr checks <url>
git -C <worktree> diff --numstat main...HEAD
```

### `DLV-SIZE` — measured, advisory, escalated

Count actual changed lines: sum `added + deleted` from `git -C <worktree> diff --numstat main...HEAD`,
**excluding** paths matching `size_exclude` (`config.md`). **Tests count.** Design PRs are exempt — a
long design document is not a code-review problem; return `na`.

**The card's own phase docs are excluded from the count.** That diff also carries `implement.md`,
`test.md`, `review.md` (concatenated across the whole review panel), `pr-body.md` and `feedback.md`
under the board dir — which shipped `size_exclude` omits as `docs/cards/**`. Do not count them, even
if a local `size_exclude` forgets to: the budget measures **the change a human must review, not the
paperwork describing it**, and `estimated_lines` — the number you report `actual_lines` against —
estimated code + tests only. Counting the docs inflates every card against its own estimate and can
breach `size_limit` on documentation volume alone. State in your `evidence` which paths you excluded.

**A breach is `advisory`, not `blocking` — deliberately.** The code is written and the PR is open;
re-dispatching `card-deliverer` cannot un-write it, so a blocking verdict would burn rework budget
against a remedy that does not exist at this phase.

**But it is not a shrug.** On a breach you **must propose a concrete split** in the finding's
`remedy`: which commits or file groups should become which smaller PRs, and in what order. Name them.
The orchestrator surfaces this prominently and the driver decides whether to land the PR or split it.

Always report `actual_lines: <N>` in your `phase_doc` even when the criterion passes — the
orchestrator records it on the card, and `/retro` reads it against `estimated_lines` to find a slicer
that systematically under-estimates.

**Don't flag:** a `size_exclude` file's size (that is what the exclusion is for); a design PR's length
under `DLV-SIZE`; CI that is merely still running (`DLV-CI` fails only on *red*, not on *pending*).
