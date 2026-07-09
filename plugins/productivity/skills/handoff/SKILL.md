---
name: handoff
description: Distil the current Claude Code session into a single self-contained handoff document that a fresh session can read to continue the work. Invoke MANUALLY when the context window is shrinking below a comfortable level and you want to hand the work off before detail is lost. Captures the session's goal, work done, outstanding work with recommended next steps, and which skills/agents/workflows to reach for — while pointing at (never copying) spec/plan files already on disk. Writes the document OUTSIDE the git repo, conforming to the handoff format contract. A future 'continue' skill reads it back.
---

# handoff — hand this session off to a fresh one

You are being invoked, by hand, to write a **handoff document**: a single Markdown file
that lets a *different* Claude session resume this exact work with everything it needs
and nothing it doesn't. The usual trigger is a context window that has shrunk below a
comfortable level — capture the state now, while you still remember it clearly, so the
detail isn't lost to compaction.

The reader is another instance of you — but a *machine* reader (the future `continue`
skill), starting cold in this same repository, that parses the document to pick up the
work. So the document has two obligations at once:

- **Conform exactly to the format contract** so `continue` can find and parse it. The
  contract — file location, filename, frontmatter schema, the fixed set of required
  sections, and the content rules — lives in
  **[`references/handoff-format.md`](references/handoff-format.md)**. Read it first and
  follow it to the letter; this SKILL does not restate the schema.
- **Read well for that reader.** Give it the *situation* and let it decide *how* to act.
  The sections below are the judgement — what makes each part of the document actually
  useful — that the contract's structure can't capture on its own.

## Before you write: gather real state

Do not write from memory alone — the session that triggers a handoff has often already
lost detail to compaction. Ground the document in observable state:

- **Git footing** for the frontmatter and `## Starting state`: current branch
  (`git branch --show-current`), `HEAD` SHA (`git rev-parse HEAD`), whether that commit
  is pushed, working-tree status (`git status --porcelain`), and files changed this
  session.
- **Work-in-progress:** if the tree is dirty, decide per the contract's WIP policy. The
  recommended move is to **checkpoint-commit the WIP first** so it travels to a fresh
  checkout and `head_sha` anchors it; then record the (now clean) state. If you
  deliberately leave WIP uncommitted, list every dirty file *with the intent of its
  change* so `continue` can reconstruct it — never rely on an embedded diff.
- **On-disk docs** worth referencing (specs, plans, ADRs) and the exact sections that matter.
- **Live artifacts:** open PRs/issues, running servers, environment set up this session.

## What each section is really for

The contract names the required sections; this is how to fill them so the pickup succeeds.

- **Goal** — the *why*, not just the what. Enough that `continue` recognises success when it arrives.
- **Starting state** — the verifiable footing. Make it checkable (branch, SHA, pushed?,
  dirty files + intent), because this is what lets `continue` confirm it is standing
  where the rest of the document assumes before it touches anything.
- **Completed** — be concrete and honest. Include **dead ends and *why* they were
  abandoned** so the reader doesn't repeat them, and flag anything attempted but not
  yet verified.
- **Outstanding & next steps** — the sequence you'd take next, as *intent and direction*
  ("get the failing auth test green, then wire the handler"), never keystrokes to paste.
  Name the exact test id / file / branch, but leave the method open.
- **Definition of done** — the acceptance criteria plus the concrete way to verify them,
  so `continue` can tell when it is finished rather than guessing.
- **Decisions made** vs **Open questions** — separate what is settled (don't let the
  reader relitigate it) from what genuinely needs a human (make the reader stop and ask,
  not decide unilaterally). Miscategorising here is the difference between a smooth
  pickup and a wrong turn.
- **Skills / agents / workflows** — the reader may not discover these on its own; name
  the specific tools (a project's `/verify`, a domain skill, a specialist agent) and
  *when* each applies.
- **References** — point at on-disk docs by path + section; **do not paste their
  contents.** Copying wastes space and goes stale; the handoff is the connective tissue,
  not a duplicate.
- **Environment** — split what *survives* a fresh session (committed/pushed code, PRs)
  from what the reader must *re-establish* (dev servers, exported env vars, local auth).
  Otherwise `continue` assumes a server is up that isn't.
- **Notes & gotchas** — conventions the repo enforces, traps hit this session, PR/issue links.

## The two hard rules (from the contract — do not break them)

- **Do not reproduce documents already on disk.** Reference them by path and section.
- **Do not script exact prompts or commands to run next.** Trust the reader's judgement
  and creativity for *how*. Concrete facts — a branch, a test id, a file path, a SHA, a
  URL — are welcome and must be exact; a prescriptive command line to paste is not.

## Procedure

1. **Read the contract** (`references/handoff-format.md`) so the output conforms.
2. **Gather real state** as above — git footing, WIP decision, docs to reference, live artifacts.
3. **Draft the document** to the contract's structure, filling each section per the
   guidance above. Complete but tight — every line earns its place for the reader.
4. **Compute the path and write the file** exactly where and how the contract specifies
   (canonical `~/.claude/handoffs/`, `<project>-<timestamp>.md`, frontmatter + fixed
   sections). Keep the shell portable — Linux + macOS, bash 3.2; use
   `date +%Y%m%d-%H%M%S` for the filename and `date +%Y-%m-%dT%H:%M:%S%z` for the
   `created` timestamp, and avoid GNU-only flags.
5. **Report back** to the user: the full path to the handoff file and a 2–3 line summary
   of what it captures, so they can eyeball it and hand it to the next session.

Do not commit the handoff document itself, and do not open a PR — it is a working
artifact, not a deliverable. (Checkpoint-committing the *code* WIP in step 2 is
separate and expected.)
