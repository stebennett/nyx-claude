# kanban-flow Review-Comment Addressing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the kanban-flow pump so that a completed GitHub review (or a `REVIEWED` comment) — not a per-comment 👍 — triggers addressing every human-authored PR comment, each answered with a commit-link reply.

**Architecture:** This is a documentation/doctrine change only — no code, no test runner. The edits live in the `kanban-flow` plugin's Markdown skill and agent files. The pump's PR-comment triage section (`kanban/SKILL.md` §6c) is the substantive change; the protocol, the two rework-mode agent descriptions, and the retro skill are updated to match. Verification is by `grep` assertions (old wording gone, new wording present) plus a final read-through, per this repo's convention (CLAUDE.md: "validated by installing the plugin, not by a test runner").

**Tech Stack:** Markdown, `git`, `grep`. No build tooling.

## Global Constraints

- **Plugin root:** all edited files are under `plugins/kanban-flow/`. Paths below are relative to the repo root `/Users/stevebennett/Code/nyx-claude`.
- **The pump is the sole PR-replier and sole writer of `card.md`/`BOARD.md`/`KNOWLEDGE.md`.** Phase agents never touch PR threads. Do not introduce any edit that has an agent reply to, resolve, or react to a comment.
- **Panel `[lens]` comments stay 👍-gated.** Only the human's *own* comments become auto-actioned. Do not remove 👍 semantics for panel comments (`REVIEW-LENSES.md` is intentionally unchanged).
- **`{gh_command}`, `{owner}`, `{repo}`, `{n}` are doctrine placeholders** — keep them verbatim as written in the surrounding text; do not resolve them to concrete values.
- **Reply marker format is exactly** `[kanban] Addressed in <commit-url> — <one-line explanation>` where `<commit-url>` is the full `https://github.com/{owner}/{repo}/commit/<sha>`, and `[kanban] Not actioned — <reason>` for non-actionable items. The `[kanban]` prefix is the idempotent addressed-marker — never change the prefix.
- **RTK proxy:** if an `rtk`-wrapped `grep`/`git` rejects a flag, fall back to `rtk proxy <command>`.
- **Commits:** Conventional Commits, ending with the trailer `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Work happens on `main` (a docs change consistent with how the pump commits doctrine); no branch required unless the executor prefers one.

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `plugins/kanban-flow/skills/kanban/SKILL.md` | The pump doctrine — §6 owns the PR lifecycle | Rewrite §6c (triage→address loop); touch §6 heading, §6b closing line, Rules bullet |
| `plugins/kanban-flow/templates/AGENT-PROTOCOL.md` | Shared doctrine handed to every phase agent | Reword the PR-comment dispatch description and the "belongs to the human" line |
| `plugins/kanban-flow/agents/card-implementer.md` | Implementer agent — PR-comment mode | Reword the PR-comment dispatch-mode bullet |
| `plugins/kanban-flow/agents/card-designer.md` | Designer agent — design-PR rework mode | Reword the design-PR rework bullet |
| `plugins/kanban-flow/skills/retro/SKILL.md` | Retro skill — mines human input channels | Add the review-complete signal + addressed/not-actioned outcomes as a mined channel |

**Not changed (verified during planning):** `README.md` (does not describe the triage flow), `templates/REVIEW-LENSES.md` (panel 👍 semantics unchanged), `skills/adr/SKILL.md` (its 👍 references are unrelated to PR triage).

---

## Task 1: Rewrite the pump's address loop (`kanban/SKILL.md`)

This is the substantive change. All four edits are in one file and change together.

**Files:**
- Modify: `plugins/kanban-flow/skills/kanban/SKILL.md` (§6 heading line 94, §6b closing line 122, §6c lines 124–131, Rules bullet line 143)

**Interfaces:**
- Produces (referenced by Tasks 2–4): the reply marker strings `[kanban] Addressed in <commit-url> — <explanation>` and `[kanban] Not actioned — <reason>`; the term "review-complete signal" (a submitted review **or** a `REVIEWED` comment); the actionable-set rule "every human-authored comment + any 👍'd panel comment".

- [ ] **Step 1: Update the §6 heading**

Replace (line 94):
```
## 6. PR open — CI gate, panel, 👍 triage
```
with:
```
## 6. PR open — CI gate, panel, review-complete addressing
```

- [ ] **Step 2: Update the §6b closing line**

Replace (line 122, the final sentence of §6b — match on the tail):
```
route `knowledge`, commit `chore(kanban): CARD-NNN PR review seeded`, and tell the driver the PR awaits their 👍 triage.
```
with:
```
route `knowledge`, commit `chore(kanban): CARD-NNN PR review seeded`, and tell the driver the PR awaits their review (👍 any panel comment to have it addressed too).
```

- [ ] **Step 3: Rewrite §6c (lines 124–131)**

Replace the entire block from `### 6c. Triage loop` through the paragraph ending `merge the implementation PR.`:
```
### 6c. Triage loop (every pump per open PR, CI green)
The human marks any comment **actionable** with a 👍 reaction; everything else is theirs to answer or ignore — never act without the 👍.
1. Fetch inline review comments: `{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments` (reactions included).
2. Actionable = 👍 **and** no `[kanban]` reply in its thread yet (the reply is the idempotent addressed-marker).
3. **Implementation PR:** dispatch `card-implementer` in PR-comment mode with the actionable comments verbatim (id, path, line, body) — it fixes exactly those (test-first for behaviour), runs the fast gates, commits, pushes. **Design PR:** re-dispatch `card-designer` with the comments verbatim; commit its revised `design.md` (and any superseding ADR proposals via the `adr` routing) to the design branch and push.
4. Reply to each addressed comment (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments/{id}/replies`) with `[kanban] Addressed in <short-sha> — <one line>`. **Never resolve threads**, never approve or dismiss — resolution and the merge are the human's.

PR-comment fixes are human-directed and don't consume the `reworks` budget. Merge detection stays with Reconcile (Section 0). A healthy card needs exactly three human actions: merge the design PR, optional 👍 triage, merge the implementation PR.
```
with:
```
### 6c. Address loop (every pump per open PR, CI green)
Nothing is actioned until the human signals the review is **complete**; then every comment they authored is addressed, plus any panel comment they 👍'd. Never act before the signal.

1. **Detect the review-complete signal** — either one satisfies it:
   - a **submitted review** by a non-app user (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/reviews`) with state `COMMENTED` / `CHANGES_REQUESTED` / `APPROVED` (`PENDING` never counts); or
   - a top-level PR comment whose trimmed body equals `REVIEWED` (case-insensitive) by a non-app user (`{gh_command} api repos/{owner}/{repo}/issues/{n}/comments`).
   No signal → do nothing on this PR this pump; report "awaiting review". The pump loop is the wait.

2. **Assemble the actionable set** — skip any item already carrying a `[kanban]` reply/marker (that reply is the idempotent addressed-marker):
   - **every human-authored inline comment** (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments`) — no 👍 needed;
   - **each human-submitted review's summary body** when non-empty (idempotency keyed to the review id via a top-level `[kanban]` marker naming the review);
   - **panel `[lens]` comments only if 👍'd**.
   "App" = the identity the flow posts as (its comments carry the `[lens]`/`[kanban]` prefix or its App login); everything else is human. Exclude the `REVIEWED` comment itself. A submitted review's inline comments and body are one atomic unit; for loose inline comments cleared by a `REVIEWED` comment, take those created at/before the newest `REVIEWED` timestamp.

3. **Dispatch. Implementation PR:** dispatch `card-implementer` in PR-comment mode with the items verbatim (id, path, line, body; review-body items flagged as summary) — it fixes exactly those (test-first for behaviour), runs the fast gates, commits (one commit per comment or a tight cluster), pushes. **Design PR:** re-dispatch `card-designer` with the items verbatim; commit its revised `design.md` (and any superseding ADR proposals via the `adr` routing) to the design branch and push.

4. **Reply once per item** — in its thread (inline, `{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments/{id}/replies`) or as a top-level `[kanban]` comment (review body): `[kanban] Addressed in <commit-url> — <one-line explanation>`, where `<commit-url>` is the full `https://github.com/{owner}/{repo}/commit/<sha>`. For an item the agent returned in `blockers` (a question, or a change it judged wrong/infeasible), reply `[kanban] Not actioned — <reason>` and surface it to the driver. Every item in the set gets exactly one reply. **Never resolve threads**, never approve or dismiss — resolution and the merge are the human's.

These fixes are human-directed and don't consume the `reworks` budget. Merge detection stays with Reconcile (Section 0). A healthy card needs exactly three human actions: merge the design PR, complete a review (or comment `REVIEWED`), merge the implementation PR.
```

- [ ] **Step 4: Update the Rules bullet (line 143)**

Replace:
```
- PR comments are actioned only on the human's 👍; the system replies `[kanban] Addressed in <sha>` but never resolves threads, never approves, never dismisses. Panel experts post `COMMENT` reviews only, on implementation PRs only.
```
with:
```
- PR comments are actioned only after a review-complete signal (a submitted review or a `REVIEWED` comment): then every human-authored comment is addressed, plus any 👍'd panel comment. The system replies `[kanban] Addressed in <commit-url>` (or `[kanban] Not actioned — <reason>`) but never resolves threads, never approves, never dismisses. Panel experts post `COMMENT` reviews only, on implementation PRs only.
```

- [ ] **Step 5: Verify the edits landed and no stale wording remains**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF '### 6c. Address loop' plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'review-complete signal' plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'REVIEWED' plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'Not actioned' plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'Addressed in <commit-url>' plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: each prints at least one match.

Run the stale-wording check:
```bash
grep -nF 'Triage loop' plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'Addressed in <short-sha>' plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'optional 👍 triage' plugins/kanban-flow/skills/kanban/SKILL.md
grep -nF 'awaits their 👍 triage' plugins/kanban-flow/skills/kanban/SKILL.md
```
Expected: each prints **no** matches (empty output).

- [ ] **Step 6: Commit**

```bash
git add plugins/kanban-flow/skills/kanban/SKILL.md
git commit -m "feat(kanban-flow): gate PR-comment addressing on a review-complete signal

Replace §6c's per-👍 triage with: address every human-authored comment
(plus 👍'd panel comments) once the human submits a review or comments
REVIEWED; reply per item with a commit link, or 'Not actioned — reason'.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: Update the shared protocol (`AGENT-PROTOCOL.md`)

**Files:**
- Modify: `plugins/kanban-flow/templates/AGENT-PROTOCOL.md` (PR-comment dispatch lines 15–17, boundary line 42)

**Interfaces:**
- Consumes (from Task 1): the actionable-set rule "every human-authored comment + any 👍'd panel comment"; the term "review-complete".

- [ ] **Step 1: Reword the PR-comment dispatch description**

Replace (lines 15–17):
```
- A **PR-comment** dispatch (implement phase: implementation-PR comments; design phase:
  design-PR comments) carries 👍-triaged PR comments (id, path, line, body); address exactly those
  and never touch the comment threads — the orchestrator replies and the human resolves.
```
with:
```
- A **PR-comment** dispatch (implement phase: implementation-PR comments; design phase:
  design-PR comments) carries the review-complete comment set (id, path, line, body; review-body
  items flagged as summary) — every human-authored comment plus any 👍'd panel comment; address
  exactly those and never touch the comment threads — the orchestrator replies (with a commit link)
  and the human resolves.
```

- [ ] **Step 2: Reword the boundary line (line 42)**

Replace:
```
  `[lens]`-prefixed inline comments. No agent ever approves, requests changes, replies to, resolves,
  or reacts to PR threads — triage (👍) and resolution belong to the human.
```
with:
```
  `[lens]`-prefixed inline comments. No agent ever approves, requests changes, replies to, resolves,
  or reacts to PR threads — the review-complete signal, 👍 triage of panel comments, and resolution
  belong to the human.
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF 'review-complete comment set' plugins/kanban-flow/templates/AGENT-PROTOCOL.md
grep -nF 'the review-complete signal, 👍 triage of panel comments' plugins/kanban-flow/templates/AGENT-PROTOCOL.md
grep -nF '👍-triaged PR comments' plugins/kanban-flow/templates/AGENT-PROTOCOL.md
```
Expected: the first two print a match; the third prints **no** matches.

- [ ] **Step 4: Commit**

```bash
git add plugins/kanban-flow/templates/AGENT-PROTOCOL.md
git commit -m "docs(kanban-flow): protocol — PR-comment dispatch carries the review-complete set

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: Update the rework-mode agent descriptions (`card-implementer.md`, `card-designer.md`)

Both files describe what their PR/design-rework dispatch receives; they change together.

**Files:**
- Modify: `plugins/kanban-flow/agents/card-implementer.md` (PR-comment mode, line 17)
- Modify: `plugins/kanban-flow/agents/card-designer.md` (design-PR rework, line 16)

**Interfaces:**
- Consumes (from Task 1): "every human-authored comment + any 👍'd panel comment"; the orchestrator replies with a commit link.

- [ ] **Step 1: Reword the implementer's PR-comment mode bullet**

Replace (line 17, the whole bullet):
```
- **PR-comment:** the dispatch prompt includes 👍-triaged PR comments (id, path, line, body). Fix exactly those — test-first for behaviour changes, direct edit for nits — run the fast test/lint gates, commit, and `git push` the card branch (it already tracks the remote). Never touch the PR threads themselves: no replies, no resolving, no reactions — the orchestrator replies and the human resolves. If a comment is wrong or can't be done as asked, don't improvise: return it in `blockers` with your reasoning so the orchestrator can surface it.
```
with:
```
- **PR-comment:** the dispatch prompt includes the review-complete comment set (id, path, line, body; review-body items flagged as summary) — every human-authored comment plus any 👍'd panel comment. Fix exactly those — test-first for behaviour changes, direct edit for nits — run the fast test/lint gates, commit, and `git push` the card branch (it already tracks the remote). Never touch the PR threads themselves: no replies, no resolving, no reactions — the orchestrator replies (with a commit link) and the human resolves. If a comment is wrong or can't be done as asked, don't improvise: return it in `blockers` with your reasoning so the orchestrator can surface it (it replies `Not actioned — <reason>`).
```

- [ ] **Step 2: Reword the designer's design-PR rework bullet**

Replace (line 16, the whole bullet):
```
- **Design-PR comment rework:** the dispatch carries 👍-triaged comments from the open design PR (and/or a docs-CI failure). Revise `design.md` to address exactly those — return the full updated doc as `phase_doc`; a comment that overturns a decision recorded in an ADR gets a superseding `proposed_adrs` entry, not a silent edit. The orchestrator commits, pushes, and replies to the threads.
```
with:
```
- **Design-PR comment rework:** once the human completes their review (or comments `REVIEWED`), the dispatch carries every human-authored comment from the open design PR (design PRs have no review panel, so nothing is 👍-gated), and/or a docs-CI failure. Revise `design.md` to address exactly those — return the full updated doc as `phase_doc`; a comment that overturns a decision recorded in an ADR gets a superseding `proposed_adrs` entry, not a silent edit. The orchestrator commits, pushes, and replies to the threads with a commit link.
```

- [ ] **Step 3: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF 'review-complete comment set' plugins/kanban-flow/agents/card-implementer.md
grep -nF 'the orchestrator replies (with a commit link)' plugins/kanban-flow/agents/card-implementer.md
grep -nF 'every human-authored comment from the open design PR' plugins/kanban-flow/agents/card-designer.md
grep -rnF '👍-triaged' plugins/kanban-flow/agents/
```
Expected: the first three print a match; the fourth (`👍-triaged` anywhere under `agents/`) prints **no** matches.

- [ ] **Step 4: Commit**

```bash
git add plugins/kanban-flow/agents/card-implementer.md plugins/kanban-flow/agents/card-designer.md
git commit -m "docs(kanban-flow): rework-mode agents receive the review-complete comment set

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: Add the review-complete signal to the retro's mined channels (`retro/SKILL.md`)

**Files:**
- Modify: `plugins/kanban-flow/skills/retro/SKILL.md` (channel-2 extract line 20, pattern bullet line 28, Rules line 55)

**Interfaces:**
- Consumes (from Task 1): the `[kanban] Addressed in <commit>` and `[kanban] Not actioned — <reason>` reply markers; the review-complete signal (submitted review or `REVIEWED`).

- [ ] **Step 1: Extend channel 2's extract list (line 20)**

In line 20, replace the fragment:
```
(c) the human's **own** review comments — each one is something no agent caught; (d) everything on the **design PR**
```
with:
```
(c) the human's **own** review comments — each one is something no agent caught — and, per comment, whether the orchestrator addressed it (`[kanban] Addressed in <commit>`) or replied `[kanban] Not actioned — <reason>` (a `Not actioned` reply is a human instruction the machine could not carry out — a gap); (d) everything on the **design PR**
```

Then, in the same line, replace the fragment:
```
(e) human review verdicts and any PR closed unmerged.
```
with:
```
(e) human review verdicts, the review-complete signal (a submitted review or a `REVIEWED` comment), and any PR closed unmerged.
```

- [ ] **Step 2: Extend the "what did the human catch" pattern bullet (line 28)**

Replace the end of line 28:
```
a design objection surfacing at PR time → the design gate policy or designer prompt let it through too late.
```
with:
```
a design objection surfacing at PR time → the design gate policy or designer prompt let it through too late. A comment the orchestrator replied `Not actioned` to is doubly telling — the machine both missed it upstream and could not fix it on request.
```

- [ ] **Step 3: Update the "no human input left behind" Rules line (line 55)**

Replace:
```
- No human input left behind: all five channels (feedback.md, PR 👍/ignored, PR pushback replies, human's own PR comments incl. design-doc-anchored ones, gate outcomes) read for every covered card, with coverage recorded in RETRO.md.
```
with:
```
- No human input left behind: all channels (feedback.md, PR 👍/ignored panel comments, PR pushback replies, the human's own PR comments incl. design-doc-anchored ones and whether each was `Addressed` or `Not actioned`, the review-complete signal, gate outcomes) read for every covered card, with coverage recorded in RETRO.md.
```

- [ ] **Step 4: Verify**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -nF 'the review-complete signal (a submitted review or a `REVIEWED` comment)' plugins/kanban-flow/skills/retro/SKILL.md
grep -nF 'Not actioned` reply is a human instruction' plugins/kanban-flow/skills/retro/SKILL.md
grep -nF 'doubly telling' plugins/kanban-flow/skills/retro/SKILL.md
grep -nF 'all five channels' plugins/kanban-flow/skills/retro/SKILL.md
```
Expected: the first three print a match; the fourth (`all five channels`) prints **no** matches.

- [ ] **Step 5: Commit**

```bash
git add plugins/kanban-flow/skills/retro/SKILL.md
git commit -m "docs(kanban-flow): retro mines the review-complete signal and Not-actioned replies

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: Whole-plugin consistency sweep

Catch any triage/👍 reference the per-file tasks missed, and read the changed doctrine end-to-end for coherence.

**Files:**
- Read-only review of `plugins/kanban-flow/` (no edits unless a stale reference is found)

- [ ] **Step 1: Sweep for stale triage vocabulary across the whole plugin**

Run:
```bash
cd /Users/stevebennett/Code/nyx-claude
grep -rnF '👍-triaged' plugins/kanban-flow/
grep -rniF 'triage loop' plugins/kanban-flow/
grep -rnF 'Addressed in <short-sha>' plugins/kanban-flow/
grep -rnF 'Addressed in <sha>' plugins/kanban-flow/
```
Expected: all four print **no** matches. If any match appears, it is a reference the tasks missed — reword it to match Task 1's model (review-complete signal; commit-link reply), commit with a `docs(kanban-flow): …` message + the standard trailer, and re-run.

- [ ] **Step 2: Confirm the deliberately-unchanged files still hold panel-👍 semantics**

Run:
```bash
grep -nF '👍' plugins/kanban-flow/templates/REVIEW-LENSES.md
```
Expected: at least one match (panel comments are still 👍-decided). This confirms we did not accidentally strip panel triage.

- [ ] **Step 3: Read the changed §6c end-to-end**

Read `plugins/kanban-flow/skills/kanban/SKILL.md` §6 (heading through the Rules bullet) as a fresh reviewer. Confirm: the trigger (6c step 1), the actionable set (step 2), dispatch (step 3), and reply (step 4) form a coherent loop; the "three human actions" sentence matches the new signal; no dangling reference to 👍-only triage. If anything reads inconsistently, fix inline and commit.

- [ ] **Step 4: Final verification against the spec's success criteria**

Confirm by inspection that the doctrine now supports each success criterion from `docs/superpowers/specs/2026-07-08-kanban-review-comment-addressing-design.md`:
- human comments addressed with a commit-link reply, or answered `Not actioned` — §6c steps 2–4;
- panel `[lens]` comments still require 👍 — §6c step 2 + REVIEW-LENSES unchanged;
- re-running the pump does not double-address — the `[kanban]` marker skip in §6c step 2;
- works on design and implementation PRs — §6c step 3 both branches.

No commit needed unless Step 1 or 3 found a fix.

---

## Self-Review (completed during planning)

**Spec coverage:**
- Trigger (submitted review OR `REVIEWED`) → Task 1 Step 3 (6c step 1). ✓
- Actionable set (human comments auto; review body; panel 👍-gated; app-vs-human; idempotent marker; timing) → Task 1 Step 3 (6c step 2). ✓
- Address & reply (dispatch shape; commit-link reply; `Not actioned`; one reply per item; no resolve/approve) → Task 1 Step 3 (6c steps 3–4). ✓
- Both design & implementation PRs → Task 1 (6c step 3 both branches) + Task 3 (designer). ✓
- Decisions 1–3 (APPROVED-with-comments; re-arm via markers; `Not actioned` replies) → Task 1 Step 3. ✓
- Files changed: SKILL.md → T1; AGENT-PROTOCOL.md → T2; card-implementer/designer → T3; retro → T4. README/REVIEW-LENSES/adr correctly out of scope → noted in File Structure + Task 5. ✓

**Placeholder scan:** No `TBD`/`TODO`/"handle edge cases"/"similar to Task N" — every edit gives exact old→new text. The `{gh_command}`/`<commit-url>`/`<sha>` tokens are intentional doctrine placeholders, preserved verbatim per Global Constraints. ✓

**Consistency:** The reply marker `[kanban] Addressed in <commit-url> — <explanation>` and `[kanban] Not actioned — <reason>`, the term "review-complete signal", and "every human-authored comment plus any 👍'd panel comment" are used identically across Tasks 1–4. ✓
