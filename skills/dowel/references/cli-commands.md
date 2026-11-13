# CLI commands (the 12 not in the MCP allowlist)

Of the 22 builtin commands in `dowel`, only 10 surface as
MCP tools (the `_safeDowelCommandNames` allowlist in
`lib/src/mcp/mcp_server.dart`). The other
12 are CLI-only. This file documents each: flag set, defaults, output
shapes, exit codes, and the Bash form the agent should call.

The allowlist excludes a command for one of five reasons:

| Reason | Commands |
|---|---|
| Mutates source on disk (agent's file tools own this) | `make:command`, `make:fast-cli`, `make:plugin` |
| Codegen barrel mutation | `commands:refresh`, `plugins:refresh` |
| Needs TTY (interactive prompts) | `plugin:install`, `plugin:uninstall`, `help` |
| Recurses into the MCP server | `mcp:serve` |
| One-time meta config | `install`, `mcp:install`, `mcp:uninstall` |

## Contents

- [Picking the Bash form](#picking-the-bash-form)
- [help](#help)
- [install](#install)
- [make:command](#makecommand)
- [make:fast-cli](#makefast-cli)
- [make:plugin](#makeplugin)
- [commands:refresh](#commandsrefresh)
- [plugins:refresh](#pluginsrefresh)
- [plugin:install](#plugininstall)
- [plugin:uninstall](#pluginuninstall)
- [mcp:serve](#mcpserve)
- [mcp:install](#mcpinstall)
- [Reading the 22-command surface from `dowel_list`](#reading-the-22-command-surface-from-dowel_list)

## Picking the Bash form

```
USE: ./bin/dowel <cmd>
WHEN: inside a consumer with `./bin/dowel` present (the canonical scaffold after `install`).
WHY: about 100 ms warm startup (native AOT).

USE: dart run :dispatcher <cmd>
WHEN: ./bin/dowel is unavailable (Windows, fresh clone, broken AOT cache).
WHY: ~3s startup; runs bin/dispatcher.dart directly so plugin commands are loaded.

USE: dart run dowel <cmd>
WHEN: before `install` has run, or to debug the dowel substrate itself.
WHY: ~3s startup; delegates to bin/dispatcher.dart when the project has one (plugins load), otherwise runs the builtins only.
```

`./bin/dowel` rebuilds the AOT bundle (~5s, `dart build cli`) on staleness
(see `${CLAUDE_SKILL_DIR}/references/state-and-recovery.md` § "AOT
bundle staleness gate").

## help

- **Signature**: `help [command]`
- **Group**: introspection
- **Boot**: `none`
- **Allowlisted**: no (interactive)

Show detailed help for a single command. The MCP allowlist excludes this
because `dowel_list` already enumerates commands and the agent's
preferred path is to read source files for flag details.

```bash
./bin/dowel help start
./bin/dowel help plugin:install
```

Exit 0 on success, 1 if the command name is unknown.

## install

- **Signature**: `install [--force]`
- **Group**: scaffolding
- **Boot**: `none`
- **Allowlisted**: no (one-time setup)

Bootstrap the consumer scaffold:

```bash
./bin/dowel install                # idempotent; skips existing files
./bin/dowel install --force        # rewrite existing files
```

Files produced (atomic write via `.tmp` + rename):

| Path | Purpose |
|---|---|
| `bin/dispatcher.dart` | Consumer entry calling `runDowel(args, baseProviders: [...], delegateToConsumer: false)`. Loads `lib/app/_plugins.g.dart`. |
| `lib/app/_plugins.g.dart` | Generated plugin provider barrel; empty `autoDiscoveredProviders()` thunk until `plugin:install` populates `.dowel/plugins.json`. |
| `lib/app/commands/_index.g.dart` | Generated command index for consumer-authored commands; empty until `make:command`. |

Pubspec mutation: adds `dowel: any` (pub.dev consumers, so the
next `pub get` pulls the published package) or `dowel: { path: ... }`
(monorepo `path:` auto-detected via `.dart_tool/package_config.json` rootUri).
Re-running is idempotent unless `--force`.

Auto-chains to `make:fast-cli` so `./bin/dowel` is compiled and ready
after `install` returns.

**Output (success)**:

```
✓ Scaffolded bin/dispatcher.dart
✓ Scaffolded lib/app/_plugins.g.dart
✓ Scaffolded lib/app/commands/_index.g.dart
✓ Injected dowel dep
dowel: built in 5s
```

Exit 0 on success, 1 on pubspec parse failure or `pubspec name` missing.

## make:command

- **Signature**: `make:command <Name>`
- **Group**: scaffolding
- **Boot**: `none`
- **Allowlisted**: no (codegen + file write)

Scaffold a `DowelCommand` subclass in the consumer (or plugin) at
`lib/app/commands/<snake_name>_command.dart` (or
`lib/src/commands/...` inside a plugin; auto-detected by checking
`pubspec.yaml`'s package name vs the closest parent).

```bash
./bin/dowel make:command Greet
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

Compile the dispatcher to a native AOT binary and write the `./bin/dowel`
wrapper script. Runs `dart build cli -t bin/dispatcher.dart -o
.dowel/cli-bundle`, writes `.dowel/build.stamp` (atomic), patches
`.gitignore` to exclude `.dowel/`.

```bash
./bin/dowel make:fast-cli              # build if stale
./bin/dowel make:fast-cli --force      # rebuild even when cache is fresh
```

**Output**:

```
dowel: built in 5s
```

Exit 0 on success, 1 if `dart build cli` fails.

## make:plugin

- **Signature**: `make:plugin <name> [--path=<dir>] [--target=<dir>]`
- **Group**: scaffolding
- **Boot**: `none`
- **Allowlisted**: no (complex codegen + subprocess)

Scaffold a dowel plugin skeleton at `packages/<name>/` (or `<path>`
if passed). Spawns `flutter create --template=package`, renders 8+ stub
files (provider, install command, install.yaml, README), detects parent
Flutter app workspace, enrols the new package in `pubspec.yaml`
`workspace:` if present.

```bash
./bin/dowel make:plugin awesome_plugin                   # generic plugin
./bin/dowel make:plugin awesome_plugin --magic           # adds install.yaml + Magic ServiceProvider
./bin/dowel make:plugin awesome_plugin --path=plugins    # alt location
```

**Output (success)**:

```
✓ flutter create --template=package
✓ Scaffolded awesome_plugin (8 files)
✓ Enrolled in parent pubspec workspace
Next: cd packages/awesome_plugin && dart run dowel make:command MyAction
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
./bin/dowel commands:refresh
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

Read `.dowel/plugins.json`, regenerate `lib/app/_plugins.g.dart` with
the registered providers. Atomic (`.tmp` + rename). Auto-called by
`plugin:install` and `plugin:uninstall`; manual invocation only when
hand-editing `.dowel/plugins.json`.

```bash
./bin/dowel plugins:refresh
```

**Output**:

```
Refreshed: 2 plugin(s) registered → lib/app/_plugins.g.dart
  - tapir → TapirDowelProvider
  - crumbs → CrumbsDowelProvider
```

Exit 0 on success, 1 if `lib/app/` is missing (run `install` first), or
on provider class-name collision.

**Side effect**: invalidates `.dowel/cli-bundle/` AOT cache and
`.dowel/build.stamp`, so the next `./bin/dowel` invocation rebuilds
against the freshly-regenerated barrel.

## plugin:install

- **Signature**: `plugin:install <name> [--dry-run] [--force] [--non-interactive] [--no-bootstrap] [--use-yaml-only] [--bootstrap-command=<cmd>]`
- **Group**: plugin management
- **Boot**: `none`
- **Allowlisted**: no (interactive prompts for destructive ops)

Install a plugin. Dispatches in two routing modes
(`lib/src/commands/plugin_install_command.dart`):

1. **Manifest flow** (preferred): plugin ships `install.yaml` at package
   root. Parse, walk `ManifestInstaller`, commit atomically, record at
   `.dowel/installed/<plugin>.json`, register in `.dowel/plugins.json`,
   regen `lib/app/_plugins.g.dart`. When the manifest declares a
   `bootstrap_command`, it AUTO-RUNS after registration as a fresh dispatcher
   subprocess (`./bin/dowel <cmd> --non-interactive`, or `dart run
   :dispatcher <cmd> --non-interactive` when no `bin/dowel`). `--no-bootstrap`
   skips the auto-run (falls back to a hint); `--bootstrap-command=<cmd>`
   overrides the manifest value.
2. **Direct registration**: no manifest, but `lib/app/_plugins.g.dart`
   exists (scaffold from `install`). Write directly to `plugins.json` +
   refresh. Without the scaffold the command exits `1` and asks for
   `dowel install` first.

```bash
./bin/dowel plugin:install tapir --dry-run    # preview the operations without writing
./bin/dowel plugin:install tapir              # commit
./bin/dowel plugin:install tapir --force      # skip destructive-op confirmation prompts
./bin/dowel plugin:install custom --use-yaml-only       # fail when no install.yaml present
```

`--dry-run` is the agent's safest pre-action: it returns the YAML-like
plan WITHOUT writing anything, so the agent can audit and confirm.

**Output (dry-run)**:

```yaml
plan:
  - create: lib/config/tapir.dart
  - inject_import: package:tapir/tapir.dart -> lib/main.dart
  - inject_provider: TapirDowelProvider -> lib/config/app.dart
  - merge_json: assets/config.json
```

**Output (commit)**:

```
Installed: tapir
Record: .dowel/installed/tapir.json
Refreshed: 2 plugin(s) registered → lib/app/_plugins.g.dart
```

Exit 0 on success, 1 on manifest validation, 1 if the user aborts a
destructive-op prompt (unless `--force`).

## plugin:uninstall

- **Signature**: `plugin:uninstall <name> [--dry-run] [--force]`
- **Group**: plugin management
- **Boot**: `none`
- **Allowlisted**: no (interactive prompts)

Reverse a plugin install. Reads `.dowel/installed/<plugin>.json`,
inverts each recorded `InstallOperation`, applies atomically.

```bash
./bin/dowel plugin:uninstall tapir --dry-run   # preview reverse ops
./bin/dowel plugin:uninstall tapir             # commit reverse
```

**V1 reversibility**:

- `WriteFile` / `DeleteFile` / `CopyFile`: fully reversed.
- `InjectImport`, `InjectAfterPattern`, `InjectAndroidPermission`, etc.:
  logged as `[skipped]` (V1 limitation; reverse pending anchor-bracketed
  markers in V1.1).

The agent must follow up with manual cleanup of injection sites
(`lib/config/app.dart`, platform manifests) for skipped ops.

**A pattern injection that matches nothing is an install failure**, not a
silent skip: `InjectBeforePattern` and `InjectAfterPattern` return `Error`
naming the target file when their pattern finds no match. The usual cause is a
host file written in a shape the plugin's pattern was not built for. Fix the
host file or the plugin's pattern; re-running changes nothing. An idempotent
skip, where the injected code is already present, still counts as applied.

An append-to-a-list pattern carries an optional `fallbackPattern` anchored on
the list's opening bracket, so an EMPTY `'providers': []` or
`configFactories: []` still takes the injection rather than failing the
install. Both composite injections (`injectProvider`, `injectConfigFactory`)
match from their list's own key forward, which is what keeps the insertion
point out of any other list in the same file.

**Output**:

```
Uninstalled: tapir
  ✓ deleted lib/config/tapir.dart
  [skipped] InjectImport package:tapir/tapir.dart -> lib/main.dart
  [skipped] InjectProvider TapirDowelProvider -> lib/config/app.dart
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
    "dowel": {
      "command": "./bin/dowel",
      "args": ["mcp:serve"]
    }
  }
}
```

The agent SHOULD NOT call `mcp:serve` directly; the MCP client (Claude
Code, Cursor) spawns it automatically based on `.mcp.json`.

Filter precedence (3-layer Cargo-style):

1. `.dowel/mcp.json` file (lowest precedence)
2. `DOWEL_MCP_PACKAGES_ALLOW` / `_DENY` / `DOWEL_MCP_TOOLS_ALLOW` /
   `_DENY` env vars (CSV)
3. CLI flags (highest precedence): `--include-package`,
   `--exclude-package`, `--include-tool`, `--exclude-tool`

Allow lists: CLI > env > file (first non-null wins). Deny lists: union
across all three (deny anywhere wins everywhere).

**Diagnostic stderr line on boot** (visible when the MCP client logs the
server subprocess):

```
[dowel_mcp] initialized with 45 tools (0 filtered; 40 plugin + 5 substrate)
```

(The exact count varies by allowlist and filter; read the actual
stderr line printed at boot, the literal numbers shift with each
plugin install.)

## mcp:install

- **Signature**: `mcp:install [--force]`
- **Group**: MCP
- **Boot**: `none`
- **Allowlisted**: no (meta-config edit)

Write the `dowel` entry to `.mcp.json` at the project root.
Idempotent: skips when the entry exists with the correct shape, rewrites
when stale (e.g. pre-Bug-B args), refuses to overwrite a hand-edited
entry without `--force`.

```bash
./bin/dowel mcp:install                # idempotent
./bin/dowel mcp:install --force        # rewrite existing entry
```

The entry produced:

```json
{
  "mcpServers": {
    "dowel": {
      "command": "./bin/dowel",
      "args": ["mcp:serve"]
    }
  }
}
```

(On Windows, falls back to `dart run dowel mcp:serve` because
`./bin/dowel` is a POSIX shell script.)

**Output**:

```
✓ Registered dowel MCP server in .mcp.json
Reconnect Claude Code (`/mcp reconnect dowel`) to pick up the new entry.
```

Exit 0 on success, 1 on `.mcp.json` parse error or refusal to overwrite
without `--force`.

## Reading the 22-command surface from `dowel_list`

Use `dowel_list` (MCP) or `./bin/dowel list` (CLI) to see the live
catalogue. The 12 CLI-only commands appear under these namespaces:

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
installed (`tapir`, `crumbs`, third-party
plugins); the exact total varies by installed set and is reported in
the `Available commands (N):` header at the top of `list` output.
