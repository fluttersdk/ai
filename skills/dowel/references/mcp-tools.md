# MCP tools

The substrate tools are the builtin commands in `_safeDowelCommandNames` (`lib/src/mcp/mcp_server.dart`), named `dowel_<command>` with `:` and `-` turned into `_`. Each tool's description and input schema reach the client through `tools/list`, so this file does not repeat them. It holds what they do not say: the result envelope, how each tool behaves over MCP, and the filter.

## Contents

- [Result envelope](#result-envelope)
- [Tools](#tools)
- [Plugin tools](#plugin-tools)
- [Filter](#filter)

## Result envelope

- A substrate tool returns text that starts with `` # `dowel <cmd>` exit N ``, then the command's captured output: errors as `[ERROR] <message>`, warnings after the data. `isError` is true when `N` is not 0, so exit 75 ("not ready, retry") arrives as an error: retry it.
- Only the captured output reaches the result, so a command writes through its output object: under `mcp:serve` the process stdout is the JSON-RPC channel, and a raw write there corrupts the stream.
- Failures on the MCP side (no session, a failed connect for a plugin tool, an uncaught exception inside a command) return `### Error`, then the message, with `isError: true`; an uncaught exception inside a command adds a stack trace. A failed VM Service connect for `dowel_tinker` is not caught by that handler, so its error result can omit the `### Error` prefix. Application failures never become JSON-RPC protocol errors; those arise only for a malformed call.
- Plugin tools and `dowel_tinker` with no usable session answer with the `### Error` texts in the Recovery table of `SKILL.md`.

## Tools

Boot mode is `none` for every tool except `dowel_tinker` (`connected`).

| Tool | Behaviour the description omits |
|---|---|
| `dowel_start` | Spawns `flutter run` and records the session; it never checks for an existing one. It takes every option `start` takes: `cdp-port` and `timeout` are numeric strings, `flutter-arg` is an array of strings (`["--dart-define=K=V"]`) and `restart` carries it. Success lines: `flutter run pid=<n>`, `vmServiceUri=<ws>`, `state=<path>`, `log=<path>`. Exit 75 while the build is still running. |
| `dowel_stop` | Stops the app and deletes the session. On an Android serial it also runs `adb shell am force-stop`. If it cannot kill the app it keeps the session and exits 1. Refuses a session owned by another project. |
| `dowel_restart` | Stops, then starts with the prior session's device, ports, `flutterArgs` and build mode. It takes `device`, `port`, `vm-service-port`, `cdp-port`, `profile-static` and `flutter-arg`: an omitted one keeps the prior value, so pass only the setting to change (`profile-static: false` forces a debug build; any `flutter-arg` replaces the whole carried set, and `flutter-arg: []` clears it). |
| `dowel_reload`, `dowel_hot_restart` | Write `r` or `R` into the FIFO and exit 0 once the keystroke is written, before Flutter finishes: read the log for the effect. Exit 2 when the pipe is missing or the session has no `stdinPipe`. |
| `dowel_status` | JSON with `running`, `pid`, `alive`, `vmServiceUri`, `device`, `webPort`, `startedAt`, `projectRoot`, `ownedByThisProject` and, while booting, `booting`. `{"running": false}` means no session and no pointer. A pointer to another project's app gives `running: true, ownedByThisProject: false`, with a warning after the JSON. |
| `dowel_logs` | Returns the whole captured log in the result text, after the header, once. It takes no `follow`: a tool call answers only when the command ends and a tail never ends, so following is a CLI feature (`./bin/dowel logs --follow` from a shell), and a call that passes `follow: true` is refused with `isError`. With no log yet it answers `Log file not found at <path>` with exit 1. |
| `dowel_doctor` | The hard checks (`flutter --version`, `dart --version`, port 3100 free, Flutter SDK 3.30.0 or newer for `--cdp-port`); exit 1 if one fails. Advisory `WARN:` lines, such as an old MCP entry, do not change the exit code. |
| `dowel_list` | The command catalogue; plugin namespaces appear only through the dispatcher entry. |
| `dowel_tinker` | The only `connected` tool; see `tinker-eval.md`. It runs no session ownership check. A blank `eval` is a usage error (exit 1), never the REPL. |

## Plugin tools

Plugin tools live in plugin packages and load only through the dispatcher entry (`./bin/dowel mcp:serve` or `dart run :dispatcher mcp:serve`). They are not substrate tools and are called through the VM Service extension the plugin registered at app boot; `tapir_evaluate` goes through `evaluate` directly. The `tapir` and `crumbs` skills document the tools of those plugins.

Once connected, the server keeps that client until the app goes away: it then drops the client and dials the session's current URI on the next call, so a `dowel_stop` and `dowel_start`, a `dowel_restart` or a device change needs no MCP client reconnect (reconnect only if calls keep failing). No plugin tool checks session ownership, so in a worktree without its own session they act on whatever `~/.dowel/state.json` names.

## Filter

Tools are allowed or denied by three layers, merged in `McpFilterConfig`:

1. `.dowel/mcp.json`, read relative to the working directory (not the project root).
2. Environment variables, comma separated: `DOWEL_MCP_PACKAGES_ALLOW`, `DOWEL_MCP_PACKAGES_DENY`, `DOWEL_MCP_TOOLS_ALLOW`, `DOWEL_MCP_TOOLS_DENY`.
3. `mcp:serve` flags `--include-package`, `--exclude-package`, `--include-tool`, `--exclude-tool`.

An allow list comes from the first layer that sets one (flag, then environment, then file) and replaces the others; deny lists are the union of all three, and deny beats allow. Names match the MCP tool name (`dowel_hot_restart`, not `hot-restart`). The substrate tools belong to provider `dowel`, so a package allow list drops them unless it names `dowel`, and a tool allow list hides every tool it does not list. Denied tools are removed before registration and never appear in `tools/list`. The filter is read once at start: after changing it, restart the server and reconnect the client. A malformed `.dowel/mcp.json` makes `mcp:serve` exit 3.
