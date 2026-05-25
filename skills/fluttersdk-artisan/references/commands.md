# Command reference (21 builtins)

Authoritative source: `lib/src/commands/*_command.dart`. Six DSL commands declare `String get signature`; five declare `configure(ArgParser parser)` with at least one flag; ten have no flag surface. The boot mode column reflects `CommandBoot boot` getter on each class.

Invocation form throughout: `dart run artisan <cmd>` (in a consumer with `bin/dispatcher.dart`) or `dart run fluttersdk_artisan <cmd>` (direct).

## Lifecycle (7)

### `start`

`lib/src/commands/start_command.dart:26` (configure at line 38)

Spawns `flutter run -d <device>` detached via a shell wrapper, uses a POSIX FIFO for stdin (so `reload` / `hot-restart` can send keystrokes), scrapes the VM Service URI from stdout, and writes `~/.artisan/state.json` with pid + URI + device + FIFO path.

| Flag | Default | Purpose |
|------|---------|---------|
| `--device` | `chrome` | Flutter device target. `flutter devices` for the catalog. |
| `--port` | `3100` | Web port (chrome target only; ignored on desktop/mobile). |
| `--vm-service-port` | `8181` | VM Service port. |
| `--dds` | off | Enable Dart Development Service. |
| `--profile-static` | off | Build profile = static (release-like, no hot reload). |

```bash
dart run artisan start --device=chrome
dart run artisan start --device=macos
dart run artisan start --device=chrome --port=3500 --dds
```

Platform: macOS / Linux only (FIFO via `mkfifo`). Windows unsupported in V1.

### `stop`

`lib/src/commands/stop_command.dart:10` (no configure override; no flags)

SIGTERMs the flutter run pid + FIFO holder pid recorded in state.json, unlinks the FIFO, deletes state.json. Idempotent: silent no-op when state.json is absent or the PID is already gone.

### `status`

`lib/src/commands/status_command.dart:10` (no configure override; no flags)

Prints JSON of state.json plus a liveness probe (`alive: true|false` via process-exists check). Returns clean JSON even when no app is running (`{"running": false}`).

```json
{
  "running": true,
  "pid": 12345,
  "vmServiceUri": "ws://127.0.0.1:8181/AbCdE/ws",
  "device": "chrome",
  "webPort": 3100,
  "startedAt": "2026-05-19T16:42:11.123Z",
  "alive": true
}
```

### `logs`

`lib/src/commands/logs_command.dart:11` (configure at line 22)

Reads `~/.artisan/flutter-dev.log` (captured stdout/stderr from `flutter run`). With `--follow`, tails it.

| Flag | Default | Purpose |
|------|---------|---------|
| `--follow` (`-f`) | off | Tail the log in follow mode (250ms poll). |

### `restart`

`lib/src/commands/restart_command.dart:8` (no configure override; no flags)

Composes `stop` + `start`. Full process recycle. Use when hot-restart cannot apply (native plugin reload).

### `reload`

`lib/src/commands/reload_command.dart:20` (no configure override; no flags)

Sends `r\n` to the FIFO stdin recorded in state.json. Equivalent to pressing `r` in interactive `flutter run`. Hot reload: preserves Dart state, rebuilds widget tree. Device-agnostic (goes through flutter_tools, not VM Service RPC).

### `hot-restart`

`lib/src/commands/hot_restart_command.dart:20` (no configure override; no flags)

Sends `R\n` to the FIFO. Equivalent to pressing `R` in interactive `flutter run`. Drops Dart state, keeps process. Use when hot reload cannot apply the change.

## Scaffolding (3)

### `make:plugin`

`lib/src/commands/make_plugin_command.dart:78` (signature DSL at line 154)

Scaffolds a new artisan plugin under `packages/<name>/`. 8-phase pipeline: validate snake_case name, resolve target dir, `flutter create --template=package`, render generic stubs, optional magic add-ons, workspace enrollment, success banner.

Signature: `make:plugin {name} {--path=} {--target=} {--magic} {--bootstrap-command=}`

| Argument / Option | Description |
|-------------------|-------------|
| `name` | Snake_case package name. Validated against pubspec regex. |
| `--path=<dir>` | Target directory. Wins over `--target` when both set. |
| `--target=<dir>` | Alias for `--path`. |
| `--magic` | Adds Magic-aware stubs (install.yaml, ServiceProvider, install/uninstall commands). |
| `--bootstrap-command=<cmd>` | Override default `<commandPrefix>:install`. |

```bash
dart run artisan make:plugin awesome_plugin
dart run artisan make:plugin awesome_plugin --magic
dart run artisan make:plugin my_logger --path=/workspace/plugins/my_logger
```

### `make:command`

`lib/src/commands/make_command_command.dart:32` (no signature DSL; uses configure)

Context-aware. In a consumer (lib/app/ + bin/dispatcher.dart): writes to `lib/app/commands/<name>_command.dart`, refreshes the index barrel. In a plugin (`lib/src/<name>_artisan_provider.dart` at root): writes to `lib/src/commands/`, injects import + registration into the nearest provider class.

Name normalization is idempotent: `Hello` becomes `HelloCommand`, `HelloCommand` stays `HelloCommand`. The signature also strips the trailing `-command` from the kebab form, so the user invokes `hello`, not `hello-command`.

```bash
dart run artisan make:command Greet
dart run artisan make:command Admin/UserSync     # produces admin:user-sync
```

### `install`

`lib/src/commands/install_command.dart:27` (signature DSL at line 29)

Writes the canonical Magic-free consumer wrapper.

Signature: `install {--force}`

Three files produced (skipped when present unless `--force`):

| File | Purpose |
|------|---------|
| `bin/dispatcher.dart` | Consumer entry calling `runArtisan(...)` |
| `lib/app/_plugins.g.dart` | Empty plugin provider barrel |
| `lib/app/commands/_index.g.dart` | Empty command index |

Pubspec injection auto-detects monorepo path-dep via `.dart_tool/package_config.json` rootUri; falls back to `fluttersdk_artisan: ^0.0.1` (pub.dev caret) when path-dep is not resolvable.

## Plugin Management (3)

### `plugin:install`

`lib/src/commands/plugin_install_command.dart:60` (signature DSL at line 67)

Three routing modes (see SKILL.md section 4 for the dispatch logic).

Signature: `plugin:install {name} {--provider=} {--bootstrap-command=} {--use-yaml-only}` + inherited `--dry-run` and `--force` from `ArtisanInstallCommand`.

| Flag | Purpose |
|------|---------|
| `--provider=<Class>` | Override the auto-derived `<PascalCaseName>ArtisanProvider` class name. |
| `--bootstrap-command=<cmd>` | Plugin sub-command to chain after registration (e.g. `logger:install`). |
| `--use-yaml-only` | Fail with non-zero exit when no install.yaml found (instead of routing to legacy injection). |
| `--dry-run` | Preview operations; commit nothing. |
| `--force` | Bypass idempotency checks; overwrite existing files. |

```bash
dart run artisan plugin:install awesome_plugin
dart run artisan plugin:install awesome_plugin --dry-run
dart run artisan plugin:install awesome_plugin --provider=AwesomePluginCustomProvider
```

Side effect: invalidates `.artisan/cli-bundle/` and `.artisan/build.stamp` so `./bin/fsa` rebuilds on next invocation.

### `plugin:uninstall`

`lib/src/commands/plugin_uninstall_command.dart:47` (signature DSL at line 54)

Mirror of plugin:install. Requires the install record at `.artisan/installed/<name>.json` (written on successful install). V1 reverses `WriteFile` / `DeleteFile` / `CopyFile` fully; other op types skip with `[skipped]` warning.

Signature: `plugin:uninstall {name} {--dry-run}` + inherited `--force`.

```bash
dart run artisan plugin:uninstall awesome_plugin --dry-run
dart run artisan plugin:uninstall awesome_plugin
```

Side effect: invalidates `.artisan/cli-bundle/` and `.artisan/build.stamp` so `./bin/fsa` rebuilds on next invocation.

### `plugins:refresh`

`lib/src/commands/plugins_refresh_command.dart:49` (signature DSL at line 77)

Regenerates `lib/app/_plugins.g.dart` from `.artisan/plugins.json`. Atomic `.tmp` + rename. Idempotent (byte-identical output on consecutive runs). `make:command` and `plugin:install` call this internally; manual invocation only needed after hand-editing `.artisan/plugins.json`.

Side effect: invalidates `.artisan/cli-bundle/` and `.artisan/build.stamp` so `./bin/fsa` rebuilds on next invocation.

## MCP (3)

### `mcp:serve`

`lib/src/commands/mcp_serve_command.dart:32` (no signature DSL; configure at line 56)

Runs the stdio JSON-RPC MCP server. The MCP client spawns the server via `./bin/fsa mcp:serve` (or `dart run :dispatcher mcp:serve` on Windows or when `bin/fsa` is absent); the CLI form is rarely used directly.

| Flag (repeatable) | Purpose |
|-------------------|---------|
| `--include-package` | Allow tools only from named packages. |
| `--exclude-package` | Block tools from named packages. |
| `--include-tool` | Allow specific tools by name. |
| `--exclude-tool` | Block specific tools by name. |

Cargo-style precedence: CLI > env (`ARTISAN_MCP_PACKAGES_ALLOW` etc.) > `.artisan/mcp.json` file. Deny lists union across all three layers (deny anywhere wins). See `references/mcp-server.md` for filter shape.

### `mcp:install`

`lib/src/commands/mcp_install_command.dart:31` (no signature DSL; configure at line 43)

Idempotently writes the `mcpServers.fluttersdk` entry to `.mcp.json`. Preserves any existing entries from other tools.

| Flag | Default | Purpose |
|------|---------|---------|
| `--path=<file>` | `.mcp.json` | Target file path. |

Canonical entry shape (when `bin/fsa` is present on POSIX):

```json
{
  "mcpServers": {
    "fluttersdk": {
      "command": "./bin/fsa",
      "args": ["mcp:serve"],
      "cwd": "."
    }
  }
}
```

On Windows or when `bin/fsa` is absent:

```json
{
  "mcpServers": {
    "fluttersdk": {
      "command": "dart",
      "args": ["run", ":dispatcher", "mcp:serve"],
      "cwd": "."
    }
  }
}
```

### `mcp:uninstall`

`lib/src/commands/mcp_uninstall_command.dart:10` (no signature DSL; configure at line 22)

Removes the `fluttersdk` key from `.mcp.json` `mcpServers`. Preserves other entries. Idempotent.

| Flag | Default | Purpose |
|------|---------|---------|
| `--path=<file>` | `.mcp.json` | Target file path. |

## Introspection (4)

### `help`

`lib/src/commands/help_command.dart:9` (no configure override; no flags)

Prints full signature + description + boot mode + flags for a single command. Errors when the command name is not registered.

```bash
dart run artisan help plugin:install
```

### `list`

`lib/src/commands/list_command.dart:10` (empty configure override at line 26; no flags)

Catalogs every registered command grouped by namespace. Total count at the top. Used for plugin-discovery sanity checks.

### `doctor`

`lib/src/commands/doctor_command.dart:16` (no configure override; no flags)

Environment preflight: `flutter --version`, `dart --version`, default port availability. Reports each check as `OK` / `WARN` / `FAIL`. Non-zero exit when any hard check fails.

### `tinker`

`lib/src/commands/tinker_command.dart:17` (signature DSL at line 22)

Connected mode (`CommandBoot.connected`). Requires `artisan start` to have written `~/.artisan/state.json`.

Signature: `tinker {--eval= : Evaluate a single Dart expression in the running app}`

```bash
dart run artisan tinker                       # interactive REPL
dart run artisan tinker --eval "1 + 1"        # one-shot pipe-friendly
dart run artisan tinker --eval "User.current.name"
```

The `--eval` flag is also the surface of the `artisan_tinker` MCP tool. Both go through `VmServiceClient.evaluate(isolateId, expr)`.

## Codegen (1)

### `commands:refresh`

`lib/src/commands/commands_refresh_command.dart:18` (no configure override; no flags)

Scans `lib/app/commands/*.dart` for `class X extends ...Command` declarations, regenerates `lib/app/commands/_index.g.dart`. Called automatically by `make:command`; manual invocation needed when hand-renaming a command file.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Generic failure (validation, runtime error, missing state) |
| 2 | Command collision at registry build (fail-fast) |
| 3 | Unknown command name |

Verify by reading the command's `handle()` method.
