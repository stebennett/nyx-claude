---
name: handoff
description: Distil the current Claude Code session into a single self-contained handoff document that a fresh session can read to continue the work. Invoke MANUALLY when the context window is shrinking below a comfortable level and you want to hand the work off before detail is lost. Captures the session's goal, work done, outstanding work with recommended next steps, and which skills/agents/workflows to reach for — while pointing at (never copying) spec/plan files already on disk. Writes the document OUTSIDE the git repo. A future 'continue' skill reads it back.
---

# handoff — hand this session off to a fresh one

You are being invoked, by hand, to write a **handoff document**: a single Markdown
file that lets a *different* Claude session resume this exact work with everything it
needs and nothing it doesn't. The usual trigger is a context window that has shrunk
below a comfortable level — capture the state now, while you still remember it clearly,
so the detail isn't lost to compaction.

The reader of this document is another instance of you: intelligent, capable, and
starting cold in this same repository. Write for that reader. Give it the *situation*
and let it decide *how* to act — do not script its keystrokes.

## What the document must contain

Draw all of this from the actual conversation and work so far — never invent state.

1. **The over-arching goal.** What is this session ultimately trying to achieve? The
   why, not just the what. Enough that the reader understands success when they see it.
2. **Work completed so far.** What has actually been done — decisions made, files
   created or changed, approaches tried (including dead ends and *why* they were
   abandoned, so the reader doesn't repeat them). Be concrete and honest: if something
   was attempted but not verified, say so.
3. **Outstanding work + recommended next steps.** What remains, and the sequence you'd
   take next. Frame next steps as *intent and direction* ("get the failing auth test
   green, then wire the handler"), not as literal commands to paste. Flag anything
   blocked, uncertain, or awaiting a decision.
4. **Skills, agents, and workflows to use.** Name the specific skills, subagents, slash
   commands, or workflows that fit the remaining work (e.g. a project's `/verify`,
   a domain skill, a specialist agent) and *when* each applies. The reader may not
   discover these on its own — point the way.
5. **Anything else that ensures a clean pickup.** Current git branch, dirty working
   tree, running processes/servers, environment quirks, credentials or access already
   set up, conventions the repo enforces, gotchas hit this session, links to relevant
   PRs/issues — whatever a cold-starting reader would otherwise have to rediscover.

## What the document must NOT contain

- **Do not reproduce documents already on disk.** Spec files, plan files, design docs,
  ADRs, READMEs already in the repo — reference them by **path** (and the specific
  section that matters) and let the reader open them into its own context. Copying them
  wastes space and goes stale. The handoff is the *connective tissue* between those
  documents and the live state, not a duplicate of them.
- **Do not script exact prompts or commands to run next.** Trust the reader's judgement
  and creativity to choose *how* to accomplish each next task. Describe the goal and the
  constraints; leave the method to them. (Concrete facts — a branch name, a test id, a
  file path, a URL — are fine and welcome; a prescriptive command line to paste is not.)

## Where to write it

The document lives **outside the git repository** so it never gets committed and doesn't
clutter the tree — this session's repo is a checkout the reader also has.

1. Determine the repo root and a project name:
   - `root="$(git rev-parse --show-toplevel 2>/dev/null)"`
   - project name = the basename of `$root` (fall back to the basename of the current
     directory if not in a git repo).
2. Choose the output directory `~/.claude/handoffs` and create it:
   `mkdir -p "$HOME/.claude/handoffs"`. (This is a stable, predictable location the
   future `continue` skill can look in.)
3. Build a filename from the project and a timestamp:
   `ts="$(date +%Y%m%d-%H%M%S)"` → `"$HOME/.claude/handoffs/<project>-<ts>.md"`.
   Example: `~/.claude/handoffs/nyx-claude-20260709-143005.md`.

Keep the shell portable (Linux + macOS, bash 3.2): use `date +%Y%m%d-%H%M%S`, avoid
GNU-only flags. If `$HOME` is unavailable for any reason, fall back to the system temp
dir (`${TMPDIR:-/tmp}/claude-handoffs`) rather than writing inside the repo.

## Format

Markdown, optimised for another Claude to read fast. Lead with a short header block —
project, timestamp, git branch, one-line goal — then the sections above under clear
`##` headings. A suggested skeleton (adapt to the session; drop sections that truly
don't apply):

```markdown
# Handoff — <project>

- **Created:** <ISO timestamp>
- **Repo / branch:** <root> @ <branch>
- **Working tree:** <clean | dirty — summary>

## Goal
<the over-arching objective>

## Completed
<what's done, with file paths and decisions; note anything unverified>

## Outstanding & next steps
<what remains, in the order you'd tackle it; direction not commands>

## Skills / agents / workflows to use
<named tools that fit the remaining work, and when each applies>

## References (already on disk — read these, don't re-read here)
<paths to specs/plans/docs + the sections that matter>

## Notes & gotchas
<environment, running processes, conventions, traps, PR/issue links>
```

## Procedure

1. **Gather state before writing.** Check the live context you can observe, not just
   your memory: current branch and working-tree status (`git status`, `git branch
   --show-current`), any files changed this session, and the on-disk docs worth
   referencing. This grounds the document in reality.
2. **Draft the document** from the conversation and that gathered state, honouring the
   contains / must-not-contain rules above. Be complete but tight — every line should
   earn its place for the reader.
3. **Write the file** to the computed path.
4. **Report back** to the user: the full path to the handoff file and a 2–3 line
   summary of what it captures, so they can eyeball it and hand it to the next session.

Do not commit the file, and do not open a PR — the handoff is a working artifact, not a
deliverable.
