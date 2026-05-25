---
name: fluttersdk-artisan
description: "fluttersdk_artisan: composable Dart 3.4+ CLI framework + stdio MCP server for Flutter and Dart. 21 builtin commands across 6 groups (lifecycle, scaffolding, plugin management, MCP, introspection, codegen) including install, make:plugin, plugin:install, mcp:serve, tinker. Declarative install.yaml plugin manifest + procedural PluginInstaller fluent DSL with 26 sealed InstallOperation variants. 10 substrate MCP tools (artisan_*) including artisan_tinker for VM expression eval, plus plugin-contributed tools from sibling plugins (fluttersdk_dusk, fluttersdk_telescope; see each plugin's MCP tool reference for the current catalog). TRIGGER when: package:fluttersdk_artisan import, fluttersdk_artisan in pubspec, dart run fluttersdk_artisan command, bin/dispatcher.dart present, install.yaml manifest, ArtisanCommand / ArtisanServiceProvider / McpToolDescriptor / PluginInstaller mention, .mcp.json fluttersdk entry, or user asks about artisan, plugin scaffold, MCP setup, dev loop, signature DSL. DO NOT TRIGGER when code only uses Wind UI or Magic without artisan touchpoint."
version: 0.0.1
when_to_use: "Any task touching fluttersdk_artisan: invoking commands, bootstrapping install, authoring or installing a plugin (install.yaml or PluginInstaller DSL), configuring MCP for Claude Code / Cursor / Windsurf, evaluating Dart via artisan_tinker, reading install.yaml schema. Apply on any repo with bin/dispatcher.dart, lib/app/_plugins.g.dart, .artisan/state.json, install.yaml, or pubspec depending on fluttersdk_artisan."
---

<!-- fluttersdk_artisan v0.0.1 | Skill updated: 2026-05-19 | Source: https://github.com/fluttersdk/artisan -->

# fluttersdk_artisan

Composable Dart 3.4+ CLI framework and stdio MCP server. One binary registers every command, one protocol describes every plugin install, one MCP server exposes the substrate to AI coding agents. Pure Dart, no Flutter runtime dependency in the framework core. The skill covers the command surface, the plugin protocol, and the MCP integration; load reference files on demand for per-topic depth.

## 1. Core Laws

1. **One binary, two entry points.** `dart run fluttersdk_artisan <cmd>` runs against the artisan package directly. `./bin/fsa <cmd>` (POSIX with AOT bundle present) or `dart run :dispatcher <cmd>` (cross-platform fallback) runs through the consumer's `bin/dispatcher.dart` wrapper produced by `install` (most projects).
2. **MCP entry is wired by `mcp:install`**: `mcp:install` writes the `.mcp.json` entry; after that, the MCP client spawns the server via `./bin/fsa mcp:serve` (or `dart run :dispatcher mcp:serve` on Windows or when `bin/fsa` is absent). Not for human CLI use; invoke via the MCP client (Claude Code, Cursor, Windsurf).
3. **Pub.dev install in docs; install command chooses at runtime**: in any user-facing artifact (README, doc pages, `llms.txt`, install.yaml templates, examples) use `dart pub add fluttersdk_artisan` or `fluttersdk_artisan: ^0.0.1`. The `install` command itself picks the right dep shape at scaffold time: a `path:` entry when `.dart_tool/package_config.json` resolves `fluttersdk_artisan` to a relative `rootUri` (sibling-package monorepo workflow), otherwise `fluttersdk_artisan: any` so the next `pub get` pulls the published package. Never hand-write `path:` syntax in docs.
4. **Atomic + idempotent**: every persistent file write goes through `.tmp` + rename. Plugin installers use lookahead-anchored regex injection so re-running `plugin:install` is a safe no-op.
5. **State lives at `~/.artisan/state.json`** for the running app (PID, VM Service URI, device, FIFO stdin pipe). At `.artisan/plugins.json` for installed plugins. At `.artisan/installed/<plugin>.json` for plugin reverse-records. State files belong in `.gitignore`; the package's own `.gitignore` already excludes `.artisan/`.
6. **Codegen barrels are generated**: `lib/app/_plugins.g.dart` (plugin provider list) and `lib/app/commands/_index.g.dart` (command index) regenerate from `.artisan/plugins.json` and from `lib/app/commands/*.dart` scans respectively. Never hand-edit the `.g.dart` files; mutate the source-of-truth and run the matching `plugins:refresh` or `commands:refresh`. `plugin:install`, `plugin:uninstall`, and `plugins:refresh` invalidate the `.artisan/cli-bundle/` AOT cache and the `.artisan/build.stamp` file as a side effect, so the next `./bin/fsa` invocation rebuilds against the freshly-regenerated `lib/app/_plugins.g.dart`.
7. **Signature DSL primary, ArgParser fallback**: 6 of the 21 commands use `String get signature => 'cmd:name {arg} {--flag}'`. The remaining 15 use `void configure(ArgParser parser)` directly or have no flag surface. Both shapes are valid; pick by complexity.
8. **MCP allowlist is explicit**: only 10 substrate commands surface as `artisan_*` MCP tools by allowlist at `lib/src/mcp/mcp_server.dart:665-675`. The other 11 commands stay CLI-only because they need a TTY, mutate source on disk in ways the agent's own file tools handle better, or recurse into the MCP server.
9. **Plugin MCP tools register via provider override**: a plugin contributes MCP tools by overriding `ArtisanServiceProvider.mcpTools()` and returning a `List<McpToolDescriptor>`. Substrate tools have `artisan_` prefix; plugin tools use the package's prefix (`dusk_`, `telescope_`, etc.).
10. **Reversible installs are partial in V1**: `plugin:uninstall` fully reverses `WriteFile` / `DeleteFile` / `CopyFile` operations; injection ops (`InjectImport`, `InjectAndroidPermission`, etc.) are logged as `[skipped]`. Always run `plugin:uninstall --dry-run` first when unsure.
11. **Magic-free path exists**: `install` writes a canonical 3-file consumer skeleton without any framework dependency. The Magic framework is one possible plugin, not a prerequisite.
12. **No forbidden marketing keywords in artifacts**: avoid "Laravel", "Symfony Console", "Artisan-style", "Artisan-inspired" in user-facing docs and code. No em-dash (—) or en-dash (–); use comma, colon, semicolon, period, or parentheses instead.

## 2. Bootstrap a consumer project

Three steps from empty repo to running artisan command:

```bash
dart pub add fluttersdk_artisan
dart run fluttersdk_artisan install
dart run artisan list
```

After `install`, the wrapper at `bin/dispatcher.dart` calls `runArtisan(...)` with the consumer's package name resolved automatically. Every subsequent command runs via `dart run artisan <cmd>` (NOT `dart run fluttersdk_artisan` once the wrapper exists, though both work).

**Files produced by `install`:**

| File | Purpose |
|------|---------|
| `bin/dispatcher.dart` | Consumer entry wrapping `runArtisan(...)` |
| `lib/app/_plugins.g.dart` | Generated plugin provider barrel (empty until `plugin:install`) |
| `lib/app/commands/_index.g.dart` | Generated command index (empty until `make:command`) |

Pubspec is also mutated to add `fluttersdk_artisan: ^0.0.1` (pub.dev consumers) or `fluttersdk_artisan: { path: ... }` (monorepo path-dep auto-detected via `.dart_tool/package_config.json` rootUri). Re-running is idempotent unless `--force` is passed.

## 3. Command surface (21 commands across 6 groups)

| Group | Commands | Boot mode |
|-------|----------|-----------|
| **Lifecycle** (7) | `start` `stop` `status` `logs` `restart` `reload` `hot-restart` | `none` |
| **Scaffolding** (3) | `make:plugin` `make:command` `install` | `none` |
| **Plugin Management** (3) | `plugin:install` `plugin:uninstall` `plugins:refresh` | `none` |
| **MCP** (3) | `mcp:serve` `mcp:install` `mcp:uninstall` | `none` |
| **Introspection** (4) | `help` `list` `doctor` `tinker` | `none` except `tinker` is `connected` |
| **Codegen** (1) | `commands:refresh` | `none` |

Full per-command synopsis (flags, behavior, source file:line, examples) lives in `${CLAUDE_SKILL_DIR}/references/commands.md`. Read that file when looking up a flag or behavior for a specific command.

**Lifecycle shortcuts (the dev-loop quartet):**

```bash
dart run artisan start --device=chrome      # spawn flutter run detached, record state.json
dart run artisan reload                      # hot reload (sends r over FIFO)
dart run artisan hot-restart                 # hot restart (sends R; drops Dart state)
dart run artisan stop                        # SIGTERM the flutter run pid + cleanup
```

`start` writes `~/.artisan/state.json` with the VM Service URI, PID, device, and FIFO stdin pipe path. `reload` / `hot-restart` send keystroke commands to that FIFO. `stop` reads the PID from state.json and SIGTERMs.

**Scaffold cheat sheet:**

```bash
dart run artisan make:plugin awesome_plugin            # 7-file plugin skeleton at packages/<name>/
dart run artisan make:plugin awesome_plugin --magic    # adds install.yaml + ServiceProvider + install/uninstall commands
dart run artisan make:command Greet                    # context-aware: plugin vs consumer; auto-registers
dart run artisan install                               # idempotent; --force to overwrite
```

`make:plugin` detects the parent Flutter app and enrolls the new plugin in `pubspec.yaml` workspace if one exists.

## 4. Plugin install protocol

**Three routing modes** dispatched by `plugin:install`, in source order at `lib/src/commands/plugin_install_command.dart:130-181`:

1. **Manifest flow** (preferred): plugin ships `install.yaml` at package root or under `assets/install.yaml`. `plugin:install` parses, walks `ManifestInstaller`, commits atomically, records the install at `.artisan/installed/<plugin>.json`, registers the provider in `.artisan/plugins.json`, refreshes `lib/app/_plugins.g.dart`.
2. **Magic-free canonical scaffold fast path**: no manifest, but `lib/app/_plugins.g.dart` exists. Skip legacy injection; write directly to `plugins.json` + refresh codegen. This is the path for plain Flutter consumers that ran `install`.
3. **Legacy injection fallback**: no manifest, no canonical scaffold. Inject `import 'package:<name>/cli.dart';` + `registry.registerProvider(<PascalCaseName>ArtisanProvider());` into `bin/dispatcher.dart`. Backward-compat path.

Force a specific mode with `--use-yaml-only` (fails when no manifest) or by passing `--provider=` and `--bootstrap-command=` overrides.

**install.yaml schema (top-level keys):**

| Key | Purpose | Required |
|-----|---------|----------|
| `plugin_name` | Package name (regex `^[a-z_][a-z0-9_]*$`) | **yes** |
| `dependencies` | `pubspec.deps` + `pubspec.dev_deps` + `pubspec.assets` | no |
| `publish` | Stub file -> target path map (`install/x.dart.stub: lib/config/x.dart`) | no |
| `json_merge` | Target JSON file + source stub + `additive` flag | no |
| `magic` | `provider` (PascalCase) + `config_factory` + `routes` for Magic-aware plugins | no |
| `native` | `android` / `ios` / `macos` / `web` platform configs | no |
| `env` | `.env` variables with defaults + comments | no |
| `prompts` | Interactive prompts (`string` / `choice` / `bool`) | no |
| `placeholders` | Template values, supports `{{ prompts.KEY }}` interpolation | no |
| `post_install` | `run` + `ask_to_run` shell commands + `message` | no |
| `bootstrap_command` | Plugin command name to chain after install (e.g. `logger:install`) | no |

Full schema with every nested field, regex, and the canonical example (transcribed from `test/installer/manifest_parser_test.dart`) lives in `${CLAUDE_SKILL_DIR}/references/install-yaml-schema.md`.

**Procedural escape hatch (PluginInstaller fluent DSL):**

When `install.yaml` is insufficient (complex conditional logic, branching prompts, custom file generation), implement an `ArtisanInstallCommand` subclass that drives `PluginInstaller` directly. Methods split into IMMEDIATE (`ask`, `confirm`, `choice` fire during chain) and DEFERRED (`writeFile`, `injectImport`, `injectProvider`, `injectAndroidPermission`, etc. enqueue typed `InstallOperation` until `commit()`). Atomic `.tmp` + rename throughout; `_committed` one-shot guard prevents replay.

Full DSL reference (all 26 sealed `InstallOperation` variants, IMMEDIATE/DEFERRED split, atomic commit semantics, example): `${CLAUDE_SKILL_DIR}/references/installer-dsl.md`.

## 5. MCP integration (the AI agent surface)

**Quick install** (writes `.mcp.json` entry idempotently):

```bash
./bin/fsa mcp:install
```

Then reconnect the MCP client (Claude Code: `/mcp reconnect fluttersdk`). The server boots in stdio JSON-RPC mode via `./bin/fsa mcp:serve` (or `dart run :dispatcher mcp:serve` on Windows or when `bin/fsa` is absent) and surfaces tools.

**10 substrate tools (always available):**

| Tool | Maps to | Purpose |
|------|---------|---------|
| `artisan_start` | `start` | Spawn `flutter run`, record `~/.artisan/state.json` |
| `artisan_stop` | `stop` | SIGTERM the running app, clean up state.json |
| `artisan_status` | `status` | Print JSON status of the recorded app (running / pid / vmServiceUri / device / startedAt) |
| `artisan_logs` | `logs` | Stream or follow the captured `flutter run` log |
| `artisan_restart` | `restart` | `stop` + `start` (full process cycle) |
| `artisan_reload` | `reload` | Hot reload via FIFO keystroke (preserves Dart state) |
| `artisan_hot_restart` | `hot-restart` | Hot restart via FIFO keystroke (drops Dart state, keeps process) |
| `artisan_doctor` | `doctor` | Environment preflight (`flutter` / `dart` / port availability) |
| `artisan_list` | `list` | Catalog every registered command grouped by namespace |
| `artisan_tinker` | `tinker --eval=...` | Evaluate Dart expression in the running app via VM Service evaluate RPC |

`artisan_tinker` is the only substrate tool that needs `CommandBoot.connected`; the dispatcher detects this and builds an `ArtisanContext.connected` with the lazy-reconnected VM client. Requires `artisan_start` to have written `~/.artisan/state.json` first.

**Plugin-contributed tools** (when the consumer wrapper registers the plugin's provider):

| Plugin | Prefix | MCP tool reference |
|--------|--------|--------------------|
| `fluttersdk_dusk` | `dusk_*` | [fluttersdk.com/dusk/mcp/tool-reference](https://fluttersdk.com/dusk/mcp/tool-reference) |
| `fluttersdk_telescope` | `telescope_*` | [fluttersdk.com/telescope/mcp/tool-reference](https://fluttersdk.com/telescope/mcp/tool-reference) |

A consumer with both plugins active exposes the 10 substrate tools plus the current plugin tool catalog from each registered sibling (see each plugin's reference page for the up-to-date list).

**Three-layer filter** (`McpFilterConfig`, Cargo-style precedence):

1. `.artisan/mcp.json` file (lowest precedence)
2. `ARTISAN_MCP_PACKAGES_ALLOW` / `_DENY` / `ARTISAN_MCP_TOOLS_ALLOW` / `_DENY` env vars (CSV)
3. CLI flags on `mcp:serve`: `--include-package`, `--exclude-package`, `--include-tool`, `--exclude-tool` (highest precedence)

Allow lists: CLI > env > file (first non-null wins, replace not merge). Deny lists: union across all three (deny anywhere wins everywhere). Per-client install instructions (Cursor, Claude Code, Claude Desktop, VS Code Copilot, Windsurf, JetBrains, Cline, OpenCode, Gemini CLI, Antigravity, Firebase Studio) live in `${CLAUDE_SKILL_DIR}/references/mcp-server.md`.

**Soft-fail + lazy reconnect**: when `~/.artisan/state.json` is absent (no running app), the MCP server stays online and registers all 10 substrate tools. Individual tool calls soft-fail at dispatch with an actionable error. When the user runs `artisan_start` later, the next tool call lazy-reconnects automatically; concurrent calls share one in-flight connect attempt via a memoized future.

## 6. Common workflows

### A. Bootstrap a brand-new consumer

```bash
dart pub add fluttersdk_artisan
dart run fluttersdk_artisan install
dart run fluttersdk_artisan mcp:install
# Reconnect the MCP client once.
```

### B. Install a third-party plugin

```bash
dart pub add awesome_plugin
dart run artisan plugin:install awesome_plugin           # routes by manifest presence
dart run artisan list                                     # plugin commands appear under awesome:* namespace
```

Inspect what an install would do without writing anything: `dart run artisan plugin:install awesome_plugin --dry-run`.

### C. Author your own plugin

```bash
dart run artisan make:plugin my_plugin                   # generic Magic-free plugin
dart run artisan make:plugin my_plugin --magic           # adds install.yaml + Magic ServiceProvider
cd packages/my_plugin
dart run artisan make:command MyAction                   # context-aware: detects we are inside a plugin
```

The plugin's `ArtisanServiceProvider` overrides `commands()` and optionally `mcpTools()`. Full authoring walkthrough: `${CLAUDE_SKILL_DIR}/references/plugin-authoring.md`.

### D. Drive a running Flutter app from an AI agent

```bash
dart run artisan start --device=chrome
# Then from the MCP client (Claude Code, Cursor):
# call artisan_list to discover available tools
# call artisan_tinker with eval="MonitorController.instance.refresh()"
# call any fluttersdk_dusk or fluttersdk_telescope tool (when the plugin provider is registered)
# call artisan_hot_restart between code edits
```

### E. Uninstall a plugin

```bash
dart run artisan plugin:uninstall awesome_plugin --dry-run    # preview reverse ops
dart run artisan plugin:uninstall awesome_plugin              # commit reverse
```

V1 reverses `WriteFile` / `DeleteFile` / `CopyFile` fully; injection ops log `[skipped]` and may require manual cleanup of `lib/config/app.dart` or platform manifests.

### F. Refresh codegen barrels manually

```bash
dart run artisan plugins:refresh        # regenerate lib/app/_plugins.g.dart from .artisan/plugins.json
dart run artisan commands:refresh       # regenerate lib/app/commands/_index.g.dart from filesystem scan
```

Both are atomic (`.tmp` + rename) and idempotent. `make:command` and `plugin:install` already call the matching refresh internally; manual invocation only needed when hand-editing the source-of-truth files.

## 7. Anti-patterns (avoid)

- **Hand-editing `.g.dart` barrels.** Mutate `.artisan/plugins.json` or `lib/app/commands/*.dart` and run the refresh command. Hand-edits get clobbered on next refresh.
- **`path:` dependency in user-facing docs.** Use `^0.0.1` pub.dev caret in README, install.yaml, generated scaffold output. Path deps are dev-only.
- **Forbidden keywords in produced artifacts**: Laravel, Symfony Console, Artisan-style, Artisan-inspired. The signature DSL syntax is artisan's own, document it as such.
- **Em-dash (—) or en-dash (–) anywhere.** Use comma, colon, semicolon, period, parentheses.
- **Adding to `_safeArtisanCommandNames` without input schema + description.** All three (allowlist, `_commandInputSchema`, `_mcpDescriptionFor`) must update together; the in-package test asserts every allowlisted name has a non-default schema entry.
- **Treating `tinker_eval` and `artisan_tinker` as different tools.** `artisan_tinker` is the artisan-substrate name. `tinker_eval` was the legacy magic_tinker plugin name (now obsolete); the artisan-builtin replaces it.
- **Assuming Windows compatibility for `start` / `stop` / `reload` / `hot-restart`.** V1 uses POSIX FIFO stdin (`mkfifo`). macOS and Linux only.

## 8. File paths quick reference

| Path | Purpose |
|------|---------|
| `bin/dispatcher.dart` (consumer) | Consumer entry wrapping `runArtisan(...)` |
| `bin/mcp.dart` (artisan package) | MCP server entry; forces `delegateToConsumer: false` |
| `lib/app/_plugins.g.dart` (consumer) | Generated plugin provider barrel |
| `lib/app/commands/_index.g.dart` (consumer) | Generated command index |
| `lib/app/commands/*.dart` (consumer) | User-authored commands (source-of-truth for `_index.g.dart`) |
| `lib/src/commands/*_command.dart` (artisan) | 21 builtin commands |
| `lib/src/console/artisan_service_provider.dart` (artisan) | Plugin contract |
| `lib/src/installer/install_manifest.dart` (artisan) | install.yaml schema classes |
| `lib/src/installer/manifest_parser.dart` (artisan) | install.yaml regex validation |
| `lib/src/mcp/mcp_server.dart:665-675` (artisan) | 10-tool substrate allowlist |
| `lib/src/mcp/mcp_filter_config.dart` (artisan) | Three-layer filter logic |
| `assets/stubs/make_plugin/{generic,magic}/` (artisan) | `make:plugin` scaffold stubs |
| `assets/stubs/consumer_*.stub` (artisan) | `install` skeleton stubs |
| `install.yaml` (plugin package) | Declarative install manifest |
| `.artisan/plugins.json` (consumer) | Installed plugin registry |
| `.artisan/installed/<plugin>.json` (consumer) | Plugin install record (reverse ops) |
| `~/.artisan/state.json` (machine-local) | Running flutter app state (PID, VM URI, device, FIFO) |
| `.mcp.json` (project root) | MCP server registration (Claude Code, Cursor) |
| `.artisan/mcp.json` (consumer, optional) | Filter config for `mcp:serve` |

## 9. Source-of-truth pointers

When this skill's content disagrees with the source code, the source wins. Key files (all under the artisan package root):

- `pubspec.yaml:2` — canonical description string
- `lib/src/commands/*_command.dart` — 21 commands, signature DSL or `configure(ArgParser)`
- `lib/src/mcp/mcp_server.dart:665-675` — 10-tool allowlist
- `lib/src/mcp/mcp_server.dart:521-597` — per-command input schemas
- `lib/src/mcp/mcp_server.dart:363-509` — per-command MCP descriptions (rich text)
- `lib/src/installer/install_manifest.dart:1-85` — schema field classes
- `lib/src/installer/manifest_parser.dart:31,34` — `plugin_name` and provider PascalCase regex
- `lib/src/state/state_file.dart:13-24` — state.json schema
- `test/installer/manifest_parser_test.dart:14-105` — canonical install.yaml example (byte-exact)

Cite these paths with line numbers when documenting behavior; consumers can verify any claim by reading the file.

## 10. References (load on trigger)

| Read when... | File |
|--------------|------|
| Looking up flags, behavior, or examples for a specific command (any of the 21) | `${CLAUDE_SKILL_DIR}/references/commands.md` |
| Writing, parsing, or extending an install.yaml plugin manifest | `${CLAUDE_SKILL_DIR}/references/install-yaml-schema.md` |
| Authoring an `ArtisanInstallCommand` or driving `PluginInstaller` programmatically | `${CLAUDE_SKILL_DIR}/references/installer-dsl.md` |
| Configuring the MCP server, per-client install, filter syntax, or tool catalog by package | `${CLAUDE_SKILL_DIR}/references/mcp-server.md` |
| Walking an end-to-end plugin authoring flow (make:plugin to publish) | `${CLAUDE_SKILL_DIR}/references/plugin-authoring.md` |

Standing reminders for the rest of the session: pub.dev install form only, no `path:` deps in produced artifacts. No em-dash. No "Laravel" / "Symfony Console" / "Artisan-style" / "Artisan-inspired" anywhere. Cite source `file_path:line_number` when documenting behavior. When asked about a flag or behavior you have not verified, read the source file before answering rather than guessing.
