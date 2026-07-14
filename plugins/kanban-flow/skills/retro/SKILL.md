---
name: retro
description: Continuous process improvement for a project's kanban-flow system. Mines done cards' phase docs and flow metrics (reworks, cycle time, gate revisions, blockers) for systemic patterns, distils them into KNOWLEDGE.md entries and concrete edits to the skills/agents/protocol, and ships approved process changes as a PR. Run every ~5 done cards or whenever flow feels wrong.
---

# /retro — process improvement loop

You close the loop the delivery system otherwise lacks: the phase docs record what actually happened on every card; you turn that record into changes that make the *next* cards cheaper, faster, and better. Improve the system, not the cards — individual code fixes belong on defect cards via `/refine`.

## 1. Gather evidence
For every card with `status: done` (and any long-`blocked` card) not covered by a previous retro (check `docs/cards/RETRO.md`), read:

**The system's trace:**
- `card.md` frontmatter metrics: `reworks` (the per-producer map — *which* producer burned loops is the signal, not the total), `started` → `delivered` elapsed, phase count, and **`estimated_lines` vs `actual_lines`**.
- The phase docs: `slice.md` … `deliver.md` — especially `## Rework` sections in `implement.md`, blocking findings in `review.md` (the lens panel's merged output), failures in `test.md`, and `## Deviations from design`.
- **The check docs — `slice-check.md`, `design-check.md`, `deliver-check.md`.** Each carries a full per-criterion verdict table with evidence. These exist to be aggregated: read every one for every covered card and tally verdicts **by criterion id**.
- `KNOWLEDGE.md` (what was already captured) and the git history of `docs/cards/` for gate revisions and blocked episodes.

**The human's trace — every channel, every card (this is the highest-value evidence):**
1. `card_dir/feedback.md` and board-level `docs/cards/feedback.md` — the driver's verbatim words at gates (design/slice revise feedback, keep-as-one rationale), `needs-input` answers, and unblock guidance, persisted by `/kanban`.
2. **Both PRs'** comment threads — the design PR (`design_pr_url`) and the implementation PR (`pr_url`): `{gh_command} pr view <url> --json comments,reviews,state` plus `{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments` (both urls stay on done cards — for legacy cards missing them, recover PR numbers from merge commit subjects). The panel now runs pre-PR (its findings live in `review.md`, not on the PR), so every remaining PR comment is **human-authored**. From these extract: (a) the human's **own** review comments — each one is something no agent, lens, or checker caught — and, per comment, whether the orchestrator addressed it (`[kanban] Addressed in <commit-url>`) or replied `[kanban] Not actioned — <reason>` (a `Not actioned` reply is a human instruction the machine could not carry out — a gap); (b) everything on the **design PR** — that's feedback on the design itself, aimed at the designer's prompt, and design-PR merge latency vs comment volume shows whether designs arrive review-ready; (c) human review verdicts, the review-complete signal (a submitted review or a `REVIEWED` comment), and any PR closed unmerged.
3. Gate outcomes at manual gates: approved first-time vs revised (and the revise text from feedback.md).

**Coverage is verifiable, not assumed:** the retro is not complete until every channel above has been read for every covered card. `RETRO.md` records, per card, each channel and what it held — including explicit empties ("no feedback.md", "PR: 0 human comments") — so a skipped channel is visible as a gap, never silently absent.

## 2. Find systemic patterns, not incidents
Ask of the evidence, XP/lean style — **human signal first**, it outranks everything else:
- **What does the driver keep having to say?** Any feedback repeated across 2+ cards is a prompt defect, not a card fact. Recurring design-gate revisions → the designer prompt lacks that judgment; encode it. Repeated `needs-input` questions of the same shape → the upstream phase (refine/slicer/designer) should resolve or ask it earlier.
- **What did the human catch that the system missed?** This is now the sharpest signal on the board: the lens panel runs **before** the PR, so **every human PR comment is something the whole panel and three checkers all missed.** Map each to a lane — inside a lens's remit → extend that lens's Walk/Red flags with the missed pattern; inside a checker's remit → propose a criterion (`LOCAL-`, or report a plugin one); a design objection surfacing at PR time → the design check or the designer's prompt let it through too late. A comment the orchestrator replied `Not actioned` to is doubly telling — the machine both missed it upstream and could not fix it on request.
- **Rework causes:** what class of finding keeps sending cards back? (e.g. lint gates failing at test → implementer should run them; design gaps → designer checklist item.)
- **Flow:** where do cards wait? Which phase is the bottleneck? Are splits happening at slice that `/refine` should have made at intake?
- **Waste:** phases that consistently add nothing for a card type; docs nobody downstream reads; spec re-reading the `## Spec references` rule should have prevented.
- **Knowledge leaks:** traps hit twice because no `knowledge` entry was recorded the first time.
- **Gate value:** did manual gates change outcomes? Did auto gates let anything bad through to PR review?
- **Panel signal:** per lens in `review.md`, how many **blocking** findings, and did they hold up (did the implementer's rework actually fix something, or push back)? A lens whose blocking findings keep landing points at an upstream phase to strengthen (recurring `[tests]` blockers → teach the designer's test strategy). A lens that never finds anything blocking across many cards may need a sharper brief in `REVIEW-LENSES.md` — or retirement. A lens whose findings the implementer keeps rebutting is miscalibrated: tighten its **Don't flag**.
- **Is the check layer earning its keep?** Tally every `*-check.md` verdict by criterion id across the covered cards. Three signals, three *different* remedies — do not confuse them:
  - **A criterion that never fails** across many cards is not paying for its dispatch. Propose pruning it (a `LOCAL-` one you own; a plugin one you report — see §3).
  - **A criterion that fails on most cards** means the checker is fine and the **producer** is systematically wrong. The remedy is an edit to *that producer's* prompt or the doctrine it reads — **not** more checking. Getting this backwards turns the check layer into a permanent rework tax on a defect nobody ever fixed at source. This is the single most important thing this section does.
  - **A defect that reached the human, or shipped, and no criterion caught it** → propose a new criterion, with an id, in the right section.
- **Is the slicer under-estimating?** For every done card compare `estimated_lines` (slicer, verified by `card-slice-checker`) with `actual_lines` (`card-deliver-checker`). A `DLV-SIZE` breach is *by definition* an `SLC-SIZE` estimate that was wrong. A consistent under-estimate across cards is a defect in the **slicer's** estimation method — propose a correction to its prompt, don't let every card keep paying for the miss at review time.
- **Which checker rubber-stamps?** A checker whose `evidence` for a passing criterion is thin ("looks complete") is skimming, and a skimming checker is worse than none — it manufactures confidence. The Method demands evidence of what was actually checked; hold it to that.

## 3. Answer the four questions, then propose changes
Frame the findings as the classic four, **every bullet citing a concrete artifact** (a phase-doc line, a feedback.md entry, a PR comment, a commit): *What went well? What went wrong? What did we learn? What should we change?* Not every question needs an answer — but if any of the first three has one, at least one concrete change must follow; and never manufacture a finding to satisfy that.

Each proposed change is the **smallest edit that prevents recurrence**, shaped precisely — `target` (exact file), `kind` (`skill | agent | protocol | lens | knowledge | template | board-tunable | card`), an evidence-linked `rationale`, and the exact `edit` (text to append, or a precise old→new replacement):
- `KNOWLEDGE.md` entries (Conventions/Gotchas) — for content lessons. Significant architecture/technology decisions are **not** retro output — they belong in `docs/adrs/` via a phase agent's `proposed_adrs`.
- Process lessons route by scope: **project-specific** ones → append to `<board_dir>/PROTOCOL-ADDENDUM.md` (prefix `[retro-YYYY-MM-DD]`; it layers on the plugin's shared doctrine for this repo only). **Universal** ones — anything that belongs in the plugin's `AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `CHECK-CRITERIA.md`, templates, agents, or skills — must **not** be edited in place: describe the exact change and flag it as a **plugin PR** in the retro output for the human to raise against the plugin repo. The `BOARD.md` header tunables (WIP limit, gate policy) remain editable in-repo.
- **Check criteria — your authority is bounded, exactly as every other agent's is.** You may add, edit and prune **`LOCAL-`** criteria in `<board_dir>/PROTOCOL-ADDENDUM.md` under a `## Check criteria — <target>` heading (`target` ∈ `intake | slice | design | deliver`), shipped in your PR like any other in-repo change. Give each a stable `LOCAL-` id and never reuse one. For a **plugin** criterion you may only *report*: "`DSG-KNOWLEDGE` has passed on 20 consecutive cards — consider raising it upstream", or "`SLC-NO-LOSS` failed on 6 of the last 8 splits — the slicer's prompt is the problem, not the check." The driver decides whether that becomes a plugin change. You never edit plugin doctrine, just as no phase agent edits `BOARD.md`.
- New `defect`/`task` cards (via `/refine`) — for product problems; do not fix product code here.
**Non-duplication check:** before proposing, confirm the rule/heuristic doesn't already exist in the target (and check `docs/adrs/README.md` for standing decisions). If the only improvement you can find already exists, propose nothing — a duplicate teaches the system to ignore its own prompts.

Present the retro to the driver: metrics table (per card: elapsed, reworks), the four answers, proposed changes with rationale. Iterate until approved.

## 4. Apply
- Append approved KNOWLEDGE entries (prefix `[retro-YYYY-MM-DD]`).
- Write `docs/cards/RETRO.md` (append a `## Retro YYYY-MM-DD` section: cards covered, the per-card **human-input channel coverage** table from step 1, metrics, the four answers, changes made — including changes proposed-but-rejected, so they aren't re-proposed) so the next retro knows where to start and a skipped channel is auditable.
- Apply approved **in-repo** process edits — `PROTOCOL-ADDENDUM.md` appends and `BOARD.md` tunables — **on a branch** (`task/retro-YYYY-MM-DD`), commit with Conventional Commits, push, and open a PR against this project's `main` via `{gh_command} pr create` — process changes get the same human review as code. **Universal lessons** (the plugin's `AGENT-PROTOCOL.md`/`REVIEW-LENSES.md`/templates/agents/skills) are **not** committed or PR'd here — they are only recorded in `RETRO.md` and surfaced in the retro output as a proposed **plugin PR** for the human to raise against the plugin repo.

## Rules
- Evidence first: every proposed change cites the cards/docs/comments that motivated it.
- No human input left behind: all channels (feedback.md, the human's own PR comments incl. design-doc-anchored ones and whether each was `Addressed` or `Not actioned`, the review-complete signal, gate outcomes) read for every covered card, with coverage recorded in RETRO.md.
- Small batches: prefer 2–4 high-leverage changes over a rewrite.
- Never edit card status, `BOARD.md` state, or `MILESTONES.md` — `/kanban` and `/refine` own those.
- Never change the product spec or acceptance criteria — product truth lives at `spec_path`.
