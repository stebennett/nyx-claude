# Kanban Checker Agents Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every producing agent in kanban-flow a defined checker, enforce a 500-line size budget on every card, and collapse the post-PR lens panel into a pre-PR review phase.

**Architecture:** Every agent becomes either a **producer** (creates artifacts, can be wrong) or a **checker** (verifies, is terminal — nothing checks a checker). Four new checker agents (intake, slice, design, deliver) read a new plugin-owned doctrine file, `CHECK-CRITERIA.md`, and return a per-criterion verdict with mandatory evidence citations. The existing `pr-expert-reviewer` panel moves *before* the PR opens and absorbs `card-reviewer`, which is deleted.

**Tech Stack:** Markdown + YAML frontmatter (agents, skills, doctrine templates), JSON (plugin manifest). No runtime code, no build step.

**Source spec:** `docs/superpowers/specs/2026-07-13-kanban-checker-agents-design.md` — read it before Task 1.

## Global Constraints

- **Working directory:** `/Users/stevebennett/Code/nyx-claude`. Branch: `feat/kanban-checker-agents` (already created and checked out — do not create another).
- **Plugin root:** `plugins/kanban-flow/`. Everything in this plan lives under it, except the plan/spec docs.
- **No test runner exists in this repo.** Per `CLAUDE.md`, plugin components are validated by structural assertion and by installing the plugin into Claude Code and exercising it. Each task's "test" is an exact `grep`/`jq`/`test` command with expected output, run before the edit (must fail) and after (must pass). **Do not introduce a test framework** — that is out of scope.
- **RTK proxy:** this machine rewrites `grep`, `ls`, `cat`, `find`, `git`. If an rtk-wrapped command rejects a flag, re-run it as `rtk proxy <command>`. All verification commands in this plan are written to be run via `rtk proxy` where they use flags rtk may filter.
- **Commits:** Conventional Commits, ending with the trailer:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```
- **Plugin-owned doctrine:** doctrine and templates live in `plugins/kanban-flow/templates/` and are read live by agents at an absolute `${CLAUDE_PLUGIN_ROOT}` path. **Never** write a doctrine copy into a target repo's `docs/cards/`.
- **Sole-writer invariant:** `/kanban` is the only writer of `BOARD.md`, `KNOWLEDGE.md`, `card.md` (post-backlog) and `docs/adrs/`. No agent — including any new checker — writes to disk. Checkers return `phase_doc`; the orchestrator persists it.
- **Checkers are terminal.** Nothing checks a checker. Do not add a checker for any checker, at any point.
- **Size budget defaults:** `size_limit: 500`, counting all changed lines **including tests**, excluding only the `size_exclude` glob list.

---

## File Structure

**New files (5):**

| File | Responsibility |
|---|---|
| `plugins/kanban-flow/templates/CHECK-CRITERIA.md` | Criteria doctrine — one section per check target, stable criterion ids |
| `plugins/kanban-flow/agents/card-intake-checker.md` | Checks `/refine` and `/requirement`'s proposed card set |
| `plugins/kanban-flow/agents/card-slice-checker.md` | Checks `card-slicer`, incl. independent `SLC-SIZE` line estimate |
| `plugins/kanban-flow/agents/card-design-checker.md` | Checks `card-designer` |
| `plugins/kanban-flow/agents/card-deliver-checker.md` | Checks `card-deliverer`, incl. measured `DLV-SIZE` |

**Renamed (1):** `agents/pr-expert-reviewer.md` → `agents/card-lens-reviewer.md` — loses its GitHub-posting role, reviews the worktree diff pre-PR.

**Deleted (1):** `agents/card-reviewer.md` — subsumed by the lens panel plus the new `acceptance` lens.

**Modified (9):**

| File | Change |
|---|---|
| `templates/AGENT-PROTOCOL.md` | Add the Checker contract section; add `check` to the phase enum; reduce the GitHub exception from two to one |
| `templates/REVIEW-LENSES.md` | Reframe as a pre-PR panel; add the `acceptance` lens |
| `templates/CHECK-CRITERIA.md` | (new — see above) |
| `templates/config.md` | Add `checks`, `check_budget`, `size_limit`, `size_exclude` |
| `templates/card-template.md` | `reworks` becomes a map; add `estimated_lines`, `actual_lines` |
| `agents/card-slicer.md` | Return `estimated_lines` |
| `skills/kanban/SKILL.md` | Check sub-steps, dispatch table, per-producer budgets, review-phase panel, delete §6b, halve §6c, board/report |
| `skills/refine/SKILL.md` + `skills/requirement/SKILL.md` | Dispatch `card-intake-checker` before presenting to the driver |
| `skills/migrate/SKILL.md` | Cutover: `reworks` map, new config keys |
| `skills/retro/SKILL.md` | Mine check docs; estimate-vs-actual; `LOCAL-` criteria authority |
| `.claude-plugin/plugin.json` | Version 0.3.0 → 0.4.0 |

---

## Task 1: The checker contract in AGENT-PROTOCOL.md

Adds the shared contract all four new checkers reference, so their agent files never restate it. Purely additive — nothing else in the system reads these fields yet, so this commit is coherent on its own.

**Files:**
- Modify: `plugins/kanban-flow/templates/AGENT-PROTOCOL.md`

**Interfaces:**
- Produces: the `result` block fields `checks`, `verdict`, `criteria[]`, `findings[]` and the `phase: check` enum value. Tasks 4–7 (the checker agents) and Task 11 (the orchestrator) all depend on exactly these names.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -c "## Checker contract" plugins/kanban-flow/templates/AGENT-PROTOCOL.md
```
Expected: `0` (and exit status 1). The section does not exist yet.

- [ ] **Step 2: Add `check` to the phase enum**

In `templates/AGENT-PROTOCOL.md`, in the `result` block, replace:

```
phase: <slice|design|implement|test|review|deliver|pr-review>
```

with:

```
phase: <slice|design|implement|test|review|deliver|check>
```

(`pr-review` is retired in Task 8, when the panel moves pre-PR and becomes the `review` phase.)

- [ ] **Step 3: Add the Checker contract section**

Insert this section immediately **before** the `## Architecture Decision Records (ADRs)` heading:

````markdown
## Checker contract (checker agents only)

Every agent in this system is either a **producer** — it creates an artifact and can be wrong — or a
**checker** — it verifies a producer's output. **Checkers are terminal: nothing checks a checker.**
That is what stops the regress; a checker's backstop is the human, at the intake and slice gates and
at the two PR merges. Never add a checker for a checker.

| Producer | Its checker(s) |
|---|---|
| intake (`/refine`, `/requirement`) | `card-intake-checker` |
| `card-slicer` | `card-slice-checker` |
| `card-designer` | `card-design-checker` |
| `card-implementer` | `card-tester`, then the `card-lens-reviewer` panel |
| `card-deliverer` | `card-deliver-checker` |

If you are a checker, these rules bind you in addition to everything above.

**You receive the producer's inputs and its output — never its reasoning.** Derive your own view from
the same inputs and compare. A checker that reads the producer's justification is only agreeing with
it.

**You write nothing and mutate nothing.** No files, no GitHub. You return `phase_doc`; the
orchestrator persists it. Your criteria come from your section of the plugin's `CHECK-CRITERIA.md`
(absolute path in your dispatch), then any `## Check criteria — <target>` section of the repo's
`PROTOCOL-ADDENDUM.md` layered on top. Local criteria carry a `LOCAL-` id prefix.

**Your `result` block carries four extra fields:**

```result
status: complete
phase: check
checks: design              # intake | slice | design | deliver
card: CARD-NNN
gate: none                  # a checker never triggers a gate
verdict: fail               # pass | fail
criteria:                   # EVERY criterion in your set — an omission is a malformed result
  - id: DSG-AC-COVERED
    verdict: fail           # pass | fail | na
    evidence: "design.md:31-58 — task list has no task for AC-3 (offline retry)"
findings:                   # [] when verdict is pass
  - criterion: DSG-AC-COVERED
    severity: blocking      # blocking | advisory
    location: "design.md:31"
    detail: "AC-3 'retries when offline' has no corresponding design task."
    remedy: "Add a task covering the retry path, or move AC-3 out of scope explicitly."
phase_doc: |
  <full markdown of the check doc>
```

Three rules give this contract its teeth:

1. **Every criterion in your set gets a verdict.** You may not silently skip the criterion you found
   inconvenient. Use `na` — with evidence for *why* it does not apply — rather than omitting it.
2. **Every finding cites a `location` in the artifact.** A finding with no location is **invalid and
   the orchestrator drops it.** If you cannot point at a line, you do not have a finding.
3. **`verdict: fail` if and only if at least one finding is `blocking`.** Advisory findings are
   recorded and ride the PR for the human; they never trigger rework.

**Blocking findings auto-rework the producer** — the orchestrator re-dispatches it with your findings
verbatim, up to that producer's `check_budget`, then parks the card for the driver. Make every
blocking finding actionable: what is wrong, where, and what right looks like.

**Agreement must be earned.** A `pass` with thin evidence is worse than no check at all, because it
manufactures confidence. Your `evidence` for each passing criterion states what you actually verified
— not "looks fine". `/retro` reads these to tell diligence from a skim.
````

- [ ] **Step 4: Run the assertion to verify it now passes**

Run:
```bash
rtk proxy grep -c "## Checker contract" plugins/kanban-flow/templates/AGENT-PROTOCOL.md && \
rtk proxy grep -c "phase: <slice|design|implement|test|review|deliver|check>" plugins/kanban-flow/templates/AGENT-PROTOCOL.md
```
Expected: `1` then `1`.

- [ ] **Step 5: Verify the terminal rule is stated (this is the anti-regress guard)**

Run:
```bash
rtk proxy grep -c "Checkers are terminal" plugins/kanban-flow/templates/AGENT-PROTOCOL.md
```
Expected: `1`.

- [ ] **Step 6: Commit**

```bash
git add plugins/kanban-flow/templates/AGENT-PROTOCOL.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): add the checker contract to AGENT-PROTOCOL

Classifies every agent as a producer or a checker and states the rule that
terminates the regress: checkers are terminal, nothing checks a checker.
Defines the four extra result fields (checks, verdict, criteria, findings),
mandatory per-criterion attestation, and the rule that a finding without a
location citation is invalid and dropped.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: CHECK-CRITERIA.md — the criteria doctrine

The single authority for what "checked" means. Stable criterion ids are load-bearing: `/retro` aggregates verdicts by id (Task 14), so an id is never renamed or reused once shipped.

**Files:**
- Create: `plugins/kanban-flow/templates/CHECK-CRITERIA.md`

**Interfaces:**
- Consumes: the Checker contract from Task 1 (`criteria[].id`, `findings[].criterion`).
- Produces: criterion ids `INT-*` (7), `SLC-*` (6), `DSG-*` (8), `DLV-*` (6). Tasks 4–7 each read exactly one section. Task 11 (orchestrator) reports failing ids on the board. Task 14 (`/retro`) aggregates by id.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
test -f plugins/kanban-flow/templates/CHECK-CRITERIA.md && echo EXISTS || echo MISSING
```
Expected: `MISSING`.

- [ ] **Step 2: Create the file**

Create `plugins/kanban-flow/templates/CHECK-CRITERIA.md` with exactly this content:

````markdown
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

1. **Derive independently, then compare.** You are given the producer's *inputs* and its *output*,
   never its reasoning. Form your own answer from the inputs first — what tasks *should* this design
   have, how big *should* this card be — and only then read the artifact and diff it against yours.
   Reading the producer's justification first and nodding along is the failure mode this whole layer
   exists to prevent.
2. **Verdict every criterion.** Return a row for every id in your section — `pass`, `fail`, or `na`.
   An omission is a malformed result. `na` needs evidence for *why* it does not apply.
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
inputs: the spec (at `spec_path`), the proposed cards, the milestone plan, and the existing board.

| id | criterion | severity when failed |
|---|---|---|
| `INT-AC-OBSERVABLE` | every acceptance criterion is observable and testable — it names something you could watch happen, not an intent | blocking |
| `INT-REQ-RESOLVES` | every `reqs` id exists in the spec and is not superseded | blocking |
| `INT-VERTICAL` | each card is a vertical slice with user-visible value, not a horizontal layer task | blocking |
| `INT-COVERAGE` | the card set covers the requirement — nothing in the REQ is unclaimed by any card | blocking |
| `INT-NO-OVERLAP` | no two cards claim the same work | blocking |
| `INT-DAG` | `depends_on` is acyclic and every id names a real card or a proposed sibling | blocking |
| `INT-MILESTONE` | every card sits in exactly one milestone, and no card depends on a card in a later milestone | blocking |

**Walk:** Read the requirement(s) first and list, in your own words, the observable behaviours it
demands. Only then read the proposed cards. Map behaviours → cards: an unclaimed behaviour is
`INT-COVERAGE`; two cards claiming one behaviour is `INT-NO-OVERLAP`. Then read each acceptance
criterion and ask *what would I run to see this?* — "the system is robust" fails `INT-AC-OBSERVABLE`;
"a request with no auth header returns 401" passes. Build the `depends_on` graph by hand and walk it
for cycles and for milestone-order violations.

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
(design | implementation), the PR body, and the branch.

| id | criterion | severity when failed |
|---|---|---|
| `DLV-BASE` | the PR targets `main` and was cut from the right branch | blocking |
| `DLV-BODY-TRUE` | every claim in the PR body is supported by the diff; no claimed acceptance criterion is unimplemented | blocking |
| `DLV-SIZE` | **actual changed lines are within `size_limit`** (implementation PRs only — see below) | **advisory, escalated** |
| `DLV-DOCS` | the phase docs that should ride this PR are on it — design PR: `slice.md`, `design.md`, `slice-check.md`, `design-check.md`, ADRs; implementation PR: `implement.md`, `test.md`, `review.md` | blocking |
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
````

- [ ] **Step 3: Verify the file exists and the criterion ids are complete and unique**

Run:
```bash
rtk proxy grep -oE '`(INT|SLC|DSG|DLV)-[A-Z-]+`' plugins/kanban-flow/templates/CHECK-CRITERIA.md \
  | sort -u | wc -l
```
Expected: `27` (7 INT + 6 SLC + 8 DSG + 6 DLV).

- [ ] **Step 4: Verify no duplicate ids in the criteria tables**

Run:
```bash
rtk proxy grep -oE '^\| `(INT|SLC|DSG|DLV)-[A-Z-]+`' plugins/kanban-flow/templates/CHECK-CRITERIA.md \
  | sort | uniq -d
```
Expected: no output (empty). A duplicate id would break `/retro`'s aggregation.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/templates/CHECK-CRITERIA.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): add CHECK-CRITERIA doctrine

27 stable criterion ids across four check targets, plus the shared Method
that makes agreement expensive: derive independently before reading the
artifact, verdict every criterion, cite a location or you have no finding.

Carries the size budget's two halves — SLC-SIZE (blocking, forces a split
before code is written) and DLV-SIZE (advisory, must propose a concrete
PR split when the real diff breaches).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: card-slicer returns `estimated_lines`

The slicer must produce a number for `card-slice-checker` to check against. Additive to its result block; nothing breaks if a legacy dispatch omits it.

**Files:**
- Modify: `plugins/kanban-flow/agents/card-slicer.md`

**Interfaces:**
- Produces: `estimated_lines: <int>` (keep-as-one) or `estimated_lines` per entry in `proposed_cards` (split). Task 4 (`card-slice-checker`) compares against it; Task 10 (`card-template.md`) stores it; Task 11 (orchestrator) persists it.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -c "estimated_lines" plugins/kanban-flow/agents/card-slicer.md
```
Expected: `0` (exit 1).

- [ ] **Step 2: Add the estimate to the `## Do` list**

In `agents/card-slicer.md`, after step 5 in the `## Do` section (the `dependents_rewire` step), append:

```markdown
6. **Estimate the size of every card you leave standing.** For the card itself (right-sized verdict)
   or for each proposed child (split), estimate the **changed lines** it will take to implement:
   walk its acceptance criteria, name the files that must change (`Grep`/`Glob` the real codebase —
   which modules exist, which are new), and estimate lines per file. **Count tests** — this project
   is TDD and a test file roughly matches the code it drives. Exclude only `size_exclude` paths from
   `config.md` (lock files, vendored deps).

   **`size_limit` (`config.md`, default 500) is a hard ceiling, not a guideline.** If your estimate
   for a card exceeds it, that card is *by definition* not right-sized — split it, however atomic it
   feels. Show your per-file working in `slice.md`; `card-slice-checker` produces its own independent
   estimate and will reject a number it cannot reconstruct.
```

- [ ] **Step 3: Add `estimated_lines` to the `## Return` section**

In the `## Return` section, replace this line:

```markdown
- **Right-sized:** `status: complete`, `gate: none`. `phase_doc` is `slice.md` with sections `## Verdict` (right-sized) and `## Rationale`. The orchestrator then marks the card `right_sized: true` and advances it to design.
```

with:

```markdown
- **Right-sized:** `status: complete`, `gate: none`. Set `estimated_lines: <int>` (a top-level result field) for the card. `phase_doc` is `slice.md` with sections `## Verdict` (right-sized), `## Rationale`, and `## Size estimate` (the per-file working behind the number). The orchestrator then marks the card `right_sized: true` and advances it to design.
```

Then replace this line:

```markdown
- **Split proposed:** `status: complete`, `gate: slice`. Populate `proposed_cards` and `dependents_rewire` (slice-phase-only result fields). `phase_doc` is `slice.md` with `## Verdict` (split), `## Proposed slices` (the children and their rationale), and `## Dependency rewiring`. Size the children carefully — they are created `right_sized: true` and will not be re-sliced.
```

with:

```markdown
- **Split proposed:** `status: complete`, `gate: slice`. Populate `proposed_cards` and `dependents_rewire` (slice-phase-only result fields), and give **every** entry in `proposed_cards` its own `estimated_lines: <int>`. `phase_doc` is `slice.md` with `## Verdict` (split), `## Proposed slices` (the children and their rationale), `## Dependency rewiring`, and `## Size estimates` (per-child, with the per-file working). Size the children carefully — they are created `right_sized: true` and will not be re-sliced, so a child over `size_limit` is a defect you cannot fix later.
```

- [ ] **Step 4: Update the calibration heuristic to name the hard limit**

In the `## Slicing heuristics` section, replace:

```markdown
- **Calibration:** a right-sized card is roughly one design and a day of TDD. Signals it's too big: >5 acceptance criteria, spanning two unrelated spec sections, or "and" in the title doing real work.
```

with:

```markdown
- **Calibration:** a right-sized card is roughly one design and a day of TDD, and **always under `size_limit` changed lines including tests** (`config.md`, default 500) — that limit is the hard ceiling and it outranks every judgement heuristic here. Softer signals it's too big: >5 acceptance criteria, spanning two unrelated spec sections, or "and" in the title doing real work.
```

Then replace:

```markdown
- The cost of a wrong "right-sized" verdict is one oversized PR; the cost of a wrong split is churn across cards. When genuinely borderline, prefer right-sized.
```

with:

```markdown
- The cost of a wrong "right-sized" verdict is one oversized PR; the cost of a wrong split is churn across cards. When genuinely borderline **and both options are under `size_limit`**, prefer right-sized. When the estimate is over the limit, borderline does not arise — split.
```

- [ ] **Step 5: Run the assertion to verify it passes**

Run:
```bash
rtk proxy grep -c "estimated_lines" plugins/kanban-flow/agents/card-slicer.md
```
Expected: `4` or more.

- [ ] **Step 6: Commit**

```bash
git add plugins/kanban-flow/agents/card-slicer.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): card-slicer estimates changed lines per card

The slicer now returns estimated_lines for the card (keep-as-one) or per
proposed child (split), with per-file working shown in slice.md. size_limit
becomes a hard ceiling that outranks every judgement heuristic: an estimate
over it means the card is not right-sized, however atomic it feels.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: card-slice-checker

The first checker, and the one carrying the size ceiling. Read-only tools — it estimates from the codebase with `Grep`/`Glob`, never runs anything.

**Files:**
- Create: `plugins/kanban-flow/agents/card-slice-checker.md`

**Interfaces:**
- Consumes: Task 1's Checker contract; Task 2's `## slice` criteria section (`SLC-VERDICT`, `SLC-SIZE`, `SLC-CHILD-VERTICAL`, `SLC-CHILD-AC`, `SLC-NO-LOSS`, `SLC-REWIRE`, `SLC-DAG`); Task 3's `estimated_lines`.
- Produces: a `result` with `checks: slice`, and a `phase_doc` the orchestrator writes to `card_dir/slice-check.md`.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
test -f plugins/kanban-flow/agents/card-slice-checker.md && echo EXISTS || echo MISSING
```
Expected: `MISSING`.

- [ ] **Step 2: Create the agent**

Create `plugins/kanban-flow/agents/card-slice-checker.md`:

````markdown
---
name: card-slice-checker
description: Checks card-slicer's work. Independently verifies the right-sized/split verdict, that every card is a vertical slice with faithfully inherited acceptance criteria, that the split loses nothing and rewires every dependent, and — critically — produces its own independent changed-lines estimate to enforce the size_limit ceiling. Blocking findings send the slicer back. Produces slice-check.md. Never writes code or files.
model: sonnet
tools: Read, Grep, Glob, Skill
---

# card-slice-checker — checker for card-slicer

You check ONE slice verdict. You are a **checker**: read the Checker contract in the plugin
`AGENT-PROTOCOL.md` (absolute path in your dispatch) and obey it exactly. You write nothing, mutate
nothing, and nothing checks you — the driver is your backstop at the slice gate.

Read, in order: the plugin `AGENT-PROTOCOL.md` (Doctrine and Checker contract), the repo's
`PROTOCOL-ADDENDUM.md` if present, the **Method** and **`## slice`** sections of the plugin
`CHECK-CRITERIA.md` (absolute path in your dispatch, plus any `## Check criteria — slice` addendum
section), and `KNOWLEDGE.md`. Then your inputs: `card.md`, `slice.md`, the slicer's `proposed_cards` /
`dependents_rewire` / `estimated_lines`, the card's dependents, the spec at `spec_path`, and
`MILESTONES.md`.

## Do

1. **Derive before you read.** Form your own view of the card from `card.md` and the spec *before*
   reading the slicer's rationale: would you split this, and if so how? Then read `slice.md` and diff
   its answer against yours. Reading the rationale first and nodding along is the one failure mode
   that makes this whole agent worthless.

2. **Estimate the size yourself** — the highest-value thing you do, and the reason a bad slice cannot
   reach `design`. For the card (right-sized) or each child (split): walk the acceptance criteria,
   `Grep`/`Glob` the real codebase to see which modules already exist and which are new, name the
   files that must change, and estimate changed lines per file. **Count tests.** Exclude only
   `size_exclude` paths (`config.md`). Sum, and show the per-file working in your evidence — a bare
   number is not evidence.

   Then apply `SLC-SIZE` per `CHECK-CRITERIA.md`: **your** estimate over `size_limit` for any card is
   blocking and the card must be split; a slicer estimate you cannot reconstruct from its own working
   is blocking even when both numbers are under the limit.

3. **Work the rest of the `## slice` criteria** in `CHECK-CRITERIA.md`, in order. Build the
   `depends_on` graph by hand for `SLC-DAG`. For `SLC-REWIRE`, list the card's dependents from your
   dispatch and tick each one off against `dependents_rewire` — a missing dependent is a card that
   will be orphaned by the split.

4. **Verdict every criterion.** `pass`, `fail`, or `na`, each with evidence of what you actually
   checked. Findings only where you can cite a location in `slice.md` or the proposed card set.

## Return

- `verdict: pass` (`status: complete`, `gate: none`, `phase: check`, `checks: slice`) when no finding
  is blocking. The orchestrator then applies the slice gate.
- `verdict: fail` when any finding is blocking — the orchestrator re-dispatches `card-slicer` with
  your findings verbatim, up to the `slice` check budget, then parks the card.
- `phase_doc` is `slice-check.md`: `## Verdict`, `## Criteria` (the full table — id, verdict,
  evidence), `## Size estimate` (your per-file working, your total, the slicer's total, and whether
  it holds), `## Blocking findings`, `## Advisory findings`.
- `status: needs-input` only if you cannot check at all (the spec is unreadable, `slice.md` is
  missing). A slice you disagree with is a `fail`, not a blocker.
- Add `knowledge` entries for recurring slicing traps worth teaching the slicer (scope: repo,
  section: Conventions).
````

- [ ] **Step 3: Verify the frontmatter parses and declares read-only tools**

Run:
```bash
rtk proxy grep -E "^(name|model|tools):" plugins/kanban-flow/agents/card-slice-checker.md
```
Expected exactly:
```
name: card-slice-checker
model: sonnet
tools: Read, Grep, Glob, Skill
```
(No `Bash`, no `Write`, no `Edit` — a checker mutates nothing.)

- [ ] **Step 4: Verify it covers every `SLC-*` criterion**

Run:
```bash
rtk proxy grep -c "SLC-SIZE" plugins/kanban-flow/agents/card-slice-checker.md
```
Expected: `2` (named in the Do list and in the size step).

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/agents/card-slice-checker.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): add card-slice-checker

Checks card-slicer against the SLC-* criteria, and independently estimates
changed lines rather than trusting the slicer's number — a number you inherit
is a number you have not checked. An estimate over size_limit is blocking and
forces a split, which makes the budget the real ceiling on card size.

Read-only tools: a checker mutates nothing.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: card-design-checker

Opus, because a checker outclassed by its producer rubber-stamps. This is the agent that turns `AGENT-PROTOCOL.md`'s Doctrine section from advice into something verified.

**Files:**
- Create: `plugins/kanban-flow/agents/card-design-checker.md`

**Interfaces:**
- Consumes: Task 1's Checker contract; Task 2's `## design` criteria (`DSG-AC-COVERED`, `DSG-SPEC-FIDELITY`, `DSG-TASK-TDD`, `DSG-DOCTRINE`, `DSG-ADR-NEEDED`, `DSG-KNOWLEDGE`, `DSG-SCOPE`, `DSG-NO-CODE`).
- Produces: a `result` with `checks: design`, and a `phase_doc` the orchestrator writes to `card_dir/design-check.md`.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
test -f plugins/kanban-flow/agents/card-design-checker.md && echo EXISTS || echo MISSING
```
Expected: `MISSING`.

- [ ] **Step 2: Create the agent**

Create `plugins/kanban-flow/agents/card-design-checker.md`:

````markdown
---
name: card-design-checker
description: Checks card-designer's work. Independently derives the task list it expects from the card's acceptance criteria, then verifies the design covers every criterion, cites the spec truthfully, is TDD-ordered, honours the standing doctrine (decimal primitives, parallel derived values, as-of semantics, determinism), proposes ADRs for expensive-to-reverse decisions, and stays in scope. Blocking findings send the designer back. Runs before the design gate and before the design PR opens. Produces design-check.md. Never writes code or files.
model: opus
tools: Read, Grep, Glob, Skill
---

# card-design-checker — checker for card-designer

You check ONE design, **before** the design gate and before the design PR opens. You are a
**checker**: read the Checker contract in the plugin `AGENT-PROTOCOL.md` (absolute path in your
dispatch) and obey it exactly. You write nothing, mutate nothing, and nothing checks you — the human
merging the design PR is your backstop.

Read, in order: the plugin `AGENT-PROTOCOL.md` (**Doctrine** and Checker contract — the Doctrine
section is the substance of `DSG-DOCTRINE`, so read it carefully), the repo's `PROTOCOL-ADDENDUM.md`
if present, the **Method** and **`## design`** sections of the plugin `CHECK-CRITERIA.md` (absolute
path in your dispatch, plus any `## Check criteria — design` addendum section), `KNOWLEDGE.md`, and
`docs/adrs/README.md` (the standing-decision index). Then your inputs: `card.md`, `slice.md`,
`design.md`, its `proposed_adrs`, and the spec sections `design.md` cites under `## Spec references`.

## Do

1. **Derive before you read.** From `card.md`'s acceptance criteria and the spec, write your own list
   of the design tasks you expect — files, order, tests. *Only then* read `design.md`'s task list and
   diff it against yours. Reading the design first anchors you to it, and an anchored checker agrees.

2. **Map both directions.** Criteria → tasks: a criterion with no task is `DSG-AC-COVERED`. Tasks →
   criteria: a task serving no criterion is `DSG-SCOPE` (scope creep costs a rework loop later, and
   the lens panel will flag it as unrelated changes at review).

3. **Open every cited spec section** and confirm it says what the design claims (`DSG-SPEC-FIDELITY`).
   A citation to a section that does not exist, or that says something else, is blocking — every
   later phase reads *only* the sections the design cites, so a bad citation propagates silently
   through implement, test and review.

4. **Work the doctrine, rule by rule** (`DSG-DOCTRINE`). For each rule in `AGENT-PROTOCOL.md`'s
   Doctrine section, decide whether this card's domain touches it. If it does, the design must say
   how it is honoured — naming the project's decimal/rounding primitive, naming *which* of two
   parallel derived values each consumer gets, stating the as-of snapshot source and the
   deterministic tie-break, fixing clock and seed. `na` is correct only when the rule genuinely does
   not apply, and it needs evidence saying why.

5. **Check the ADR ledger** (`DSG-ADR-NEEDED`). Read the index first. An expensive-to-reverse decision
   made silently in the design is blocking; a proposal duplicating a standing ADR is blocking; a
   decision that *contradicts* a standing ADR without a `supersedes` is blocking.

6. **Verdict every criterion** in the `## design` section — `pass`, `fail`, or `na`, each with
   evidence of what you actually checked. Findings only where you can cite a `design.md` line.

## Return

- `verdict: pass` (`status: complete`, `gate: none`, `phase: check`, `checks: design`) when no finding
  is blocking. The orchestrator then applies the design gate and opens the design PR.
- `verdict: fail` when any finding is blocking — the orchestrator re-dispatches `card-designer` with
  your findings verbatim, up to the `design` check budget, then parks the card.
- `phase_doc` is `design-check.md`: `## Verdict`, `## Criteria` (the full table — id, verdict,
  evidence), `## Acceptance criteria → tasks` (the two-way map), `## Doctrine` (rule by rule, how the
  design honours it or why it does not apply), `## Blocking findings`, `## Advisory findings`.
- `status: needs-input` only if you cannot check at all (`design.md` missing, spec unreachable). A
  design you would have written differently is a `pass` with advisory findings — you are not the
  designer, and taste is not a defect.
- Add `knowledge` entries for recurring design traps worth teaching the designer (scope: repo).
- You may return `proposed_adrs` when the design makes a significant decision it failed to record —
  but prefer a `DSG-ADR-NEEDED` finding, so the *designer* records it and learns.
````

- [ ] **Step 3: Verify frontmatter and tools**

Run:
```bash
rtk proxy grep -E "^(name|model|tools):" plugins/kanban-flow/agents/card-design-checker.md
```
Expected exactly:
```
name: card-design-checker
model: opus
tools: Read, Grep, Glob, Skill
```

- [ ] **Step 4: Verify the doctrine linkage exists**

Run:
```bash
rtk proxy grep -c "DSG-DOCTRINE" plugins/kanban-flow/agents/card-design-checker.md
```
Expected: `2` or more.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/agents/card-design-checker.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): add card-design-checker

Checks card-designer against the DSG-* criteria before the design gate and
before the design PR opens. Opus, because a checker outclassed by its
producer rubber-stamps.

Derives its own expected task list from the acceptance criteria before
reading the design, maps criteria to tasks in both directions, opens every
cited spec section, and works AGENT-PROTOCOL's Doctrine rule by rule — which
is the point at which that doctrine stops being advice and starts being
verified.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: card-deliver-checker

Haiku, because every one of its criteria is answered by evidence from `gh` and `git` rather than by judgement. The only checker with `Bash`, and it uses it read-only.

**Files:**
- Create: `plugins/kanban-flow/agents/card-deliver-checker.md`

**Interfaces:**
- Consumes: Task 1's Checker contract; Task 2's `## deliver` criteria (`DLV-BASE`, `DLV-BODY-TRUE`, `DLV-SIZE`, `DLV-DOCS`, `DLV-PURITY`, `DLV-CI`).
- Produces: a `result` with `checks: deliver`, `actual_lines: <int>` reported in the `phase_doc`, and a `phase_doc` the orchestrator writes to `card_dir/deliver-check.md`.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
test -f plugins/kanban-flow/agents/card-deliver-checker.md && echo EXISTS || echo MISSING
```
Expected: `MISSING`.

- [ ] **Step 2: Create the agent**

Create `plugins/kanban-flow/agents/card-deliver-checker.md`:

````markdown
---
name: card-deliver-checker
description: Checks card-deliverer's work after a PR opens. Verifies the PR targets main from the right branch, that every claim in the PR body is supported by the diff, that the expected phase docs ride it, that a design PR carries no code, that CI is not red — and measures the actual changed lines against size_limit, proposing a concrete split into smaller PRs when it breaches. Produces deliver-check.md. Read-only against GitHub: never comments, approves, merges or mutates.
model: haiku
tools: Read, Grep, Glob, Bash, Skill
---

# card-deliver-checker — checker for card-deliverer

You check ONE open PR. You are a **checker**: read the Checker contract in the plugin
`AGENT-PROTOCOL.md` (absolute path in your dispatch) and obey it exactly. Nothing checks you — the
human merging the PR is your backstop.

**You have `Bash`, and it is read-only.** You run `gh` *read* commands and `git` *read* commands to
gather evidence. You never comment on the PR, never approve, never request changes, never resolve,
never react, never push, never merge. `card-deliverer` is the only agent in this system that mutates
GitHub, and you are not it.

Read: the plugin `AGENT-PROTOCOL.md` (Doctrine + Checker contract), the repo's
`PROTOCOL-ADDENDUM.md` if present, the **Method** and **`## deliver`** sections of the plugin
`CHECK-CRITERIA.md` (absolute path in your dispatch, plus any `## Check criteria — deliver` addendum
section), and `KNOWLEDGE.md`. Your dispatch gives you `card.md`, the `pr_url`, the PR **mode**
(`design` | `implementation`), and the `worktree`.

## Do

1. **Gather the evidence** (`{gh_command}` from `config.md`):
   ```bash
   {gh_command} pr view <pr_url> --json baseRefName,headRefName,body,state,files
   {gh_command} pr checks <pr_url>
   git -C <worktree> diff --numstat main...HEAD
   git -C <worktree> log --oneline main..HEAD
   ```
   Paste real output into your evidence. Never report a result you did not observe.

2. **`DLV-BASE`** — `baseRefName` is `main`; `headRefName` matches the card's `branch`. A design PR's
   branch ends `-design`; an implementation PR's does not.

3. **`DLV-BODY-TRUE`** — read the PR body claim by claim and find each one in the diff. A body
   claiming an acceptance criterion is implemented when no code or test in the diff serves it is
   blocking: the PR body is what the human reads instead of the diff, so a false body is a lie told
   to the reviewer.

4. **`DLV-SIZE`** (implementation PRs only — `na` on a design PR). Sum `added + deleted` from
   `--numstat`, **excluding** paths matching `size_exclude` (`config.md`). **Tests count.** Report
   `actual_lines: <N>` in your `phase_doc` **whether or not it breaches** — the orchestrator records
   it on the card and `/retro` reads it against `estimated_lines`.

   **On a breach:** severity is `advisory`, never blocking (the code is written; re-dispatching the
   deliverer cannot un-write it). But you **must propose a concrete split** in the finding's
   `remedy` — name which commits or file groups become which smaller PRs, and in what order. "This is
   too big" without a proposed split is not a finding, it is a complaint.

5. **`DLV-DOCS`** — the phase docs that should ride this PR are in the diff. Design PR: `slice.md`,
   `design.md`, `slice-check.md`, `design-check.md`, and any ADRs. Implementation PR: `implement.md`,
   `test.md`, `review.md`.

6. **`DLV-PURITY`** — a design PR carries **no code** (docs and ADRs only). An implementation PR
   carries nothing unrelated to the card.

7. **`DLV-CI`** — fails only on **red**. Pending or running CI is `pass` with evidence saying so; no
   checks configured is `pass` (a docs-only design PR is reviewable without a pipeline).

8. **Verdict every criterion** with evidence — the real command output, not a summary of it.

## Return

- `verdict: pass` (`status: complete`, `gate: none`, `phase: check`, `checks: deliver`) when no
  finding is blocking. A `DLV-SIZE` breach alone is a `pass` — it is advisory — but the orchestrator
  surfaces your split proposal to the driver prominently.
- `verdict: fail` when any finding is blocking — the orchestrator re-dispatches `card-deliverer`
  (wrong base, false body, missing docs, impure PR) or `card-implementer` (a claimed acceptance
  criterion genuinely is not implemented), up to the `deliver` check budget.
- `phase_doc` is `deliver-check.md`: `## Verdict`, `## Criteria` (the full table — id, verdict,
  evidence with real command output), `## Size` (`actual_lines`, the excluded paths, and against
  `estimated_lines` from the card), `## Blocking findings`, `## Advisory findings` (a `DLV-SIZE`
  breach's proposed PR split lives here, in full).
- `status: blocked` only if you cannot check at all (`{gh_command}` failing, PR unreachable).
````

- [ ] **Step 3: Verify frontmatter and that Bash is present**

Run:
```bash
rtk proxy grep -E "^(name|model|tools):" plugins/kanban-flow/agents/card-deliver-checker.md
```
Expected exactly:
```
name: card-deliver-checker
model: haiku
tools: Read, Grep, Glob, Bash, Skill
```

- [ ] **Step 4: Verify the read-only-GitHub constraint is stated explicitly**

Run:
```bash
rtk proxy grep -c "never merge" plugins/kanban-flow/agents/card-deliver-checker.md
```
Expected: `1`. This agent has `Bash` and a `pr_url`; the constraint must be unmissable.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/agents/card-deliver-checker.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): add card-deliver-checker

Checks the opened PR against the DLV-* criteria from real gh/git output.
Haiku, because every criterion is answered by evidence rather than judgement.

Measures actual changed lines and records actual_lines on every card, breach
or not, so /retro can read it against the slicer's estimate. A breach is
advisory — the code is already written — but it must propose a concrete split
into smaller PRs; "too big" without a proposed split is a complaint, not a
finding.

Has Bash, and it is read-only: card-deliverer remains the only agent that
mutates GitHub.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: card-intake-checker

Runs before the driver ever sees a proposal, so their attention goes on judgement rather than catching structural sloppiness.

**Files:**
- Create: `plugins/kanban-flow/agents/card-intake-checker.md`

**Interfaces:**
- Consumes: Task 1's Checker contract; Task 2's `## intake` criteria (`INT-AC-OBSERVABLE`, `INT-REQ-RESOLVES`, `INT-VERTICAL`, `INT-COVERAGE`, `INT-NO-OVERLAP`, `INT-DAG`, `INT-MILESTONE`).
- Produces: a `result` with `checks: intake`. **Dispatched by `/refine` and `/requirement`, not by `/kanban`** — the only checker with a non-orchestrator caller. Task 12 wires it in.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
test -f plugins/kanban-flow/agents/card-intake-checker.md && echo EXISTS || echo MISSING
```
Expected: `MISSING`.

- [ ] **Step 2: Create the agent**

Create `plugins/kanban-flow/agents/card-intake-checker.md`:

````markdown
---
name: card-intake-checker
description: Checks the card set proposed by /refine or /requirement, before the driver sees it. Verifies every acceptance criterion is observable, every REQ id resolves, every card is a vertical slice, the set covers the requirement without overlap, depends_on is acyclic, and the milestone plan holds. Blocking findings send the intake skill back to revise. Produces an intake-check report. Never writes files, never creates cards.
model: opus
tools: Read, Grep, Glob, Skill
---

# card-intake-checker — checker for intake (/refine, /requirement)

You check a **proposed card set** before any card exists on disk and before the driver is asked to
approve it. You are a **checker**: read the Checker contract in the plugin `AGENT-PROTOCOL.md`
(absolute path in your dispatch) and obey it exactly. You write nothing, create no cards, and nothing
checks you — the driver's approval gate is your backstop.

You are the earliest checker in the system, and the cheapest place to fix anything: a malformed
acceptance criterion caught here costs one revision; the same criterion caught at review costs a
design, an implementation, and two rework loops.

Read: the plugin `AGENT-PROTOCOL.md` (Doctrine + Checker contract), the repo's
`PROTOCOL-ADDENDUM.md` if present, the **Method** and **`## intake`** sections of the plugin
`CHECK-CRITERIA.md` (absolute path in your dispatch, plus any `## Check criteria — intake` addendum
section), the plugin `INTAKE.md` (the slicing and milestone doctrine the proposal is meant to
follow), and `KNOWLEDGE.md`. Your dispatch gives you: the **proposed cards** (title, type, layer,
reqs, why, acceptance criteria, depends_on), the **milestone plan**, the **existing board** (card ids
and their milestones), and the **requirement(s)** in scope, plus `spec_path`.

## Do

1. **Derive before you read.** Read the requirement(s) in the spec first and list, in your own words,
   the observable behaviours they demand. *Only then* read the proposed cards. Doing it the other way
   round means measuring the proposal against itself.

2. **Map behaviours → cards.** A demanded behaviour claimed by no card is `INT-COVERAGE`. A behaviour
   claimed by two cards is `INT-NO-OVERLAP`. Both are blocking: the first ships an incomplete
   requirement, the second guarantees a merge conflict and duplicated work.

3. **Read every acceptance criterion and ask: *what would I run to see this?*** If you cannot name
   the observation, it fails `INT-AC-OBSERVABLE`. "The system is robust", "performance is
   acceptable", "the code is clean" — none is a criterion. "A request with no auth header returns
   401" is.

4. **Resolve every `reqs` id** against the spec (`INT-REQ-RESOLVES`) — it must exist and not be
   superseded. A card citing a superseded REQ is building something the project already decided
   against.

5. **Build the `depends_on` graph by hand** and walk it: cycles fail `INT-DAG`; an id naming neither
   a proposed sibling nor a real card fails `INT-DAG`; a card depending on a card in a *later*
   milestone fails `INT-MILESTONE`.

6. **Check each card is a vertical slice** (`INT-VERTICAL`) per `INTAKE.md` — observable behaviour,
   not a horizontal layer. A "set up the database schema" card with no user-visible outcome is the
   canonical failure.

7. **Verdict every criterion** with evidence citing the proposed card or the spec line.

## Return

- `verdict: pass` (`status: complete`, `gate: none`, `phase: check`, `checks: intake`) when no finding
  is blocking. The intake skill then presents the proposal to the driver.
- `verdict: fail` when any finding is blocking — the intake skill revises the proposal and re-checks,
  up to the `intake` check budget, then presents to the driver with your findings attached.
- `phase_doc` is the intake check report: `## Verdict`, `## Criteria` (the full table — id, verdict,
  evidence), `## Requirement coverage` (behaviour → card map), `## Blocking findings`,
  `## Advisory findings`. The intake skill shows this to the driver alongside the proposal; it is not
  written as a card phase doc (no card exists yet).
- `status: needs-input` only if you cannot check at all (spec unreadable, no proposal supplied).
- **A card set you would have sliced differently is a `pass`.** Granularity that meets `INT-VERTICAL`
  is the intake skill's call, not yours. Taste is not a defect.
- Add `knowledge` entries for recurring intake traps (scope: repo, section: Conventions).
````

- [ ] **Step 3: Verify frontmatter and tools**

Run:
```bash
rtk proxy grep -E "^(name|model|tools):" plugins/kanban-flow/agents/card-intake-checker.md
```
Expected exactly:
```
name: card-intake-checker
model: opus
tools: Read, Grep, Glob, Skill
```

- [ ] **Step 4: Verify all four checkers now exist**

Run:
```bash
rtk proxy ls plugins/kanban-flow/agents/ | rtk proxy grep -c "checker"
```
Expected: `4`.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/agents/card-intake-checker.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): add card-intake-checker

Checks /refine's and /requirement's proposed card set against the INT-*
criteria before the driver sees it, so their attention goes on judgement
rather than catching structural sloppiness.

The earliest and cheapest checker: a malformed acceptance criterion caught
here costs one revision; the same criterion caught at review costs a design,
an implementation and two rework loops.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Collapse card-reviewer into a pre-PR lens panel

The riskiest task — it touches working machinery. It is one commit because a reviewer must accept or reject it as a unit: renaming the panel agent without deleting `card-reviewer` would run both, and deleting `card-reviewer` without the `acceptance` lens would lose acceptance-criteria traceability entirely.

**Files:**
- Rename: `plugins/kanban-flow/agents/pr-expert-reviewer.md` → `plugins/kanban-flow/agents/card-lens-reviewer.md`
- Delete: `plugins/kanban-flow/agents/card-reviewer.md`
- Modify: `plugins/kanban-flow/templates/REVIEW-LENSES.md`
- Modify: `plugins/kanban-flow/templates/AGENT-PROTOCOL.md`

**Interfaces:**
- Consumes: nothing new.
- Produces: agent `card-lens-reviewer` (dispatched once per lens, in parallel, at `status: review`), the `acceptance` lens, and a `phase_doc` per lens that the orchestrator concatenates into `card_dir/review.md`. Task 11 rewires the orchestrator to dispatch it.

- [ ] **Step 1: Write the failing assertions**

Run:
```bash
rtk proxy grep -c "^## \[acceptance\]" plugins/kanban-flow/templates/REVIEW-LENSES.md; \
test -f plugins/kanban-flow/agents/card-reviewer.md && echo REVIEWER_EXISTS
```
Expected: `0` (exit 1), then `REVIEWER_EXISTS`. Neither is the end state.

- [ ] **Step 2: Rename the panel agent**

```bash
git mv plugins/kanban-flow/agents/pr-expert-reviewer.md \
       plugins/kanban-flow/agents/card-lens-reviewer.md
```

- [ ] **Step 3: Rewrite `card-lens-reviewer.md` for the pre-PR world**

Replace the **entire** contents of `plugins/kanban-flow/agents/card-lens-reviewer.md` with:

````markdown
---
name: card-lens-reviewer
description: Review phase. One expert lens of the review panel — reviews the card's branch diff against main from a single assigned lens (acceptance, design, functionality, simplicity, tests, readability, security, python, typescript) per the REVIEW-LENSES doctrine, in the card's worktree, before any PR opens. Returns findings to the orchestrator; blocking findings feed the automatic rework loop. Dispatched once per lens, in parallel. Never touches GitHub.
model: sonnet
tools: Read, Grep, Glob, Bash, Skill
---

# card-lens-reviewer — one lens of the review panel

You are **one expert on a panel**, and together the panel is `card-implementer`'s checker. Your
dispatch prompt names your `lens`, the card's `worktree`, `card_id`, and `card.md`. You review the
whole branch diff **through that lens only**.

You run **before any PR exists**. You do not touch GitHub — you have no `pr_url` and no business with
one. You return findings; the orchestrator persists them and runs the rework loop. The PR the human
eventually sees is one your panel has already cleaned.

First read the plugin protocol at the `AGENT-PROTOCOL.md` absolute path your dispatch provides
(Doctrine included), then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both. Then read
**only**: `KNOWLEDGE.md`; the **Etiquette** and **Method** sections plus **your lens's section** of
the plugin `REVIEW-LENSES.md` at the absolute path your dispatch provides; and the card's `design.md`
(acceptance criteria, scope, spec references), `implement.md` and `test.md`. Read the spec sections
`design.md` cites if your lens needs them. Do not read other lenses' sections. Your lens section's
**Walk** is your procedure — execute its steps in order and hold its **Ask of every hunk** questions
through the line pass; its **Example finding** is your calibration bar for depth and finding shape.

## Do

1. Get the diff: `git -C <worktree> diff main...HEAD`. **Map pass first** (whole diff + `design.md`,
   write nothing), then the line pass through your lens's Walk. Use the `worktree` (Read/Grep) for
   surrounding context the diff hides — a hunk that looks fine in isolation may break an invariant
   visible one screen up.
2. Apply the Method gates to every candidate finding before it becomes a finding: **verify in the
   worktree** (grep for the counter-evidence), pass the **rebuttal test** (if the author's best
   defence wins, drop it or downgrade), check it is not in your lens's **Don't flag** list, and shape
   it as **observation → consequence → fix**, anchored to `path:line`.
3. **Classify severity.** `blocking` — correctness, a spec violation, a broken invariant, an
   acceptance criterion with no test. `advisory` — nits, polish, questions you could not verify.
   Blocking findings are re-dispatched to `card-implementer` verbatim and cost a rework loop from a
   finite budget, so do not inflate: two verified blocking findings beat ten speculative ones. Max 10
   findings, highest value first, never padded.

## Return

- `status: blocked` with `blockers` = your **blocking** findings, if any — the orchestrator merges the
  panel's blocking findings and runs the automatic rework loop (or parks the card once the
  `implement` check budget is spent). Each blocker must be actionable: `path:line`, what is wrong,
  what right looks like.
- Otherwise `status: complete`, `gate: none`, `phase: review`.
- `phase_doc` is your lens's slice of `review.md`: `## [<lens>]` then `### Blocking` and
  `### Advisory` bullets (`path:line — observation → consequence → fix`). **Zero findings must be
  earned:** instead of a bare `No findings.`, list what you checked and found clean (per the Method)
  — `/retro` reads this to tell diligence from a skim. The orchestrator concatenates the panel's
  phase docs into one `review.md`.
- Add `knowledge` entries for recurring patterns worth teaching earlier phases (scope: repo).
- Never write files, never touch GitHub, never fix the code — you review; the implementer fixes.
````

- [ ] **Step 4: Delete card-reviewer**

```bash
git rm plugins/kanban-flow/agents/card-reviewer.md
```

- [ ] **Step 5: Reframe REVIEW-LENSES.md's header for the pre-PR panel**

In `templates/REVIEW-LENSES.md`, replace the opening block (lines 1–12, from `# PR review panel — lenses` through the paragraph ending `**Example finding** showing the calibration bar and comment shape.`) with:

```markdown
# Review panel — lenses

One `card-lens-reviewer` agent is dispatched per lens at the card's **review** phase, against the
branch diff in the card's worktree — **before any PR opens**. Together the panel is
`card-implementer`'s checker: blocking findings feed the automatic rework loop, so the PR the human
eventually sees has already survived every lens. Each expert reads the two shared sections
(**Etiquette**, **Method**) plus **only its own lens section**. Checklists distil
[Google's eng-practices reviewer guide](https://google.github.io/eng-practices/review/reviewer/looking-for.html)
onto this codebase.

Each lens section has the same shape: **Focus** (your one job), **Walk** (the procedure — follow it
in order, don't freestyle), **Ask of every hunk** (anchor questions to hold in mind on the
line-by-line pass), **Red flags** (concrete patterns, greppable where possible), **Don't flag**
(known false positives — a wrong finding costs the implementer a rework loop), and a worked
**Example finding** showing the calibration bar and finding shape.
```

- [ ] **Step 6: Rewrite the Etiquette section for findings, not GitHub comments**

Replace the whole `## Etiquette (every lens)` section with:

```markdown
## Etiquette (every lens)
- Every finding **starts with your tag**, e.g. `[design] …` or `[security] …`.
- **Severity is `blocking` or `advisory`.** `blocking` = correctness, spec violation, broken
  invariant, or an acceptance criterion with no test — it goes back to the implementer verbatim and
  costs a rework loop from a finite budget. `advisory` = polish, nits, and things you suspect but
  could not verify; these ride the PR for the human and never trigger rework. **Do not inflate.** A
  card that burns its rework budget on nits parks for the driver.
- Comment on the code, never the author ("this function recomputes…", not "you recompute…").
- Every finding is anchored to `path:line` in the branch diff.
- Stay in your lane: skip findings clearly owned by another lens unless severe and likely missed.
- Max 10 findings — but never pad toward it. Two verified findings beat ten speculative ones.
- Mention one notable good thing in your phase doc when you see it. Reviews teach.
- You do not touch GitHub. There is no PR yet.
```

- [ ] **Step 7: Fix the two Method references to posting**

In `## Method`, replace item 2's parenthetical:

```
   If you can't verify it, either drop it or post it honestly as `Question:` with what you checked.
```
with:
```
   If you can't verify it, either drop it or record it honestly as `advisory` with what you checked.
```

and item 3's last line:

```
   because Y"). If the defence wins, don't post. If you can't tell, `Question:`.
```
with:
```
   because Y"). If the defence wins, drop it. If you can't tell, make it `advisory`.
```

and item 6's opening:

```
6. **Zero findings must be earned.** If you post nothing, your returned phase_doc lists what you
```
with:
```
6. **Zero findings must be earned.** If you find nothing, your returned phase_doc lists what you
```

- [ ] **Step 8: Add the `acceptance` lens**

Insert this section immediately **after** the `## Method` section and **before** `## [design]`:

````markdown
## [acceptance]
**Focus:** Does this branch actually deliver the card, and does it hold the project's invariants?
You are the lens that absorbed the old `card-reviewer` — traceability and conventions are yours, and
if you do not check them, nobody does.

**Walk:**
1. **Traceability, criterion by criterion.** For every acceptance criterion in `design.md`, name the
   specific test(s) that prove it — file and test name. A criterion with no test is a **blocking**
   finding, always. This is the single highest-value check on the panel: a card can be beautiful,
   secure, simple and readable and still not do what it was asked to do.
2. **Scope, both directions.** Anything in the diff outside `design.md`'s in-scope list is a
   drive-by; anything in the in-scope list absent from the diff is unfinished. Both are findings.
3. **Convention adherence:** `KNOWLEDGE.md`'s Conventions section, and the project invariants — core
   logic only in its designated layer; adapters and wrappers hold no business logic; the spec's exact
   rounding rule, never a language default.
4. **Deviation audit:** read `implement.md`'s `## Deviations from design`. Every deviation is either
   justified in writing or a finding.

**Ask of every hunk:** Which acceptance criterion does this line serve? If none — why is it here?

**Red flags:** an acceptance criterion whose "test" only asserts the function returns without
raising; a criterion marked done in `implement.md` with no corresponding test; production code with
no test touching it at all; a `## Deviations from design` section that is empty on a diff that
plainly departs from the design; business logic outside its designated layer.

**Don't flag:** test *quality* (that's `[tests]`'s lane — you check a criterion has *a* test; they
check it would catch a bug); design elegance (`[design]`); missing criteria the card never claimed.

**Example finding.** `design.md` lists AC-3 "a voided line item is excluded from the order total",
and `implement.md` marks it done. Grep of the diff finds `tests/domain/test_totals.py` with
`test_total_sums_lines` and `test_total_empty_order` — neither constructs a voided line.
Finding: `[acceptance] blocking — tests/domain/test_totals.py: AC-3 (voided line items excluded from
the total) has no test. The two tests here cover the happy path and the empty case; neither builds a
voided line, so the exclusion branch in domain/totals.py:34 is unproven and would pass CI even if it
were inverted. Add a test with one voided and one live line asserting the total equals the live line
only.`
````

- [ ] **Step 9: Tighten AGENT-PROTOCOL's GitHub exception from two to one**

In `templates/AGENT-PROTOCOL.md`, in the `## Boundaries (sole-writer invariant)` section, replace:

```markdown
- **GitHub is off-limits to phase agents**, with two exceptions: the deliver phase pushes the branch
  and opens the PR; the pr-review phase posts its lens's findings as **one `COMMENT` review** with
  `[lens]`-prefixed inline comments. No agent ever approves, requests changes, replies to, resolves,
  or reacts to PR threads — the review-complete signal, 👍 triage of panel comments, and resolution
  belong to the human.
```

with:

```markdown
- **GitHub is off-limits to phase agents, with exactly one exception:** the deliver phase pushes the
  branch and opens the PR. Nothing else. The review panel runs **before** the PR opens, against the
  branch diff in the worktree, and returns findings to the orchestrator — it does not comment on
  GitHub. `card-deliver-checker` reads the PR (`gh pr view`, `gh pr checks`) but mutates nothing. No
  agent ever comments, approves, requests changes, replies to, resolves, or reacts to a PR thread —
  the review-complete signal and thread resolution belong to the human, and the orchestrator alone
  replies with commit links.
```

- [ ] **Step 10: Update the protocol's dispatch list for the renamed agent**

In `templates/AGENT-PROTOCOL.md`'s `## On dispatch you receive` section, replace:

```markdown
- A **pr-review** dispatch (`pr-expert-reviewer`, one per lens after an implementation PR opens)
  carries a `lens` and the `pr_url` instead of prior phase docs.
```

with:

```markdown
- A **review** dispatch (`card-lens-reviewer`, one per lens, in parallel, at the review phase) carries
  a `lens` and reviews the branch diff in the `worktree` — before any PR exists.
- A **check** dispatch (a `card-*-checker`) carries the producer's inputs and its output artifact, and
  the plugin's `CHECK-CRITERIA.md` path. See the Checker contract below.
```

- [ ] **Step 11: Verify the collapse is complete**

Run:
```bash
rtk proxy grep -rn "pr-expert-reviewer\|card-reviewer" plugins/kanban-flow/ ; echo "exit=$?"
```
Expected: no matches in `agents/` or `templates/`. **Matches in `skills/kanban/SKILL.md` are expected at this point** — Task 11 rewires the orchestrator. If any match appears in `agents/` or `templates/`, fix it before committing.

Run:
```bash
rtk proxy grep -c "^## \[acceptance\]" plugins/kanban-flow/templates/REVIEW-LENSES.md; \
test -f plugins/kanban-flow/agents/card-lens-reviewer.md && echo LENS_OK; \
test -f plugins/kanban-flow/agents/card-reviewer.md && echo BAD_STILL_THERE || echo REVIEWER_GONE
```
Expected: `1`, `LENS_OK`, `REVIEWER_GONE`.

- [ ] **Step 12: Commit**

```bash
git add -A plugins/kanban-flow/agents plugins/kanban-flow/templates
git commit -m "$(cat <<'EOF'
feat(kanban-flow)!: collapse card-reviewer into a pre-PR lens panel

card-reviewer and the pr-expert-reviewer panel reviewed the same diff twice.
They become one: pr-expert-reviewer is renamed card-lens-reviewer, moves to
the review phase against the worktree diff before any PR opens, and a new
[acceptance] lens absorbs card-reviewer's acceptance-criteria traceability
and convention checks. card-reviewer is deleted.

Blocking panel findings now auto-rework the implementer instead of waiting on
the human's review-complete signal and per-comment triage. The PR the human
opens has already survived every lens.

Consequence: AGENT-PROTOCOL's "GitHub is off-limits, with two exceptions" is
now one exception — card-deliverer. No phase agent comments on a PR.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: config.md — the four new keys

**Files:**
- Modify: `plugins/kanban-flow/templates/config.md`

**Interfaces:**
- Produces: `checks`, `check_budget`, `size_limit`, `size_exclude`. Read by Task 11 (orchestrator), Tasks 4/6 (size), Task 12 (intake), Task 13 (`/migrate` adds them to existing repos).

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -cE "^(checks|check_budget|size_limit|size_exclude):" plugins/kanban-flow/templates/config.md
```
Expected: `0` (exit 1).

- [ ] **Step 2: Add the keys to the frontmatter**

In `templates/config.md`, after the `gates:` block (which ends with `  deliver: auto`) and before `layers:`, insert:

```yaml
checks:
  intake: on
  slice: on
  design: on
  deliver: on
check_budget:
  intake: 2
  slice: 2
  design: 2
  implement: 2
  deliver: 1
size_limit: 500
size_exclude:
  - "*.lock"
  - "package-lock.json"
  - "yarn.lock"
  - "pnpm-lock.yaml"
  - "Cargo.lock"
  - "poetry.lock"
  - "uv.lock"
  - "go.sum"
  - "Gemfile.lock"
  - "composer.lock"
  - "vendor/**"
  - "node_modules/**"
```

- [ ] **Step 3: Document them in the prose section**

In the bullet list below the frontmatter, after the `- **gates** — …` bullet, insert:

```markdown
- **checks** — every producer has a checker, and by default every check runs.
  This switch exists as an escape hatch for a checker that turns out noisy, not
  as a routine tunable: while any check is `off`, `/kanban` warns in every pump
  report and on `BOARD.md`'s header, naming what is shipping unchecked. Note the
  reach of `slice: off` in particular — `SLC-SIZE` is the only thing enforcing
  **size_limit** *before code is written*, so disabling the slice check removes
  the hard cap on card size and leaves only `DLV-SIZE`'s after-the-fact warning.
  There is deliberately **no `implement` switch**: the implementer's checkers are
  `card-tester` and the lens panel, so an off switch there would silently skip
  running the test suite. The implement chain is unconditional.
- **check_budget** — per-producer automatic rework loops before a card parks for
  the driver. Budgets are per-producer so a card that needed two design revisions
  does not arrive at implement with nothing left. `implement: 2` is the historic
  behaviour of the old single `reworks` counter. `deliver: 1` because a delivery
  check failing twice means something another deliverer pass will not fix.
- **size_limit** — the hard ceiling on a card's **changed lines, including
  tests** (default 500). Enforced twice: `card-slice-checker` independently
  estimates before any code is written and a projected breach **forces a split**
  (`SLC-SIZE`, blocking); `card-deliver-checker` measures the real diff and, on a
  breach, must propose a concrete split into smaller PRs (`DLV-SIZE`, advisory).
  This is the real ceiling on card size in the system.
- **size_exclude** — glob paths omitted from both counts: machine-authored files
  a human never reviews. Lock files and vendored dependencies by default; add
  your project's generated code (protobuf stubs, OpenAPI clients) here.
```

- [ ] **Step 4: Verify the keys are present and the YAML frontmatter still parses**

Run:
```bash
rtk proxy grep -cE "^(checks|check_budget|size_limit|size_exclude):" plugins/kanban-flow/templates/config.md
```
Expected: `4`.

Run (confirms the frontmatter block is still well-formed — the `---` fences are intact and balanced):
```bash
rtk proxy grep -c "^---$" plugins/kanban-flow/templates/config.md
```
Expected: `2`.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/templates/config.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): add checks, check_budget, size_limit, size_exclude to config

Checks default on; the switch is an escape hatch for a noisy checker, and
/kanban warns loudly while one is off. Deliberately no implement switch — the
implementer's checkers are the tester and the lens panel, so an off switch
there would silently skip running the test suite.

Budgets are per-producer so a card that spent two loops on design does not
reach implement with nothing left.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: card-template.md — reworks map, estimated_lines, actual_lines

**Files:**
- Modify: `plugins/kanban-flow/templates/card-template.md`

**Interfaces:**
- Consumes: Task 3's `estimated_lines`, Task 6's `actual_lines`, Task 9's `check_budget`.
- Produces: the `reworks` map shape, `estimated_lines`, `actual_lines`. Task 11 reads/writes them; Task 13 migrates legacy cards to them; Task 14 mines them.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -c "^reworks: 0" plugins/kanban-flow/templates/card-template.md
```
Expected: `1` — the old scalar shape is still there.

- [ ] **Step 2: Replace the `reworks` scalar with the per-producer map**

In `templates/card-template.md`, replace this line:

```yaml
reworks: 0            # automatic test/review→implement loops consumed (budget 2); flow-metric input for /retro
```

with:

```yaml
reworks:              # automatic rework loops consumed, per producer (budgets: config.md `check_budget`); flow-metric input for /retro
  slice: 0            # card-slice-checker → card-slicer
  design: 0           # card-design-checker → card-designer
  implement: 0        # card-tester / the lens panel → card-implementer
  deliver: 0          # card-deliver-checker → card-deliverer
estimated_lines: ""   # changed lines card-slicer projected, verified by card-slice-checker; the SLC-SIZE ceiling is config.md `size_limit`
actual_lines: ""      # changed lines card-deliver-checker measured on the implementation PR; vs estimated_lines it is /retro's signal that the slicer under-estimates
```

- [ ] **Step 3: Verify the new shape**

Run:
```bash
rtk proxy grep -cE "^(estimated_lines|actual_lines):" plugins/kanban-flow/templates/card-template.md; \
rtk proxy grep -c "^reworks: 0" plugins/kanban-flow/templates/card-template.md
```
Expected: `2`, then `0` (exit 1 on the second — the scalar is gone).

- [ ] **Step 4: Commit**

```bash
git add plugins/kanban-flow/templates/card-template.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): per-producer reworks map, estimated_lines, actual_lines

reworks becomes a map keyed by producer so a card that needed two design
revisions does not arrive at implement with no budget left. estimated_lines
and actual_lines are the size budget's two halves, and their delta is what
tells /retro the slicer is systematically under-estimating.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Orchestrator — check sub-steps, budgets, dispatch table

The first half of the `/kanban` rewiring: how checks run. Task 11b handles the PR flow.

**Files:**
- Modify: `plugins/kanban-flow/skills/kanban/SKILL.md`

**Interfaces:**
- Consumes: everything from Tasks 1–10.
- Produces: the dispatch-vs-handle rule for `<phase>-check.md`, the per-producer rework loop, and the `checks`/`check_budget` reads.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -c "check_budget" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: `0` (exit 1).

- [ ] **Step 2: Read the new config keys in Section 1**

In `## 1. Load state`, replace:

```markdown
Read `{board_dir}/config.md` first — it carries the tunables (`spec_path`, `gh_command`, `wip_limit`, `gates`, `layers`, `gate_layer`, `adr_dir`, `coverage_target`). Everything below reads these; never hardcode them.
```

with:

```markdown
Read `{board_dir}/config.md` first — it carries the tunables (`spec_path`, `gh_command`, `wip_limit`, `gates`, `checks`, `check_budget`, `size_limit`, `size_exclude`, `layers`, `gate_layer`, `adr_dir`, `coverage_target`). Everything below reads these; never hardcode them. Missing `checks` producer → `on`; missing `check_budget` producer → `2` (`deliver` → `1`); missing `size_limit` → `500`.
```

Then, in the same section, replace:

```markdown
Read every `docs/cards/CARD-*/card.md` and parse its frontmatter (missing `reworks`/`started`/`delivered`/`design_pr_url` fields default to `0`/empty — legacy cards).
```

with:

```markdown
Read every `docs/cards/CARD-*/card.md` and parse its frontmatter (missing `started`/`delivered`/`design_pr_url`/`estimated_lines`/`actual_lines` fields default to empty — legacy cards). **`reworks` is a per-producer map** (`{slice, design, implement, deliver}`); a legacy scalar `reworks: N` reads as `{implement: N}`, everything else `0` (Section 0.5 normalises it on disk).
```

- [ ] **Step 3: Add the check sub-step to the dispatch-vs-handle rule (Section 5)**

In `## 5. Advance in-flight cards`, replace the paragraph:

```markdown
**Dispatch vs. handle:** phase-doc presence in the card's current worktree `card_dir` decides — absent → dispatch the phase agent; present → handle (gate or advance). Key states:
```

with:

```markdown
**Dispatch vs. handle:** phase-doc presence in the card's current worktree `card_dir` decides — absent → dispatch the phase agent; present → handle (gate or advance).

**Every producer is followed by its checker before its gate.** The same rule extends with no new machinery: the **phase doc** present + its **`<phase>-check.md` absent** → dispatch the checker; both present with `verdict: pass` → advance. A check whose `checks` policy is `off` is skipped entirely (and warned about, Section 7). Checkers never trigger a gate — they gate the *producer*, and the driver's gate comes after.

Key states:
```

- [ ] **Step 4: Add the check states to the key-states list**

In the same key-states list, make these three replacements.

Replace:
```markdown
- `status: slice` + `slice.md` absent → dispatch card-slicer (no worktree; include the card's **dependents** for `dependents_rewire`).
- slice right-sized (or start with `right_sized: true`) → **design transition:**
```
with:
```markdown
- `status: slice` + `slice.md` absent → dispatch card-slicer (no worktree; include the card's **dependents** for `dependents_rewire`).
- `status: slice` + `slice.md` present + `slice-check.md` absent + `checks.slice: on` → **dispatch card-slice-checker** (same inputs as the slicer, plus `slice.md` and the slicer's `proposed_cards`/`dependents_rewire`/`estimated_lines`). `verdict: fail` → rework the slicer (below). `verdict: pass` → record `estimated_lines` on the card and continue.
- slice right-sized *and checked* (or start with `right_sized: true`) → **design transition:**
```

Replace:
```markdown
- `status: design` + `design.md` absent → dispatch card-designer.
- `status: design` + `design.md` present + design stop pending per policy → present the stop (Section 3).
```
with:
```markdown
- `status: design` + `design.md` absent → dispatch card-designer.
- `status: design` + `design.md` present + `design-check.md` absent + `checks.design: on` → **dispatch card-design-checker**. `verdict: fail` → rework the designer (below). `verdict: pass` → continue to the gate.
- `status: design` + `design.md` present + checked + design stop pending per policy → present the stop (Section 3).
```

Replace:
```markdown
- `status: deliver` → deliver gate (Section 3) → card-deliverer in **implementation mode** → record `pr_url` → Section 6.
```
with:
```markdown
- `status: deliver` → deliver gate (Section 3) → card-deliverer in **implementation mode** → record `pr_url` → **dispatch card-deliver-checker** (below) → Section 6.
- **PR open** (design or implementation) + `deliver-check.md` absent + `checks.deliver: on` → **dispatch card-deliver-checker** with the `pr_url`, the PR mode, and the `worktree`. Record its `actual_lines` on the card. `verdict: fail` → rework `card-deliverer` (wrong base, false PR body, missing docs, impure PR) or `card-implementer` (a claimed acceptance criterion genuinely is not implemented), consuming the `deliver` budget. `verdict: pass` → Section 6. **A `DLV-SIZE` advisory breach is a `pass`** — surface its proposed PR split prominently in the report (Section 7) and leave the merge decision to the driver.
```

- [ ] **Step 5: Rewrite the dispatch table**

Replace the whole dispatch table with:

```markdown
| status / condition | dispatch | model |
|---|---|---|
| slice, `slice.md` absent | card-slicer | sonnet |
| slice, `slice.md` present, `slice-check.md` absent | card-slice-checker | sonnet |
| design, `design.md` absent | card-designer | opus |
| design, `design.md` present, `design-check.md` absent | card-design-checker | opus |
| implement | card-implementer | sonnet |
| test | card-tester | haiku |
| review | **card-lens-reviewer × lenses, in parallel** | per-lens (Section 6b) |
| deliver (design or implementation PR) | card-deliverer | haiku |
| PR open, `deliver-check.md` absent | card-deliver-checker | haiku |

(`card-intake-checker` is dispatched by `/refine` and `/requirement`, not by you.)
```

- [ ] **Step 6: Replace the single-counter rework rule with per-producer budgets**

In `### Process each result`, step 4, replace:

```markdown
   - `blocked` from **tester or reviewer** (failing gates / blocking findings) → **automatic rework**: if `reworks < 2`, increment, `status: implement`, delete stale `test.md`/`review.md` from the branch, re-dispatch `card-implementer` in rework mode with the findings verbatim. Else `status: blocked`.
```

with:

```markdown
   - `blocked` from **tester or the lens panel** (failing gates / blocking findings) → **automatic rework**: if `reworks.implement < check_budget.implement`, increment it, `status: implement`, delete stale `test.md`/`review.md` from the branch, re-dispatch `card-implementer` in rework mode with the findings verbatim (merged across lenses). Else `status: blocked`. **On a re-run of the panel, dispatch only the lenses that raised blocking findings** — not all of them.
   - `verdict: fail` from **any checker** → **automatic rework of its producer**: if `reworks.<producer> < check_budget.<producer>`, increment it, delete the stale `<phase>-check.md`, and re-dispatch that producer in rework mode with the checker's blocking findings verbatim (slice → card-slicer; design → card-designer; deliver → card-deliverer or card-implementer per the finding). Else `status: blocked` with the blocker **`check failed — <failing criterion ids>`** (e.g. `check failed — DSG-AC-COVERED, DSG-SCOPE`), and the driver decides. **Advisory findings never trigger rework** — they are recorded in the check doc and ride the PR.
   - **Drop any finding with no `location`** — the contract makes it invalid (`AGENT-PROTOCOL.md`, Checker contract). If dropping it leaves no blocking finding, the verdict is a `pass`.
```

- [ ] **Step 7: Persist the size fields (Process-each-result step 2)**

In `### Process each result`, after step 2 (the `phase_doc` write), insert a new sub-bullet at the end of step 2:

```markdown
   Persist the size fields when a result carries them: `estimated_lines` from **card-slicer** (verified by card-slice-checker) and `actual_lines` from **card-deliver-checker** go onto `card.md` frontmatter with the pump's state commit. Both are `/retro` fuel — never drop them.
```

- [ ] **Step 8: Add the check-doc paths to the docs-ride-their-PR rule**

In `## Rules`, replace the last rule:

```markdown
- All branches off `main`; all PRs target `main`. Phase docs ride their half's PR: slice/design/ADRs/early feedback in the design PR; implement/test/review in the implementation PR.
```

with:

```markdown
- All branches off `main`; all PRs target `main`. Phase docs ride their half's PR: `slice.md`/`slice-check.md`/`design.md`/`design-check.md`/ADRs/early feedback in the design PR; `implement.md`/`test.md`/`review.md` in the implementation PR. `deliver-check.md` commits to `main` — the PR is already open by the time it exists.
- **Checkers are terminal.** Never dispatch a checker for a checker's output. The driver is their backstop.
- Every producer is checked before its gate, unless `checks.<producer>` is `off` — in which case say so, loudly, every pump.
```

- [ ] **Step 9: Render checks on the board (Section 2)**

In `## 2. Render the board (sole writer)`, replace:

```markdown
Rewrite `BOARD.md` from the parsed cards: one bullet per card under the column matching its `status`, showing `CARD-NNN — title · phase · branch` (suffix the `[M<N>]` milestone tag), for blocked cards the blocker, for cards awaiting driver input `(awaiting input)`, and for cards with an open PR the PR link (`design PR #N open` / `PR #N open`).
```

with:

```markdown
Rewrite `BOARD.md` from the parsed cards: one bullet per card under the column matching its `status`, showing `CARD-NNN — title · phase · branch` (suffix the `[M<N>]` milestone tag), for blocked cards the blocker, for cards awaiting driver input `(awaiting input)`, for cards with an open PR the PR link (`design PR #N open` / `PR #N open`), and for a card whose producer has returned but whose checker has not yet run or passed, `· checking <phase>`. A card parked on an exhausted check budget shows its blocker with the failing criterion ids (`check failed — DSG-AC-COVERED, DSG-SCOPE`) — the board says *why* it is stuck without anyone opening a file.

**If any `checks` producer is `off`, put it in the header**, e.g. `⚠ checks disabled: design — cards are reaching the design PR unchecked`. A disabled check is loud, not silent: it is an escape hatch for a checker that turned out noisy, never a state the board lets you drift into and forget.
```

- [ ] **Step 10: Warn about disabled checks in the report (Section 7)**

In `## 7. Report`, after the sentence ending `…what awaits a gate/input/merge, splits, amendments applied (card, action, REQ), blocks, free slots, and per-milestone progress.`, insert:

```markdown
**Check layer:** which checks ran and their verdicts; any producer reworked by its checker (card, failing criterion ids, `reworks.<producer>`); any card parked on an exhausted check budget. Surface a `DLV-SIZE` breach **prominently**, with the checker's proposed PR split verbatim — the driver decides whether to land the PR or split it, and they cannot decide what they cannot see.

**If any `checks` producer is `off`, warn every pump** — name it and name the consequence: *"checks disabled: design — cards are reaching the design PR unchecked"*. For `slice=off` add: *"— and `size_limit` is unenforced before code is written; only `DLV-SIZE`'s after-the-fact warning remains."*
```

- [ ] **Step 11: Verify**

Run:
```bash
rtk proxy grep -cE "check_budget|card-slice-checker|card-design-checker|card-deliver-checker" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: `8` or more.

Run:
```bash
rtk proxy grep -c "reworks < 2" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: `0` (exit 1) — the old single-counter rule is gone.

Run:
```bash
rtk proxy grep -cE "checking <phase>|checks disabled" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: `3` or more (board render, header warning, report warning).

- [ ] **Step 12: Commit**

```bash
git add plugins/kanban-flow/skills/kanban/SKILL.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): orchestrator runs a checker after every producer

Extends the existing dispatch-vs-handle rule with no new machinery: phase doc
present + <phase>-check.md absent -> dispatch the checker. A failing verdict
auto-reworks that producer against its own budget; an exhausted budget parks
the card with the failing criterion ids as the blocker.

Findings with no location citation are dropped at the orchestrator, per the
contract — a checker that cannot point at a line does not get to cost the
producer a rework loop.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11b: Orchestrator — review phase, delete §6b, halve §6c

The second half: the PR flow, now that the panel runs pre-PR.

**Files:**
- Modify: `plugins/kanban-flow/skills/kanban/SKILL.md`

**Interfaces:**
- Consumes: Task 8's `card-lens-reviewer` and the `acceptance` lens.
- Produces: the review-phase panel dispatch (Section 6b becomes the lens table's home); a PR address loop with no panel logic.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -c "pr-expert-reviewer" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: `2` or more — the orchestrator still references the deleted agent.

- [ ] **Step 2: Replace §6b with the review-phase panel**

Delete the entire `### 6b. Seed the review panel (implementation PRs only, once, CI green)` section — heading, prose, lens table and all — and **move the lens table into Section 5** as a new subsection immediately after the dispatch table:

```markdown
### The review panel (status: review)

`card-implementer`'s checker is `card-tester`, then this panel. It runs on the **branch diff in the
worktree, before any PR opens** — the PR the human sees has already survived every lens.

At `status: review` with `review.md` absent, dispatch one `card-lens-reviewer` **per lens, in
parallel** (one Agent-tool message), passing each its `lens`, `worktree`, `card_id`, `card.md`,
`design.md`, `implement.md`, `test.md`, and the doctrine paths (`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md`,
`${CLAUDE_PLUGIN_ROOT}/templates/REVIEW-LENSES.md`, and `<board_dir>/PROTOCOL-ADDENDUM.md`). Lens
briefs live in the plugin's `REVIEW-LENSES.md`; each expert reads only its own section. Assemble the
panel from the branch's changed files (`git -C <worktree> diff --name-only main...HEAD`).

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

Concatenate the panel's returned phase docs into `card_dir/review.md` and commit it on the
implementation branch. Merge the lenses' **blocking** findings; any blocking finding → automatic
rework of `card-implementer` (Section 5, step 4). **On a rework re-run, re-dispatch only the lenses
that raised blocking findings** — not the whole panel. No blocking findings → advance to `deliver`.

The panel does not wait for CI: `card-tester` has already run the suite in the worktree, so the diff
reaching the panel is green by construction.
```

- [ ] **Step 3: Retitle Section 6 and delete the panel from it**

Replace the Section 6 heading and its opening line:

```markdown
## 6. PR open — CI gate, panel, review-complete addressing

A card with an open PR (design or implementation) holds its WIP slot until merged.
```

with:

```markdown
## 6. PR open — CI gate, review-complete addressing

A card with an open PR (design or implementation) holds its WIP slot until merged. The review panel
has already run (Section 5) — nothing on the PR is machine-reviewed. What remains is CI, the human's
review, and addressing what they say.
```

- [ ] **Step 4: Simplify the CI gate's forward reference**

In `### 6a. CI gate`, replace:

```markdown
Every pump, before panel or addressing, check the PR's CI: `{gh_command} pr checks <url>`.
```
with:
```markdown
Every pump, before addressing, check the PR's CI: `{gh_command} pr checks <url>`.
```

and replace:
```markdown
- **All green** → proceed to 6b/6c.
```
with:
```markdown
- **All green** → proceed to 6b.
```

- [ ] **Step 5: Rewrite §6c as §6b — the human-only address loop**

Replace the entire `### 6c. Address loop (every pump per open PR, CI green)` section with:

````markdown
### 6b. Address loop (every pump per open PR, CI green)

Nothing is actioned until the human signals the review is **complete**; then every comment they
authored is addressed. Never act before the signal.

1. **Detect the review-complete signal** — either one satisfies it:
   - a **submitted review** by a non-app user (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/reviews`) with state `COMMENTED` / `CHANGES_REQUESTED` / `APPROVED` (`PENDING` never counts); or
   - a top-level PR comment whose trimmed body equals `REVIEWED` (case-insensitive) by a non-app user (`{gh_command} api repos/{owner}/{repo}/issues/{n}/comments`).
   No signal → do nothing on this PR this pump; report "awaiting review". The pump loop is the wait.

2. **Assemble the actionable set** — every **human-authored** item the signal authorises, skipping any already carrying a `[kanban]` reply/marker (that reply is the idempotent addressed-marker):
   - **every human-authored inline comment** (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments`);
   - **each human-submitted review's summary body** when non-empty (idempotency keyed to the review id via a top-level `[kanban]` marker naming the review).
   "App" = the identity the flow posts as (its comments carry the `[kanban]` prefix or its App login); everything else is human. Exclude the `REVIEWED` comment itself. **Scope by signal:** a submitted review authorises only its own inline comments and body (one atomic unit); a `REVIEWED` comment authorises every loose inline comment (one not attached to a submitted review) created at/before its timestamp. A human comment reached by neither signal waits for one.

   *(Legacy note: an old PR may still carry `[lens]` comments from the retired post-PR panel. They are app-authored, so they are never in the actionable set. If the driver wants one addressed, they reply to it in their own voice and that reply is picked up as human-authored.)*

3. **Dispatch. Implementation PR:** dispatch `card-implementer` in PR-comment mode with the items verbatim (id, path, line, body; review-body items flagged as summary) — it fixes exactly those (test-first for behaviour), runs the fast gates, commits, pushes. **Design PR:** re-dispatch `card-designer` with the items verbatim; commit its revised `design.md` (and any superseding ADR proposals via the `adr` routing) to the design branch and push.

4. **Reply once per item** — in its thread (inline, `{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments/{id}/replies`) or as a top-level `[kanban]` comment (review body): `[kanban] Addressed in <commit-url> — <one-line explanation>`, where `<commit-url>` is the full `https://github.com/{owner}/{repo}/commit/<sha>`. For an item the agent returned in `blockers` (a question, or a change it judged wrong/infeasible), reply `[kanban] Not actioned — <reason>` and surface it to the driver. Every item in the set gets exactly one reply. **Never resolve threads**, never approve or dismiss — resolution and the merge are the human's.

These fixes are human-directed and don't consume any rework budget. Merge detection stays with Reconcile (Section 0). A healthy card needs exactly three human actions: merge the design PR, complete a review (or comment `REVIEWED`), merge the implementation PR.
````

- [ ] **Step 6: Fix the two Rules that reference the panel and 👍 triage**

In `## Rules`, replace:

```markdown
- PR comments are actioned only after a review-complete signal (a submitted review or a `REVIEWED` comment): then every human-authored comment is addressed, plus any 👍'd panel comment. The system replies `[kanban] Addressed in <commit-url>` (or `[kanban] Not actioned — <reason>`) but never resolves threads, never approves, never dismisses. Panel experts post `COMMENT` reviews only, on implementation PRs only.
```

with:

```markdown
- PR comments are actioned only after a review-complete signal (a submitted review or a `REVIEWED` comment): then every human-authored comment is addressed. The system replies `[kanban] Addressed in <commit-url>` (or `[kanban] Not actioned — <reason>`) but never resolves threads, never approves, never dismisses. **No agent comments on a PR** — the review panel runs pre-PR, against the worktree diff.
```

- [ ] **Step 7: Verify the collapse reached the orchestrator**

Run:
```bash
rtk proxy grep -rn "pr-expert-reviewer\|card-reviewer\|pr-review.md\|6c\." plugins/kanban-flow/skills/kanban/SKILL.md; echo "exit=$?"
```
Expected: no matches.

Run:
```bash
rtk proxy grep -c "card-lens-reviewer" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: `2` or more.

Run (the whole plugin should now be free of the retired names):
```bash
rtk proxy grep -rn "pr-expert-reviewer\|card-reviewer" plugins/kanban-flow/; echo "exit=$?"
```
Expected: no matches anywhere in the plugin.

- [ ] **Step 8: Commit**

```bash
git add plugins/kanban-flow/skills/kanban/SKILL.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow)!: review panel moves pre-PR; delete the 👍 triage loop

The review phase now dispatches the lens panel against the worktree diff, and
blocking findings auto-rework the implementer. Section 6b (seed the panel on
the open PR) is deleted outright; the address loop halves — no [lens] comments,
no 👍 triage, no panel/human comment partition, no pr-review.md.

What remains on a PR is CI, the human's review, and addressing what they said.
A healthy card needs three human actions: merge the design PR, complete a
review, merge the implementation PR.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Intake wiring — /refine and /requirement dispatch card-intake-checker

**Files:**
- Modify: `plugins/kanban-flow/skills/refine/SKILL.md`
- Modify: `plugins/kanban-flow/skills/requirement/SKILL.md`

**Interfaces:**
- Consumes: Task 7's `card-intake-checker`; Task 9's `check_budget.intake` and `checks.intake`.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -rc "card-intake-checker" plugins/kanban-flow/skills/refine/SKILL.md plugins/kanban-flow/skills/requirement/SKILL.md
```
Expected: `0` for both files.

- [ ] **Step 2: Add the check step to /refine**

In `skills/refine/SKILL.md`, insert a new step between step 4 (milestones) and step 5 (Present the proposal), and renumber the following steps (5→6, 6→7, 7→8):

```markdown
5. **Check the proposal before showing it to anyone.** Unless `config.md`'s `checks.intake` is `off`,
   dispatch **`card-intake-checker`** (opus) with: the proposed cards, the milestone plan, the
   existing board's cards and their milestones, the requirement(s) in scope, `spec_path`, and the
   doctrine paths (`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md`,
   `${CLAUDE_PLUGIN_ROOT}/templates/CHECK-CRITERIA.md`, `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md`,
   and `<board_dir>/PROTOCOL-ADDENDUM.md`).

   `verdict: fail` → **revise the proposal against the blocking findings and re-check**, up to
   `check_budget.intake` (default 2). Budget exhausted → present anyway, with the unresolved findings
   shown to the driver as open questions — never silently.

   `verdict: pass` → proceed. Show the driver the checker's advisory findings alongside the proposal.

   The driver's attention is the scarcest thing in this system: it should go on judgement, not on
   catching an unobservable acceptance criterion or a dependency cycle. That is what this step buys.
```

- [ ] **Step 3: Add the check step to /requirement**

In `skills/requirement/SKILL.md`, in step 5 (`**Propose — once.**`), insert immediately **before** the line `   Ask for approval, edits, or removals. Iterate until approved. **Write nothing before`:

```markdown
   **Check before you propose.** Unless `config.md`'s `checks.intake` is `off`, dispatch
   **`card-intake-checker`** (opus) with the new cards, the milestone placements, the existing board,
   the requirement, `spec_path`, and the doctrine paths (`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md`,
   `${CLAUDE_PLUGIN_ROOT}/templates/CHECK-CRITERIA.md`, `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md`,
   `<board_dir>/PROTOCOL-ADDENDUM.md`). `verdict: fail` → revise against the blocking findings and
   re-check, up to `check_budget.intake` (default 2); exhausted → present anyway with the unresolved
   findings shown as open questions. Show advisory findings alongside the proposal.

```

- [ ] **Step 4: Verify**

Run:
```bash
rtk proxy grep -c "card-intake-checker" plugins/kanban-flow/skills/refine/SKILL.md; \
rtk proxy grep -c "card-intake-checker" plugins/kanban-flow/skills/requirement/SKILL.md
```
Expected: `1` or more for each.

- [ ] **Step 5: Verify /refine's steps are still sequentially numbered after the insert**

Run:
```bash
rtk proxy grep -nE "^[0-9]+\. \*\*" plugins/kanban-flow/skills/refine/SKILL.md
```
Expected: the leading numbers read `1. 2. 3. 4. 5. 6. 7. 8.` with no repeats or gaps. Fix any misnumbering now.

- [ ] **Step 6: Commit**

```bash
git add plugins/kanban-flow/skills/refine/SKILL.md plugins/kanban-flow/skills/requirement/SKILL.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): intake skills check the proposal before the driver sees it

/refine and /requirement dispatch card-intake-checker on the proposed card set
and revise against blocking findings before presenting. The driver's attention
is the scarcest thing in the system — it should go on judgement, not on
catching an unobservable acceptance criterion or a dependency cycle.

An exhausted budget presents anyway, with the unresolved findings shown as open
questions. Never silently.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 13: /migrate — the cutover

**Files:**
- Modify: `plugins/kanban-flow/skills/migrate/SKILL.md`

**Interfaces:**
- Consumes: Task 9's config keys, Task 10's `reworks` map.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -c "reworks" plugins/kanban-flow/skills/migrate/SKILL.md
```
Expected: `0` (exit 1).

- [ ] **Step 2: Add the card-frontmatter migration step**

In `skills/migrate/SKILL.md`, insert a new step between step 5 (Template copies) and step 6 (Config), and renumber the rest (6→7, 7→8, 8→9):

```markdown
6. **Card frontmatter — the `reworks` map.** For every `docs/cards/CARD-*/card.md`, rewrite a legacy
   scalar `reworks: N` as the per-producer map:

   ```yaml
   reworks:
     slice: 0
     design: 0
     implement: N     # the old counter only ever counted test/review→implement loops
     deliver: 0
   ```

   A card with **no** `reworks` key gets the all-zero map. Also add `estimated_lines: ""` and
   `actual_lines: ""` to every card that lacks them.

   This is the **one** exception to the "never touch board state" rule below, and it is a pure shape
   change: no status, phase, dependency or content is altered, and `implement: N` preserves the exact
   budget the card had. Cards at `status: review` need no special handling — `review.md` is absent, so
   the next `/kanban` pump dispatches the new lens panel for them.
```

- [ ] **Step 3: Amend the Config step to be explicit about the new keys**

In the (now) step 7 **Config**, append to the end of the step:

```markdown
   This run adds `checks`, `check_budget`, `size_limit` and `size_exclude` (all with plugin defaults —
   every check `on`, budgets 2 except `deliver: 1`, `size_limit: 500`). **Tell the driver in the PR
   body what `size_limit` means for them:** from the next `/kanban` pump, `card-slice-checker` will
   *force a split* on any card it projects over 500 changed lines including tests. That is a real
   behaviour change on an existing backlog, and it must not arrive as a surprise.
```

- [ ] **Step 4: Amend the never-touch-board-state rule**

In `## Rules`, replace:

```markdown
- **Never touch board state** — `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`, cards, ADRs.
  Only the doctrine/template copies, `PROTOCOL-ADDENDUM.md`, and `config.md`.
```

with:

```markdown
- **Never touch board state** — `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`, ADRs, and any card's
  status, phase, dependencies or content. The doctrine/template copies, `PROTOCOL-ADDENDUM.md` and
  `config.md` are yours. **One exception:** the `reworks` frontmatter shape change in Step 6 — a
  mechanical rewrite that preserves the card's existing budget exactly and alters nothing else.
```

- [ ] **Step 5: Verify**

Run:
```bash
rtk proxy grep -cE "reworks|size_limit" plugins/kanban-flow/skills/migrate/SKILL.md
```
Expected: `4` or more.

Run:
```bash
rtk proxy grep -nE "^[0-9]+\. \*\*" plugins/kanban-flow/skills/migrate/SKILL.md
```
Expected: leading numbers read `1.` through `9.` with no repeats or gaps.

- [ ] **Step 6: Commit**

```bash
git add plugins/kanban-flow/skills/migrate/SKILL.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): /migrate cuts over reworks to the per-producer map

Rewrites a legacy scalar reworks: N as {implement: N} — the old counter only
ever counted test/review→implement loops, so the card's budget is preserved
exactly — and adds the four new config keys with plugin defaults.

The PR body must tell the driver what size_limit means for their existing
backlog: from the next pump, a card projected over 500 changed lines gets
split. That is a real behaviour change and it must not arrive as a surprise.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 14: /retro — mine the check docs, own the LOCAL- criteria

The payoff for stable criterion ids. Without this, the check layer only ever grows.

**Files:**
- Modify: `plugins/kanban-flow/skills/retro/SKILL.md`
- Modify: `plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md`

**Interfaces:**
- Consumes: Task 2's criterion ids, Task 3/6's `estimated_lines`/`actual_lines`, Task 8's `card-lens-reviewer`.

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
rtk proxy grep -c "check.md\|criterion" plugins/kanban-flow/skills/retro/SKILL.md
```
Expected: `0` (exit 1).

- [ ] **Step 2: Add check docs to the evidence gathered**

In `skills/retro/SKILL.md` §1, under **The system's trace**, replace:

```markdown
- `card.md` frontmatter metrics: `reworks`, `started` → `delivered` elapsed, phase count.
- The phase docs: `slice.md` … `deliver.md`, `pr-review.md` — especially `## Rework` sections in `implement.md`, blocking findings in `review.md`, failures in `test.md`, and `## Deviations from design`.
```

with:

```markdown
- `card.md` frontmatter metrics: `reworks` (the per-producer map — *which* producer burned loops is the signal, not the total), `started` → `delivered` elapsed, phase count, and **`estimated_lines` vs `actual_lines`**.
- The phase docs: `slice.md` … `deliver.md` — especially `## Rework` sections in `implement.md`, blocking findings in `review.md` (the lens panel's merged output), failures in `test.md`, and `## Deviations from design`.
- **The check docs — `slice-check.md`, `design-check.md`, `deliver-check.md`.** Each carries a full per-criterion verdict table with evidence. These exist to be aggregated: read every one for every covered card and tally verdicts **by criterion id**.
```

- [ ] **Step 3: Add the check-layer analysis to §2**

In §2, append these bullets to the list:

```markdown
- **Is the check layer earning its keep?** Tally every `*-check.md` verdict by criterion id across the covered cards. Three signals, three *different* remedies — do not confuse them:
  - **A criterion that never fails** across many cards is not paying for its dispatch. Propose pruning it (a `LOCAL-` one you own; a plugin one you report — see §3).
  - **A criterion that fails on most cards** means the checker is fine and the **producer** is systematically wrong. The remedy is an edit to *that producer's* prompt or the doctrine it reads — **not** more checking. Getting this backwards turns the check layer into a permanent rework tax on a defect nobody ever fixed at source. This is the single most important thing this section does.
  - **A defect that reached the human, or shipped, and no criterion caught it** → propose a new criterion, with an id, in the right section.
- **Is the slicer under-estimating?** For every done card compare `estimated_lines` (slicer, verified by `card-slice-checker`) with `actual_lines` (`card-deliver-checker`). A `DLV-SIZE` breach is *by definition* an `SLC-SIZE` estimate that was wrong. A consistent under-estimate across cards is a defect in the **slicer's** estimation method — propose a correction to its prompt, don't let every card keep paying for the miss at review time.
- **Which checker rubber-stamps?** A checker whose `evidence` for a passing criterion is thin ("looks complete") is skimming, and a skimming checker is worse than none — it manufactures confidence. The Method demands evidence of what was actually checked; hold it to that.
```

- [ ] **Step 4: Give /retro authority over LOCAL- criteria, and only those**

In §3, replace this bullet:

```markdown
- Process lessons route by scope: **project-specific** ones → append to `<board_dir>/PROTOCOL-ADDENDUM.md` (prefix `[retro-YYYY-MM-DD]`; it layers on the plugin's shared doctrine for this repo only). **Universal** ones — anything that belongs in the plugin's `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, templates, agents, or skills — must **not** be edited in place: describe the exact change and flag it as a **plugin PR** in the retro output for the human to raise against the plugin repo. The `BOARD.md` header tunables (WIP limit, gate policy) remain editable in-repo.
```

with:

```markdown
- Process lessons route by scope: **project-specific** ones → append to `<board_dir>/PROTOCOL-ADDENDUM.md` (prefix `[retro-YYYY-MM-DD]`; it layers on the plugin's shared doctrine for this repo only). **Universal** ones — anything that belongs in the plugin's `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `CHECK-CRITERIA.md`, templates, agents, or skills — must **not** be edited in place: describe the exact change and flag it as a **plugin PR** in the retro output for the human to raise against the plugin repo. The `BOARD.md` header tunables (WIP limit, gate policy) remain editable in-repo.
- **Check criteria — your authority is bounded, exactly as every other agent's is.** You may add, edit and prune **`LOCAL-`** criteria in `<board_dir>/PROTOCOL-ADDENDUM.md` under a `## Check criteria — <target>` heading (`target` ∈ `intake | slice | design | deliver`), shipped in your PR like any other in-repo change. Give each a stable `LOCAL-` id and never reuse one. For a **plugin** criterion you may only *report*: "`DSG-KNOWLEDGE` has passed on 20 consecutive cards — consider raising it upstream", or "`SLC-NO-LOSS` failed on 6 of the last 8 splits — the slicer's prompt is the problem, not the check." The driver decides whether that becomes a plugin change. You never edit plugin doctrine, just as no phase agent edits `BOARD.md`.
```

- [ ] **Step 5: Update §2's stale references to the retired agents**

In §2, replace:

```markdown
- **What did the human catch that the system missed?** Every human-authored PR comment maps to a lane: inside a panel lens's lane → extend that lens's Walk/Red flags with the missed pattern; inside the card-reviewer's remit → strengthen its "where bugs hide" list; a design objection surfacing at PR time → the design gate policy or designer prompt let it through too late. A comment the orchestrator replied `Not actioned` to is doubly telling — the machine both missed it upstream and could not fix it on request.
- **Where did the human correct the machine?** Panel comments rebutted in replies or consistently never 👍'd → tighten that lens's Don't flag / calibration. Machine findings the human 👍'd instantly → patterns to teach *earlier* phases so they never reach the PR.
```

with:

```markdown
- **What did the human catch that the system missed?** This is now the sharpest signal on the board: the lens panel runs **before** the PR, so **every human PR comment is something the whole panel and three checkers all missed.** Map each to a lane — inside a lens's remit → extend that lens's Walk/Red flags with the missed pattern; inside a checker's remit → propose a criterion (`LOCAL-`, or report a plugin one); a design objection surfacing at PR time → the design check or the designer's prompt let it through too late. A comment the orchestrator replied `Not actioned` to is doubly telling — the machine both missed it upstream and could not fix it on request.
```

Then replace the **Panel signal** bullet:

```markdown
- **Panel signal:** per lens in `pr-review.md`, how many findings, and how many earned the human's 👍? A lens whose findings keep getting actioned points at an upstream phase to strengthen (e.g. recurring `[tests]` 👍s → teach the designer's test strategy); a lens that never does may need a sharper brief in `REVIEW-LENSES.md` — or retirement.
```

with:

```markdown
- **Panel signal:** per lens in `review.md`, how many **blocking** findings, and did they hold up (did the implementer's rework actually fix something, or push back)? A lens whose blocking findings keep landing points at an upstream phase to strengthen (recurring `[tests]` blockers → teach the designer's test strategy). A lens that never finds anything blocking across many cards may need a sharper brief in `REVIEW-LENSES.md` — or retirement. A lens whose findings the implementer keeps rebutting is miscalibrated: tighten its **Don't flag**.
```

- [ ] **Step 6: Add the criteria heading to the addendum template**

In `templates/PROTOCOL-ADDENDUM.md`, replace:

```markdown
`/retro` appends project-specific process lessons here, each prefixed
`[retro-YYYY-MM-DD]`. Universal lessons belong in the plugin instead — `/retro`
flags those as a plugin PR rather than writing them here.

<!-- No project-specific rules yet. -->
```

with:

```markdown
`/retro` appends project-specific process lessons here, each prefixed
`[retro-YYYY-MM-DD]`. Universal lessons belong in the plugin instead — `/retro`
flags those as a plugin PR rather than writing them here.

<!-- No project-specific rules yet. -->

## Check criteria

Project-specific check criteria, layered on top of the plugin's `CHECK-CRITERIA.md`.
Each checker reads its own target's section here in addition to the plugin's.

Criteria here carry a **`LOCAL-`** id prefix so they never collide with a plugin id
and `/retro` can tell which set a verdict came from. Ids are stable and permanent —
never renamed, never reused. `/retro` owns this section; it may add, edit and prune
`LOCAL-` criteria, but never touches the plugin's.

Add a `## Check criteria — <target>` subsection (`target` ∈ `intake` | `slice` |
`design` | `deliver`) when a lesson earns one. Format matches the plugin file: a
table of `| id | criterion | severity when failed |`.

<!-- No project-specific criteria yet. -->
```

- [ ] **Step 7: Verify**

Run:
```bash
rtk proxy grep -c "LOCAL-" plugins/kanban-flow/skills/retro/SKILL.md; \
rtk proxy grep -c "LOCAL-" plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md; \
rtk proxy grep -rn "pr-review.md\|👍" plugins/kanban-flow/skills/retro/SKILL.md; echo "exit=$?"
```
Expected: `2` or more, `2` or more, then **no matches** for the third (the 👍 apparatus and `pr-review.md` are gone from `/retro` too).

Note: `/retro`'s §1 "human's trace" and its Rules still mention 👍 in a few places. **Remove every remaining 👍 / `pr-review.md` reference in this file** — the triage mechanism no longer exists. Re-run the third command until it returns no matches.

- [ ] **Step 8: Commit**

```bash
git add plugins/kanban-flow/skills/retro/SKILL.md plugins/kanban-flow/templates/PROTOCOL-ADDENDUM.md
git commit -m "$(cat <<'EOF'
feat(kanban-flow): /retro mines the check docs and owns LOCAL- criteria

Aggregates every *-check.md verdict by criterion id and routes the three
signals to three different remedies. The one that matters: a criterion that
fails on most cards means the PRODUCER is wrong, and the fix goes in the
producer's prompt — not in more checking. Getting that backwards turns the
check layer into a permanent rework tax on a defect nobody ever fixes.

Also mines estimated_lines vs actual_lines to catch a slicer that
systematically under-estimates, and drops the retired 👍/pr-review.md
apparatus. With the panel now pre-PR, every human PR comment is something the
whole panel and three checkers all missed — the sharpest signal on the board.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 15: Version bump and README

**Files:**
- Modify: `plugins/kanban-flow/.claude-plugin/plugin.json`
- Modify: `plugins/kanban-flow/README.md`

**Interfaces:**
- Consumes: nothing. `/kanban` compares `config.md`'s `kanban_flow_version` to this version to nudge `/migrate` (Task 13).

- [ ] **Step 1: Write the failing assertion**

Run:
```bash
jq -r .version plugins/kanban-flow/.claude-plugin/plugin.json
```
Expected: `0.3.0`.

- [ ] **Step 2: Bump the version and update the description**

Edit `plugins/kanban-flow/.claude-plugin/plugin.json` to:

```json
{
  "name": "kanban-flow",
  "description": "Autonomous, card-driven kanban development: an orchestrator, specialist agents, and a checker for every one of them that verifies its work against stable, auditable criteria. Runs each backlog card through slice → design → implement → test → review, holds it under a hard changed-lines budget, and ships design and implementation as two reviewable PRs.",
  "version": "0.4.0",
  "author": { "name": "Steve Bennett" },
  "license": "MIT",
  "keywords": ["kanban", "orchestration", "agents", "tdd", "code-review", "workflow"]
}
```

- [ ] **Step 3: Verify the JSON parses and the version is right**

Run:
```bash
jq -e '.version == "0.4.0"' plugins/kanban-flow/.claude-plugin/plugin.json
```
Expected: `true` (exit 0). A malformed JSON manifest makes the plugin undiscoverable, so this must pass.

- [ ] **Step 4: Update the README**

In `plugins/kanban-flow/README.md`, replace the `- **Agents:**` line under `## Contents` with:

```markdown
- **Agents — producers:** `card-slicer`, `card-designer`, `card-implementer`, `card-deliverer`.
- **Agents — checkers:** `card-intake-checker`, `card-slice-checker`, `card-design-checker`, `card-deliver-checker`, plus `card-tester` and the `card-lens-reviewer` panel (together, the implementer's checkers). **Checkers are terminal — nothing checks a checker.** That is what stops the regress; the human is their backstop, at the intake and slice gates and at the two PR merges.
```

Then replace the `- **Templates:**` line's parenthetical list `(`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `INTAKE.md` — the card doctrine shared by `refine` and `requirement` — and the card/PR templates)` with:

```markdown
(`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `CHECK-CRITERIA.md`, `INTAKE.md` — the card doctrine shared by `refine` and `requirement` — and the card/PR templates)
```

Then insert this section immediately **before** `## Upgrading an existing repo`:

````markdown
## Every agent is checked

Each agent that **produces** something has a **checker** that verifies it, and checkers are
**terminal** — nothing checks a checker. Checkers write nothing and mutate nothing; they return a
verdict, and the orchestrator persists it and runs the rework loop.

What makes a check more than a rubber stamp: criteria live in the plugin's `CHECK-CRITERIA.md` with
**stable ids**, a checker must return a verdict for **every** criterion with an evidence citation,
and **a finding that cannot point at a line is invalid and gets dropped**. `/retro` aggregates
verdicts by id — a criterion that never fires gets pruned, and one that fires constantly means the
**producer** is wrong and *its* prompt gets fixed, not the check.

Blocking findings automatically rework the producer, against a per-producer budget
(`check_budget` in `config.md`). Checks are on by default; `checks` can turn one off if it proves
noisy, and `/kanban` then warns loudly, every pump, about what is shipping unchecked.

### The size budget

`size_limit` (default **500** changed lines, **including tests**; only lock files and vendored deps
are excluded via `size_exclude`) is the hard ceiling on a card, enforced twice:

- **`SLC-SIZE`, at slice — blocking.** `card-slice-checker` independently estimates the card's size
  from the codebase before any code is written. Over the limit **forces a split**, however atomic the
  card felt. This makes `size_limit` the real ceiling on card size, tighter than any "is this a
  vertical slice?" judgement call.
- **`DLV-SIZE`, at deliver — advisory, escalated.** `card-deliver-checker` measures the real diff. A
  breach cannot block (the code is written), but it **must propose a concrete split into smaller
  PRs**, which `/kanban` surfaces for you to act on.

A `DLV-SIZE` breach is, by definition, an `SLC-SIZE` estimate that was wrong — so every card records
`estimated_lines` and `actual_lines`, and `/retro` reads the delta to catch a slicer that
systematically under-estimates.

### Review happens before the PR

The lens panel (`card-lens-reviewer`, one agent per lens, in parallel) reviews the branch diff at the
**review** phase, in the worktree, **before any PR opens** — and blocking findings automatically
rework the implementer. The PR you open has already survived every lens.

No agent comments on a PR. `card-deliverer` is the only one that touches GitHub at all, and only to
push the branch and open the PR. On the PR you review normally: signal review-complete (submit a
review, or comment `REVIEWED`), and every comment you wrote gets addressed and answered with a commit
link. A healthy card needs exactly three actions from you: merge the design PR, complete a review,
merge the implementation PR.
````

- [ ] **Step 5: Verify the README covers the behaviour change**

Run:
```bash
rtk proxy grep -cE "size_limit|checker|/migrate" plugins/kanban-flow/README.md
```
Expected: `3` or more.

- [ ] **Step 6: Commit**

```bash
git add plugins/kanban-flow/.claude-plugin/plugin.json plugins/kanban-flow/README.md
git commit -m "$(cat <<'EOF'
chore(kanban-flow): bump to 0.4.0, document the checker layer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 16: Whole-plugin consistency check and end-to-end exercise

The plugin has no test runner, so this is where it actually gets validated — per `CLAUDE.md`, by installing it and exercising it. **Do not skip this task.** Every prior task's assertions were local; this is the only one that catches a cross-file contradiction.

**Files:**
- Modify: any file the checks below reveal as inconsistent.

- [ ] **Step 1: No dangling references to deleted or renamed agents**

Run:
```bash
rtk proxy grep -rn "pr-expert-reviewer\|card-reviewer\|pr-review.md" plugins/kanban-flow/ docs/; echo "exit=$?"
```
Expected: matches **only** in `docs/superpowers/specs/` and `docs/superpowers/plans/` (which describe the change). Any match under `plugins/` is a bug — fix it.

- [ ] **Step 2: Every agent named in the orchestrator's dispatch table exists**

Run:
```bash
for a in card-slicer card-slice-checker card-designer card-design-checker \
         card-implementer card-tester card-lens-reviewer card-deliverer \
         card-deliver-checker card-intake-checker; do
  test -f "plugins/kanban-flow/agents/$a.md" || echo "MISSING: $a"
done; echo done
```
Expected: `done` with no `MISSING` lines.

- [ ] **Step 3: Every agent's `name:` frontmatter matches its filename**

Run:
```bash
for f in plugins/kanban-flow/agents/*.md; do
  n=$(rtk proxy grep -m1 '^name:' "$f" | sed 's/^name: *//')
  b=$(basename "$f" .md)
  [ "$n" = "$b" ] || echo "MISMATCH: $f has name: $n"
done; echo done
```
Expected: `done` with no `MISMATCH` lines. A mismatch means Claude Code cannot resolve the agent.

- [ ] **Step 4: Every criterion id in CHECK-CRITERIA is referenced by exactly one checker**

Run:
```bash
rtk proxy grep -oE '^\| `(INT|SLC|DSG|DLV)-[A-Z-]+`' plugins/kanban-flow/templates/CHECK-CRITERIA.md \
  | sed 's/[|` ]//g' | sort -u | wc -l
```
Expected: `27`. If this drifted from Task 2, the doctrine has been edited inconsistently — reconcile it.

- [ ] **Step 5: No doctrine file tells an agent to write a `docs/cards/` copy**

Run:
```bash
rtk proxy grep -rn "docs/cards/AGENT-PROTOCOL\|docs/cards/CHECK-CRITERIA\|docs/cards/REVIEW-LENSES" plugins/kanban-flow/; echo "exit=$?"
```
Expected: no matches. Doctrine is plugin-owned and read live; a copied doctrine file is the exact bug `/migrate` exists to undo.

- [ ] **Step 6: The plugin manifest and marketplace manifest both parse**

Run:
```bash
jq -e . plugins/kanban-flow/.claude-plugin/plugin.json > /dev/null && echo PLUGIN_OK
jq -e . .claude-plugin/marketplace.json > /dev/null && echo MARKETPLACE_OK
```
Expected: `PLUGIN_OK`, `MARKETPLACE_OK`.

- [ ] **Step 7: Exercise the plugin for real**

This is the actual validation. In a scratch directory **outside this repo**:

```bash
mkdir -p /private/tmp/claude-501/-Users-stevebennett-Code-nyx-claude/*/scratchpad/kanban-e2e
```

Then, in a Claude Code session with the plugin installed from this branch:
1. `/kanban-init` in the scratch repo — confirm `config.md` carries `checks`, `check_budget`, `size_limit`, `size_exclude`, and that **no** `AGENT-PROTOCOL.md`, `CHECK-CRITERIA.md` or `REVIEW-LENSES.md` copy is written into `docs/cards/`.
2. Write a two-requirement spec and run `/refine` — confirm `card-intake-checker` is dispatched **before** the proposal is shown, and that its verdict table appears alongside the cards.
3. Deliberately give one card an unobservable acceptance criterion ("the system is robust"). Confirm the intake checker fails `INT-AC-OBSERVABLE` and `/refine` revises before presenting.
4. Run `/kanban` and confirm: the slicer runs, then `card-slice-checker`, and the check's `estimated_lines` lands on the card.
5. Deliberately add a card whose scope obviously exceeds 500 lines. Confirm `SLC-SIZE` fails **blocking** and the card is **split**, not merely warned about.
6. Confirm at `status: review` that the **lens panel** is dispatched (including `acceptance`) against the worktree diff, that **no `[lens]` comment is posted to GitHub**, and that a blocking finding reworks the implementer.

Record what you observed. If any step diverges from the spec, fix the plugin — do not adjust the expectation.

- [ ] **Step 8: Commit any fixes**

```bash
git add -A plugins/kanban-flow
git commit -m "$(cat <<'EOF'
fix(kanban-flow): consistency fixes from the end-to-end pass

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
EOF
)"
```

(If Step 7 found nothing to fix, skip this commit — do not manufacture one.)

- [ ] **Step 9: Open the PR**

```bash
git push -u origin feat/kanban-checker-agents
gh pr create --base main --title "feat(kanban-flow): a checker for every agent, and a 500-line size budget" --body "$(cat <<'EOF'
## What

Every agent in kanban-flow is now classified as a **producer** (creates artifacts, can be wrong) or a **checker** (verifies, and is **terminal** — nothing checks a checker, which is what stops the regress).

Four new checkers — `card-intake-checker`, `card-slice-checker`, `card-design-checker`, `card-deliver-checker` — cover the phases that shipped unverified. `card-tester` and the lens panel are re-declared as `card-implementer`'s checkers, which they already were in everything but name.

## What makes it more than ceremony

A new `CHECK-CRITERIA.md` doctrine with **stable criterion ids**. Each checker must return a verdict for *every* criterion with an evidence citation, and **a finding with no location is invalid and dropped** — so a checker that wants to look useful by inventing findings has to point at a line. `/retro` aggregates verdicts by id, and when a criterion fails constantly it fixes the **producer**, not the check.

## The 500-line size budget

Enforced twice. `SLC-SIZE` (blocking) has `card-slice-checker` independently estimate a card's changed lines before any code is written; over `size_limit` **forces a split**. `DLV-SIZE` (advisory) measures the real diff and must propose a concrete split into smaller PRs. Tests count; only lock files and vendored deps are excluded.

## Breaking: the review panel moves pre-PR

`card-reviewer` and the `pr-expert-reviewer` panel reviewed the same diff twice. They collapse: the panel (renamed `card-lens-reviewer`, plus a new `acceptance` lens) now runs at the **review** phase against the worktree diff, and blocking findings **auto-rework the implementer** instead of waiting on a review-complete signal and per-comment 👍 triage.

Consequences: orchestrator §6b deleted, §6c halved, and `AGENT-PROTOCOL`'s "GitHub is off-limits, with two exceptions" becomes **one** — `card-deliverer`. The PR you open has already survived every lens.

## Existing repos

Run **`/migrate`**: it rewrites `reworks: N` → `{implement: N}` and adds the four config keys. Note the behaviour change it brings — from the next pump, a card projected over 500 lines gets split.

## Spec & plan

- `docs/superpowers/specs/2026-07-13-kanban-checker-agents-design.md`
- `docs/superpowers/plans/2026-07-13-kanban-checker-agents.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)

https://claude.ai/code/session_01ETP9j4amgkoPuRsDV2Bb2u
EOF
)"
```

---

## Appendix: what this plan deliberately does not do

- **No checker for any checker.** Terminal, by design. If a future task proposes one, it is wrong.
- **No test framework.** This repo validates plugin components by structural assertion and by exercising the plugin (`CLAUDE.md`). Introducing one is a separate decision with its own spec.
- **No `implement` entry in `checks`.** The implementer's checkers are `card-tester` and the lens panel; an off switch there would silently skip running the test suite.
- **No multi-vote checker panels.** One checker per producer, except the implementer, whose lens panel already gives diverse perspectives.
- **`/retro` does not open PRs against the plugin repo.** It reports universal lessons; the driver ports them.
