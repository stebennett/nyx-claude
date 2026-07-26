# Target resolution

How a command-line argument becomes `target_repo`, `target_pr`, `self_login`, a `workdir`,
and a `worktree` to grep for surrounding-code context.

## The resolution table

Three invocation forms — none, a PR number, or a repo reference — resolve to a
`target_repo` (`owner/repo`) and an optional `target_pr`:

| argument | `target_repo` | `target_pr` | mode |
|---|---|---|---|
| *(none)* | origin of the cwd repo | — | queue pass |
| `42` (all digits) | origin of the cwd repo | `42` | single PR |
| `https://github.com/o/r/pull/42` | `o/r` | `42` | single PR |
| `o/r#42` | `o/r` | `42` | single PR |
| `https://github.com/o/r` | `o/r` | — | queue pass |
| `git@github.com:o/r.git` | `o/r` | — | queue pass |
| `o/r` | `o/r` | — | queue pass |

## Disambiguation

Disambiguation is total, not heuristic — every argument falls into exactly one of three
buckets, checked in this order:

1. **No argument at all.** Fall back to the origin of the working directory's repo, queue
   pass, no `target_pr`.
2. **The argument is all digits.** It is a PR number, full stop — never a repo, never
   anything else. `target_repo` is the origin of the working directory's repo; `target_pr`
   is the argument.
3. **The argument contains a `/`.** It is a repo reference (bare `o/r`, a repo URL, an SSH
   remote, or a PR URL/`o/r#42` form that also carries a PR number). Extract `target_repo`
   from it with the recipes below, and `target_pr` too if the form carries one.

If neither rule 2 nor rule 3 matches, and there is no argument and no git repo in the
working directory, that is a hard stop: report exactly what is missing (no target named,
and the working directory is not a git repo) and do nothing else. Never guess a target.

## Extraction recipes

```bash
# from a git remote URL (https or ssh) → owner/repo
origin_repo() {
  git remote get-url origin 2>/dev/null \
    | sed -nE 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+?)(\.git)?$#\2#p'
}

# from a PR URL → owner/repo and number
# https://github.com/o/r/pull/42 → "o/r 42"
parse_pr_url() {
  printf '%s\n' "$1" \
    | sed -nE 's#^https://github\.com/([^/]+/[^/]+)/pull/([0-9]+).*$#\1 \2#p'
}
```

`o/r#42` and bare `https://github.com/o/r` need no recipe beyond a split on `#` and a strip
of the `https://github.com/` prefix respectively — both are one `sed` substitution, not
shown separately because they follow the same pattern as `parse_pr_url` above.

## `self_login`

```bash
self_login=$(gh api user --jq .login)
```

This is what the self-review downgrade compares an authoring PR's `author.login` against
(GitHub 422s an `APPROVE` or `REQUEST_CHANGES` event from a PR's own author). Resolve it
once per pass, in preflight, and reuse it for every PR — it does not change mid-pass and a
repeat `gh api user` call per PR buys nothing.

## Locality decision

The target is **local** when the working directory is a git repo whose `origin_repo`
(the recipe above) equals `target_repo`; every other case — including "not a git repo at
all" and "a git repo whose origin points somewhere else" — is **remote**.

This decision is binary and made once, in preflight, before anything else touches disk.
A remote target must never touch the working directory's repo: no fetch into it, no
worktree added to it, no ref written into it. Remote work happens entirely inside a
separate clone under `workdir` or `clone_cache_dir`; the user's checkout is invisible to it.

## Local worktree recipe

```bash
git -C "$repo" fetch origin "pull/$n/head:refs/pr-reviewer/$n" --force
git -C "$repo" worktree add --detach "$workdir/tree" "refs/pr-reviewer/$n"
```

This touches no branch, no index, and no checked-out file in the user's working tree. The
fetch writes a new ref under `refs/pr-reviewer/`, a namespace reserved for this skill so it
can never collide with a branch or tag the user already has; the worktree is added detached,
so nothing in the user's own checkout moves.

## Remote clone recipe

```bash
git clone --filter=blob:none --no-checkout \
  "https://github.com/$target_repo.git" "$cache/$owner-$repo"
```

The cache path is `clone_cache_dir` when that config key is set, otherwise the session
scratchpad. Either way the clone lands at `$cache/$owner-$repo`.

The clone is **blobless** — `--filter=blob:none` fetches every commit and tree but no file
contents up front, so blobs arrive on demand as the worktree is populated. This keeps a
first touch of a large repository fast. The clone is reused across every PR processed in
the pass, and across passes when run under `/loop`: check whether `$cache/$owner-$repo`
already exists and is a git repository before cloning, and if so, reuse is a `git fetch`,
never a re-clone.

## Cleanup, mandatory after each PR

```bash
git -C "$repo" worktree remove --force "$workdir/tree"
git -C "$repo" update-ref -d "refs/pr-reviewer/$n"
```

Run this after every PR is processed, unconditionally — on success, on a skipped or parked
outcome, and on failure. A local target must be left exactly as found: no stray worktree
directory, no leftover `refs/pr-reviewer/*` ref, no change to the branch the user had
checked out before this pass began. `worktree remove --force` clears the worktree even if
something inside it was modified; `update-ref -d` removes the ref itself rather than merely
letting it go stale.

## The diff is canonical from GitHub

```bash
gh pr diff --repo "$target_repo" "$n" > "$workdir/pr-$n.diff"
```

This is not computed locally, and that is deliberate: inline review comments must anchor to
lines GitHub recognises as part of the diff, and using GitHub's own rendering of the diff —
via `gh pr diff` — is what guarantees the line numbers actually line up with what a reviewer
sees on the PR. A local `git diff` against a different merge base, a different set of
renames, or different whitespace handling would silently desync the anchors.

The worktree (local or remote-clone-backed) exists *only* to give the review lenses
surrounding-code context — callers, conventions, invariants a hunk alone doesn't show. It is
never used to compute the diff itself.
