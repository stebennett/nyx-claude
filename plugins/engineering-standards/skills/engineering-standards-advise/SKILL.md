---
name: engineering-standards-advise
description: Check a specification's technology decisions against the Home Projects Engineering Standards and record them in its "Technology decisions" section. Use whenever a spec, design or requirements document is being written or revised — including during brainstorming and kanban-flow refine or requirement sessions — and it chooses or implies languages, frameworks, databases, deployment targets, packaging, CI or dependency tooling. Also run it by hand to check an existing spec.
---

# engineering-standards-advise

Make sure a spec's technology choices meet the bundled standards *before* anything is built, while
changing a decision is still cheap. You find every decision, sort it, raise conflicts, ask about
what is open, and record the result. The user decides every conflict; you never resolve one on
their behalf, in either direction.

Work on the spec document being written. You write only that document and nothing else, and you
leave committing to whoever owns the spec (the user, or the skill that is writing it).

## Steps

1. **Read the standards.** Read `${CLAUDE_PLUGIN_ROOT}/skills/engineering-standards-assess/references/standards.md`:
   section 2 (mandated stack and `just` recipes), section 3 (project types and applicability
   matrix) and the DAT preamble (lightweight deployments). Note its version line. Read
   `references/decisions-format.md` for the section you will write. The step is done when you can
   name the allowed values for every required row.

2. **Extract.** List every technology decision the spec states or implies (a mention of "React
   dashboard" implies a TypeScript frontend; "nightly sync job on the cluster" implies Kubernetes),
   plus every required row of the decisions section the spec does not settle yet. If the spec
   already has a `## Technology decisions` section, start from it and re-check it. The step is
   done when every required row has either a stated value or is marked open.

3. **Classify** each decision:

   | Class | Meaning | Action |
   |---|---|---|
   | Mandated | Fixed by the standards (`just`, GitHub Actions, Renovate, Docker Hardened Images, Dev Container, Helm for Kubernetes, exact pinning, TypeScript for any frontend) | Nothing to record or ask; mandated choices get no rows |
   | Constrained | The standards allow a short list: project type; backend Go or Python (or none); frontend TypeScript or none; deployment Fly.io, Cloudflare, Kubernetes or none; database PostgreSQL, SQLite/D1 or none | If the spec states a compliant value, record it with Source `spec` and do not re-ask. Otherwise ask, explaining what each option brings with it |
   | Open | The standards are silent (web framework, HTTP router, migration tool, frontend framework …) | Raise only those listed in `decisions-format.md` (stated in the spec, or needed for the walking skeleton). Ask, or suggest when the user hands it over |
   | Conflict | The spec states a choice the standards forbid | Step 4 |

   Consequences to explain for Constrained options, from the standards:
   - **Kubernetes** → Helm chart in `charts/<app>/`, an ArgoCD Application, no `deploy` recipe,
     migrations as a Helm pre-upgrade hook.
   - **Fly.io / Cloudflare** → `fly.toml` or Wrangler config, a `deploy` recipe and workflow,
     preview deployments.
   - **SQLite / D1** → allowed only if all three lightweight conditions hold; single instance on
     persistent storage; Litestream or scheduled backups. Anything else is PostgreSQL.
   - **Library** → bounded ranges in published dependency metadata, no deployment.

4. **Raise conflicts** before any other question, since later choices (an HTTP router, a
   migration tool) depend on the answers. For each conflict, tell the user the choice, every
   criterion ID it would fail (e.g. "Express backend → STK-1", "MySQL → DAT-1", "Dependabot →
   DEP-2, DEP-3, DEP-6") and the compliant alternatives with their trade-offs. Ask with
   `AskUserQuestion` (conflicts may share one call, up to four). The options are:
   - each compliant alternative ("Change the spec to …"), recommended one first;
   - **"Keep <choice> as an exemption"**, as an explicit option, whose description says it makes
     assess score those criteria N/A, and that scaffold will build only the stack-neutral parts if
     it changes the backend language or database.
   For every kept exemption, ask for the reason in a follow-up (free text through "Other"), and
   record one exemption line per failing criterion with that reason.

   The step is done when every conflict has the user's answer.

5. **Ask the rest.** Use `AskUserQuestion` for Constrained and Open decisions, up to four per
   call. Put your recommendation first, labelled "(Recommended)", with a one-line reason drawn from
   the spec. When the user says "you pick", record your suggestion as `advisor-suggestion-accepted`
   — a choice they never heard is one they could not reject, so always name it. `status` and, unless
   the database is SQLite or D1, `lightweight` are not asked (see `decisions-format.md`); for SQLite
   or D1, ask each of the three DAT conditions explicitly. The step is done when every required row
   has a value.

6. **Record.** Write or update `## Technology decisions` in the spec exactly per
   `references/decisions-format.md`, stamped with the standards version from step 1.
   - If the spec file does not exist yet (decisions made mid-conversation), hold the decisions and
     write the section when the spec is written.
   - Where the user chose to change the spec, edit the text that stated the old choice so the spec
     does not contradict itself. Edit nothing else outside the section.
   - Never add, remove or alter REQ id markers (`REQ-NNN`); `req-ids` owns them.

7. **Report.** Summarise the decisions (one line each), any exemptions with their criteria, and
   say that nothing was committed. If the repo is empty or docs-only and implementation is next,
   mention `engineering-standards-scaffold`.
