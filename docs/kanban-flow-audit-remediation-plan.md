# Kanban Flow Audit — Remediation Plan

## Summary

The audit found **3 errors**, **22 warnings**, and **4 notes** across the kanban-flow plugin.  
This plan provides detailed steps to resolve every issue, ordered by severity then dependency.

---

## ERROR 1: BOARD.md Has Old Phase Columns

**File:** `doctrine/board/BOARD.md`  
**Lines:** 10, 16, 18

### Current State
```
## Slice
## Test
## Review
```

### Required State
```
## Spec
## Verify
## Accept
```

### Fix
Replace the three column headers to match the new state machine:
- `## Slice` → `## Spec`
- `## Test` → `## Verify`
- `## Review` → `## Accept`

### Related
The conductor agent's state machine lists columns as `Spec, Design, Implement, Verify, Accept, Deliver, Blocked, Done, Split, Superseded`. The board scaffolding must match.

---

## ERROR 2: deliver-pr/SKILL.md References "orchestrator" Instead of "conductor"

**File:** `skills/deliver-pr/SKILL.md`  
**Lines:** 44–46

### Current State
```
Only the orchestrator tears it down once the last slice merges.
```

### Required State
```
Only the conductor tears it down once the last slice merges.
```

### Fix
Replace `orchestrator` with `conductor` on lines 44–46.

---

## ERROR 3: migrate.md Misrepresents conductor as "cheap haiku agent"

**File:** `commands/migrate.md`  
**Lines:** 128–132

### Current State
```
- *0.5 → 0.6:* `pump_gate: on` — the pre-flight gate switch (command §0.0). `on` is the new
  default and changes no card outcome: each pump first runs the cheap `conductor` haiku agent to
  decide idle-vs-run, so a quiet board stops before loading the board instead of
  after. Say that `off` bypasses the gate and reconciles directly (a debugging escape hatch), and
  that the gate writes no state and errs toward running.
```

### Issues
- `conductor` is sonnet, not haiku. The old `pump-gate` was haiku.
- The conductor does much more than "decide idle-vs-run" — it runs the full pump cycle.
- The `pump_gate` config option and its behavior no longer exist in the new architecture.

### Fix
Replace the entire block. Since this is a migration document explaining a 0.5→0.6 delta, the migration description should note that pump_gate was replaced by the conductor's §1 Pre-flight and the config option was removed:

```markdown
  - *0.5 → 0.6:* `pump_gate` — removed. The pre-flight gate was previously a separate
    `pump-gate` haiku agent. In the new architecture the **conductor** agent runs its own
    §1 Pre-flight check (fetch main, scan merges, probe open PRs) inline before loading
    the board. The `pump_gate` config key is no longer read — remove it from config.md.
    The conductor's pre-flight produces the same run-vs-idle decision without a separate
    agent dispatch.
```

---

## WARNING 1: Doc Name Inconsistencies — `test.md` vs `verify.md`

**Files affected:**
- `agents/conductor.md:63` — dispatch table uses `test.md` for verifier's output
- `agents/verifier.md:64` — phase_doc field shows `<test.md content>`

**Issue:** The AGENT-PROTOCOL convention is `{phase}.md` so the verifier should produce `verify.md`. The conductor dispatch table anchors on `test.md` which breaks this convention.

### Fix
1. **`agents/conductor.md`** — In the §4 Advance dispatch table, change:
   ```
   | verify | test.md | verifier | persist, fast-gate |
   ```
   to:
   ```
   | verify | verify.md | verifier | persist, fast-gate |
   ```
   Also update any other references to `test.md` in the conductor's gate logic, Council 2 inputs section, and state machine tables.

2. **`agents/verifier.md`** — Change the return section:
   ```
   phase_doc: <verify.md content>
   ```

3. **`doctrine/card-template.md`** — Change `test.md` → `verify.md` in the phase docs list.

4. **`doctrine/design-pr-template.md`** — If it references `test.md`, change to `verify.md`.

---

## WARNING 2: Doc Name Inconsistencies — `accept.md` vs `acceptance-review.md`

**Files affected:**
- `doctrine/card-template.md:40` — lists both `accept.md` and `acceptance-review.md`
- `commands/retro.md:19` — references `accept.md`

**Issue:** The spec and conductor consistently use `acceptance-review.md`. Some files use the shorter `accept.md` which could cause lookups to fail.

### Fix
1. **`doctrine/card-template.md:40`** — Remove `accept.md` from the phase docs list. The line becomes:
   ```
   Free-form context. Phase docs (design-spec.md, solution-review.md, design.md, implement.md, verify.md, acceptance-review.md, deliver-check.md, …) live beside this file…
   ```

2. **`commands/retro.md`** — Search for and replace any `accept.md` references with `acceptance-review.md`.

---

## WARNING 3: Doc Name Inconsistencies — `review.md` → `acceptance-review.md`

**Files affected:**
- `commands/retro.md:19` — references `review.md`
- `skills/carve-pr/SKILL.md:9` — "end of the review phase"
- `skills/lens-review/SKILL.md:63-64,74-76` — `phase: review`, "review phase", "test phase"

**Issue:** Old doc/phase names linger in now-active skill files.

### Fix
1. **`commands/retro.md`** — Replace `review.md` with `acceptance-review.md` and update any phase-doc lists in the retro-triage logic.

2. **`skills/carve-pr/SKILL.md`**:
   - Line 9: `"end of the review phase"` → `"when the acceptance gate passes"`
   - Line 101: `phase: review` → `phase: accept`

3. **`skills/lens-review/SKILL.md`**:
   - Line 63: `phase: review` → `phase: accept`
   - Lines 74-76: `"Council 2"` and `"test phase"` → `"verify phase"`
   - Line 64: `review.md` → `"the council's review section"` (lenses write into acceptance-review.md)

---

## WARNING 4: Old Phase Names in Inactive Skills

**Files:**
- `skills/slice-card/SKILL.md:13` — "slice phase"
- `doctrine/INTAKE.md:59-60,115` — "slice phase"
- `doctrine/checks/intake.md:26` — "skips the slice phase"
- `doctrine/checks/split.md:4` — "end of the review phase"

**Issue:** These files reference old phase concepts that don't exist in the new lifecycle.

### Fix
1. **`skills/slice-card/SKILL.md`** — Replace "slice phase" with "spec phase" since slicing is now part of the analyst's refinement work.

2. **`doctrine/INTAKE.md`** — Replace "skip the slice phase" with "skip spec phase" (the analyst self-checks replace the old slice phase).

3. **`doctrine/checks/intake.md`** — Same change: "skips the spec phase."

4. **`doctrine/checks/split.md`** — Replace "end of the review phase" with "end of the accept phase."

---

## WARNING 5: AGENT-PROTOCOL.md References "orchestrator" and "slice phase"

**File:** `doctrine/AGENT-PROTOCOL.md`  
**Lines:** 3, 7, 106

### Current State
- Line 3: "read by the `/kanban` orchestrator"
- Line 7: "shared contract between the `/kanban` orchestrator and the phase agents"
- Line 106: "(slice phase only)"

### Fix
1. Line 3: `"read by the **conductor** agent"`
2. Line 7: `"shared contract between the **conductor** and the other agents"`
3. Line 106: `(spec phase only)` or `(analyst's refinement phase only)`

---

## WARNING 6: card-template.md Phase Doc List Is Inconsistent

**File:** `doctrine/card-template.md:40`  
**Current:** Lists every phase doc including `spec.md`, `accept.md`, `verify.md`, `acceptance-review.md`, etc. Some are old names, some are new.

### Fix
Replace line 40 with a clean canonical list matching the conductor's sole-writer invariant:
```
Free-form context. Phase docs written to the card directory (design-spec.md, solution-review.md,
acceptance-review.md) and to the worktree branch (design.md, implement.md, verify.md,
security-audit.md, deliver-check.md) live beside this file. Split lineage is recorded here as prose
(e.g. "Split out of CARD-NNN" on a child, "Split into CARD-XXX, CARD-YYY" on a `split` parent).
```
Also update the frontmatter comment for `design_pr_url` on line 14: `slice.md + design.md` → `design-spec.md + solution-review.md + design.md`

---

## WARNING 7: Return Contract — Missing `phase`, `card`, `gate` Fields

**Files affected:** All 7 phase agent files (analyst, designer, architect, builder, verifier, security-analyst, pilot)

**Issue:** AGENT-PROTOCOL.md requires `phase`, `card`, `gate` in every result block. None of the new agents include these fields.

**Assessment:** In the old system the orchestrator injected these into the dispatch and agents returned them verbatim. In the new system the conductor knows the card and phase from its dispatch table, so these fields are redundant for conductor-side processing. Either:
- (A) Update AGENT-PROTOCOL.md to remove these requirements for agents (since conductor tracks state), or
- (B) Add the fields to each agent's return format for protocol compliance.

**Recommendation:** Option A — update AGENT-PROTOCOL.md. Remove `phase`, `card`, `gate` from the required result block and add a note that the conductor tracks these externally. This matches the new architecture where the conductor is the sole state manager.

---

## WARNING 8: Hardcoded Skill Names in Agent Files

**Files:** `designer.md:29`, `architect.md:47`, `builder.md:33`

**Current:**
- designer: "Invoke board-knowledge for relevant UX gotchas or conventions"
- architect: "Invoke board-knowledge for gotchas and conventions"
- builder: "Invoke relevant skills (test-driven-development, board-knowledge)"

**Issue:** The spec says agents should discover skills autonomously. Hardcoding skill names couples agents to the skill directory structure.

### Fix
Replace hardcoded skill references with behavioral descriptions:

1. **`designer.md:29`** — Change to:
   `Check project-specific conventions and gotchas before designing.`

2. **`architect.md:47`** — Change to:
   `Check project-specific conventions and gotchas before designing.`

3. **`builder.md:33`** — Change to:
   `Execute design task list TDD. Commit after each green task using Conventional Commits. Run project fast test/lint gates. Return implement.md.`

---

## WARNING 9: retro.md References Old Agent Name "slicer"

**File:** `commands/retro.md:51`

**Current:** References "slicer" (the old card-slicer agent)

### Fix
Replace "slicer" with "analyst" throughout the retro command. Also replace "intake" with "analyst" where it refers to the agent role in the estimation section.

---

## WARNING 10: lens-review/SKILL.md Phase References

**File:** `skills/lens-review/SKILL.md:74-76`

**Current:**
```
Lenses are used by Council 2 members (**architect**, **designer**, **pilot**) for full panel
review. The **verifier** also applies lenses in a testability-assessment capacity during the test
phase.
```

### Fix
```
Lenses are used by Council 2 members (**architect**, **designer**, **pilot**) for acceptance
review. The **verifier** also applies lenses in a testability-assessment capacity during the verify
phase.
```

---

## NOTE 1: migrate.md `status: review` Reference

**File:** `commands/migrate.md:107`

**Issue:** References `status: review` in legacy migration context. This is explaining old behavior, so it's acceptable. No change needed.

---

## NOTE 2: AGENT-PROTOCOL.md References "orchestrator owns them"

**File:** `doctrine/AGENT-PROTOCOL.md:30`

**Issue:** "The orchestrator owns them" — could say "conductor" for consistency but the generic term "orchestrator" describes the role, not the agent name. Acceptable.

---

## NOTE 3: Conductor Has Different Return Format

**File:** `agents/conductor.md`

**Issue:** The conductor uses `{pump_summary, cards_processed, gates, commits}` instead of the standard agent return format. This is by design — the conductor is a manager, not a phase agent. No change needed.

---

## NOTE 4: Retro Rework Fields Use Old Keys

**File:** `commands/retro.md:14`

**Issue:** `RETRO-INBOX.md` format references `{slice:0, design:1, implement:2, split:0, deliver:0}`. The `slice` key is from the old rework map. With the new lifecycle, the conductor uses `spec` instead of `slice` in the reworks map. This should be updated in the retro command and in the conductor's §0 reconcile procedure.

### Fix
1. **`commands/retro.md`** — Replace `slice:` with `spec:` in the RETRO-INBOX.md line format.
2. **`agents/conductor.md`** — Verify §0 Step 3 RETRO-INBOX append uses `spec:` (not `slice:`).
3. **`doctrine/card-template.md`** — The reworks map already uses `spec:` → verify consistency.

---

## Complete Execution Order

| Step | Issue(s) | Files | Dependency |
|------|----------|-------|------------|
| 1 | ERROR 1 | `doctrine/board/BOARD.md` | — |
| 2 | ERROR 2 | `skills/deliver-pr/SKILL.md` | — |
| 3 | ERROR 3 | `commands/migrate.md` | — |
| 4 | WARNING 1 | `conductor.md`, `verifier.md`, `card-template.md`, `design-pr-template.md` | Best done together (test.md → verify.md) |
| 5 | WARNING 2 | `card-template.md`, `retro.md` | After step 4 |
| 6 | WARNING 3 | `retro.md`, `carve-pr/SKILL.md`, `lens-review/SKILL.md` | After step 4 |
| 7 | WARNING 4 | `slice-card/SKILL.md`, `INTAKE.md`, `checks/intake.md`, `checks/split.md` | — |
| 8 | WARNING 5 | `AGENT-PROTOCOL.md` | — |
| 9 | WARNING 6 | `card-template.md` | After step 4 |
| 10 | WARNING 7 | `AGENT-PROTOCOL.md` | After step 8 |
| 11 | WARNING 8 | `designer.md`, `architect.md`, `builder.md` | — |
| 12 | WARNING 9 | `retro.md` | — |
| 13 | WARNING 10 | `lens-review/SKILL.md` | After step 6 |
| 14 | NOTE 4 | `retro.md`, `conductor.md`, `card-template.md` | After steps 4,12 |

### Verification After All Fixes

1. Grep for old agent names across `.opencode/` — zero matches outside kept files and deprecated orchestrator
2. Grep for old phase names (`test\.md`, `review\.md`, `slice phase`, `phase: review`, `phase: test`, `phase: slice`) — zero matches in active files
3. Verify BOARD.md columns match the conductor's state machine
4. Verify deliver-pr/SKILL.md uses "conductor" (not "orchestrator")
5. Verify migrate.md correctly describes the new architecture
6. Verify card-template.md phase docs list is canonical
7. Verify no agent files hardcode skill names
8. Verify reworks map keys are `spec:` (not `slice:`)
