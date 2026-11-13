<p align="center">
  <img src="https://raw.githubusercontent.com/anilcancakir/ai/master/.github/ai-logo.png" width="120" alt="AI skills for Flutter logo" />
</p>

<h1 align="center">AI skills for Flutter</h1>

<p align="center">
  <strong>One registry that teaches your AI coding agent Wind UI, the Magic Framework and the dowel dev tooling.</strong><br/>
  Install once, and Claude Code, Cursor, Gemini CLI, OpenCode, Codex CLI and more write correct code on the first try.
</p>

<p align="center">
  <a href="https://github.com/anilcancakir/ai/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/ai/ci.yml?branch=master&label=CI" alt="CI"></a>
  <a href="https://github.com/anilcancakir/ai/actions/workflows/deploy-registry.yml"><img src="https://img.shields.io/github/actions/workflow/status/anilcancakir/ai/deploy-registry.yml?branch=master&label=Registry" alt="Registry"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
</p>

<p align="center">
  <a href="https://anilcancakir.github.io/ai/">Registry</a> ·
  <a href="#install">Install</a> ·
  <a href="docs/SKILLS.md">Skills</a> ·
  <a href="https://github.com/anilcancakir/ai/issues">Issues</a>
</p>

---

AI coding assistants are strong, but they do not know your frameworks: they invent widget names, guess API shapes and miss conventions. These skills give the agent structured knowledge of Wind UI's `className` system, the Laravel-inspired Magic Framework and the dowel, tapir and crumbs dev tooling.

## At a glance

| Fact | Value |
|:-----|:------|
| Registry | `https://anilcancakir.github.io/ai/` (GitHub Pages, `skills/index.json`) |
| Install | `npx skills add anilcancakir/ai` |
| Claude Code plugin | `anilcancakir@anilcancakir-marketplace` |
| Skills | `wind-ui`, `magic-framework`, `dowel`, `fluttersdk-dusk`, `fluttersdk-telescope`, plus the owned `flutter-review` |
| Subagents and commands | `anilcancakir:flutter-reviewer`, `anilcancakir:flutter-reviewer-deep`, `/anilcancakir:flutter-test` |
| Tools served | OpenCode, Claude Code, Cursor, Gemini CLI, Codex CLI, Antigravity CLI, Cline, Roo Code |
| Freshness | A source repo publishes a release, `sync.yml` mirrors its `skills/<name>/` here and bumps the registry version |
| License | MIT |

## Install

### `npx skills` (recommended)

Works with [40+ AI coding agents](https://github.com/vercel-labs/skills).

```bash
# All skills, every detected agent
npx skills add anilcancakir/ai

# One skill
npx skills add anilcancakir/ai --skill wind-ui

# Global, available in every project
npx skills add anilcancakir/ai -g
```

Each package also ships its own skill, so a single one installs straight from its repo: `npx skills add anilcancakir/magic_device`.

### Claude Code plugin

```bash
/plugin marketplace add https://raw.githubusercontent.com/anilcancakir/ai/master/.claude-plugin/marketplace.json
/plugin install anilcancakir@anilcancakir-marketplace
```

Moving from the old `fluttersdk@fluttersdk-marketplace` install: remove that marketplace (`/plugin marketplace remove fluttersdk-marketplace`) and add the new one; the plugin and marketplace names changed.

The plugin registers:

- the skills (`/anilcancakir:wind-ui`, `/anilcancakir:magic-framework`, `/anilcancakir:fluttersdk-dusk`, `/anilcancakir:fluttersdk-telescope`, `/anilcancakir:dowel`)
- `/anilcancakir:flutter-review`, a review that runs in a subagent as an independent second pair of eyes and then fixes what it finds, plus `/anilcancakir:flutter-test`
- the `anilcancakir:flutter-reviewer` and `anilcancakir:flutter-reviewer-deep` subagents, invokable with `@`
- the bundled MCP server from `.mcp.json` (HTTP transport to `mcp.anilcancakir.com`)

### Other tools

<details>
<summary><strong>OpenCode</strong></summary>

Add the registry URL to `opencode.json`; skills are fetched and cached locally.

```json
{
    "skills": {
        "urls": ["https://anilcancakir.github.io/ai/"]
    }
}
```

</details>

<details>
<summary><strong>Cursor</strong></summary>

```bash
mkdir -p .cursor/rules
cp tool-templates/cursor/wind-magic.mdc .cursor/rules/
```

The rule activates for every `.dart` file.

</details>

<details>
<summary><strong>Gemini CLI</strong></summary>

```bash
mkdir -p ~/.gemini/commands
cp tool-templates/gemini/*.toml ~/.gemini/commands/
```

Use `/flutter-review` and `/flutter-test`.

</details>

<details>
<summary><strong>Universal installer</strong></summary>

```bash
git clone https://github.com/anilcancakir/ai.git && cd ai

bash scripts/install.sh --dry-run --global      # preview
bash scripts/install.sh --global                # every detected tool
bash scripts/install.sh --global --with-mcp     # also register the MCP server
bash scripts/install.sh --project               # into the current Flutter project
```

</details>

## Skills

| Skill | Source repo | What it covers |
|:------|:------------|:---------------|
| `wind-ui` | [anilcancakir/wind_kit](https://github.com/anilcancakir/wind_kit) | W-prefix widgets, the `className` parser pipeline, `WindRecipe` variants, dark mode, responsive breakpoints |
| `magic-framework` | [anilcancakir/magic](https://github.com/anilcancakir/magic) | IoC container, 18 facades, Eloquent ORM, GoRouter routing, forms, auth, testing |
| `fluttersdk-dusk` | [anilcancakir/tapir](https://github.com/anilcancakir/tapir) | E2E driver: tools and CLI commands to snap, tap, type and screenshot a running Flutter app |
| `fluttersdk-telescope` | [anilcancakir/crumbs](https://github.com/anilcancakir/crumbs) | Runtime inspector: ring buffers for HTTP, logs, exceptions, events, gates, DB queries |
| `dowel` | [anilcancakir/dowel](https://github.com/anilcancakir/dowel) | CLI framework and stdio MCP server: start, reload, inspect and tinker a running app |

`dowel` replaced `fluttersdk-artisan` on its first sync (v1.4.85). The two remaining `fluttersdk-*` skills are renamed `tapir` and `crumbs` on the first sync after each source repo ships its renamed package; the old directory and index entry leave with it. The synced version is the `version:` field in `skills/<name>/SKILL.md`, and [`skills/index.json`](skills/index.json) is the machine-readable index. Full descriptions: [docs/SKILLS.md](docs/SKILLS.md).

## MCP server

`https://mcp.anilcancakir.com/` is the read-only docs server of anilcancakir.com: `list_packages`, `list_docs`, `search_docs` and `read_doc` over Streamable HTTP, public and without auth. The plugin registers it; client snippets for each tool are in [docs/MCP.md](docs/MCP.md). Clients that only speak stdio use the `mcp-remote` bridge:

```bash
npx -y mcp-remote https://mcp.anilcancakir.com/
```

## For AI coding agents

| Do | Because |
|:---|:--------|
| Edit a skill in its source repo, never under `skills/<name>/` | `sync.yml` rsyncs with `--delete`, so a registry-only file is gone after the next sync |
| Add a source with one entry in `registry-sources.json` | the sync rejects any source key that is not listed there |
| Keep `plugin.json`, `marketplace.json` and `marketplace.plugins[0]` on one version | the `Plugin manifest + version sync` job fails otherwise |
| Write a skill `description:` on one line | the indexer rejects folded and block scalars |
| List every file of a skill in `skills/index.json` | OpenCode downloads only listed files (the sync regenerates the entry) |
| Open pull requests against `master` | it is the default branch and the only one CI and Pages watch |

## How it works

```
source repo release  ->  repository_dispatch  ->  sync.yml  ->  skills/<name>/  ->  Pages
                                                    |
                                                    +-> skills/index.json, plugin and marketplace version bump
```

- **OpenCode** reads `anilcancakir.github.io/ai/index.json` and downloads the listed files.
- **Claude Code** installs the plugin from `.claude-plugin/`; skills under `skills/` are namespaced `/anilcancakir:`.
- **Deployment**: a push to `master` that changes `skills/` deploys Pages.

To add a skill source, see [docs/UPSTREAM-SETUP.md](docs/UPSTREAM-SETUP.md); the repo rules are in [CLAUDE.md](CLAUDE.md).

## Links

- [Registry](https://anilcancakir.github.io/ai/), [skills docs](docs/SKILLS.md), [MCP clients](docs/MCP.md), [upstream setup](docs/UPSTREAM-SETUP.md)
- [Changelog](CHANGELOG.md), [issues](https://github.com/anilcancakir/ai/issues), [security policy](SECURITY.md)

## License

MIT. See [LICENSE](LICENSE).

<p align="center">
  <sub>Built with care by <a href="https://github.com/anilcancakir">Anılcan Çakır</a></sub>
</p>
