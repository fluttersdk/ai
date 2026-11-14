# MCP tools reference

Every `crumbs_*` tool `CrumbsDowelProvider.mcpTools()` declares. Each routes to one `ext.crumbs.*` extension through dowel's MCP server, which forwards the call's arguments unchanged.

## Contents

- [Calling convention](#calling-convention)
- [Tools](#tools)
- [Cursor, `logger` and `type`](#cursor-logger-and-type)
- [Errors](#errors)
- [Empty answers](#empty-answers)

## Calling convention

- The answer is one text block holding a JSON object; parse it before reading fields.
- Lists are oldest first; the last entry is the newest.
- `limit` (integer) keeps the newest N (with `since`, the oldest N after it); omitted, the whole buffer comes back. A value that does not parse as an integer reads the whole buffer, zero or below reads nothing.
- None of the tools takes a required parameter.

## Tools

| Tool | Extension | Parameters | Answer |
|---|---|---|---|
| `crumbs_tail` | `ext.crumbs.console` | `limit`, `level`, `logger`, `since` | `{messages: [LogRecordEntry], cursor}` |
| `crumbs_requests` | `ext.crumbs.requests` | `limit` | `{requests: [HttpRequestRecord]}` |
| `crumbs_exceptions` | `ext.crumbs.exceptions` | `limit` | `{exceptions: [ExceptionRecord]}` |
| `crumbs_dumps` | `ext.crumbs.dumps` | `limit` | `{dumps: [DumpRecord]}` |
| `crumbs_events` | `ext.crumbs.events` | `limit`, `type`, `since` | `{events: [EventRecord], cursor}` |
| `crumbs_gates` | `ext.crumbs.gates` | `limit` | `{gates: [GateRecord]}` |
| `crumbs_queries` | `ext.crumbs.queries` | `limit` | `{queries: [QueryRecord]}` |
| `crumbs_caches` | `ext.crumbs.caches` | `limit` | `{caches: [CacheRecord]}` |
| `crumbs_frames` | `ext.crumbs.frames` | `limit` | `{frames: [FramePerfRecord], livenessCounter}` |
| `crumbs_clear` | `ext.crumbs.clear` | none | `{cleared: true}` |

Record fields are in `records.md`.

- `crumbs_tail`: `level` is a minimum level name, compared case-insensitively against the `package:logging` order `FINEST`, `FINER`, `FINE`, `CONFIG`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`. A name outside that list (`ALL`, a typo) matches nothing. The buffer keeps every level; the filter runs at read time.
- `crumbs_exceptions`: errors that reach `FlutterError.onError` or `PlatformDispatcher.instance.onError`. An exception the code caught appears only if it logged it, and then in `crumbs_tail`.
- `crumbs_dumps`: `debugPrint` output only. `print` and `stdout.write` do not go through `debugPrint`.
- `crumbs_events`, `crumbs_gates`, `crumbs_queries`, `crumbs_caches`: filled only by the Magic watchers `MagicCrumbsIntegration` registers, which a `magic_devtools` release built on crumbs ships (auth, database and gate-definition events, checks through `Gate`, queries that dispatch `QueryExecuted`, `Cache` facade operations). Magic model events go to the model buffer, which no tool serves.
- `crumbs_frames`: `livenessCounter` is present on every answer, the list empty or not. It counts the frames an installed `FramePerfWatcher` has seen drawn, so it stays at zero when none is registered; when it does not move between two reads, either no watcher is installed or no frame was drawn between them. `blocks` is filled only while `FlutterTimeline` collection is on (a tapir perf session in its default attribution mode turns it on).
- `crumbs_clear`: empties every buffer the store holds, frames included. It does not touch the file sink's files or any other reporter.

The extensions `ext.crumbs.pause`, `ext.crumbs.resume`, `ext.crumbs.files` and `ext.crumbs.file` have no MCP tool. The timeline files are read with `crumbs:files` (see `cli-commands.md`).

## Cursor, `logger` and `type`

`crumbs_tail` and `crumbs_events` declare these beside `limit`:

| Parameter | On | Meaning |
|---|---|---|
| `since` | tail, events | Only records whose `atUs` is greater (microseconds). Not an integer: refused with `invalidParams` |
| `logger` | tail | Exact logger name |
| `type` | events | Prefix of `eventType` |

`cursor` in the answer is the largest `atUs` returned; with nothing returned it is the `since` you passed, or null without one. With `since`, `limit` keeps the oldest N after it and extends the page to every record sharing the last `atUs`, so passing `cursor` back as `since` reads each record that exists when the page is read exactly once; a record added later with the same microsecond `atUs` as the page's last record can be missed. Without `since`, `limit` keeps the newest N.

```text
crumbs_tail { logger: "Sync", limit: 20 }             {messages: [...], cursor: 1734567890123}
crumbs_tail { logger: "Sync", since: 1734567890123 }  only what Sync logged after that
```

## Errors

| Answer | Meaning | Next move |
|---|---|---|
| `VM Service connect failed` or `No Flutter app detected` | No running session dowel can reach | `./bin/dowel start --device=<device>`, then retry; the server reconnects on the next call |
| `ext.crumbs.<x> is not registered in the running app yet (still booting, a release build, or the plugin is not installed). Retry in a few seconds.` | The app has no crumbs extensions yet: still booting, not installed, guarded out by the build mode, or `CRUMBS_DISABLE` set | Retry a few times; if it persists, check the guard in `lib/main.dart` and `CRUMBS_DISABLE`, then restart the app |
| `since must be an integer number of microseconds.` | A `since` that is not an integer | Pass the `cursor` value as it came |

## Empty answers

An empty list is a verdict only once its producer is known to be registered:

| Empty | Check |
|---|---|
| `messages` | The app logs through `package:logging`; `level` is a real level name; `logger` is the exact name |
| `requests` | An HTTP adapter is registered, or an interceptor calls `CrumbsStore.recordHttp`: crumbs hooks no HTTP client itself |
| `exceptions` | `ExceptionWatcher` is registered |
| `dumps` | `DumpWatcher` is registered and the build is debug; the code calls `debugPrint`, not `print` |
| `events`, `gates`, `queries`, `caches` | `MagicCrumbsIntegration.install()` ran after `Magic.init()`, from a `magic_devtools` release built on crumbs |
| `frames` | `FramePerfWatcher` is registered; read `livenessCounter` |
| any | `crumbs_clear` or a hot restart ran since the action; the host called `CrumbsStore.pause()`; a throwing `redactor` dropped the records (logs, events, exceptions, HTTP, dumps, queries, gates) |
