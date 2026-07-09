# Handoff document format — the `handoff` ↔ `continue` contract

This is the **single source of truth** for the shape, location, and naming of a handoff
document. The `handoff` skill *writes* documents that conform to this spec; a future
`continue` skill *reads* them by relying on it. Both skills bind to this file — change
the contract here, in one place, and bump `schema_version` when the change is breaking.

The current schema is **version 1**.

---

## 1. Location & discovery

**Canonical directory:** `~/.claude/handoffs/`
Chosen because it is outside any git repo (never committed) and is a stable, predictable
place `continue` can scan.

**Fallback directory** (only when `$HOME` is genuinely unavailable):
`${TMPDIR:-/tmp}/claude-handoffs`. Both skills apply this identical rule — `continue`
checks the canonical directory first, then the fallback. A handoff is never written
inside the repo working tree.

**Filename:** `<project>-<YYYYMMDD-HHMMSS>.md`
- `<project>` — the basename of the repo root (human-friendly label only; it is **not**
  the matching key, see below). Example: `nyx-claude-20260709-143005.md`.
- The timestamp uses `date +%Y%m%d-%H%M%S`, so filenames **sort lexically = chronologically**.

**Matching (which document `continue` loads):**
1. Filter to documents whose frontmatter `repo_root` **or** `remote` matches the repo
   `continue` is running in. The filename basename is a label and may collide across
   checkouts — never match on it.
2. Of those, ignore any with `status: consumed`.
3. Pick the **newest** remaining by frontmatter `created` (equivalently, by the
   timestamp in the filename).

---

## 2. File structure

A conforming document is: **YAML frontmatter** (required machine header) followed by a
**fixed set of `##` sections** (required — present even when empty).

### 2.1 Frontmatter (required machine header)

```yaml
---
schema_version: 1
project: <repo-root basename>
repo_root: <absolute path to repo root>
remote: <origin remote URL, or "" if none>
branch: <current branch name>
head_sha: <full HEAD commit SHA>
branch_pushed: <true|false>          # is HEAD present on the remote branch?
working_tree: <clean|dirty>
created: <ISO 8601, e.g. 2026-07-09T14:30:05+0000>
status: open                         # open → consumed (set by continue when done)
supersedes: <filename of the prior handoff for this repo, or "">
---
```

Every key is required. Use `""` for genuinely-absent string values (`remote`,
`supersedes`); never omit a key. `schema_version` MUST be the integer `1` for this spec.

### 2.2 Sections (required, fixed headings, in this order)

Every heading below MUST appear, spelled exactly, even when it has no content — in that
case write `None.` under it rather than dropping the heading. This fixed shape is what
lets `continue` parse reliably.

| # | Heading | Purpose |
|---|---------|---------|
| 1 | `## Goal` | The over-arching objective — the *why*, enough to recognise success. |
| 2 | `## Starting state` | The verifiable footing (see §3). |
| 3 | `## Completed` | What is actually done — decisions, files, approaches tried **and dead ends with why they were dropped**. Flag anything not yet verified. |
| 4 | `## Outstanding & next steps` | What remains, in the order you'd tackle it, as *intent and direction* — not scripted commands. |
| 5 | `## Definition of done` | Acceptance criteria **and** how to verify them (exact test id, a `/verify`-style skill, the command family) so `continue` can self-check completion. |
| 6 | `## Decisions made (do not relitigate)` | Settled choices `continue` must respect rather than reopen. |
| 7 | `## Open questions (needs human)` | Things `continue` must **stop and ask** about rather than decide unilaterally. |
| 8 | `## Skills / agents / workflows to use` | Named skills/subagents/slash-commands/workflows that fit the remaining work, and *when* each applies. |
| 9 | `## References (on disk — read, don't duplicate)` | Repo-root-relative paths to specs/plans/ADRs/docs **plus the specific section that matters**. Never paste their contents. |
| 10 | `## Environment` | Split into **Durable** (committed/pushed/PRs — survives a fresh session) and **Ephemeral to re-establish** (dev servers, exported env vars, local auth — gone in a new session). |
| 11 | `## Notes & gotchas` | Conventions the repo enforces, traps hit this session, PR/issue links — anything a cold reader would otherwise rediscover. |

---

## 3. The `## Starting state` section

This section makes the tree state **verifiable**, not prose, so `continue` can confirm
it is standing where the narrative assumes. It MUST contain:

- **Branch & commit:** `branch` and `head_sha` (mirroring the frontmatter), stated so
  `continue` can `git rev-parse HEAD` and compare.
- **Pushed?** whether `head_sha` is on the remote (`branch_pushed`), so a fresh clone
  knows whether it can fetch the work or must reconstruct it locally.
- **Uncommitted work:** if `working_tree: dirty`, a list of the dirty files **with the
  intent of each change** (what it is mid-doing), so the state is legible even where the
  literal diff isn't present.
- **How to verify:** an explicit check for `continue` to run before acting — at minimum
  "confirm `HEAD` == `<head_sha>`; if the branch has moved, reconcile before proceeding."

**Work-in-progress policy:** the author is *recommended* (not required) to
checkpoint-commit uncommitted work before handing off, so it travels to a fresh
checkout; `head_sha`/`branch_pushed` then anchor it. If WIP is deliberately left
uncommitted, that is legal — it must be captured in the dirty-files list above so
`continue` can reconstruct or resume it. The document never embeds a full `git diff`
(it bloats and goes stale); it points at committed state and describes uncommitted state.

---

## 4. Content rules (binding)

These hold across every section:

- **Reference, don't reproduce.** Documents already on disk (specs, plans, ADRs,
  READMEs) are cited by **path + section**, never copied. The handoff is the connective
  tissue between those documents and the live state.
- **Direction, not commands.** Describe *what* the next step achieves and its
  constraints; leave *how* to `continue`'s judgement. Do not script prompts or command
  lines to paste.
- **But facts must be exact.** Identifiers are not "method" and must be precise:
  file paths, test ids, branch names, commit SHAs, and URLs are stated verbatim. "Get
  the failing auth test green" names the exact test id/path; the approach stays open.
- **Paths are repo-root-relative** (matching `repo_root`), since `continue` may start
  from a different working directory.
- **Empty means `None.`** A section with nothing to say still appears, with `None.`
  under it. Never drop a heading.

---

## 5. Reader contract (what `continue` may rely on, and must do)

A conforming reader:

1. **Discovers** the document per §1 (match on `repo_root`/`remote`, skip `consumed`,
   newest `created`).
2. **Verifies footing** per §3 before acting: compare `HEAD` to `head_sha`; if the
   branch moved or the tree differs from what `## Starting state` describes, reconcile
   (or surface the mismatch) rather than plough ahead.
3. **Re-reads primary sources** listed in `## References` into its own context — the
   handoff is a map, not a replacement for the specs it points at.
4. **Respects boundaries:** treats `## Decisions made` as settled, and **stops to ask**
   on anything under `## Open questions` instead of deciding unilaterally.
5. **Self-checks** against `## Definition of done`.
6. **Closes the loop:** on successful pickup, sets the document's `status: consumed`
   (so it is not re-selected) and, when continuing further, may write a fresh handoff
   whose `supersedes` points at the one just consumed.

---

## 6. Versioning

`schema_version` is an integer. Additive, backward-compatible changes (a new optional
section that readers may ignore) do not bump it. Any change that would break a v1 reader
— renaming/removing a required section or frontmatter key, changing the matching rules —
bumps the version, and both skills branch on `schema_version` to stay compatible with
older documents on disk.
