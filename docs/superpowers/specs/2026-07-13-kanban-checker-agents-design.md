# Checker agents for kanban-flow

**Date:** 2026-07-13
**Status:** Approved — ready for implementation planning
**Plugin:** `plugins/kanban-flow`

## Problem

Every agent in kanban-flow can be wrong, but only one of them is checked.

`card-implementer`'s work is verified three times — by `card-tester`, by `card-reviewer`, and by the
`pr-expert-reviewer` panel on the PR. Every other agent ships unverified:

- `card-slicer` — under the default `slice=auto` policy its proposed split is applied to the board
  with no review at all.
- `card-designer` — under the default `design=pr` there is no interactive stop; the only check is a
  human reading the design PR.
- `card-tester` — nothing verifies it ran the suite it claims to have run, or that its coverage
  numbers are real.
- `card-deliverer` — nothing verifies the PR body matches the diff, that the branch was rebased, or
  that the PR targets the right base.
- intake (`/refine`, `/requirement`) — a malformed acceptance criterion or a bad slice here poisons
  every downstream phase, and the only check is the driver's attention.

The doctrine in `AGENT-PROTOCOL.md` compounds this. It carries hard-won rules — use the project's
decimal primitive, never blend parallel derived values, respect as-of semantics — that nothing
verifies. They are advice a designer may or may not have honoured.

There is also no ceiling on card size. Whether a card is "a vertical slice" is a judgement call the
slicer makes and nobody audits, so a card can reach the driver as a several-thousand-line PR that no
human will review properly. Nothing in the system predicts how big a card will be, and nothing
measures how big it turned out.

Separately, the PR review panel has a ceremony problem. The eight lenses post inline comments on the
open PR, and nothing is actioned until the driver signals review-complete and 👍s the comments they
want fixed. In practice the driver agrees with almost all of them, so the triage step is pure
overhead standing between a known-good finding and its fix.

## The model: producers and checkers

Every agent is classified as exactly one of two things.

**Producers** create artifacts and can be wrong:

| Producer | Produces |
|---|---|
| intake (`/refine`, `/requirement`) | the card set + milestone plan |
| `card-slicer` | `slice.md`, `proposed_cards`, `dependents_rewire` |
| `card-designer` | `design.md`, `proposed_adrs` |
| `card-implementer` | code + `implement.md` |
| `card-deliverer` | the PR |

**Checkers** verify a producer's output. **Checkers are terminal: nothing checks a checker.** This is
what terminates the regress implied by "every agent has a checker", and it is stated in doctrine so
that no checker-checker is ever added. A checker's backstop is the human — the driver at the intake
and slice gates, the reviewer at the two PR merges.

| Producer | Its checker(s) | Status |
|---|---|---|
| intake | `card-intake-checker` | **new** |
| `card-slicer` | `card-slice-checker` | **new** |
| `card-designer` | `card-design-checker` | **new** |
| `card-implementer` | `card-tester`, then the lens review panel | exists — re-declared as checkers |
| `card-deliverer` | `card-deliver-checker` | **new** |

Producers never check. Checkers never produce, never write to disk, and never mutate GitHub.

## Agent roster changes

**New:** `card-intake-checker`, `card-slice-checker`, `card-design-checker`, `card-deliver-checker` —
four separate agent files, each declaring its own tools and model. The shared checker contract lives
once in `AGENT-PROTOCOL.md` (below); the agent files reference it rather than restating it.

**Renamed:** `pr-expert-reviewer` → `card-lens-reviewer`. It is no longer PR-scoped: it reviews the
branch diff in the worktree and returns findings. It no longer touches GitHub.

**Deleted:** `card-reviewer`. It is fully subsumed by the lens panel (below).

**Amended:** `card-slicer` — gains an `estimated_lines` field on its result (see the size budget).

**Unchanged:** `card-designer`, `card-implementer`, `card-tester`, `card-deliverer`.

## The checker contract

A new **Checker contract** section in `AGENT-PROTOCOL.md`.

**On dispatch a checker receives** the producer's *inputs* (`card.md`, the spec sections the artifact
cites, the prior phase docs the producer had) and the producer's *output artifact* — but **never the
producer's reasoning**. The checker derives its own view from the same inputs and compares. A checker
that reads the producer's justification is only agreeing with it.

**A checker writes nothing and mutates nothing.** It returns a `phase_doc`; the orchestrator persists
it, as with every other phase agent. Read-only tools throughout, with one exception:
`card-deliver-checker` needs read-only `gh`/`git` commands to inspect the PR it is checking. No
checker dispatches another agent.

**Return shape.** The existing fenced `result` block gains four fields:

```result
status: complete
phase: check
checks: design              # intake | slice | design | deliver
card: CARD-NNN
verdict: fail               # pass | fail
criteria:                   # EVERY criterion in this check's set — omissions are malformed
  - id: DSG-AC-COVERED
    verdict: fail           # pass | fail | na
    evidence: "design.md:31-58 — task list has no task for AC-3 (offline retry)"
findings:
  - criterion: DSG-AC-COVERED
    severity: blocking      # blocking | advisory
    location: "design.md:31"
    detail: "AC-3 'retries when offline' has no corresponding design task."
    remedy: "Add a task covering the retry path, or move AC-3 out of scope explicitly."
phase_doc: |
  <full markdown of the check doc>
```

Three rules give the contract teeth:

1. **Every criterion in the set gets a verdict.** A checker cannot silently skip the criterion it
   found inconvenient. A missing id is a malformed result.
2. **Every finding cites a `location` in the artifact.** A finding with no location is **invalid and
   the orchestrator drops it**. This is the anti-noise valve: a checker that wants to look useful by
   inventing findings has to point at a line.
3. **`verdict: fail` if and only if at least one finding is `blocking`.** Advisory findings are
   recorded in the check doc and ride the PR for the human; they never trigger rework.

## `CHECK-CRITERIA.md` — criteria doctrine

A new plugin-owned doctrine file, `templates/CHECK-CRITERIA.md`, sibling to `REVIEW-LENSES.md` and
resolved identically: the orchestrator injects the absolute `${CLAUDE_PLUGIN_ROOT}` path at dispatch;
agents never read a `docs/cards/` copy. One section per check target. Each checker reads only its own
section.

**Criterion ids are stable and permanent.** This is load-bearing: stable ids are what let `/retro`
aggregate verdicts across cards and ask whether the check layer is earning its keep.

### intake

| id | criterion |
|---|---|
| `INT-AC-OBSERVABLE` | each acceptance criterion is observable and testable, not a restatement of intent |
| `INT-REQ-RESOLVES` | every `reqs` id exists in the spec and is not superseded |
| `INT-VERTICAL` | each card is a vertical slice with user-visible value, not a horizontal layer task |
| `INT-COVERAGE` | the card set covers the requirement; nothing in the REQ is unclaimed |
| `INT-NO-OVERLAP` | no two cards claim the same work |
| `INT-DAG` | `depends_on` is acyclic and names real cards |
| `INT-MILESTONE` | every card sits in exactly one milestone; milestone order respects `depends_on` |

### slice

| id | criterion |
|---|---|
| `SLC-VERDICT` | the keep-as-one call is justified, or the split is genuinely necessary |
| `SLC-SIZE` | **no card is projected to exceed the size budget** (below). Blocking — a card over budget *must* be split |
| `SLC-CHILD-VERTICAL` | each proposed child is itself a vertical slice |
| `SLC-CHILD-AC` | each child's acceptance criteria are observable and faithfully inherited from the parent |
| `SLC-NO-LOSS` | the union of the children covers the parent; nothing was dropped |
| `SLC-REWIRE` | `dependents_rewire` is complete: every card that `depends_on` the parent is listed, with correct new deps |
| `SLC-DAG` | child `depends_on` is acyclic |

### design

| id | criterion |
|---|---|
| `DSG-AC-COVERED` | every acceptance criterion maps to at least one design task |
| `DSG-SPEC-FIDELITY` | `## Spec references` cite real spec sections, and the design contradicts none of them |
| `DSG-TASK-TDD` | the task list is file-level and TDD-ordered (a test precedes the code it drives) |
| `DSG-DOCTRINE` | where the card's domain touches them, the design honours standing doctrine (decimal/rounding primitives, parallel derived values never blended, as-of semantics, determinism) |
| `DSG-ADR-NEEDED` | expensive-to-reverse decisions are proposed as ADRs, and none duplicates or silently contradicts a standing one |
| `DSG-KNOWLEDGE` | the design does not re-tread a gotcha already recorded in `KNOWLEDGE.md` |
| `DSG-SCOPE` | in/out of scope is explicit, and nothing in the design falls outside the card's ACs |
| `DSG-NO-CODE` | the design branch is docs-only |

`DSG-DOCTRINE` is the point at which `AGENT-PROTOCOL.md`'s doctrine block stops being advice and
becomes something verified.

### deliver

| id | criterion |
|---|---|
| `DLV-BASE` | the PR targets `main` and was cut from the right branch |
| `DLV-BODY-TRUE` | every claim in the PR body is supported by the diff; no claimed AC is unimplemented |
| `DLV-SIZE` | **the PR's actual changed lines are within the size budget** (below). Implementation PRs only. Advisory, but escalated — see below |
| `DLV-DOCS` | the phase docs that should ride this PR are on it (design PR: `slice.md`, `design.md`, ADRs; implementation PR: `implement.md`, `test.md`, `review.md`) |
| `DLV-PURITY` | a design PR carries no code; an implementation PR carries no unrelated changes |
| `DLV-CI` | CI is green or running; the PR was not opened on a known-red branch |

### Two-layer resolution

A checker reads its section of the plugin's `CHECK-CRITERIA.md`, then layers the project's
`PROTOCOL-ADDENDUM.md` `## Check criteria — <target>` section on top — the same way protocol doctrine
already layers. **Local criteria carry a `LOCAL-` id prefix**, so they never collide with a future
plugin id and `/retro` can tell which set a verdict came from.

## The size budget

A card must be small enough that a human can actually review it. The budget is enforced twice —
**predicted** at slice, **measured** at deliver — so a mis-estimate is caught, not merely tolerated.

### What counts

**All changed lines** (added + deleted, per `git diff --numstat`), **including tests**. A 500-line
test file is still 500 lines a human must read; excluding tests would let a card ship a 500-line
implementation plus 600 lines of test as an 1100-line review.

Excluded are only machine-authored files, matched by a configurable glob list — `size_exclude` in
`config.md`, defaulting to:

```
*.lock  package-lock.json  yarn.lock  pnpm-lock.yaml  Cargo.lock  poetry.lock
uv.lock  go.sum  Gemfile.lock  composer.lock  vendor/**  node_modules/**
```

A project with generated code (protobuf stubs, OpenAPI clients) adds its globs here, rather than this
design inventing a policy for it. The threshold itself is `size_limit` in `config.md`, defaulting to
**500**.

### `SLC-SIZE` — predicted, at slice (blocking)

`card-slicer` gains an **`estimated_lines`** field on its result: for a keep-as-one verdict, the
estimate for the card; for a split, an estimate per proposed child. It is recorded on the card
frontmatter as `estimated_lines: N`.

`card-slice-checker` **produces its own independent estimate** from the card's acceptance criteria and
the existing codebase — it does not take the slicer's number on trust, which is the entire point of a
checker. It then checks two things: that the slicer's estimate is defensible against its own, and that
**no card is projected over `size_limit`**.

**A projected breach is a blocking finding: the card must be split.** The rework loop already carries
this correctly — the slicer is re-dispatched with the finding verbatim and produces children instead
of a keep-as-one verdict. Each child is then subject to `SLC-SIZE` in turn, so a split that merely
yields two over-budget children does not pass either.

Because a projected breach *forces* a split, `size_limit` becomes the real ceiling on card size in the
system — tighter in practice than any judgement-based "is this a vertical slice?" test, and much
harder to argue with.

### `DLV-SIZE` — measured, at deliver (advisory, escalated)

`card-deliver-checker` measures the implementation PR's actual changed lines
(`git diff --numstat main...<branch>`, minus `size_exclude`) and records `actual_lines: N` on the card.
Design PRs are exempt: a long design document is not a code-review problem.

**A measured breach is advisory rather than blocking, and deliberately so.** The code is written and
the PR is open; re-dispatching `card-deliverer` cannot un-write it, so a blocking verdict would burn
rework budget against a remedy that does not exist at that phase.

But it is not a shrug. On a breach the checker **must propose a concrete split**: which commits or file
groups should become which smaller PRs, and in what order. That proposal is the finding's `remedy`, the
`/kanban` report surfaces it prominently, and the driver decides whether to land the PR as-is or split
it for review.

### Predicted vs. measured is a retro signal

`estimated_lines` and `actual_lines` sit side by side on every done card. A `DLV-SIZE` breach means
`SLC-SIZE` passed on an estimate that turned out wrong — an **escaped defect in the slicer**, which is
exactly the class of thing `/retro` exists to fix at source. `/retro` mines the estimate/actual delta
across done cards and, when the slicer systematically under-estimates, proposes a correction to its
prompt rather than letting every card keep paying for the miss at review time.

## The review phase becomes the lens panel

`card-reviewer` (one generalist Opus pass over the branch diff) and the `pr-expert-reviewer` panel
(eight lenses over the same diff, post-PR) do the same job twice. They collapse into one.

**The `review` phase dispatches the lens panel** against `git diff main...<branch>` in the card's
worktree, in parallel, one `card-lens-reviewer` per lens. Findings merge into `review.md`. Blocking
findings auto-rework the implementer, exactly as `card-reviewer`'s findings do today. The panel runs
**before** the PR opens, so the PR the human sees has already survived eight lenses.

**`REVIEW-LENSES.md` gains an `acceptance` lens** (always dispatched, opus), covering
acceptance-criteria coverage and convention/doctrine adherence — the dimensions today's
`card-reviewer` owns and no existing lens covers. With it, `card-reviewer` is fully subsumed.

Lens table for the `review` phase:

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

**On rework, only the lenses that raised blocking findings re-run** — not all eight.

The panel does not wait for CI: `card-tester` has already run the suite locally in the worktree, so
the diff reaching the panel is green by construction.

### Consequences

**`AGENT-PROTOCOL.md` drops an exception.** It currently reads *"GitHub is off-limits to phase
agents, with two exceptions"* — the deliverer, and the pr-reviewer posting inline comments. With the
panel pre-PR there is **one** exception: the deliverer. No phase agent other than `card-deliverer`
touches GitHub at all.

**Orchestrator §6b (seed the review panel) is deleted entirely.** No panel seeding, no `[lens]`
comments, no `pr-review.md`.

**Orchestrator §6c (address loop) halves.** It reduces to: the human signals review-complete → every
human-authored comment the signal authorises is addressed → the orchestrator replies
`[kanban] Addressed in <commit-url>` on each. The 👍 triage of panel comments, the panel/human
comment partition, and the scope-by-signal rules for panel comments all disappear. The
review-complete signal, the `[kanban]` idempotent reply marker, "never resolve threads, never
approve, never dismiss", and the rule that these fixes don't consume the rework budget all stand
unchanged.

**Legacy `[lens]` comments on already-open PRs go inert.** The address loop actions human-authored
comments only, and a `[lens]` comment is app-authored. If the driver wants one addressed after
cutover, they reply to it in their own voice and the loop picks the reply up. No legacy code path is
needed. Existing `pr-review.md` files stay on disk, unread.

**What is lost:** lens reasoning no longer appears as inline GitHub comments. Instead `review.md` —
the merged lens findings plus a record of what was reworked in response — rides the implementation
PR, and unaddressed advisory findings surface in the PR body.

## Orchestrator wiring

The existing **dispatch-vs-handle** rule already keys off phase-doc presence in `card_dir`. Checks
extend it with no new machinery: `<phase>-check.md` absent + the phase doc present → dispatch the
checker; both present with `verdict: pass` → advance.

Each check sits **between its producer and that producer's gate**, so the driver is never asked to
judge unchecked work.

| point | behaviour |
|---|---|
| **intake** | `/refine` and `/requirement` dispatch `card-intake-checker` on the proposed card set **before presenting it to the driver**. Blocking findings → the skill revises and re-checks. The driver only ever sees a checked proposal. |
| **slice** | after `card-slicer` returns, before the slice gate. Blocking → re-dispatch the slicer in rework mode with findings verbatim. Passing → the gate applies (auto-split or driver). |
| **design** | after `card-designer` returns, before the design gate **and before the design PR opens**. Blocking → re-dispatch the designer. Passing → the design PR opens, carrying `slice-check.md` and `design-check.md`. |
| **implement** | `card-tester`, then the lens panel. Both auto-rework the implementer on blocking findings, as today. |
| **deliver** | after `card-deliverer` returns the PR url. Blocking → re-dispatch the deliverer (wrong base, false PR body) or the implementer (a claimed AC is not actually implemented). |

**Dispatch table** (additions and changes in bold):

| status / condition | dispatch | model |
|---|---|---|
| slice, `slice.md` absent | `card-slicer` | sonnet |
| **slice, `slice.md` present, `slice-check.md` absent** | **`card-slice-checker`** | **sonnet** |
| design, `design.md` absent | `card-designer` | opus |
| **design, `design.md` present, `design-check.md` absent** | **`card-design-checker`** | **opus** |
| implement | `card-implementer` | sonnet |
| test | `card-tester` | haiku |
| **review** | **`card-lens-reviewer` × lenses, in parallel** | **per-lens (table above)** |
| deliver | `card-deliverer` | haiku |
| **deliver, PR open, `deliver-check.md` absent** | **`card-deliver-checker`** | **haiku** |
| **intake (from `/refine`, `/requirement`)** | **`card-intake-checker`** | **opus** |

Model tiers are chosen so a checker is never outclassed by its producer — a haiku checking an Opus
design is theatre. The deliver check is haiku because every one of its criteria is answered by
evidence from `gh pr view` and `git log` rather than by judgement.

**Rework loop.** Identical in shape to the existing tester/reviewer loop: blocking findings →
increment that producer's rework counter → re-dispatch the producer with the findings verbatim →
re-check. Budget exhausted → `status: blocked`, blocker `check failed — <criterion ids>`, driver
decides. Advisory findings never loop.

**Card lifecycle statuses are unchanged** — `slice → design → implement → test → review → deliver`
still holds. Checks are sub-steps within a status, visible through check-doc presence, not new
columns.

## State and config

### `card.md` frontmatter

`reworks: N` becomes a per-producer map, so a card that needed two design revisions does not arrive
at implement with no budget left:

```yaml
reworks:
  slice: 0
  design: 1
  implement: 0
  deliver: 0
estimated_lines: 180    # from card-slicer, verified by card-slice-checker
actual_lines: 412       # from card-deliver-checker, on the implementation PR
```

`estimated_lines` and `actual_lines` are the size budget's two halves (above); together they are the
signal `/retro` uses to correct a systematically under-estimating slicer.

Legacy `reworks: N` normalises to `{implement: N}` — that counter has only ever been spent on
implement rework. Reconcile's legacy-normalisation step (orchestrator §0.5) handles cards mid-flight;
`/migrate` handles the rest.

### `config.md`

Four new keys:

```
checks:       intake=on · slice=on · design=on · deliver=on
check_budget: intake=2 · slice=2 · design=2 · implement=2 · deliver=1
size_limit:   500
size_exclude: *.lock, package-lock.json, yarn.lock, pnpm-lock.yaml, Cargo.lock,
              poetry.lock, uv.lock, go.sum, Gemfile.lock, composer.lock,
              vendor/**, node_modules/**
```

`size_limit` and `size_exclude` are defined in the size-budget section above. A missing `size_limit`
defaults to **500**; a missing `size_exclude` defaults to the list shown.

A missing `checks` or `check_budget` key, or a missing producer within one, defaults to **`on`** and
to a budget of **2**
(except `deliver=1`: a delivery check failing twice means something another deliverer pass will not
fix). `implement=2` is exactly today's behaviour, now expressed in the same vocabulary as everything
else.

**A disabled check is loud, not silent.** While any check is off, every `/kanban` pump warns in its
report — *"checks disabled: design — cards are reaching the design PR unchecked"* — and `BOARD.md`'s
header carries the same. The switch is an escape hatch for a checker that turns out noisy, not a
state you can drift into and forget.

Note the reach of `slice=off` in particular: `SLC-SIZE` is the only thing enforcing the size ceiling
before code is written, so disabling the slice check removes the hard cap on card size and leaves only
`DLV-SIZE`'s advisory warning after the fact. The pump's warning names this consequence explicitly.

**`implement` is deliberately not on the `checks` switch list.** The implementer's checkers are
`card-tester` and the lens panel, so an `implement=off` key would be a config knob that silently
skips running the test suite. The implement chain stays unconditional. `check_budget` still carries
`implement`, because tolerance for rework is a different question from whether the work is tested at
all.

### `BOARD.md`

A card mid-check renders `· checking <phase>`. A card parked on an exhausted budget renders its
blocker with the failing criterion ids — `check failed — DSG-AC-COVERED, DSG-SCOPE` — so the board
shows *why* a card is stuck without opening anything.

### Where check docs live

- `slice-check.md`, `design-check.md` — ride the **design PR** (pre-implementation artifacts, like the
  docs they check).
- `review.md` (merged lens findings) — rides the **implementation PR**, as today.
- `deliver-check.md` — commits to `main`, because the PR is already open by the time it exists.
- The intake check has no card branch: its findings append to the card's `## Notes` and to the
  proposal shown to the driver.

## `/retro` and the self-tuning loop

`/retro` gains a pass over every `*-check.md` on done cards, aggregating verdicts by criterion id.
Three signals, three different remedies:

- **A criterion that never fails across many cards** → it is not earning its dispatch cost. Prune it.
- **A criterion that fails on most cards** → the checker is fine; the **producer** is systematically
  wrong. The remedy is an edit to the producer's agent prompt or the doctrine it reads — *not* more
  checking. Without this, the check layer becomes a permanent rework tax on a defect nobody ever
  fixed at source.
- **A defect that shipped and no criterion caught** → propose a new criterion, with an id, in the
  right section.
- **`estimated_lines` vs `actual_lines` across done cards** → when the slicer systematically
  under-estimates, propose a correction to *its* prompt. A `DLV-SIZE` breach is by definition an
  `SLC-SIZE` estimate that was wrong, and the fix belongs at the slicer, not at review time.

**`/retro`'s authority is bounded by the sole-writer discipline the rest of the system runs on.** It
may add, edit and prune `LOCAL-` criteria in the project's `PROTOCOL-ADDENDUM.md` freely, shipping
them in the same PR it already ships process changes in. For a **plugin** criterion it may only
*report*: *"`DSG-KNOWLEDGE` has passed on 20 consecutive cards — consider raising it upstream"*, or
*"`SLC-NO-LOSS` has failed on 6 of the last 8 splits — the slicer's prompt is the problem, not the
check."* The driver decides whether that becomes a plugin change. `/retro` never edits plugin
doctrine, just as no phase agent edits `BOARD.md`.

## Migration (`/migrate`)

The existing `/migrate` skill gains this cutover:

1. Rewrite each card's `reworks: N` → `reworks: {implement: N}` (absent → all-zero map).
2. Add `checks:`, `check_budget:`, `size_limit:` and `size_exclude:` to `config.md` with the defaults
   above.
3. Stamp the new `kanban_flow_version`.
4. Cards currently at `status: review` re-enter the phase as a panel dispatch (`review.md` absent →
   dispatch the panel). No special-casing needed.
5. Open implementation PRs keep their `[lens]` comments; they are app-authored, so the address loop
   ignores them. Existing `pr-review.md` files stay on disk, unread.

## Risks

**Cost.** Three extra dispatches per card (slice, design, deliver checks) plus one per intake run —
roughly a 30–40% increase in dispatches per card, weighted toward cheap tiers except the Opus design
check. Checks are inherently serial with their producer, since they gate it, so each adds a
round-trip of latency. Partly offset: deleting `card-reviewer` removes an Opus pass, and the panel no
longer makes a second GitHub round-trip.

**Designed against:**

| failure mode | mitigation |
|---|---|
| rubber-stamping (an LLM agreeing with an LLM) | per-criterion attestation; fresh context excluding the producer's reasoning; mandatory evidence citations |
| invented findings (a checker manufacturing work) | a finding with no `location` is invalid and dropped |
| infinite regress | checkers are terminal, stated in doctrine; the human is their backstop |
| ossification (a criteria set that only grows) | `/retro`'s aggregation pass, and its mandate to fix the **producer** when a criterion fails constantly |
| rework starvation | per-producer budgets |
| a noisy checker with no remedy | the `checks` off-switch, which warns loudly while engaged |

**The honest risk that remains:** if checkers agree with producers almost always, this is cost with
no signal. **The first `/retro` after ~5 checked cards should be treated as a deliberate evaluation
of whether the layer earns its keep**, using the per-criterion verdict data the design exists to
produce.

## Out of scope

- **Checker-checkers.** Checkers are terminal, by design.
- **Multi-vote checker panels.** One checker per producer, except the implementer, whose lens panel
  already provides diverse perspectives.
- **Making the implement chain switchable.** Tester and the lens panel run unconditionally.
- **A deterministic (non-LLM) validator** for structural intake properties (acyclic `depends_on`, REQ
  ids resolving). The `card-intake-checker` covers these as criteria; a mechanical validator could
  later cover them more cheaply and exactly, but is not part of this design.
- **`/retro` opening PRs against the plugin repo.** It reports; the driver ports.
