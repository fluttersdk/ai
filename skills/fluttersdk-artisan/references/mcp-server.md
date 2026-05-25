# MCP server reference

Authoritative source: `lib/src/mcp/mcp_server.dart` (server class), `lib/src/mcp/mcp_server.dart:665-675` (substrate allowlist), `lib/src/mcp/mcp_filter_config.dart` (three-layer filter), `lib/src/commands/mcp_install_command.dart` (canonical `.mcp.json` branched shape), `lib/src/state/state_file.dart:13-24` (state.json schema), `bin/mcp.dart` (legacy entry point).

The fluttersdk_artisan MCP server is a stdio JSON-RPC server built on `dart_mcp ^0.5.1`. It surfaces 10 substrate tools (the lifecycle quartet, status / logs / doctor / list, and tinker for VM expression eval) plus any plugin-contributed tools the consumer's `bin/dispatcher.dart` registers via `ArtisanServiceProvider.mcpTools()`. Post-install, the canonical dispatch path is `./bin/fsa mcp:serve` (POSIX with AOT bundle present) or `dart run :dispatcher mcp:serve` (Windows or no-fsa fallback).

## Quick install

Prerequisite: substrate package + consumer scaffold land via `dart pub add fluttersdk_artisan` followed by `dart run fluttersdk_artisan install`. `mcp:install` assumes `bin/dispatcher.dart` and (POSIX) `bin/fsa` are already present.

```bash
dart pub add fluttersdk_artisan         # if not already in pubspec.yaml
dart run fluttersdk_artisan install     # if bin/dispatcher.dart not yet scaffolded
./bin/fsa mcp:install
# or on Windows / when bin/fsa is absent:
# dart run fluttersdk_artisan mcp:install
# Then reconnect the MCP client. For Claude Code: /mcp reconnect fluttersdk
```

`mcp:install` is idempotent: re-running replaces the existing `fluttersdk` entry in `.mcp.json`, preserves any other server entries. The branched entry shape is auto-detected at install time based on platform and `bin/fsa` availability.

## Canonical `.mcp.json` entry

The shape written by `mcp:install` at `lib/src/commands/mcp_install_command.dart`:

**When `bin/fsa` is present and not on Windows:**

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

**When `bin/fsa` is absent or on Windows:**

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

`cwd: "."` means the server inherits the consumer project's working directory; this is required so the server can read `.artisan/state.json`, `.artisan/mcp.json` (filter), and the consumer's `pubspec.yaml`. The `./bin/fsa` variant starts ~50ms (AOT native); the `dart run :dispatcher` variant starts ~3s (Dart VM).

## 10 substrate tools

Allowlist at `lib/src/mcp/mcp_server.dart:665-675`. Tool names use the `artisan_` prefix with `:` and `-` mapped to `_`.

| Tool | Maps to | Connected | Input |
|------|---------|:---------:|-------|
| `artisan_start` | `start` | no | `device`, `port`, `vm-service-port`, `dds`, `profile-static` |
| `artisan_stop` | `stop` | no | none |
| `artisan_status` | `status` | no | none |
| `artisan_logs` | `logs` | no | `follow` (bool) |
| `artisan_restart` | `restart` | no | none |
| `artisan_reload` | `reload` | no | none |
| `artisan_hot_restart` | `hot-restart` | no | none |
| `artisan_doctor` | `doctor` | no | none |
| `artisan_list` | `list` | no | none |
| `artisan_tinker` | `tinker --eval=...` | **yes** | `eval` (string, required) |

`artisan_tinker` is the only substrate tool needing `CommandBoot.connected`. The dispatcher detects the boot mode, ensures `_vmClient` is connected (lazy-reconnect if absent), builds `ArtisanContext.connected`, and dispatches.

`dusk_evaluate` is a plugin tool with `extensionMethod: 'ext.dusk.evaluate'` but the dispatcher special-cases it by tool name and routes through `VmServiceClient.evaluate(isolateId, expression)` directly, because the dusk-side host handler returns a no-op sentinel by design. Surfaces 3 result branches plus the RPCError code 113 compile-error case (see `lib/src/mcp/mcp_server.dart` `_dispatchEvaluate` for the four-branch handling).

## Plugin-contributed tools

A plugin contributes tools by overriding `ArtisanServiceProvider.mcpTools()`:

```dart
final class MyPluginArtisanProvider extends ArtisanServiceProvider {
  @override
  List<ArtisanCommand> commands() => [MyCmdCommand()];

  @override
  List<McpToolDescriptor> mcpTools() => [
    McpToolDescriptor(
      name: 'my_plugin_action',
      description: 'Short Claude-Code-canonical description (imperative opener, 1-2 sentences + Usage bullets).',
      inputSchema: {
        'type': 'object',
        'properties': {
          'target': {'type': 'string', 'description': 'Action target.'},
        },
        'required': ['target'],
      },
      extensionMethod: 'ext.myPlugin.action', // VM Service extension method name
    ),
  ];
}
```

The MCP server surfaces the tool when the consumer's `bin/dispatcher.dart` calls `registry.registerProvider(MyPluginArtisanProvider());`. The tool's `extensionMethod` (without the `artisan:` prefix) routes the dispatch through VM Service; the running Flutter app must have registered the extension via `registerExtension('ext.myPlugin.action', handler)`.

### Sibling plugin catalog

| Plugin | Prefix | MCP tool reference |
|--------|--------|--------------------|
| `fluttersdk_dusk` | `dusk_*` | [fluttersdk.com/dusk/mcp/tool-reference](https://fluttersdk.com/dusk/mcp/tool-reference) |
| `fluttersdk_telescope` | `telescope_*` | [fluttersdk.com/telescope/mcp/tool-reference](https://fluttersdk.com/telescope/mcp/tool-reference) |

These plugin packages evolve independently; the canonical, up-to-date tool catalog (per-tool input schema, parameters, return shape, examples) lives on each plugin's own reference page linked above. A consumer with both plugins registered exposes the 10 substrate tools plus every tool listed on those pages, filtered through the three-layer pipeline.

## Three-layer filter

`McpFilterConfig` (`lib/src/mcp/mcp_filter_config.dart`) merges three sources in Cargo-style: CLI flags > env vars > file.

### Layer 1: `.artisan/mcp.json` (file)

Optional; place at the consumer project root. Shape:

```json
{
  "packages": {
    "allow": null,
    "deny": []
  },
  "tools": {
    "allow": null,
    "deny": []
  }
}
```

`allow: null` means "no opinion" (delegate to upper layers). `allow: []` means "block all". `allow: ["x", "y"]` means "only x and y are permitted".

`deny` is always a list; empty means "no opinion at this layer".

### Layer 2: env vars

| Variable | Format |
|----------|--------|
| `ARTISAN_MCP_PACKAGES_ALLOW` | CSV: `fluttersdk_artisan,fluttersdk_dusk` |
| `ARTISAN_MCP_PACKAGES_DENY` | CSV |
| `ARTISAN_MCP_TOOLS_ALLOW` | CSV |
| `ARTISAN_MCP_TOOLS_DENY` | CSV |

Absent or blank env vars are "no opinion".

### Layer 3: CLI flags on `mcp:serve`

| Flag (repeatable) | Layer 1+2 equivalent |
|-------------------|----------------------|
| `--include-package=<name>` | `packages.allow` |
| `--exclude-package=<name>` | `packages.deny` |
| `--include-tool=<name>` | `tools.allow` |
| `--exclude-tool=<name>` | `tools.deny` |

### Merge precedence

- **Allow**: first non-null wins. CLI > env > file. If all three are null, accept all (no allow-list active).
- **Deny**: union of all three. Deny anywhere wins everywhere.

Example: file says `packages.deny: ["fluttersdk_dusk"]`, env says `ARTISAN_MCP_TOOLS_ALLOW="artisan_start,artisan_tinker"`, CLI passes `--exclude-tool=artisan_logs`. Resulting filter: dusk tools blocked, only `artisan_start` and `artisan_tinker` permitted, `artisan_logs` additionally blocked.

## Soft-fail + lazy reconnect

When the MCP server initializes:

1. Read `~/.artisan/state.json` via `StateFile.read()`.
2. If state.json is absent or empty: stay online, log a warning to stderr, register all 10 substrate tools anyway.
3. If state.json present: lazy-connect to the VM Service via `VmServiceClient.new(stateFile.vmServiceUri)`.

When a tool call arrives and `_vmClient` is null (no app running at server init, but maybe one started since):

1. Memoize a `_lazyReconnect()` Future under `_reconnecting`.
2. Concurrent calls share the same in-flight connect attempt.
3. Clear `_reconnecting` in `finally`; next call retries.

If the lazy reconnect fails (state.json still absent, VM Service unreachable), the tool returns a `CallToolResult` with an actionable error message:

```
### Error
Not connected to a running Flutter app. Run `dart run fluttersdk_artisan start` first so `~/.artisan/state.json` records the VM Service URI.
```

Net effect: MCP clients stay connected across the consumer's `start` / `stop` cycles. The model can call `artisan_start` from cold, then immediately call `artisan_tinker` against the freshly running app.

## Per-client install

`mcp:install` writes `.mcp.json` which Claude Code and Cursor read natively. Other MCP-aware clients require different config files; the canonical entry shape branches based on platform and `bin/fsa` availability (see Canonical `.mcp.json` entry above).

### Cursor

File: `~/.cursor/mcp.json`. Same branched shape as `.mcp.json`.

### Claude Code

`.mcp.json` at project root (managed by `mcp:install`). Alternatively the CLI:

```bash
claude mcp add fluttersdk -- ./bin/fsa mcp:serve
# or on Windows / when bin/fsa is absent:
# claude mcp add fluttersdk -- dart run :dispatcher mcp:serve
```

For per-project scope: append `--scope project`. For user scope: `--scope user`.

### Claude Desktop

File location depends on OS:

- macOS: `~/Library/Application Support/Claude/claude_desktop_config.json`
- Windows: `%APPDATA%\Claude\claude_desktop_config.json`

Same `mcpServers` shape. Restart Claude Desktop after editing (File > Exit, not just window close).

### VS Code Copilot

File: `.vscode/mcp.json` at project root. Shape (POSIX with `bin/fsa`):

```json
{
  "servers": {
    "fluttersdk": {
      "type": "stdio",
      "command": "./bin/fsa",
      "args": ["mcp:serve"]
    }
  }
}
```

On Windows or when `bin/fsa` is absent, use `{"command": "dart", "args": ["run", ":dispatcher", "mcp:serve"]}`.

### Windsurf

Same shape as Cursor / Claude Code. Reload the Windsurf MCP panel after editing.

### JetBrains IDEs (Junie / AI Assistant)

Settings > MCP > Add server. Same `command + args + cwd` triple.

### Cline / Roo-Code

File: `~/.config/cline/mcp.json` (or platform equivalent).

### OpenCode

Schema differs slightly: `mcp.<name>` instead of `mcpServers.<name>`.

```json
{
  "mcp": {
    "fluttersdk": {
      "type": "local",
      "command": ["./bin/fsa", "mcp:serve"],
      "enabled": true
    }
  }
}
```

On Windows or when `bin/fsa` is absent, use `{"command": ["dart", "run", ":dispatcher", "mcp:serve"], ...}`.

### Gemini CLI

File: `~/.gemini/settings.json`. Same `mcpServers` shape.

### Antigravity

Settings > MCP servers > Add. Same shape.

### Firebase Studio

File: `.idx/mcp.json` at project root. Same shape.

## state.json schema

Written by `start`, read by `stop` / `status` / `reload` / `hot-restart` / mcp:serve. Path: `~/.artisan/state.json` (machine-local, not per-project).

```json
{
  "pid": 12345,
  "vmServiceUri": "ws://127.0.0.1:8181/AbCdE/ws",
  "webPort": 3100,
  "vmServicePort": 8181,
  "startedAt": "2026-05-19T16:42:11.123Z",
  "profile": "debug",
  "projectRoot": "/Users/me/myapp",
  "device": "chrome",
  "chromePid": null,
  "tmpProfileDir": null,
  "stdinPipe": "/Users/me/.artisan/flutter-dev.fifo",
  "stdinHolderPid": 12346
}
```

Single-slot: one Flutter app per machine. Multiple concurrent `start` invocations race and overwrite. The MCP server soft-fails when state.json is missing; tools register but dispatch errors actionably.

Schema definition: `lib/src/state/state_file.dart:13-24`. Atomic write via `.tmp` + rename in `StateFile.write()`.

## Diagnostic flow

When MCP tools misbehave:

1. **No tools surfacing**: check `./bin/fsa list` output for the artisan binaries (or `dart run fluttersdk_artisan list` when fsa is absent); confirm install. Check `.mcp.json` exists with the `fluttersdk` entry. Reconnect the MCP client.
2. **`artisan_start` returns ok but `artisan_tinker` errors "not connected"**: lazy-reconnect should resolve; call `artisan_status` first to verify the app is recorded in state.json.
3. **Tool count lower than expected**: the filter is active. Check `.artisan/mcp.json`, env vars, and CLI flags (`ARTISAN_MCP_*`). Empty deny lists, null allow lists everywhere = no filter.
4. **Plugin tools missing**: confirm the consumer's `bin/dispatcher.dart` registers the plugin provider via `registry.registerProvider(...)`. Check `lib/app/_plugins.g.dart` for the auto-discovered list. Post-install, run `./bin/fsa mcp:install` to update `.mcp.json` if it still carries the pre-fix `fluttersdk_artisan:mcp` args.
5. **State file stale**: `./bin/fsa stop` (or `dart run fluttersdk_artisan stop`) to clean. Restart the MCP client.

The MCP server writes initialization status to stderr; capture from the MCP client's log panel.
