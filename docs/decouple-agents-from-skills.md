# Decouple agents from skills — compose at dispatch time

**Current state:** Every agent definition hardcodes its skill name and describes what the
skill does. This couples agents to skills in two places: the name reference and the summary
paragraph.

**Target state:** Agents are pure persona + permissions + protocol bootstrap. They never
name a skill. The orchestrator (and `INTAKE.md` for the intake checker) owns the wiring and
injects "Load and execute the **`<skill>`** skill." at dispatch time.

**Skills are untouched** — they're already pure, uncoupled recipes.

---

## File-by-file changes

### 1. Orchestrator dispatch table — add `skill` column

**File:** `plugins/kanban-flow/.opencode/skills/kanban-orchestrator/SKILL.md`

**Edit 1.1 — replace the table header and rows (lines 501–516)**

Find this exact text:
```
| status / condition | dispatch | model |
|---|---|---|
| slice, `slice.md` absent | card-slicer | sonnet |
| slice, `slice.md` present, `slice-check.md` absent | card-slice-checker | sonnet |
| design, `design.md` absent | card-designer | opus |
| design, `design.md` present, `design-check.md` absent | card-design-checker | opus |
| implement, `implement.md` absent (or a failing `test.md`/`review.md` present) | card-implementer | sonnet |
| test, `test.md` absent | card-tester | haiku — **sonnet when levels are configured** (env lifecycle + failure classification are judgement; per-card, not a lens multiplier) |
| review, **`review.md` absent** | **card-lens-reviewer × lenses, in parallel** (only `review_lenses_failed`, if set) | per-lens (Section 5, review panel) |
| review, panel passed, diff > `size_limit`, `split.md` absent | **pr-splitter** | sonnet |
| review, `split.md` present, `split-check.md` absent | **card-split-checker** | sonnet |
| review, split check passed with N ≥ 2, `split-acceptance.md` absent | **card-lens-reviewer × N, in SLICE MODE** — lens `acceptance`, **one per slice**, in parallel, each carrying `slice: k`, `slices: N`, slice `k`'s path list + change types, and `split.md` | sonnet — narrow trace re-check; code already opus-reviewed (RATIONALE) |
| deliver (design PR, implementation PR, **or slice PR `k`**) | card-deliverer | haiku |
| design PR open, `deliver-check-design.md` absent | card-deliver-checker (design mode) | sonnet |
| implementation PR open, `deliver-check.md` absent (**slice PR `k` open, `deliver-check-<k>.md` absent**) | card-deliver-checker (implementation mode) | sonnet |
| **open slice PR `k` needs a commit** (§6a CI rework, §6b addressing, a `DLV-*` finding routed to the implementer) | card-implementer — **dispatched into slice `k`'s worktree, on slice `k`'s branch**, never the card's | sonnet |
```

Replace with this exact text:
```
| status / condition | dispatch | model | skill |
|---|---|---|---|
| slice, `slice.md` absent | card-slicer | sonnet | slice-card |
| slice, `slice.md` present, `slice-check.md` absent | card-slice-checker | sonnet | slice-check |
| design, `design.md` absent | card-designer | opus | design-card |
| design, `design.md` present, `design-check.md` absent | card-design-checker | opus | design-check |
| implement, `implement.md` absent (or a failing `test.md`/`review.md` present) | card-implementer | sonnet | implement-card |
| test, `test.md` absent | card-tester | haiku — **sonnet when levels are configured** (env lifecycle + failure classification are judgement; per-card, not a lens multiplier) | test-card |
| review, **`review.md` absent** | **card-lens-reviewer × lenses, in parallel** (only `review_lenses_failed`, if set) | per-lens (Section 5, review panel) | lens-review |
| review, panel passed, diff > `size_limit`, `split.md` absent | **pr-splitter** | sonnet | carve-pr |
| review, `split.md` present, `split-check.md` absent | **card-split-checker** | sonnet | split-check |
| review, split check passed with N ≥ 2, `split-acceptance.md` absent | **card-lens-reviewer × N, in SLICE MODE** — lens `acceptance`, **one per slice**, in parallel, each carrying `slice: k`, `slices: N`, slice `k`'s path list + change types, and `split.md` | sonnet — narrow trace re-check; code already opus-reviewed (RATIONALE) | lens-review |
| deliver (design PR, implementation PR, **or slice PR `k`**) | card-deliverer | haiku | deliver-pr |
| design PR open, `deliver-check-design.md` absent | card-deliver-checker (design mode) | sonnet | deliver-check |
| implementation PR open, `deliver-check.md` absent (**slice PR `k` open, `deliver-check-<k>.md` absent**) | card-deliver-checker (implementation mode) | sonnet | deliver-check |
| **open slice PR `k` needs a commit** (§6a CI rework, §6b addressing, a `DLV-*` finding routed to the implementer) | card-implementer — **dispatched into slice `k`'s worktree, on slice `k`'s branch**, never the card's | sonnet | implement-card |
```

**Edit 1.2 — insert skill injection into dispatch prompt template**

Find this exact text (lines 573–577):
```
Include `worktree` once it exists. **Always include the doctrine paths** every agent reads:
`.opencode/doctrine/AGENT-PROTOCOL.md` and the repo's `<board_dir>/PROTOCOL-ADDENDUM.md`.
**Every `card-*-checker` dispatch additionally carries `.opencode/doctrine/checks/_method.md`
plus its own target's `.opencode/doctrine/checks/<target>.md`** (intake→`intake.md`,
slice→`slice.md`, design→`design.md`, split→`split.md`, deliver→`deliver.md`).
```

Replace with this exact text:
```
Include `worktree` once it exists. **Always include the doctrine paths** every agent reads:
`.opencode/doctrine/AGENT-PROTOCOL.md` and the repo's `<board_dir>/PROTOCOL-ADDENDUM.md`.
**Every `card-*-checker` dispatch additionally carries `.opencode/doctrine/checks/_method.md`
plus its own target's `.opencode/doctrine/checks/<target>.md`** (intake→`intake.md`,
slice→`slice.md`, design→`design.md`, split→`split.md`, deliver→`deliver.md`).

**In every dispatch prompt, after the protocol bootstrap, inject one instruction:**
`Load and execute the **\`<skill>\`** skill.` — reading the `skill` column from the dispatch
table above. This is the sole authority for the agent→skill mapping. Agent definitions
never name their skill; the orchestrator wires it.
```

---

### 2. INTAKE.md — add skill injection for intake checker

**File:** `plugins/kanban-flow/.opencode/doctrine/INTAKE.md`

**Edit 2.1 — add skill injection to the dispatch instruction (lines 99–106)**

Find this exact text:
```
Unless `config.md`'s `checks.intake` is `off`, dispatch **`card-intake-checker`** (opus)
with: the proposed cards, their milestone placement, the existing board's cards and
milestones, the requirement(s) in scope, `spec_path`, **`size_limit` and `size_exclude`**
(the ceiling and exclusions for `INT-SIZED`), and the doctrine paths it reads —
`.opencode/doctrine/AGENT-PROTOCOL.md`,
`.opencode/doctrine/checks/_method.md`,
`.opencode/doctrine/checks/intake.md`,
`.opencode/doctrine/INTAKE.md`, and `<board_dir>/PROTOCOL-ADDENDUM.md`.
```

Replace with this exact text:
```
Unless `config.md`'s `checks.intake` is `off`, dispatch **`card-intake-checker`** (opus)
with: the proposed cards, their milestone placement, the existing board's cards and
milestones, the requirement(s) in scope, `spec_path`, **`size_limit` and `size_exclude`**
(the ceiling and exclusions for `INT-SIZED`), **the instruction `Load and execute the
\`\`intake-check\`\` skill.`**, and the doctrine paths it reads —
`.opencode/doctrine/AGENT-PROTOCOL.md`,
`.opencode/doctrine/checks/_method.md`,
`.opencode/doctrine/checks/intake.md`,
`.opencode/doctrine/INTAKE.md`, and `<board_dir>/PROTOCOL-ADDENDUM.md`.
```

---

### 3. Strip skill references from all 12 agent definitions

Every agent currently has variations of:
1. A line like `Then load and execute the **\`<skill>\`** skill.` (or `— it handles...`)
2. A paragraph beginning `The skill handles...` or `The skill defines...` summarising what
   the skill does.

Both must be removed. Dispatch-input notes that are **agent-specific** (not in the skill)
stay. The pattern is:

- **Remove** the "load and execute" line entirely.
- **Remove** the "The skill handles..." follow-up paragraph entirely.
- **Keep** the agent's persona, protocol-bootstrap, dispatch-mode awareness, and
  agent-specific constraints (GitHub rules, worktree rules, "never improvise" rules).
- **Keep** the "Return per the protocol's result block" line (the return format lives in
  AGENT-PROTOCOL.md).

Below are the exact old→new replacements for each agent. If an `oldString` is not found
exactly as shown, the file has diverged — search for the skill name instead and adapt.

#### 3.1 card-deliver-checker.md

**File:** `plugins/kanban-flow/.opencode/agents/card-deliver-checker.md`

Find:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`. Then load and execute the **`deliver-check`** skill.

Your dispatch gives you the card, the PR URL, the mode, the worktree, the `gh_command`, size
limits, estimated lines, and the checks policy. The skill handles the gather-evidence workflow,
the DLV-* criteria (including slice vs unsplit variations), verdict logic, and the
`phase_doc` naming rules.

Return per the protocol's ````result` block; the skill defines the `phase_doc` structure and
section names.
```

Replace with:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`.

Your dispatch gives you the card, the PR URL, the mode, the worktree, the `gh_command`, size
limits, estimated lines, and the checks policy.

Return per the protocol's ````result` block.
```

#### 3.2 card-deliverer.md

**File:** `plugins/kanban-flow/.opencode/agents/card-deliverer.md`

Find:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.
Then load and execute the **`deliver-pr`** skill — it handles both design and implementation
modes, including slice PRs.

Your dispatch names your mode (`design` or `implementation`), the card's `worktree`, and the
path to the PR body file. The skill defines the rebase, verify, push, open-PR workflow for each
mode, the body-file workflow, and the return format with `phase_doc` naming.

Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.

Your dispatch names your mode (`design` or `implementation`), the card's `worktree`, and the
path to the PR body file.

Return per the protocol's ````result` block.
```

#### 3.3 card-design-checker.md

**File:** `plugins/kanban-flow/.opencode/agents/card-design-checker.md`

Find:
```
Read `AGENT-PROTOCOL.md` (its **Doctrine** section is the substance of `DSG-DOCTRINE` — read it
carefully), then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both. Then load and
execute the **`design-check`** skill.

Your dispatch provides the card, the design's outputs (`slice.md`, `design.md`,
`proposed_adrs`), spec sections, and — when the project configures test levels — level
definitions, the derive map, seams, and the `LEVELS.md` doctrine path. The skill handles the
derive-before-reading procedure, the DSG-* criteria (including conditional
`DSG-LEVELS`/`DSG-SEAMS`/`DSG-DATA`), the two-way criteria ↔ task map, verdict logic, and the
`design-check.md` return structure.

Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md` (its **Doctrine** section is the substance of `DSG-DOCTRINE` — read it
carefully), then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.

Your dispatch provides the card, the design's outputs (`slice.md`, `design.md`,
`proposed_adrs`), spec sections, and — when the project configures test levels — level
definitions, the derive map, seams, and the `LEVELS.md` doctrine path.

Return per the protocol's ````result` block.
```

#### 3.4 card-designer.md

**File:** `plugins/kanban-flow/.opencode/agents/card-designer.md`

Find:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.
Then load and execute the **`design-card`** skill.

Your dispatch names your mode: **Fresh** (produce the design from scratch) or **Design-PR
comment rework** (address human review comments on an open design PR). The skill handles both
modes, the 7-step design procedure (scope → approach → interfaces → data flow → task list →
test strategy → cite sources), the design heuristics, the test levels block generation, and the
return format with `phase_doc` = `design.md` section structure.

You always return `gate: design` — the orchestrator applies the gate policy. Return per the
protocol's ````result` block; also record every proposed ADR in `design.md`'s `## Proposed
ADRs` section (the durable copy the checker verdicts against).
```

Replace with:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.

Your dispatch names your mode: **Fresh** (produce the design from scratch) or **Design-PR
comment rework** (address human review comments on an open design PR).

You always return `gate: design` — the orchestrator applies the gate policy. Also record every
proposed ADR in `design.md`'s `## Proposed ADRs` section (the durable copy the checker
verdicts against). Return per the protocol's ````result` block.
```

#### 3.5 card-implementer.md

**File:** `plugins/kanban-flow/.opencode/agents/card-implementer.md`

Find:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.
Then load and execute the **`implement-card`** skill.

Your dispatch names your mode:
- **Fresh** — execute the design task list from the top.
- **Rework** — fix blocking findings from the tester, reviewer, or failing CI.
- **PR-comment** — address every human-authored comment from an open PR.

**When something blocks you — a finding that reveals the design is wrong, a comment you cannot
do as asked, a task needing files outside the design's list — stop and return `status: blocked`
with the evidence. Never improvise a redesign or expand scope.**

The skill handles the TDD loop per mode (including CI reproduction and push-on-rework), craft
heuristics, and the return format with `phase_doc` = `implement.md` section variants (including
`## Rework` and `## PR comments addressed`).

Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.

Your dispatch names your mode:
- **Fresh** — execute the design task list from the top.
- **Rework** — fix blocking findings from the tester, reviewer, or failing CI.
- **PR-comment** — address every human-authored comment from an open PR.

**When something blocks you — a finding that reveals the design is wrong, a comment you cannot
do as asked, a task needing files outside the design's list — stop and return `status: blocked`
with the evidence. Never improvise a redesign or expand scope.**

Return per the protocol's ````result` block.
```

#### 3.6 card-intake-checker.md

**File:** `plugins/kanban-flow/.opencode/agents/card-intake-checker.md`

Find:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`. Then load and execute the **`intake-check`** skill.

Your dispatch gives you the proposed cards, the milestone plan, the existing board, the
requirement(s) in scope, `spec_path`, and `size_limit` / `size_exclude`. The skill handles the
Walk (behaviour mapping, AC verification, dependency graph construction, vertical-slice check,
and size estimation per `_method.md`'s appendix), verdict logic, and the return format with the
intake check report persisted to `<board_dir>/intake-checks/`.

Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`.

Your dispatch gives you the proposed cards, the milestone plan, the existing board, the
requirement(s) in scope, `spec_path`, and `size_limit` / `size_exclude`.

Return per the protocol's ````result` block.
```

#### 3.7 card-lens-reviewer.md

**File:** `plugins/kanban-flow/.opencode/agents/card-lens-reviewer.md`

Find:
```
Read `AGENT-PROTOCOL.md` (Doctrine included), then the repo's `PROTOCOL-ADDENDUM.md` if
present, and obey both. Then load and execute the **`lens-review`** skill — it handles both
**whole-diff mode** (the normal panel: map pass, line pass through the lens's Walk) and
**slice mode** (when your dispatch carries a slice number: scope to slice paths, answer the
two carve-check questions).

Your dispatch provides the absolute paths to `.opencode/doctrine/lenses/_shared.md` and your
lens file `.opencode/doctrine/lenses/<lens>.md`. The skill's procedure is the lens file's Walk;
your lens file's **Example finding** is the calibration bar. Do not read other lenses' files.

Never write files, never touch GitHub, never fix the code — you review; the implementer fixes.
Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md` (Doctrine included), then the repo's `PROTOCOL-ADDENDUM.md` if
present, and obey both.

Your dispatch provides the absolute paths to `.opencode/doctrine/lenses/_shared.md` and your
lens file `.opencode/doctrine/lenses/<lens>.md`. Your lens file's **Example finding** is the
calibration bar. Do not read other lenses' files.

Never write files, never touch GitHub, never fix the code — you review; the implementer fixes.
Return per the protocol's ````result` block.
```

#### 3.8 card-slice-checker.md

**File:** `plugins/kanban-flow/.opencode/agents/card-slice-checker.md`

Find:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`. Then load and execute the **`slice-check`** skill.

Your dispatch provides `card.md`, `slice.md`, the slicer's `proposed_cards` /
`dependents_rewire` / `estimated_lines`, the card's dependents, the spec at `spec_path`, and
`MILESTONES.md`. The skill handles the derive-before-reading procedure, the independent size
estimate (per `_method.md`'s appendix), the SLC-* criteria, and the return format with
`phase_doc` = `slice-check.md`.

Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`.

Your dispatch provides `card.md`, `slice.md`, the slicer's `proposed_cards` /
`dependents_rewire` / `estimated_lines`, the card's dependents, the spec at `spec_path`, and
`MILESTONES.md`.

Return per the protocol's ````result` block.
```

#### 3.9 card-slicer.md

**File:** `plugins/kanban-flow/.opencode/agents/card-slicer.md`

Find:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.
Then load and execute the **`slice-card`** skill.

Your dispatch provides the card and lists its dependents (cards that `depends_on` it). The skill
handles the slice test, child card proposal and dependents rewire, the size estimation procedure
(with `size_limit` as a hard ceiling), the slicing heuristics, and the return format — including
the `proposed_cards` and `dependents_rewire` field shapes when splitting.

Return per the protocol's ````result` block. When splitting, populate `proposed_cards` and
`dependents_rewire` per the field shapes defined in the skill.
```

Replace with:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.

Your dispatch provides the card and lists its dependents (cards that `depends_on` it).

Return per the protocol's ````result` block. When splitting, populate `proposed_cards` and
`dependents_rewire` per the field shapes defined in `AGENT-PROTOCOL.md`.
```

#### 3.10 card-split-checker.md

**File:** `plugins/kanban-flow/.opencode/agents/card-split-checker.md`

Find:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`. Then load and execute the **`split-check`** skill.

Your dispatch names the **original branch** and provides `split.md`, `design.md`,
`implement.md`, `review.md`, and `size_limit` / `size_exclude`. The skill handles the ground
truth derivation (every diff names the original branch with `--no-renames`), the SPL-* criteria
(including the set-equality computation for `SPL-NO-LOSS` and the `SPL-GREEN` evidence
judgment), refusal checking, and the return format with `phase_doc` = `split-check.md` including
the coverage reconciliation section.

Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md` (Doctrine), then the repo's `PROTOCOL-ADDENDUM.md` if present, and
`KNOWLEDGE.md`.

Your dispatch names the **original branch** and provides `split.md`, `design.md`,
`implement.md`, `review.md`, and `size_limit` / `size_exclude`.

Return per the protocol's ````result` block.
```

#### 3.11 card-tester.md

**File:** `plugins/kanban-flow/.opencode/agents/card-tester.md`

Find:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.
Then load and execute the **`test-card`** skill.

When your dispatch carries level commands, it also provides the
`.opencode/doctrine/testing/LEVELS.md` and `.opencode/doctrine/testing/DIAGNOSIS.md` doctrine
paths — the skill reads them when present. The skill handles the gate sequence (suite →
coverage → property tests → lint/types → test levels), the test-level environment lifecycle
with trap-guarded teardown, blocker classification per `DIAGNOSIS.md`, and the return format
with `phase_doc` = `test.md` (≤80 lines).

Return per the protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.

When your dispatch carries level commands, it also provides the
`.opencode/doctrine/testing/LEVELS.md` and `.opencode/doctrine/testing/DIAGNOSIS.md` doctrine
paths.

Return per the protocol's ````result` block.
```

#### 3.12 pr-splitter.md

**File:** `plugins/kanban-flow/.opencode/agents/pr-splitter.md`

Find:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.
Then load and execute the **`carve-pr`** skill.

Your dispatch names the original branch. You carve code the lens panel already approved — not a
second chance to change it. The skill enforces the three inviolable rules (named branch,
`--no-renames` on every `--name-status`, throwaway worktree only), handles the inventory →
carve → bootstrap → prove-green workflow, the refusal path, and the return format with
`phase_doc` = `split.md` sections.

You create **no branches, no lasting worktrees, no commits, no PRs, and touch no GitHub.**
`card-deliverer` opens the PRs, one per slice, after `card-split-checker` passes. Return per the
protocol's ````result` block.
```

Replace with:
```
Read `AGENT-PROTOCOL.md`, then the repo's `PROTOCOL-ADDENDUM.md` if present, and obey both.

Your dispatch names the original branch. You carve code the lens panel already approved — not a
second chance to change it.

You create **no branches, no lasting worktrees, no commits, no PRs, and touch no GitHub.**
`card-deliverer` opens the PRs, one per slice, after `card-split-checker` passes. Return per the
protocol's ````result` block.
```

---

### 4. File NOT changed

**`plugins/kanban-flow/.opencode/agents/pump-gate.md`** — unchanged. pump-gate was already
decoupled (it never referenced a skill).

---

## Verification checklist

After applying all edits, confirm:

- [ ] `grep -r "load and execute" plugins/kanban-flow/.opencode/agents/` returns **0 matches** — no agent still names its skill.
- [ ] `grep -r "The skill handles" plugins/kanban-flow/.opencode/agents/` returns **0 matches** — no agent still describes its skill.
- [ ] The orchestrator dispatch table has a `skill` column with 14 rows and all 12 skill names appear.
- [ ] `INTAKE.md` line ~103 includes "Load and execute the \`intake-check\` skill."
- [ ] `grep -ci "load and execute" plugins/kanban-flow/.opencode/skills/kanban-orchestrator/SKILL.md` returns **1** — only the one injection instruction (the injected text is capitalized "Load and execute", so match case-insensitively).
- [ ] `wc -l` on each agent file shows it shrank by 2–5 lines.
- [ ] `pump-gate.md` has zero diff (`git diff plugins/kanban-flow/.opencode/agents/pump-gate.md` is empty).
- [ ] Every skill directory under `.opencode/skills/` still exists and its SKILL.md is untouched (zero diff on skills).

## Agent→skill mapping reference

For troubleshooting or future dispatch-table additions, here is the complete mapping:

| Agent | Skill |
|---|---|
| card-slicer | slice-card |
| card-slice-checker | slice-check |
| card-designer | design-card |
| card-design-checker | design-check |
| card-implementer | implement-card |
| card-tester | test-card |
| card-lens-reviewer | lens-review |
| pr-splitter | carve-pr |
| card-split-checker | split-check |
| card-deliverer | deliver-pr |
| card-deliver-checker | deliver-check |
| card-intake-checker | intake-check |

Skills are at `plugins/kanban-flow/.opencode/skills/<name>/SKILL.md`.
The orchestrator owns the wiring via its dispatch table.
`INTAKE.md` owns the wiring for `card-intake-checker`.

---

## Design rationale

- **Agents = roles.** An agent is a persona, permissions set, and model pinning. It expects a
  procedure to arrive at dispatch time but never knows which one. This makes agents reusable
  — the same agent could load different skills in different contexts without changing its
  definition.

- **Skills = recipes.** A skill is a standalone procedure. It doesn't know which agent loads
  it. This makes skills portable — a skill could be loaded by a different agent, or even
  invoked standalone, without modification.

- **Orchestrator = wiring.** The orchestrator (and INTAKE.md for the intake path) is the only
  place that knows which skill each agent needs. This is a single source of truth — changing
  the mapping means changing one table row, not two files.

- **Why not convention-based?** The agent→skill names diverge in 4 of 12 cases (pr-splitter →
  carve-pr, card-deliverer → deliver-pr, card-tester → test-card, card-lens-reviewer →
  lens-review). Imposing a naming convention would require renaming agents or skills, each
  with downstream impacts on the orchestrator and commands. The table column is explicit and
  costs one line per row.
