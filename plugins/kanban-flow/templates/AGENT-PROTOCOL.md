# Phase Agent Protocol

Every `card-*` phase agent MUST follow this protocol. It is the shared contract between the
`/kanban` orchestrator and the phase agents.

## On dispatch you receive
- `card_id` (e.g. CARD-001), `card_dir` (e.g. docs/cards/CARD-001-slug), `worktree` (absolute path
  to this card's git worktree), the full text of `card.md`, and the prior phase docs **your phase
  needs** (the orchestrator sends only those — don't expect all of them).
- **Doctrine paths:** the absolute path to the plugin's `AGENT-PROTOCOL.md` (this file) and the
  repo's `PROTOCOL-ADDENDUM.md`; `card-lens-reviewer` also receives the plugin's `REVIEW-LENSES.md`
  path. Read the protocol here, then layer the addendum — never read a `docs/cards/` copy.
- Exception: the **slice** phase runs before any worktree exists, so `card-slicer` receives no
  `worktree`; it instead receives the card's current **dependents** (ids that `depends_on` it).
- A **rework** dispatch (implement phase only) additionally carries the blocking findings from the
  tester, the reviewer, or a failing CI run (job + log excerpt); fix exactly those, and push the
  branch when the dispatch notes the PR is already open.
- A **PR-comment** dispatch (implement phase: implementation-PR comments; design phase:
  design-PR comments) carries the review-complete comment set (id, path, line, body; review-body
  items flagged as summary) — every human-authored comment plus any 👍'd panel comment; address
  exactly those and never touch the comment threads — the orchestrator replies (with a commit link)
  and the human resolves.
- A **review** dispatch (`card-lens-reviewer`, one per lens, in parallel, at the review phase) carries
  a `lens` and reviews the branch diff in the `worktree` — before any PR exists.
- A **check** dispatch (a `card-*-checker`) carries the producer's inputs and its output artifact, and
  the plugin's `CHECK-CRITERIA.md` path. See the Checker contract below.
- A **deliver** dispatch names its mode: `design` (push the docs+ADRs branch, open the design PR)
  or `implementation` (rebase, confirm green, push, open the implementation PR).

## Always, before doing anything
1. Read `docs/cards/KNOWLEDGE.md` in full.
2. Read `card.md` and the phase docs you were given.
3. Read the spec **selectively**: slice and design read whatever they need to judge/design; every
   later phase reads only the sections `design.md` cites under `## Spec references`. Never re-read
   the whole spec when the design already names its sources.

## Boundaries (sole-writer invariant)
- You MUST NOT write or edit `BOARD.md`, `KNOWLEDGE.md`, or any `card.md`. The orchestrator owns them.
- You MUST NOT write your phase doc to disk. You RETURN its full markdown as `phase_doc` (below);
  the orchestrator persists it **on the card's current branch** — slice/design docs and ADRs ride
  the **design PR**; implement/test/review docs ride the **implementation PR**. The design PR
  merges before the implementation branch is cut, so merged designs and ADRs are on `main` for
  every later card to build on.
- You MAY create and edit **code** files — but only inside `worktree` (use absolute paths under it).
  The slice and design phases produce no code; a design branch is docs-only.
- **GitHub is off-limits to phase agents, with exactly one exception:** the deliver phase pushes the
  branch and opens the PR. Nothing else. The review panel runs **before** the PR opens, against the
  branch diff in the worktree, and returns findings to the orchestrator — it does not comment on
  GitHub. `card-deliver-checker` reads the PR (`gh pr view`, `gh pr checks`) but mutates nothing. No
  agent ever comments, approves, requests changes, replies to, resolves, or reacts to a PR thread —
  the review-complete signal and thread resolution belong to the human, and the orchestrator alone
  replies with commit links.

## Doctrine (expertise every agent carries)
Distilled from expert review of this codebase and domain — treat these as standing knowledge:
- **The spec outranks your training.** Its stated acceptance criteria are binding. When plausible
  domain knowledge from memory disagrees with the project spec (`spec_path` in `config.md`), the
  spec wins — check it, don't recall it.
- **Numeric precision is a common landmine.** Binary floats and language-default rounding introduce
  representation error (a value meant to be exactly x.5 may be stored as x.4999…), so where the spec
  defines exact rounding or exact-decimal arithmetic, use the project's designated decimal/rounding
  primitive — never a language default (e.g. Python's banker's `round()`) or binary `float` — and
  never compare such values with float tolerance.
- **Parallel derived values, never blended.** When the spec defines two related but distinct
  computed quantities for different purposes (e.g. a raw measure that drives one calculation and
  an adjusted/weighted variant that drives another), using one where the other belongs is a
  blocking defect. Name which one you mean, every time.
- **As-of semantics.** Per-record figures use the values in effect on that record's date, from the
  snapshot stored on the record — not today's values, not the current reference data. Replay is
  chronological; ties (same-date records) need a deterministic order (date, then id).
- **Determinism everywhere.** Fixed clock, fixed seed data, ordered queries, no network in tests.
  A flaky test is a failing test — never re-run it to green.
- **Evidence over claims.** Paste the command and real output; never report a result you did not
  observe. Smallest change that satisfies the acceptance criteria; reuse before writing new (YAGNI).

## Your structured return (your final message — nothing else)
Emit exactly one fenced ```result block, valid YAML:

```result
status: complete            # complete | blocked | needs-input
phase: <slice|design|implement|test|review|deliver|check>
card: CARD-NNN
gate: none                  # none | design | slice  (which gate this phase triggers; never "deliver")
summary:
  - "2–4 bullets a human reads at the gate or in the board"
open_questions:             # required when status is needs-input; else []
  - "Blocking question for the driver"
blockers:                   # required when status is blocked; else []
  - "What is broken and the evidence (command + output excerpt)"
knowledge:                  # may be empty — but if your phase hit a trap or set a convention, record it; an empty KNOWLEDGE.md after many cards is a process failure
  - scope: repo             # repo | personal
    section: Conventions    # Conventions | Gotchas | Glossary  (repo scope only; significant decisions are ADRs, below)
    entry: "Fact to record, prefixed mentally with [CARD-NNN]"
proposed_adrs:              # may be empty — significant architecture/technology decisions only
  - title: "Short decision title"
    context: "The forces at play"
    decision: "What we decided"
    consequences: "What becomes easier/harder"
    supersedes: []          # optional ADR ids this decision replaces, e.g. [ADR-0003]
proposed_cards:             # SLICE PHASE ONLY, with gate: slice — the child cards to create; else omit/[]
  - title: "Short imperative title"
    type: feature           # feature | task | defect
    layer: domain           # one of the project's configured layers (see config.md `layers`)
    why: "One line of user-facing intent"
    acceptance_criteria:
      - "Observable, testable criterion"
    depends_on: []          # sibling child titles and/or existing CARD ids
dependents_rewire:          # SLICE PHASE ONLY — for each existing card that depends_on the parent
  - card: CARD-NNN
    new_depends_on: []      # what it should depend on after the split replaces the parent
phase_doc: |
  <full markdown body of this phase's doc — the orchestrator writes it to card_dir/<phase>.md>
```

- `status: needs-input` → orchestrator surfaces `open_questions` to the driver and re-dispatches you with answers.
- `status: blocked` from the **tester or reviewer** with actionable findings → orchestrator auto-re-dispatches the implementer in rework mode (budget: 2 loops), then parks the card.
- `status: blocked` from any other phase → orchestrator parks the card with `blockers` shown on the board.
- `status: complete` + `gate: slice` (slice phase only) → orchestrator applies the gate policy: auto-apply the split, or surface `proposed_cards` + `dependents_rewire` to the driver.
- `status: complete` + `gate: design` → orchestrator applies the gate policy: auto-approve, or stop for the driver (domain-layer cards by default).
- The deliver gate is triggered by a card reaching `deliver` status, not by any agent `gate` value. No agent should ever emit `gate: deliver`.

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

**Two kinds of checker.** The table names a *role*, not a return format. `card-tester` and the lens
panel check the implementer by running the suite and reviewing the diff, and they keep their own
existing contract (`status: blocked` + `blockers`). The **result fields below bind only the four
dedicated `card-*-checker` agents** — `card-intake-checker`, `card-slice-checker`,
`card-design-checker`, `card-deliver-checker` — which is why `checks` takes one of
`intake | slice | design | deliver` and no `implement` value exists. Everything *else* in this
section — independence, evidence over adjectives, and the terminal rule — binds every checker in the
table.

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

## Architecture Decision Records (ADRs)

Significant **architecture or technology decisions** (framework/library choices, data-model
invariants, cross-cutting patterns, expensive-to-reverse trade-offs) are recorded as ADRs in
`docs/adrs/` (Cognitect format: Title · Context · Decision · Status · Consequences), not in
`KNOWLEDGE.md`. Small conventions → `KNOWLEDGE.md ## Conventions`; traps → `## Gotchas`.
- Any phase agent MAY return `proposed_adrs` when it makes or surfaces such a decision. You only
  *propose*: the orchestrator persists each ADR (numbering, file, index, `adrs:` card link) via
  the `adr` skill. Design-phase ADRs are written once the design gate passes (auto or approved).
- Read `docs/adrs/README.md`'s index before proposing — to reverse an earlier decision, propose a
  new ADR with `supersedes: [ADR-NNNN]`; never propose a duplicate of a standing one.
