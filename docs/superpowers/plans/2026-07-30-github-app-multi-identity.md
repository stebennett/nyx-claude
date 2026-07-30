# github-app-identity Multi-Profile Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let one machine drive several GitHub App bot identities — a build clone and a review clone of the same repository — selected by per-clone git config, with no path back to personal credentials.

**Architecture:** A new shared bash library holds profile validation, profile loading, and the working-directory→profile resolution rule. The `gh` shim, token minter, credential helper, setup script, and a new status script all source it and take an explicit `--profile <name>`. Each profile gets its own env file and its own token cache. Repo setup additionally resets git's credential-helper list so inherited helpers (osxkeychain, `gh auth git-credential`) cannot answer first.

**Tech Stack:** bash 3.2, git, curl, openssl, python3 (JSON parsing in the token minter), GitHub Apps API, GitHub Actions.

## Source Spec

`docs/superpowers/specs/2026-07-30-github-app-multi-identity-design.md`

## Deviation From The Spec — Read First

The spec lists five scripts and does not mention a shared library. Implementation adds a sixth
file, `scripts/gh-app-common.sh`, because profile validation and loading are needed by three
scripts and the cwd→profile resolution rule by two. Duplicating ~50 lines of security-relevant
bash across four files is how the two copies drift. Everything else follows the spec as
written. **If you would rather keep the flat five-script layout, say so before Task 1** — every
later task depends on this choice.

## Global Constraints

Copied verbatim from `CLAUDE.md` and the spec. Every task's requirements implicitly include
this section.

- **bash 3.2 compatible** (macOS default). No `mapfile`, no `readarray`, no `declare -A`, no
  `${var,,}`/`${var^^}`.
- **No GNU-only constructs.** No `grep -oP`, no `\K`, no `find -printf`, no `date -Iseconds`,
  no `sed -i` without an argument. Use `sed -nE`, `ls -t`, `date +%Y-%m-%dT%H:%M:%S%z`.
- **`python3` is a hard dependency** of `github-app-token.sh` (already the case on `main`).
  `openssl` and `curl` are required for minting. `jq` is not used by this plugin.
- **Profile name pattern is exactly `^[A-Za-z0-9][A-Za-z0-9._-]*$`** — no underscore. Use
  `pr-reviewer`, not `pr_reviewer`.
- **No production-reachable environment variable may select the identity.** `GH_APP_PROFILE_DIR`
  and `GH_APP_CACHE_DIR` relocate storage; neither names a profile. `GH_APP_ENABLED_OVERRIDE`
  is deleted, not renamed.
- **Fail closed.** Every error path aborts. No condition may result in personal credentials
  being used.
- **Every test is offline.** No network, no real `gh`, no real GitHub App. Stub the token
  command.
- Test scripts are standalone: `set -euo pipefail`, `mktemp -d` with an `EXIT` trap, `FAIL: …`
  to stderr + `exit 1` on failure, one `PASS: …` line at the end.

---

### Task 1: Shared library — validation, profile loading, resolution

**Files:**
- Create: `plugins/github-app-identity/scripts/gh-app-common.sh`
- Test: `plugins/github-app-identity/scripts/tests/test_gh_app_common.sh`

**Interfaces:**
- Consumes: nothing.
- Produces, for every later task:
  - `GH_APP_DOCTRINE` — string constant appended to auth-failure messages.
  - `gh_app_die <msg…>` — prints `gh-app: <msg>` to stderr, exits 1.
  - `gh_app_validate_profile <name>` — returns 0, or dies. Must be called from the current
    shell, never inside `$( )`.
  - `gh_app_profile_dir` / `gh_app_cache_dir` — print the directory. Safe in `$( )`.
  - `gh_app_list_profiles` — prints available profile names, two-space indented.
  - `gh_app_load_profile <name>` — validates, requires the file, sources it with `set -a`, and
    sets `GH_APP_PROFILE_FILE`. Dies on a missing profile.
  - `gh_app_resolve_profile` — prints the profile for the cwd, or nothing for pass-through.
    Exits 1 on legacy config. Callers **must** use `p="$(gh_app_resolve_profile)" || exit 1`.

- [ ] **Step 1: Write the failing test**

Create `plugins/github-app-identity/scripts/tests/test_gh_app_common.sh`:

```bash
#!/usr/bin/env bash
# Offline tests for the shared helper library: name validation, profile
# loading, and working-directory -> profile resolution.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lib="$here/../gh-app-common.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

profiles="$work/profiles"; mkdir -p "$profiles"
cat > "$profiles/builder.env" <<'EOF'
GITHUB_APP_ID=111
GITHUB_APP_INSTALLATION_ID=222
GITHUB_APP_PRIVATE_KEY_PATH=/dev/null
GITHUB_APP_SLUG=my-builder
GITHUB_APP_BOT_USER_ID=333
EOF
touch "$profiles/pr-reviewer.env"

# Run a snippet against the library in a clean subshell. Prints its stdout;
# returns its exit status.
run() { ( set +e; cd "${2:-$work}"; GH_APP_PROFILE_DIR="$profiles" bash -c "
  set -euo pipefail
  . '$lib'
  $1" ) ; }

# --- name validation: accepts sane names ---
for name in builder pr-reviewer a A0 x.y z-1.2; do
  run "gh_app_validate_profile '$name'" >/dev/null 2>&1 \
    || { echo "FAIL: rejected valid name '$name'" >&2; exit 1; }
done

# --- name validation: rejects anything that must not become a path ---
for bad in "" "../evil" ".hidden" "a b" "a/b" "-lead" "a\$b"; do
  if run "gh_app_validate_profile '$bad'" >/dev/null 2>&1; then
    echo "FAIL: accepted invalid name '$bad'" >&2; exit 1
  fi
done

# --- load_profile: sources the file and exports its values ---
out="$(run 'gh_app_load_profile builder; echo "$GITHUB_APP_SLUG/$GITHUB_APP_ID"')"
[[ "$out" == "my-builder/111" ]] \
  || { echo "FAIL: load_profile did not export values, got '$out'" >&2; exit 1; }

# --- load_profile: a missing profile dies and names the ones that exist ---
if err="$(run 'gh_app_load_profile nope' 2>&1)"; then
  echo "FAIL: load_profile accepted a missing profile" >&2; exit 1
fi
echo "$err" | grep -q 'nope' || { echo "FAIL: error omits the bad name: $err" >&2; exit 1; }
echo "$err" | grep -q 'builder' \
  || { echo "FAIL: error does not list available profiles: $err" >&2; exit 1; }

# --- resolve: outside a git repo -> empty, exit 0 (pass-through) ---
outside="$work/outside"; mkdir -p "$outside"
out="$(run 'gh_app_resolve_profile' "$outside")" \
  || { echo "FAIL: resolve errored outside a repo" >&2; exit 1; }
[[ -z "$out" ]] || { echo "FAIL: resolve returned '$out' outside a repo" >&2; exit 1; }

# --- resolve: repo with no markers -> empty, exit 0 (pass-through) ---
plain="$work/plain"; mkdir -p "$plain"; ( cd "$plain" && git init -q . )
out="$(run 'gh_app_resolve_profile' "$plain")" \
  || { echo "FAIL: resolve errored in an unconfigured repo" >&2; exit 1; }
[[ -z "$out" ]] || { echo "FAIL: resolve returned '$out' in an unconfigured repo" >&2; exit 1; }

# --- resolve: repo with gh-app.profile -> that name ---
conf="$work/conf"; mkdir -p "$conf"
( cd "$conf" && git init -q . && git config --local gh-app.profile pr-reviewer )
out="$(run 'gh_app_resolve_profile' "$conf")"
[[ "$out" == "pr-reviewer" ]] \
  || { echo "FAIL: resolve gave '$out', expected 'pr-reviewer'" >&2; exit 1; }

# --- resolve: legacy gh-app.enabled with no profile -> abort, not pass-through ---
legacy="$work/legacy"; mkdir -p "$legacy"
( cd "$legacy" && git init -q . && git config --local gh-app.enabled true )
if err="$(run 'gh_app_resolve_profile' "$legacy" 2>&1)"; then
  echo "FAIL: legacy repo passed through instead of aborting" >&2; exit 1
fi
echo "$err" | grep -q 'setup-github-app-git.sh' \
  || { echo "FAIL: legacy abort does not say how to fix it: $err" >&2; exit 1; }

# --- resolve: a --global profile must NOT enable an unconfigured repo ---
globalcfg="$work/global.gitconfig"
printf '[gh-app]\n\tprofile = builder\n' > "$globalcfg"
out="$( GIT_CONFIG_GLOBAL="$globalcfg" run 'gh_app_resolve_profile' "$plain" )"
[[ -z "$out" ]] \
  || { echo "FAIL: a global gh-app.profile leaked into an unconfigured repo" >&2; exit 1; }

echo "PASS: gh-app-common validation, profile loading, and cwd resolution"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash plugins/github-app-identity/scripts/tests/test_gh_app_common.sh`
Expected: FAIL — the library does not exist, so every `run` errors on the missing source file.

- [ ] **Step 3: Write the library**

Create `plugins/github-app-identity/scripts/gh-app-common.sh`:

```bash
#!/usr/bin/env bash
# Shared helpers for the github-app-identity scripts. Sourced, never executed.
# bash 3.2 compatible; no GNU-only constructs.

# Appended to every auth-failure message. This is the plugin's standing rule,
# placed where an agent actually reads it: in the abort it just hit.
GH_APP_DOCTRINE="Do NOT retry with personal credentials or 'gh auth login' — this means setup is incomplete. Run gh-app-status.sh."

gh_app_die() { echo "gh-app: $*" >&2; exit 1; }

gh_app_profile_dir() { printf '%s\n' "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}"; }
gh_app_cache_dir()   { printf '%s\n' "${GH_APP_CACHE_DIR:-$HOME/.cache/gh-app}"; }

# A profile name becomes a path component twice (profile file, cache file), so
# it is validated before it is ever concatenated into a path.
# Must be called from the current shell — it exits, which a $( ) subshell eats.
gh_app_validate_profile() {
  local name="${1:-}"
  local rule="must match ^[A-Za-z0-9][A-Za-z0-9._-]*\$ (letters, digits, dot, dash)"
  [ -n "$name" ] || gh_app_die "empty profile name — $rule"
  case "$name" in
    [A-Za-z0-9]*) : ;;
    *) gh_app_die "invalid profile name '$name' — $rule" ;;
  esac
  case "$name" in
    *[!A-Za-z0-9._-]*) gh_app_die "invalid profile name '$name' — $rule" ;;
  esac
  return 0
}

gh_app_list_profiles() {
  local d f n found=0
  d="$(gh_app_profile_dir)"
  for f in "$d"/*.env; do
    [ -f "$f" ] || continue
    n="${f##*/}"; n="${n%.env}"
    printf '  %s\n' "$n"
    found=1
  done
  [ "$found" -eq 1 ] || printf '  (none found in %s)\n' "$d"
}

# Validate, require, and source a profile. Exports its values and sets
# GH_APP_PROFILE_FILE. Dies if the profile does not exist.
gh_app_load_profile() {
  local name="${1:-}" f
  gh_app_validate_profile "$name"
  f="$(gh_app_profile_dir)/$name.env"
  if [ ! -f "$f" ]; then
    echo "gh-app: no such profile '$name' (expected $f)" >&2
    echo "gh-app: available profiles:" >&2
    gh_app_list_profiles >&2
    exit 1
  fi
  set -a
  # shellcheck disable=SC1090
  . "$f"
  set +a
  GH_APP_PROFILE_FILE="$f"
  return 0
}

# Print the profile governing the current directory, or nothing when gh should
# pass through unchanged. Exits 1 on legacy config.
# Callers MUST write: profile="$(gh_app_resolve_profile)" || exit 1
gh_app_resolve_profile() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0

  local p
  p="$(git config --local --get gh-app.profile 2>/dev/null || true)"
  if [ -n "$p" ]; then
    printf '%s\n' "$p"
    return 0
  fi

  # --local, never a plain --get: a stray --global setting must not enable every
  # repo on the machine. In a linked worktree --local resolves to the clone's
  # shared config, which is what makes worktrees inherit the clone's identity.
  if git config --local --get gh-app.enabled >/dev/null 2>&1; then
    echo "gh-app: legacy config — this repo sets gh-app.enabled but no gh-app.profile." >&2
    echo "gh-app: re-run: setup-github-app-git.sh <profile>" >&2
    exit 1
  fi
  return 0
}
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash plugins/github-app-identity/scripts/tests/test_gh_app_common.sh`
Expected: `PASS: gh-app-common validation, profile loading, and cwd resolution`

- [ ] **Step 5: Commit**

```bash
git add plugins/github-app-identity/scripts/gh-app-common.sh \
        plugins/github-app-identity/scripts/tests/test_gh_app_common.sh
git commit -m "feat(github-app-identity): add shared profile resolution library"
```

---

### Task 2: Token minter takes `--profile`, caches per profile

**Files:**
- Modify: `plugins/github-app-identity/scripts/github-app-token.sh`
- Modify: `plugins/github-app-identity/scripts/tests/test_github_app_token.sh`

**Interfaces:**
- Consumes: `gh_app_die`, `gh_app_load_profile`, `gh_app_cache_dir` from Task 1.
- Produces: CLI `github-app-token.sh --profile <name>` printing one token to stdout. Cache path
  `$(gh_app_cache_dir)/token-<name>.json`. Non-zero exit and empty stdout on any failure. This
  exact CLI is called by Tasks 3, 4, and 6.

- [ ] **Step 1: Rewrite the test**

Replace `plugins/github-app-identity/scripts/tests/test_github_app_token.sh` entirely:

```bash
#!/usr/bin/env bash
# Offline tests: --profile is required, caches are keyed per profile, and a
# missing profile errors rather than serving another profile's cached token.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../github-app-token.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

profiles="$work/profiles"; cache="$work/cache"; mkdir -p "$profiles" "$cache"
for p in builder pr-reviewer; do
  cat > "$profiles/$p.env" <<EOF
GITHUB_APP_ID=1
GITHUB_APP_INSTALLATION_ID=2
GITHUB_APP_PRIVATE_KEY_PATH=/dev/null
GITHUB_APP_SLUG=$p
GITHUB_APP_BOT_USER_ID=3
EOF
done

future=$(( $(date +%s) + 3600 ))
printf '{"token":"ghs_BUILDER","expires_at_epoch":%s}\n'  "$future" > "$cache/token-builder.json"
printf '{"token":"ghs_REVIEWER","expires_at_epoch":%s}\n' "$future" > "$cache/token-pr-reviewer.json"

run() { GH_APP_PROFILE_DIR="$profiles" GH_APP_CACHE_DIR="$cache" bash "$script" "$@"; }

# --- each profile gets its own cached token: no bleed between identities ---
out="$(run --profile builder)"
[[ "$out" == "ghs_BUILDER" ]] || { echo "FAIL: builder got '$out'" >&2; exit 1; }
out="$(run --profile pr-reviewer)"
[[ "$out" == "ghs_REVIEWER" ]] || { echo "FAIL: pr-reviewer got '$out'" >&2; exit 1; }

# --- --profile=<name> form works too ---
out="$(run --profile=builder)"
[[ "$out" == "ghs_BUILDER" ]] || { echo "FAIL: --profile= form got '$out'" >&2; exit 1; }

# --- no --profile: refuse (an implicit default is how the wrong token gets minted) ---
if run >/dev/null 2>&1; then echo "FAIL: ran without --profile" >&2; exit 1; fi

# --- unknown profile: error, and do NOT fall back to any cached token ---
if out="$(run --profile ghost 2>/dev/null)"; then
  echo "FAIL: unknown profile succeeded with '$out'" >&2; exit 1
fi

# --- a profile whose env file was deleted must error, not serve a stale cache ---
rm -f "$profiles/builder.env"
if out="$(run --profile builder 2>/dev/null)"; then
  echo "FAIL: deleted profile served a stale cached token '$out'" >&2; exit 1
fi

# --- an expired cache entry is not reused (no network here, so it must fail loudly) ---
past=$(( $(date +%s) - 60 ))
printf '{"token":"ghs_STALE","expires_at_epoch":%s}\n' "$past" > "$cache/token-pr-reviewer.json"
out="$(run --profile pr-reviewer 2>/dev/null || true)"
[[ "$out" != "ghs_STALE" ]] || { echo "FAIL: reused an expired token" >&2; exit 1; }

echo "PASS: token minter requires --profile and isolates caches per profile"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash plugins/github-app-identity/scripts/tests/test_github_app_token.sh`
Expected: FAIL — the script does not accept `--profile` and reads a single cache file.

- [ ] **Step 3: Rewrite the head of the script**

In `plugins/github-app-identity/scripts/github-app-token.sh`, replace everything from the
shebang down to and including the `cache_file=` line with:

```bash
#!/usr/bin/env bash
# Mint (and cache) a GitHub App installation access token, printed to stdout.
#   github-app-token.sh --profile <name>
# Profile config comes from $GH_APP_PROFILE_DIR/<name>.env; tokens are cached
# per profile so two identities can never reuse each other's token.
set -euo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

profile=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   profile="${2:-}"; shift 2 ;;
    --profile=*) profile="${1#--profile=}"; shift ;;
    *) gh_app_die "unknown argument '$1' (usage: github-app-token.sh --profile <name>)" ;;
  esac
done
[ -n "$profile" ] || gh_app_die "--profile <name> is required (usage: github-app-token.sh --profile <name>)"

# Load before touching the cache: a deleted or mistyped profile must error
# rather than quietly serve a token minted under some other identity.
gh_app_load_profile "$profile"

cache_file="$(gh_app_cache_dir)/token-$profile.json"
```

Leave the rest of the file — the cached-token reuse block, the JWT construction, the curl call,
and the atomic 0600 cache write — exactly as it is. Then update the two error messages further
down to name the profile and carry the doctrine:

Replace `: "${GITHUB_APP_ID:?GITHUB_APP_ID not set (see the github-app-identity setup runbook)}"`
and the two lines after it with:

```bash
: "${GITHUB_APP_ID:?GITHUB_APP_ID not set in $GH_APP_PROFILE_FILE}"
: "${GITHUB_APP_INSTALLATION_ID:?GITHUB_APP_INSTALLATION_ID not set in $GH_APP_PROFILE_FILE}"
: "${GITHUB_APP_PRIVATE_KEY_PATH:?GITHUB_APP_PRIVATE_KEY_PATH not set in $GH_APP_PROFILE_FILE}"
```

Replace the final failure line:

```bash
) || { echo "gh-app: failed to mint an installation token for profile '$profile'. Response: $response" >&2
       echo "gh-app: $GH_APP_DOCTRINE" >&2
       exit 1; }
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash plugins/github-app-identity/scripts/tests/test_github_app_token.sh`
Expected: `PASS: token minter requires --profile and isolates caches per profile`

- [ ] **Step 5: Commit**

```bash
git add plugins/github-app-identity/scripts/github-app-token.sh \
        plugins/github-app-identity/scripts/tests/test_github_app_token.sh
git commit -m "feat(github-app-identity)!: mint tokens per named profile"
```

---

### Task 3: `gh` shim resolves the profile from the clone

**Files:**
- Modify: `plugins/github-app-identity/scripts/gh`
- Modify: `plugins/github-app-identity/scripts/tests/test_gh_shim.sh`

**Interfaces:**
- Consumes: `gh_app_resolve_profile`, `gh_app_die`, `GH_APP_DOCTRINE` (Task 1); the
  `--profile <name>` CLI (Task 2).
- Produces: nothing later tasks call. `GH_APP_REAL_GH` and `GITHUB_APP_TOKEN_CMD` remain as
  test seams; `GH_APP_ENABLED_OVERRIDE` is gone.

- [ ] **Step 1: Rewrite the test**

Replace `plugins/github-app-identity/scripts/tests/test_gh_shim.sh` entirely. Note it now uses
real `git init` repos rather than an override variable — that is the point: the escape hatch
is deleted, so the real resolution path is what gets tested.

```bash
#!/usr/bin/env bash
# Offline tests for the directory-aware gh shim. Real git repos, stub gh,
# stub token command. No network.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
shim="$here/../gh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Stub "real gh": records GH_TOKEN and argv.
stub="$work/realgh"
cat > "$stub" <<EOF
#!/usr/bin/env bash
echo "GH_TOKEN=\${GH_TOKEN:-<unset>}" > "$work/ran"
printf '%s\n' "\$@" >> "$work/ran"
EOF
chmod +x "$stub"

# Stub token command: echoes a token derived from the --profile it was given,
# so the test can prove the right profile reached it.
tok="$work/tok"
cat > "$tok" <<'EOF'
#!/usr/bin/env bash
p=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   p="${2:-}"; shift 2 ;;
    --profile=*) p="${1#--profile=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$p" ] || { echo "token stub: no --profile" >&2; exit 1; }
echo "ghs_TOKEN_FOR_$p"
EOF
chmod +x "$tok"

# Case a: not a repo -> pass-through, no token.
rm -f "$work/ran"; outside="$work/outside"; mkdir -p "$outside"
( cd "$outside" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" api /rate_limit )
grep -q 'GH_TOKEN=<unset>' "$work/ran" || { echo "FAIL(a): token set on pass-through" >&2; exit 1; }
grep -q 'api' "$work/ran" || { echo "FAIL(a): args not forwarded" >&2; exit 1; }

# Case b: repo with no marker -> pass-through.
rm -f "$work/ran"; plain="$work/plain"; mkdir -p "$plain"; ( cd "$plain" && git init -q . )
( cd "$plain" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" pr list )
grep -q 'GH_TOKEN=<unset>' "$work/ran" || { echo "FAIL(b): token set in unconfigured repo" >&2; exit 1; }

# Case c/d: two clones, two identities -> each gets its own profile's token.
for pair in "build:builder" "review:pr-reviewer"; do
  d="$work/${pair%%:*}"; p="${pair##*:}"
  mkdir -p "$d"; ( cd "$d" && git init -q . && git config --local gh-app.profile "$p" )
  rm -f "$work/ran"
  ( cd "$d" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" pr view 1 )
  grep -q "GH_TOKEN=ghs_TOKEN_FOR_$p" "$work/ran" \
    || { echo "FAIL(c/d): clone $d did not authenticate as '$p': $(cat "$work/ran")" >&2; exit 1; }
done

# Case e: enabled repo + empty token -> abort, real gh NOT run.
rm -f "$work/ran"
empty="$work/empty"; printf '#!/usr/bin/env bash\nexit 0\n' > "$empty"; chmod +x "$empty"
if ( cd "$work/build" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$empty" bash "$shim" api /x ) >/dev/null 2>&1; then
  echo "FAIL(e): shim ran with an empty token" >&2; exit 1
fi
if [[ -f "$work/ran" ]]; then echo "FAIL(e): real gh was invoked despite empty token" >&2; exit 1; fi

# Case f: enabled repo + failing token command -> abort, real gh NOT run.
rm -f "$work/ran"
boom="$work/boom"; printf '#!/usr/bin/env bash\nexit 3\n' > "$boom"; chmod +x "$boom"
if ( cd "$work/build" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$boom" bash "$shim" api /x ) >/dev/null 2>&1; then
  echo "FAIL(f): shim ran despite a failing token command" >&2; exit 1
fi
if [[ -f "$work/ran" ]]; then echo "FAIL(f): real gh was invoked despite token failure" >&2; exit 1; fi

# Case g: legacy marker with no profile -> abort, never pass-through to personal auth.
rm -f "$work/ran"; legacy="$work/legacy"; mkdir -p "$legacy"
( cd "$legacy" && git init -q . && git config --local gh-app.enabled true )
if ( cd "$legacy" && GH_APP_REAL_GH="$stub" GITHUB_APP_TOKEN_CMD="$tok" bash "$shim" api /x ) >/dev/null 2>&1; then
  echo "FAIL(g): legacy repo passed through to personal auth" >&2; exit 1
fi
if [[ -f "$work/ran" ]]; then echo "FAIL(g): real gh ran in a legacy repo" >&2; exit 1; fi

# Case h: no recursion — the shim resolves a real gh that is not itself, via PATH.
rm -f "$work/ran"
bindir="$work/bin"; realdir="$work/real"; mkdir -p "$bindir" "$realdir"
cp "$shim" "$bindir/gh"; cp "$here/../gh-app-common.sh" "$bindir/"; chmod +x "$bindir/gh"
cp "$stub" "$realdir/gh"; chmod +x "$realdir/gh"
( cd "$work/build" && GITHUB_APP_TOKEN_CMD="$tok" PATH="$bindir:$realdir:$PATH" "$bindir/gh" issue list )
grep -q 'GH_TOKEN=ghs_TOKEN_FOR_builder' "$work/ran" \
  || { echo "FAIL(h): shim did not resolve/exec the real gh" >&2; exit 1; }

echo "PASS: gh shim pass-through / per-clone identity / abort / legacy trap / no-recursion"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash plugins/github-app-identity/scripts/tests/test_gh_shim.sh`
Expected: FAIL at case c/d — the shim keys on `gh-app.enabled` and passes no `--profile`.

- [ ] **Step 3: Rewrite the shim body**

In `plugins/github-app-identity/scripts/gh`, keep the shebang, the comment block, `set -euo
pipefail`, the `dir=` line, and the whole `resolve_real_gh` function unchanged. Add the source
line directly after `dir=`:

```bash
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"
```

Then replace everything from `# Opted in?` to the end of the file with:

```bash
real_gh="$(resolve_real_gh)"

# Which identity governs this directory? Empty means pass through untouched.
profile="$(gh_app_resolve_profile)" || exit 1
if [ -z "$profile" ]; then
  exec "$real_gh" "$@"
fi

token="$("${GITHUB_APP_TOKEN_CMD:-$dir/github-app-token.sh}" --profile "$profile")" \
  || gh_app_die "could not mint a token for profile '$profile'. $GH_APP_DOCTRINE"
[ -n "$token" ] \
  || gh_app_die "empty token for profile '$profile' — refusing to run, because gh would fall back to personal auth. $GH_APP_DOCTRINE"

[ -n "${GH_APP_DEBUG:-}" ] && echo "gh-app shim: running gh as profile '$profile'" >&2
GH_TOKEN="$token" exec "$real_gh" "$@"
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash plugins/github-app-identity/scripts/tests/test_gh_shim.sh`
Expected: `PASS: gh shim pass-through / per-clone identity / abort / legacy trap / no-recursion`

- [ ] **Step 5: Commit**

```bash
git add plugins/github-app-identity/scripts/gh \
        plugins/github-app-identity/scripts/tests/test_gh_shim.sh
git commit -m "feat(github-app-identity)!: resolve the gh identity per clone"
```

---

### Task 4: Credential helper takes `--profile`

**Files:**
- Modify: `plugins/github-app-identity/scripts/git-credential-github-app.sh`
- Modify: `plugins/github-app-identity/scripts/tests/test_git_credential_github_app.sh`

**Interfaces:**
- Consumes: the `--profile <name>` CLI (Task 2).
- Produces: helper CLI `git-credential-github-app.sh --profile <name> <get|store|erase>`. Task 5
  writes exactly this string into git config.

Git appends the operation as the **final** argument, so the helper must scan its arguments
rather than read `$1`.

- [ ] **Step 1: Rewrite the test**

Replace `plugins/github-app-identity/scripts/tests/test_git_credential_github_app.sh`:

```bash
#!/usr/bin/env bash
# Offline tests: the helper scans for --profile (git appends the operation
# last), emits x-access-token, and refuses to answer without a profile.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
helper="$here/../git-credential-github-app.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

# Token stub echoing a token derived from --profile.
stub="$work/tok"
cat > "$stub" <<'EOF'
#!/usr/bin/env bash
p=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   p="${2:-}"; shift 2 ;;
    --profile=*) p="${1#--profile=}"; shift ;;
    *) shift ;;
  esac
done
[ -n "$p" ] || exit 1
echo "tok_$p"
EOF
chmod +x "$stub"

req() { printf 'protocol=https\nhost=github.com\n\n'; }

# --- get, with the operation appended last as git does it ---
out="$(req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile pr-reviewer get)"
echo "$out" | grep -qx 'username=x-access-token' \
  || { echo "FAIL: missing username line: $out" >&2; exit 1; }
echo "$out" | grep -qx 'password=tok_pr-reviewer' \
  || { echo "FAIL: wrong/missing password line: $out" >&2; exit 1; }

# --- the profile actually selects the identity ---
out="$(req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile builder get)"
echo "$out" | grep -qx 'password=tok_builder' \
  || { echo "FAIL: helper ignored the profile: $out" >&2; exit 1; }

# --- get with no --profile: no credentials, non-zero exit ---
if out="$(req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" get 2>/dev/null)"; then
  echo "FAIL: answered without a profile" >&2; exit 1
fi
if echo "${out:-}" | grep -q 'password='; then
  echo "FAIL: leaked a password line without a profile" >&2; exit 1
fi

# --- get when the token command fails: no credentials, non-zero exit ---
boom="$work/boom"; printf '#!/usr/bin/env bash\nexit 3\n' > "$boom"; chmod +x "$boom"
if out="$(req | GITHUB_APP_TOKEN_CMD="$boom" bash "$helper" --profile builder get 2>/dev/null)"; then
  echo "FAIL: answered despite a failing token command" >&2; exit 1
fi

# --- store/erase are no-ops that succeed (tokens are minted fresh each time) ---
req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile builder store >/dev/null
req | GITHUB_APP_TOKEN_CMD="$stub" bash "$helper" --profile builder erase >/dev/null

echo "PASS: credential helper honours --profile and fails closed"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash plugins/github-app-identity/scripts/tests/test_git_credential_github_app.sh`
Expected: FAIL — the helper reads `$1`, so `--profile` is treated as the operation and nothing
is emitted.

- [ ] **Step 3: Rewrite the helper**

Replace `plugins/github-app-identity/scripts/git-credential-github-app.sh` entirely:

```bash
#!/usr/bin/env bash
# git credential helper: supplies a GitHub App installation token for HTTPS git ops.
# Configured by setup-github-app-git.sh as:
#   credential.https://github.com.helper = <abs path> --profile <name>
# git appends the operation (get/store/erase) as the LAST argument, so the
# profile has to be scanned for rather than read from $1.
set -euo pipefail
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

profile=""
op=""
while [ $# -gt 0 ]; do
  case "$1" in
    --profile)   profile="${2:-}"; shift 2 ;;
    --profile=*) profile="${1#--profile=}"; shift ;;
    *) op="$1"; shift ;;
  esac
done

case "$op" in
  get)
    if [ -z "$profile" ]; then
      echo "gh-app credential helper: no --profile in the git config helper line." >&2
      echo "gh-app: re-run: setup-github-app-git.sh <profile>" >&2
      exit 1
    fi
    token="$("${GITHUB_APP_TOKEN_CMD:-$dir/github-app-token.sh}" --profile "$profile")" \
      || gh_app_die "credential helper could not mint a token for profile '$profile'. $GH_APP_DOCTRINE"
    [ -n "$token" ] \
      || gh_app_die "credential helper got an empty token for profile '$profile'. $GH_APP_DOCTRINE"
    echo "username=x-access-token"
    echo "password=$token"
    ;;
  *)
    # store/erase: nothing to persist — tokens are minted fresh each time.
    : ;;
esac
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash plugins/github-app-identity/scripts/tests/test_git_credential_github_app.sh`
Expected: `PASS: credential helper honours --profile and fails closed`

- [ ] **Step 5: Commit**

```bash
git add plugins/github-app-identity/scripts/git-credential-github-app.sh \
        plugins/github-app-identity/scripts/tests/test_git_credential_github_app.sh
git commit -m "feat(github-app-identity)!: pass the profile to the credential helper"
```

---

### Task 5: Repo setup takes a profile and wins the credential race

This is the task that fixes the live defect: git consults credential helpers system → global →
local and uses the **first** that answers, so today's appended helper never runs and pushes
authenticate as the personal account.

**Files:**
- Modify: `plugins/github-app-identity/scripts/setup-github-app-git.sh`
- Create: `plugins/github-app-identity/scripts/tests/test_setup_github_app_git.sh`
- Unchanged: `plugins/github-app-identity/scripts/tests/test_owner_repo_parse.sh` (the
  `--parse` contract is preserved, so this file must keep passing untouched)

**Interfaces:**
- Consumes: `gh_app_load_profile`, `gh_app_die` (Task 1); the helper CLI (Task 4).
- Produces: the local git config Task 3 and Task 6 read — `gh-app.profile`, the two-value
  `credential.https://github.com.helper` list, `user.name`, `user.email`, HTTPS `origin`.

- [ ] **Step 1: Write the failing test**

Create `plugins/github-app-identity/scripts/tests/test_setup_github_app_git.sh`:

```bash
#!/usr/bin/env bash
# Offline tests for per-repo setup, including the regression that matters:
# an inherited global credential helper must not beat ours. Requires git >= 2.32
# for GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
setup="$here/../setup-github-app-git.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

profiles="$work/profiles"; mkdir -p "$profiles"
cat > "$profiles/pr-reviewer.env" <<'EOF'
GITHUB_APP_ID=1
GITHUB_APP_INSTALLATION_ID=2
GITHUB_APP_PRIVATE_KEY_PATH=/dev/null
GITHUB_APP_SLUG=my-reviewer
GITHUB_APP_BOT_USER_ID=4242
EOF

repo="$work/repo"; mkdir -p "$repo"
( cd "$repo" && git init -q . && git remote add origin git@github.com:acme/widget.git )

run_setup() { ( cd "$repo" && GH_APP_PROFILE_DIR="$profiles" bash "$setup" "$@" ); }

# --- a profile argument is required ---
if run_setup >/dev/null 2>&1; then echo "FAIL: ran with no profile" >&2; exit 1; fi
if run_setup ghost >/dev/null 2>&1; then echo "FAIL: accepted an unknown profile" >&2; exit 1; fi

run_setup pr-reviewer >/dev/null

cfg() { git -C "$repo" config --local --get "$1"; }

# --- identity, marker, and remote ---
[[ "$(cfg user.name)"  == "my-reviewer[bot]" ]] || { echo "FAIL: user.name = $(cfg user.name)" >&2; exit 1; }
[[ "$(cfg user.email)" == "4242+my-reviewer[bot]@users.noreply.github.com" ]] \
  || { echo "FAIL: user.email = $(cfg user.email)" >&2; exit 1; }
[[ "$(cfg gh-app.profile)" == "pr-reviewer" ]] || { echo "FAIL: gh-app.profile not set" >&2; exit 1; }
[[ "$(git -C "$repo" remote get-url origin)" == "https://github.com/acme/widget.git" ]] \
  || { echo "FAIL: origin not switched to HTTPS" >&2; exit 1; }

# --- helper list: exactly one empty reset then one helper carrying the profile ---
helpers="$(git -C "$repo" config --local --get-all credential.https://github.com.helper)"
[[ "$(printf '%s\n' "$helpers" | wc -l | tr -d ' ')" == "2" ]] \
  || { echo "FAIL: expected 2 helper values, got: $helpers" >&2; exit 1; }
[[ -z "$(printf '%s\n' "$helpers" | sed -n '1p')" ]] \
  || { echo "FAIL: first helper value is not the empty reset: $helpers" >&2; exit 1; }
printf '%s\n' "$helpers" | sed -n '2p' | grep -q -- '--profile pr-reviewer' \
  || { echo "FAIL: helper line lacks --profile pr-reviewer: $helpers" >&2; exit 1; }

# --- idempotence: running twice must not duplicate the helper values ---
run_setup pr-reviewer >/dev/null
helpers="$(git -C "$repo" config --local --get-all credential.https://github.com.helper)"
[[ "$(printf '%s\n' "$helpers" | wc -l | tr -d ' ')" == "2" ]] \
  || { echo "FAIL: helper values duplicated on re-run: $helpers" >&2; exit 1; }

# --- a legacy gh-app.enabled marker is cleared ---
git -C "$repo" config --local gh-app.enabled true
run_setup pr-reviewer >/dev/null
if git -C "$repo" config --local --get gh-app.enabled >/dev/null 2>&1; then
  echo "FAIL: legacy gh-app.enabled survived setup" >&2; exit 1
fi

# --- REGRESSION: an inherited global helper must not answer before ours ---
# Reproduces the real machine: `gh auth login` writes a github.com helper into
# ~/.gitconfig, and the system gitconfig adds osxkeychain.
personal="$work/helper-personal"
cat > "$personal" <<'EOF'
#!/usr/bin/env bash
[ "${1:-}" = get ] && { echo username=personal-user; echo password=PERSONAL_TOKEN; }
EOF
chmod +x "$personal"

ours="$work/helper-app"
cat > "$ours" <<'EOF'
#!/usr/bin/env bash
op=""
while [ $# -gt 0 ]; do case "$1" in --profile) shift 2 ;; --profile=*) shift ;; *) op="$1"; shift ;; esac; done
[ "$op" = get ] && { echo username=x-access-token; echo password=APP_TOKEN; }
EOF
chmod +x "$ours"

printf '[credential]\n\thelper = osxkeychain-stub\n' > "$work/system.gitconfig"
printf '[credential "https://github.com"]\n\thelper =\n\thelper = %s\n' "$personal" > "$work/global.gitconfig"

# Point the repo's local helper at our stub, exactly as setup wrote it (path + --profile).
git -C "$repo" config --local --unset-all credential.https://github.com.helper
git -C "$repo" config --local --add credential.https://github.com.helper ""
git -C "$repo" config --local --add credential.https://github.com.helper "$ours --profile pr-reviewer"

creds="$( printf 'protocol=https\nhost=github.com\n\n' \
  | GIT_CONFIG_SYSTEM="$work/system.gitconfig" GIT_CONFIG_GLOBAL="$work/global.gitconfig" \
    GIT_TERMINAL_PROMPT=0 git -C "$repo" credential fill 2>/dev/null )"

echo "$creds" | grep -qx 'username=x-access-token' \
  || { echo "FAIL: REGRESSION — an inherited helper won the credential race: $creds" >&2; exit 1; }
if echo "$creds" | grep -q 'PERSONAL_TOKEN'; then
  echo "FAIL: REGRESSION — personal credentials were returned: $creds" >&2; exit 1
fi

echo "PASS: per-repo setup writes the profile, is idempotent, and beats inherited helpers"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash plugins/github-app-identity/scripts/tests/test_setup_github_app_git.sh`
Expected: FAIL at the first assertion — the script takes no profile argument.

- [ ] **Step 3: Rewrite the script's argument handling and config writes**

In `plugins/github-app-identity/scripts/setup-github-app-git.sh`, keep the `parse_owner_repo`
function and the `--parse` early-exit **exactly as they are** and keep them **above** the new
argument handling, so `test_owner_repo_parse.sh` keeps passing without a profile. Replace
everything from the `dir=` line to the end of the file with:

```bash
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

[ $# -eq 1 ] || gh_app_die "usage: setup-github-app-git.sh <profile>"
profile="$1"
gh_app_load_profile "$profile"

: "${GITHUB_APP_SLUG:?GITHUB_APP_SLUG not set in $GH_APP_PROFILE_FILE}"
: "${GITHUB_APP_BOT_USER_ID:?GITHUB_APP_BOT_USER_ID not set in $GH_APP_PROFILE_FILE}"

repo_root="$(git rev-parse --show-toplevel)"
origin_url="$(git -C "$repo_root" remote get-url origin)"
owner_repo="$(parse_owner_repo "$origin_url")" \
  || gh_app_die "cannot derive owner/repo from origin: $origin_url"

bot_name="${GITHUB_APP_SLUG}[bot]"
bot_email="${GITHUB_APP_BOT_USER_ID}+${GITHUB_APP_SLUG}[bot]@users.noreply.github.com"
helper="$dir/git-credential-github-app.sh"

git -C "$repo_root" config --local user.name  "$bot_name"
git -C "$repo_root" config --local user.email "$bot_email"
git -C "$repo_root" remote set-url origin "https://github.com/${owner_repo}.git"

# git collects credential helpers system -> global -> local and uses the FIRST
# that answers. `gh auth login` writes a github.com helper into ~/.gitconfig and
# macOS ships osxkeychain in the system config, so simply appending ours would
# leave it unreachable and push as the personal account. An empty value resets
# the accumulated list, making ours the only helper for this host.
git -C "$repo_root" config --local --unset-all credential.https://github.com.helper 2>/dev/null || true
git -C "$repo_root" config --local --add credential.https://github.com.helper ""
git -C "$repo_root" config --local --add credential.https://github.com.helper "$helper --profile $profile"
git -C "$repo_root" config --local credential.https://github.com.useHttpPath false

git -C "$repo_root" config --local gh-app.profile "$profile"
git -C "$repo_root" config --local --unset-all gh-app.enabled 2>/dev/null || true

echo "Enabled GitHub App identity '$profile' for ${owner_repo}:"
echo "  commit identity: $bot_name <$bot_email>"
echo "  origin over HTTPS, credential helper reset to: $helper --profile $profile"
echo "  gh-app.profile = $profile (gh and git push act as this App here)"
echo "  verify with: gh-app-status.sh"
```

- [ ] **Step 4: Run both tests to confirm they pass**

Run:
```bash
bash plugins/github-app-identity/scripts/tests/test_setup_github_app_git.sh
bash plugins/github-app-identity/scripts/tests/test_owner_repo_parse.sh
```
Expected: `PASS: per-repo setup writes the profile, is idempotent, and beats inherited helpers`
and `PASS: owner/repo parsed from SSH/HTTPS, garbage rejected`.

- [ ] **Step 5: Commit**

```bash
git add plugins/github-app-identity/scripts/setup-github-app-git.sh \
        plugins/github-app-identity/scripts/tests/test_setup_github_app_git.sh
git commit -m "fix(github-app-identity)!: reset the credential helper list on enable

git consults credential helpers system -> global -> local and uses the first
that answers. The helper appended by setup lost to the github.com helper that
gh auth login writes into ~/.gitconfig, so pushes in enabled repos
authenticated as the personal account rather than the App. Setup now writes an
empty-string reset before its own helper, and takes the profile name."
```

---

### Task 6: `gh-app-status.sh`

**Files:**
- Create: `plugins/github-app-identity/scripts/gh-app-status.sh`
- Test: `plugins/github-app-identity/scripts/tests/test_gh_app_status.sh`

**Interfaces:**
- Consumes: `gh_app_resolve_profile`, `gh_app_load_profile` (Task 1); the token CLI (Task 2);
  the config written by Task 5.
- Produces: `gh-app-status.sh`, no arguments. Exit 0 when consistent (including a legitimate
  pass-through), non-zero when something is wrong. Task 7 installs it; the abort messages from
  Tasks 1–4 already name it.

The live access check uses `GET /repos/{owner}/{repo}` with the installation token: a single
unpaginated call that returns 200 only if this App can see this repository.
`GET /installation/repositories` would be paginated and could miss the repo on page 1.

- [ ] **Step 1: Write the failing test**

Create `plugins/github-app-identity/scripts/tests/test_gh_app_status.sh`:

```bash
#!/usr/bin/env bash
# Offline tests for gh-app-status.sh. The network probe is stubbed via
# GH_APP_CURL; the token command is stubbed via GITHUB_APP_TOKEN_CMD.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
status="$here/../gh-app-status.sh"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

profiles="$work/profiles"; mkdir -p "$profiles"
key="$work/app.pem"; echo "not-a-real-key" > "$key"; chmod 600 "$key"
cat > "$profiles/pr-reviewer.env" <<EOF
GITHUB_APP_ID=1
GITHUB_APP_INSTALLATION_ID=2
GITHUB_APP_PRIVATE_KEY_PATH=$key
GITHUB_APP_SLUG=my-reviewer
GITHUB_APP_BOT_USER_ID=4242
EOF

tok="$work/tok"; printf '#!/usr/bin/env bash\necho ghs_FAKE\n' > "$tok"; chmod +x "$tok"
ok="$work/curl-ok";  printf '#!/usr/bin/env bash\necho 200\n' > "$ok";  chmod +x "$ok"
no="$work/curl-404"; printf '#!/usr/bin/env bash\necho 404\n' > "$no"; chmod +x "$no"

# run <dir> [VAR=value ...] — `env` is required: a VAR=value coming from "$@"
# expansion is a command name, not an assignment.
run() {
  local d="$1"; shift
  ( cd "$d" && GH_APP_PROFILE_DIR="$profiles" GITHUB_APP_TOKEN_CMD="$tok" env "$@" bash "$status" )
}

# --- outside a repo: pass-through is a valid state, exit 0 ---
outside="$work/outside"; mkdir -p "$outside"
out="$(run "$outside")" || { echo "FAIL: non-zero exit outside a repo" >&2; exit 1; }
echo "$out" | grep -qi 'pass' || { echo "FAIL: no pass-through note outside a repo: $out" >&2; exit 1; }

# --- repo with no profile: pass-through, exit 0 ---
plain="$work/plain"; mkdir -p "$plain"; ( cd "$plain" && git init -q . )
out="$(run "$plain")" || { echo "FAIL: non-zero exit in an unconfigured repo" >&2; exit 1; }
echo "$out" | grep -qi 'pass' || { echo "FAIL: no pass-through note: $out" >&2; exit 1; }

# --- a fully configured repo reports the identity and exits 0 ---
repo="$work/repo"; mkdir -p "$repo"
( cd "$repo" && git init -q . \
  && git remote add origin https://github.com/acme/widget.git \
  && git config --local gh-app.profile pr-reviewer \
  && git config --local user.name  "my-reviewer[bot]" \
  && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" \
  && git config --local --add credential.https://github.com.helper "" \
  && git config --local --add credential.https://github.com.helper \
       "/opt/gh-app/git-credential-github-app.sh --profile pr-reviewer" )
out="$(run "$repo" GH_APP_CURL="$ok")" || { echo "FAIL: non-zero exit on a healthy repo: $out" >&2; exit 1; }
echo "$out" | grep -q 'pr-reviewer'  || { echo "FAIL: profile not reported: $out" >&2; exit 1; }
echo "$out" | grep -q 'my-reviewer'  || { echo "FAIL: App slug not reported: $out" >&2; exit 1; }
echo "$out" | grep -q 'acme/widget'  || { echo "FAIL: repo not reported: $out" >&2; exit 1; }

# --- commit identity that disagrees with the profile is an inconsistency ---
( cd "$repo" && git config --local user.email "someone@example.com" )
if run "$repo" GH_APP_CURL="$ok" >/dev/null 2>&1; then
  echo "FAIL: mismatched commit identity reported healthy" >&2; exit 1
fi
( cd "$repo" && git config --local user.email "4242+my-reviewer[bot]@users.noreply.github.com" )

# --- repo outside the App installation (404) is an inconsistency ---
if run "$repo" GH_APP_CURL="$no" >/dev/null 2>&1; then
  echo "FAIL: a repo outside the installation reported healthy" >&2; exit 1
fi

# --- an unreadable private key is an inconsistency ---
mv "$key" "$key.moved"
if run "$repo" GH_APP_CURL="$ok" >/dev/null 2>&1; then
  echo "FAIL: a missing private key reported healthy" >&2; exit 1
fi
mv "$key.moved" "$key"

# --- legacy config aborts ---
legacy="$work/legacy"; mkdir -p "$legacy"
( cd "$legacy" && git init -q . && git config --local gh-app.enabled true )
if run "$legacy" GH_APP_CURL="$ok" >/dev/null 2>&1; then
  echo "FAIL: legacy repo reported healthy" >&2; exit 1
fi

echo "PASS: gh-app-status reports the active identity and fails on inconsistency"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash plugins/github-app-identity/scripts/tests/test_gh_app_status.sh`
Expected: FAIL — `gh-app-status.sh` does not exist.

- [ ] **Step 3: Write the status script**

Create `plugins/github-app-identity/scripts/gh-app-status.sh`:

```bash
#!/usr/bin/env bash
# Report which GitHub App identity governs the current directory, and whether
# that identity is actually usable here. Takes no arguments: it resolves the
# profile exactly as the gh shim does, so it reports what gh and git push will
# really do. Exit 0 when consistent, non-zero when something is wrong.
set -uo pipefail

dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gh-app-common.sh
. "$dir/gh-app-common.sh"

problems=0
note() { printf '  %-22s %s\n' "$1" "$2"; }
bad()  { printf '  %-22s %s\n' "$1" "PROBLEM: $2"; problems=$((problems + 1)); }

profile="$(gh_app_resolve_profile)" || exit 1

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "gh-app: not a git repository — gh and git pass through as your personal identity."
  exit 0
fi
repo_root="$(git rev-parse --show-toplevel)"

if [ -z "$profile" ]; then
  echo "gh-app: no profile for $repo_root — gh and git pass through as your personal identity."
  echo "        enable with: setup-github-app-git.sh <profile>"
  exit 0
fi

echo "gh-app: identity for $repo_root"
gh_app_load_profile "$profile"
note "profile" "$profile"
note "profile file" "$GH_APP_PROFILE_FILE"
note "app" "${GITHUB_APP_SLUG:-<unset>} (app id ${GITHUB_APP_ID:-<unset>}, installation ${GITHUB_APP_INSTALLATION_ID:-<unset>})"

# --- private key ---
if [ -r "${GITHUB_APP_PRIVATE_KEY_PATH:-/nonexistent}" ]; then
  note "private key" "$GITHUB_APP_PRIVATE_KEY_PATH"
else
  bad "private key" "not readable at '${GITHUB_APP_PRIVATE_KEY_PATH:-<unset>}'"
fi

# --- commit identity must match the profile, or commits carry the wrong author ---
want_name="${GITHUB_APP_SLUG:-}[bot]"
want_email="${GITHUB_APP_BOT_USER_ID:-}+${GITHUB_APP_SLUG:-}[bot]@users.noreply.github.com"
got_name="$(git -C "$repo_root" config --local --get user.name 2>/dev/null || true)"
got_email="$(git -C "$repo_root" config --local --get user.email 2>/dev/null || true)"
if [ "$got_name" = "$want_name" ] && [ "$got_email" = "$want_email" ]; then
  note "commit identity" "$got_name <$got_email>"
else
  bad "commit identity" "is '$got_name <$got_email>', profile expects '$want_name <$want_email>' — re-run setup-github-app-git.sh $profile"
fi

# --- origin must be HTTPS or the credential helper is never consulted ---
origin_url="$(git -C "$repo_root" remote get-url origin 2>/dev/null || true)"
case "$origin_url" in
  https://github.com/*) note "origin" "$origin_url" ;;
  "") bad "origin" "no origin remote" ;;
  *)  bad "origin" "'$origin_url' is not HTTPS — pushes bypass the App credential helper" ;;
esac

# --- the effective helper list, as git will actually apply it ---
helpers="$(git -C "$repo_root" config --get-all credential.https://github.com.helper 2>/dev/null || true)"
last_helper="$(printf '%s\n' "$helpers" | sed -n '$p')"
case "$last_helper" in
  *git-credential-github-app.sh*--profile*"$profile"*) note "credential helper" "$last_helper" ;;
  *) bad "credential helper" "last helper is '$last_helper', not this profile's — re-run setup-github-app-git.sh $profile" ;;
esac

# --- live check: can this App actually see this repository? ---
owner_repo=""
case "$origin_url" in
  https://github.com/*) owner_repo="${origin_url#https://github.com/}"; owner_repo="${owner_repo%.git}" ;;
esac

token="$("${GITHUB_APP_TOKEN_CMD:-$dir/github-app-token.sh}" --profile "$profile" 2>/dev/null || true)"
if [ -z "$token" ]; then
  bad "token" "could not mint a token for profile '$profile'. $GH_APP_DOCTRINE"
elif [ -z "$owner_repo" ]; then
  bad "repo access" "cannot derive owner/repo from origin, skipping the access check"
else
  # One unpaginated call: 200 only if this installation can see this repo.
  code="$( "${GH_APP_CURL:-curl}" -sS -o /dev/null -w '%{http_code}' --max-time 30 \
      -H "Authorization: token $token" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/repos/${owner_repo}" 2>/dev/null || echo 000 )"
  case "$code" in
    200) note "repo access" "$owner_repo (App installation confirmed)" ;;
    404) bad "repo access" "$owner_repo is not visible to this App — install '${GITHUB_APP_SLUG}' on it" ;;
    401) bad "repo access" "token rejected (401) — check the App id and private key in $GH_APP_PROFILE_FILE" ;;
    *)   bad "repo access" "unexpected HTTP $code checking $owner_repo" ;;
  esac
fi

if [ "$problems" -ne 0 ]; then
  echo "gh-app: $problems problem(s) found."
  echo "gh-app: $GH_APP_DOCTRINE"
  exit 1
fi
echo "gh-app: OK — this clone acts as ${GITHUB_APP_SLUG}[bot] via profile '$profile'."
```

Note `set -uo pipefail` without `-e`: the script deliberately runs every check and reports all
problems at once rather than dying on the first.

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash plugins/github-app-identity/scripts/tests/test_gh_app_status.sh`
Expected: `PASS: gh-app-status reports the active identity and fails on inconsistency`

- [ ] **Step 5: Commit**

```bash
git add plugins/github-app-identity/scripts/gh-app-status.sh \
        plugins/github-app-identity/scripts/tests/test_gh_app_status.sh
git commit -m "feat(github-app-identity): add gh-app-status.sh"
```

---

### Task 7: Install the new files, and run the tests in CI

**Files:**
- Modify: `plugins/github-app-identity/scripts/install.sh`
- Modify: `plugins/github-app-identity/scripts/tests/test_install.sh`
- Modify: `.github/workflows/plugins.yml`

**Interfaces:**
- Consumes: every script from Tasks 1–6.
- Produces: `gh-app-common.sh` and `gh-app-status.sh` on `PATH` alongside the rest.

`gh-app-common.sh` is installed **without** the executable bit — it is sourced, never run.

- [ ] **Step 1: Update the test**

Replace the body of `plugins/github-app-identity/scripts/tests/test_install.sh` (keep the
shebang and `set -euo pipefail`):

```bash
#!/usr/bin/env bash
# Offline test: install.sh places every executable plus the sourced library
# into GH_APP_BIN, and the installed shim can find its library.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
install="$here/../install.sh"
bin="$(mktemp -d)"; trap 'rm -rf "$bin"' EXIT

GH_APP_BIN="$bin" bash "$install" >/dev/null

for f in gh github-app-token.sh git-credential-github-app.sh setup-github-app-git.sh gh-app-status.sh; do
  [[ -x "$bin/$f" ]] || { echo "FAIL: $f not installed/executable" >&2; exit 1; }
done

# The library is sourced, not executed: present, readable, not executable.
[[ -f "$bin/gh-app-common.sh" ]] || { echo "FAIL: gh-app-common.sh not installed" >&2; exit 1; }
if [[ -x "$bin/gh-app-common.sh" ]]; then
  echo "FAIL: gh-app-common.sh should not be executable" >&2; exit 1
fi

# An installed script must be able to source the library from its own directory.
out="$( cd / && bash -c ". '$bin/gh-app-common.sh'; gh_app_validate_profile builder && echo sourced" )"
[[ "$out" == "sourced" ]] || { echo "FAIL: installed library did not source cleanly: $out" >&2; exit 1; }

echo "PASS: install placed all five executables plus the sourced library in GH_APP_BIN"
```

- [ ] **Step 2: Run it to confirm it fails**

Run: `bash plugins/github-app-identity/scripts/tests/test_install.sh`
Expected: FAIL — `gh-app-status.sh` is not installed.

- [ ] **Step 3: Update install.sh**

In `plugins/github-app-identity/scripts/install.sh`, replace the install loop with:

```bash
for f in gh github-app-token.sh git-credential-github-app.sh setup-github-app-git.sh gh-app-status.sh; do
  install -m 0755 "$src/$f" "$bin/$f"
done
# Sourced by the scripts above, never executed — no executable bit.
install -m 0644 "$src/gh-app-common.sh" "$bin/gh-app-common.sh"
```

- [ ] **Step 4: Run the test to confirm it passes**

Run: `bash plugins/github-app-identity/scripts/tests/test_install.sh`
Expected: `PASS: install placed all five executables plus the sourced library in GH_APP_BIN`

- [ ] **Step 5: Add the CI job**

In `.github/workflows/plugins.yml`, append a second job at the same indentation as
`check-plugin`:

```yaml
  script-tests:
    name: script tests (${{ matrix.os }})
    runs-on: ${{ matrix.os }}
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest]
    steps:
      - uses: actions/checkout@v4

      - name: Run every plugin's script tests
        run: |
          # Both platforms matter: this repo targets bash 3.2 (macOS default)
          # and forbids GNU-only constructs, so a Linux-only run would hide
          # exactly the breakage that rule exists to prevent.
          fail=0
          found=0
          for t in plugins/*/scripts/tests/*.sh; do
            [ -f "$t" ] || continue
            found=1
            echo "::group::$t"
            bash "$t" || fail=1
            echo "::endgroup::"
          done
          if [ "$found" -eq 0 ]; then
            echo "::error::no script tests were found — the glob is wrong"
            exit 1
          fi
          if [ "$fail" -ne 0 ]; then
            echo "::error::one or more script tests failed"
            exit 1
          fi
```

- [ ] **Step 6: Run the whole suite locally, the way CI will**

Run:
```bash
for t in plugins/*/scripts/tests/*.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
bash scripts/check-plugin.sh plugins/github-app-identity
```
Expected: a `PASS:` line from each of the eight test files, no `FAILED:` lines, and
`check-plugin.sh` exiting 0.

- [ ] **Step 7: Commit**

```bash
git add plugins/github-app-identity/scripts/install.sh \
        plugins/github-app-identity/scripts/tests/test_install.sh \
        .github/workflows/plugins.yml
git commit -m "ci: install the status script and run plugin script tests on both platforms"
```

---

### Task 8: Replace the skill with two commands

**Files:**
- Delete: `plugins/github-app-identity/skills/github-app-identity/SKILL.md` (and the now-empty
  `skills/` tree)
- Create: `plugins/github-app-identity/commands/setup.md`
- Create: `plugins/github-app-identity/commands/enable.md`

**Interfaces:**
- Consumes: the CLIs from Tasks 2–6.
- Produces: `/github-app-identity:setup` and `/github-app-identity:enable`. These are the first
  commands in this marketplace, so their frontmatter sets the convention.

The doctrine the skill carried now lives in `GH_APP_DOCTRINE` (Task 1), which is why deleting
the skill loses nothing.

- [ ] **Step 1: Delete the skill**

```bash
git rm -r plugins/github-app-identity/skills
```

- [ ] **Step 2: Write the setup command**

Create `plugins/github-app-identity/commands/setup.md`:

```markdown
---
description: Set up this machine for GitHub App bot identities, and add a named App profile.
argument-hint: "[profile-name]"
allowed-tools: Bash, Read, Write, Edit
---

# Set up a GitHub App bot identity

Target profile: **$1** (if empty, ask which identity is being created — e.g. `builder`,
`pr-reviewer` — before doing anything).

Profile names must match `^[A-Za-z0-9][A-Za-z0-9._-]*$`: letters, digits, dot and dash only.

## 1. Check what already exists

```bash
ls "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}" 2>/dev/null
type -a gh
```

If the profile file already exists, stop and report it — do not overwrite an identity.

## 2. Walk the user through creating the App

The user must do this part in a browser; you cannot. Point them at
`templates/setup-runbook.md` and wait for the values it produces. Each identity needs its
**own** App: two agents sharing one App share one identity, which defeats the purpose.

Collect five values: App ID, installation ID, private key path, App slug, bot user id.

## 3. Write the profile

```bash
mkdir -p "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}"
cp plugins/github-app-identity/templates/profile.env.example \
   "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}/<profile>.env"
```

Fill in all five values. The private key belongs outside any repo, `chmod 600`.

## 4. Install the scripts

```bash
bash plugins/github-app-identity/scripts/install.sh
```

Confirm the shim wins on `PATH` — `type -a gh` must list `~/.local/bin/gh` first. `install.sh`
warns when it does not; that warning is not optional to fix, since a losing shim means every
`gh` call silently uses personal auth.

## 5. Enable a clone

Setup does not enable any repository. Tell the user to run `/github-app-identity:enable
<profile>` inside each clone that should use this identity — typically one clone per identity.
```

- [ ] **Step 3: Write the enable command**

Create `plugins/github-app-identity/commands/enable.md`:

```markdown
---
description: Point this clone at a GitHub App identity, so its commits, pushes, and gh calls act as that bot.
argument-hint: "<profile-name>"
allowed-tools: Bash
---

# Enable a GitHub App identity in this clone

Target profile: **$1** (required — if empty, list the available profiles with
`ls "${GH_APP_PROFILE_DIR:-$HOME/.config/gh-app/profiles}"` and ask which one).

Identity is per **clone**, not per worktree: `git config --local` in a linked worktree resolves
to the clone's shared config, so every worktree of this clone inherits what you set here. Two
identities in one repository means two clones.

## 1. Enable

```bash
setup-github-app-git.sh "$1"
```

This sets the bot commit identity, switches `origin` to HTTPS, resets the credential helper
list so inherited helpers cannot answer first, and writes `gh-app.profile`.

## 2. Verify

```bash
gh-app-status.sh
```

Every line must be clean. Report the output to the user. If it reports problems, fix the setup
— never work around an auth failure with personal credentials or `gh auth login`.
```

- [ ] **Step 4: Verify the plugin still validates**

Run: `bash scripts/check-plugin.sh plugins/github-app-identity`
Expected: exit 0. The skill checks are now vacuous for this plugin; nothing else regresses.

Also confirm nothing still points at the deleted skill:

```bash
grep -rn "skills/github-app-identity\|github-app-identity:github-app-identity" . \
  --include="*.md" --include="*.json" --include="*.sh" | grep -v docs/superpowers
```
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add -A plugins/github-app-identity
git commit -m "refactor(github-app-identity)!: replace the skill with two commands

Setup is a human-initiated operation; a skill invited agents to invoke it
mid-task. The standing rule the skill carried now ships in GH_APP_DOCTRINE,
appended to every auth-failure message, where an agent reads it at the moment
it would otherwise reach for personal credentials."
```

---

### Task 9: Documentation, templates, and version

**Files:**
- Modify: `plugins/github-app-identity/README.md`
- Modify: `plugins/github-app-identity/templates/setup-runbook.md`
- Rename: `plugins/github-app-identity/templates/github-app.env.example` →
  `plugins/github-app-identity/templates/profile.env.example`
- Modify: `plugins/github-app-identity/templates/adr-github-app-identity.md`
- Modify: `plugins/github-app-identity/.claude-plugin/plugin.json`
- Modify: `plugins/devtools/README.md`, `plugins/devtools/skills/pr-reviewer/SKILL.md`

**Interfaces:**
- Consumes: everything. This task documents the finished behaviour.
- Produces: no code.

- [ ] **Step 1: Rename and rewrite the profile template**

```bash
git mv plugins/github-app-identity/templates/github-app.env.example \
       plugins/github-app-identity/templates/profile.env.example
```

Then replace its contents:

```bash
# One GitHub App identity for the github-app-identity plugin.
# Copy to ~/.config/gh-app/profiles/<profile>.env (or under $GH_APP_PROFILE_DIR)
# and fill in. One file per identity; each identity needs its own App.
# Profile names must match ^[A-Za-z0-9][A-Za-z0-9._-]*$ — e.g. builder, pr-reviewer.
# See setup-runbook.md.

# Numeric App ID (App settings page).
GITHUB_APP_ID=

# Numeric installation ID (this App's install on your account).
GITHUB_APP_INSTALLATION_ID=

# Absolute path to this App's private key .pem (keep it OUTSIDE any repo, chmod 600).
GITHUB_APP_PRIVATE_KEY_PATH=$HOME/.config/gh-app/<profile>.pem

# This App's slug (from its public URL). Builds the bot identity.
GITHUB_APP_SLUG=

# Numeric id of this App's bot user: gh api /users/<slug>[bot] --jq .id
GITHUB_APP_BOT_USER_ID=
```

- [ ] **Step 2: Rewrite the README**

Replace `plugins/github-app-identity/README.md`:

```markdown
# github-app-identity

Give local automation (Claude Code, agents, your own scripts) dedicated **GitHub App**
identities instead of your personal credentials — several of them, one per clone, with no
silent fallback to personal auth.

Typical use: a build clone commits and pushes as one bot, a review clone reviews and merges as
another. Because GitHub rejects an `APPROVE` from a pull request's own author, two identities
are what make a real review verdict possible.

## How it works

- Each identity is a **profile**: one env file under `~/.config/gh-app/profiles/<name>.env`
  naming a GitHub App, its installation, and its key. Each identity needs its own App.
- A clone opts in with `git config --local gh-app.profile <name>`. A global `gh` **shim** on
  `PATH` reads that marker, mints a short-lived installation token for that profile, and runs
  the real `gh` as the App. Everywhere else it passes straight through. If the token cannot be
  minted it **aborts** rather than fall back to your personal identity.
- A **git credential helper** does the same for `git push`/`fetch` over HTTPS. Enabling a repo
  resets the credential helper list first, so helpers inherited from your global config
  (`gh auth login`) or the system config (osxkeychain) cannot answer before it.
- Bot-authored commits come from per-repo `user.name`/`user.email`.
- Tokens are cached **per profile**, so two clones can never reuse each other's identity.

Identity is per clone, not per worktree: `git config --local` in a linked worktree resolves to
the clone's shared config, so every worktree inherits the clone's identity. Two identities in
one repository means two clones.

## Setup

1. **Per identity:** `/github-app-identity:setup <profile>` — create the App (see
   `templates/setup-runbook.md`), write `~/.config/gh-app/profiles/<profile>.env`, and put the
   scripts on `PATH` with `scripts/install.sh`.
2. **Per clone:** `/github-app-identity:enable <profile>` — bot identity, HTTPS origin,
   credential helper reset, and the `gh-app.profile` marker.

## Checking

```bash
gh-app-status.sh    # which bot am I here, and can it actually see this repo?
```

An auth failure means setup is incomplete. Fix the setup — never work around it with personal
credentials or `gh auth login`.

Commits are bot-authored (not cryptographically "Verified"). GitHub Actions CI is out of scope:
use `actions/create-github-app-token` there.
```

- [ ] **Step 3: Update the runbook**

In `plugins/github-app-identity/templates/setup-runbook.md`:

Replace the intro paragraph with:

```markdown
One-time, human-run setup so local automation (Claude Code, agents, your scripts) acts as
dedicated **GitHub Apps** inside clones you opt in. Each bot identity is a **profile** backed
by its own App — run sections 1–5 once per identity, then section 7 once per clone. Scope is
local tooling only (not GitHub Actions — see the end).
```

In section 1, replace the **Repository permissions** bullet with, verbatim:

```markdown
- **Repository permissions:** grant what this identity's role actually needs. `Metadata:
  Read-only` is always required. Beyond that it depends on what the agent does, so decide per
  App rather than copying a recipe.
```

In section 2, change the key destination to `~/.config/gh-app/<profile>.pem` so two Apps do not
collide on one filename.

Replace section 5 with:

```markdown
## 5. Write the profile

```bash
mkdir -p ~/.config/gh-app/profiles
cp templates/profile.env.example ~/.config/gh-app/profiles/<profile>.env
$EDITOR ~/.config/gh-app/profiles/<profile>.env   # fill in all five values
```

Profile names must match `^[A-Za-z0-9][A-Za-z0-9._-]*$` — `builder`, `pr-reviewer`. Repeat
sections 1–5 for each identity you want.
```

Replace sections 7 and 8 with:

````markdown
## 7. Enable a clone

Inside each clone you want to opt in:

```bash
setup-github-app-git.sh <profile>   # bot identity, HTTPS origin, credential reset, marker
```

Identity is per clone, not per worktree — every worktree of a clone inherits it. Two identities
in one repository means two clones.

## 8. Verify

```bash
# a) inside an enabled clone, everything agrees and the App can see the repo
gh-app-status.sh

# b) git will actually use the App, not an inherited helper
printf 'protocol=https\nhost=github.com\n\n' | git credential fill | grep username
#    expected: username=x-access-token

# c) outside any enabled clone, gh is unchanged
cd /tmp && gh auth status   # your personal identity, untouched
```
````

Append a migration section at the end, before "Future: GitHub Actions CI":

```markdown
## Migrating from the single-App layout

Earlier versions kept one App in `~/.config/gh-app/github-app.env` and marked repos with
`gh-app.enabled`. To move:

```bash
mkdir -p ~/.config/gh-app/profiles
mv ~/.config/gh-app/github-app.env ~/.config/gh-app/profiles/<profile>.env
bash scripts/install.sh
```

Then, in every clone that was enabled: `setup-github-app-git.sh <profile>`.

A clone you miss aborts on its next `gh` call — `gh-app.enabled` without `gh-app.profile` is
treated as broken config, not as a reason to pass through to your personal identity.
```

- [ ] **Step 4: Update the ADR template**

In `plugins/github-app-identity/templates/adr-github-app-identity.md`, replace the **Decision**
and **Consequences** sections:

```markdown
## Decision

Adopt the `github-app-identity` plugin with one **profile** per bot identity. Each profile is
an env file under `~/.config/gh-app/profiles/<name>.env` naming its own GitHub App, and a clone
opts in with `git config --local gh-app.profile <name>`. A global directory-aware `gh` shim, a
git credential helper, and per-repo git config make commits, pushes, and `gh`/API calls act as
that App inside that clone only. The shim aborts rather than fall back to personal auth if a
token cannot be minted, and tokens are cached per profile so identities cannot bleed.

Enabling a repo resets git's credential helper list before registering the App helper: git
consults helpers system → global → local and uses the first that answers, so an appended helper
loses to the github.com helper `gh auth login` writes into `~/.gitconfig`.

Identity is per clone, not per worktree — `--local` in a linked worktree resolves to the
clone's shared config. Two identities in one repository means two clones. Commits are
bot-authored but not cryptographically "Verified". GitHub Actions CI is out of scope.

## Consequences

Easier: machine work is attributable to a specific bot, not a person; a reviewer identity
distinct from the author identity restores real `APPROVE`/`REQUEST_CHANGES` verdicts; no
per-call-site wrapping and no silent personal-auth fallback. Harder: one App and one profile
per identity to create and maintain; a one-time per-machine install; the shim relies on `PATH`
precedence; each App is its own revocation point; and running two identities against one
repository requires two clones.
```

- [ ] **Step 5: Bump the version and note the interop**

In `plugins/github-app-identity/.claude-plugin/plugin.json`, set `"version": "0.2.0"` and
replace `description` with:

```json
  "description": "Give local automation dedicated GitHub App identities — one profile per bot, selected per clone. A directory-aware `gh` shim, a token minter, and a git credential helper make commits, pushes, and gh/API calls act as the App, never falling back to personal credentials.",
```

In `plugins/devtools/README.md` (the paragraph at line ~104) and
`plugins/devtools/skills/pr-reviewer/SKILL.md` (line ~426), extend the existing
`github-app-identity` sentence to name the mechanism:

> Installing this repo's `github-app-identity` plugin and giving the reviewer clone its own
> profile (a different App from the one the build agent commits under) makes `pr-reviewer` post
> as a distinct account — restoring real `APPROVE` and `REQUEST_CHANGES` records even when it
> is reviewing its own work.

- [ ] **Step 6: Verify the docs match the code**

Run:
```bash
grep -rn "gh-app.enabled\|github-app.env\|GITHUB_APP_ENV\|GITHUB_APP_TOKEN_CACHE" \
  plugins/github-app-identity --include="*.md" --include="*.json"
```
Expected: matches only inside the runbook's migration section (which describes the old layout
on purpose). Any other hit is stale documentation — fix it.

Then:
```bash
bash scripts/check-plugin.sh plugins/github-app-identity
for t in plugins/*/scripts/tests/*.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
```
Expected: exit 0, eight `PASS:` lines, no `FAILED:`.

- [ ] **Step 7: Commit**

```bash
git add plugins/github-app-identity plugins/devtools
git commit -m "docs(github-app-identity): document profiles and bump to 0.2.0"
```

---

## Final verification

- [ ] Full suite, the way CI runs it:
  ```bash
  for t in plugins/*/scripts/tests/*.sh; do echo "== $t"; bash "$t" || echo "FAILED: $t"; done
  for p in plugins/*/; do bash scripts/check-plugin.sh "$p" || echo "FAILED: $p"; done
  ```
  Expected: eight `PASS:` lines, no `FAILED:`.

- [ ] Real-world smoke test, run by the user on this machine after migrating:
  ```bash
  cd <build clone>  && gh-app-status.sh
  cd <review clone> && gh-app-status.sh
  ```
  Both must report OK with **different** App slugs. Then confirm the defect is actually fixed:
  ```bash
  printf 'protocol=https\nhost=github.com\n\n' | git credential fill | grep username
  ```
  Expected: `username=x-access-token`. If it says anything else, the credential reset did not
  take and pushes would still be personal.
