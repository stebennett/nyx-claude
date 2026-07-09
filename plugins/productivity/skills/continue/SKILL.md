---
name: continue
description: Pick up work handed off from a previous Claude Code session by reading its handoff document, verifying the footing, and proposing a continuation plan for the user to approve BEFORE any work begins. Invoke MANUALLY at the start of a fresh session that is resuming earlier work — optionally passing the handoff file path. Binds to the handoff-format contract written by the 'handoff' skill. NEVER starts the work without explicit user authorisation.
---

# continue — resume work from a handoff document

You are picking up work that a previous Claude Code session handed off. Your job in this
skill is **not** to do that work yet — it is to **understand it, verify you can safely
resume it, and propose a plan the user signs off on first**.

You are the *reader* half of the handoff contract. The document you consume was written
to **[`../handoff/references/handoff-format.md`](../handoff/references/handoff-format.md)**
— read that contract first; it defines the frontmatter, the fixed sections, and the
reader obligations you must honour. This SKILL is the procedure for honouring them.

> **The one inviolable rule:** you MUST present a continuation plan and receive explicit
> authorisation from the user before making any change to code, files, git state, or the
> outside world. No edits, no commits, no commands that mutate anything, until the user
> says go. If you are ever unsure whether you have authorisation — you do not. Ask.

## 1. Locate the handoff document

- **If the user gave a path** (as an argument or in their message), use it directly.
- **Otherwise, discover it** per the contract's matching rules: scan the canonical
  directory `~/.claude/handoffs/` (then the fallback `${TMPDIR:-/tmp}/claude-handoffs`),
  keep only documents whose frontmatter `repo_root`/`remote` matches the repo you are in,
  ignore any with `status: consumed`, and choose the **newest** by `created`.
- **If several plausibly match** (e.g. multiple open handoffs for this repo), do not
  guess — list the candidates with their `created` timestamps and one-line goals and ask
  the user which to resume.
- **If none is found**, say so plainly and ask the user for the path rather than inventing one.

## 2. Load and validate

- Parse the frontmatter and confirm `schema_version` is one you understand. If it is
  newer than this skill knows, say so and proceed cautiously (rely only on fields you
  recognise), or ask the user how to proceed.
- Confirm the required sections are present. If the document is malformed or truncated,
  surface exactly what is missing rather than filling gaps with assumptions.

## 3. Verify the footing — before trusting the narrative

The document describes work relative to a specific starting state. Confirm you are
actually standing there **before** you build a plan on top of it:

- Compare the current commit to the recorded `head_sha` (`git rev-parse HEAD`). If they
  differ, the branch has moved since the handoff was written — determine how (ahead,
  behind, diverged) and treat the document's "completed" claims as needing
  re-confirmation.
- Check the branch (`git branch --show-current`) against the recorded `branch`, and the
  working tree (`git status --porcelain`) against what `## Starting state` describes
  (clean, or the listed dirty files).
- If `branch_pushed` is false and you are in a fresh clone, the recorded commit may not
  be present — you may need to fetch it or reconstruct uncommitted work from the
  `## Starting state` description.
- **Any mismatch is a finding, not a blocker to hide.** Note it and carry it into the
  plan you present — never silently plough ahead on a tree that differs from what the
  document assumes.

## 4. Re-read the primary sources

The handoff is a *map*, not a replacement for the documents it points at. Open every
path listed under `## References` (specs, plans, ADRs — the specific sections named) into
your own context, plus the key files the `## Completed` and `## Outstanding` sections
touch. Ground your understanding in the actual repo, not just the summary.

## 5. Build the continuation plan

Now use your own judgement — this is where the handoff trusts the reader. The document
gives you *direction*, not commands; turn it into a concrete plan of *how you intend to
proceed*, informed by what you just read in the repo. The plan you present to the user
should cover:

- **Goal (restated) & definition of done** — confirm your understanding of the objective
  and the acceptance criteria / verification from the document, so the user can correct
  any drift.
- **Footing summary** — where the repo actually is versus where the document expects it,
  including any mismatch found in step 3 and how you propose to reconcile it.
- **Your proposed steps** — the concrete sequence you intend to take, derived from
  `## Outstanding & next steps` but reasoned through against the real code. Name the
  skills, agents, and workflows from `## Skills / agents / workflows to use` (and any
  others you judge appropriate) and where each applies.
- **Boundaries you will respect** — restate the settled items from `## Decisions made`
  you will not reopen, and surface every `## Open questions (needs human)` item to the
  user now, since some may need answering before you can proceed.
- **Risks / unknowns** — anything unverified, missing, or ambiguous that could change the
  approach.

Keep it reviewable: the user should be able to read the plan and know exactly what you
will do, in what order, and where their input is still needed.

## 6. Stop and get authorisation

Present the plan and **wait**. Do not begin work.

- If the harness offers a plan-approval gate (plan mode), use it so the user's approval
  is explicit.
- Otherwise, ask the user directly to confirm the plan (or amend it). Treat silence,
  ambiguity, or a mere acknowledgement as **not** authorisation.
- If the user requests changes, revise the plan and present again. Loop until they
  explicitly approve.
- If `## Open questions` items are unanswered and block the first steps, get those
  answers as part of this gate.

## 7. On the go-ahead

Only after explicit authorisation:

1. **Mark the handoff consumed.** Set the document's frontmatter `status: consumed` so it
   is not re-selected by a future `continue`. (This edits the handoff file outside the
   repo, not repo code.)
2. **Execute the approved plan**, honouring the boundaries: never relitigate a
   `## Decisions made` item, and **stop to ask** the moment you hit an `## Open questions`
   matter or anything the plan did not cover and the user did not authorise.
3. **Self-check against the definition of done** before calling the work finished.
4. **If the context window shrinks again** before the work is complete, invoke the
   `handoff` skill to write a fresh handoff whose `supersedes` points at the one you just
   consumed — continuing the chain.

## Guardrails

- No mutation of code, files, git, or the outside world before step 7. Reading,
  searching, and running read-only inspection commands to build the plan is expected;
  anything that changes state is not.
- Never fabricate document contents, referenced files, or completed work. If something
  the handoff claims cannot be verified, say so in the plan.
- The user's authorisation is for *the plan you presented*. A materially different course
  of action needs fresh authorisation.
