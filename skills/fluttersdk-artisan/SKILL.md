---
name: fluttersdk-artisan
description: "fluttersdk_artisan: Dart CLI framework + stdio MCP server that lets an LLM agent boot, inspect, hot-reload, and evaluate a running Flutter app via 10 substrate MCP tools (`artisan_*`) and 21 builtin CLI commands (`./bin/fsa`). `~/.artisan/state.json` carries the running app's pid + VM Service URI + FIFO pipe; lazy-reconnect picks it up after `artisan_start`. Plugin tools (`dusk_*`, `telescope_*`) surface ONLY via `./bin/fsa mcp:serve` (dispatcher path), not `dart run fluttersdk_artisan:mcp` (substrate-only). TRIGGER when: any `artisan_*` MCP call, `./bin/fsa` or `dart run artisan` invocation, `.artisan/state.json` / `bin/dispatcher.dart` / `_plugins.g.dart` mention, or the user asks to start / stop / restart / reload / hot-restart / inspect / tinker a Flutter app. DO NOT TRIGGER on plugin authoring (install.yaml / PluginInstaller DSL) or pure `dart test` without driving the app."
version: 0.0.2
when_to_use: "Any task where the agent boots, restarts, inspects, or evaluates a running Flutter app via artisan: calling `artisan_*` MCP tools (start, status, doctor, tinker, hot-restart) in sequence, invoking `./bin/fsa <cmd>` from Bash, recovering from missing state.json or stale PID, picking substrate vs dispatcher MCP wiring, choosing between `artisan_tinker` (VM Service evaluate) and `dusk_evaluate` (E2E driver) for an inspect-or-mutate flow."
---

<!-- fluttersdk_artisan v0.0.5 | Skill updated: 2026-05-26 | Source: https://github.com/fluttersdk/artisan -->

# fluttersdk_artisan

CLI framework and stdio MCP server for Flutter dev loops, designed for LLM
agents. The running app exposes a process + VM Service surface plus an MCP
server; the agent calls `artisan_*` tools (or `./bin/fsa <cmd>` from a
shell) to start the app, hot-reload it, read its logs, evaluate Dart
expressions against the running isolate, and discover what other plugin
tools (`dusk_*`, `telescope_*`) are available, all without leaving the
conversation.

This skill assumes the host app already has artisan installed
(`bin/dispatcher.dart` present, `lib/app/_plugins.g.dart` non-empty,
`.mcp.json` wired). If not, run `dart pub add fluttersdk_artisan` followed
by `dart run fluttersdk_artisan install` once from the app root, then
`./bin/fsa mcp:install` to write the MCP entry, then reconnect the client.

## 1. Core Laws

1. **Two MCP boot paths produce two different tool catalogs.** The substrate
   entry `dart run fluttersdk_artisan:mcp` (via `bin/mcp.dart` of the
   artisan package) forces `delegateToConsumer: false` and surfaces ONLY the
   10 substrate tools (`artisan_start`, `artisan_stop`, ...,
   `artisan_tinker`). The consumer dispatcher entry `./bin/fsa mcp:serve`
   (via `bin/dispatcher.dart` of the host app) loads
   `lib/app/_plugins.g.dart` and surfaces substrate tools PLUS every
   plugin's `mcpTools()` (`dusk_*` from `fluttersdk_dusk`, `telescope_*`
   from `fluttersdk_telescope`, etc.). Inspect `.mcp.json` to see which
   path is wired; `./bin/fsa mcp:serve` is the dev default. Diagnose a
   missing plugin namespace by calling `artisan_list`: `dusk:` /
   `telescope:` groups appear only when the dispatcher wrapper loaded the
   provider.

2. **State lives at `~/.artisan/state.json`, and it is the single source of
   truth for connectedness.** `artisan_start` writes it atomically (pid +
   `vmServiceUri` + FIFO path + device + ports). Every connected tool
   reads it on dispatch. When absent, the soft-fail contract holds:
   `artisan_status` returns `{"running": false}`, `artisan_stop` no-ops
   (exit 0), `artisan_tinker` and any plugin tool that needs the VM
   Service return `isError: true` with an actionable "Run `artisan start`
   first" message. The MCP server stays online either way; failed calls
   do not kill the session.

3. **Lazy-reconnect makes "start then immediately tinker" work without a
   client reconnect.** The MCP server reads state.json eagerly at
   initialize, but it does NOT refuse to register tools when state.json
   is absent. The next call to any connected tool re-reads state.json
   via `_lazyReconnect()`, opens the VM Service WebSocket, and resolves
   the main isolate id. Concurrent calls coalesce on the same in-flight
   future (memoized `_reconnecting`), so a burst of tool calls right
   after `artisan_start` triggers exactly one connect.

4. **Hot-restart auto-refreshes the isolate id; hot-reload preserves it.**
   `artisan_reload` (lower-case `r` over FIFO) keeps Dart state and the
   same isolate id. `artisan_hot_restart` (capital `R`) mints a new
   isolate id. `VmServiceClient.callServiceExtension` catches
   `SentinelException` once, re-resolves the main isolate id via
   `getMainIsolateId()`, and retries; the agent never has to manually
   reconnect after a hot restart. After `artisan_hot_restart`, the next
   `artisan_tinker` call automatically picks up the new isolate.

5. **`artisan_tinker` accepts ONE expression, not a statement.** The
   underlying `vm_service` `evaluate` RPC compiles a single Dart
   expression against the app's root library. Trailing semicolons,
   multi-statement blocks, `import` directives, top-level declarations,
   and function definitions all raise `RPCError(code: 113,
   "Expression compilation error")`. Bare `await` is allowed because
   artisan auto-wraps the expression in `(() async => <expr>)()` whenever
   the source string contains `await`. For non-primitive return values,
   append `.toString()` INSIDE the expression or the result renders as
   `<ClassName#id>` instead of readable state.

6. **CLI and MCP reach the same handlers; the allowlist is the gap.** Only
   10 of the 21 builtin commands surface as MCP tools (lifecycle quartet
   plus `status`, `logs`, `restart`, `doctor`, `list`, `tinker`). The
   other 11 are CLI-only: `help`, `install`, `make:command`,
   `make:fast-cli`, `make:plugin`, `commands:refresh`, `plugins:refresh`,
   `plugin:install`, `plugin:uninstall`, `mcp:serve`, `mcp:install`.
   They are excluded because they mutate source on disk (use the agent's
   file tools instead), need a TTY (interactive prompts), recurse into
   the MCP server (`mcp:serve`), or are meta-config (`mcp:install`).
   Drop to Bash for any of those: `./bin/fsa <cmd>` (fastest; native
   AOT, ~110ms warm) or `dart run artisan <cmd>` (fallback; ~3s).

7. **FIFO control of reload / hot-restart is POSIX-only.** `start` creates
   a named pipe (`~/.artisan/flutter-dev.fifo`) via `mkfifo` and spawns
   two background processes: a HOLDER (`tail -f /dev/null > fifo`) that
   keeps the write end open, plus FLUTTER (`nohup flutter run ... <
   fifo`) that reads keystrokes from stdin. `artisan_reload` and
   `artisan_hot_restart` send `r\n` / `R\n` via `printf %s '...' >
   <fifo>` (shell redirection; Dart `File.open` rejects FIFOs because it
   issues `lseek`). Windows is unsupported in V1; `mkfifo` throws
   `StateError('mkfifo failed (Windows not yet supported; V1 is
   POSIX-only): ...')`.

8. **`./bin/fsa` is an AOT cache and self-rebuilds on staleness.** The
   wrapper rebuilds (~5s, `dart build cli`) when any of these holds: the
   dispatcher binary at `.artisan/cli-bundle/bundle/bin/dispatcher` is
   missing, `.artisan/build.stamp` is empty or missing, the stamp's
   `pubspec.lock hash : dart --version` key mismatches, or
   `pubspec.yaml` is newer than `pubspec.lock` (un-run `pub get`).
   When `./bin/fsa` says `waiting for another fsa invocation`, the
   PID-aware lock probe should reclaim a stale lock dir automatically;
   if it does not, `rm -rf .artisan/.fsa.lock` + retry.

## 2. Tool surface (10 substrate tools, +N plugin tools when dispatcher-wired)

Substrate tools always available (allowlist at
`lib/src/mcp/mcp_server.dart:871-882`):

| Family | Tools | Boot mode | Mental model |
|---|---|---|---|
| Lifecycle | `artisan_start`, `artisan_stop`, `artisan_restart`, `artisan_reload`, `artisan_hot_restart` | `none` | Boot, kill, full-cycle, or send `r` / `R` to the FIFO. State.json is the side effect. |
| Inspect | `artisan_status`, `artisan_logs`, `artisan_doctor`, `artisan_list` | `none` | JSON state (`status`), captured stdout (`logs`), preflight gates (`doctor`), command catalog (`list`). |
| Evaluate | `artisan_tinker { eval: "..." }` | `connected` | One Dart expression compiled in the root library's scope, evaluated on the main isolate. |

Plugin tools surface when the dispatcher wrapper is wired and the
relevant plugin packages are installed:

| Plugin (when installed) | Prefix | Skill |
|---|---|---|
| `fluttersdk_dusk` | `dusk_*` | the `fluttersdk-dusk` skill, bundled with the dusk package |
| `fluttersdk_telescope` | `telescope_*` | the `fluttersdk-telescope` skill, bundled with the telescope package |

Confirm the live tool count after MCP boot by reading the server's stderr
(logged as `[fluttersdk_artisan_mcp] initialized with N tools
(M filtered; <P> plugin + <S> substrate)`), or call `artisan_list` and
look for `dusk:` / `telescope:` namespaces.

Per-tool input schema, return shape, error envelope, and example calls:
`${CLAUDE_SKILL_DIR}/references/mcp-tools.md`. CLI flags, exit codes, and
output shapes for the 11 CLI-only commands:
`${CLAUDE_SKILL_DIR}/references/cli-commands.md`.

## 3. The four agent loops

### A. First-touch discovery (every fresh session)

```
1. artisan_doctor       Run 4 hard preflight checks (flutter, dart, port 3100,
                        sdk >= 3.30.0). WARN lines are advisory; only ✗ on a
                        hard check blocks.
2. artisan_status       {"running": false} or {running, pid, alive, vmServiceUri,
                        device, webPort, startedAt}.
3. artisan_list         Grouped command catalog. Confirms which plugin namespaces
                        surface (dusk: / telescope:).
```

Branch on `status`:
- `{"running": false}` → call `artisan_start` before any connected tool.
- `{"running": true, "alive": true, ...}` → straight to plugin or tinker calls.
- `{"running": true, "alive": false, ...}` → process died; call `artisan_restart`.

### B. Boot + inspect + evaluate

```
1. artisan_start { device: "chrome" }
   Writes state.json; blocks until VM Service URI captured (90s timeout).
2. artisan_status
   Confirm vmServiceUri present + alive: true.
3. artisan_tinker { eval: "WidgetsBinding.instance.lifecycleState.toString()" }
4. <reason about state>
5. artisan_tinker { eval: "await SharedPreferences.getInstance().then((p) => p.getKeys().toList())" }
   The `await` is auto-wrapped in (() async => ...)().
6. artisan_tinker { eval: "MyController.instance.state.toString()" }
```

Step 1's `device` defaults to whatever `flutter devices` returns first;
pass `chrome` for web (default port 3100), `macos` for desktop,
`<adb-serial>` for Android. The VM Service URI surfaces in state.json
before `artisan_start` returns.

### C. Hot reload after a source edit

```
1. <edit lib/views/whatever.dart, save>
2. artisan_reload                      Send 'r\n' over FIFO; Dart state preserved.
3. artisan_logs { follow: false }      Check for the expected post-reload log line.
4. artisan_tinker { eval: "..." }      Confirm controller behaves as expected.
```

When reload fails (const constructor change, top-level state corrupted,
build error during reassemble), switch to `artisan_hot_restart` (capital
`R`, drops Dart state). When THAT fails, `artisan_restart` (full stop +
start cycle, slowest).

### D. Drop-to-Bash for CLI-only commands

```bash
./bin/fsa make:command MyCommand                    # codegen + auto _index.g.dart refresh
./bin/fsa plugin:install awesome_plugin --dry-run    # preview manifest plan
./bin/fsa plugin:install awesome_plugin              # commit + refresh barrel
./bin/fsa plugins:refresh                            # regenerate _plugins.g.dart from .artisan/plugins.json
./bin/fsa list                                       # grouped command catalog (same payload as artisan_list)
```

`./bin/fsa` is the fastest form (~110ms warm). When the AOT bundle is
stale the wrapper rebuilds in ~5s before exec. Cross-platform fallback:
`dart run artisan <cmd>` (~3s, runs through `bin/dispatcher.dart`).
Substrate-only fallback (no plugins): `dart run fluttersdk_artisan <cmd>`
(~3s, plugin providers NOT loaded; useful for debugging the artisan
substrate itself).

## 4. Picking the right path

| Need | Use | Why |
|---|---|---|
| Boot / restart / inspect / evaluate the running app | `artisan_*` MCP tool | One round-trip; agent stays inside the MCP session. |
| Inspect or mutate live state (singletons, controllers, Cache) | `artisan_tinker` | VM Service `evaluate`; works mid-session; one-shot. |
| Inspect the UI semantics tree, gesture against widgets | `dusk_*` (when dispatcher path wired) | E2E driver with actionability gate; pair with tinker for state checks. |
| Tail HTTP / log / exception ring buffers | `telescope_*` (when dispatcher path wired) | Reads `fluttersdk_telescope`'s in-app buffers. |
| Scaffold a command, plugin, or consumer entry | `./bin/fsa make:command` / `make:plugin` / `make:fast-cli` | CLI-only; mutates source on disk + regenerates barrels. |
| Install or uninstall a third-party plugin | `./bin/fsa plugin:install <name>` | CLI-only; interactive prompts; `--dry-run` previews ops. |
| Edit `.mcp.json` to wire the MCP server | `./bin/fsa mcp:install` (one-shot) or edit `.mcp.json` directly | Meta-config; one-time. |

## 5. Recovery: substring contracts for common failures

Connected tools (`artisan_tinker`, `dusk_*`, `telescope_*`) soft-fail via
`isError: true` text responses, never RPC exceptions. Branch on the
substring, not the full message:

| Substring | Cause | Agent's next move |
|---|---|---|
| `No Flutter app detected` / `Run `artisan start` first` | `~/.artisan/state.json` is absent | Call `artisan_start { device: ... }`, then retry. |
| `state.json missing vmServiceUri` | start wrote a partial state (rare; usually a crashed `flutter run`) | `artisan_restart`. |
| `Pipe missing: <path>. Run `artisan restart`` | FIFO file was deleted while state.json still recorded it | `artisan_restart` (or `rm ~/.artisan/state.json` + `artisan_start`). |
| `state.json has no stdinPipe entry; ... older artisan` | state.json predates the FIFO refactor | `artisan_restart`. |
| `Expression compilation error` / `RPCError(code: 113)` | `artisan_tinker { eval }` is not a single expression | Strip trailing `;`, collapse statements to a single expression, retry. |
| `Isolate sentinel (kind: ...)` | VM Service evaluate saw a stale isolate id | Auto-recovered on the next call; if it persists, `artisan_hot_restart` then retry. |
| `mkfifo failed (Windows not yet supported; V1 is POSIX-only)` | `artisan_start` on Windows | V1 limitation; stop and surface to the user. |
| `Chrome failed to open debug port <port>` | `--cdp-port` with a port already in use, or Chrome missing | Pick a free port via `--cdp-port=<N>`, confirm Chrome is installed. |
| `fsa: waiting for another fsa invocation...` does not clear | Stale `.artisan/.fsa.lock` directory after a hard kill | `rm -rf .artisan/.fsa.lock` + retry. |
| `another app is recorded` from `artisan_start` | state.json already has a running pid | Call `artisan_stop` first, then `artisan_start`. |

When `artisan_list` is missing an expected plugin namespace (`dusk:` /
`telescope:`):

- Verify `.mcp.json` points at `./bin/fsa mcp:serve`, NOT `dart run fluttersdk_artisan:mcp`.
- Verify `.artisan/plugins.json` lists the plugin.
- Verify `lib/app/_plugins.g.dart` imports the provider and `autoDiscoveredProviders()` returns a non-empty list.
- Run `./bin/fsa plugins:refresh` to regenerate the barrel from `.artisan/plugins.json`.
- Reconnect the MCP client (`/mcp reconnect fluttersdk` in Claude Code) so the next handshake re-reads tool list. Stdio MCP servers do NOT auto-reconnect; the client must reissue `initialize`.

Deep recovery reference (state.json schema, FIFO model, AOT staleness, MCP
boot path comparison, every failure substring):
`${CLAUDE_SKILL_DIR}/references/state-and-recovery.md`.

## 6. Quick install + doctor (when artisan is missing)

If `./bin/fsa` is absent or `dart run artisan list` errors with "command
not found", artisan is not installed in the consumer. From the Flutter app
root:

```bash
dart pub add fluttersdk_artisan
dart run fluttersdk_artisan install        # scaffolds bin/dispatcher.dart + _plugins.g.dart + _index.g.dart, builds ./bin/fsa
./bin/fsa mcp:install                       # writes .mcp.json fluttersdk entry pointing at ./bin/fsa mcp:serve
./bin/fsa doctor                            # 4 hard checks + advisory WARN lines
./bin/fsa list                              # confirm the substrate command set is registered
```

Then reconnect the MCP client. If `fluttersdk_dusk` or
`fluttersdk_telescope` are already in the pubspec, `./bin/fsa list` shows
their `dusk:` / `telescope:` namespaces automatically because
`lib/app/_plugins.g.dart` imports their providers; if not, install them
via `dart pub add fluttersdk_dusk && ./bin/fsa plugin:install fluttersdk_dusk`.

## 7. References (load on trigger)

| Read when... | File |
|---|---|
| Calling any `artisan_*` MCP tool: per-tool input schema, return shape, error envelope, example | `${CLAUDE_SKILL_DIR}/references/mcp-tools.md` |
| Invoking any of the 11 CLI-only commands from Bash: flags, defaults, output shapes, exit codes | `${CLAUDE_SKILL_DIR}/references/cli-commands.md` |
| Writing an `artisan_tinker` expression: constraints, the `await` wrapper, generic recipes plus optional Magic recipes, what NOT to send | `${CLAUDE_SKILL_DIR}/references/tinker-eval.md` |
| Recovering from a state failure (missing state.json, dead FIFO, stale lock, wrong MCP wiring, AOT staleness, VM Service unreachable) | `${CLAUDE_SKILL_DIR}/references/state-and-recovery.md` |

Standing reminders for the rest of the session: cite
`file_path:line_number` when documenting behavior; pub.dev install form
only in user-facing artifacts (no `path:` deps in docs or stubs); no
em-dash or en-dash anywhere (use comma, colon, semicolon, period, or
parentheses); no "Laravel" / "Symfony Console" / "Artisan-style" /
"Artisan-inspired" in produced text. When asked about a flag or behavior
you have not verified, read the source file before answering rather than
guessing.
