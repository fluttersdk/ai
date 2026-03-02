# FlutterSDK AI

AI coding skills, MCP servers, commands, and scripts for the FlutterSDK ecosystem — distributed across **all major AI coding tools**.

| Tool | Integration |
|------|-------------|
| [OpenCode](https://github.com/opencodetool/opencode) | URL-based skill registry |
| [Claude Code](https://docs.anthropic.com/en/docs/claude-code) | Plugin + Marketplace |
| [Cursor](https://cursor.sh) | Rules (`.mdc`) |
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | Command templates (`.toml`) |
| [VS Code Copilot](https://code.visualstudio.com/) | Instructions (`.md`) |

## Available Skills

### Wind UI

Utility-first styling framework for Flutter — think Tailwind CSS, but for widgets.

```dart
WDiv(
    className: 'p-4 bg-white dark:bg-gray-900 rounded-lg shadow-md',
    child: WText(
        'Hello, Wind UI!',
        className: 'text-lg font-semibold text-gray-800 dark:text-white',
    ),
)
```

### Magic Framework

Laravel-inspired Flutter framework with IoC Container, Facades, Eloquent ORM, and GoRouter wrapper.

```dart
class UserController extends MagicController {
    Future<MagicResponse> index() async {
        final users = await User.query().where('active', true).get();

        return response.ok(users);
    }
}
```

## Quick Start

### Option 1: `npx skills` (Recommended)

The fastest way to install — works with [40+ AI coding agents](https://github.com/vercel-labs/skills) including OpenCode, Claude Code, Cursor, Gemini CLI, and more.

```bash
# Install all FlutterSDK skills to all detected agents
npx skills add fluttersdk/ai

# Install to specific agents only
npx skills add fluttersdk/ai -a opencode -a claude-code -a cursor

# Install a specific skill
npx skills add fluttersdk/ai --skill wind-ui
npx skills add fluttersdk/ai --skill magic-framework

# Install globally (available across all projects)
npx skills add fluttersdk/ai -g

# Preview available skills without installing
npx skills add fluttersdk/ai --list
```

### Option 2: Universal Installer

```bash
# Clone the repository
git clone https://github.com/fluttersdk/ai.git
cd ai

# Preview what would be installed
bash scripts/install.sh --dry-run --global

# Install globally for all detected tools
bash scripts/install.sh --global

# Or install into your current Flutter project
bash scripts/install.sh --project
```

### Option 3: Tool-Specific Setup

#### OpenCode

Add the registry URL to your `opencode.json`:

```json
{
    "skills": {
        "urls": [
            "https://fluttersdk.github.io/ai/"
        ]
    }
}
```

Skills are fetched automatically and cached locally. Use them by name — OpenCode activates them when it detects relevant trigger keywords.

#### Claude Code

Install as a plugin:

```bash
# From local clone
claude plugin install --plugin-dir ./path/to/fluttersdk-ai

# Or via marketplace
/plugin marketplace add fluttersdk/ai
/plugin install fluttersdk@fluttersdk-marketplace
```

Skills are namespaced as `/fluttersdk:wind-ui` and `/fluttersdk:magic-framework`.

#### Cursor

Copy the rule file into your project:

```bash
mkdir -p .cursor/rules
cp commands/cursor/fluttersdk.mdc .cursor/rules/
```

The rule activates automatically for all `.dart` files.

#### Gemini CLI

Copy command templates to your Gemini config:

```bash
mkdir -p ~/.gemini/commands
cp commands/gemini/*.toml ~/.gemini/commands/
```

Use with `/flutter-review` and `/flutter-test` commands.

#### VS Code Copilot

Copy the instructions file into your project:

```bash
mkdir -p .github
cp .github/copilot-instructions.md .github/
```

## Repository Structure

```
fluttersdk-ai/
├── skills/                     ← Skill definitions (GitHub Pages root)
│   ├── index.json              ← OpenCode discovery manifest
│   ├── wind-ui/                ← Wind UI skill + references
│   └── magic-framework/        ← Magic Framework skill + references
│
├── mcps/                       ← MCP server projects
│   └── fluttersdk-mcp/         ← TypeScript MCP server (@fluttersdk/mcp)
│
├── commands/                   ← Command templates per tool
│   ├── opencode/               ← OpenCode commands (JSON)
│   ├── claude/                 ← Claude Code commands (Markdown)
│   ├── cursor/                 ← Cursor rules (.mdc)
│   └── gemini/                 ← Gemini CLI commands (TOML)
│
├── scripts/
│   └── install.sh              ← Universal multi-tool installer
│
├── .claude-plugin/             ← Claude Code plugin manifest
│   ├── plugin.json
│   └── marketplace.json
│
├── .github/
│   ├── workflows/
│   │   └── deploy-registry.yml ← GitHub Pages deployment
│   └── copilot-instructions.md ← VS Code Copilot instructions
│
├── AGENTS.md                   ← AI contributor guide
├── LICENSE                     ← MIT
└── README.md                   ← This file
```

## How It Works

### Skill Registry (OpenCode)

OpenCode fetches `https://fluttersdk.github.io/ai/index.json`, which lists available skills and their files. Each skill's files are downloaded from the same base URL and cached locally.

```
index.json → lists skills with file arrays
  → wind-ui/SKILL.md, wind-ui/references/widgets.md, ...
  → magic-framework/SKILL.md, magic-framework/references/eloquent-orm.md, ...
```

### Claude Code Plugin

The `.claude-plugin/plugin.json` manifest at the repository root makes this entire repo installable as a Claude Code plugin. Skills in `skills/` are automatically discovered and namespaced under `/fluttersdk:`.

### GitHub Pages Deployment

Pushing to `main` triggers automatic deployment of the `skills/` directory to GitHub Pages via the `deploy-registry.yml` workflow. The `.nojekyll` file ensures Markdown files are served as-is.

## Contributing

### Adding a New Skill

1. Create `skills/<skill-name>/SKILL.md` with YAML frontmatter (`name`, `description`)
2. Add reference files in `skills/<skill-name>/references/`
3. Update `skills/index.json` — list every file in the `files` array
4. Bump version in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
5. Push to `main`

See [AGENTS.md](AGENTS.md) for the complete specification.

### Checklist

- [ ] `SKILL.md` has valid frontmatter (`name`, `description`)
- [ ] Every file listed in `index.json` `files` array
- [ ] `index.json` description matches `SKILL.md` frontmatter
- [ ] Version bumped in both `plugin.json` and `marketplace.json`

## License

[MIT](LICENSE) — Anilcan Cakir
