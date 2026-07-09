---
name: kanban
description: Orchestrate a project's kanban board. Reconciles state from merged PRs, renders the board, schedules ready cards up to the WIP limit, runs each card through slice→design→(design PR)→implement→test→review→(implementation PR) via the card-* agents with automatic rework loops. Each card ships as two PRs — design docs + ADRs first, code second — so decisions reach main early. /refine creates cards; /kanban is the sole writer of BOARD.md, KNOWLEDGE.md, and card.md thereafter. Safe to run under /loop. Run under Opus.
---

# /kanban — orchestrator & dashboard

You drive cards through the board. `/refine` creates cards; thereafter you are the **sole writer** of `docs/cards/BOARD.md`, `docs/cards/KNOWLEDGE.md`, and every `docs/cards/CARD-*/card.md`. No phase agent ever writes these files. Phase agents only return structured `result` blocks; you persist everything they produce.

**Every card ships as two PRs.** The **design PR** (branch `<type>/NNN-slug-design`) carries the pre-implementation artifacts — `slice.md`, `design.md`, ADRs, gate feedback — so decisions land on `main` early and feed future cards' design thinking. The **implementation PR** (branch `<type>/NNN-slug`, cut from `main` *after* the design PR merges) carries the code plus `implement.md`/`test.md`/`review.md`. The human merging each PR is the review gate for that half. Consequence for doc flow: **phase docs live on the card's current branch, not on `main` directly** — your direct-to-main commits are limited to `card.md`/`BOARD.md`/`KNOWLEDGE.md` state, the milestone swap on splits, a split parent's terminal `slice.md`, and post-PR artifacts (`pr-review.md`, later `feedback.md` entries).

Each invocation runs one **pump cycle**: reconcile → load state → render → resolve gates/blockers with the driver → schedule & advance (in waves, as far as cards can go) → re-render → report. A card only stops mid-lifecycle at a manual gate, `needs-input`, an exhausted rework budget, an open PR awaiting merge, or `done`. This makes the skill safe to run unattended (e.g. under `/loop`): PRs accumulate for the human to review and merge; the next pump reconciles merges and refills WIP.

## 0. Reconcile (self-healing state)

Card state must survive lost local commits and merges that happen while no pump is running. Before anything else:

1. `git fetch origin main` and inspect `git log origin/main` for merge subjects matching `CARD-NNN … (#N)`.
2. **Design PR merged** (matches a card's `design_pr_url`, or subject contains `design:`): the card's design docs + ADRs are now on `main`. Tear down the design branch and worktree, pull main, create the **implementation branch** `<type>/NNN-slug` and worktree off fresh `origin/main`, update `branch`/`worktree`, set `status: implement` (keep `design_pr_url` for traceability). The card continues in Section 5.
3. **Implementation PR merged** (matches `pr_url`, or a non-design `CARD-NNN` merge subject): set `status: done`, `phase: done`, set `delivered` to the merge date, tear down its worktree and delete the local branch. Keep `pr_url`/`design_pr_url` — `/retro` mines both PRs' threads.
4. For every card with a non-empty `design_pr_url` or `pr_url` not yet merged, check the PR state (`{gh_command} pr view <url> --json state,mergedAt`). `MERGED` → apply step 2/3. `CLOSED` (unmerged) → `status: blocked` with blocker "PR closed without merge", surface to the driver.
5. **Normalize legacy state** from older lifecycle versions: `status: plan` → `status: design` (an existing `plan.md` stays as designer input); any non-enum status (e.g. `awaiting-input`) → restore the card to the phase whose input it awaits and surface what was being asked; a `retro:` frontmatter field is inert (per-card retros were consolidated into `/retro`). Cards already at `implement` or later when the two-PR flow shipped have their design docs on `main` already — they skip the design PR and carry only the implementation PR.
6. Note any other drift you can't self-heal (a card id in a merged PR with no card dir, a worktree with no card) in the report — don't guess.

## 1. Load state
Read `{board_dir}/config.md` first — it carries the tunables (`spec_path`, `gh_command`, `wip_limit`, `gates`, `layers`, `gate_layer`, `adr_dir`, `coverage_target`). Everything below reads these; never hardcode them. `board_dir` defaults to `docs/cards`. Read every `docs/cards/CARD-*/card.md` and parse its frontmatter (missing `reworks`/`started`/`delivered`/`design_pr_url` fields default to `0`/empty — legacy cards). This is the source of truth. Read `docs/cards/KNOWLEDGE.md`. Read `docs/cards/MILESTONES.md` (authored by `/refine`; you never write it): parse the ordered `## M<N> — <title>` headings and each milestone's `**Cards:**` line into a `card → milestone index` map (document order = delivery order; a card in no milestone has index ∞). Compute each milestone's progress = done members / total members.

Resolve the **plugin doctrine directory** once this pump: `${CLAUDE_PLUGIN_ROOT}/templates/` (the same path `/kanban-init` uses). You pass absolute paths from it into every dispatch (Section 5) — agents never read a `docs/cards/` doctrine copy. **Template resolution rule** (used wherever a skill fills a template): for `card-template.md`, `pr-template.md`, or `design-pr-template.md`, read `config.md`'s `template_overrides[<name>]` if set (a repo-relative path), else the plugin's `${CLAUDE_PLUGIN_ROOT}/templates/<name>`. **Migration check:** compare `config.md`'s `kanban_flow_version` to the installed plugin version and scan `<board_dir>` for leftover plugin-owned copies (`AGENT-PROTOCOL.md`, `REVIEW-LENSES.md`, `card-template.md`, `pr-template.md`, `design-pr-template.md`) — excluding any template file registered in `template_overrides` (a preserved override is intentional, not a leftover). If the version is behind or any such unregistered copy exists, set `migration_needed` for the report (Section 7).

## 2. Render the board (sole writer)
Rewrite `BOARD.md` from the parsed cards: one bullet per card under the column matching its `status`, showing `CARD-NNN — title · phase · branch` (suffix the `[M<N>]` milestone tag), for blocked cards the blocker, for cards awaiting driver input `(awaiting input)`, and for cards with an open PR the PR link (`design PR #N open` / `PR #N open`). Columns in order: Backlog, Slice, Design, Implement, Test, Review, Deliver, Blocked, Done, Split. Render `status: split` cards in the `## Split` section as `CARD-NNN — title → split into CARD-XXX, CARD-YYY` (terminal). Update the header counts and `last rendered` line.

These tunables are read from `config.md` (BOARD may display them, but config is authoritative): WIP limit (`wip_limit`), gate policy (`gates`).
- **WIP limit** (default 3).
- **Gate policy** — e.g. `slice=auto · design=pr · deliver=auto`. Per gate: `slice` = `auto` (apply splits immediately) or `manual` (stop for the driver). `design` = `pr` (no interactive stop — the design PR *is* the review), `domain` (interactive stop before opening the design PR for `gate_layer` cards only), or `manual` (interactive stop for every card). `deliver` = `auto` (open the implementation PR without stopping) or `manual` (present the PR body first). Missing config → defaults `slice=auto`, `design=pr`, `deliver=auto`.

Also render the derived **`## Milestones`** section: `M<N> — <title> · <done>/<total> · <state>` (`not started` / `in progress` / `complete`). Computed from card status — never edit `MILESTONES.md` itself.

## 3. Resolve gates & blockers first
- **Blocked cards:** show the blocker; ask the driver how to proceed (re-dispatch with guidance, edit the card, or leave parked). Unattended: leave parked, continue.
- **Slice gate** (a slicer proposed a split): `slice=auto` → apply the split immediately (carve-out below) and report it prominently. `slice=manual` → present the children + `dependents_rewire`; driver picks `approve` / `revise (feedback)` / `keep-as-one` (keep-as-one → `right_sized: true`, proceed to the design transition in Section 5).
  - **Carve-out (sole-writer):** create each child `docs/cards/CARD-NNN-slug/card.md` from the `card-template.md` template (resolved per Section 1's template-resolution rule; ids continue from the current max) with `status: backlog`, **`right_sized: true`** (the slicer just sized them), the proposed `layer`/`type`/`depends_on` (sibling titles → new ids), and a `## Notes` line `Split out of <parent-id>`; apply `dependents_rewire`; swap parent for children on the milestone's `**Cards:**` line (mechanical only); parent → `status: split` with `## Notes` `Split into <ids>`, and commit its `slice.md` directly to `main` (terminal record — no PR will carry it). Commit `chore(kanban): split CARD-NNN into …`.
- **Design stop** (only when policy is `domain`/`manual` and the card qualifies): present the `design.md` summary + open questions **before the design PR opens**. Driver picks `approve` (→ open the design PR) / `revise (feedback)` (→ re-dispatch `card-designer`) / `stop`. Under the default `design=pr` there is no stop — review happens on the design PR itself.
- **Deliver gate** (card at `status: deliver`, `pr_url` empty): assemble the implementation PR body (fill the `pr-template.md` template — resolved per Section 1's template-resolution rule — from the card's docs and acceptance criteria) into `card_dir/pr-body.md` in the worktree. `deliver=auto` → dispatch `card-deliverer` without stopping. `deliver=manual` → present the body first. If `pr_url` is set the PR is open — Section 6; never re-dispatch.

**Driver input is durable (retro fuel).** Before acting on any driver response — a gate decision and any revise feedback, answers to `open_questions`, unblock guidance, a keep-as-one rationale, a policy override — append it **verbatim** to `card_dir/feedback.md` under `## YYYY-MM-DD · <phase> · <what was asked>` (board-level input → `docs/cards/feedback.md`). Pre-design-PR entries live in the design worktree and ride that PR; later entries ride the implementation branch; post-PR entries commit to `main`. The driver's words are `/retro`'s highest-value signal; they must never live only in chat scrollback.

## 4. Schedule
- A `backlog` card is **ready** when every id in `depends_on` is `done`.
- Count in-flight cards (status in slice|design|implement|test|review|deliver). A card with an open PR (design or implementation) holds its WIP slot until merged — intentional back-pressure that keeps the human's merge queue short. `split` is terminal, not in-flight. While in-flight < WIP limit and ready cards remain, **start** the next ready card, ordering candidates by **`(milestone_index, layer_rank, card_id)`** ascending (layer rank = the order defined in `config.layers`; missing layer → infer from title; no milestone → ∞). Soft milestone preference — never idle a free slot.
- **Starting a card:** set `started` to today. If `right_sized: true` already (intake or split child), skip slice: perform the design transition (Section 5) directly. Otherwise `status: slice` — no branch or worktree yet; the card may be split before any work begins.

## 5. Advance in-flight cards (chain until a stop)

Advance every in-flight card **as far as it can go this pump**. Work in waves: dispatch all dispatchable cards' agents in parallel (one Agent-tool message), process each `result` **serially** (sole writer), apply transitions, dispatch the next wave. A card stops chaining at: a manual gate, `needs-input`, `blocked`, rework budget exhausted, an open PR awaiting merge, or `done`.

**Dispatch vs. handle:** phase-doc presence in the card's current worktree `card_dir` decides — absent → dispatch the phase agent; present → handle (gate or advance). Key states:
- `status: slice` + `slice.md` absent → dispatch card-slicer (no worktree; include the card's **dependents** for `dependents_rewire`).
- slice right-sized (or start with `right_sized: true`) → **design transition:** create branch `<type>/NNN-slug-design` + worktree off `main` via **superpowers:using-git-worktrees** (e.g. `../<repo>-worktrees/CARD-NNN`), set `branch`/`worktree`, write `slice.md` into the worktree's `docs/cards/CARD-NNN-slug/` and commit it on the branch, `status: design`.
- `status: design` + `design.md` absent → dispatch card-designer.
- `status: design` + `design.md` present + design stop pending per policy → present the stop (Section 3).
- `status: design` + gate passed + `design_pr_url` empty → **open the design PR:** persist `design.md` (and any `feedback.md`) to the branch; route `proposed_adrs` (below) so ADR files land on the branch; assemble the design PR body from the `design-pr-template.md` template (resolved per Section 1's template-resolution rule); dispatch `card-deliverer` in **design mode** (push + open PR titled `CARD-NNN — design: <title>`). On return, record `design_pr_url`; the card now awaits merge (Section 6 CI/addressing apply).
- Design PR merged → handled by Reconcile (Section 0 step 2): implementation branch/worktree created, `status: implement`.
- `status: implement|test|review` → dispatch per the table; on `complete` advance (implement→test→review→deliver), committing each returned phase doc to the **implementation branch**.
- `status: deliver` → deliver gate (Section 3) → card-deliverer in **implementation mode** → record `pr_url` → Section 6.

| status | dispatch | model |
|---|---|---|
| slice | card-slicer | sonnet |
| design | card-designer | opus |
| implement | card-implementer | sonnet |
| test | card-tester | haiku |
| review | card-reviewer | opus |
| deliver (design or implementation PR) | card-deliverer | haiku |

**Model pinning:** you (the orchestrator) run under Opus; every dispatch passes the table's `model` explicitly so no agent ever inherits the session model. The agents' distilled expertise lives in their prompts and `AGENT-PROTOCOL.md`'s Doctrine section — capability comes from the instructions, not the model tier.

In the dispatch prompt include: `card_id`, `card_dir`, the full `card.md`, and **only the phase docs the phase needs**: slicer → none; designer → slice.md; implementer → design.md (+ findings on rework); tester → design.md's test strategy + implement.md; reviewer → design.md + implement.md + test.md; deliverer → the PR body file path and mode (design / implementation). Include `worktree` once it exists. **Always include the doctrine paths** every agent reads: the absolute `${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md` and the repo's `<board_dir>/PROTOCOL-ADDENDUM.md` (for `pr-expert-reviewer` dispatches also the absolute `${CLAUDE_PLUGIN_ROOT}/templates/REVIEW-LENSES.md` — see Section 6b).

### Process each `result` (you persist everything)
1. Parse the fenced `result` YAML.
2. Write `phase_doc` to the card's `card_dir` **in its current worktree** and commit it on the card's branch (Conventional Commit, e.g. `docs(card): CARD-NNN design`). Rework passes overwrite the doc; note the rework count in it.
3. Route `knowledge`: append `repo` entries under the right `KNOWLEDGE.md` section — `Conventions | Gotchas | Glossary` only, prefix `[CARD-NNN]` (no Decisions section: decisions are ADRs) — committed to `main`; `personal` entries → the Claude project memory directory for this checkout.
   **Route `proposed_adrs`:** invoke the **`adr`** skill with `card_id`, today's ISO date, the proposed list, and the card's **worktree** as the write target — ADR files land on the card's current branch and merge via its PR (design-phase ADRs via the design PR — the point of this flow). **Numbering across parallel branches:** allocate `NNNN = max(files under docs/adrs/ on main, every id in any card's `adrs:` list) + 1`; appending the id to the card's `adrs:` frontmatter (a direct-to-main state commit) reserves the number before the file merges.
4. Apply the transition:
   - `needs-input` → surface `open_questions`; on answers re-dispatch the same agent. Unattended: leave awaiting input, continue other cards.
   - `blocked` from **implementer** (design wrong, environment broken) → `status: blocked`; driver decides.
   - `blocked` from **tester or reviewer** (failing gates / blocking findings) → **automatic rework**: if `reworks < 2`, increment, `status: implement`, delete stale `test.md`/`review.md` from the branch, re-dispatch `card-implementer` in rework mode with the findings verbatim. Else `status: blocked`.
   - `complete` + `gate: slice` → slice gate per policy (Section 3).
   - `complete` + `gate: none` from **slice** → `right_sized: true`; design transition (above).
   - `complete` + `gate: design` → design stop per policy, then the design-PR step (above).
   - `complete` + `gate: none` (implement, test, review) → advance and continue the chain; reaching `deliver` triggers the deliver gate.
   - `complete` from **deliverer** → record the PR url into `design_pr_url` (design mode) or `pr_url` (implementation mode); the card awaits merge; Section 6.
5. Commit state changes (`card.md`, `BOARD.md`, `KNOWLEDGE.md`) to `main` with a Conventional Commit (`chore(kanban): …` matching what happened), ending with the project `Co-Authored-By` trailer, and **push** (`git push origin main`; on rejection retry after `git pull --rebase origin main`). If pushes to `main` are refused by branch protection, say so in the report — Reconcile keeps lifecycle state recoverable from merged PRs, and phase docs/ADRs are safe on their branches regardless.

## 6. PR open — CI gate, panel, review-complete addressing

A card with an open PR (design or implementation) holds its WIP slot until merged.

### 6a. CI gate — nothing else happens on the PR until checks pass
Every pump, before panel or addressing, check the PR's CI: `{gh_command} pr checks <url>`. (CI log/rerun calls use `gh` directly.)
- **No checks configured** → proceed. The gate requires that no check is failing, not that checks exist — docs-only design PRs and pre-CI-pipeline PRs are reviewable.
- **Pending / running** → do nothing for this card this pump; report "CI running". The pump loop is the wait.
- **All green** → proceed to 6b/6c.
- **Failing** → read the real logs (`gh run view <run-id> --log-failed`) and classify:
  - **Actionable** (caused by the branch): dispatch `card-implementer` in rework mode with job + step + log excerpt (for a design PR: `card-designer`, e.g. a docs linter), noting the PR is open. Consumes the `reworks` budget; exhausted → `blocked`.
  - **Infrastructure** (Actions outage/degradation, runner provisioning, stuck/cancelled checks, rate limiting): **flag it** prominently, attempt `gh run rerun <run-id> --failed`, note the retry (date + reason) on the card's `## Notes`, re-check next pump. After **3** infra retries without progress → `status: blocked` ("CI infrastructure unavailable"). Never treat a red PR as reviewable or mergeable.
  - **Ambiguous / flaky** (failed once, passes locally, no relevant diff): infrastructure treatment first; a second consecutive failure of the same job is real.

### 6b. Seed the review panel (implementation PRs only, once, CI green)
Design PRs are prose the human reviews directly — no panel. For an **implementation PR** with CI green and `pr-review.md` absent: assemble the panel from the PR's changed files (`{gh_command} pr diff <url> --name-only`) and dispatch one `pr-expert-reviewer` **per lens, in parallel**, passing each its `lens`, `pr_url`, `worktree`, `card_id`, `card.md`, and the doctrine paths (`${CLAUDE_PLUGIN_ROOT}/templates/AGENT-PROTOCOL.md`, `${CLAUDE_PLUGIN_ROOT}/templates/REVIEW-LENSES.md`, and `<board_dir>/PROTOCOL-ADDENDUM.md`). Lens briefs live in the plugin's `REVIEW-LENSES.md` (the injected path); each expert reads only its own section.

| lens | dispatch when | model |
|---|---|---|
| design | always | opus |
| functionality | always | opus |
| security | always | opus |
| simplicity | always | sonnet |
| tests | always | sonnet |
| readability | always | sonnet |
| python | diff touches `*.py` | sonnet |
| typescript | diff touches `*.ts` / `*.tsx` | sonnet |

Each expert posts one `COMMENT` review with `[lens]`-prefixed inline comments (nothing when it finds nothing). Concatenate the returned phase docs into `card_dir/pr-review.md` (committed to `main` — the PR is already open), route `knowledge`, commit `chore(kanban): CARD-NNN PR review seeded`, and tell the driver the PR awaits their review (👍 any panel comment to have it addressed too).

### 6c. Address loop (every pump per open PR, CI green)
Nothing is actioned until the human signals the review is **complete**; then every comment they authored is addressed, plus any panel comment they 👍'd. Never act before the signal.

1. **Detect the review-complete signal** — either one satisfies it:
   - a **submitted review** by a non-app user (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/reviews`) with state `COMMENTED` / `CHANGES_REQUESTED` / `APPROVED` (`PENDING` never counts); or
   - a top-level PR comment whose trimmed body equals `REVIEWED` (case-insensitive) by a non-app user (`{gh_command} api repos/{owner}/{repo}/issues/{n}/comments`).
   No signal → do nothing on this PR this pump; report "awaiting review". The pump loop is the wait.

2. **Assemble the actionable set** — skip any item already carrying a `[kanban]` reply/marker (that reply is the idempotent addressed-marker):
   - **every human-authored inline comment the signal authorises** (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments`) — no 👍 needed (see *scope by signal* below);
   - **each human-submitted review's summary body** when non-empty (idempotency keyed to the review id via a top-level `[kanban]` marker naming the review);
   - **panel `[lens]` comments only if 👍'd**.
   "App" = the identity the flow posts as (its comments carry the `[lens]`/`[kanban]` prefix or its App login); everything else is human. Exclude the `REVIEWED` comment itself. **Scope by signal:** a submitted review authorises only its own inline comments and body (one atomic unit); a `REVIEWED` comment authorises every loose inline comment (one not attached to a submitted review) created at/before its timestamp. A human comment reached by neither signal waits for one.

3. **Dispatch. Implementation PR:** dispatch `card-implementer` in PR-comment mode with the items verbatim (id, path, line, body; review-body items flagged as summary) — it fixes exactly those (test-first for behaviour), runs the fast gates, commits (one commit per comment or a tight cluster), pushes. **Design PR:** re-dispatch `card-designer` with the items verbatim; commit its revised `design.md` (and any superseding ADR proposals via the `adr` routing) to the design branch and push.

4. **Reply once per item** — in its thread (inline, `{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments/{id}/replies`) or as a top-level `[kanban]` comment (review body): `[kanban] Addressed in <commit-url> — <one-line explanation>`, where `<commit-url>` is the full `https://github.com/{owner}/{repo}/commit/<sha>`. For an item the agent returned in `blockers` (a question, or a change it judged wrong/infeasible), reply `[kanban] Not actioned — <reason>` and surface it to the driver. Every item in the set gets exactly one reply. **Never resolve threads**, never approve or dismiss — resolution and the merge are the human's.

These fixes are human-directed and don't consume the `reworks` budget. Merge detection stays with Reconcile (Section 0). A healthy card needs exactly three human actions: merge the design PR, complete a review (or comment `REVIEWED`), merge the implementation PR.

## 7. Report
Print a concise digest: what advanced (and how far it chained), design PRs opened/merged, implementation PRs opened, what was auto-reworked (card, findings, `reworks`), what awaits a gate/input/merge, splits, blocks, free slots, and per-milestone progress. Flow metrics per finished card: `started → delivered` elapsed and `reworks`. List **ADRs written this pump** (`ADR-NNNN — title → CARD-NNN`, and which PR carries each). Warn on `MILESTONES.md` drift (a `/refine` fix — surface, don't edit). If `migration_needed` (Section 1), warn prominently: **"Un-migrated doctrine copies or a stale `kanban_flow_version` detected — run `/migrate`."** **Every 5 cards done**, suggest `/retro`.

## Rules
- `/refine` creates `card.md` files; thereafter never let phase agents write `BOARD.md`, `KNOWLEDGE.md`, or `card.md` — you are the sole writer of all three. Likewise sole writer of `docs/adrs/`, produced only via the `adr` skill from agents' `proposed_adrs` — agents propose, never write.
- `/refine` owns `MILESTONES.md`; your only edit is the mechanical parent→children swap on an applied split.
- Two PRs per card, in order: design PR (docs + ADRs) merges **before** the implementation branch is cut. Never start implementing a card whose design PR is unmerged; never bundle code into a design PR.
- A card cannot reach `design` until `right_sized: true`. Never re-slice a right-sized card. No branch/worktree during `slice`; a `split` parent never gets one.
- Never exceed the WIP limit. Never start a card with unmet dependencies. Prefer the earliest incomplete milestone, but never idle a free slot.
- Auto-rework only for actionable findings (failing tests, blocking review findings, branch-caused CI failures); max 2 loops per card, then the driver decides.
- PR comments are actioned only after a review-complete signal (a submitted review or a `REVIEWED` comment): then every human-authored comment is addressed, plus any 👍'd panel comment. The system replies `[kanban] Addressed in <commit-url>` (or `[kanban] Not actioned — <reason>`) but never resolves threads, never approves, never dismisses. Panel experts post `COMMENT` reviews only, on implementation PRs only.
- Code review happens only on green CI (no-checks PRs count as reviewable). Branch-caused failures are fixed from the real logs; infrastructure failures are flagged, rerun, re-checked (max 3), then parked.
- All branches off `main`; all PRs target `main`. Phase docs ride their half's PR: slice/design/ADRs/early feedback in the design PR; implement/test/review in the implementation PR.
