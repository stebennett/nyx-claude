# productivity

Skills for working more productively with Claude Code.

## Skills

### `handoff`

Distils the current Claude Code session into a single self-contained Markdown
document that a **fresh** session can read to continue the work — without losing the
context that lived in the conversation.

**When to use it.** Invoke it by hand when the context window is shrinking below a
comfortable level and you want to hand the work off cleanly before detail is lost to
compaction.

**What it produces.** A document capturing:

- the over-arching goal of the session,
- the work completed so far (including dead ends and why they were dropped),
- the outstanding work with recommended next steps (direction, not scripted commands),
- the skills, agents, and workflows to reach for next,
- and any other state — branch, dirty tree, running processes, conventions, gotchas —
  a cold-starting reader would otherwise have to rediscover.

It deliberately **does not** copy documents already on disk (specs, plans, ADRs) —
it references them by path so the next session reads them into its own context — and
it **does not** script exact prompts or commands, leaving the *how* to the picking-up
agent.

**Where it writes.** Outside the git repo, in `~/.claude/handoffs/`, named
`<project>-<timestamp>.md` (e.g. `nyx-claude-20260709-143005.md`), so it is never
committed and is easy for a future `continue` skill to find.

**The format is a contract.** The document's location, filename, frontmatter schema,
required sections, and content rules are specified in
[`skills/handoff/references/handoff-format.md`](skills/handoff/references/handoff-format.md)
— the single source of truth that both `handoff` (writer) and `continue` (reader) bind
to. It is versioned (`schema_version`) so the two skills can evolve without breaking
documents already on disk. Notable guarantees for the reader: a machine-readable
frontmatter header (repo root, remote, branch, `head_sha`, `status`), a *verifiable*
starting-state block so `continue` can confirm its footing before acting, an explicit
definition-of-done, and a clean split between settled decisions and open questions that
need a human.

### `continue`

The reader half of the handoff. Invoke it by hand at the start of a **fresh** session
that is resuming earlier work, optionally passing the handoff file path.

**What it does.** Locates the handoff document (an explicit path, or the newest open one
matching this repo per the contract), validates it, **verifies the footing** — comparing
the current commit and working tree against the recorded `head_sha` and starting state —
and re-reads the referenced specs/plans into context. It then reasons the document's
*direction* into a concrete **continuation plan** and presents it for the user to review:
restated goal and definition-of-done, a footing summary with any mismatch, the proposed
steps and which skills/agents/workflows they use, the boundaries it will respect, and the
open questions that need answering.

**It never starts work without authorisation.** The plan is a gate: `continue` makes no
change to code, files, or git state until the user explicitly approves. On the go-ahead it
marks the handoff `status: consumed`, executes the approved plan while respecting the
decisions/open-questions boundary, self-checks against the definition-of-done, and — if
context runs low again — writes a fresh handoff that `supersedes` the one it consumed,
continuing the chain.

## The cycle

`handoff` (session running low) → writes document → **you** carry it to a new session →
`continue` (fresh session) → plan → your approval → work resumes. Repeat as often as a
long task needs; each handoff `supersedes` the last.
