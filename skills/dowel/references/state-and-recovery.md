# State, lifecycle and recovery

dowel keeps mutable state outside the source tree: the session directory `~/.dowel/sessions/<hash>/` (state, log and FIFO of one project's running app), the pointer `~/.dowel/state.json`, and the AOT bundle `.dowel/cli-bundle/` with its stamp `.dowel/build.stamp` and build lock `.dowel/.dowel.lock/`: those three, with the scratch paths of a build, are the only gitignored part of `.dowel/` (`.dowel/cli-bundle*`, `.dowel/build.stamp*`, `.dowel/.dowel.lock/`). `.dowel/plugins.json`, `.dowel/installed/` and `.dowel/mcp.json` are source of truth and stay in version control. This file covers each, the two MCP entry points, and the recovery cases that need more than a row of the Recovery table in `SKILL.md`.

## Contents

- [Session and ownership](#session-and-ownership)
- [state.json keys](#statejson-keys)
- [FIFO model](#fifo-model)
- [AOT bundle staleness](#aot-bundle-staleness)
- [MCP entry points](#mcp-entry-points)
- [Recovery cases](#recovery-cases)
- [Two projects at once](#two-projects-at-once)

## Session and ownership

- The session path is `~/.dowel/sessions/<hash>/state.json`; `<hash>` is a truncated SHA-256 of the project root, the nearest ancestor of the working directory that holds a `pubspec.yaml`. `flutter-dev.log` and `flutter-dev.fifo` sit beside it. The home directory resolves from `$HOME`, then `$USERPROFILE`, then `/tmp`.
- `~/.dowel/state.json` points at whichever session started last. A read falls back to it when this project has no session of its own, and hand-writing it is the documented recovery when `dowel start` cannot boot an app.
- `stop`, `reload`, `hot-restart` and every connected CLI command refuse a session whose `projectRoot` is not the working directory or an ancestor of it, exit 1, naming both paths; `status` reports `ownedByThisProject: false` and exits 0 instead. State without a `projectRoot`, `--state=<path>` and `DOWEL_STATE_FILE` skip the check; the flag wins when both are set. A named file that is missing or unreadable falls back to the pointer, still unchecked, so confirm it exists and holds the intended `projectRoot`. The MCP server runs no check for plugin tools and `dowel_tinker`, and the server resolves the session from its own working directory, falling back to the pointer when that project has none.
- A git worktree has its own `pubspec.yaml`, so its project root is the worktree. Without a session of its own, the pointer answers. The check passes when the worktree sits inside the project root the pointer recorded (an app at the repo root, the worktree under it): `stop` stops the main app, `restart` stops it and boots the worktree's own app on the main app's ports, and connected commands act on it, all reporting success. A sibling checkout, or an app in a subdirectory the worktree is not inside, is refused. Run `dowel start` in the worktree first, or pass `--state=<path>`.
- Writes go through `<file>.<pid>.tmp` and a rename; an unreadable session file reads as absent and falls through to the pointer.

## state.json keys

| Key | Notes |
|---|---|
| `pid`, `stdinHolderPid` | The `flutter run` process and the `tail -f /dev/null > fifo` holder that keeps the FIFO open |
| `stdinPipe` | FIFO path; `reload` and `hot-restart` write into it, so hand-written state without it cannot hot restart |
| `vmServiceUri` | `ws://host:port/<token>/ws`; null while `booting` |
| `booting` | Present and true between the spawn and the URI landing: the record is incomplete, not wrong |
| `webPort`, `vmServicePort` | Recorded for every device; `webPort` is passed to flutter for `chrome` only; `vmServicePort` defaults to 8181 |
| `device`, `profile`, `startedAt`, `projectRoot` | Target device, `debug` or `static`, ISO 8601 time, absolute project path |
| `chromePid`, `tmpProfileDir`, `cdpPort` | Set by `start --cdp-port`, null otherwise |
| `flutterArgs` | The `--flutter-arg` values; absent when there were none |

`restart` stops, then starts again with the prior session's device, `webPort`, `vmServicePort`, `cdpPort`, `flutterArgs` and `profile: static`; an explicit flag wins. It refuses to go on when `stop` refuses, and a failed relaunch leaves no app, so do not restart blind in a worktree. Over MCP `dowel_restart` takes the same options and an omitted one keeps the prior value: to change the device, `dowel_restart { device }`. Read the file through `dowel_status`, which adds an `alive` probe.

## FIFO model

- `start` creates the FIFO with `mkfifo`, starts a holder (`tail -f /dev/null > fifo`) so the write end stays open, and runs `nohup flutter run < fifo`.
- `reload` writes `r`, `hot-restart` writes `R`, through shell redirection (`printf`): Dart's `File.open` rejects a FIFO. Both exit 0 once the keystroke is written, before Flutter finishes; read the log for the effect.
- `stop` stops the flutter process group (the holder shares it), deletes the FIFO and terminates the holder.
- `dowel_stop` with no session is a no-op that exits 0. A hard-killed `flutter run` can leave `state.json` without its FIFO: `reload` then exits 2 with `Pipe missing: <path>`. Recover with `dowel_restart`, or `dowel_stop` then `dowel_start`.
- Windows has no `mkfifo`, so the lifecycle commands fail there; there is no agent-side recovery.

## AOT bundle staleness

`./bin/dowel` is a shell wrapper generated from `assets/stubs/bin_dowel.sh.stub`. It rebuilds the dispatcher AOT when any of these holds:

| Condition | Meaning |
|---|---|
| Binary missing | `.dowel/cli-bundle/bundle/bin/dispatcher` absent or not executable |
| Stamp missing or empty | `.dowel/build.stamp` |
| Stamp mismatch | The key `<sha256(pubspec.lock)>:<4th word of dart --version>` changed |
| `pubspec.yaml` newer than the stamp | Edited after the last build |
| `lib/app/_plugins.g.dart` newer than the stamp | Regenerated after the last build |

A build takes `.dowel/.dowel.lock` (an atomic `mkdir`), runs `dart build cli -t bin/dispatcher.dart` into `.dowel/cli-bundle.build.<pid>`, swaps it in by rename, writes the stamp and `exec`s the binary. The lock is released before the `exec`, so a long-lived `mcp:serve` never holds it. A dead owner's lock is reclaimed through a PID probe; a live owner is waited on for `DOWEL_LOCK_TIMEOUT` seconds (default 600), then the call fails naming its pid. The wait prints `dowel: waiting for another dowel invocation to finish...` on stderr. If it never clears, regenerate a wrapper that predates the release lock with `dart run dowel make:fast-cli --force`, or `rm -rf .dowel/.dowel.lock`.

`plugins:refresh` (so `plugin:install` too) and `plugin:uninstall` purge the bundle, `make:fast-cli --force` rebuilds it, and `commands:refresh` does neither. If `./bin/dowel` does not see a command you just generated, run `rm -rf .dowel/cli-bundle .dowel/build.stamp && ./bin/dowel list`, or use `dart run :dispatcher <cmd>`.

## MCP entry points

| Aspect | `dart run dowel:mcp` | `./bin/dowel mcp:serve` |
|---|---|---|
| Entry | `bin/mcp.dart` of the dowel package | `bin/dispatcher.dart` of the host app |
| Loads `lib/app/_plugins.g.dart` | No | Yes |
| Tools | Substrate only | Substrate plus every plugin's `mcpTools()` |
| Use | Debugging dowel itself | The dev loop in a consumer app |

`mcp:install` writes the dispatcher shape: `{"command": "./bin/dowel", "args": ["mcp:serve"], "cwd": "."}` under `mcpServers.dowel`. Where `./bin/dowel` is absent, or on Windows, it writes `dart run :dispatcher mcp:serve`.

Plugin tools missing from `tools/list` (`dowel_list` shows command namespaces and is no proof either way):

1. Read `.mcp.json`: `dart run dowel:mcp` is the substrate entry and never lists plugin tools.
2. Read `.dowel/plugins.json` and `lib/app/_plugins.g.dart` (`autoDiscoveredProviders()` must be non-empty). Run `./bin/dowel plugins:refresh`; if `plugins.json` is empty too, run `./bin/dowel plugin:install <name>`.
3. Reconnect the MCP client (Claude Code: `/mcp reconnect dowel`); the server does not signal tool-list changes.
4. Read the stderr boot line `[dowel_mcp] registered N tools (M filtered; P plugin + S substrate)`: `P` is the plugin tool count before filtering, and `M` above zero means a filter is denying tools.

## Recovery cases

- **A second `dowel_start` for the same project.** `start` never reads an existing session before it spawns: it launches another `flutter run`, truncates the log and replaces the session file, leaving the first app running with nothing recorded. Check `dowel_status`; if a session is live, `dowel_stop` or `dowel_restart` first. A session file that `dowel_stop` cannot clear: remove that project's directory under `~/.dowel/sessions/` and retry. Removing only `~/.dowel/state.json` clears the pointer, not the session; `rm -rf ~/.dowel/sessions` clears every project.
- **`booting: true` and no `vmServiceUri`.** The caller gave up before the URI was scraped, typically at a client's tool-call limit on a cold iOS or Android build; the app is up. Do not re-run `start` or hand-write the file. A CLI connected command reads the URI back from the log and completes the record: `./bin/dowel tinker --eval=1`; it exits 75 while the build is still running and 1 when the recorded process is gone. The MCP tools do not do this. If it does not clear, `flutter run` is failing: read the log.
- **CLI `start` exits 75** (`flutter run (pid N) is still building after Ns`): the plain branch while the app is alive; treat it as the interrupted start above and do not re-run `start`. Exit 1 with `exited before announcing a VM Service URI` is the real failure. The `--cdp-port` branch reaps what it spawned and exits 1.
- **`<ext> is not registered in the running app yet`** (exit 75): the app is still booting, or it is a release build or lacks the plugin. Wait and retry.
- **Connected calls fail after a restart, stop and start, or device change.** The MCP server drops its VM client when the old app's socket closes and dials the URI the session records now on the next call; a plugin tool call that finds the old connection disposed is not run again and reports that its outcome is unknown. So check whether it took effect, then retry it after `dowel_status` shows the new app `alive`. Reconnect the MCP client (Claude Code: `/mcp reconnect dowel`) only if it keeps failing.
- **`start --cdp-port` failures.** `CDP port <N> is already in use` and `Port <web-port> is already in use` fail before anything is spawned (free the port with `lsof -ti tcp:<port>` or pick another). `Chrome binary not found` names the expected path. A Flutter SDK older than 3.30.0 is refused on this branch. If Chrome fails after the probe, `start` kills Chrome and returns an error.
- **`doctor` reports the default web port busy.** Another process holds TCP 3100; pass `--port=<N>` to `start`.
- **Reset everything for a project.** `./bin/dowel stop`, remove its session directory, then `./bin/dowel start`.

## Two projects at once

Each project has its own session directory, so state, log and FIFO do not collide; ports do. Only `--cdp-port` starts probe ports, so give every session its own:

```bash
./bin/dowel start --device=chrome --port=3100 --cdp-port=9333 --vm-service-port=8181   # project A
./bin/dowel start --device=chrome --port=3180 --cdp-port=9380 --vm-service-port=8281   # project B
```

Run commands from inside the project they belong to. A CLI command that would act on another project's app refuses and names both paths, but plugin tools and `dowel_tinker` over MCP, and a worktree inside the recorded root, are not refused: check `dowel_status` (`projectRoot`, `ownedByThisProject`) before acting. Pass `--state=<path>` to name a session outside the directory.
