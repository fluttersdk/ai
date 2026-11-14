# CLI commands reference

Every `crumbs:*` command `CrumbsDowelProvider.commands()` registers, run from a shell. The read commands mirror an MCP tool by name and call the same extension. `crumbs:install` and `crumbs:files` are CLI only; `crumbs_exceptions` has no command.

## Contents

- [Entry points](#entry-points)
- [Output and exit codes](#output-and-exit-codes)
- [Read commands](#read-commands)
- [crumbs:files](#crumbsfiles)
- [crumbs:install](#crumbsinstall)

## Entry points

| Form | When |
|---|---|
| `./bin/dowel <cmd>` | The default once `crumbs:install` scaffolded it: the consumer's compiled dowel CLI |
| `dart run crumbs <cmd>` | Before `./bin/dowel` exists; loads the crumbs commands itself, slower to start |
| `dart run dowel <cmd>` | The consumer's dispatcher, once the plugin is registered |

Every command but `crumbs:install` needs a running app started by dowel (`./bin/dowel start --device=<device>`) in the same project.

## Output and exit codes

- One line per record, oldest first, on stdout. An empty buffer prints a warning and exits 0; every command but `crumbs:tail` and `crumbs:files` names the missing producer in it (`No DB query records (register MagicQueryWatcher).`), and `crumbs:tail` and `crumbs:events` print no warning under `--json` or `--follow`.
- `--json` exists on `crumbs:tail` and `crumbs:events` only: one JSON object per line, the record as the extension returned it.
- Exit codes come from dowel's dispatcher: 0 success, 1 when the project has no running session (or it belongs to another project), 3 when the call throws (a non-integer `--since` on `crumbs:tail` or `crumbs:events` ends here, as `Connected command ... failed`), 75 when the app has not registered `ext.crumbs.*` yet (still booting, a release build, or crumbs is not installed: retry in a few seconds). `crumbs:files` exits 1 when the sink refuses.

## Read commands

| Command | Extension | Flags (default) | Line format |
|---|---|---|---|
| `crumbs:tail` | `ext.crumbs.console` | `--limit` (50), `--level`, `--logger`, `--since`, `--json`, `--follow` | `<time> [<LEVEL>] <logger>: <message>` |
| `crumbs:requests` | `ext.crumbs.requests` | `--limit` (50) | `<timestamp> <METHOD> <url> → <status> (<ms>ms) atUs=<atUs>` plus `requestId=`, `interactionId=`, `linkedBy=` when set |
| `crumbs:events` | `ext.crumbs.events` | `--limit` (50), `--type`, `--since`, `--json`, `--follow` | `<time> <eventType> <payload>` plus `listeners=<n>` when known |
| `crumbs:gates` | `ext.crumbs.gates` | `--limit` (50) | `<time> <ability> allowed\|denied user=<id> arguments=[...]` |
| `crumbs:dumps` | `ext.crumbs.dumps` | `--limit` (50) | `<time> <message>` |
| `crumbs:queries` | `ext.crumbs.queries` | `--limit` (50) | `<time> [<connection>] <sql> bindings=[...] (<ms>ms)` |
| `crumbs:caches` | `ext.crumbs.caches` | `--limit` (50) | `<time> [<operation>] <key>` plus `ttl=<ms>ms` when set |
| `crumbs:frames` | `ext.crumbs.frames` | `--limit` (50) | `<time> frame#<n> atUs=<atUs> vsyncStartUs=<us> build=<n>us raster=<n>us vsync=<n>us total=<n>us blocks=<map>` plus `interactionId=`, `linkedBy=` when set, then `livenessCounter=<n>`; an empty answer prints the warning with the counter |
| `crumbs:clear` | `ext.crumbs.clear` | none | `Cleared crumbs buffers.` |

`--since` takes an `atUs` in microseconds and is exclusive; with it `--limit` keeps the oldest N after it. `--follow` re-reads every second from the cursor the last read returned, drops `--limit` after the first read and prints nothing on an empty poll; it ends only when the process is interrupted, so run it in the background. `--level` is a minimum level name (`INFO`, `WARNING`, `SEVERE`); an unknown name matches nothing, so it prints `No log records.` (nothing under `--json` or `--follow`).

```bash
./bin/dowel crumbs:tail --level=WARNING --limit=100
./bin/dowel crumbs:tail --logger=Sync --json --follow
./bin/dowel crumbs:events --type=Auth --json --since=1734567890123
./bin/dowel crumbs:requests --limit=20
```

## crumbs:files

Lists the running app's timeline files, newest first, as `<name> <bytes>`, earlier launches included. With `--name` it prints the whole lines of that file from `--offset` (bytes, default 0), a 64 KiB window per call (a single longer line comes back whole), and the offset to continue from as `next offset: <n>` at `-v`.

```bash
./bin/dowel crumbs:files
./bin/dowel crumbs:files --name=timeline-20261114T091500Z-1.jsonl -v
./bin/dowel crumbs:files --name=timeline-20261114T091500Z-1.jsonl --offset=<next offset>
```

A name is matched against the sink's own listing before any file is opened, so only a listed timeline file can be read. It prints an error and exits 1 when no sink runs (`No timeline file sink is running.`) or the name or offset is refused.

## crumbs:install

Boot mode `none`; run it from the app root as `dart run crumbs crumbs:install`. Each step is idempotent:

1. When `bin/dispatcher.dart` is missing, runs `dart run crumbs install`, dowel's scaffold (`bin/dispatcher.dart`, `./bin/dowel`, the generated plugin and command indexes).
2. Runs `dart run crumbs plugin:install crumbs`, which reads `install.yaml`, records the plugin in `.dowel/plugins.json` and regenerates `lib/app/_plugins.g.dart`.
3. Patches `lib/main.dart`: the `kReleaseMode` and crumbs imports, `WidgetsFlutterBinding.ensureInitialized()` when absent, and the `if (!kReleaseMode)` block with `CrumbsPlugin.install()`, `ExceptionWatcher` and `DumpWatcher` before `await Magic.init(` or, without one, `runApp(`. On a Magic app whose resolved `magic_devtools` ships crumbs' integration it adds `MagicCrumbsIntegration.install()` after `Magic.init()`; otherwise it warns. A `main.dart` that already calls `CrumbsPlugin.install(` gets no crumbs import and no crumbs block, and its Magic block takes the guard of the existing crumbs block (`kDebugMode` on an app wired by an earlier crumbs); and a missing `lib/main.dart` is skipped with a message.

It does not write `.mcp.json`: run `dart run crumbs mcp:install` after it; on macOS and Linux with `./bin/dowel` present the entry runs `./bin/dowel mcp:serve`; otherwise, and on Windows, it runs `dart run crumbs mcp:serve` (`--invocation=<name>` swaps the executable of that form).
