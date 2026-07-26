# Target resolution

How a command-line argument becomes `target_repo`, `target_pr`, `self_login`, the
locality bindings (`owner`, `repo_name`, `cache`, `git_repo`), a `workdir`, and a `worktree`
to grep for surrounding-code context.

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

Every argument is classified by checking these rules in order, and every argument matches
exactly one:

1. **No argument at all.** Fall back to the origin of the working directory's repo, queue
   pass, no `target_pr`.
2. **The argument is all digits.** It is a PR number, full stop — never a repo, never
   anything else. `target_repo` is the origin of the working directory's repo; `target_pr`
   is the argument.
3. **The argument contains a `/`.** It is a repo reference (bare `o/r`, a repo URL, an SSH
   remote, or a PR URL/`o/r#42` form that also carries a PR number). Extract `target_repo`
   from it with the recipes below, and `target_pr` too if the form carries one.
4. **Anything else — an argument that is neither all digits nor contains a `/`.** This is
   malformed input, not a fourth valid form: a bare word like `banana`, a typo like
   `owner-repo`, or any other string matching none of rules 2–3. Hard stop: report the
   literal argument received and the accepted forms (a PR number, `owner/repo`,
   `owner/repo#42`, a full repo or PR URL, or an SSH remote), and do nothing else. Never
   guess a target from a malformed argument.

There are two further hard stops, both orthogonal to the four rules above, and both about
the cwd's origin that rules 1 and 2 depend on:

- **No argument and no git repo in the working directory.** Report exactly what is missing
  (no target named, and the working directory is not a git repo) and do nothing else.
- **A git repo whose `origin` matched no recognised GitHub shape.** `origin_repo` below
  prints nothing when `git remote get-url origin` fails or returns a URL that is not a
  GitHub remote — a GitLab or Bitbucket remote, a non-standard SSH host alias
  (`git@work-github:o/r.git`), a URL with a host port and a path segment too many, or no
  `origin` remote at all. An empty result must **never** flow onward: an empty
  `target_repo` turns every later `gh --repo ""` into a failure with no named cause. Hard
  stop instead, and name both halves — the literal URL received and why it could not be
  resolved (it does not match `github.com[:/]<owner>/<repo>`), plus the accepted forms.

Both hard stops apply to rules 1 and 2 only; rules 3 and 4 never read the cwd's origin.

With the malformed-input case named as its own outcome, classification is total: every
possible argument — including no argument — resolves to a defined outcome, either a
`target_repo`/`target_pr` pair or one of the three named hard stops.

## Extraction recipes

```bash
# from a git remote URL → owner/repo, or nothing at all
# Two stages on purpose: BSD ERE has no non-greedy quantifier, so a
# `([^/]+/[^/]+?)(\.git)?$` form is a hard parse error on stock macOS.
# Normalise first (drop trailing slashes, then the optional .git), match second.
origin_repo() {
  git remote get-url origin 2>/dev/null \
    | sed -E 's#/+$##; s#\.git$##' \
    | sed -nE 's#^([a-z][a-z0-9+.-]*://)?(git@)?github\.com(:[0-9]+)?[:/]([^/]+/[^/]+)$#\4#p'
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

`origin_repo` is deliberately a local parse, not `gh repo view --json nameWithOwner`: it
must work before any network call, must not depend on the target being readable by the
current token, and must be able to *fail closed* rather than fail with an auth error. The
scheme, `git@`, port, `:` -vs- `/` separator and trailing-`/` forms above are all optional
because remotes legitimately arrive in every combination of them. Executed on stock
`/usr/bin/sed`, these resolve to `o/r`:
`https://github.com/o/r`, `https://github.com/o/r.git`, `https://github.com/o/r/`,
`https://github.com/o/r.git/`, `git@github.com:o/r`, `git@github.com:o/r.git`,
`git://github.com/o/r.git`, `ssh://git@github.com/o/r.git`,
`ssh://git@github.com:22/o/r.git`. These print nothing, and are therefore the second hard
stop above, not a silently-empty `target_repo`: `https://gitlab.com/o/r.git`,
`git@github.com:o/r/extra.git`, and an absent `origin`.

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

This verdict is binary and reached once, in preflight, before anything else touches disk —
it needs only `origin_repo` and `target_repo`, no config.

A remote target must never touch the working directory's repo: no fetch into it, no
worktree added to it, no ref written into it. Remote work happens entirely inside a
separate clone under `clone_cache_dir` or the session scratchpad; the user's checkout is
invisible to it.

### The bindings the decision makes

Bind these once per pass. Every recipe below, and every step of `SKILL.md` that runs `git`,
uses them; none of them is inferable later.

The verdict itself and the two name components need no config, so they land in preflight
alongside `target_repo`:

```bash
owner="${target_repo%%/*}"       # "o"  from "o/r"
repo_name="${target_repo#*/}"    # "r"  from "o/r"
```

`git_repo` — the one filesystem path every `git -C` below runs against — is bound as soon as
the config is in hand (`SKILL.md` step 2), because the remote branch needs
`clone_cache_dir`. That is still well before step 5, the first step that runs `git` at all:

```bash
if [ "$(origin_repo)" = "$target_repo" ]; then
  # local target — git runs against the user's own checkout, in place
  git_repo="$PWD"
else
  # remote target — git runs against a cache clone, never the user's checkout.
  # cache is clone_cache_dir when that config key is set, else the session
  # scratchpad directory given to you when the skill was invoked.
  cache="$clone_cache_dir"
  git_repo="$cache/$owner-$repo_name"
fi
```

`git_repo` is a **filesystem path**; `repo_name` is the **name component** of
`target_repo`. They are deliberately different names because they are different things —
never call either one `repo`. (`pr-merger.md` binds its own `owner`/`repo` pair from
`target_repo` for its GraphQL query; that is a separate agent with a separate context and
no filesystem work, and its bindings are correct as they stand.)

## Worktree recipe

The same two commands serve both localities — `git_repo` is what differs, and it is already
bound above (the user's checkout for a local target, the cache clone for a remote one). The
worktree always lands at `$workdir/tree`, never inside `git_repo`.

```bash
git -C "$git_repo" fetch origin "pull/$n/head:refs/pr-reviewer/$n" --force
git -C "$git_repo" worktree add --detach "$workdir/tree" "refs/pr-reviewer/$n"
```

This touches no branch, no index, and no checked-out file in the user's working tree. The
fetch writes a new ref under `refs/pr-reviewer/`, a namespace reserved for this skill so it
can never collide with a branch or tag the user already has; the worktree is added detached,
so nothing in the user's own checkout moves.

## Remote clone recipe

```bash
git clone --filter=blob:none --no-checkout \
  "https://github.com/$target_repo.git" "$git_repo"
```

`git_repo` is already `$cache/$owner-$repo_name` for a remote target, bound at the locality
decision above — that is the clone's one and only path, and the same value every later
`git -C` uses. `cache` is `clone_cache_dir` when that config key is set, otherwise the
session scratchpad.

The clone is **blobless** — `--filter=blob:none` fetches every commit and tree but no file
contents up front, so blobs arrive on demand as the worktree is populated. This keeps a
first touch of a large repository fast. The clone is reused across every PR processed in
the pass, and across passes when run under `/loop`: check whether `$git_repo` already exists
and is a git repository before cloning, and if so, reuse is a `git fetch`, never a re-clone.

## Cleanup, mandatory after each PR

```bash
git -C "$git_repo" worktree remove --force "$workdir/tree"
git -C "$git_repo" update-ref -d "refs/pr-reviewer/$n"
rm -rf "$workdir"
```

**Run these three in exactly this order.** `git worktree remove --force` must deregister
`$workdir/tree` from `$git_repo` *before* the directory disappears: delete `$workdir` first
and the remove fails (`fatal: '…/tree' is not a working tree`, exit 128), leaving a stale
`prunable` worktree registration in the user's own repository. The `rm -rf "$workdir"` is
what actually reclaims the `mktemp -d` scratch directory holding the diff — without it a
`/loop` run leaks one temp directory per PR, forever.

Run all three after every PR is processed, unconditionally — on success, on a skipped or
parked outcome, and on failure. A local target must be left exactly as found: no stray
worktree directory, no leftover `refs/pr-reviewer/*` ref, no temp directory, no change to
the branch the user had checked out before this pass began. `worktree remove --force` clears
the worktree even if something inside it was modified; `update-ref -d` removes the ref itself
rather than merely letting it go stale.

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
