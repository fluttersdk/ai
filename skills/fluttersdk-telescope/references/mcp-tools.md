# MCP tools reference

Authoritative source: `lib/src/telescope_artisan_provider.dart` (all 9 `McpToolDescriptor` entries, descriptions,
and input schemas). VM extension registrations: `lib/src/extensions/register_telescope_extensions.dart`.

## Overview

Telescope contributes 9 MCP tools to the fluttersdk artisan dispatcher. All use the `telescope_` prefix. Each
tool is backed by a `ext.telescope.*` VM Service extension registered in the running Flutter app. The tools are
read-only (except `telescope_clear`) and return JSON arrays of immutable records from ring buffers in
`TelescopeStore`. Records are returned newest-first.

**Prerequisites:** the running app must have called `TelescopePlugin.install()` (and the relevant watcher
registrations) before the tool can return any records. If the extension is registered but no watcher has fed
the buffer, the tool returns an empty array, not an error.

**Common workflow for an LLM agent:**

```
1. artisan_start (start the Flutter app)
2. telescope_clear (zero out all buffers)
3. <trigger the user action or navigation>
4. telescope_requests / telescope_tail / telescope_exceptions (inspect results)
```

---

## Tool catalog

### telescope_tail

**VM extension:** `ext.telescope.console`
**Buffer:** `TelescopeStore.recentLogs()`
**Populated by:** `LogWatcher` (auto-installed; subscribes to `Logger.root.onRecord`)

Return recent log records from the running Flutter app. Each record carries timestamp, log level, logger name,
message, and optional error / stackTrace attachment.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `level` | string | no | Minimum log level to include. Values (lowest to highest): `FINEST`, `FINER`, `FINE`, `CONFIG`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`. Omit for all levels. |
| `limit` | integer | no | Maximum number of records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `LogRecordEntry` objects.

```json
[
  {
    "level": "WARNING",
    "loggerName": "MonitorController",
    "message": "poll failed, retrying in 5s",
    "time": "2026-05-21T10:14:22.000Z"
  }
]
```

**Usage notes:**

- Pair with `telescope_clear` before a repro to isolate the relevant log lines.
- For HTTP traffic use `telescope_requests`; for crashes use `telescope_exceptions`.
- If the app does not use `package:logging`, this tool returns an empty array. All Magic framework logs go through
  `package:logging` so they do appear here.

**Agent example:**

```
Call telescope_tail with level="WARNING" and limit=20 to check for recent warnings
after the user navigated to the monitors dashboard.
```

---

### telescope_requests

**VM extension:** `ext.telescope.requests`
**Buffer:** `TelescopeStore.recentHttp()`
**Populated by:** `DioHttpAdapter` (vanilla Dio) or `MagicHttpFacadeAdapter` (Magic apps)

Return recent HTTP request/response records from the running Flutter app. Each record carries method, URL,
status code, duration (ms), request headers, response body snippet, and `isError` flag.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | no | Maximum number of HTTP records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `HttpRequestRecord` objects.

```json
[
  {
    "url": "https://api.uptizm.com/monitors",
    "method": "GET",
    "statusCode": 200,
    "durationMs": 143,
    "isError": false,
    "timestamp": "2026-05-21T10:14:21.000Z",
    "responseBody": "{\"data\":[...]}"
  }
]
```

**Usage notes:**

- Only calls routed through an installed `TelescopeHttpAdapter` are captured. Raw `dart:io HttpClient` calls are
  invisible.
- `attributedHeuristically: true` appears on records when the adapter could not exactly match a response to its
  request (concurrent in-flight calls). Attribution is best-effort FIFO.
- Pair with `telescope_clear` to isolate the HTTP traffic of a specific user action.

---

### telescope_exceptions

**VM extension:** `ext.telescope.exceptions`
**Buffer:** `TelescopeStore.recentExceptions()`
**Populated by:** `ExceptionWatcher` (opt-in; hooks `FlutterError.onError` + `PlatformDispatcher.instance.onError`)

Return recent uncaught exception records. Each record carries timestamp, exception type, message, and full
stackTrace.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | no | Maximum number of exception records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `ExceptionRecord` objects.

```json
[
  {
    "exceptionType": "StateError",
    "message": "Bad state: no element",
    "time": "2026-05-21T10:14:25.000Z",
    "stackTrace": "#0 List.first (dart:core/list.dart:158)\n..."
  }
]
```

**Usage notes:**

- Covers uncaught exceptions only. `try / catch` blocks that swallow errors do NOT appear here.
- Requires `ExceptionWatcher` to have been registered before the exception occurred.
- Pair with `telescope_tail` (level="SEVERE") to see what the app logged around the crash.

---

### telescope_events

**VM extension:** `ext.telescope.events`
**Buffer:** `TelescopeStore.recentEvents()`
**Populated by:** `MagicEventWatcher` (Magic apps only)

Return recent in-app event records. Each record carries timestamp, event class name, and a JSON snapshot of
the event payload. Events are dispatched through Magic's `Event.dispatch()` facade.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | no | Maximum number of event records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `EventRecord` objects.

```json
[
  {
    "eventClass": "MonitorChecked",
    "payload": {"monitorId": "abc-123", "status": "up"},
    "time": "2026-05-21T10:14:22.000Z"
  }
]
```

**Usage notes:**

- Only events dispatched via the Magic `Event` facade appear here. Raw `ChangeNotifier.notifyListeners` calls
  are invisible.
- Requires `MagicEventWatcher` (registered by `MagicTelescopeIntegration.install()`).
- For gate checks use `telescope_gates`; for HTTP use `telescope_requests`.
- CLI access: MCP-only in V1 (no `telescope:events` CLI command).

---

### telescope_gates

**VM extension:** `ext.telescope.gates`
**Buffer:** `TelescopeStore.recentGates()`
**Populated by:** `MagicGateWatcher` (Magic apps only)

Return recent Gate authorization check records. Each record carries timestamp, ability name, result
(allowed / denied), authenticated user ID, and the argument class name when one was provided.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | no | Maximum number of gate check records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `GateRecord` objects.

```json
[
  {
    "ability": "monitors.destroy",
    "result": "denied",
    "userId": "user-456",
    "argumentClass": "Monitor",
    "time": "2026-05-21T10:14:23.000Z"
  }
]
```

**Usage notes:**

- Only checks routed through Magic's `Gate.allows` / `Gate.denies` are captured. Direct policy class calls are
  not recorded.
- Requires `MagicGateWatcher` (registered by `MagicTelescopeIntegration.install()`).
- Useful for debugging why a button is hidden or a route is blocked without modifying policy classes.
- CLI access: MCP-only in V1 (no `telescope:gates` CLI command).

---

### telescope_dumps

**VM extension:** `ext.telescope.dumps`
**Buffer:** `TelescopeStore.recentDumps()`
**Populated by:** `DumpWatcher` (opt-in; overrides global `debugPrint`)

Return recent debug print records. Each record carries timestamp and the full message string passed to
`debugPrint`.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | no | Maximum number of dump records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `DumpRecord` objects.

```json
[
  {
    "message": "MonitorController: polling interval set to 30s",
    "time": "2026-05-21T10:14:20.000Z"
  }
]
```

**Usage notes:**

- Only output routed through `debugPrint` (the Flutter global override point) is captured. `dart:io stdout.write`
  calls are invisible.
- Requires `DumpWatcher` to have been registered (opt-in).
- For structured logs use `telescope_tail`; for crashes use `telescope_exceptions`.
- CLI access: MCP-only in V1 (no `telescope:dumps` CLI command).

---

### telescope_queries

**VM extension:** `ext.telescope.queries`
**CLI command:** `telescope:queries`
**Buffer:** `TelescopeStore.recentQueries()`
**Populated by:** `MagicQueryWatcher` (Magic apps only; subscribes to `QueryExecuted` event)

Return recent database query records. Each record carries timestamp, SQL string, bindings list, execution time
(ms), and connection name.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | no | Maximum number of query records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `QueryRecord` objects.

```json
[
  {
    "sql": "SELECT * FROM monitors WHERE team_id = ?",
    "bindings": ["team-789"],
    "timeMs": 4,
    "connection": "default",
    "time": "2026-05-21T10:14:22.000Z"
  }
]
```

**Usage notes:**

- Only queries that go through Magic's QueryBuilder (dispatching `QueryExecuted` via the EventDispatcher) are
  recorded. Raw sqlite3 / Dio SQL calls bypass this tool.
- Requires `MagicQueryWatcher` (registered by `MagicTelescopeIntegration.install()`).
- For Magic Cache traffic use `telescope_caches`; for HTTP use `telescope_requests`.

---

### telescope_caches

**VM extension:** `ext.telescope.caches`
**CLI command:** `telescope:caches`
**Buffer:** `TelescopeStore.recentCaches()`
**Populated by:** `MagicCacheWatcher` (Magic apps only; subscribes to CacheHit / CacheMiss / CachePut /
CacheForget / CacheFlush events)

Return recent Magic Cache operation records. Each record carries timestamp, operation tag
(`hit | miss | put | forget | flush`), cache key, and optional TTL.

**Input schema:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `limit` | integer | no | Maximum number of cache records to return, newest first. Omit for the whole buffer (cap: 500). |

**Return shape:** JSON array of `MagicCacheRecord` objects.

```json
[
  {
    "key": "monitors.team-789",
    "tag": "miss",
    "time": "2026-05-21T10:14:21.000Z"
  },
  {
    "key": "monitors.team-789",
    "tag": "put",
    "ttl": 300,
    "time": "2026-05-21T10:14:21.000Z"
  }
]
```

**Usage notes:**

- Only `Magic.Cache` facade calls dispatch these events. Raw driver-level cache calls bypass this tool.
- Requires `MagicCacheWatcher` (registered by `MagicTelescopeIntegration.install()`).
- For DB queries use `telescope_queries`; for HTTP use `telescope_requests`.

---

### telescope_clear

**VM extension:** `ext.telescope.clear`
**CLI command:** `telescope:clear`
**Buffer:** all 9 buffers simultaneously

Clear every Telescope ring buffer (http, logs, exceptions, events, gates, dumps, queries, caches, models) in one
call. Use as a "set zero" before reproducing a bug so the next read returns only records produced after the clear.

**Input schema:** no parameters.

**Return shape:** empty JSON object `{}` (acknowledgment).

**Usage notes:**

- Idempotent: safe to call when buffers are already empty.
- Does NOT affect the live `package:logging` stream; only the captured ring buffers.
- Does NOT pause recording. New records start accumulating immediately after the clear.

---

## Tool summary table

| Tool | VM extension | CLI command | Requires watcher | limit param |
|------|-------------|-------------|-----------------|-------------|
| `telescope_tail` | `ext.telescope.console` | `telescope:tail` | `LogWatcher` (auto) | yes |
| `telescope_requests` | `ext.telescope.requests` | `telescope:requests` | `DioHttpAdapter` or `MagicHttpFacadeAdapter` | yes |
| `telescope_exceptions` | `ext.telescope.exceptions` | - | `ExceptionWatcher` (opt-in) | yes |
| `telescope_events` | `ext.telescope.events` | - | `MagicEventWatcher` (Magic) | yes |
| `telescope_gates` | `ext.telescope.gates` | - | `MagicGateWatcher` (Magic) | yes |
| `telescope_dumps` | `ext.telescope.dumps` | - | `DumpWatcher` (opt-in) | yes |
| `telescope_queries` | `ext.telescope.queries` | `telescope:queries` | `MagicQueryWatcher` (Magic) | yes |
| `telescope_caches` | `ext.telescope.caches` | `telescope:caches` | `MagicCacheWatcher` (Magic) | yes |
| `telescope_clear` | `ext.telescope.clear` | `telescope:clear` | none | no |

Pause and resume VM extensions (`ext.telescope.pause`, `ext.telescope.resume`) are registered in the app but NOT
surfaced as MCP tools in V1. They remain backlog.
