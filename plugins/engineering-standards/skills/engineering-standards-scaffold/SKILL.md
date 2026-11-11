---
name: engineering-standards-scaffold
description: Initialise a new repository to the Home Projects Engineering Standards before implementation starts. Use when asked to start implementing in a repository that is empty or holds only specification and design documentation. Records the classification in .nyx.yml, then builds the tooling, CI, deployment config, docs and a walking skeleton from the spec's technology decisions, verifies it with the standards checks, and commits locally. Run it in the main session, never from a subagent or inside a kanban-flow card worktree — kanban-flow users run it before /kanban starts implementing.
---

# engineering-standards-scaffold

Turn a spec's technology decisions into a standards-conformant skeleton, so the first feature is
built on the right foundations. You check the repo is new, settle the decisions, confirm the build
with the user, write `.nyx.yml` first, generate the skeleton, verify it with the standards checks,
and commit it locally. You build no features: those come afterwards, through kanban-flow or a plan.

Work on the current working directory. Never create or overwrite a file that already exists, never
delete anything, and never push. If a hook blocks a write or command (for example code-safely's
`protect-claudemd.sh` on `CLAUDE.md`), do not work around it: show the user what you meant to write
and ask them to create it or allow it. Throughout, `$P` is `${CLAUDE_PLUGIN_ROOT}`.

## Steps

1. **Preflight.** Run `bash "$P/scripts/scaffold-preflight.sh" . < /dev/null`. A non-zero exit
   names a missing dependency (`jq`, or mikefarah `yq` v4); relay the install hint and stop.
   - `verdict: populated` — stop. Name the non-documentation files (`non_doc_files`), say scaffold
     is only for new repositories, and point at `/engineering-standards-classify` and
     `/engineering-standards-assess` for existing ones.
   - `worktree: secondary` — stop. Say scaffold runs in the main checkout, before any kanban-flow
     card work starts.
   - `nested: true`: the directory sits inside another git repository, and scaffolding there
     would stage and commit that repository's changes. Stop, and ask whether to make this
     directory its own repository (`git init -b main` here, then re-run preflight) or to
     scaffold elsewhere.
   - `git: false`: run `git init -b main`.

   The step is done when the verdict is `empty` or `docs-only` and you are in a main checkout.

2. **Settle the decisions.** Find the spec: Markdown files in `docs/` and the repo root containing
   `## Technology decisions`. If several, ask which with `AskUserQuestion`. The section's format is
   in `../engineering-standards-advise/references/decisions-format.md`.
   - If no spec has the section, the section is missing required rows, or it is stamped with a
     framework version other than the one in
     `${CLAUDE_PLUGIN_ROOT}/skills/engineering-standards-assess/references/standards.md`, follow
     `../engineering-standards-advise/SKILL.md` now against the spec — including its conflict
     check on the spec text. This updates the spec before anything is built.
   - If there is no spec at all (an empty repo), run the advise flow in conversation and record the
     decisions in `docs/spec.md` under a one-paragraph description the user gives you.

   The step is done when the spec has a complete, current decisions section.

3. **Confirm the build.** Read `references/scaffold-checklist.md`. Show the user, briefly: the
   decisions; the files and directories you will create (the entries that apply); any entries you
   will skip because a kept exemption changes the stack; and any path that already exists and will
   be left alone. Ask with `AskUserQuestion`:
   - the licence: a named licence (recommend MIT for public code) and its copyright holder, or
     private and unlicensed;
   - the module path or package name:
     - Go: `github.com/<owner>/<repo>`, recommended from the git remote or the `gh` login;
     - Python/npm: the package name from the spec;
   - when a `dhi.io` image is needed: whether they are logged in to `dhi.io` (`docker login dhi.io`)
     so its tags and digests can be pinned now;
   - which optional categories to adopt, asked only when the section 3 matrix offers `O`
     categories beyond those the decisions already imply (see `decisions-format.md`);
   - go ahead, or change something.

   Nothing is written until the user says go ahead.

4. **Write the tag.** Map the decisions to the tag per `decisions-format.md` into a JSON file under
   your scratchpad with exactly the keys `type`, `status`, `deployment_target`, `database`,
   `lightweight`, `optional_categories`, `exemptions`, then run
   `bash "$P/scripts/tag.sh" write . <file>`. On a validation error, fix the value with the user
   and write again. `.nyx.yml` now exists even if a later step fails.

5. **Generate the skeleton.** Work through every checklist entry that applies, in the checklist's
   order. Look up each version per its "Version lookup" table at the moment you write it; never
   guess a version or copy one from the worked example. Before writing each path, check it does
   not exist; if it does, skip it and note it for the report. Write only `Stack-neutral: yes`
   entries, and note the rest as left to the user, in two cases: a kept exemption changes the
   stack, or the checklist has no entry for the combination (e.g. a Go or Python backend on
   Cloudflare Workers). Never improvise a stack the checklist doesn't cover. Generate
   lockfiles with the real tool (`go mod tidy`, `uv lock`, `npm install`) when it is available on
   the host; otherwise note DEP-1 as pending until `just setup` runs in the Dev Container.

6. **Verify.**
   1. `git add -A .`, because the checks read only tracked files.
   2. `bash "$P/scripts/scaffold-verify.sh" . < /dev/null`. Exit 6 means a check group crashed,
      usually on a file you generated (e.g. invalid YAML). Fix that file and re-run, and never
      report a result from a failed run. For each entry in `gaps`, decide:
      a checklist entry should have satisfied it → fix the file and re-run; it needs GitHub, a
      secret, a real CI run or a human (marked `unverified`, or listed in the checklist's "Out of
      scope") → report it, do not fake it. Repeat until only reportable gaps remain.
   3. If `just` and the language toolchain (Go, uv/Python or Node) are on the host, run
      `just setup` then `just check`, and fix failures until it passes. Do not install global
      tools to make this work. If a recipe step needs a tool only the Dev Container provides
      (e.g. `pre-commit install`), report it rather than forcing it. If `just check` cannot run,
      say plainly that it was not run and must be run inside the Dev Container — never claim it
      passes.

   VCS-2 ("no git history") stays a gap until step 7's commit. VCS-1 reads the current branch, so
   it shows as a gap whenever the commit lands on `chore/scaffold`; that is expected, and it clears
   once the branch merges. The step is done when every remaining gap has a reason you can state.

7. **Commit locally.** If the repo had no commits at step 1 (`commits: false`), make the initial
   commit on `main`. Otherwise create the branch first with `git switch -c chore/scaffold`.
   Commit everything you generated plus the updated spec with a Conventional Commit message,
   `chore: scaffold <project name from the spec> per engineering standards`, with the session's
   attribution trailer once, at the end. Never push. Then re-run `scaffold-verify.sh` for the
   report.

8. **Hand off.** Report:
   - what was created, and anything skipped (existing paths, stack-neutral skips) and why;
   - the criteria `scaffold-verify.sh` shows as met, and each remaining gap with its reason;
   - whether `just check` ran and passed;
   - remote follow-ups only the user can do: push and open a PR (if on `chore/scaffold`), the
     `main` branch ruleset (VCS-3), the `DHI_USERNAME`/`DHI_TOKEN` Actions secrets for `dhi.io`,
     installing the Renovate app (DEP-2), the ArgoCD Application in the GitOps repo (DPL-6, for
     Kubernetes), and platform tokens (`FLY_API_TOKEN` / `CLOUDFLARE_API_TOKEN`) for deploys.

   Then suggest `/engineering-standards-assess` for a baseline, and kanban-flow (`/kanban-init`,
   `/refine`) or a plan to build the features.
