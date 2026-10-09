---
name: engineering-standards-assess
description: Assess the current repository against the Home Projects Engineering Standards and write the scored report to docs/assessment.md. Requires a tag from engineering-standards-classify.
disable-model-invocation: true
---

# engineering-standards-assess

You are the coordinator of an assessment against the bundled standards
(`references/standards.md`, machine form `references/rubric.json`). Scripts score the mechanical
criteria and do all arithmetic; `es-checker` agents run those scripts; `es-assessor` agents score
the judgment criteria. You orchestrate, write the Actions, and report. Keep your own context lean:
hold plans, file paths and one-line agent results, and let the files carry the records.

Work on the current working directory, headless: everything you need comes from the tag in
`.nyx.yml`. You write `docs/assessment.md` and files in your run directory, and leave committing
to the user.

Throughout, `$P` is `${CLAUDE_PLUGIN_ROOT}` and `$REPO` is the output of `pwd -P`.

## Steps

1. **Plan.** Create a run directory with `mktemp -d "${TMPDIR:-/tmp}/es-assess.XXXXXX"` (call it
   `$RUN`), then run `bash "$P/scripts/plan.sh" "$REPO" < /dev/null > "$RUN/plan.json"`.
   A non-zero exit is the gate refusing: no tag, an invalid or archived tag, a version mismatch,
   or a missing `jq`/`yq`. Relay its message verbatim — it names the fix, usually
   `/engineering-standards-classify` — and stop. Otherwise save the warnings with
   `jq .warnings "$RUN/plan.json" > "$RUN/warnings.json"`.

2. **Run the checks.** Dispatch one `es-checker` agent (`engineering-standards:es-checker`) per
   entry in `plan.groups`, all in a single message so they run in parallel, each with:
   `group`, `repo: $REPO`, `script: $P/scripts/checks/group-<n>.sh`, `out: $RUN/script-<n>.json`.
   Any `"status": "error"` result is a script failure: report the group and its error and stop.

3. **Score the judgment criteria.** Dispatch one `es-assessor` agent
   (`engineering-standards:es-assessor`) per group whose `judgment` list is non-empty, all in a
   single message, each with: `group`, `repo: $REPO`, `tag` (from `plan.tag`), `criteria` (that
   group's `judgment` list, verbatim), `checker_out: $RUN/script-<n>.json`,
   `standards: ${CLAUDE_PLUGIN_ROOT}/skills/engineering-standards-assess/references/standards.md`,
   `out: $RUN/judgment-<n>.json`.

4. **Score.** Merge and score:
   `jq -s add "$RUN"/script-*.json "$RUN"/judgment-*.json > "$RUN/records.json"`, then
   `bash "$P/scripts/score.sh" "$REPO" "$RUN/records.json" > "$RUN/scored.json"`.
   Exit 6 lists missing, duplicate, invalid or unknown records by ID. For judgment IDs, dispatch
   the owning group's `es-assessor` again with only those criteria and
   `out: $RUN/judgment-<n>-retry.json`, drop the bad entries from the original file with `jq`, and
   re-merge and re-score — once. A script ID in that list, or a second failure, is a bug: report
   the error and stop.

5. **Write the Actions.** From `$RUN/scored.json`, take every criterion with `applicable: true`
   and a score of 0 or 1. Write `$RUN/actions.json` as an array of
   `{"id", "action", "target_level"}`, one entry per such criterion, ordered by level (L1 first)
   then rubric order. `target_level` is the criterion's level. The `action` is one imperative
   sentence specific to this repository, built from the criterion's evidence: name the file,
   recipe, workflow step or setting to add or change ("Add a `migrate` recipe running `goose up`",
   not "Implement migrations"). For an unverified criterion whose only gap is confirmation, the
   action says what to confirm and where. The step is done when every such criterion has exactly
   one action.

6. **Render.** Compare with the previous report before overwriting it, then render:
   `bash "$P/scripts/delta.sh" docs/assessment.md "$RUN/scored.json" > "$RUN/delta.json"`,
   `mkdir -p docs`, and
   `bash "$P/scripts/render.sh" "$RUN/scored.json" "$RUN/actions.json" "$RUN/warnings.json" > docs/assessment.md`.

7. **Report.** Give the user a short summary built from `scored.json` and `delta.json`:
   - overall score and maturity level, each with the previous value when `delta.previous` is set;
   - the blocking gate criteria for the next level (and the score it needs, if short);
   - criteria whose score changed since the last report (`delta.changed`);
   - the count of unverified criteria, pointing at "Needs manual confirmation";
   - any warnings — a tag that contradicts the repository means the scores may rest on the
     wrong classification, so suggest re-running `/engineering-standards-classify`.

   Close by saying `docs/assessment.md` was written and is uncommitted.
