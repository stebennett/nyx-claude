# kanban-flow — address human review comments on a review-complete signal

**Date:** 2026-07-08
**Plugin:** `plugins/kanban-flow`
**Status:** Approved design, ready for implementation planning

## Problem

Today the kanban-flow pump only actions a PR comment when the human adds a 👍
reaction to it (`SKILL.md` §6c). Every comment the human wants addressed must be
individually 👍'd — including comments the human wrote themselves. This is
tedious: the natural GitHub workflow is to leave review comments and submit a
review, not to re-mark each of your own comments.

We want the pump to treat a **completed review** as the go signal and then
address **every human-authored review comment** automatically, replying to each
with a link to the commit that addressed it plus a brief explanation of the
change. The 👍 mechanism stays, but only for comments the human did *not* write
(the panel's `[lens]` comments).

## Approach

**Approach A — evolve the existing triage loop in place.** The pump already owns
GitHub-state parsing and posts the `[kanban]` replies while the phase agents own
the fix. This change widens that existing boundary: broaden the trigger from
"any 👍" to "a review-complete signal", redefine the actionable set with an
author filter, and enrich the reply to carry a commit URL + explanation. No new
card state, no new mechanism — it reuses today's dispatch modes
(`card-implementer` PR-comment mode, `card-designer` rework) and the idempotent
`[kanban]`-marker pattern.

Rejected: modelling the review signal as first-class card frontmatter (fights the
"state is recoverable from merged PRs" principle) and pushing the policy into the
agents (scatters the identity/reply rules the pump deliberately centralises).

## Design

### 1. The trigger — a review-complete signal

Every pump, for each open PR (design **or** implementation) with CI green, the
pump determines whether the human has finished reviewing. A signal is **either**:

- A **submitted GitHub review** by a non-app user — state `COMMENTED`,
  `CHANGES_REQUESTED`, or `APPROVED`. `PENDING` (unsubmitted) never counts.
  Fetch: `{gh_command} api repos/{owner}/{repo}/pulls/{n}/reviews`.
- A **top-level PR comment** whose trimmed body equals `REVIEWED`
  (case-insensitive) by a non-app user. Fetch:
  `{gh_command} api repos/{owner}/{repo}/issues/{n}/comments`.

No signal → the pump does nothing on this PR this pump and reports
"awaiting review" (mirrors today's "nothing 👍'd" no-op). The pump loop is the
wait.

### 2. The actionable set

Once a signal exists, the pump assembles the set of items to address:

- **Human inline comments** — every inline review comment the signal authorises
  (`{gh_command} api repos/{owner}/{repo}/pulls/{n}/comments`) authored by a
  non-app account with no `[kanban]` reply already in its thread. No 👍 required.
  See *Timing* below for which comments a given signal authorises.
- **Review summary bodies** — the body text of each human-submitted review, when
  non-empty. Idempotency keyed to the review id (a top-level `[kanban]` marker
  comment that names the review).
- **Panel `[lens]` comments** — included only if the human added a 👍 reaction
  (unchanged from today) and no `[kanban]` reply yet.

Author identification: "the app" is the identity the flow posts as — its
comments carry the `[lens]`/`[kanban]` prefixes and/or the App/bot login exposed
by `gh_command`'s configured identity. Everything else is human. The `REVIEWED`
comment itself is excluded from the set.

Timing:

- A **submitted review**'s inline comments and body are processed as one atomic
  unit — the review *is* the signal and the container.
- For loose inline comments cleared by a `REVIEWED` **comment** (comments not
  attached to a submitted review), process those created at or before the newest
  `REVIEWED` comment's timestamp.
- A submitted-review signal authorises only its own atomic unit — it does **not**
  sweep loose comments; a human comment reached by neither signal waits for one.

### 3. Address & reply

- **Dispatch** (unchanged in shape): implementation PR →
  `card-implementer` in PR-comment mode; design PR → `card-designer` rework.
  The items are passed verbatim (id, path, line, body; review-body items flagged
  as summary-level).
- The agent fixes exactly those items — test-first for behaviour changes, direct
  edit for nits — runs the fast test/lint gates, commits with Conventional
  Commits (one commit per comment or a tight cluster), and pushes the branch.
- **Per addressed item, exactly one reply** — posted in the comment's thread
  (inline) or as a top-level `[kanban]` comment (review body):

  ```
  [kanban] Addressed in <commit-url> — <one-line explanation of the change>
  ```

  where `<commit-url>` is the full, clickable
  `https://github.com/{owner}/{repo}/commit/<sha>`. This replaces today's bare
  `<short-sha>` and is the "link to commit" requirement. The reply remains the
  idempotent addressed-marker.
- **Non-actionable / can't-do items** — a comment that is a question, or a change
  the agent judges wrong or infeasible: the agent returns it in `blockers`; the
  pump replies `[kanban] Not actioned — <reason>` (also a marker, so it is never
  retried) and surfaces it to the driver. Every item in the actionable set
  therefore receives exactly one reply — nothing is silently dropped.
- The pump never resolves threads, approves, or dismisses (unchanged). These
  fixes are human-directed and do **not** consume the `reworks` budget
  (unchanged).

### 4. Decisions

1. An `APPROVED` review that still carries inline comments → the comments are
   still addressed (the human wanted them fixed). `APPROVED` with no comments and
   an empty body → nothing to action; the human intends to merge.
2. Each new submitted review or new `REVIEWED` comment re-arms the sweep; the
   per-item `[kanban]` markers keep repeated pumps safe (already-addressed items
   are skipped).
3. Non-actionable human comments receive an explicit `[kanban] Not actioned —
   <reason>` reply rather than silence.

## Files changed

- `skills/kanban/SKILL.md` — rewrite §6c (the triage loop) to the
  review-complete gate + author-filtered actionable set + commit-link reply;
  adjust the §6 heading, §6b's closing line ("awaits 👍 triage" → "awaits your
  review"), and the PR-comment bullet in the Rules list.
- `templates/AGENT-PROTOCOL.md` — reword the triage/👍 lines (≈16, 41–42) to the
  signal + author-filter model and the commit-link reply.
- `agents/card-implementer.md` (PR-comment mode, ≈line 17) and
  `agents/card-designer.md` (design-PR rework, ≈line 16) — the dispatch inputs
  are now "all human review comments (auto) + 👍'd panel comments", and the
  addressed-reply carries a commit link.
- `skills/retro/SKILL.md` — add the review-complete signal and the
  auto-addressed human comments as a mined input channel (the "no human input
  left behind" checklist and the channels list).
- `README.md` — update if it describes the triage / 👍 flow.

## Out of scope

- Top-level PR conversation comments are **not** addressed (only inline comments
  and review-summary bodies are); the conversation timeline is where `REVIEWED`
  and general discussion live.
- No change to the review panel, CI gate, ADR flow, or reconcile logic.
- No new card frontmatter fields.
- Resolving/approving/dismissing threads remains the human's job.

## Success criteria

- A human can leave inline review comments, submit the review (or post
  `REVIEWED`), and on the next pump every one of their comments is either
  addressed with a commit-link reply or answered with a `Not actioned` reply.
- Panel `[lens]` comments still require a 👍 to be actioned.
- Re-running the pump does not re-address or double-reply to any comment.
- The flow works identically on design and implementation PRs.
