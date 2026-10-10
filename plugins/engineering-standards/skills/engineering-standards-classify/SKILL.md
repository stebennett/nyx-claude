---
name: engineering-standards-classify
description: Classify the current repository (type, status, deployment target, database, adopted optional categories, exemptions) and record it in .nyx.yml for engineering-standards-assess.
disable-model-invocation: true
---

# engineering-standards-classify

Record what kind of project this repository is, so `/engineering-standards-assess` knows which
criteria apply. You infer, the user confirms, then you write. The classification lives in the
`engineering_standards:` section of `.nyx.yml` at the repo root; other keys in that file belong to
other tools and stay as they are. `scripts/tag.sh` writes only that section.

Work on the current working directory. You write `.nyx.yml` and nothing else, and you leave
committing to the user.

## Steps

1. **Detect.** Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect.sh" .`. A non-zero exit names a
   missing dependency (`jq`, or mikefarah `yq` v4); relay the install hint and stop. The output has
   `signals`, a `proposed` value and a `reasons` entry for every field, and `existing` (the current
   section, or `null`).

2. **Refine the proposal.** The script's guesses are heuristics. Read the README's opening and
   anything the signals make ambiguous (e.g. a `Dockerfile` with no server framework, both
   PostgreSQL and SQLite references) and correct a proposed value when the evidence says
   otherwise, rewriting its reason. Definitions you are classifying against, in
   `${CLAUDE_PLUGIN_ROOT}/skills/engineering-standards-assess/references/standards.md`:
   - **type**: section 3 (Service, Library, CLI, Infrastructure — one primary type).
   - **database** and **lightweight**: the DAT preamble. SQLite used only for test fixtures or a
     CLI's single-user local state is still `sqlite`; lightweight means all three DAT conditions.
   - **optional_categories**: categories marked `O` for the chosen type in the section 3
     applicability matrix, scored only if the repo has adopted them. `DAT` applies only when
     `database` is not `none`.

   The step is done when every field has a value you can defend from evidence in the repo.

3. **Confirm.** Ask with `AskUserQuestion`, putting your value first and labelled
   "(Recommended)", with its reason as the description. When `existing` is set and differs from
   your value, offer the existing value as the second option and say so.
   - First call: `type`, `deployment_target`, `database`, `status`.
   - Second call, built from the confirmed answers: `lightweight` (only when `database` is
     `sqlite` or `d1`; otherwise it is `false`), `optional_categories` (multi-select over the `O`
     categories for the confirmed type, with your adoption evidence per option; skip the question
     when there are none), and exemptions — keep `existing.exemptions` if any, and ask whether to
     add one. An exemption is a criterion ID plus a one-line justification for marking it N/A;
     take both from the user's "Other" answer.

   The step is done when the user has answered every question you asked.

4. **Write.** Put the confirmed values in a JSON object with exactly the keys `type`, `status`,
   `deployment_target`, `database`, `lightweight`, `optional_categories`, `exemptions` in a temp
   file under your scratchpad, then run
   `bash "${CLAUDE_PLUGIN_ROOT}/scripts/tag.sh" write . <file>`. It stamps `schema_version` and
   `framework_version`, validates, and prints the written section. On a validation error, fix the
   value with the user and write again.

5. **Report.** Show the written section, say `.nyx.yml` is uncommitted, and point the user at
   `/engineering-standards-assess`. If `status` is `archived`, say instead that archived
   repositories are not assessed.
