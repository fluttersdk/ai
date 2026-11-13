---
name: dowel
description: "Start, hot reload and inspect a running Flutter app from an agent with dowel's `dowel_*` MCP tools and `./bin/dowel` CLI."
version: 0.0.9
when_to_use: "Use when driving a Flutter app through dowel, installing a dowel plugin, or fixing dowel MCP wiring or session errors."
---

# dowel

`dowel` is a CLI and a stdio MCP server in one binary. An agent calls `dowel_*` tools (or `./bin/dowel <cmd>` from a shell) to start the app, hot reload it, read its log, evaluate Dart against the running isolate, and install plugins that add their own commands and tools, without leaving the conversation.

Scope: this skill drives an app and installs plugins. Writing a plugin (`install.yaml`, `PluginInstaller`, `DowelServiceProvider`) is in the plugin authoring docs; widget interaction is the `tapir` skill and HTTP, log and exception capture is the `crumbs` skill.

## Install

If `./bin/dowel` is missing or `dart run dowel list` fails, dowel is not set up. From the Flutter app root:

```bash
dart pub add dowel
dart run dowel install        # bin/dispatcher.dart, lib/app/*.g.dart barrels, then builds ./bin/dowel
./bin/dowel mcp:install       # writes the dowel entry into .mcp.json
./bin/dowel doctor            # toolchain preflight
```

Reconnect the MCP client afterwards (Claude Code: `/mcp reconnect dowel`); stdio servers are not reloaded on their own.

## Rules

1. **Two MCP entries give two tool catalogues.** `dart run dowel:mcp` serves the 10 substrate tools only. `./bin/dowel mcp:serve` (or `dart run :dispatcher mcp:serve`) also loads `lib/app/_plugins.g.dart` and adds every plugin's `tapir_*`, `crumbs_*` and similar tools. Read `.mcp.json` to see which one is wired; a missing plugin namespace in `dowel_list` means the substrate entry is wired, or `plugins:refresh` has not run.
2. **The session is per project.** `dowel_start` writes `~/.dowel/sessions/<hash>/state.json` (pid, `vmServiceUri`, FIFO path, device, ports) keyed by the project root, so two projects run side by side and a command never acts on another project's app. `~/.dowel/state.json` is only a pointer to whichever session started last. With no session, `dowel_status` answers `{"running": false}`, `dowel_stop` is a no-op and connected tools return `isError: true` with "Run `dowel start` first"; the server stays up.
3. **"Start, then tinker" needs no reconnect.** The server re-reads the session on the next connected call and opens the VM Service once, however many calls arrive together.
4. **Reload keeps the isolate, restart replaces it.** `dowel_reload` (`r`) keeps Dart state; `dowel_hot_restart` (`R`) drops it and mints a new isolate id. The client re-resolves a stale id by itself, so call `dowel_tinker` again without reconnecting.
5. **`dowel_tinker` takes one expression.** The VM Service compiles a single expression in the root library: a trailing `;`, several statements, `import` or a declaration fail with `RPCError(code: 113)`. A bare `await` is allowed because dowel wraps the source in `(() async => <expr>)()`. End a non-primitive result with `.toString()` inside the expression, or it prints as `<ClassName#id>`.
6. **Only 10 of the 22 commands are MCP tools.** The CLI-only rest (`help`, `install`, `make:*`, `commands:refresh`, `plugins:refresh`, `plugin:install`, `plugin:uninstall`, `mcp:*`) write source, prompt, or recurse into the server. Run them from Bash: `./bin/dowel <cmd>` (native, about 100 ms warm) or `dart run dowel <cmd>` (about 3 s).
7. **Reload and hot restart are POSIX only.** `start` creates a FIFO (`~/.dowel/sessions/<hash>/flutter-dev.fifo`) and `dowel_reload` or `dowel_hot_restart` write `r` or `R` into it. On Windows `mkfifo` fails with "V1 is POSIX-only"; stop and tell the user.
8. **`./bin/dowel` is an AOT cache.** It rebuilds (about 5 s) when the bundle or `.dowel/build.stamp` is missing or empty, the stamp's lockfile hash or Dart version differs, or `pubspec.yaml` or `lib/app/_plugins.g.dart` is newer than the stamp. A wrapper stuck on `waiting for another dowel invocation` is a stale lock: `make:fast-cli --force`, or remove `.dowel/.dowel.lock`.
9. **Exit `75` means retry.** `dowel start --timeout=N` and connected commands return it while the app is still building; every other non-zero code is a failure.
10. **Nothing writes before the commit.** `plugin:install <name> --dry-run` previews every operation; the real run is atomic and recorded under `.dowel/installed/<plugin>.json`, so `plugin:uninstall` can reverse it. A plugin without an `install.yaml` is registered straight into `.dowel/plugins.json` and needs the scaffold from `dowel install`.

## Tool surface

Substrate tools (the `_safeDowelCommandNames` allowlist in `lib/src/mcp/mcp_server.dart`), always available:

| Family | Tools | Mental model |
|---|---|---|
| Lifecycle | `dowel_start`, `dowel_stop`, `dowel_restart`, `dowel_reload`, `dowel_hot_restart` | Boot, kill, full cycle, or send `r` or `R` to the FIFO; the session file is the side effect |
| Inspect | `dowel_status`, `dowel_logs`, `dowel_doctor`, `dowel_list` | Session JSON, captured log, preflight checks, command catalogue |
| Evaluate | `dowel_tinker { eval: "..." }` | One Dart expression on the main isolate |

Plugin tools appear with the dispatcher entry (rule 1): `tapir_*` from `tapir`, `crumbs_*` from `crumbs`. The server logs `[dowel_mcp] initialized with N tools (M filtered; P plugin + S substrate)` to stderr at boot; `dowel_list` shows the `tapir:` and `crumbs:` namespaces.

Per-tool schema, return shape and errors: `${CLAUDE_SKILL_DIR}/references/mcp-tools.md`. Flags, exit codes and output of the CLI-only commands: `${CLAUDE_SKILL_DIR}/references/cli-commands.md`.

## Picking the path

| Need | Use | Why |
|---|---|---|
| Boot, restart, inspect or evaluate the running app | `dowel_*` tool | One round trip inside the MCP session |
| Read or change live state (singletons, controllers, caches) | `dowel_tinker` | VM Service evaluate, one shot |
| Inspect the semantics tree or drive gestures | `tapir_*` | Actionability-gated driver; pair with tinker for state checks |
| Read HTTP, log and exception buffers | `crumbs_*` | The in-app ring buffers |
| Scaffold a command, plugin or entry | `./bin/dowel make:command`, `make:plugin`, `make:fast-cli` | CLI-only; writes source and regenerates barrels |
| Install or remove a plugin | `./bin/dowel plugin:install <name>` or `plugin:uninstall <name>` | CLI-only; `--dry-run` previews |

## Recipes

First touch of a session:

```text
dowel_doctor     four hard checks (flutter, dart, port 3100, sdk >= 3.30.0); WARN lines are advisory
dowel_status     {"running": false}, or {running, pid, alive, vmServiceUri, device, webPort, startedAt}
dowel_list       confirms which plugin namespaces loaded
```

`running: false` means call `dowel_start` before any connected tool; `alive: false` means the process died, call `dowel_restart`.

Boot, inspect, evaluate:

```text
dowel_start { device: "chrome" }
dowel_status                                        vmServiceUri present, alive: true
dowel_tinker { eval: "WidgetsBinding.instance.lifecycleState.toString()" }
dowel_tinker { eval: "await SharedPreferences.getInstance().then((p) => p.getKeys().toList())" }
```

`device` defaults to `chrome` (web, port 3100); pass `macos` for desktop or an adb serial for Android.

Hot reload after an edit: `dowel_reload`, then `dowel_logs { follow: false }` for the expected line, then `dowel_tinker` to confirm. If reload fails (a const constructor change, a build error during reassemble) use `dowel_hot_restart`; if that fails, `dowel_restart`.

CLI-only work from Bash:

```bash
./bin/dowel make:command MyCommand                   # class plus _index.g.dart refresh
./bin/dowel plugin:install awesome_plugin --dry-run  # preview the plan
./bin/dowel plugin:install awesome_plugin            # commit and refresh the barrel
./bin/dowel plugins:refresh                          # regenerate _plugins.g.dart from .dowel/plugins.json
```

## Recovery

Connected tools soft-fail with `isError: true` text. Branch on the substring:

| Substring | Cause | Next move |
|---|---|---|
| `No Flutter app detected` / ``Run `dowel start` first`` | No session for this project | `dowel_start { device: ... }`, retry |
| `state.json missing or has no vmServiceUri` | `flutter run` crashed during boot | `dowel_restart` |
| session shows `booting: true` | `start` was cut short by its caller; the app is running | Call any connected tool, it recovers the URI from the session log. Do not re-run start or hand-write the file |
| ``Pipe missing: <path>. Run `dowel restart` `` | The FIFO was deleted while the session recorded it | `dowel_restart` |
| `The session has no stdinPipe entry` | The session predates the FIFO or was hand-written | `dowel_restart` |
| `Expression compilation error` / `RPCError(code: 113)` | `eval` is not a single expression | Drop the `;`, collapse to one expression |
| `Isolate sentinel (kind: ...)` | Stale isolate id | Recovers on the next call; if not, `dowel_hot_restart` |
| `mkfifo failed (Windows not yet supported; V1 is POSIX-only)` | `dowel_start` on Windows | Stop and tell the user |
| `Chrome failed to open debug port <port>` | `--cdp-port` in use, or Chrome missing | Pass a free `--cdp-port=<N>` |

A plugin namespace missing from `dowel_list`: check `.mcp.json` runs `./bin/dowel mcp:serve` and not `dart run dowel:mcp`; check `.dowel/plugins.json` lists the plugin and `lib/app/_plugins.g.dart` imports its provider; run `./bin/dowel plugins:refresh`; reconnect the client.

State schema, FIFO model, AOT staleness and every failure: `${CLAUDE_SKILL_DIR}/references/state-and-recovery.md`. Writing a `dowel_tinker` expression (constraints, the `await` wrapper, recipes): `${CLAUDE_SKILL_DIR}/references/tinker-eval.md`.

## Testing

Test a command without a process, a VM or a terminal: build a `DowelContext.bare` over a `MapInput` and a `BufferedOutput`, call `handle`, assert on the exit code and the captured output.

```dart
import 'package:dowel/dowel.dart';
import 'package:test/test.dart';

final class GreetCommand extends DowelCommand {
  @override
  String get signature => 'greet {name} {--shout}';

  @override
  String get description => 'Greet a person by name.';

  @override
  CommandBoot get boot => CommandBoot.none;

  @override
  Future<int> handle(DowelContext context) async {
    context.output.success('Hello, ${context.input.argument('name') ?? 'world'}');
    return 0;
  }
}

void main() {
  test('greet says hello', () async {
    final command = GreetCommand();
    final output = BufferedOutput();
    final context = DowelContext.bare(
      MapInput(
        const <String, dynamic>{'shout': false},
        positional: const ['Ada'],
        signature: command.parsedSignature,
      ),
      output,
    );

    expect(await command.handle(context), 0);
    expect(output.content, contains('Hello, Ada'));
  });
}
```

An installer is tested the same way against `InstallContext.test` with an `InMemoryFs`: stage the operations, assert on `pendingOps`, and commit only when the test is about the written content.
