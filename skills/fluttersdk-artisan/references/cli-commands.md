# CLI commands (the 11 not in the MCP allowlist)

Of the 21 builtin commands in `fluttersdk_artisan`, only 10 surface as
MCP tools (allowlist at `lib/src/mcp/mcp_server.dart:871-882`). The other
11 are CLI-only. This file documents each: flag set, defaults, output
shapes, exit codes, and the Bash form the agent should call.

The allowlist excludes a command for one of five reasons:

| Reason | Commands |
|---|---|
| Mutates source on disk (agent's file tools own this) | `make:command`, `make:fast-cli`, `make:plugin` |
| Codegen barrel mutation | `commands:refresh`, `plugins:refresh` |
| Needs TTY (interactive prompts) | `plugin:install`, `plugin:uninstall`, `help` |
| Recurses into the MCP server | `mcp:serve` |
| One-time meta config | `install`, `mcp:install` |

## Picking the Bash form

```
USE: ./bin/fsa <cmd>
WHEN: inside a consumer with `./bin/fsa` present (the canonical scaffold after `install`).
WHY: ~110ms warm startup (native AOT).

USE: dart run artisan <cmd>
WHEN: ./bin/fsa is unavailable (Windows, fresh clone, broken AOT cache).
WHY: ~3s startup; runs through bin/dispatcher.dart so plugin commands are loaded.

USE: dart run fluttersdk_artisan <cmd>
WHEN: debugging the artisan substrate itself, or before `install` has run.
WHY: ~3s startup; substrate-only, plugin providers NOT loaded.
```

`./bin/fsa` rebuilds the AOT bundle (~5s, `dart build cli`) on staleness
(see `${CLAUDE_SKILL_DIR}/references/state-and-recovery.md` § "AOT
bundle staleness gate").

## help

- **Signature**: `help [command]`
- **Group**: introspection
- **Boot**: `none`
- **Allowlisted**: no (interactive)

Show detailed help for a single command. The MCP allowlist excludes this
because `artisan_list` already enumerates commands and the agent's
preferred path is to read source files for flag details.

```bash
./bin/fsa help start
./bin/fsa help plugin:install
```

Exit 0 on success, 1 if the command name is unknown.

## install

- **Signature**: `install [--force]`
- **Group**: scaffolding
- **Boot**: `none`
- **Allowlisted**: no (one-time setup)

Bootstrap the consumer scaffold:

```bash
./bin/fsa install                # idempotent; skips existing files
./bin/fsa install --force        # rewrite existing files
```

Files produced (atomic write via `.tmp` + rename):

| Path | Purpose |
|---|---|
| `bin/dispatcher.dart` | Consumer entry calling `runArtisan(args, baseProviders: [...], delegateToConsumer: false)`. Loads `lib/app/_plugins.g.dart`. |
| `lib/app/_plugins.g.dart` | Generated plugin provider barrel; empty `autoDiscoveredProviders()` thunk until `plugin:install` populates `.artisan/plugins.json`. |
| `lib/app/commands/_index.g.dart` | Generated command index for consumer-authored commands; empty until `make:command`. |

Pubspec mutation: adds `fluttersdk_artisan: ^0.0.6` (pub.dev consumers)
or `fluttersdk_artisan: { path: ... }` (monorepo `path:` auto-detected
via `.dart_tool/package_config.json` rootUri). Re-running is idempotent
unless `--force`.

Auto-chains to `make:fast-cli` so `./bin/fsa` is compiled and ready
after `install` returns.

**Output (success)**:

```
✓ Scaffolded bin/dispatcher.dart
✓ Scaffolded lib/app/_plugins.g.dart
✓ Scaffolded lib/app/commands/_index.g.dart
✓ Injected fluttersdk_artisan dep
fsa: built in 5s
```

Exit 0 on success, 1 on pubspec parse failure or `pubspec name` missing.

## make:command

- **Signature**: `make:command <Name>`
- **Group**: scaffolding
- **Boot**: `none`
- **Allowlisted**: no (codegen + file write)

Scaffold an `ArtisanCommand` subclass in the consumer (or plugin) at
`lib/app/commands/<snake_name>_command.dart` (or
`lib/src/commands/...` inside a plugin; auto-detected by checking
`pubspec.yaml`'s package name vs the closest parent).

```bash
./bin/fsa make:command Greet
```

After write, automatically calls `commands:refresh` to regenerate
`lib/app/commands/_index.g.dart`.

**Output**:

```
Generated: lib/app/commands/greet_command.dart
Refreshed: 6 command(s) registered → lib/app/commands/_index.g.dart
```

Exit 0 on success, 1 on name validation (must be PascalCase, no
reserved Dart keyword).

## make:fast-cli

- **Signature**: `make:fast-cli [--force]`
- **Group**: scaffolding
- **Boot**: `none`
- **Allowlisted**: no (AOT compile + file write)

Compile the dispatcher to a native AOT binary and write the `./bin/fsa`
wrapper script. Runs `dart build cli -t bin/dispatcher.dart -o
.artisan/cli-bundle`, writes `.artisan/build.stamp` (atomic), patches
`.gitignore` to exclude `.artisan/`.

```bash
./bin/fsa make:fast-cli              # build if stale
./bin/fsa make:fast-cli --force      # rebuild even when cache is fresh
```

**Output**:

```
fsa: built in 5s
```

Exit 0 on success, 1 if `dart build cli` fails.

## make:plugin

- **Signature**: `make:plugin <name> [--path=<dir>] [--target=<dir>]`
- **Group**: scaffolding
- **Boot**: `none`
- **Allowlisted**: no (complex codegen + subprocess)

Scaffold an artisan plugin skeleton at `packages/<name>/` (or `<path>`
if passed). Spawns `flutter create --template=package`, renders 8+ stub
files (provider, install command, install.yaml, README), detects parent
Flutter app workspace, enrols the new package in `pubspec.yaml`
`workspace:` if present.

```bash
./bin/fsa make:plugin awesome_plugin                   # generic plugin
./bin/fsa make:plugin awesome_plugin --magic           # adds install.yaml + Magic ServiceProvider
./bin/fsa make:plugin awesome_plugin --path=plugins    # alt location
```

**Output (success)**:

```
✓ flutter create --template=package
✓ Scaffolded awesome_plugin (8 files)
✓ Enrolled in parent pubspec workspace
Next: cd packages/awesome_plugin && dart run artisan make:command MyAction
```

Exit 0 on success, 1 on validation (name must match
`^[a-z_][a-z0-9_]*$`), 1 on `flutter create` failure.

## commands:refresh

- **Signature**: `commands:refresh`
- **Group**: codegen
- **Boot**: `none`
- **Allowlisted**: no (codegen barrel mutation)

Scan `lib/app/commands/*.dart`, regenerate `lib/app/commands/_index.g.dart`
with the discovered commands. Atomic (`.tmp` + rename). Auto-called by
`make:command`; manual invocation only when hand-editing command files.

```bash
./bin/fsa commands:refresh
```

**Output**:

```
Refreshed: 5 command(s) registered → lib/app/commands/_index.g.dart
```

Exit 0 on success.

## plugins:refresh

- **Signature**: `plugins:refresh`
- **Group**: codegen
- **Boot**: `none`
- **Allowlisted**: no (codegen barrel mutation)

Read `.artisan/plugins.json`, regenerate `lib/app/_plugins.g.dart` with
the registered providers. Atomic (`.tmp` + rename). Auto-called by
`plugin:install` and `plugin:uninstall`; manual invocation only when
hand-editing `.artisan/plugins.json`.

```bash
./bin/fsa plugins:refresh
```

**Output**:

```
Refreshed: 2 plugin(s) registered → lib/app/_plugins.g.dart
  - fluttersdk_dusk → FluttersdkDuskArtisanProvider
  - fluttersdk_telescope → FluttersdkTelescopeArtisanProvider
```

Exit 0 on success, 1 if `lib/app/` is missing (run `install` first), or
on provider class-name collision.

**Side effect**: invalidates `.artisan/cli-bundle/` AOT cache and
`.artisan/build.stamp`, so the next `./bin/fsa` invocation rebuilds
against the freshly-regenerated barrel.

## plugin:install

- **Signature**: `plugin:install <name> [--dry-run] [--force] [--use-yaml-only] [--provider=<C>] [--bootstrap-command=<cmd>]`
- **Group**: plugin management
- **Boot**: `none`
- **Allowlisted**: no (interactive prompts for destructive ops)

Install a plugin. Dispatches in three routing modes
(`lib/src/commands/plugin_install_command.dart:130-181`):

1. **Manifest flow** (preferred): plugin ships `install.yaml` at package
   root. Parse, walk `ManifestInstaller`, commit atomically, record at
   `.artisan/installed/<plugin>.json`, register in `.artisan/plugins.json`,
   regen `lib/app/_plugins.g.dart`.
2. **Magic-free canonical fast path**: no manifest, but
   `lib/app/_plugins.g.dart` exists (canonical scaffold from `install`).
   Skip legacy injection; write directly to `plugins.json` + refresh.
3. **Legacy injection fallback**: no manifest, no canonical scaffold.
   Inject `import 'package:<name>/cli.dart';` plus
   `registry.registerProvider(...)` into `bin/dispatcher.dart`.

```bash
./bin/fsa plugin:install fluttersdk_dusk --dry-run    # preview the operations without writing
./bin/fsa plugin:install fluttersdk_dusk              # commit
./bin/fsa plugin:install fluttersdk_dusk --force      # skip destructive-op confirmation prompts
./bin/fsa plugin:install custom --use-yaml-only       # fail when no install.yaml present
```

`--dry-run` is the agent's safest pre-action: it returns the YAML-like
plan WITHOUT writing anything, so the agent can audit and confirm.

**Output (dry-run)**:

```yaml
plan:
  - create: lib/config/dusk.dart
  - inject_import: package:fluttersdk_dusk/dusk.dart -> lib/main.dart
  - inject_provider: DuskArtisanProvider -> lib/config/app.dart
  - merge_json: assets/config.json
```

**Output (commit)**:

```
Installed: fluttersdk_dusk
Record: .artisan/installed/fluttersdk_dusk.json
Refreshed: 2 plugin(s) registered → lib/app/_plugins.g.dart
```

Exit 0 on success, 1 on manifest validation, 1 if the user aborts a
destructive-op prompt (unless `--force`).

## plugin:uninstall

- **Signature**: `plugin:uninstall <name> [--dry-run] [--force]`
- **Group**: plugin management
- **Boot**: `none`
- **Allowlisted**: no (interactive prompts)

Reverse a plugin install. Reads `.artisan/installed/<plugin>.json`,
inverts each recorded `InstallOperation`, applies atomically.

```bash
./bin/fsa plugin:uninstall fluttersdk_dusk --dry-run   # preview reverse ops
./bin/fsa plugin:uninstall fluttersdk_dusk             # commit reverse
```

**V1 reversibility**:

- `WriteFile` / `DeleteFile` / `CopyFile`: fully reversed.
- `InjectImport`, `InjectAfterPattern`, `InjectAndroidPermission`, etc.:
  logged as `[skipped]` (V1 limitation; reverse pending anchor-bracketed
  markers in V1.1).

The agent must follow up with manual cleanup of injection sites
(`lib/config/app.dart`, platform manifests) for skipped ops.

**Output**:

```
Uninstalled: fluttersdk_dusk
  ✓ deleted lib/config/dusk.dart
  [skipped] InjectImport package:fluttersdk_dusk/dusk.dart -> lib/main.dart
  [skipped] InjectProvider DuskArtisanProvider -> lib/config/app.dart
Refreshed: 1 plugin(s) registered → lib/app/_plugins.g.dart
```

Exit 0 on success, 1 if install record not found, 1 if the user aborts
(unless `--force`).

## mcp:serve

- **Signature**: `mcp:serve [--include-package=<csv>] [--exclude-package=<csv>] [--include-tool=<csv>] [--exclude-tool=<csv>]`
- **Group**: MCP
- **Boot**: `none` (no VM Service; the server itself manages its own
  lazy-reconnect for connected tools)
- **Allowlisted**: no (recurses into the MCP server itself)

Boot the stdio JSON-RPC MCP server. Reads from stdin, writes JSON-RPC
to stdout, diagnostics to stderr. Process never exits normally
(blocks on stdin).

This command is the entry point `.mcp.json` wires:

```json
{
  "mcpServers": {
    "fluttersdk": {
      "command": "./bin/fsa",
      "args": ["mcp:serve"]
    }
  }
}
```

The agent SHOULD NOT call `mcp:serve` directly; the MCP client (Claude
Code, Cursor) spawns it automatically based on `.mcp.json`.

Filter precedence (3-layer Cargo-style):

1. `.artisan/mcp.json` file (lowest precedence)
2. `ARTISAN_MCP_PACKAGES_ALLOW` / `_DENY` / `ARTISAN_MCP_TOOLS_ALLOW` /
   `_DENY` env vars (CSV)
3. CLI flags (highest precedence): `--include-package`,
   `--exclude-package`, `--include-tool`, `--exclude-tool`

Allow lists: CLI > env > file (first non-null wins). Deny lists: union
across all three (deny anywhere wins everywhere).

**Diagnostic stderr line on boot** (visible when the MCP client logs the
server subprocess):

```
[fluttersdk_artisan_mcp] initialized with 45 tools (0 filtered; 40 plugin + 5 substrate)
```

(The exact count varies by allowlist and filter; read the actual
stderr line printed at boot, the literal numbers shift with each
plugin install.)

## mcp:install

- **Signature**: `mcp:install [--force]`
- **Group**: MCP
- **Boot**: `none`
- **Allowlisted**: no (meta-config edit)

Write the `fluttersdk` entry to `.mcp.json` at the project root.
Idempotent: skips when the entry exists with the correct shape, rewrites
when stale (e.g. pre-Bug-B args), refuses to overwrite a hand-edited
entry without `--force`.

```bash
./bin/fsa mcp:install                # idempotent
./bin/fsa mcp:install --force        # rewrite existing entry
```

The entry produced:

```json
{
  "mcpServers": {
    "fluttersdk": {
      "command": "./bin/fsa",
      "args": ["mcp:serve"]
    }
  }
}
```

(On Windows, falls back to `dart run artisan mcp:serve` because
`./bin/fsa` is a POSIX shell script.)

**Output**:

```
✓ Registered fluttersdk MCP server in .mcp.json
Reconnect Claude Code (`/mcp reconnect fluttersdk`) to pick up the new entry.
```

Exit 0 on success, 1 on `.mcp.json` parse error or refusal to overwrite
without `--force`.

## Reading the 21-command surface from `artisan_list`

Use `artisan_list` (MCP) or `./bin/fsa list` (CLI) to see the live
catalog. The 11 CLI-only commands appear under these namespaces:

- root: `help`, `install`
- `commands:`: `commands:refresh`
- `make:`: `make:command`, `make:fast-cli`, `make:plugin`
- `mcp:`: `mcp:install`, `mcp:serve`, `mcp:uninstall` (uninstall mirrors
  `mcp:install` in reverse, identical agent UX)
- `plugin:`: `plugin:install`, `plugin:uninstall`
- `plugins:`: `plugins:refresh`

The 10 MCP-allowlisted commands appear at the root: `start`, `stop`,
`status`, `logs`, `restart`, `reload`, `hot-restart`, `doctor`, `list`,
`tinker`.

Total: 21 substrate builtins. Plugin commands add to the count when
installed (`fluttersdk_dusk`, `fluttersdk_telescope`, third-party
plugins); the exact total varies by installed set and is reported in
the `Available commands (N):` header at the top of `list` output.
