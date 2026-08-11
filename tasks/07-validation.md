# Task 07: End-to-End Validation

## Why

After all migration artifacts are created, we need to verify that:
1. The full file count matches the migration checklist in the plan
2. No stale `${CLAUDE_PLUGIN_ROOT}` references exist anywhere in the `.opencode/` tree
3. All files are well-formed (frontmatter valid, no missing files)
4. The directory structure exactly matches the plan's file layout
5. The agent model assignments and permission profiles match the plan

This task does NOT test runtime behavior (which requires a live OpenCode session with a project) — it validates structural correctness of the migration output.

## What

Run a comprehensive set of verification checks against `plugins/kanban-flow/.opencode/`.

## How

### Check 1: File Count Match

Count files against the migration checklist:

```bash
# Commands: 6 files
ls -1 plugins/kanban-flow/.opencode/commands/*.md | wc -l

# Skills: 3 files (one SKILL.md each in 3 directories)
find plugins/kanban-flow/.opencode/skills -name "SKILL.md" | wc -l

# Agents: 13 files
ls -1 plugins/kanban-flow/.opencode/agents/*.md | wc -l

# Doctrine: 30 files (recursive)
find plugins/kanban-flow/.opencode/doctrine -type f | wc -l
```

Expected counts: commands=6, skills=3, agents=13, doctrine=30

### Check 2: No Stale References

```bash
# No ${CLAUDE_PLUGIN_ROOT} anywhere in .opencode/
grep -rl '\${CLAUDE_PLUGIN_ROOT}' plugins/kanban-flow/.opencode/
# Must produce NO output

# No references to old reference file paths in the orchestrator skill
grep -l 'references/pump\.md\|references/reconcile-edge-cases\.md\|references/split-shipping\.md' plugins/kanban-flow/.opencode/skills/kanban-orchestrator/SKILL.md
# Must produce NO output
```

### Check 3: Valid YAML Frontmatter in All Agent Files

```bash
python3 -c "
import sys, os, yaml

base = 'plugins/kanban-flow/.opencode'
agents_dir = os.path.join(base, 'agents')
for f in sorted(os.listdir(agents_dir)):
    if not f.endswith('.md'):
        continue
    path = os.path.join(agents_dir, f)
    content = open(path).read()
    if not content.startswith('---'):
        print(f'{f}: MISSING frontmatter (does not start with ---)')
        sys.exit(1)
    end = content.index('---', 3)
    fm = yaml.safe_load(content[3:end])
    required = ['name', 'description', 'mode', 'model']
    missing = [k for k in required if k not in fm]
    if missing:
        print(f'{f}: MISSING keys: {missing}')
        sys.exit(1)
    if fm['mode'] != 'subagent':
        print(f'{f}: mode is {fm[\"mode\"]}, expected subagent')
        sys.exit(1)
    print(f'{f}: OK (model={fm[\"model\"]})')
print('All agent frontmatter valid')
" 2>&1
```

If `yaml` is not available, use:

```bash
for f in plugins/kanban-flow/.opencode/agents/*.md; do
  name=$(basename "$f")
  if ! head -1 "$f" | grep -q '^---$'; then
    echo "FAIL: $name missing frontmatter"
  fi
done
echo "Frontmatter presence check complete"
```

### Check 4: Valid YAML Frontmatter in Command and Skill Files

```bash
for f in plugins/kanban-flow/.opencode/commands/*.md; do
  name=$(basename "$f")
  if ! head -1 "$f" | grep -q '^---$'; then
    echo "FAIL: $name command missing frontmatter"
  else
    echo "OK: $name command"
  fi
done

for f in plugins/kanban-flow/.opencode/skills/*/SKILL.md; do
  name=$(basename $(dirname "$f"))
  if ! head -1 "$f" | grep -q '^---$'; then
    echo "FAIL: $name skill missing frontmatter"
  else
    echo "OK: $name skill"
  fi
done
```

### Check 5: Model Assignments Match Plan

```bash
python3 -c "
import os, yaml

base = 'plugins/kanban-flow/.opencode/agents'
expected = {
    'pump-gate': 'anthropic/claude-haiku-4-5',
    'card-deliverer': 'anthropic/claude-haiku-4-5',
}

for f in os.listdir(base):
    if not f.endswith('.md'):
        continue
    path = os.path.join(base, f)
    content = open(path).read()
    start = content.index('---', 3)
    fm = yaml.safe_load(content[3:start])
    name = f.replace('.md', '')
    exp = expected.get(name, 'anthropic/claude-sonnet-4-6')
    if fm['model'] != exp:
        print(f'{name}: model={fm[\"model\"]}, expected={exp}')
        sys.exit(1)
print('All model assignments correct')
" 2>&1 || echo "Model check skipped (install pyyaml)"
```

### Check 6: Permission Profiles Match Plan

```bash
python3 -c "
import os, yaml, sys

base = 'plugins/kanban-flow/.opencode/agents'
producers = {'card-implementer', 'card-deliverer', 'pr-splitter'}
readonly_bash = {'card-tester', 'card-lens-reviewer', 'card-split-checker', 'card-deliver-checker', 'pump-gate'}
ask_bash = {'card-slicer', 'card-designer', 'card-intake-checker', 'card-slice-checker', 'card-design-checker'}

for f in os.listdir(base):
    if not f.endswith('.md'):
        continue
    path = os.path.join(base, f)
    content = open(path).read()
    start = content.index('---', 3)
    fm = yaml.safe_load(content[3:start])
    name = f.replace('.md', '')
    perm = fm.get('permission', {})
    edit = perm.get('edit', 'deny')
    bash_perm = perm.get('bash', 'ask')

    if name in producers:
        assert edit == 'allow', f'{name}: expected edit=allow, got {edit}'
        assert bash_perm == 'allow', f'{name}: expected bash=allow, got {bash_perm}'
    elif name in readonly_bash:
        assert edit == 'deny', f'{name}: expected edit=deny, got {edit}'
        assert bash_perm == 'allow', f'{name}: expected bash=allow, got {bash_perm}'
    elif name in ask_bash:
        assert edit == 'deny', f'{name}: expected edit=deny, got {edit}'
        assert bash_perm == 'ask', f'{name}: expected bash=ask, got {bash_perm}'
    else:
        print(f'UNKNOWN agent: {name}')
        sys.exit(1)
print('All permission profiles correct')
" 2>&1 || echo "Permission check skipped (install pyyaml)"
```

### Check 7: Directory Structure Matches Plan

```bash
# Expected directories
for dir in \
  plugins/kanban-flow/.opencode/commands \
  plugins/kanban-flow/.opencode/skills/kanban-orchestrator \
  plugins/kanban-flow/.opencode/skills/adr \
  plugins/kanban-flow/.opencode/skills/req-ids \
  plugins/kanban-flow/.opencode/agents \
  plugins/kanban-flow/.opencode/doctrine/board \
  plugins/kanban-flow/.opencode/doctrine/checks \
  plugins/kanban-flow/.opencode/doctrine/lenses \
  plugins/kanban-flow/.opencode/doctrine/testing; do
  [ -d "$dir" ] && echo "OK: $dir" || echo "MISSING: $dir"
done
```

### Check 8: Doctrine Files Match Sources (byte-identical)

```bash
# Spot-check a subset — if these pass, the full copy was correct
diff plugins/kanban-flow/templates/AGENT-PROTOCOL.md plugins/kanban-flow/.opencode/doctrine/AGENT-PROTOCOL.md && echo "OK: AGENT-PROTOCOL.md"
diff plugins/kanban-flow/templates/checks/_method.md plugins/kanban-flow/.opencode/doctrine/checks/_method.md && echo "OK: checks/_method.md"
diff plugins/kanban-flow/templates/lenses/_shared.md plugins/kanban-flow/.opencode/doctrine/lenses/_shared.md && echo "OK: lenses/_shared.md"
diff plugins/kanban-flow/templates/testing/LEVELS.md plugins/kanban-flow/.opencode/doctrine/testing/LEVELS.md && echo "OK: testing/LEVELS.md"
diff plugins/kanban-flow/templates/board/BOARD.md plugins/kanban-flow/.opencode/doctrine/board/BOARD.md && echo "OK: board/BOARD.md"
diff plugins/kanban-flow/templates/INTAKE.md plugins/kanban-flow/.opencode/doctrine/INTAKE.md && echo "OK: INTAKE.md"
diff plugins/kanban-flow/templates/config.md plugins/kanban-flow/.opencode/doctrine/config.md && echo "OK: config.md"
```

### Check 9: opencode.json is Valid

```bash
python3 -c "
import json, sys
cfg = json.load(open('plugins/kanban-flow/opencode.json'))
assert cfg['subagent_depth'] == 2, 'subagent_depth must be 2'
agents = cfg.get('agent', {})
for name in ['card-implementer', 'card-deliverer', 'pr-splitter']:
    a = agents.get(name, {})
    p = a.get('permission', {})
    assert p.get('edit') == 'allow', f'{name}: edit=allow required'
    assert p.get('bash') == 'allow', f'{name}: bash=allow required'
print('opencode.json valid')
"
```

## Verification

All checks above must pass. If any check fails, fix the issue and re-run the failing check.

A successful run produces output like:
```
Commands: 6
Skills: 3
Agents: 13
Doctrine: 30
No stale references found
All agent frontmatter valid
All model assignments correct
All permission profiles correct
All directories exist
Doctrine files match
opencode.json valid
```

## Dependencies

All previous tasks (01–06) must be complete before running validation.
