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
— the single source of truth that both `handoff` (writer) and the future `continue`
(reader) bind to. It is versioned (`schema_version`) so the two skills can evolve
without breaking documents already on disk. Notable guarantees for the reader: a
machine-readable frontmatter header (repo root, remote, branch, `head_sha`,
`status`), a *verifiable* starting-state block so `continue` can confirm its footing
before acting, an explicit definition-of-done, and a clean split between settled
decisions and open questions that need a human.

## Roadmap

- `continue` — reads a handoff document and resumes the work it describes. It will bind
  to the same [`handoff-format.md`](skills/handoff/references/handoff-format.md) contract:
  match the document by repo, verify the recorded footing, respect the decisions/open-questions
  boundary, and mark the document `consumed` on a successful pickup. Planned for a later
  addition.
