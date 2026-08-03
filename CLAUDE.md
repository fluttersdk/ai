# CLAUDE.md

FlutterSDK AI skill registry that distributes AI coding skills, MCP servers, and commands for Wind UI, Magic Framework, and more across OpenCode, Claude Code, Cursor, Gemini CLI, and VS Code Copilot.

Hosted via GitHub Pages at `fluttersdk.github.io/ai/`

## Commands

| Command | Description |
|---------|-------------|
| `npm run build` | Compile MCP server (from `mcps/fluttersdk-mcp/`) |
| `npm run lint` | ESLint check (MCP server) |
| `npm test` | Run MCP server tests |
| `cd mcps/fluttersdk-mcp && npm test` | Run bridge-specific tests |
| `node -e "JSON.parse(require('fs').readFileSync('skills/index.json','utf8'))"` | Validate registry JSON |
| `bash scripts/install.sh --dry-run` | Preview multi-tool installation |

## Architecture

- `skills/`: GitHub Pages root. Each skill = `<name>/SKILL.md` + `<name>/references/*.md`
  - `wind-ui/`: Wind UI className system, from `fluttersdk_wind`
  - `magic-framework/`: Magic Framework IoC + Facades + ORM, from `magic`
  - `fluttersdk-dusk/`: E2E Flutter app driver via MCP, from `fluttersdk_dusk`
  - `fluttersdk-telescope/`: Runtime inspector, 9 ring buffers, from `fluttersdk_telescope`
  - `fluttersdk-artisan/`: CLI framework + stdio MCP server, from `fluttersdk_artisan`

> **Every `skills/<name>/` directory is a MIRROR. Never edit a skill here.** `sync.yml` rsyncs the upstream subtree with `--delete`, so a registry-only file is one sync away from deletion; that is how six hand-written `wind-ui` reference files disappeared before anyone noticed. Edit the skill in its upstream repo (`fluttersdk/wind`, `magic`, `dusk`, `telescope`, `artisan`) and let the sync deliver it.
>
> The sync fires when an upstream **publishes a release**, not on every upstream push. To pull an unreleased skill fix, run the upstream repo's "Dispatch skill update to registry" workflow manually. Per-skill versions live in each `SKILL.md` frontmatter and in `skills/index.json`; do not copy them into prose here, they drift within a release cycle.
- `skills/index.json`: OpenCode discovery manifest. Source of truth for file listing
- `.claude-plugin/`: Plugin manifest (`plugin.json`) + marketplace catalog (`marketplace.json`)
- `mcps/`: MCP servers (TypeScript, stdio transport, Zod schemas)
- `commands/`: Claude Code plugin commands (`flutter-review.md`, `flutter-test.md`); auto-discovered as `/fluttersdk:<name>`
- `tool-templates/`: Cross-tool command templates (`cursor/`, `gemini/`, `opencode/`) consumed by `scripts/install.sh`
- `.mcp.json`: Bundled MCP server config (HTTP transport to `mcp.fluttersdk.com`); auto-loaded on plugin install
- `.github/workflows/deploy-registry.yml`: Auto-deploys `skills/` to Pages on push to main; also writes `.well-known/skills/index.json` for OpenCode forward-compat
- `.github/workflows/sync.yml`: Automates skill sync checklist on push to main

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

Run `.github/workflows/sync.yml` (or push to `main`) to automate this checklist.

> Missing from `index.json` = OpenCode users won't get the file.
> Missing version bump = Claude Code users won't get the update.

## Anti-Patterns

- Never put skills inside `.claude-plugin/`: skills live at `skills/` root
- Never use inline single-line arrays: multi-line with trailing commas
- Never create MCP tools without Zod input schemas
- Never hardcode paths in install script: use `$HOME` / `$XDG_CONFIG_HOME`
- Skill names: lowercase, hyphen-separated only (`wind-ui`, not `WindUI`)

## Code Style (Project-Specific)

- Markdown: ATX headers, fenced code blocks with language ID, tables for structured data
- TypeScript (MCP): 4-space indent, 120-char width, `const` over `let`, no `any`
- JSON: 4-space indent, trailing newline, hyphen-separated keys for skills
