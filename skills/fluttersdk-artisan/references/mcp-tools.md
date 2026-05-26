# MCP tools reference

Per-tool deep reference for the 10 substrate MCP tools exposed by the
`fluttersdk_artisan` MCP server. The allowlist lives at
`lib/src/mcp/mcp_server.dart:871-882`:

```dart
const Set<String> _safeArtisanCommandNames = <String>{
  'start',
  'stop',
  'status',
  'logs',
  'restart',
  'reload',
  'hot-restart',
  'doctor',
  'list',
  'tinker',
};
```

Substrate tools surface from BOTH the substrate path (`dart run
fluttersdk_artisan:mcp` via `bin/mcp.dart`) and the consumer dispatcher
path (`./bin/fsa mcp:serve` via the host app's `bin/dispatcher.dart`).
Plugin tools (`dusk_*`, `telescope_*`) surface ONLY from the dispatcher
path because the substrate's `bin/mcp.dart` forces
`delegateToConsumer: false` and does not load the consumer's
`lib/app/_plugins.g.dart` barrel.

Every tool returns a `CallToolResult` (per the MCP 2025-06-18 spec) with
either `isError: false` + a text content block, or `isError: true` + a
markdown-formatted error message under `### Error`. Soft-fail is the
contract: protocol-level RPC errors never surface; missing-app /
compile-error / runtime-exception cases all return successful JSON-RPC
responses with `isError: true` text.

## Dispatch model (cross-cutting)

- **Boot modes**: 9 of 10 tools declare `CommandBoot.none` (no VM Service
  required). Only `artisan_tinker` declares `CommandBoot.connected`. The
  MCP server's `_dispatchArtisanCommand` (`lib/src/mcp/mcp_server.dart:770-840`)
  inspects the boot mode and routes accordingly.
- **Lazy-reconnect**: connected tools check `_vmClient == null` before
  dispatch. If null, `_lazyReconnect()` re-reads state.json, opens the
  WebSocket, resolves the main isolate id, and caches the client.
  Concurrent calls coalesce on a memoized `_reconnecting` future
  (`lib/src/mcp/mcp_server.dart:248-266`).
- **Output envelope**: substrate handlers write to a `BufferedOutput`;
  the MCP dispatcher reads `stdout` + `stderr` after the handler returns
  and packs them into a single `TextContent` block prefixed with
  `` `# `artisan <cmd>` exit <code>` ``.
- **No protocol errors**: every failure (no app, runtime exception, FIFO
  missing) returns `{ "content": [{ "type": "text", "text": "..." }],
  "isError": true }`. Never `{ "error": { "code": ... } }`.

## artisan_start

- **Maps to CLI**: `start`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/start_command.dart:197`
- **MCP descriptor**: `lib/src/mcp/mcp_server.dart` (description block in
  `_mcpDescriptionFor`, input schema in `_commandInputSchema`)

**Description (verbatim)**:

> Boot a Flutter app in detached mode and record its VM Service URI for
> downstream tools.
>
> Spawns `flutter run -d <device>` as a background process and writes the
> resulting VM Service URI + pid + web port to `~/.artisan/state.json`.
> Other tools (`artisan_status`, `artisan_logs`, `dusk_*`,
> `telescope_*`, `tinker_eval`) read this state file to find the running
> app. ONLY ONE Flutter app per machine can be tracked at a time
> (single-slot state).
>
> Usage:
> - Call this BEFORE invoking any plugin tool (`dusk_snap`,
>   `telescope_tail`, `tinker_eval`) that needs VM Service access.
> - Default device is the first available; pass `device: "chrome"` for
>   web (port 3100), `device: "macos"` for desktop, or
>   `device: "<serial>"` for a connected mobile.
> - Returns immediately once the VM Service URI is captured; the Flutter
>   process keeps running in the background.
> - To stop call `artisan_stop`. To full-cycle restart call
>   `artisan_restart`. For source-change reload call `artisan_reload`
>   (state preserved) or `artisan_hot_restart` (state dropped).
> - Fails with "another app is recorded" when state.json already has a
>   running pid; call `artisan_stop` first.

**Input schema**:

```json
{
  "type": "object",
  "properties": {
    "device":            { "type": "string",  "description": "chrome | macos | linux | <adb-serial>. Omit for `flutter devices` first." },
    "port":              { "type": "string",  "description": "Web port for the chrome device. Default 3100. Ignored for non-web." },
    "vm-service-port":   { "type": "string",  "description": "Host VM Service port. Default 8181." },
    "dds":               { "type": "boolean", "description": "Enable Dart Development Service proxy. Default false." },
    "profile-static":    { "type": "boolean", "description": "Run flutter in --profile mode (no hot reload). Default false." }
  }
}
```

**Returns on success**:

```
# `artisan start` exit 0
Spawned flutter run (pid=12345).
VM Service: ws://127.0.0.1:8181/<token>/ws
Recorded to ~/.artisan/state.json
```

**Returns on error**:

```
# `artisan start` exit 1
### Error
another app is recorded (pid=12345). Run `artisan stop` first.
```

Other documented error messages: `Failed to capture child PIDs from start
wrapper`, `Timed out after 90s waiting for VM Service URI`,
`--cdp-port expects an integer port number, got "..."`,
`--cdp-port requires --device=chrome or --device=web-server`,
`Flutter SDK <X> is older than 3.30.0` (CDP path),
`Chrome binary not found` (CDP path),
`mkfifo failed (Windows not yet supported; V1 is POSIX-only)`.

**Agent recipes**:

```
artisan_start { device: "chrome" }                  # web, port 3100
artisan_start { device: "macos" }                   # desktop
artisan_start { device: "emulator-5554" }           # Android emulator
artisan_start { device: "chrome", port: "3200" }    # alt web port
```

## artisan_stop

- **Maps to CLI**: `stop`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/stop_command.dart:56`

**Description (verbatim)**:

> Stop the currently-running Flutter app and clear its state file.
>
> Sends SIGTERM to the `flutter run` process recorded in
> `~/.artisan/state.json`, then deletes the state file. Safe to call when
> no app is running (returns success, no-op).
>
> Usage:
> - Call after development is done OR before `artisan_start` if the
>   previous app process is stale.
> - No-op when `~/.artisan/state.json` is absent; never errors on
>   missing state.

**Input schema**: `{ "type": "object", "properties": {} }`

**Returns on success (app running)**:

```
# `artisan stop` exit 0
Sent SIGTERM to pid=12345.
state.json removed.
```

**Returns on success (no app)**:

```
# `artisan stop` exit 0
No state file; nothing to stop.
```

**Notes**:

- Idempotent: always exit 0 except for catastrophic file-system errors.
- Also SIGTERMs the FIFO holder pid, deletes the FIFO file, and (on the
  CDP path) reaps the Chrome process with a 2s grace period before SIGKILL.
- Errors mid-cleanup are logged as warnings and swallowed; the command
  still returns exit 0.

## artisan_status

- **Maps to CLI**: `status`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/status_command.dart:21`

**Description (verbatim)**:

> Return the JSON status of the recorded Flutter app.
>
> Reads `~/.artisan/state.json` and reports pid, vmServiceUri, device,
> webPort, profile, startedAt. Also probes whether the recorded pid is
> still alive (process may have crashed without cleaning state).
>
> Usage:
> - Use to discover the VM Service URI before manually connecting other
>   tooling, or to confirm `artisan_start` succeeded.
> - Returns `{"running": false}` when no state file exists.

**Input schema**: `{ "type": "object", "properties": {} }`

**Returns on success (app running)**:

```json
{
  "running": true,
  "pid": 12345,
  "alive": true,
  "vmServiceUri": "ws://127.0.0.1:8181/<token>/ws",
  "webPort": 3100,
  "startedAt": "2026-05-26T10:30:45.123Z",
  "device": "chrome"
}
```

**Returns on success (no app)**:

```json
{"running": false}
```

**Returns on success (stale pid)**:

```json
{
  "running": true,
  "pid": 12345,
  "alive": false,
  ...
}
```

**Notes**:

- Always exit 0; never raises. The JSON is the entire payload.
- `alive` is a `kill -0 <pid>` (POSIX) / `tasklist /FI "PID eq <pid>"`
  (Windows) probe via `lib/src/console/process_alive.dart:17-27`.
- `alive: false` means the recorded pid is dead; state.json was not
  cleaned up. Recovery: `artisan_restart` (or `artisan_stop` + manual
  re-`start`).

## artisan_logs

- **Maps to CLI**: `logs`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/logs_command.dart:27`

**Description (verbatim)**:

> Read the captured `flutter run` log output.
>
> Reads the stdout/stderr captured by the background Flutter process
> started via `artisan_start`. Returns recent lines OR tails the live
> stream with `follow: true`.
>
> Usage:
> - Pass `follow: true` to tail until interrupted; default returns the
>   most recent buffered lines.
> - Returns empty when no app has been started yet.

**Input schema**:

```json
{
  "type": "object",
  "properties": {
    "follow": {
      "type": "boolean",
      "description": "Tail the live stream until the client disconnects. Default false."
    }
  }
}
```

**Returns on success**:

```
# `artisan logs` exit 0
[contents of ~/.artisan/flutter-dev.log]
```

**Returns on error (no log file)**:

```
# `artisan logs` exit 1
### Error
Log file not found at ~/.artisan/flutter-dev.log. Run `artisan start` first.
```

**Notes**:

- `follow: true` polls the log file every 250ms and streams deltas; the
  call does NOT return until the client closes the channel.
- For long-running tails over MCP, prefer `follow: false` + repeated
  one-shot calls; some MCP clients buffer the entire response and only
  surface it on completion.

## artisan_restart

- **Maps to CLI**: `restart`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/restart_command.dart:19`

**Description (verbatim)**:

> Stop and re-start the running Flutter app preserving the same device.
>
> Convenience wrapper around `artisan_stop` + `artisan_start`. Slower
> than `artisan_reload` (which preserves Dart state) and
> `artisan_hot_restart` (which keeps the process alive but drops state).
> Only use when the others cannot apply the change (native plugin added,
> pubspec dep change).
>
> Usage:
> - No parameters; uses the device + flags from the prior `artisan_start`.
> - Reuses the same VM Service port + web port when possible.

**Input schema**: `{ "type": "object", "properties": {} }`

**Returns on success**:

```
# `artisan restart` exit 0
Sent SIGTERM to pid=12345.
state.json removed.
Spawned flutter run (pid=67890).
VM Service: ws://127.0.0.1:8181/<new-token>/ws
Recorded to ~/.artisan/state.json
```

**Notes**:

- Composite: invokes `StopCommand().handle(ctx)` then
  `StartCommand().handle(ctx)` sequentially. Reads the device from
  state.json BEFORE the stop.
- Slowest of the three reload verbs because the process must fully
  terminate and respawn (~5-15s on web, depending on Flutter startup).
- Use when: native plugin added, pubspec dependency changed,
  `lib/main.dart` initialization corrupted, isolate id needs a complete
  reset.

## artisan_reload

- **Maps to CLI**: `reload`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/reload_command.dart:32`

**Description (verbatim)**:

> Hot reload the running Flutter app.
>
> Sends `r` to the `flutter run` process stdin via the recorded FIFO
> pipe. Triggers Flutter's hot reload: Dart state is preserved, the
> widget tree rebuilds with the new source. The standard fast-iteration
> verb during Flutter development.
>
> Usage:
> - Call after every meaningful source edit to see the change immediately.
> - If hot reload fails (state mismatch, breaking source change), Flutter
>   logs the error to the captured output; check `artisan_logs` and
>   consider `artisan_hot_restart` instead.
> - Returns the response Flutter wrote back to stdin (typically blank
>   on success).

**Input schema**: `{ "type": "object", "properties": {} }`

**Returns on success**:

```
# `artisan reload` exit 0
Sent `r` (reload) to flutter run stdin.
```

**Returns on error (no state)**:

```
# `artisan reload` exit 2
### Error
No state file; nothing to reload. Run `artisan start` first.
```

**Returns on error (FIFO missing)**:

```
# `artisan reload` exit 2
### Error
Pipe missing: ~/.artisan/flutter-dev.fifo. Run `artisan restart`.
```

**Returns on error (older artisan state)**:

```
# `artisan reload` exit 2
### Error
state.json has no stdinPipe entry; the app was started by an older artisan that pre-dates the FIFO refactor. Run `artisan restart`.
```

**Notes**:

- Writes `r\n` to the FIFO via shell redirection (`printf %s 'r\n' >
  <fifo>`). Dart `File.open` rejects FIFOs because it calls `lseek`.
- POSIX only. On Windows, `artisan_start` fails at `mkfifo` so this tool
  never reaches a usable FIFO.
- Hot reload preserves Dart state and the same isolate id. The next
  `artisan_tinker` call hits the same isolate as before the reload.

## artisan_hot_restart

- **Maps to CLI**: `hot-restart`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/hot_restart_command.dart:32`

**Description (verbatim)**:

> Hot restart the running Flutter app (drops Dart state, keeps process).
>
> Sends `R` to the `flutter run` process stdin. Stronger than
> `artisan_reload`: drops all Dart state but keeps the same process +
> VM Service connection. Use when hot reload cannot apply the change
> (const constructors changed, top-level state corrupted).
>
> Usage:
> - Slower than `artisan_reload`; faster than `artisan_restart` (no
>   process re-spawn).
> - Call when source changes invalidate existing app state but the
>   process itself is fine.
> - Preserves the recorded VM Service URI; downstream tooling stays
>   connected.

**Input schema**: `{ "type": "object", "properties": {} }`

**Returns on success**:

```
# `artisan hot-restart` exit 0
Sent `R` (hot-restart) to flutter run stdin.
```

**Notes**:

- Identical FIFO mechanics to `artisan_reload`; sends `R\n` (capital R).
- Mints a new isolate id. `VmServiceClient.callServiceExtension` catches
  the resulting `SentinelException` once and refreshes via
  `getMainIsolateId()`, so the next `artisan_tinker` call self-recovers.
- Error envelope identical to `artisan_reload` (exit 2 for missing state
  / FIFO).

## artisan_doctor

- **Maps to CLI**: `doctor`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/doctor_command.dart:84`

**Description (verbatim)**:

> Run preflight environment checks for Flutter development.
>
> Verifies: `flutter` on PATH, `dart` on PATH, default ports free (e.g.
> 3100 for chrome web). Reports each check as `✓` / `✗` with the
> underlying command output. Exits non-zero when any hard check fails.
>
> Usage:
> - Run this when setup feels broken OR before starting a new
>   development session on an unfamiliar machine.
> - Stale `.mcp.json` entries pointing at the removed `fluttersdk_mcp`
>   package surface here as a WARN (advisory; not a hard failure).

**Input schema**: `{ "type": "object", "properties": {} }`

**Returns on success (all checks pass)**:

```
# `artisan doctor` exit 0
  ✓ flutter --version
  ✓ dart --version
  ✓ port 3100 free
  ✓ flutter sdk >= 3.30.0 (for --cdp-port)
```

**Returns on success with advisory WARN**:

```
# `artisan doctor` exit 0
  ✓ flutter --version
  ✓ dart --version
  ✓ port 3100 free
  ✓ flutter sdk >= 3.30.0 (for --cdp-port)
WARN: Stale MCP entry detected. Pre-upgrade .mcp.json points at the removed fluttersdk_mcp package. Run: ./bin/fsa mcp:install (or: dart run fluttersdk_artisan mcp:install) to refresh the entry.
```

**Returns on error (any hard check fails)**:

```
# `artisan doctor` exit 1
  ✓ flutter --version
  ✗ dart --version
  ✓ port 3100 free
  ✓ flutter sdk >= 3.30.0 (for --cdp-port)
```

**Hard checks** (`lib/src/commands/doctor_command.dart:84-98`):

| Check | Pass when | Fail when |
|---|---|---|
| `flutter --version` | `Process.run('flutter', ['--version'])` exit 0 | exit != 0 or exception |
| `dart --version` | `Process.run('dart', ['--version'])` exit 0 | exit != 0 or exception |
| `port 3100 free` | `lsof -ti tcp:3100` stdout empty (or skip on Windows) | Process listening on 3100 |
| `flutter sdk >= 3.30.0` | `flutter --version --machine` `frameworkVersion >= 3.30.0` | Older version or parse failure |

**Advisory WARN lines** (emit but DO NOT change exit code):

- `WARN: Stale MCP entry detected.` (pre-upgrade `.mcp.json` points at
  removed `fluttersdk_mcp` package).
- `WARN: Pre-fix MCP entry detected.` (`.mcp.json` uses pre-Bug-B args
  shape).
- `WARN: Flutter SDK is older than 3.30.0.` (CDP commands require
  flutter/flutter#170612).

## artisan_list

- **Maps to CLI**: `list`
- **Boot mode**: `none`
- **Handler**: `lib/src/commands/list_command.dart:29`

**Description (verbatim)**:

> List every registered artisan command grouped by namespace.
>
> Returns the full CLI command surface available to the consumer app:
> builtins (start, stop, doctor, etc.), plugin commands (`dusk:*`,
> `telescope:*`, `plugin:*`), `make:*` generators, `mcp:*` meta. Useful
> for discovering what is available without inspecting source.
>
> Usage:
> - No parameters; returns plain text grouped by `:` namespace.
> - The total command count appears at the top so plugin loading can be
>   sanity-checked at a glance.

**Input schema**: `{ "type": "object", "properties": {} }`

**Returns on success**:

```
# `artisan list` exit 0

Available commands (60):

  doctor                          Run environment preflight checks (flutter, dart, port availability).
  help                            Show detailed help for a single command.
  hot-restart                     Hot restart the running Flutter app (drops Dart state, keeps process).
  install                         Bootstrap the consumer scaffold (dispatcher + barrels + ./bin/fsa).
  list                            List every registered command grouped by namespace.
  reload                          Hot reload the running Flutter app.
  restart                         Stop and re-start the running Flutter app preserving the same device.
  start                           Boot a Flutter app in detached mode and record its VM Service URI.
  status                          Print JSON status of the recorded flutter app.
  stop                            Stop the currently-running Flutter app and clear its state file.
  tinker                          Evaluate a Dart expression in the running isolate.

 commands
  commands:refresh                Regenerate lib/app/commands/_index.g.dart from filesystem scan.

 dusk
  dusk:snap                       Capture the widget tree + device screenshot.
  dusk:tap                        Tap a widget at a semantic path.
  ...

 make
  make:command                    Scaffold an ArtisanCommand subclass.
  make:fast-cli                   Scaffold a fast AOT-compiled CLI.
  make:plugin                     Scaffold a plugin package structure.

 mcp
  mcp:install                     Write .mcp.json fluttersdk entry.
  mcp:serve                       Boot the stdio MCP server.
  mcp:uninstall                   Remove .mcp.json fluttersdk entry.

 plugin
  plugin:install                  Register a plugin + run install.yaml manifest.
  plugin:uninstall                Reverse a plugin install.

 plugins
  plugins:refresh                 Regenerate lib/app/_plugins.g.dart from .artisan/plugins.json.

 telescope
  telescope:tail                  Tail live HTTP requests from the running app.
  ...
```

**Notes**:

- Always exit 0; never fails.
- Use the namespace headers (`dusk`, `telescope`, `make`, `plugin`,
  `mcp`) to confirm which plugins surfaced. Missing `dusk:` or
  `telescope:` namespace indicates the dispatcher path is not wired
  (see `${CLAUDE_SKILL_DIR}/references/state-and-recovery.md` for the
  MCP boot path comparison).

## artisan_tinker

- **Maps to CLI**: `tinker --eval=<expr>`
- **Boot mode**: `connected` (requires `~/.artisan/state.json` with
  `vmServiceUri`)
- **Handler**: `lib/src/commands/tinker_command.dart:35`

**Description (verbatim)**:

> Evaluate a Dart expression inside the running Flutter app via the
> VM Service `evaluate` RPC.
>
> Compiles `eval` in the scope of the app's root library and returns the
> result as text. Has full access to anything imported by
> `lib/main.dart`: top-level functions, singletons, services. The
> expression may be a simple lookup
> (`WidgetsBinding.instance.lifecycleState`), a method call
> (`MyService.instance.refresh()`), or any single Dart expression
> including `await`.
>
> Usage:
> - Use to INSPECT live app state without rebuilding the UI (current
>   user, active controllers, cache contents).
> - Use to TRIGGER an action programmatically (call a method, fire an
>   event, mutate a singleton) without going through the UI surface.
> - Requires an artisan-managed running app: call `artisan_start` first
>   so `~/.artisan/state.json` records the VM Service URI.
> - Errors (compile, runtime, breakpoints) surface as the evaluate RPC's
>   error response; the model receives the error text and can self-correct.

**Input schema**:

```json
{
  "type": "object",
  "properties": {
    "eval": {
      "type": "string",
      "description": "Dart expression to evaluate in the running app's root library (e.g. `WidgetsBinding.instance.lifecycleState`, `MyService.instance.refresh()`, `1+1`). The expression runs in the foreground isolate, `await` is auto-wrapped, and the formatted result returns as text. Required."
    }
  },
  "required": ["eval"]
}
```

**Returns on success (primitive)**:

```
# `artisan tinker` exit 0
42
```

**Returns on success (complex object)**:

```
# `artisan tinker` exit 0
<MyState#a3f9>
```

(Append `.toString()` inside the expression for readable state. See
`${CLAUDE_SKILL_DIR}/references/tinker-eval.md` for the recipe.)

**Returns on error (compile error)**:

```
# `artisan tinker` exit 1
### Error
Expression compilation error: Expected an identifier, but got ';'.
```

**Returns on error (runtime exception)**:

```
# `artisan tinker` exit 1
### Error
Runtime exception: NoSuchMethodError: The getter 'foo' was called on null.
```

**Returns on error (no app)**:

```
# `artisan tinker` exit 1
### Error
Not connected to a running Flutter app. Run `dart run fluttersdk_artisan start` first so `~/.artisan/state.json` records the VM Service URI.
```

**Notes**:

- Only substrate tool with `CommandBoot.connected`. The MCP dispatcher
  detects this at `lib/src/mcp/mcp_server.dart:794-820` and triggers
  lazy-reconnect when `_vmClient == null`.
- The expression is auto-wrapped in `(() async => <expr>)()` whenever
  the source string contains `await` (`lib/src/vm/vm_service_client.dart:155-157`).
  This is transparent: write `await Foo.bar()` and tinker handles the
  async wrapping.
- Single expression only. Trailing `;` and multi-statement blocks raise
  `RPCError(code: 113, "Expression compilation error")`.
- Scope is the app's `rootLib` (resolved from `getIsolate(...)`); top-level
  symbols and imported libraries are in scope. Instance members of
  `this` are NOT in scope (no implicit receiver in evaluate context).

**Agent recipes**:

```
artisan_tinker { eval: "WidgetsBinding.instance.lifecycleState.toString()" }
artisan_tinker { eval: "MyService.instance.state.toString()" }
artisan_tinker { eval: "await MyService.instance.refresh()" }
artisan_tinker { eval: "(MyService.instance..reset()).state.toString()" }     # cascade: side-effect + read
artisan_tinker { eval: "MyService.instance.notify('event'), 'dispatched'" }   # comma operator for void side-effect
```

Generic placeholders (`MyService`, `MyState`) stand in for whatever the
host app's singleton naming is. When the optional `magic` package is
installed the equivalent expressions use `Magic.find<T>()` for resolution.

Deep recipe pack, scope rules, error path branching:
`${CLAUDE_SKILL_DIR}/references/tinker-eval.md`.

## Plugin-tool surface (when dispatcher path wired)

Plugin tools are NOT substrate tools; they live in plugin packages and
are collected by the MCP server only when the dispatcher wrapper loads
the consumer's `lib/app/_plugins.g.dart`. Common companion plugins:

| Plugin | Prefix | Skill |
|---|---|---|
| `fluttersdk_dusk` (E2E driver) | `dusk_*` | the `fluttersdk-dusk` skill, bundled with the dusk package |
| `fluttersdk_telescope` (runtime inspector) | `telescope_*` | the `fluttersdk-telescope` skill, bundled with the telescope package |

The artisan skill does not duplicate the per-plugin tool reference; load
the matching plugin's skill when calling its tools.

## Cross-cutting: dispatch + error envelopes

**Dispatch routing** (`lib/src/mcp/mcp_server.dart:231-309`):

1. Tool name starts with `artisan:` prefix (substrate) → in-process
   handler via `_dispatchArtisanCommand`. Connected commands go through
   the lazy-reconnect path; `none` commands run with `ArtisanContext.bare()`.
2. Tool name does NOT start with `artisan:` (plugin) → dispatch via
   `vmClient.callServiceExtension<Object?>()` (the VM Service extension
   the plugin registered at app boot).
3. Special case: `dusk_evaluate` → routes through `vm.evaluate` directly
   (`_dispatchEvaluate`, lines 319-417), not the plugin extension.

**Error envelope** (uniform across every tool):

```json
{
  "content": [{ "type": "text", "text": "### Error\n<message>" }],
  "isError": true
}
```

The `### Error\n` prefix is the contract the skill recovery table at
`SKILL.md` § 5 branches on. Tools never return JSON-RPC protocol errors
for application-level failures; protocol errors only arise for malformed
tool calls (unknown tool, schema violation) and surface from `dart_mcp`
itself.

**`dusk_evaluate` error branches** (`lib/src/mcp/mcp_server.dart:319-417`):

| Branch | Trigger | Message prefix |
|---|---|---|
| InstanceRef success | normal return | (no error; JSON value in content) |
| ErrorRef | runtime exception | `Runtime exception: <message>` |
| SentinelException | stale isolate after hot-restart | `Isolate sentinel (kind: ...)` |
| RPCError code 113 | compile error | `Expression compilation error: ...` |
| Other RPCError | DDS/transport failure | `VM Service RPC error (code <N>): ...` |
| Unexpected exception | catch-all | `Unexpected error during dusk_evaluate: ...` |

## Filter mechanics

Tools can be denied by a 3-layer filter (`lib/src/mcp/mcp_filter_config.dart`):

1. `.artisan/mcp.json` file (lowest precedence)
2. `ARTISAN_MCP_PACKAGES_ALLOW` / `_DENY` / `ARTISAN_MCP_TOOLS_ALLOW` / `_DENY`
   env vars (CSV)
3. `mcp:serve` CLI flags: `--include-package`, `--exclude-package`,
   `--include-tool`, `--exclude-tool` (highest precedence)

Allow lists: CLI > env > file (first non-null wins, replace not merge).
Deny lists: union across all three (deny anywhere wins everywhere).

Denied tools are filtered at initialize time BEFORE `registerTool`, so
they never appear in `tools/list`. Calling a denied tool returns
dart_mcp's native "No tool registered with the name <X>" error.

Changing the filter (file or env) requires a client reconnect; the MCP
server does NOT auto-reload mcp.json in V1.
