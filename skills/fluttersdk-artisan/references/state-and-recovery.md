# State, lifecycle, and recovery

`fluttersdk_artisan` keeps three pieces of mutable state outside the
source tree: the session directory at
`~/.artisan/sessions/<hash>/` (state, log and FIFO for ONE project's
running app), the legacy pointer `~/.artisan/state.json` (whichever
session started last), and the AOT bundle at `.artisan/cli-bundle/`
plus its stamp `.artisan/build.stamp` (per-project compiled wrapper). This file
documents each, the MCP boot path comparison (substrate vs dispatcher),
and the recovery loop for every common failure substring.

## Contents

- [state.json schema](#statejson-schema)
- [FIFO pipe model](#fifo-pipe-model)
- [AOT bundle staleness gate](#aot-bundle-staleness-gate)
- [MCP server boot path comparison](#mcp-server-boot-path-comparison)
- [Diagnosing missing plugin tools](#diagnosing-missing-plugin-tools)
- [Recovery loops by substring](#recovery-loops-by-substring)
- [Quick state cleanup](#quick-state-cleanup)
- [Running two projects at once](#running-two-projects-at-once)
- [When to favour `./bin/fsa` over MCP](#when-to-favour-binfsa-over-mcp)

## state.json schema

`lib/src/state/state_file.dart`

- **Absolute path**: `~/.artisan/sessions/<hash>/state.json`, where
  `<hash>` is a truncated SHA-256 of the project root (resolved from
  `$HOME`, falling back to `$USERPROFILE`, then `/tmp`). The log and the
  FIFO live beside it in the same directory.
- **Per project, not per machine.** It used to be one global
  `~/.artisan/state.json`. A second project's `artisan start` silently
  took that slot, and every connected command from the first project then
  drove the second app, succeeding each time: the measured case had a
  worktree in another repository rewrite it mid-session, and two commands
  later produced a screenshot of an entirely different product.
- **The legacy pointer still exists** at `~/.artisan/state.json`, holding
  whatever started last. `read()` falls back to it when this project has
  no session, so the documented recovery recipe (hand-writing that file
  when `artisan start` cannot boot an app) keeps working.
- **Ownership is checked before acting.** Any command that connects to,
  stops, reloads or hot-restarts the recorded app refuses when its
  `projectRoot` is not this directory or an ancestor of it. A working
  directory inside the project passes, and so does state with no recorded
  `projectRoot` (hand-written recovery state usually omits it).
- **Overrides**: `--state=<path>` (global flag, consumed before dispatch)
  and `ARTISAN_STATE_FILE`. The flag wins. Naming the session explicitly
  also bypasses the ownership check, because you have already answered
  the question it asks.
- **Two projects still need distinct ports.** `start` fails fast when the
  web or CDP port is taken; pass `--port`, `--vm-service-port` and
  `--cdp-port` per session.
- **Atomicity**: every write goes through `.tmp` + rename; concurrent
  readers never see partial JSON.
- **Soft-read**: missing file returns `null`, parse failure also
  returns `null` (no exception propagation).

| Key | Type | Written by | Notes |
|---|---|---|---|
| `pid` | int | `start` | flutter run subprocess PID |
| `vmServiceUri` | string | `start` | `ws://host:port/<token>/ws` (always WebSocket; http → ws normalized) |
| `webPort` | int | `start` | the `--web-port` passed to flutter (e.g. 3100) |
| `vmServicePort` | int | `start` | host VM Service port (default 8181) |
| `device` | string | `start` | `chrome` / `macos` / `linux` / device serial; mirrors `--device` |
| `startedAt` | string | `start` | ISO 8601 timestamp |
| `profile` | string | `start` | `debug` or `static` (set when `--profile-static`) |
| `projectRoot` | string | `start` | absolute path to the Flutter project that ran `start` |
| `stdinPipe` | string | `start` | FIFO path (`~/.artisan/flutter-dev.fifo`) |
| `stdinHolderPid` | int | `start` | the `tail -f /dev/null > fifo` holder pid (kept alive so writer-side EOF does not propagate) |
| `chromePid` | int / null | `start --cdp-port` | Chrome subprocess pid; null on non-CDP runs |
| `tmpProfileDir` | string / null | `start --cdp-port` | Chrome temp profile dir; null otherwise |
| `cdpPort` | int / null | `start --cdp-port` | the `--cdp-port` value; null when CDP is disabled |
| `booting` | bool / absent | `start` | present and true only between the spawn and the URI landing; says the record is incomplete rather than wrong |

`restart` preserves `cdpPort` across the stop+start cycle: it reads the value from `state.json` before `stop` deletes the file, then forwards it into `start`, so a CDP-enabled session survives a restart. An explicit `--cdp-port` on the `restart` invocation wins over the preserved value.

The agent reads state.json via `artisan_status`. Direct file reads via
`Read` tool are also valid for debugging but `artisan_status` adds the
`alive` liveness probe.

## FIFO pipe model

- **Path**: `~/.artisan/flutter-dev.fifo`
- **Created**: by `artisan_start` via shell `mkfifo` (skipped on Windows;
  start raises `StateError('mkfifo failed (Windows not yet supported;
  V1 is POSIX-only): ...')` on Windows).
- **Dual-process holder pattern**:
  - HOLDER process: `tail -f /dev/null > fifo`. Keeps the write end
    open so flutter run's stdin does not EOF when an external writer
    closes its handle.
  - FLUTTER process: `nohup flutter run ... < fifo`. Reads keystrokes
    from stdin.
- **Write semantics**: `artisan_reload` writes `r\n`,
  `artisan_hot_restart` writes `R\n`. Both use shell redirection:
  `printf %s 'r\n' > <fifo>`. Dart's `File.open` rejects FIFOs because
  the implementation calls `lseek` (illegal on FIFO).
- **Cleanup**: `artisan_stop` deletes the FIFO file and SIGTERMs the
  HOLDER pid. POSIX semantics: unlinking a FIFO invalidates the inode
  but open file descriptors remain valid until closed.

**Race: FIFO missing while state.json exists.** If the user hard-kills
flutter run (SIGKILL), the FIFO may be cleaned up while state.json is
not. `artisan_reload` then exits 2 with
`Pipe missing: <path>. Run `artisan restart``. Recovery:
`artisan_restart` (rebuilds the FIFO), or `artisan_stop` (cleans state)
+ `artisan_start`.

## AOT bundle staleness gate

`./bin/fsa` (POSIX shell wrapper) self-rebuilds the dispatcher AOT when
any of 4 conditions holds. Wrapper source: the consumer's `bin/fsa`
script, lines 39-47.

```bash
needs_build() {
  [ ! -x "$BINARY" ] && return 0                              # 1: binary missing
  [ ! -s "$STAMP_FILE" ] && return 0                          # 2: stamp empty/missing
  [ "$(cat "$STAMP_FILE")" != "$COMPILE_KEY" ] && return 0    # 3: stamp mismatch (lock hash : sdk version)
  [ "$ROOT/pubspec.yaml" -nt "$ROOT/pubspec.lock" ] && return 0   # 4: pubspec newer than lock
  return 1
}
```

| Condition | Trigger |
|---|---|
| Binary missing | `.artisan/cli-bundle/bundle/bin/dispatcher` absent or non-executable |
| Stamp missing | `.artisan/build.stamp` does not exist or is empty |
| Stamp mismatch | The `<sha256(pubspec.lock)>:<dart --version>` key has changed (lock or SDK upgrade) |
| pubspec newer than lock | `pubspec.yaml` modified after `pubspec.lock` (un-run `pub get`) |

**Rebuild flow** (acquires `.artisan/.fsa.lock` directory via atomic
`mkdir`, runs `dart build cli -t bin/dispatcher.dart -o
.artisan/cli-bundle`, writes the stamp atomically, exec's the binary).
Typical rebuild: ~5s on a warm machine.

**Lock staleness recovery**: if a previous `./bin/fsa` crashed
(SIGKILL bypasses trap), `.artisan/.fsa.lock/` survives. The next
invocation reads the lock's stored PID and probes via `kill -0`. If the
owner is dead, `rm -rf .artisan/.fsa.lock` and retry the `mkdir`.
Symptom of the race never clearing: `fsa: waiting for another fsa
invocation to finish...` Recovery: `rm -rf .artisan/.fsa.lock` +
retry.

**When to manually invalidate the AOT**: after editing
`.artisan/plugins.json` by hand, or after a `plugins:refresh` /
`commands:refresh` that should change the registered set. Both refresh
commands invalidate the cache as a side effect (delete
`.artisan/cli-bundle/` + `.artisan/build.stamp`), so the next
`./bin/fsa` rebuilds. If staleness persists: `rm -rf .artisan/cli-bundle
.artisan/build.stamp && ./bin/fsa list`.

## MCP server boot path comparison

There are TWO entry points for the MCP server. The dispatcher path is
the dev default; the substrate path exists for testing the artisan
package itself.

| Aspect | `dart run fluttersdk_artisan:mcp` (substrate) | `./bin/fsa mcp:serve` (dispatcher) |
|---|---|---|
| Entry source | `bin/mcp.dart` of the artisan package | `bin/dispatcher.dart` of the host app |
| Force flags | `collectMcpTools: true`, `delegateToConsumer: false` | passes consumer providers via `baseProviders: [...]` + `plugins.autoDiscoveredProviders()` |
| Loads `lib/app/_plugins.g.dart` | NO | YES |
| Substrate tools | 10 (the allowlist) | 10 (the allowlist) |
| Plugin tools | NONE | substrate + every plugin's `mcpTools()` |
| Use case | Debugging the artisan substrate itself | Production dev loop in a real consumer app |

The canonical `.mcp.json` shape (written by `./bin/fsa mcp:install`)
wires the dispatcher path:

```json
{
  "mcpServers": {
    "fluttersdk": {
      "command": "./bin/fsa",
      "args": ["mcp:serve"]
    }
  }
}
```

This surfaces the 10 substrate tools plus every installed plugin's
contributed tools. Read the stderr boot line
`[fluttersdk_artisan_mcp] initialized with N tools (...)` for the
exact count in your consumer.

## Diagnosing missing plugin tools

Symptoms: `artisan_list` does NOT show `dusk:` or `telescope:` namespace,
or MCP `tools/list` shows only `artisan_*` entries.

Decision tree:

```
1. Inspect .mcp.json:
   - command: "./bin/fsa", args: ["mcp:serve"]          → dispatcher path; should surface plugin tools
   - command: "dart", args: ["run", "fluttersdk_artisan:mcp"] → substrate path; will NOT surface plugin tools
   - Anything else                                       → custom wiring; check the args manually

2. If dispatcher path is wired but plugin tools still missing:
   - Read .artisan/plugins.json: does it list the plugin (fluttersdk_dusk, fluttersdk_telescope)?
   - Read lib/app/_plugins.g.dart: does autoDiscoveredProviders() return a non-empty list?
   - If no: run `./bin/fsa plugins:refresh` to regenerate from .artisan/plugins.json.
   - If plugins.json is also empty: run `./bin/fsa plugin:install <name>`.

3. Reconnect the MCP client (Claude Code: /mcp reconnect fluttersdk).
   The MCP server does NOT auto-detect tool list changes; the client must
   reissue `initialize` + `tools/list`.

4. Read the MCP server's stderr boot line:
   [fluttersdk_artisan_mcp] initialized with N tools (M filtered; P plugin + S substrate)
   - P=0 means no plugin providers loaded (dispatcher path is broken or plugins.json is empty).
   - M>0 means the filter is denying tools; check .artisan/mcp.json + env vars + CLI flags.
```

## Recovery loops by substring

Connected tools (`artisan_tinker`, `dusk_*`, `telescope_*`) and the
substrate's own lifecycle commands return `isError: true` with a text
message. Branch on substring, not full text.

### `No Flutter app detected` / `Run `artisan start` first`

Cause: this project has no session (app never started, or `stop` ran).
Note that a sibling project's running app does NOT satisfy this: sessions
are per project, so a pointer describing somebody else's app is refused
rather than driven.

```
artisan_start { device: "chrome" }   # or whatever target
artisan_status                        # confirm vmServiceUri present
<retry the failing tool>
```

### `another app is recorded`

Cause: `artisan_start` called while state.json already records a running
pid.

```
artisan_stop
artisan_start { device: ... }
```

If `artisan_stop` returns "No state file" but `artisan_start` still
fails, the session file is mid-write (race) or owned by a different user.
Remove the session directory for this project (`artisan_status` reports its
`projectRoot`; the path is `~/.artisan/sessions/<hash>/`) and retry. Removing
only `~/.artisan/state.json` clears the pointer, not the session.

### The session says `booting: true` and has no `vmServiceUri`

Cause: `start` was cut short between spawning the app and scraping its URI.
Almost always the CALLER gave up, not the app: an MCP client kills a tool
call at 60s and a cold iOS or Android build routinely takes longer. The app
is up, the session records everything except the URI, and the marker says so.

Do NOT re-run `start` and do NOT hand-write the file. The next connected
tool call reads the URI out of the session log and keeps it:

```
artisan_status         # booting: true, vmServiceUri null
<any connected tool>   # recovers the URI and completes the record
artisan_status         # booting gone, vmServiceUri present
```

If it does not clear, the underlying flutter run is failing rather than
slow, and `artisan_logs` shows what it printed. From Bash the scrape window
itself is adjustable: `./bin/fsa start -d chrome --timeout=180`. The MCP
tool has no timeout parameter, so that path is CLI-only.

### `state.json missing vmServiceUri`

Cause: a state file that records no URI and carries no `booting` marker, so
it was not an interrupted start: flutter run crashed during boot before the
URI was scraped.

```
artisan_status         # confirm the bad state
artisan_stop           # clean
artisan_start { ... }  # retry
artisan_logs           # check what flutter run actually printed during boot
```
Read the captured log.

### `Pipe missing: <path>. Run `artisan restart``

Cause: FIFO was deleted while state.json still recorded it (usually
hard-kill of flutter run).

```
artisan_restart
```

Or, if that loops: `artisan_stop` (forces cleanup), then `artisan_start`.

### `The session has no stdinPipe entry`

Cause: either the app was started by an artisan predating the FIFO refactor,
or the state file was hand-written without it. The second is the likelier one
now, and it is why hand-writing is the wrong recovery: `stdinPipe` holds the
path `start` creates for `flutter run`'s stdin, and `reload` / `hot-restart`
write their keystroke into it, so a file without it cannot hot restart.

```
artisan_restart        # rewrites the session with the current schema
```

### `Expression compilation error` / `RPCError(code: 113)` (tinker only)

Cause: the `eval` argument is not a valid single expression.

Recovery: rewrite. Common fixes:

- Strip trailing `;`
- Collapse `var x = 1; x + 1` to `(() { var x = 1; return x + 1; })()`
- Replace `import '...'` with a direct symbol access (if the symbol is
  already imported by `lib/main.dart`)
- See `${CLAUDE_SKILL_DIR}/references/tinker-eval.md` for the recipe pack.

### `Runtime exception: ...` (tinker only)

Cause: the expression compiled but threw at runtime. This is a real bug
in the running code or wrong input.

Recovery: read the Dart exception class and message. Fix the app code
or change the expression.

### `Isolate sentinel (kind: ...)`

Cause: stale isolate id (usually mid-hot-restart). The retry path in
`VmServiceClient.callServiceExtension` should auto-recover; persistent
failure means the isolate is gone.

```
artisan_hot_restart   # forces a clean isolate id
<retry the failing tool>
```

### `mkfifo failed (Windows not yet supported; V1 is POSIX-only)`

Cause: `artisan_start` on Windows.

V1 limitation. Surface to the user; there is no agent-side recovery.

### `Port <web-port> is already in use` (CDP path)

Cause: `artisan_start --cdp-port=<N> --port=<web-port>` detects that the
web port (the `--port` value, not the CDP port) is already in use and fails
fast before spawning any processes. The error names the busy web port and
suggests running `fsa stop` or selecting a different `--port`.

Recovery:

```bash
lsof -ti tcp:<web-port>             # find the squatter on the web port
kill <squatter pid>                 # or pick a different --port
./bin/fsa start --cdp-port=<N> --port=<new-web-port>
```

The port probe runs before Chrome and the flutter web-server launch, so
no orphaned processes are left. This fail-fast behavior replaces the prior
90s timeout that could leave stale sessions (issue #25).

### `Chrome failed to open debug port <port>`

Cause: `artisan_start --cdp-port=<N>` with Chrome missing, or a Chrome
initialization failure after the port probe passed.

```bash
# Confirm Chrome is installed:
which google-chrome                 # Linux
ls /Applications/Google\ Chrome.app # macOS
```

If Chrome is missing: the `Chrome binary not found` message names the
expected path (macOS: `/Applications/Google Chrome.app/Contents/MacOS/Google Chrome`;
Linux: `google-chrome` on PATH).

If Chrome initialization fails after the port probe, `artisan_start` reaps
the spawned Chrome process, flutter web-server, FIFO pipe, and temporary
profile directory before returning an error (issue #25). Run `artisan start`
again once Chrome is healthy.

### `Flutter SDK <X> is older than 3.30.0` (CDP path)

Cause: `artisan_start --cdp-port` requires the WebSocket hot reload fix
from flutter/flutter#170612 (landed in 3.30.0).

Recovery: `flutter upgrade`, then retry. If staying on the older SDK,
drop the `--cdp-port` flag and use the standard Chrome target (no CDP
features available without it).

### `port 3100 free` ✗ (doctor)

Cause: another process holds TCP 3100 (the default web port).

```bash
lsof -ti tcp:3100                   # find the squatter
kill <squatter pid>                 # or pass --port=<N> to artisan_start
```

### `fsa: waiting for another fsa invocation to finish...` (does not clear)

Cause: stale `.artisan/.fsa.lock/` directory after a hard kill of a
prior fsa run.

```bash
rm -rf .artisan/.fsa.lock
./bin/fsa <cmd>
```

The PID-aware lock probe should reclaim automatically; manual cleanup
is the fallback when it does not.

### Plugin tool returns "No tool registered with the name <X>"

Cause: dart_mcp's native error envelope. Either the tool was denied by
the filter, or the plugin provider was not loaded.

```
1. Call artisan_list, confirm the tool's namespace is missing.
2. If namespace missing: follow "Diagnosing missing plugin tools" above.
3. If namespace present: check .artisan/mcp.json + env vars + CLI flags
   on `mcp:serve`. The filter is denying the specific tool.
4. Reconnect the MCP client after fixing.
```

## Quick state cleanup

When the running app is wedged in an unrecoverable state and a fresh
start is preferred:

```bash
./bin/fsa stop                          # SIGTERM + cleanup if possible
rm -rf ~/.artisan/sessions              # force clean (state + FIFO + log)
rm -f  ~/.artisan/state.json            # the legacy pointer
./bin/fsa start --device=chrome         # fresh boot
```

`rm -rf ~/.artisan/sessions` clears EVERY project's session, so prefer
stopping the one you mean. `./bin/fsa doctor` prints the path this
project resolves to when you want to remove just that directory.

After this, the next MCP call automatically lazy-reconnects.

## Running two projects at once

Each project gets its own session directory, so state, log and FIFO no
longer collide. Ports still do: give each session its own.

```bash
# project A
./bin/fsa start --device=chrome --port=3100 --cdp-port=9333 --vm-service-port=8181

# project B, in another checkout
./bin/fsa start --device=chrome --port=3180 --cdp-port=9380 --vm-service-port=8281
```

Commands resolve the session from the working directory, so run them
from inside the project they belong to. A command that would act on
another project's app refuses instead, naming both paths; pass
`--state=<path>` when you genuinely mean a session outside this
directory.

**Do not `fsa restart` blind in a worktree.** It carries the prior
session's device and all three ports across now, but a restart still
stops before it starts: if the relaunch fails, the app you were driving
is already gone.

## When to favour `./bin/fsa` over MCP

For high-frequency drop-to-Bash work (codegen, plugin install,
inspection of `.artisan/plugins.json`), prefer the CLI:

```bash
./bin/fsa list | rg dusk:               # quick filter
./bin/fsa plugin:install custom_plugin --dry-run | tee plan.yaml
./bin/fsa doctor                        # one-line health check
```

The MCP path is for in-session orchestration (start → tinker → reload →
status); the CLI path is for one-shot scripted work the agent needs to
chain with `jq`, `rg`, or `tee`.
