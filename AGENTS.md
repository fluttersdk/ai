# AGENTS.md — FlutterSDK AI Repository

> AI skill registry and tooling for the FlutterSDK ecosystem.
> Published at `github.com/fluttersdk/ai` · Hosted via GitHub Pages at `fluttersdk.github.io/ai/`

---

## Repository Purpose

This repository distributes AI coding skills, MCP servers, commands, and scripts for FlutterSDK community products (Wind UI, Magic Framework, etc.) across **all major AI coding tools**: OpenCode, Claude Code, Cursor, Gemini CLI, and VS Code Copilot.

## Directory Structure

```
fluttersdk-ai/
├── .claude-plugin/                 ← Claude Code plugin manifest
│   ├── plugin.json                 ← Plugin metadata (name, version, description)
│   └── marketplace.json            ← Marketplace catalog for plugin distribution
│
├── skills/                         ← GitHub Pages deployment root + Claude Code plugin skills
│   ├── index.json                  ← OpenCode skill discovery manifest
│   ├── .nojekyll                   ← Disable Jekyll processing
│   ├── wind-ui/                    ← Wind UI skill
│   │   ├── SKILL.md
│   │   └── references/
│   │       ├── widgets.md
│   │       ├── layout-patterns.md
│   │       ├── design-tokens.md
│   │       ├── tokens.md
│   │       ├── component-patterns.md
│   │       ├── form-patterns.md
│   │       └── theme-setup.md
│   └── magic-framework/           ← Magic Framework skill
│       ├── SKILL.md
│       └── references/
│           ├── controllers-views.md
│           ├── eloquent-orm.md
│           ├── facades-api.md
│           ├── routing-navigation.md
│           ├── bootstrap-lifecycle.md
│           ├── auth-system.md
│           ├── forms-validation.md
│           ├── http-network.md
│           ├── secondary-systems.md
│           └── testing-patterns.md
│
├── mcps/                           ← MCP server projects
│   └── fluttersdk-mcp/            ← TypeScript MCP server (npm: @fluttersdk/mcp)
│       ├── package.json
│       ├── tsconfig.json
│       └── src/
│           └── index.ts
│
├── commands/                       ← Reusable command templates per tool
│   ├── opencode/                   ← OpenCode command snippets (JSON)
│   ├── claude/                     ← Claude Code commands (.md)
│   ├── gemini/                     ← Gemini CLI commands (.toml)
│   └── cursor/                     ← Cursor rules (.mdc)
│
├── scripts/
│   └── install.sh                  ← Universal multi-tool installer
│
├── .github/
│   ├── workflows/
│   │   └── deploy-registry.yml     ← GitHub Pages deployment
│   └── copilot-instructions.md     ← VS Code Copilot instructions
│
├── AGENTS.md                       ← This file
├── README.md
├── LICENSE                         ← MIT
├── .editorconfig
└── .gitignore
```

## Build / Lint / Test Commands

```bash
# No build step for skills — they are static markdown files.
# MCP server (from mcps/fluttersdk-mcp/):
npm install                         # Install dependencies
npm run build                       # Compile TypeScript
npm run lint                        # ESLint check
npm test                            # Run tests

# Validate registry index:
node -e "JSON.parse(require('fs').readFileSync('skills/index.json','utf8'))"

# Install script:
bash scripts/install.sh --dry-run   # Preview installation
bash scripts/install.sh --global    # Install globally for all tools
bash scripts/install.sh --project   # Install into current project
```

## Skill Format Specification

Skills are Markdown files with YAML frontmatter. This is the **canonical format** shared by OpenCode, Claude Code, and `.agents/` conventions.

### SKILL.md Structure

```markdown
---
name: skill-name
description: "One-line description. Include trigger keywords for AI agent activation."
---

# Skill Title

Skill content in Markdown. This is injected as context when the skill is activated.

## References

Reference files in `references/` contain extended documentation the AI loads on-demand.
```

### Frontmatter Rules

| Field         | Required | Constraints                                                    |
|---------------|----------|----------------------------------------------------------------|
| `name`        | Yes      | 1–64 chars, lowercase, alphanumeric + hyphens, no leading/trailing/consecutive hyphens |
| `description` | Yes      | 1–1024 chars, include trigger keywords for agent activation    |

### Reference Files

- Stored in `references/` subdirectory alongside `SKILL.md`
- Pure Markdown — no frontmatter needed
- Loaded on-demand by the AI agent when the skill is active
- Name files descriptively: `eloquent-orm.md`, `layout-patterns.md`

## Registry Format (`skills/index.json`)

OpenCode discovers skills via URL-based registry. The `index.json` follows this exact schema:

```json
{
    "skills": [
        {
            "name": "skill-name",
            "description": "Skill description",
            "files": [
                "SKILL.md",
                "references/example.md"
            ]
        }
    ]
}
```

**How it works**: OpenCode fetches `<base-url>/index.json`, then downloads each file from `<base-url>/<skill-name>/<file>`. Files are cached locally after first download.

**User configuration** (in `opencode.json`):
```json
{
    "skills": {
        "urls": ["https://fluttersdk.github.io/ai/"]
    }
}
```

## Multi-Tool Configuration Formats

### OpenCode
- **Skills**: URL-based via `skills.urls` in `opencode.json` → serves `index.json`
- **MCP**: `opencode.json` → `"mcp"` key with `{ "type": "local", "command": [...] }`
- **Commands**: `opencode.json` → `"command"` key with `{ "template": "...", "agent": "build" }`

### Claude Code
- **Plugin**: This repo IS a Claude Code plugin — `.claude-plugin/plugin.json` at root
- **Skills**: `skills/<name>/SKILL.md` — namespaced as `/fluttersdk:<skill-name>`
- **MCP**: `.mcp.json` → `"mcpServers"` key
- **Commands**: `.claude/commands/<name>.md` (filename = command name)
- **Instructions**: `CLAUDE.md` at project root
- **Marketplace**: `.claude-plugin/marketplace.json` for plugin distribution

### Cursor
- **Rules**: `.cursor/rules/<name>.mdc` — Markdown with YAML frontmatter (`description`, `globs`, `alwaysApply`)
- **MCP**: `.cursor/mcp.json` → `"mcpServers"` key

### Gemini CLI
- **Instructions**: `GEMINI.md` at project root
- **Commands**: `.gemini/commands/<name>.toml`
- **MCP**: `~/.gemini/settings.json` → `"mcpServers"` key

### VS Code Copilot
- **Instructions**: `.github/copilot-instructions.md`
- **MCP**: `.vscode/mcp.json` → `"servers"` key

## MCP Server Structure

MCP servers live in `mcps/<server-name>/` and follow the Model Context Protocol specification (JSON-RPC 2.0 over stdio).

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const server = new McpServer({ name: "fluttersdk", version: "1.0.0" });

server.tool("tool_name", { param: z.string() }, async ({ param }) => {
    return { content: [{ type: "text", text: "result" }] };
});

const transport = new StdioServerTransport();
await server.connect(transport);
```

- Publish to npm with `bin` field for `npx @fluttersdk/mcp` usage
- Default transport: stdio (required by OpenCode, Claude Code, Cursor)
- Input schemas use Zod for type-safe validation

## How to Add a New Skill

1. Create directory: `skills/<skill-name>/`
2. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
3. Add reference files in `skills/<skill-name>/references/` if needed
4. Update `skills/index.json` — add entry with `name`, `description`, and `files` array listing every file
5. **Every file must be listed** in `index.json` `files` array — OpenCode only downloads listed files
6. Commit and push to `main` — GitHub Actions deploys to Pages automatically

### Checklist When Adding/Updating Skills

After any skill change, verify **all** of the following are in sync:

- [ ] `skills/<name>/SKILL.md` exists with valid frontmatter (`name`, `description`)
- [ ] All reference files listed in `skills/index.json` `files` array
- [ ] `skills/index.json` `description` matches SKILL.md frontmatter `description`
- [ ] `.claude-plugin/marketplace.json` `version` bumped if skills changed materially
- [ ] `.claude-plugin/plugin.json` `version` bumped to match marketplace version

**Forgetting `index.json` = OpenCode users won't get the file.**
**Forgetting version bump = Claude Code users won't get the update.**

## Code Style

This repository contains mostly Markdown (skills) and TypeScript (MCP servers). Follow these conventions:

### Markdown (Skills)
- UTF-8 encoding, LF line endings
- No trailing whitespace
- Use ATX headers (`#`, `##`, `###`) — not Setext
- Code blocks with language identifier (` ```dart `, ` ```typescript `)
- Tables for structured reference data
- Numbered step comments for multi-phase explanations

### TypeScript (MCP Servers)
- 4 spaces indentation, 120-char max line width
- Trailing commas on multi-line constructs
- Explicit types on all public APIs
- `const` over `let` — never `var`
- No `any` — use `unknown` + type guards
- ESLint + Prettier must pass with zero warnings

### JSON
- 4 spaces indentation
- Trailing newline
- Keys in lowercase with hyphens for skill names, camelCase for config keys

## GitHub Pages Deployment

The `skills/` directory is deployed to GitHub Pages via `.github/workflows/deploy-registry.yml`:

- Triggers on push to `main` when `skills/**` changes
- Deploys `skills/` as the Pages root
- `.nojekyll` file prevents Jekyll from processing Markdown files
- Result: `https://fluttersdk.github.io/ai/index.json` serves the skill manifest

## Anti-Patterns

| Forbidden                              | Do Instead                                    |
|----------------------------------------|-----------------------------------------------|
| Inline arrays on single line           | Multi-line with trailing commas               |
| Missing `description` in SKILL.md      | Always include trigger keywords               |
| Unlisted files in skill directory       | Every file must appear in `index.json` `files` |
| MCP tools without Zod schemas          | Always define input schema with Zod           |
| Hardcoded paths in install script      | Use `$HOME`, `$XDG_CONFIG_HOME` detection     |
| Skill names with uppercase or spaces   | Lowercase, hyphen-separated: `wind-ui`        |
| Committing without updating index.json | Always sync index.json with actual files      |
| Changing skills without bumping version | Bump version in both `plugin.json` AND `marketplace.json` |
| Putting skills inside `.claude-plugin/` | Skills go at plugin root (`skills/`), NOT inside `.claude-plugin/` |

## Claude Code Plugin System

This repository doubles as a **Claude Code plugin**. The `.claude-plugin/plugin.json` manifest at the root makes the entire repo installable via:

```bash
# From GitHub
claude plugin install --plugin-dir ./path/to/fluttersdk-ai

# Or via marketplace
/plugin install fluttersdk@fluttersdk-marketplace
```

### Plugin Manifest (`.claude-plugin/plugin.json`)

```json
{
    "name": "fluttersdk",
    "description": "FlutterSDK AI skills — Wind UI, Magic Framework, and more",
    "version": "1.0.0",
    "author": {
        "name": "Anilcan Cakir",
        "email": "anilcan.cakir@gmail.com"
    },
    "repository": "https://github.com/fluttersdk/ai",
    "license": "MIT"
}
```

**Key rules:**
- `name` field becomes the skill namespace → `/fluttersdk:wind-ui`, `/fluttersdk:magic-framework`
- Skills directory must be at plugin root (not inside `.claude-plugin/`)
- Only `plugin.json` goes inside `.claude-plugin/`
- All other directories (`skills/`, `commands/`, `.mcp.json`) live at the plugin root

### Marketplace Distribution (`.claude-plugin/marketplace.json`)

To distribute this repo as a marketplace catalog:

```json
{
    "$schema": "https://anthropic.com/claude-code/marketplace.schema.json",
    "name": "fluttersdk-marketplace",
    "version": "1.0.0",
    "description": "FlutterSDK community AI skills for Flutter development",
    "owner": {
        "name": "Anilcan Cakir",
        "email": "anilcan.cakir@gmail.com"
    },
    "plugins": [
        {
            "name": "fluttersdk",
            "source": "./",
            "description": "FlutterSDK AI skills — Wind UI, Magic Framework, and more",
            "version": "1.0.0",
            "category": "development"
        }
    ]
}
```

**Users add the marketplace:**
```bash
/plugin marketplace add fluttersdk/ai
/plugin install fluttersdk@fluttersdk-marketplace
```

### Plugin vs Standalone Skills

| Feature              | Standalone (`.claude/skills/`) | Plugin (`skills/`)              |
|----------------------|--------------------------------|---------------------------------|
| Skill invocation     | `/wind-ui`                     | `/fluttersdk:wind-ui`           |
| Scope                | Single project                 | Shareable, versioned            |
| Updates              | Manual copy                    | `/plugin marketplace update`    |
| Namespace conflicts  | Possible                       | Prevented by plugin prefix      |
