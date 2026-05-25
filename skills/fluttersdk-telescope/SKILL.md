---
name: fluttersdk-telescope
description: "fluttersdk_telescope: runtime inspector plugin for Flutter apps. Captures HTTP traffic, structured logs, uncaught exceptions, Magic Model lifecycle events, Magic Cache operations, in-app events, Gate authorization checks, debugPrint output, and DB queries into 9 in-memory ring buffers. Surfaces all 9 buffers as VM Service extensions (ext.telescope.*) and exposes 9 MCP tools (telescope_*) for LLM-agent inspection without modifying app code or attaching DevTools. Plugin of fluttersdk_artisan: contributes 6 CLI commands and 9 MCP tools via TelescopeArtisanProvider. TRIGGER when: package:fluttersdk_telescope import, TelescopePlugin.install() call, TelescopeWatcher / TelescopeHttpAdapter mention, ext.telescope.* VM extension, telescope_* MCP tool call, or user asks about inspecting HTTP, logs, exceptions, or Magic framework state in a running Flutter app. DO NOT TRIGGER when code only uses fluttersdk_artisan substrate tools without telescope."
version: 0.0.1
when_to_use: "Any task that reads or reacts to runtime state in a running Flutter app via telescope: calling telescope_* MCP tools from an agent workflow, registering a custom TelescopeWatcher or TelescopeHttpAdapter, debugging why a watcher does not capture records, writing or running telescope watcher tests, or configuring TelescopePlugin.install() in main.dart."
---

<!-- fluttersdk_telescope v0.0.1 | Skill updated: 2026-05-21 | Source: references/fluttersdk_telescope -->

# fluttersdk_telescope

Runtime inspector for Flutter apps. Installs a set of watchers and HTTP adapters that funnel every observable
signal (HTTP calls, log lines, exceptions, Magic model saves, cache hits, events, gate checks, debugPrint, DB
queries) into 9 in-memory ring buffers inside the running app. A matching set of VM Service extensions
(ext.telescope.*) and MCP tools (telescope_*) lets an LLM agent read those buffers on demand, without touching
the app source or opening Flutter DevTools.

The package is debug-only: the consumer wraps `TelescopePlugin.install()` inside `if (kDebugMode)` in `main.dart`.
Release builds tree-shake the entire subsystem (dart2js + dart2native AOT).

## 1. Core Laws

1. **Plugin of fluttersdk_artisan.** `TelescopeArtisanProvider` registers 6 CLI commands and 9 MCP tools with the
   artisan dispatcher. The canonical bootstrap is `dart run fluttersdk_telescope telescope:install` (telescope's
   own bin carries the artisan substrate, so it works from a fresh consumer without prior artisan wiring). The
   command scaffolds `bin/dispatcher.dart`, runs `plugin:install fluttersdk_telescope` (which writes
   `FluttersdkTelescopeArtisanProvider` into `lib/app/_plugins.g.dart`), and patches `lib/main.dart`. After
   install, prefer the consumer's `./bin/fsa <cmd>` (native AOT, ~110ms warm) over the slower
   `dart run fluttersdk_telescope <cmd>` (~3s cold) for everyday calls.
2. **Three entry points.** `TelescopePlugin.install()` starts the default stack (LogWatcher + VM extensions).
   `TelescopePlugin.registerHttpAdapter(adapter)` adds HTTP capture. `TelescopePlugin.registerWatcher(watcher)`
   adds any additional watcher. Both registration methods call `install()` on the argument immediately.
3. **LogWatcher is auto-installed; everything else is opt-in.** `ExceptionWatcher`, `DumpWatcher`, and all
   Magic-side watchers (`MagicModelWatcher`, `MagicCacheWatcher`, `MagicEventWatcher`, `MagicGateWatcher`,
   `MagicQueryWatcher`) are registered explicitly after `TelescopePlugin.install()`.
4. **Ring buffers, not logs.** `TelescopeStore` holds 9 `Queue<T>` buffers capped at 500 entries each (default,
   configurable via `TelescopeStore.setCapacity`). Oldest entries are dropped when the cap is reached. No disk IO.
5. **Chain-preserve every global override.** Any watcher that replaces a global hook (`FlutterError.onError`,
   `PlatformDispatcher.instance.onError`, `debugPrint`) saves the previous value and calls it inside the new
   handler. `uninstall()` restores the previous value exactly. This keeps Sentry / Bugsnag coexisting safely.
6. **VM extensions are idempotent.** All registrations go through `registerExtensionIdempotent` (from
   `fluttersdk_artisan`). Hot-restart safe; duplicate registration on hot-restart is a no-op rather than an
   `ArgumentError`.
7. **Contracts are frozen.** `TelescopeWatcher` (`name`, `install`, `uninstall`),
   `TelescopeHttpAdapter` (`name`, `install`, `uninstall`, optional `pendingCount`), and
   `TelescopePlugin` (`install`, `registerHttpAdapter`, `registerWatcher`) are frozen for V1.
   Magic-side glue depends on them; changes require a coordinated bump across both repos.
8. **No em-dash, no en-dash anywhere.** Use comma, colon, semicolon, period, or parentheses.

## 2. Minimal install in main.dart

```dart
import 'package:flutter/foundation.dart';
import 'package:fluttersdk_telescope/telescope.dart';

// Magic-side watchers and adapters (if using Magic framework).
import 'package:magic/magic.dart'; // MagicTelescopeIntegration (optional)

void main() async {
  if (kDebugMode) {
    // 1. Install core plugin (LogWatcher + VM extensions).
    TelescopePlugin.install();

    // 2. Capture uncaught exceptions (opt-in).
    TelescopePlugin.registerWatcher(ExceptionWatcher());

    // 3. Capture debugPrint output (opt-in, debug-only gate inside DumpWatcher).
    TelescopePlugin.registerWatcher(DumpWatcher());
  }

  await Magic.init([...]);

  if (kDebugMode) {
    // 4. Register Magic-side adapters and watchers after Magic is ready.
    MagicTelescopeIntegration.install();
  }

  runApp(MagicApplication());
}
```

`MagicTelescopeIntegration.install()` registers `MagicHttpFacadeAdapter` + `MagicModelWatcher` +
`MagicCacheWatcher` + `MagicEventWatcher` + `MagicGateWatcher` + `MagicQueryWatcher` in one call.

## 3. Three public contracts

### TelescopeWatcher

Defined at `lib/src/watchers/watcher.dart`. Three methods: `name` (human-readable string), `install()` (wire the
hook), `uninstall()` (tear down for test isolation). Built-in impls: `LogWatcher` (auto), `ExceptionWatcher`,
`DumpWatcher`. Magic ships `MagicModelWatcher`, `MagicCacheWatcher`, `MagicEventWatcher`, `MagicGateWatcher`,
`MagicQueryWatcher`. Details and chain-preserve discipline: `${CLAUDE_SKILL_DIR}/references/watchers.md`.

### TelescopeHttpAdapter

Defined at `lib/src/adapters/http_adapter.dart`. Same 3-method shape as `TelescopeWatcher` plus an optional
`pendingCount` getter (default returns 0; override for in-flight tracking used by dusk `wait_for_network_idle`).
Built-in impl: `DioHttpAdapter` (vanilla Dio). Magic ships `MagicHttpFacadeAdapter`.

### McpToolDescriptor (9 telescope tools)

Defined in `fluttersdk_artisan`. Telescope registers 9 descriptors in `TelescopeArtisanProvider.mcpTools()`. Each
maps a `telescope_*` MCP tool name to an `ext.telescope.*` VM extension. Full per-tool input schemas and usage
examples: `${CLAUDE_SKILL_DIR}/references/mcp-tools.md`.

## 4. TelescopeStore (ring buffer sink)

`lib/src/telescope_store.dart`. Singleton, static methods only. 9 `Queue<T>` buffers + 9 broadcast
`StreamController<T>`. Key APIs:

| Method | Purpose |
|--------|---------|
| `recordHttp(r)` / `recordLog(r)` / `recordException(r)` | Feed a record into the matching buffer |
| `recordMagicModel(r)` / `recordMagicCache(r)` / `recordEvent(r)` | Same for Magic-side records |
| `recordGate(r)` / `recordDump(r)` / `recordQuery(r)` | Same for gate, dump, query records |
| `recentHttp({limit})` | Return the N most recent HTTP records |
| `recentLogs({limit, minLevel})` | Return logs filtered by minimum level |
| `recentExceptions({limit})` etc. | Per-buffer `recent*` variants |
| `onHttpRecord` / `onLogRecord` etc. | Broadcast `Stream<T>` per buffer |
| `clear()` | Wipe all 9 buffers |
| `pause()` / `resume()` | Pause / resume recording globally |
| `pendingHttpCount` | Sum of `pendingCount` across all registered HTTP adapters |
| `resetForTesting()` | Test-only: clear buffers + reset pause + reset cap + clear adapter registry |

Watchers call `TelescopeStore.record*` and nothing else. They do not reach into `Queue` or `StreamController`
internals.

## 5. VM Service extensions (ext.telescope.*)

Registered by `registerAllTelescopeExtensions()` (`lib/src/extensions/`). All 11 extensions:

| Extension | CLI command | MCP tool |
|-----------|------------|---------|
| `ext.telescope.requests` | `telescope:requests` | `telescope_requests` |
| `ext.telescope.console` | `telescope:tail` | `telescope_tail` |
| `ext.telescope.exceptions` | - | `telescope_exceptions` |
| `ext.telescope.events` | - | `telescope_events` |
| `ext.telescope.gates` | - | `telescope_gates` |
| `ext.telescope.dumps` | - | `telescope_dumps` |
| `ext.telescope.queries` | `telescope:queries` | `telescope_queries` |
| `ext.telescope.caches` | `telescope:caches` | `telescope_caches` |
| `ext.telescope.clear` | `telescope:clear` | `telescope_clear` |
| `ext.telescope.pause` | - | - (backlog) |
| `ext.telescope.resume` | - | - (backlog) |

Pause and resume VM extensions are registered but NOT surfaced as MCP tools in V1 (backlog). Events, gates, and
dumps have VM extensions and MCP tools but no CLI commands (MCP-only access is intentional for V1).

## 6. References (load on trigger)

| Read when... | File |
|--------------|------|
| Registering a custom watcher, understanding chain-preserve discipline, reading watcher test patterns | `${CLAUDE_SKILL_DIR}/references/watchers.md` |
| Calling telescope_* MCP tools from an agent workflow, reading input schemas and return shapes | `${CLAUDE_SKILL_DIR}/references/mcp-tools.md` |

## 7. Source-of-truth pointers

When this skill's content disagrees with the source code, the source wins:

- `lib/src/watchers/watcher.dart` -- `TelescopeWatcher` contract (3 frozen methods)
- `lib/src/adapters/http_adapter.dart` -- `TelescopeHttpAdapter` contract (3 frozen methods + optional `pendingCount`)
- `lib/src/telescope_plugin.dart` -- `TelescopePlugin.install()`, `registerHttpAdapter()`, `registerWatcher()`
- `lib/src/telescope_store.dart` -- 9 buffers, all `record*` / `recent*` / `on*Record` / `clear` / `pause` / `resume`
- `lib/src/telescope_artisan_provider.dart` -- 9 `McpToolDescriptor` entries; canonical MCP tool descriptions
- `lib/src/extensions/register_telescope_extensions.dart` -- 11 VM extension registrations
- `references/magic/lib/src/cli/telescope_integration.dart` -- Magic-side watcher and adapter impls
