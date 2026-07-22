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

## The handoff cycle

`handoff` (session running low) → writes document → **you** carry it to a new session →
`continue` (fresh session) → plan → your approval → work resumes. Repeat as often as a
long task needs; each handoff `supersedes` the last.

### `task-observer`

Continuous skill discovery and improvement — the *"One Skill to Rule Them All"* task
observer. Invoke it at the start of any task-oriented session (any interaction where you
will use tools and produce deliverables) so skill-improvement opportunities are captured
throughout the work rather than lost between sessions.

**What it does.** While you work, it watches for friction, corrections, and recurring
patterns worth preserving — signals for a **new** skill, for **improving** an existing
one, or for **simplifying** one that has grown — and logs them silently to an observation
log in a stable per-project workspace. It surfaces them as a grouped summary at end of
session (log-and-defer by default), and runs a comprehensive **review** (scheduled, or a
7-day in-session fallback) that cross-checks open observations against your skills,
propagates cross-cutting principles, and stages updated skills for your sign-off — nothing
goes live without you installing it.

**Setup — reliable activation.** The skill self-initialises on its first invocation (it
creates its own `skill-observations/` log, principles file, and review-date marker in a
stable per-project workspace — nothing to scaffold by hand). But description-level matching
alone can miss invocation when the agent is deep in a task, so pair it with a
configuration-level instruction that fires it every session. Add this block to your
`CLAUDE.md` (or your harness's project-instructions file):

```
At the start of any task-oriented session — any interaction where you will
use tools and produce deliverables — invoke the task-observer skill before
beginning work. This ensures skill improvement opportunities are captured
throughout the session.

When loading any skill, check the observation log for OPEN observations
tagged to that skill. Apply their insights to the current work, even if
the skill file hasn't been updated yet. This enables immediate application
of observations before they're permanently integrated during the weekly
review.
```

One caveat on *where* it stores state: it anchors on a stable path that outlives the
session (in Claude Code, the project identity under `~/.claude/projects/<project-id>/`),
**not** your current working directory — so a cwd inside an ephemeral git worktree or
temporary clone is re-anchored, since state written there is lost at teardown. The full
activation, compaction, and no-filesystem guidance lives in `references/environments.md`.

**Working with it day to day.**

- **It stays out of your way.** Once loaded, it logs observations in the background without
  interrupting your work, and it will *not* aggressively push new-skill or improvement
  ideas at you. If you want it more proactive, that's a cue to edit the skill (see below).
- **Ask for the tally.** A reliable habit is to ask near the end of a session — *"Any
  observations logged?"* — for a grouped summary of everything captured. You can also ask
  it to re-analyse the whole conversation for opportunities it may have missed. Pairing
  this with something you already do at session end (archiving the task, writing a handoff)
  makes it stick.
- **What gets stored where.** Under the stable per-project workspace it writes only to its
  own subdirectories: `skill-observations/` (the observation log at
  `skill-observations/log.md`, the cross-cutting-principles file, and an `archive/` of
  resolved entries) and `skill-updates/` (staged skill changes awaiting your install).
  Nothing else in the workspace is touched, and **no skill update is ever installed
  automatically** — updates are staged for you to review and install yourself. You don't
  normally need to read the log directly; the skill handles it.
- **Cross-cutting principles compound.** Some observations reveal principles that apply
  across your whole skill library (e.g. *"every skill with rules needs a mechanism to
  enforce them"*). These are captured separately and checked automatically whenever a skill
  is created or updated — raising the quality floor across all your skills over time.
- **Open-source vs internal.** It classifies skills as **open-source** (methodology-driven,
  project-agnostic) or **internal** (your/client/project specifics, personal preferences),
  defaulting to open-source and stripping specifics where it can. The boundary is also a
  confidentiality boundary with layered safeguards — worth knowing so you can tag
  observations correctly when prompted. Whether you ever publish a skill is always your
  call.
- **The review is a safety net.** If 7+ days pass with open observations waiting, it offers
  (one line, never a gate) to run a comprehensive review that cross-checks every open
  observation against every skill, checks principle compliance, applies what it safely can,
  and summarises the rest for you. If you update skills more often than weekly you may
  rarely hit it; a scheduled cadence (e.g. a few mornings a week) suits heavier use — see
  `references/weekly-review.md`.
- **It pairs with `skill-creator`.** The observer decides *what* to build or improve; the
  built-in `skill-creator` handles *how*.
- **Make it your own.** This is now your meta-skill — if it's too passive, too noisy, or
  missing things, just tell Claude what isn't working and have it revise the skill.
- **Getting kickstarted.** You don't have to wait for it to suggest skills. Seed a few
  proactively — a personal writing-style skill is a good first one (have Claude analyse
  your best pre-AI writing, then paste your edits back over time and let the observer refine
  it). Bigger workflows follow the same pattern.

**Reference files (loaded on demand).** The core `SKILL.md` stays lean; episodic
procedure lives in [`skills/task-observer/references/`](skills/task-observer/references/):
`weekly-review.md` (the review procedure and approval policy), `skill-authoring.md`
(taxonomy, licensing, confidentiality layers, editing rules), and `environments.md`
(activation setup, compaction behaviour, and a handoff-doc mode for storage-less
environments).

**Inspiration & attribution.** This skill is adapted from the *"One Skill to Rule Them
All"* task-observer skill created by Eoghan Henn / [rebelytics.com](https://rebelytics.com)
([github.com/rebelytics/one-skill-to-rule-them-all](https://github.com/rebelytics/one-skill-to-rule-them-all)),
which was the basis for it and its inspiration. The original is licensed under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/); this version has been modified
(the skill's own files carry no author, branding, or external links) and is distributed
under the same licence. Credit for the underlying methodology belongs to the original
author.
