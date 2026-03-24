<p align="center">
  <img src="https://raw.githubusercontent.com/fluttersdk/ai/main/.github/ai-logo.svg" width="120" alt="FlutterSDK AI Logo" />
</p>

<h1 align="center">FlutterSDK AI</h1>

<p align="center">
  <strong>AI coding skills for the FlutterSDK ecosystem.</strong><br/>
  Teach your AI assistant Wind UI, Magic Framework, and more — across every major coding tool.
</p>

<p align="center">
  <a href="https://github.com/fluttersdk/ai/actions"><img src="https://img.shields.io/github/actions/workflow/status/fluttersdk/ai/deploy-registry.yml?branch=main&label=Registry" alt="Registry"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
  <a href="https://github.com/fluttersdk/ai/stargazers"><img src="https://img.shields.io/github/stars/fluttersdk/ai?style=flat" alt="GitHub stars"></a>
</p>

<p align="center">
  <a href="https://fluttersdk.github.io/ai/">Registry</a> ·
  <a href="https://github.com/fluttersdk/ai/issues">Issues</a> ·
  <a href="#quick-start">Quick Start</a>
</p>

---

## Why?

AI coding assistants are powerful — but they don't know your frameworks. They hallucinate widget names, guess at API patterns, and miss conventions.

**FlutterSDK AI fixes this.** It gives your AI structured knowledge about Wind UI's className system, Magic Framework's Laravel-inspired architecture, and more — so it generates correct code on the first try.

One install, every tool:

| Tool | Integration |
|:-----|:------------|
| [OpenCode](https://github.com/opencodetool/opencode) | URL-based skill registry |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Plugin + Marketplace |
| [Cursor](https://cursor.sh) | Rules (`.mdc`) |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Command templates (`.toml`) |
| [VS Code Copilot](https://code.visualstudio.com/) | Instructions (`.md`) |

## Skills

### Wind UI

Utility-first styling for Flutter — Tailwind CSS syntax, but for widgets.

```dart
// Your AI generates this correctly — every time
WDiv(
    className: 'flex flex-col gap-6 p-6 bg-white dark:bg-gray-900 rounded-xl shadow-lg',
    children: [
        WText('Dashboard', className: 'text-2xl font-bold text-gray-900 dark:text-white'),
        WButton(
            onTap: _refresh,
            className: 'bg-blue-600 hover:bg-blue-700 text-white px-6 py-3 rounded-lg',
            child: Text('Refresh'),
        ),
    ],
)
```

20 widgets · responsive breakpoints · dark mode · state styling · server-driven UI

### Magic Framework

Laravel-inspired Flutter framework with IoC Container, Facades, Eloquent ORM, and GoRouter wrapper.

```dart
// Your AI knows the full Magic API — controllers, facades, ORM, routing
class UserController extends MagicController {
    Future<MagicResponse> index() async {
        final users = await User.query().where('active', true).get();

        return response.ok(users);
    }
}
```

Eloquent ORM · Facades · Auth · Forms & Validation · HTTP · CLI scaffolding

## Quick Start

### Option 1: `npx skills` (Recommended)

The fastest way — works with [40+ AI coding agents](https://github.com/vercel-labs/skills).

```bash
# Install all FlutterSDK skills to all detected agents
npx skills add fluttersdk/ai

# Install a specific skill
npx skills add fluttersdk/ai --skill wind-ui

# Install globally (available across all projects)
npx skills add fluttersdk/ai -g
```

### Option 2: Universal Installer

```bash
git clone https://github.com/fluttersdk/ai.git && cd ai

# Preview what would be installed
bash scripts/install.sh --dry-run --global

# Install globally for all detected tools
bash scripts/install.sh --global

# Or install into your current Flutter project
bash scripts/install.sh --project
```

### Option 3: Tool-Specific

<details>
<summary><strong>OpenCode</strong></summary>

Add the registry URL to your `opencode.json`:

```json
{
    "skills": {
        "urls": ["https://fluttersdk.github.io/ai/"]
    }
}
```

Skills are fetched automatically and cached locally.

</details>

<details>
<summary><strong>Claude Code</strong></summary>

```bash
# From local clone
claude plugin install --plugin-dir ./path/to/fluttersdk-ai

# Or via marketplace
/plugin marketplace add fluttersdk/ai
/plugin install fluttersdk@fluttersdk-marketplace
```

Skills are namespaced as `/fluttersdk:wind-ui` and `/fluttersdk:magic-framework`.

</details>

<details>
<summary><strong>Cursor</strong></summary>

```bash
mkdir -p .cursor/rules
cp commands/cursor/fluttersdk.mdc .cursor/rules/
```

Activates automatically for all `.dart` files.

</details>

<details>
<summary><strong>Gemini CLI</strong></summary>

```bash
mkdir -p ~/.gemini/commands
cp commands/gemini/*.toml ~/.gemini/commands/
```

Use with `/flutter-review` and `/flutter-test` commands.

</details>

<details>
<summary><strong>VS Code Copilot</strong></summary>

```bash
mkdir -p .github
cp .github/copilot-instructions.md .github/
```

</details>

## How It Works

```
skills/index.json              ← OpenCode fetches this from GitHub Pages
  → wind-ui/SKILL.md           ← Skill definition + className rules
  → wind-ui/references/*.md    ← On-demand widget docs, layout patterns, tokens
  → magic-framework/SKILL.md   ← Skill definition + framework laws
  → magic-framework/refs/*.md  ← Controllers, ORM, facades, routing, auth, ...
```

**OpenCode**: Fetches `fluttersdk.github.io/ai/index.json`, downloads listed skill files, caches locally.

**Claude Code**: Plugin manifest (`.claude-plugin/plugin.json`) makes the repo installable. Skills in `skills/` are auto-discovered and namespaced under `/fluttersdk:`.

**Deployment**: Push to `main` → GitHub Actions deploys `skills/` to GitHub Pages automatically.

## Contributing

### Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
2. Add reference files in `skills/<skill-name>/references/`
3. Update `skills/index.json` — list **every** file in the `files` array
4. Bump version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
5. Push to `main`

See [CLAUDE.md](CLAUDE.md) for the full specification.

> **Important**: Every file must be listed in `index.json` — OpenCode only downloads listed files. Forgetting a file means users get incomplete skills.

## License

MIT — see [LICENSE](LICENSE) for details.

---

<p align="center">
  <sub>Built with care by <a href="https://github.com/fluttersdk">FlutterSDK</a></sub><br/>
  <sub>If this saves you time, <a href="https://github.com/fluttersdk/ai">give it a star</a> — it helps others discover it.</sub>
</p>
