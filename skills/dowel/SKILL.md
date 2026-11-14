---
name: dowel
description: "Start, hot reload and inspect a running Flutter app from an agent with dowel's `dowel_*` MCP tools and `./bin/dowel` CLI."
version: 0.0.9
when_to_use: "Use when running, reloading or evaluating in a Flutter app through dowel, installing a dowel plugin, or fixing dowel MCP wiring or session errors."
---

# dowel

`dowel` is a CLI and a stdio MCP server in one binary. An agent calls `dowel_*` tools (or `./bin/dowel <cmd>` from a shell) to start the app, hot reload it, read its log, evaluate Dart against the running isolate, and install plugins that add their own commands and tools, without leaving the conversation.

Scope: this skill drives an app and installs plugins. Writing a plugin (`install.yaml`, `PluginInstaller`, `DowelServiceProvider`) is in the plugin authoring docs; testing a command you wrote is `${CLAUDE_SKILL_DIR}/references/testing-commands.md`; widget interaction is the `tapir` skill and HTTP, log and exception capture is the `crumbs` skill.

## Install

If `./bin/dowel` is missing or `dart run dowel list` fails, dowel is not set up. From the Flutter app root:

```bash
dart pub add dowel
dart run dowel install        # bin/dispatcher.dart, lib/app/*.g.dart barrels, then builds ./bin/dowel; keeps an existing dowel constraint
./bin/dowel mcp:install       # writes the dowel entry into .mcp.json
./bin/dowel doctor            # toolchain preflight
```

Reconnect the MCP client afterwards (Claude Code: `/mcp reconnect dowel`); stdio servers are not reloaded on their own.

## Rules

1. **Two MCP entries give two tool catalogues.** `dart run dowel:mcp` serves the substrate tools only. `./bin/dowel mcp:serve` (or `dart run :dispatcher mcp:serve`) also loads `lib/app/_plugins.g.dart` and adds every plugin's tools (`tapir_*`, `crumbs_*`). Read `.mcp.json` to see which one is wired. Plugin tools missing from `tools/list` (`dowel_list` shows command namespaces and is no proof either way): follow "MCP entry points" in `${CLAUDE_SKILL_DIR}/references/state-and-recovery.md`.
2. **The session is per project.** `dowel_start` writes `~/.dowel/sessions/<hash>/state.json` (pid, `vmServiceUri`, FIFO path, device, ports) keyed by the project root, so two projects run side by side. `~/.dowel/state.json` only points at whichever session started last. CLI commands and the substrate tools refuse another project's session (`status` reports `ownedByThisProject: false` instead of refusing); plugin tools and `dowel_tinker` run no such check, so read `projectRoot` and `ownedByThisProject` from `dowel_status` when two apps are up. An MCP server resolves the session from its own working directory and falls back to the shared pointer when that project has none.
3. **In a git worktree, start the app there, from a shell.** Run `./bin/dowel start` in the worktree (or pass `--state=<path>`) before any command that uses the session; MCP tools take no `--state` and use the server's own working directory, so do not rely on them from a worktree. The ownership check passes when the worktree sits inside the project root the main app recorded (an app at the repo root, the worktree under it) and for state with no recorded `projectRoot`; then `stop` stops the main app, `restart` stops it and boots the worktree on its ports, and connected commands act on it, all reporting success. A sibling checkout, or an app in a subdirectory the worktree is not inside, is refused. `--state=<path>` skips the check, and a file that is missing or unreadable falls back to the shared pointer, so confirm it exists and holds the intended `projectRoot`.
4. **The VM connection follows the session.** The first connected call after `dowel_start` opens the VM Service and the MCP server keeps that client. `dowel_reload` (`r`) keeps Dart state; `dowel_hot_restart` (`R`) drops it and mints a new isolate id, which `dowel_tinker` re-reads on each call. When the app stops or restarts (`dowel_restart`, a stop and start, a device change) the server drops its client and dials the URI the session records now on the next call, and a plugin tool call that finds the old connection disposed is not replayed: it reports `the outcome of this call is unknown`, and the next call reconnects. No MCP client reconnect is needed; check the app state before repeating a call that changes it. If connected calls keep failing, read `dowel_status` first, then reconnect the MCP client (`/mcp reconnect dowel`).
5. **`dowel_tinker` takes one expression.** The VM compiles a single expression in the root library: a trailing `;`, several statements, `import` or a declaration fail with code 113 (`[ERROR] evaluate: (113) ...`). A bare `await` compiles because dowel wraps the source in `(() async => <expr>)()`, but the result is the Future (`<_Future#...>`), not the awaited value: start the work with `await`, then read the outcome with a second expression. A quiet state does not prove the work finished, so poll a completion flag the app exposes (such as `isLoading`) with a timeout. End a non-primitive result with `.toString()` inside the expression, or it prints as `<ClassName#id>`. A runtime exception comes back as `Error: <message>` with exit 0, so read the text rather than `isError`. Recipes: `${CLAUDE_SKILL_DIR}/references/tinker-eval.md`.
6. **Only the lifecycle and inspect commands are MCP tools.** `help`, `install`, `make:*`, `commands:refresh`, `plugins:refresh`, `plugin:install`, `plugin:uninstall` and `mcp:*` are CLI-only: run them from Bash as `./bin/dowel <cmd>` (native) or `dart run dowel <cmd>` (slower startup). Read `${CLAUDE_SKILL_DIR}/references/cli-commands.md` before running one of them, for its exit codes and what it writes.
7. **Reload and hot restart are POSIX only.** `start` creates a FIFO (`~/.dowel/sessions/<hash>/flutter-dev.fifo`) and `dowel_reload` or `dowel_hot_restart` write `r` or `R` into it. Windows has no `mkfifo`; stop and tell the user.
8. **`./bin/dowel` is an AOT cache.** It rebuilds when the bundle or `.dowel/build.stamp` is missing or empty, the stamp's lockfile hash or Dart version differs, or `pubspec.yaml` or `lib/app/_plugins.g.dart` is newer than the stamp. A build holds `.dowel/.dowel.lock`; a dead owner's lock is reclaimed and a live one is waited on for `DOWEL_LOCK_TIMEOUT` seconds (default 600). Force a rebuild with `make:fast-cli --force`; if a command you just generated is missing, delete `.dowel/cli-bundle` and `.dowel/build.stamp`.
9. **Exit `75` means retry.** CLI `start --timeout=N` (without `--cdp-port`) and CLI connected commands return it while the app is still building; every other non-zero code is a failure. A substrate tool result starts with `` # `dowel <cmd>` exit N `` and sets `isError` when `N` is not 0, so a 75 shows up as an error.
10. **`--dry-run` is the only write-free path.** `plugin:install <name> --dry-run` previews every operation and writes nothing. The real run swaps file operations in through `.tmp` files only after all were staged, but dependency additions and injections write directly while staging and are not rolled back: after a failed install inspect `git status` and recover by hand. A failure after those edits reports `rolledBack: false` and leaves a partial record. A successful run is recorded under `.dowel/installed/<plugin>.json`, and `plugin:uninstall` reverses its file-creating operations and the dependency additions the project did not already declare, skipping and warning about the rest. A record written by an older dowel is refused (`unsupported-install-record`): re-run `plugin:install <name> --force` once, which also switches off every other conflict check, so read `git diff` after it. A plugin without an `install.yaml` is registered straight into `.dowel/plugins.json`, needs the scaffold from `dowel install`, and cannot be uninstalled.
11. **Commit `.dowel/plugins.json` and `.dowel/installed/`.** Only `.dowel/cli-bundle*`, `.dowel/build.stamp*` and `.dowel/.dowel.lock/` are cache and gitignored. `plugin:install` refuses to run when `lib/app/_plugins.g.dart` registers providers but `.dowel/plugins.json` is missing, because it would regenerate the barrel with one plugin: restore the file from version control. `make:fast-cli` (so `install`) replaces a bare `.dowel/` line in `.gitignore` with the cache entries.

## Tool surface

Substrate tools, available unless `.dowel/mcp.json`, `DOWEL_MCP_TOOLS_DENY` or `--exclude-tool` denies them:

| Family | Tools | Mental model |
|---|---|---|
| Lifecycle | `dowel_start`, `dowel_stop`, `dowel_restart`, `dowel_reload`, `dowel_hot_restart` | Boot, kill, full cycle, or send `r` or `R` to the FIFO; the session file is the side effect |
| Inspect | `dowel_status`, `dowel_logs`, `dowel_doctor`, `dowel_list` | Session JSON, captured log, preflight checks, command catalogue |
| Evaluate | `dowel_tinker { eval: "..." }` | One Dart expression on the main isolate |

`dowel_logs` returns the whole captured log in the tool result, once; following it is a CLI feature, so run `./bin/dowel logs --follow` from a shell. `dowel_start` and `dowel_restart` take every option their CLI commands take (`cdp-port`, `timeout` and an array `flutter-arg` for `dowel_start`; `dowel_restart` keeps any option you omit from the prior session). Plugin tools appear with the dispatcher entry (rule 1); the server logs `[dowel_mcp] registered N tools (M filtered; P plugin + S substrate)` to stderr at boot. Read `${CLAUDE_SKILL_DIR}/references/mcp-tools.md` for per-tool behaviour, the result envelope and the filter.

## Picking the path

| Need | Use | Why |
|---|---|---|
| Boot, restart, inspect or evaluate the running app | `dowel_*` tool | One round trip inside the MCP session |
| Read the app log | `dowel_logs` | The whole log comes back in the tool result; follow it from a shell |
| Read or change live state (singletons, controllers, caches) | `dowel_tinker` | VM Service evaluate, one shot |
| Inspect the semantics tree or drive gestures | `tapir_*` | Plugin tools; pair with tinker for state checks |
| Read HTTP, log and exception buffers | `crumbs_*` | Plugin tools over the in-app ring buffers |
| Scaffold a command, plugin or entry | `./bin/dowel make:command`, `make:plugin`, `make:fast-cli` | CLI-only; `make:command` also refreshes the command index |
| Install or remove a plugin | `./bin/dowel plugin:install <name>` or `plugin:uninstall <name>` | CLI-only; `--dry-run` previews |

## Recipes

First touch of a session:

```text
dowel_doctor     hard checks (flutter, dart, port 3100, SDK 3.30.0 or newer for --cdp-port); WARN lines are advisory
dowel_status     {"running": false}, or {running, pid, alive, vmServiceUri, device, webPort, startedAt, projectRoot, ownedByThisProject}
dowel_list       confirms which plugin namespaces loaded
```

`running: false` means call `dowel_start` before any connected tool; `alive: false` means the process died, call `dowel_restart`; `ownedByThisProject: false` means the app belongs to another project.

Boot, inspect, evaluate:

```text
dowel_start { device: "chrome" }
dowel_status                                        vmServiceUri present, alive: true
dowel_tinker { eval: "WidgetsBinding.instance.lifecycleState.toString()" }
dowel_tinker { eval: "await MyService.instance.refresh()" }              returns <_Future#...>; the work still runs
dowel_tinker { eval: "MyService.instance.state.toString()" }                read the outcome
```

`device` defaults to `chrome` (web, port 3100); pass `macos` for desktop or an adb serial for Android.

Hot reload after an edit: `dowel_reload` exits 0 once the keystroke is written, before Flutter finishes, so read the log file for the expected line, then `dowel_tinker` to confirm. If reload fails (a const constructor change, a build error during reassemble) use `dowel_hot_restart`; if that fails, `dowel_restart`.

CLI-only work from Bash:

```bash
./bin/dowel make:command MyCommand                   # class plus _index.g.dart refresh
./bin/dowel plugin:install awesome_plugin --dry-run  # preview the plan
./bin/dowel plugin:install awesome_plugin            # commit and refresh the barrel
```

## Recovery

Connected tools soft-fail with text. Branch on the substring:

| Substring | Cause | Next move |
|---|---|---|
| `No Flutter app detected (~/.dowel/state.json missing or has no vmServiceUri)` from a plugin tool, or `Not connected to a running Flutter app` from `dowel_tinker` | No session, or a session that records no `vmServiceUri` | `dowel_status`: `running: false` means `dowel_start { device }` and retry; `booting: true` means the next row; otherwise `flutter run` crashed during boot, so read the log, `dowel_stop`, then `dowel_start` |
| `VM Service connect failed:` from a plugin tool, or a raw exception with a stack trace from `dowel_tinker` | A session is recorded but the app is gone, or the connection just closed | `dowel_status` (`alive`), then `dowel_restart` or `dowel_start` and retry; the server dials the new URI on its own. Reconnect the MCP client only if it keeps failing |
| session shows `booting: true` | `start` was cut short by its caller; the app is running | Do not re-run start or hand-write the file. Run `./bin/dowel tinker --eval=1`: a CLI connected command reads the URI back from the session log and saves it, exiting 75 while the build is still running and 1 when the recorded process is gone; MCP tools do not |
| ``Pipe missing: <path>. Run `dowel restart` `` | The FIFO was deleted while the session recorded it | `dowel_restart` |
| `The session has no stdinPipe entry` | The session predates the FIFO or was hand-written | `dowel_restart` |
| `evaluate: (113)` | `eval` is not a single expression | Drop the `;`, collapse to one expression |
| `--eval needs a Dart expression` | `eval` was blank | Pass an expression; a blank `eval` is a usage error and never starts the REPL |
| `This project still has files from fluttersdk_artisan` from `dart run dowel install` (or a `fluttersdk_artisan leftovers` WARN from `doctor`) | The project was generated by the package dowel replaced | Follow the numbered steps in the message; delete the old `bin/dispatcher.dart` first, because `doctor` hands over to it. The page is `getting-started/migrating-from-fluttersdk-artisan` in the docs |
| `Isolate sentinel encountered` (from `tapir_evaluate`) | Stale isolate id after a hot restart | Call any other plugin tool once (its retry refreshes the cached id), or reconnect the MCP client, then retry |
| ``# `dowel start` exit 75`` | The build is still running and the session is `booting` | Follow the `session shows booting: true` row above once the build had time to finish; do not call `dowel_start` again |
| `Chrome binary not found`, `CDP port <N> is already in use`, `Port <N> is already in use` | `start --cdp-port` preflight (CLI only) | Install Chrome, or free the port or pass another |
| `mkfifo failed` | `dowel_start` on Windows | Stop and tell the user |

State keys, the FIFO model, AOT staleness and the longer recovery cases: `${CLAUDE_SKILL_DIR}/references/state-and-recovery.md`.

## Testing

A command is tested without a process, a VM or a terminal: a `DowelContext.bare` over a `MapInput` and a `BufferedOutput`, then `handle` and an assertion on the exit code and the captured output; an installer runs against `InstallContext.test` with an `InMemoryFs`. The runnable sample is in `${CLAUDE_SKILL_DIR}/references/testing-commands.md`; read it before writing the test.
