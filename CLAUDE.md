# CLAUDE.md

AI skill registry that distributes AI coding skills, MCP servers, and commands for Wind UI, Magic Framework, and more across OpenCode, Claude Code, Cursor, Gemini CLI, Codex CLI and more.

Hosted via GitHub Pages at `anilcancakir.github.io/ai/`

## Commands

| Command | Description |
|---------|-------------|
| `actionlint .github/workflows/*.yml` | Lint the workflows |
| `jq empty registry-sources.json .claude-plugin/*.json .mcp.json` | Validate the JSON manifests |
| `node -e "JSON.parse(require('fs').readFileSync('skills/index.json','utf8'))"` | Validate registry JSON |
| `bash scripts/install.sh --dry-run` | Preview multi-tool installation |

## Architecture

- `skills/`: GitHub Pages root. Each skill = `<name>/SKILL.md` + `<name>/references/*.md`
  - `wind-ui/`: Wind UI className system, from `wind_kit`
  - `magic-framework/`: Magic Framework IoC + Facades + ORM, from `magic`
  - `tapir/`: E2E Flutter app driver via MCP, from `tapir`
  - `crumbs/`: Runtime inspector over MCP, from `crumbs`
  - `dowel/`: CLI framework + stdio MCP server, from `dowel`

> **Every `skills/<name>/` directory is a MIRROR. Never edit a skill here.** `sync.yml` rsyncs the upstream subtree with `--delete`, so a registry-only file is one sync away from deletion; that is how six hand-written `wind-ui` reference files disappeared before anyone noticed. Edit the skill in its upstream repo (`registry-sources.json` lists the repo, branch and skill directory behind each source key) and let the sync deliver it.
>
> The sync fires when an upstream **publishes a release**, not on every upstream push. To pull an unreleased skill fix, run the upstream repo's "Dispatch skill update to registry" workflow manually. Per-skill versions live in each `SKILL.md` frontmatter and in `skills/index.json`; do not copy them into prose here, they drift within a release cycle.
- `skills/index.json`: OpenCode discovery manifest. Source of truth for file listing
- `.claude-plugin/`: Plugin manifest (`plugin.json`) + marketplace catalog (`marketplace.json`)
- `commands/`: Claude Code plugin commands (`flutter-test.md`); auto-discovered as `/anilcancakir:<name>`
- `agents/`: plugin subagents (`flutter-reviewer.md`, `flutter-reviewer-deep.md`); auto-discovered as `anilcancakir:<name>`. Plugin agents support `name`, `description`, `model`, `effort`, `maxTurns`, `tools`, `disallowedTools`, `skills`, `memory`, `background`, `isolation` only; `hooks`, `mcpServers`, and `permissionMode` are ignored for plugin-shipped agents, so do not add them
- `references/`: plugin-owned reference files the skill and agents read through `${CLAUDE_PLUGIN_ROOT}` (`flutter-review-core.md`, `dart-style-core.md`). Not part of any mirrored skill

> `skills/flutter-review/` is the one skill this repo owns rather than mirrors, and it is deliberately absent from `skills/index.json`: it orchestrates Claude Code subagents, which the other tools the registry serves cannot spawn. Everything else under `skills/` is a mirror and belongs in the index.
- `tool-templates/`: Cross-tool command templates (`cursor/`, `gemini/`, `opencode/`) consumed by `scripts/install.sh`
- `.mcp.json`: Bundled MCP server config (HTTP transport to `mcp.anilcancakir.com`); auto-loaded on plugin install
- `.github/workflows/deploy-registry.yml`: Auto-deploys `skills/` to Pages on push to master; also writes `.well-known/skills/index.json` for OpenCode forward-compat
- `.github/workflows/sync.yml`: Receives `repository_dispatch` from a source repo, validates the source key against `registry-sources.json`, mirrors the skill, bumps the version triplet and pushes to master as the `anilcancakir-ai-registry` App. To add a source, add one entry to `registry-sources.json`; `replaces` lists skill directories the source supersedes (they are deleted on its first sync)
- `registry-sources.json`: Allowed sync sources, one key per source repo: `repo`, `branch`, `skill`, `replaces`

## Skill Format

`SKILL.md` uses YAML frontmatter with two required fields:
- `name`: 1-64 chars, lowercase, alphanumeric + hyphens
- `description`: 1-1024 chars, must include trigger keywords for agent activation

Reference files go in `references/`: pure Markdown, no frontmatter, loaded on-demand.

## Sync Rules (Critical)

After ANY skill change, ALL of the following must stay in sync:

1. Every file on disk under `skills/<name>/` must be listed in `index.json` `files` array
2. `index.json` `description` must match SKILL.md frontmatter `description`
3. `.claude-plugin/plugin.json` version must be bumped (patch for content updates)
4. `.claude-plugin/marketplace.json` version must match, both top-level AND `plugins[0].version`

`sync.yml` performs this checklist for every mirrored skill; a change you make by hand (the owned `flutter-review`, the manifests, the installer) must keep it true.

> Missing from `index.json` = OpenCode users won't get the file.
> Missing version bump = Claude Code users won't get the update.

## Post-Change Checklist

A change is not done while any of these is stale: `CHANGELOG.md` `[Unreleased]`, `README.md`, `docs/SKILLS.md` (skill table), `docs/UPSTREAM-SETUP.md` (sources), `registry-sources.json`, and the Architecture list above. Then `actionlint .github/workflows/*.yml`, the JSON files parse (`jq empty`), and `bash -n scripts/install.sh`.

## Development Flow

Branch from `master` as `<type>/<topic>` (`feat`, `fix`, `chore`, `docs`, `refactor`, `release`) and open a pull request into `master`; nothing is pushed to `master` by hand. The registry App pushes sync commits to `master` directly; that is why the branch rules use a ruleset with the App as a bypass actor rather than classic protection.

## Testing

- Workflows: `actionlint`. Manifests: the `Plugin manifest + version sync` job (schema, three-way version, frontmatter of every plugin component).
- `scripts/update-skill-index.mjs`: run it on a scratch tree with `SKILL=<name> REPLACES="<old>"` before changing it.

## Release

The registry has no manual release. Every accepted sync patch-bumps the version triplet (`plugin.json`, `marketplace.json` and `plugins[0]`) and creates a GitHub Release `vX.Y.Z`. Repo-owned changes that ship (agents, commands, `flutter-review`, the installer, the manifests) go into `CHANGELOG.md` under `[Unreleased]`; there is no tag per change.

## CI

- `ci.yml` (`Lint & Test`): aggregator over `Workflows lint` and `Plugin manifest + version sync`; no `paths:` filter.
- `changelog.yml` (`Changelog`): a pull request that changes shipped files needs a `CHANGELOG.md` entry, or the `skip-changelog` label; Dependabot and `release:` titles are exempt.
- `deploy-registry.yml`: a push to `master` that changes `skills/**` deploys Pages and writes `.well-known/skills/index.json`.
- `sync.yml`: `repository_dispatch` from a source repo, or run by hand with `source` and `version`.

## Anti-Patterns

- Never put skills inside `.claude-plugin/`: skills live at `skills/` root
- Never use inline single-line arrays: multi-line with trailing commas
- Never hardcode paths in install script: use `$HOME` / `$XDG_CONFIG_HOME`
- Skill names: lowercase, hyphen-separated only (`wind-ui`, not `WindUI`)

## Code Style (Project-Specific)

- Markdown: ATX headers, fenced code blocks with language ID, tables for structured data
- TypeScript (MCP): 4-space indent, 120-char width, `const` over `let`, no `any`
- JSON: 4-space indent, trailing newline, hyphen-separated keys for skills
