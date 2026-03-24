# Sync Skills Registry

After skill files are updated, synchronize the registry, plugin, and marketplace manifests.

## Input

$ARGUMENTS — optional: skill name(s) to sync. If omitted, auto-detect from git diff.

## Procedure

### 1. Detect changed skills

- Run `git diff HEAD~1 --name-only` to find changed files under `skills/`
- Extract unique skill names from paths matching `skills/<name>/`
- If $ARGUMENTS provided, use those skill names instead

### 2. Validate file list — disk vs index.json

For each changed skill:

1. List actual files on disk: `skills/<name>/SKILL.md` + `skills/<name>/references/*.md`
2. Read `skills/index.json` → find matching skill entry → read `files` array
3. Add any files present on disk but missing from `files` array
4. Remove any files listed in `files` array but missing from disk
5. Sort `files` array: `SKILL.md` first, then `references/` alphabetically

### 3. Sync description — SKILL.md → index.json

For each changed skill:

1. Read `description` from `skills/<name>/SKILL.md` YAML frontmatter
2. Read `description` from matching entry in `skills/index.json`
3. If different → update `index.json` to match SKILL.md (SKILL.md is source of truth)

### 4. Bump patch version

Increment **patch** version across all manifest files:

- `.claude-plugin/plugin.json` → `version`
- `.claude-plugin/marketplace.json` → top-level `version` AND `plugins[0].version`

All three version values MUST match after bump.

**Rules:**
- Skill content updates = patch bump (e.g. 1.1.0 → 1.1.1)
- New skill or major structural change = minor bump — only if user explicitly says so
- Major bump = never unless user explicitly requests

### 5. Validate JSON

```bash
node -e "JSON.parse(require('fs').readFileSync('skills/index.json','utf8')); console.log('index.json: valid')"
```

### 6. Report

Output a summary table:

| Item | Status |
|------|--------|
| Changed skill(s) | list names |
| Files added to index.json | list or "none" |
| Files removed from index.json | list or "none" |
| Description synced | yes/no per skill |
| New version | X.Y.Z |

Do NOT commit. Suggest a commit message and let the user decide.
