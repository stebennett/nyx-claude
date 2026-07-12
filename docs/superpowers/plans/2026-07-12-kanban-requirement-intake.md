# `/requirement` + `req-ids` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two skills to `plugins/kanban-flow` — `/requirement` (elicit a requirement, write it to the spec, slice it into cards, and apply its impact on the board) and `req-ids` (the single authority for REQ identity) — plus the shared intake doctrine and the `/kanban` changes they depend on.

**Architecture:** `req-ids` owns requirement identity in `spec_path` (heading format, numbering, supersede markers), mirroring how the existing `adr` skill owns ADR identity. `templates/INTAKE.md` holds the card-slicing doctrine shared by `/refine` and `/requirement`, read live from the plugin. `/requirement` may edit `backlog` cards directly, but for cards already in flight it appends to an amendment queue (`AMENDMENTS.md`) that `/kanban` drains on its next pump — preserving `/kanban`'s sole-writer invariant over in-flight `card.md`.

**Tech Stack:** Markdown only. Claude Code plugin components (`skills/<name>/SKILL.md`, `templates/*.md`), discovered by convention.

## Global Constraints

- **There is no test runner in this repo** (`CLAUDE.md`: "No build/test tooling exists yet"). Every deliverable here is Markdown doctrine read by a model at runtime. There is therefore **no red-green TDD cycle to write**. Each task instead ends with (a) concrete structural checks you actually run, and (b) a read-through against the spec. Task 8 is the real end-to-end exercise. Do not fabricate a test framework for this.
- **Plugin-owned doctrine is never copied into a consuming repo.** New templates are read live via `${CLAUDE_PLUGIN_ROOT}/templates/`. Do not add them to `/kanban-init`'s copy list.
- **Skills take no `model` frontmatter field.** The convention in this plugin is the literal phrase `Run under Opus.` at the end of the `description`.
- Conventional Commits. Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```
- Spec: `docs/superpowers/specs/2026-07-12-kanban-add-requirement-design.md`. Read it before Task 1.
- Card id format `CARD-NNN` (3 digits). Requirement id format `REQ-NNN` (3 digits). ADR id format `ADR-NNNN` (4 digits) — do not confuse them.
- RTK rewrites `grep`/`cat`/`git`. If a check command below rejects a flag, re-run it as `rtk proxy <command>`.

---

### Task 1: Card template — `reqs` field and `superseded` status

The shared contract every later task consumes. Do this first so `/refine`, `/requirement`, and `/kanban` all refer to fields that exist.

**Files:**
- Modify: `plugins/kanban-flow/templates/card-template.md`

**Interfaces:**
- Consumes: nothing.
- Produces: the frontmatter key `reqs: []` (list of `REQ-NNN` strings) and the status enum value `superseded`. Tasks 3–6 all depend on both.

- [ ] **Step 1: Add `reqs` to the frontmatter**

In `plugins/kanban-flow/templates/card-template.md`, insert a new line immediately after the `layer:` line:

```yaml
reqs: []              # REQ ids this card implements, e.g. [REQ-012]. Empty = unknown (a card written before this field), NOT "unaffected".
```

- [ ] **Step 2: Add `superseded` to the status enum**

Replace the `status:` line's comment:

```yaml
status: backlog       # backlog | slice | design | implement | test | review | deliver | done | blocked | split | superseded
```

Replace the `phase:` line's comment the same way if it enumerates statuses; if it only says `mirrors status`, leave it.

- [ ] **Step 3: Document the terminal status in the Notes section**

In the `## Notes` paragraph at the bottom, after the sentence about split lineage, add:

```markdown
A `superseded` card is terminal: `/requirement` retired it because the requirement it implemented was superseded. The reason is recorded here.
```

- [ ] **Step 4: Verify both fields are present**

Run:
```bash
rtk proxy grep -n "reqs:\|superseded" plugins/kanban-flow/templates/card-template.md
```
Expected: at least three matching lines — the `reqs:` frontmatter key, the `status:` enum comment containing `superseded`, and the `## Notes` sentence.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/templates/card-template.md
git commit -m "feat(kanban-flow): add reqs field and superseded status to card template

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: The `req-ids` skill — sole authority for REQ identity

**Files:**
- Create: `plugins/kanban-flow/skills/req-ids/SKILL.md`

**Interfaces:**
- Consumes: `config.md`'s `spec_path`.
- Produces: three named operations that Tasks 4 and 5 invoke by name — **`backfill`** (id an un-id'd spec; idempotent no-op otherwise), **`allocate`** (insert a new requirement under the next free id; returns the id), **`supersede`** (mark old REQ ids superseded by a new one). Also produces the canonical spec heading format that `/refine` and `/requirement` cite.

- [ ] **Step 1: Create the skill file**

Create `plugins/kanban-flow/skills/req-ids/SKILL.md` with exactly this content:

````markdown
---
name: req-ids
description: Assign and maintain stable REQ-NNN ids in a project's spec. The single authority for the REQ heading format, id allocation, and supersede markers. Invoked by /refine (first pass) and /requirement; may also be run directly. Idempotent. Run under Opus.
---

# req-ids — the spec's requirement identity

You hold **sole-writer authority for requirement identity** in the project spec
(`spec_path` in `{board_dir}/config.md`): the heading format, the numbers, and the
`**Status:**` lines. You are to the spec what the `adr` skill is to `docs/adrs/`.

Your callers — `/refine` and `/requirement` — compose requirement **prose**. You
persist it with correct **identity**. You never author, reword, or delete requirement
content.

## The format

A requirement is an addressable heading in the spec:

```markdown
## Boards

### REQ-012 — Export a board to CSV
**Status:** active

Users with read access can export a board to CSV, one row per card, including
the card's id, title, status and milestone.
```

- **Id** — `REQ-NNN`, zero-padded to three digits, unique across the spec, allocated
  in ascending order, **never reused and never renumbered**.
- **`**Status:**`** — exactly `active` or `superseded by REQ-NNN`.
- **`## <Area>`** — a free-form grouping heading. Requirements live under one.
- **Non-normative prose** — overview, goals, glossary, architecture notes,
  background — is **not** a requirement. It gets no id and you leave it untouched.

## Operations

The caller names exactly one operation.

### `backfill` — id an un-id'd spec

Run this before any other work touches the spec. `/refine` calls it on its first
pass; `/requirement` calls it before it does anything else.

1. Read the spec at `spec_path`.
2. **If every requirement-bearing section already carries a `### REQ-NNN — ` heading,
   report `already-id'd` and stop.** This is the common case and it is a **no-op** —
   write nothing, ask nothing.
3. Otherwise, identify the discrete requirements in the existing prose. A requirement
   is a statement of something the system must do that is observable and independently
   checkable. Exclude non-normative prose (above).
4. Where one paragraph bundles several requirements, split it into separate REQs.
   **Preserve the author's wording verbatim** — reuse their sentences unchanged and add
   only the `### REQ-NNN — <title>` heading and the `**Status:** active` line. Err
   toward keeping the author's structure; you are numbering their spec, not rewriting it.
5. Number in document order, starting at `REQ-001`.
6. **Present the full diff** and the count (`n requirements identified`). Ask the driver
   to `approve` or `revise`. **Never write without approval.**
7. On approval, write the spec. Return the map of `REQ id → title` to the caller.

### `allocate` — add a new requirement

The caller passes a **title**, the requirement **prose**, and the **area** (an existing
`## <Area>` heading, or a new one to create).

1. `NNN = max(every REQ id in the spec) + 1`, zero-padded to three digits. Take the max
   across **all** requirements including superseded ones — ids are never reused.
2. Insert the requirement at the end of the named area's requirements. If the area does
   not exist, append the `## <Area>` heading at the end of the spec's requirement
   sections and put it there.
3. Write it in the canonical format with `**Status:** active`.
4. **Return the allocated id** to the caller — it needs it for the cards' `reqs` field.

### `supersede` — retire a requirement

The caller passes one or more **old ids** and the **new id** replacing them.

1. For each old id, set its status line to `**Status:** superseded by REQ-NNN`.
2. **Never delete the requirement and never edit its prose.** It stays exactly where it
   is. History is the point: cards that cited it still resolve.
3. **Refuse** and report the conflict to the caller (do not guess) if an old id does not
   exist, or is already `superseded by` a **different** id. The caller decides.
4. Return the list of ids you changed.

## Rules

- You write files; **you never commit**. The invoking skill owns the commit. Run
  directly, you leave the spec change in the working tree for the user to commit.
- Requirements are never deleted, never renumbered, and ids are never reused.
- You never author, reword, or delete requirement **content** — only identity and
  status. Content belongs to the caller.
- You never touch `card.md`, `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`, or
  `AMENDMENTS.md`. Your write surface is exactly one file: `spec_path`.
- `backfill` is idempotent. It is safe — and expected — to invoke it on every `/refine`
  and `/requirement` run.
````

- [ ] **Step 2: Verify the skill is well-formed and discoverable**

Run:
```bash
rtk proxy head -4 plugins/kanban-flow/skills/req-ids/SKILL.md
```
Expected: a YAML frontmatter block opening with `---`, then `name: req-ids`, then a `description:` ending in `Run under Opus.`, then `---`.

Run:
```bash
rtk proxy grep -c "^### \`backfill\`\|^### \`allocate\`\|^### \`supersede\`" plugins/kanban-flow/skills/req-ids/SKILL.md
```
Expected: `3` — all three operations Tasks 4 and 5 invoke by name are defined.

- [ ] **Step 3: Commit**

```bash
git add plugins/kanban-flow/skills/req-ids/SKILL.md
git commit -m "feat(kanban-flow): add req-ids skill, sole authority for REQ identity

Owns the REQ heading format, id allocation and supersede markers in the
project spec, mirroring how the adr skill owns ADR identity. Exposes
backfill / allocate / supersede for /refine and /requirement.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `templates/INTAKE.md` — shared card doctrine

Lift the card-slicing rules out of `/refine` so `/refine` and `/requirement` cannot drift apart. Read live from the plugin, in the same pattern as `AGENT-PROTOCOL.md`.

**Files:**
- Create: `plugins/kanban-flow/templates/INTAKE.md`
- Modify: `plugins/kanban-flow/templates/board/MILESTONES.md`

**Interfaces:**
- Consumes: the `reqs` field from Task 1; `config.md`'s `layers`.
- Produces: the doctrine both intake skills cite by absolute path `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` (Tasks 4 and 5).

- [ ] **Step 1: Create the doctrine file**

Create `plugins/kanban-flow/templates/INTAKE.md` with exactly this content:

````markdown
# Intake doctrine — turning requirements into cards

Read **live from the plugin** by `/refine` (whole-backlog intake) and `/requirement`
(single-requirement intake). Never copied into a project.

Requirement **identity** — REQ ids, spec headings, supersede markers — is **not** here.
That belongs to the `req-ids` skill. This file is about **cards**.

## Card numbering

`CARD-NNN`, zero-padded to three digits. The next id is `max + 1` across existing
`docs/cards/CARD-*` directories; start at `CARD-001` when there are none. Ids are never
reused and never renumbered. A card lives at `docs/cards/CARD-NNN-<slug>/card.md`, where
`<slug>` is a short kebab-case of the title.

## Slice vertically

Each card must be **independently shippable and testable**. Prefer a thin vertical slice
over a horizontal layer. Apply YAGNI — propose only what the requirement actually demands.

## Classify `type`

- `feature` — a new user-facing capability
- `task` — internal scaffolding or refactor, no direct user value
- `defect` — fixing broken behaviour, **including behaviour a changed requirement has
  made wrong**

## Annotate `layer`

One of `config.layers`. Tag a vertical slice by the **lowest** layer where it does
substantive work — a card adding a domain rule plus the API endpoint that exposes it is
`domain`. `/kanban` orders ready cards by position in that list, so this drives scheduling.

## Link `reqs`

Every card carries `reqs: [REQ-NNN, …]` — the requirement ids it implements. This is the
machine-readable index `/requirement` uses for impact analysis.

**An empty `reqs` means _unknown_, not _unaffected_.** Only cards written before this
field existed should be empty. Never propose a new card without at least one REQ id.

## Write acceptance criteria

Observable, testable bullets. Each cites the requirement it enforces:

```markdown
- [ ] Export produces one CSV row per card, with id, title, status and milestone (REQ-012)
- [ ] A user without read access on the board gets 403 (REQ-012)
```

## Set `depends_on`

The card ids that must be `done` before this card starts — an `api` card depends on its
`domain` and `db` cards. **Keep the graph acyclic.**

## Set `right_sized`

`true` **only** when the card is obviously atomic: a single small change you cannot
imagine splitting. `true` makes `/kanban` skip the slice phase entirely, so use it only
when you are sure. Otherwise leave it `""` and the slice phase decides.

You are the **coarse** slicer. `/kanban`'s `card-slicer` re-checks every non-right-sized
card at pickup and splits anything still too big — so do not agonise over perfect
atomicity here.

## Milestones

A milestone is a **delivery increment** — a coherent set of cards that together ship a
capability. (Distinct from a card's workflow *phase*, slice→deliver.) `MILESTONES.md`
holds one `## M<N> — <title>` heading per milestone **in delivery order**, each with
`**Goal:**` (one line), `**Exit criteria:**` (observable), and `**Cards:**` (member ids).

Two invariants, validated **before** you present a proposal:

1. **Coverage** — every card, new and existing, belongs to **exactly one** milestone.
   None orphaned, none in two.
2. **Dependency consistency** — no card may `depends_on` a card in a **later** milestone.
   Same or earlier is fine.

Report and fix any violation before presenting — rework the grouping or the card's
milestone until both hold.

`/refine` and `/requirement` are the only writers of `MILESTONES.md`. `/kanban` reads it
and never writes it, except for the mechanical parent→children swap on an applied split.

## Never

- Bundle multiple cards into one `card.md`. One card = one file.
- Write `BOARD.md` or `KNOWLEDGE.md` — `/kanban` is their sole writer.
- Touch a card that is **not** in `backlog`. A card beyond backlog owns a branch, a
  worktree and possibly an open PR; only `/kanban` may change it. `/requirement` reaches
  those cards through the amendment queue instead.
- Create branches or worktrees, or write code. Intake is intake.
````

- [ ] **Step 2: Update the MILESTONES board starter to reflect shared ownership**

In `plugins/kanban-flow/templates/board/MILESTONES.md`, replace this line:

```markdown
Ordered delivery milestones, authored by `/refine`. Document order = delivery order.
```

with:

```markdown
Ordered delivery milestones, authored by `/refine` and `/requirement`. Document order = delivery order.
```

- [ ] **Step 3: Verify**

Run:
```bash
rtk proxy grep -n "Coverage\|Dependency consistency\|empty \`reqs\`\|not in \`backlog\`" plugins/kanban-flow/templates/INTAKE.md
```
Expected: four matches — both milestone invariants, the `reqs`-means-unknown rule, and the backlog-only boundary. These are the load-bearing rules Tasks 4 and 5 rely on.

Run:
```bash
rtk proxy grep -n "refine" plugins/kanban-flow/templates/board/MILESTONES.md
```
Expected: the line now naming both `/refine` and `/requirement`.

- [ ] **Step 4: Commit**

```bash
git add plugins/kanban-flow/templates/INTAKE.md plugins/kanban-flow/templates/board/MILESTONES.md
git commit -m "feat(kanban-flow): add INTAKE.md shared card doctrine

Card slicing, type/layer classification, reqs linking, depends_on,
right_sized and the milestone invariants — shared live by /refine and
/requirement so the two intake skills cannot drift apart.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Rewrite `/refine` to delegate to `req-ids` and `INTAKE.md`

`/refine` keeps what is genuinely its own — read the whole spec, propose the *entire* backlog, own the approval loop — and delegates identity to `req-ids` and card rules to `INTAKE.md`.

**Files:**
- Modify: `plugins/kanban-flow/skills/refine/SKILL.md` (full rewrite of the body; frontmatter description updated)

**Interfaces:**
- Consumes: `req-ids`'s `backfill` operation (Task 2); `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` (Task 3); the `reqs` card field (Task 1).
- Produces: nothing new for later tasks. This is the last task that touches `/refine`.

- [ ] **Step 1: Replace `plugins/kanban-flow/skills/refine/SKILL.md` with this content**

````markdown
---
name: refine
description: Use to populate or re-slice a project's backlog. Backfills REQ ids into the spec via req-ids, then proposes decomposed, ordered cards (type, layer, reqs, acceptance criteria, depends_on) and a milestone plan for approval into docs/cards/. Intake only — never starts implementation. Run under Opus.
---

# Refine — backlog intake

Turn the whole spec into a backlog of right-sized cards. You propose; the driver
approves; only then do cards land on disk. **Never** start slice/design/implementation
work here — that is `/kanban`'s job.

You are one of the two **intake** skills. `/requirement` is the other: it handles a
*single* new or changed requirement. You both follow the same card doctrine and share
ownership of `MILESTONES.md`.

## Steps

1. **Read context.** Read `{board_dir}/config.md` first (`spec_path`, `layers`,
   `board_dir`). Then read:
   - the plugin's card doctrine at `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` — **the
     rules for everything below**: card numbering, vertical slicing, `type`, `layer`,
     `reqs`, acceptance criteria, `depends_on`, `right_sized`, and the milestone
     invariants. Follow it exactly; it is not duplicated here.
   - the spec at `spec_path`, plus any material it references;
   - `{board_dir}/KNOWLEDGE.md`;
   - every existing `docs/cards/CARD-*/card.md`, so you neither duplicate nor renumber
     over an existing card;
   - `{board_dir}/MILESTONES.md`;
   - the card template — `config.md`'s `template_overrides["card-template.md"]` if set,
     else `${CLAUDE_PLUGIN_ROOT}/templates/card-template.md`.

2. **Ensure the spec has REQ ids.** Invoke the **`req-ids`** skill's **`backfill`**
   operation on `spec_path`. On an un-id'd spec it proposes an id'd version for the
   driver's approval; on an already-id'd spec it is a silent no-op. Do this **before
   slicing** — every card you propose must cite REQ ids, so the ids have to exist first.
   Never assign REQ ids yourself; `req-ids` is their sole authority.

3. **Slice the spec into cards**, following `INTAKE.md`. Respect `config.layers`' order.

4. **Group the cards into ordered milestones**, following `INTAKE.md`'s milestone rules.
   Assign **every** card — proposed and existing — to exactly one milestone, and validate
   both invariants (coverage; no card depends on a card in a later milestone) before you
   present anything.

5. **Present the proposal** to the driver:
   - the **card table** — id, type, layer, title, `reqs`, `depends_on`, a one-line why,
     and 2–4 acceptance criteria each;
   - the **milestone plan** — ordered `M1…Mn` with title, goal, and member ids.

   Ask for approval, edits, or removals. Iterate the cards and milestones together until
   approved.

6. **On approval, write.** For each approved card, create
   `docs/cards/CARD-NNN-<slug>/card.md` from the card template with `status: backlog`,
   `phase: backlog`, the chosen `type`/`layer`/`reqs`/`depends_on`, empty
   `branch`/`worktree`, `reworks: 0`, `right_sized` per `INTAKE.md`, and today's date.
   Then create or update `{board_dir}/MILESTONES.md` in its documented format. When
   re-slicing an existing backlog, place new cards into the right milestone and keep both
   invariants holding across the whole set.

7. **Hand off.** Tell the driver to run `/kanban` to render the board and begin
   scheduling. Do not render `BOARD.md` yourself.

## Rules

- **Intake only.** No branches, no worktrees, no code.
- **Your only spec write is `req-ids`' backfill.** You never author, reword, or delete
  requirement content — that is `/requirement`'s job. You add ids to prose that already
  exists, nothing more.
- Card doctrine lives in `INTAKE.md`, not here. If a rule about slicing, typing, layering,
  `reqs`, `depends_on`, `right_sized`, or milestones seems to be missing, it is in
  `INTAKE.md` — read it, don't invent it.
- You may only create and edit cards in `status: backlog`. A card beyond backlog belongs
  to `/kanban`. If the backlog you are re-slicing collides with an in-flight card, say so
  and stop — `/requirement` is the skill that can act on it, via the amendment queue.
- Do not edit `BOARD.md` or `KNOWLEDGE.md`.
- You share `MILESTONES.md` with `/requirement`. `/kanban` reads it but never writes it.
````

- [ ] **Step 2: Verify the delegation is real, not just described**

Run:
```bash
rtk proxy grep -n "INTAKE.md\|req-ids\|backfill" plugins/kanban-flow/skills/refine/SKILL.md
```
Expected: `INTAKE.md` cited by its `${CLAUDE_PLUGIN_ROOT}` path in Step 1 and referenced in the Rules; `req-ids` + `backfill` named in Step 2.

Run:
```bash
rtk proxy grep -n "vertical\|YAGNI\|acyclic\|Coverage" plugins/kanban-flow/skills/refine/SKILL.md
```
Expected: **no matches.** The slicing rules must now live only in `INTAKE.md` — a match here means the doctrine got duplicated, which is exactly what this task exists to prevent.

- [ ] **Step 3: Commit**

```bash
git add plugins/kanban-flow/skills/refine/SKILL.md
git commit -m "refactor(kanban-flow): /refine delegates to req-ids and INTAKE.md

Card doctrine moves to the shared INTAKE.md; REQ id backfill moves to the
req-ids skill. /refine keeps whole-backlog intake, the proposal loop, and
MILESTONES.md (now shared with /requirement).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: The `/requirement` skill

The main deliverable. Elicits a requirement, persists it via `req-ids`, slices cards per `INTAKE.md`, and applies impact — directly for `backlog` cards, via the amendment queue for everything in flight.

**Files:**
- Create: `plugins/kanban-flow/skills/requirement/SKILL.md`

**Interfaces:**
- Consumes: `req-ids`'s `backfill` / `allocate` / `supersede` (Task 2); `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` (Task 3); the `reqs` field and `superseded` status (Task 1).
- Produces: the **`AMENDMENTS.md` queue format** that `/kanban` drains in Task 6. Its exact shape — a `## CARD-NNN — <action>` heading with `**Raised:**`, `**Reason:**`, `**Action:**` lines, and the two legal actions `supersede` and `revisit` — is the contract between this task and Task 6. Do not change it in one place only.

- [ ] **Step 1: Create the skill file**

Create `plugins/kanban-flow/skills/requirement/SKILL.md` with exactly this content:

````markdown
---
name: requirement
description: Add, amend or supersede a single requirement on a running project. Interviews the driver into a well-formed requirement, persists it to the spec via req-ids, slices it into cards per the intake doctrine, and applies its impact on the board — editing backlog cards directly and queueing amendments for cards already in flight. Intake only — never starts implementation. Run under Opus.
---

# /requirement — add, amend, or supersede a requirement

`/refine` turns a whole spec into a backlog. **You handle one requirement on a project
that is already running** — the mid-flight ask, the changed mind, the thing the spec
never said.

You are an **intake** skill. You never write code, never create branches or worktrees,
and never start a card.

Usage: `/requirement [rough one-liner]`. With no argument, ask what the driver wants to add.

## The ownership boundary — read this first

`/kanban` is the **sole writer** of every `card.md` from the moment a card leaves
`backlog`. That rule is what makes the board safe to drive unattended under `/loop`, and
a card beyond backlog owns a git branch, a worktree, and possibly an open PR — so
retiring one is a **teardown**, not a file edit.

You respect that boundary absolutely. Classify every existing card by `status` alone:

| Card status | What you may do |
|---|---|
| `backlog` | **Edit, re-slice, or delete it directly.** No branch, no worktree, no PR — nothing to tear down. This is the same authority `/refine` has. |
| `slice` … `deliver`, `blocked` | **Never touch the file.** Append an amendment to `{board_dir}/AMENDMENTS.md`; `/kanban` applies it on its next pump. |
| `done` | **Never amend, never supersede** — it shipped. If the new requirement contradicts shipped behaviour, that is a **new card** (usually a `defect`). |
| `split`, `superseded` | Terminal. Ignore. |

## Steps

1. **Load context.** Read `{board_dir}/config.md` first (`spec_path`, `layers`,
   `board_dir`). Then read:
   - the plugin's card doctrine at `${CLAUDE_PLUGIN_ROOT}/templates/INTAKE.md` — the
     rules for every card you propose. Follow it exactly; it is not duplicated here.
   - the spec at `spec_path`;
   - every `docs/cards/CARD-*/card.md` (you need `status`, `reqs` and `depends_on` on all
     of them for impact analysis);
   - `{board_dir}/MILESTONES.md` and `{board_dir}/KNOWLEDGE.md`;
   - the card template — `config.md`'s `template_overrides["card-template.md"]` if set,
     else `${CLAUDE_PLUGIN_ROOT}/templates/card-template.md`.

2. **Ensure the spec has REQ ids.** Invoke the **`req-ids`** skill's **`backfill`**
   operation. On an un-id'd spec it proposes an id'd version for approval; otherwise it is
   a silent no-op. Everything below addresses requirements by id, so this must happen first.

3. **Elicit.** Interview the driver **one question at a time** — never a wall of questions.
   Prefer multiple choice where the options are genuinely enumerable. Cover:
   - **Intent** — what becomes possible, and for whom. Why now.
   - **Scope** — and explicitly what is *out* of scope.
   - **Edge cases** — what happens at the boundaries, on failure, for the unauthorised user.
   - **Acceptance** — the observable criteria that would prove it done.

   **Stop as soon as the requirement is testable** — not after a fixed number of questions.
   A requirement is testable when you could hand it to someone who has never met the driver
   and they could tell you whether the built thing satisfies it.

4. **Analyse impact.** Decide what this requirement *is*:
   - **new** — it adds a capability nothing in the spec covers;
   - **amends** an existing `REQ-NNN` — same capability, changed detail;
   - **supersedes** one or more existing `REQ-NNN` — the old requirement is now wrong.

   Then find every affected card. Use the `reqs` frontmatter field as the index — it is a
   lookup, not an inference. Two traps:
   - **A card with empty `reqs` means _unknown_, not _unaffected_.** It pre-dates the
     field. Read it and judge; surface it to the driver as *impact undetermined* rather
     than silently assuming it is fine.
   - **Superseding a card orphans its dependents.** Any card whose `depends_on` names a
     card you are superseding can never become ready — `/kanban` will park it forever. For
     **every** dependent you must propose a rewire: drop the dead id, or repoint it at the
     replacement card. A `backlog` dependent you rewire directly; an in-flight dependent
     needs its own `revisit` amendment. **Never leave a dangling `depends_on`.**

   Classify each affected card by the ownership boundary above.

5. **Propose — once.** A single approval surface. Show:
   - the **requirement** exactly as it will appear in the spec (heading, `**Status:**`, prose);
   - any **supersede** links (`REQ-012 supersedes REQ-004`);
   - the **new cards** — id, type, layer, title, `reqs`, `depends_on`, and acceptance
     criteria, per `INTAKE.md`;
   - **edits and deletions to backlog cards**, each with its reason;
   - **`depends_on` rewires**, each with its reason;
   - **milestone placement** for every new card, with both `INTAKE.md` invariants
     re-validated across the whole board;
   - the **amendments to be queued** — one line per in-flight card, naming the action and
     why.

   Ask for approval, edits, or removals. Iterate until approved. **Write nothing before
   approval.**

6. **On approval, write — then commit once.**
   1. Persist the requirement via **`req-ids`**: `allocate` for the new one (it returns the
      id), then `supersede` for any it replaces. Never edit the spec by hand.
   2. Create the new cards from the card template, and apply the approved edits, deletions
      and `depends_on` rewires to `backlog` cards.
   3. Update `{board_dir}/MILESTONES.md`.
   4. Append the approved amendments to `{board_dir}/AMENDMENTS.md` (format below),
      creating the file if it does not exist.
   5. Commit everything as **one** Conventional Commit:
      `chore(kanban): add REQ-NNN — <title>` (or `amend` / `supersede` as fitting), ending
      with the project's `Co-Authored-By` trailer.

   The commit matters: `/kanban` drains the queue on a later pump, possibly in another
   session. An uncommitted amendment is a lost amendment.

7. **Hand off.** Tell the driver to run **`/kanban`** — it will drain the queue and
   schedule the new cards. If you queued no amendments, say so; the next pump just picks up
   the new cards.

## The amendment queue

`{board_dir}/AMENDMENTS.md` is a queue **you write and `/kanban` drains**. A missing file
means an empty queue.

One block per pending amendment:

```markdown
## CARD-007 — supersede
**Raised:** 2026-07-12 by /requirement
**Reason:** REQ-004 superseded by REQ-012 — export moves from CSV to XLSX, so this card builds the wrong thing.
**Action:** supersede
```

**Exactly two actions.** There is no third — do not invent one.

- **`supersede`** — the card is dead. `/kanban` will close any open PR, tear down the
  worktree and branch, and set `status: superseded` (terminal). Use when the card builds
  something the project no longer wants.
- **`revisit`** — the card is still wanted, but its scope moved. `/kanban` will set
  `status: blocked` with a blocker naming the REQ, leaving the branch, worktree and PR
  intact, and its blocked-card conversation asks the driver how to proceed. Use for
  everything that is not a clean kill.

There is deliberately **no "re-slice a card that already has code on its branch"** action.
That is `revisit` plus a human decision. Do not automate it.

`**Reason:**` is written for a human reading it days later in a different session. Name the
REQ ids and say what actually changed.

## Rules

- **Intake only.** No branches, no worktrees, no code, no starting cards.
- **Never write a `card.md` that is not in `backlog`.** In-flight cards are reached only
  through `AMENDMENTS.md`. This is not a style preference — it is the invariant that keeps
  the board's state from being corrupted by two concurrent writers.
- **Never write `BOARD.md` or `KNOWLEDGE.md`.** `/kanban` owns them.
- **Never edit the spec directly.** `req-ids` is the sole authority for requirement
  identity; you supply the prose, it supplies the identity.
- **Never delete a requirement.** Superseding leaves it in place, marked. History is the point.
- Card doctrine lives in `INTAKE.md`. If a rule about slicing, typing, layering, `reqs`,
  `depends_on`, `right_sized`, or milestones seems missing here, it is there.
- Never leave a dangling `depends_on` pointing at a superseded card.
- Elicit one question at a time.
````

- [ ] **Step 2: Verify the queue contract matches what Task 6 will drain**

Run:
```bash
rtk proxy grep -n "AMENDMENTS.md\|\*\*Action:\*\*\|supersede\|revisit" plugins/kanban-flow/skills/requirement/SKILL.md
```
Expected: the queue file named; the `**Action:**` key present; both `supersede` and `revisit` defined, and the explicit statement that there are exactly two actions.

Run:
```bash
rtk proxy grep -n "dangling\|depends_on" plugins/kanban-flow/skills/requirement/SKILL.md
```
Expected: the dependent-rewire trap in Step 4 and the closing rule. This is the hole in the original design; if these lines are absent, superseding a card will silently deadlock its dependents.

- [ ] **Step 3: Commit**

```bash
git add plugins/kanban-flow/skills/requirement/SKILL.md
git commit -m "feat(kanban-flow): add /requirement skill

Elicits one requirement, persists it via req-ids, slices cards per
INTAKE.md, edits backlog cards directly, and queues AMENDMENTS.md for
cards already in flight so /kanban's sole-writer invariant holds.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `/kanban` — drain the queue, render `Superseded`, update ownership

**Files:**
- Modify: `plugins/kanban-flow/skills/kanban/SKILL.md` — frontmatter `description`, intro paragraph (line ~8), Section 0 (Reconcile), Section 2 (Render), Section 4 (Schedule), Section 7 (Report), Rules.

**Interfaces:**
- Consumes: the `AMENDMENTS.md` block format and its two actions from Task 5; the `superseded` status from Task 1.
- Produces: nothing later tasks depend on.

- [ ] **Step 1: Update the frontmatter description**

In the `description:` field, replace:
```
/refine creates cards; /kanban is the sole writer of BOARD.md, KNOWLEDGE.md, and card.md thereafter.
```
with:
```
/refine and /requirement create and edit backlog cards; /kanban is the sole writer of BOARD.md, KNOWLEDGE.md, and card.md thereafter, and drains /requirement's amendment queue.
```

- [ ] **Step 2: Update the intro paragraph**

Replace the first sentence of the body paragraph (currently `You drive cards through the board. `/refine` creates cards; thereafter you are the **sole writer** of …`) with:

```markdown
You drive cards through the board. The intake skills `/refine` and `/requirement` create and edit cards **while they are in `backlog`**; from the moment a card leaves backlog you are its **sole writer** — as you are of `docs/cards/BOARD.md` and `docs/cards/KNOWLEDGE.md` throughout. `/requirement` reaches cards beyond backlog only by queueing an amendment for you to apply (Section 0). No phase agent ever writes these files. Phase agents only return structured `result` blocks; you persist everything they produce.
```

- [ ] **Step 3: Add the queue drain to Section 0 (Reconcile)**

Insert this as **step 6** of Section 0, immediately after the "Normalize legacy state" step, and **renumber the existing final step ("Note any other drift…") to 7**:

````markdown
6. **Drain the amendment queue.** Read `{board_dir}/AMENDMENTS.md` (absent → empty queue → skip). It is written by `/requirement` when a new or changed requirement invalidates a card that is no longer in `backlog`. For each `## CARD-NNN — <action>` block, apply it and then **delete the block**:
   - **`supersede`** — the card is dead. Close any open PR (design or implementation) with a comment naming the superseding requirement (`{gh_command} pr close <url> --comment "Superseded by <REQ-NNN> — <reason>"`), tear down its worktree and delete its local branch, set `status: superseded` / `phase: superseded`, and append the block's `**Reason:**` verbatim to the card's `## Notes`. **Terminal:** a superseded card is never scheduled, holds no WIP slot, and is never reopened.
   - **`revisit`** — the card is still wanted but its scope moved. Set `status: blocked` with the blocker `requirement changed — <REQ-NNN>`, and append the `**Reason:**` to `## Notes`. **Leave the branch, worktree and any open PR intact** — Section 3's blocked-card conversation asks the driver how to proceed.

   Any other action value, a block naming a card that does not exist, or a block naming a card already `done`/`split`/`superseded`: **leave the block in place** and surface it as drift (step 7). Never guess.

   Commit the drained queue and the card changes with the pump's state commit (e.g. `chore(kanban): apply amendments — CARD-007 superseded`), and list what you applied in the report (Section 7).
````

- [ ] **Step 4: Render the `Superseded` column (Section 2)**

Replace:
```markdown
Columns in order: Backlog, Slice, Design, Implement, Test, Review, Deliver, Blocked, Done, Split.
```
with:
```markdown
Columns in order: Backlog, Slice, Design, Implement, Test, Review, Deliver, Blocked, Done, Split, Superseded.
```

And immediately after the sentence describing how `split` cards render, add:

```markdown
Render `status: superseded` cards in the `## Superseded` section as `CARD-NNN — title → superseded by REQ-NNN` (terminal).
```

- [ ] **Step 5: Teach the scheduler about terminal and dangling state (Section 4)**

Replace:
```markdown
`split` is terminal, not in-flight.
```
with:
```markdown
`split` and `superseded` are terminal, not in-flight — neither holds a WIP slot, and neither is ever scheduled.
```

Then add this bullet at the end of Section 4:

```markdown
- **Dangling dependency:** a `backlog` card whose `depends_on` names a `superseded` card can never become ready. `/requirement` is required to rewire dependents when it supersedes a card, so this means something slipped. Surface it as drift, leave the card parked, and tell the driver to fix it with `/requirement` — **never silently treat the dead dependency as satisfied.**
```

- [ ] **Step 6: Report amendments (Section 7)**

In the Section 7 digest sentence, add `amendments applied (card, action, REQ)` to the list of things the report prints — alongside `splits, blocks, free slots`.

- [ ] **Step 7: Update the Rules**

Replace the first Rules bullet:
```markdown
- `/refine` creates `card.md` files; thereafter never let phase agents write `BOARD.md`, `KNOWLEDGE.md`, or `card.md` — you are the sole writer of all three.
```
with:
```markdown
- `/refine` and `/requirement` create and edit `card.md` files **in `backlog`**; from the moment a card leaves backlog you are its sole writer, and you are sole writer of `BOARD.md` and `KNOWLEDGE.md` throughout. Never let phase agents write any of the three.
```

Replace the `MILESTONES.md` bullet:
```markdown
- `/refine` owns `MILESTONES.md`; your only edit is the mechanical parent→children swap on an applied split.
```
with:
```markdown
- `/refine` and `/requirement` own `MILESTONES.md`; your only edit is the mechanical parent→children swap on an applied split.
```

And add these two bullets:
```markdown
- **Never write `spec_path`.** Requirement content belongs to `/requirement`; requirement identity (REQ ids, supersede markers) belongs to the `req-ids` skill.
- `superseded` is terminal, exactly like `split`: never scheduled, never reopened, never holding a WIP slot. It is set **only** by draining an amendment (Section 0), never by a phase agent.
```

- [ ] **Step 8: Verify every edit landed and nothing contradicts**

Run:
```bash
rtk proxy grep -n "AMENDMENTS\|superseded\|Superseded" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: the Section 0 drain step, the Section 2 column and render line, the Section 4 terminal + dangling-dependency rules, the Section 7 report line, and both new Rules bullets.

Run:
```bash
rtk proxy grep -n "/refine creates" plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: **no matches.** The old sole-writer wording must be gone from both the description and the Rules — a leftover here is a doctrine contradiction that a phase agent will act on.

- [ ] **Step 9: Commit**

```bash
git add plugins/kanban-flow/skills/kanban/SKILL.md
git commit -m "feat(kanban-flow): /kanban drains the amendment queue

Reconcile applies /requirement's amendments (supersede tears the card
down and closes its PR; revisit blocks it for the driver). Adds the
terminal Superseded column, guards against dangling depends_on, and
updates the sole-writer rules for shared backlog ownership.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: README and version bump

**Files:**
- Modify: `plugins/kanban-flow/README.md`
- Modify: `plugins/kanban-flow/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing.

- [ ] **Step 1: Document the two new skills in the README**

In `plugins/kanban-flow/README.md`, replace the `**Skills:**` line under `## Contents` with:

```markdown
- **Skills:** `kanban` (orchestrator), `refine` (whole-backlog intake), `requirement` (add/amend/supersede a single requirement on a running project), `req-ids` (sole authority for REQ ids in the spec), `retro` (process improvement), `adr` (ADR persistence), `kanban-init` (project scaffolder), `migrate` (one-time upgrade of an existing repo to plugin-owned doctrine).
```

In the `**Templates:**` line, add `INTAKE.md` to the list of plugin-owned doctrine files (alongside `AGENT-PROTOCOL.md` and `REVIEW-LENSES.md`).

- [ ] **Step 2: Add a usage step for `/requirement`**

In the `## Use` section, append a step 5:

```markdown
5. When a new requirement lands mid-project, run `/requirement` — it interviews you, writes the requirement to your spec with a stable `REQ-NNN` id, slices it into cards, and reports what it invalidates on the board. Then run `/kanban` to apply it.
```

- [ ] **Step 3: Bump the version**

In `plugins/kanban-flow/.claude-plugin/plugin.json`, change `"version": "0.2.0"` to `"version": "0.3.0"`.

- [ ] **Step 4: Verify the JSON is still valid**

Run:
```bash
rtk proxy python3 -c "import json;print(json.load(open('plugins/kanban-flow/.claude-plugin/plugin.json'))['version'])"
```
Expected: `0.3.0`

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/README.md plugins/kanban-flow/.claude-plugin/plugin.json
git commit -m "docs(kanban-flow): document /requirement and req-ids; bump to 0.3.0

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: End-to-end validation in a scratch repo

**This task is driven interactively by a human in a Claude Code session** — it exercises slash commands, which an agent cannot invoke on the user's behalf. Do not skip it and do not simulate it. Record what actually happened, including anything that went wrong.

**Files:**
- Create: `docs/superpowers/plans/2026-07-12-kanban-requirement-validation.md` (the record of results)

- [ ] **Step 1: Build a scratch project**

```bash
mkdir -p /private/tmp/claude-501/-Users-stevebennett-Code-nyx-claude/b976d8fb-06be-41d6-8475-c085b5be25be/scratchpad/kanban-scratch
cd /private/tmp/claude-501/-Users-stevebennett-Code-nyx-claude/b976d8fb-06be-41d6-8475-c085b5be25be/scratchpad/kanban-scratch
git init
mkdir -p docs
```

Write `docs/spec.md` as **un-id'd prose** — this is what exercises `backfill`:

```markdown
# Widget Tracker — spec

## Overview
A tool for tracking widgets through a workshop.

## Boards
Users can create a board and add cards to it. Each card has a title and a status.
Users with read access can export a board to CSV.

## Access
Only the board owner can delete a board.
```

- [ ] **Step 2: Install the plugin from this local marketplace**

In a Claude Code session rooted at the scratch repo:

```
/plugin marketplace add /Users/stevebennett/Code/nyx-claude
/plugin install kanban-flow@nyx-claude
/kanban-init
```

Expected: `docs/cards/` scaffolded with `config.md`, `PROTOCOL-ADDENDUM.md`, `BOARD.md`, `KNOWLEDGE.md`, `MILESTONES.md`. Confirm `INTAKE.md` was **not** copied in (it is plugin-owned).

- [ ] **Step 3: Case 1 — `/refine` backfills REQ ids on its first pass**

Run `/refine`.

Expected, and record each: it invokes `req-ids` **before** slicing; it presents an id'd `docs/spec.md` as a diff (roughly `REQ-001` create-board/add-cards, `REQ-002` CSV export, `REQ-003` owner-only delete — the exact split is judgement, so record what it chose); on approval the spec is written; the cards it then proposes each carry `reqs:` citing those ids.

Approve, then confirm on disk:
```bash
rtk proxy grep -n "REQ-\|Status:" docs/spec.md
rtk proxy grep -rn "reqs:" docs/cards/
```

- [ ] **Step 4: Case 2 — `/refine` is idempotent**

Run `/refine` again. Expected: `req-ids` reports `already-id'd` and writes nothing; the spec is unchanged (`git diff --stat docs/spec.md` → empty). Record if it re-ids anything — that is a bug in `backfill`'s step 2.

- [ ] **Step 5: Case 3 — a new requirement, no conflict**

Run `/kanban` once to start a card, then:

```
/requirement users should be able to filter a board by status
```

Expected: it interviews you one question at a time; proposes a `REQ-004` plus card(s); on approval writes the spec, cards and `MILESTONES.md` in **one** commit; queues **no** amendments. Confirm `AMENDMENTS.md` does not exist or is empty.

- [ ] **Step 6: Case 4 — supersede affecting a `backlog` card**

Supersede the CSV-export requirement with an XLSX one, while its card is still in `backlog`:

```
/requirement exports should be XLSX, not CSV — CSV is dropped entirely
```

Expected: it identifies the export card via `reqs`; `req-ids` marks the old REQ `**Status:** superseded by REQ-NNN` and leaves its prose in place; the **backlog card is edited or deleted directly**; **no amendment is queued**. Confirm:
```bash
rtk proxy grep -n "superseded by" docs/spec.md
```

- [ ] **Step 7: Case 5 — supersede affecting an in-flight card (the important one)**

Run `/kanban` until a card is genuinely in flight (it has a `branch` and a `worktree`, ideally an open PR). Then supersede the requirement that card implements.

Expected:
- the in-flight `card.md` is **not modified** by `/requirement` (`git log -1 --stat` on it shows no `/requirement` commit touching it);
- an `AMENDMENTS.md` block appears with `**Action:** supersede`;
- if any card `depends_on` the doomed card, `/requirement` proposes a **rewire** — this is the deadlock guard;
- everything lands in one commit.

Then run `/kanban` and confirm it: closes the open PR with a comment naming the REQ, tears down the worktree and branch, sets `status: superseded`, renders the card under `## Superseded` in `BOARD.md`, deletes the drained block from `AMENDMENTS.md`, and reports the amendment.

- [ ] **Step 8: Case 6 — `revisit`**

Queue a `revisit` amendment against an in-flight card (supersede a requirement it only partly implements, so the card is still wanted).

Expected from the next `/kanban`: `status: blocked` with a blocker naming the REQ; **branch, worktree and PR left intact**; the blocked-card conversation offers re-dispatch / edit / park.

- [ ] **Step 9: Write down what actually happened**

Create `docs/superpowers/plans/2026-07-12-kanban-requirement-validation.md` recording, per case: what you ran, what happened, and **pass or fail**. Where behaviour differed from this plan, write what it actually did — do not paper over it. Any failure here is a doctrine bug in one of the Markdown files; fix it in the relevant task's file and re-run the affected case.

- [ ] **Step 10: Commit the record**

```bash
cd /Users/stevebennett/Code/nyx-claude
git add docs/superpowers/plans/2026-07-12-kanban-requirement-validation.md
git commit -m "docs: record end-to-end validation of /requirement and req-ids

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-review notes

**Spec coverage.** Every section of the design maps to a task: the `req-ids` skill and its three operations → Task 2; the spec/REQ format → Task 2; the `reqs` card link → Tasks 1 and 3; `/requirement`'s command surface, elicit, impact analysis and one-pass proposal → Task 5; the ownership boundary → Tasks 5 and 6; the amendment queue and its two actions → Tasks 5 (writer) and 6 (drainer); the `Superseded` column → Task 6; `INTAKE.md` and the `/refine` refactor → Tasks 3 and 4; files/version/README → Task 7; the validation cases → Task 8. `/migrate` and `/kanban-init` are untouched, as the design specifies.

**One addition beyond the spec.** Superseding a card leaves any card that `depends_on` it permanently un-ready — `/kanban` would park the dependent forever with no diagnosis. The design did not cover this. Task 5 requires `/requirement` to propose a rewire for every dependent, and Task 6 makes `/kanban` surface a dangling dependency as drift rather than silently treating it as satisfied.

**Contract consistency.** The `AMENDMENTS.md` block shape (`## CARD-NNN — <action>`, `**Raised:**`, `**Reason:**`, `**Action:**`) and its two legal actions (`supersede`, `revisit`) are written identically in Task 5 (the writer) and Task 6 (the drainer). The three `req-ids` operation names (`backfill`, `allocate`, `supersede`) are used identically in Tasks 2, 4 and 5. The `superseded` status is introduced in Task 1 and consumed in Tasks 5 and 6.
