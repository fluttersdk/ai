# MCP tool reference

Per-tool schema, response envelope, and example calls for the 9
`telescope_*` MCP tools. Every read tool returns a single
`{"<key>": [<record>, ...]}` JSON object inside a single `text` content
block; parse the `text` body as JSON before reasoning over fields.

For per-record field shape (every key inside the record objects), see
`records.md`.

## Contents

- [`telescope_requests`](#telescope_requests)
- [`telescope_tail`](#telescope_tail)
- [`telescope_exceptions`](#telescope_exceptions)
- [`telescope_events`](#telescope_events)
- [`telescope_gates`](#telescope_gates)
- [`telescope_dumps`](#telescope_dumps)
- [`telescope_queries`](#telescope_queries)
- [`telescope_caches`](#telescope_caches)
- [`telescope_clear`](#telescope_clear)
- [Common semantics](#common-semantics)
- [Empty-buffer diagnosis](#empty-buffer-diagnosis)

---

## telescope_requests

Outbound HTTP records captured by the registered `TelescopeHttpAdapter`.

**VM extension:** `ext.telescope.requests`.

**Input:**

```json
{ "limit": 20 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. Bad value silently falls back to whole buffer. |

**Response:**

```json
{
  "records": [
    {
      "url": "https://api.example.test/users",
      "method": "GET",
      "statusCode": 200,
      "durationMs": 184,
      "isError": false,
      "timestamp": "2026-05-25T09:14:22.318Z",
      "requestHeaders": { "Authorization": "Bearer ..." },
      "responseBody": "{\"data\":[...]}"
    }
  ]
}
```

**Origin:** populated only when a `TelescopeHttpAdapter` is registered.
Magic-stack apps get `MagicHttpFacadeAdapter` via
`MagicTelescopeIntegration.install()`. Vanilla Dio apps register
`DioHttpAdapter` manually. Raw `dart:io HttpClient` is invisible.

**Common pattern:** call right after a `dusk_tap` that submitted a
form; filter the `records` array on `method == 'POST'` and a URL
substring to find the call of interest.

---

## telescope_tail

Structured log records from `package:logging`.

**VM extension:** `ext.telescope.console`.

**Input:**

```json
{ "level": "WARNING", "limit": 50 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `level` | string | no filter | Minimum-threshold filter. Uppercase names from `package:logging` (`FINEST`, `FINER`, `FINE`, `CONFIG`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`). Case-insensitive inside the handler. |
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "messages": [
    {
      "level": "WARNING",
      "levelValue": 900,
      "message": "User 42 reload returned no data",
      "loggerName": "UserController",
      "time": "2026-05-25T09:14:22.318Z",
      "error": "...",
      "stackTrace": "..."
    }
  ]
}
```

**Level threshold semantics:** `level: "WARNING"` returns WARNING (900)
+ SEVERE (1000) + SHOUT (1200) only. `level: "INFO"` adds INFO (800) on
top. Omit `level` to get every level.

**Capture gate:** `LogWatcher` sets `Logger.root.level = Level.ALL`,
so every record is captured regardless of named-logger thresholds.
The `level` filter only narrows what comes back from the buffer; the
buffer itself still holds the lower-level records (re-querying without
the filter recovers them).

**Origin:** `LogWatcher` auto-installs as part of
`TelescopePlugin.install()`. Always wired in a telescope-enabled app.

---

## telescope_exceptions

Uncaught exception records.

**VM extension:** `ext.telescope.exceptions`. **MCP-only**, no CLI
mirror in V1.

**Input:**

```json
{ "limit": 5 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "exceptions": [
    {
      "exceptionType": "AuthorizationException",
      "message": "Ability 'users.destroy' denied",
      "time": "2026-05-25T09:14:22.318Z",
      "stackTrace": "...",
      "isolate": "main"
    }
  ]
}
```

**Capture surface:** `FlutterError.onError` and
`PlatformDispatcher.instance.onError`, chained over any prior handler
(Sentry / Bugsnag still receive the same throw). Swallowed `try /
catch` is invisible by design; pair with `telescope_tail` to catch a
breadcrumb the swallower logged.

**Origin:** populated only when `ExceptionWatcher` is registered (opt-
in via `TelescopePlugin.registerWatcher(ExceptionWatcher())`).
`telescope:install` adds this line during bootstrap.

---

## telescope_events

In-app events dispatched through Magic's `Event` facade.

**VM extension:** `ext.telescope.events`. **MCP-only**, no CLI mirror
in V1.

**Input:**

```json
{ "limit": 10 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "events": [
    {
      "eventType": "AuthLoginSucceeded",
      "payload": {},
      "time": "2026-05-25T09:14:22.318Z",
      "listenerCount": 3
    }
  ]
}
```

**Coverage:** `MagicEventWatcher` listens for `AuthLogin`,
`AuthLogout`, `AuthFailed`, `AuthRestored`, `DatabaseConnected`,
`GateAbilityDefined`, `GateBeforeRegistered`, plus `ModelCreated`,
`ModelSaved`, `ModelDeleted`. To inspect Magic model lifecycle from
the agent, query this buffer and filter on `eventType` containing
`Model`.

`payload` is `{}` in the V1 release (placeholder; structured payload
extraction is V1.x backlog). Raw
`ChangeNotifier.notifyListeners` calls are not captured.

**Origin:** requires `MagicTelescopeIntegration.install()`. Without
it the buffer stays empty.

---

## telescope_gates

Gate authorization checks.

**VM extension:** `ext.telescope.gates`. **MCP-only**, no CLI mirror
in V1.

**Input:**

```json
{ "limit": 20 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "gates": [
    {
      "ability": "users.destroy",
      "result": false,
      "arguments": ["User#42"],
      "time": "2026-05-25T09:14:22.318Z",
      "userId": "user_7"
    }
  ]
}
```

**Coverage:** every `Gate.allows(...)` / `Gate.denies(...)` call.
`result` is the bool the facade returned; `arguments` is the list
passed positionally (each entry serialized as its `runtimeType.toString()`
unless it has its own `toJson`). `userId` is the authenticated user's
id at the time of the check (string-stringified), or absent for guest.

**Origin:** requires `MagicTelescopeIntegration.install()`.

---

## telescope_dumps

`debugPrint` captures.

**VM extension:** `ext.telescope.dumps`. **MCP-only**, no CLI mirror in
V1.

**Input:**

```json
{ "limit": 50 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "dumps": [
    {
      "message": "UserController: rxState=loaded",
      "time": "2026-05-25T09:14:22.318Z",
      "wrapWidth": 80
    }
  ]
}
```

**Capture surface:** global `debugPrint` override that chains the
prior implementation. Only calls that go through the `debugPrint`
callback are captured. Plain Dart `print(...)` does NOT route through
`debugPrint`, so `print("...")` output is invisible to this buffer;
callers must use `debugPrint(...)` to land in `telescope_dumps`. Raw
`dart:io stdout.write` and `stderr.write` are also invisible.

**Origin:** populated only when `DumpWatcher` is registered (opt-in
via `TelescopePlugin.registerWatcher(DumpWatcher())`).
`telescope:install` adds this line during bootstrap. The watcher
self-gates on `kDebugMode` and never captures in release builds.

---

## telescope_queries

DB queries via Magic's QueryBuilder.

**VM extension:** `ext.telescope.queries`.

**Input:**

```json
{ "limit": 50 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "queries": [
    {
      "sql": "SELECT * FROM users WHERE team_id = ?",
      "bindings": ["team_3"],
      "timeMs": 4,
      "connectionName": "default",
      "time": "2026-05-25T09:14:22.318Z"
    }
  ]
}
```

**Coverage:** every query dispatched via `MagicQueryWatcher` listening
on the `QueryExecuted` event. Raw `sqlite3` / `drift` / `package:sqflite`
calls are invisible.

**Origin:** requires `MagicTelescopeIntegration.install()`.

---

## telescope_caches

Magic Cache operations.

**VM extension:** `ext.telescope.caches`.

**Input:**

```json
{ "limit": 20 }
```

| Field | Type | Default | Notes |
|---|---|---|---|
| `limit` | integer | whole buffer | Cap on records returned. |

**Response:**

```json
{
  "caches": [
    {
      "operation": "hit",
      "key": "team:3:users",
      "time": "2026-05-25T09:14:22.318Z",
      "ttlMs": 300000
    }
  ]
}
```

`operation` is one of `put`, `hit`, `miss`, `forget`, `flush`. `ttlMs`
is the TTL in milliseconds (converted from `Duration` on the producer
side); absent for operations that do not carry a TTL.

**Current state:** placeholder. Magic's `Cache` facade does not yet
emit the cache events `MagicCacheWatcher` subscribes to, so this
buffer reads as `{"caches": []}` in current builds. The watcher is
wired and ready for when Magic ships the events.

**Origin:** requires `MagicTelescopeIntegration.install()` (when
events ship).

---

## telescope_clear

Wipe all 9 ring buffers atomically.

**VM extension:** `ext.telescope.clear`.

**Input:**

```json
{}
```

No parameters.

**Response:**

```json
{ "cleared": true }
```

Idempotent: safe to call when buffers are already empty. Does NOT
affect live subscriptions (`package:logging` Logger streams, the
`onXRecord` broadcast streams inside the running app); only the
captured ring buffers are emptied.

`ext.telescope.pause` and `ext.telescope.resume` exist as VM
extensions for completeness but are deliberately not surfaced as MCP
tools in V1. Reach for them only from Dart code via
`TelescopeStore.pause()` / `.resume()` in a custom helper.

---

## Common semantics

- **Envelope wrapping.** MCP returns the JSON object as a single
  `text` content block: `{ "content": [{ "type": "text", "text":
  "<json string>" }], "isError": false }`. Parse the `text` body as
  JSON before reasoning over fields.

- **Tool naming.** Tools surface to the model as
  `mcp__fluttersdk__telescope_<name>` (the `.mcp.json` server key is
  `fluttersdk`). The `telescope_` prefix is part of the tool name, not
  the server.

- **Ordering.** Records come back in chronological order (oldest at
  index 0). The handler does not reverse the queue. Iterate from the
  end for newest-first.

- **Cap.** Each ring buffer holds 500 records by default; older
  entries evict silently on overflow. Without `limit`, the response
  carries up to 500 records per buffer.

- **Bad input is silent.** Invalid `limit` (non-numeric string)
  coerces to null, returning the whole buffer. Invalid `level` (a name
  not in the `package:logging` order list) is also lenient and returns
  the whole buffer, not empty: `_meetsLevel` resolves the threshold
  with `List.indexOf` and falls back to `-1` on a miss, so every
  captured level (indices 0..7) passes the `actual >= min` check. No
  error envelope is emitted; the handler always returns
  `ServiceExtensionResponse.result`.

- **Hot-restart safety.** All 11 extensions register via
  `registerExtensionIdempotent` from `fluttersdk_artisan`. Hot
  restart re-runs the install code without re-registration errors.

- **Pause / resume gating.** When `TelescopeStore.pause()` is called
  (no MCP tool, Dart-only), all `recordX` methods early-return. The
  buffers retain their existing records; reading still works.
  `resume()` re-enables recording.

---

## Empty-buffer diagnosis

When a tool returns an empty array on an active app, the watcher /
adapter is the most likely missing piece:

| Tool empty | Likely cause | Fix |
|---|---|---|
| `telescope_requests` | No `TelescopeHttpAdapter` registered | Call `MagicTelescopeIntegration.install()` (Magic) or `TelescopePlugin.registerHttpAdapter(DioHttpAdapter(dio))` (vanilla). |
| `telescope_tail` | `LogWatcher` not auto-installed (very rare; only if `TelescopePlugin.install()` was skipped) | Confirm `TelescopePlugin.install()` runs inside the `kDebugMode` block in `main.dart`. |
| `telescope_exceptions` | `ExceptionWatcher` not registered | Add `TelescopePlugin.registerWatcher(ExceptionWatcher())`. |
| `telescope_dumps` | `DumpWatcher` not registered, or the code uses `dart:io stdout.write` | Add `TelescopePlugin.registerWatcher(DumpWatcher())`; rewrite calls to `debugPrint`. |
| `telescope_events` | `MagicTelescopeIntegration.install()` not called | Add the call after `Magic.init()` inside the `kDebugMode` block. |
| `telescope_gates` | Same as events | Same fix. |
| `telescope_queries` | Same as events, or queries use `sqlite3` directly | Same fix; or migrate the call to the Magic QueryBuilder. |
| `telescope_caches` | Magic does not yet emit cache events (V1 placeholder) | Wait for Magic to ship cache events; nothing to fix in telescope. |

If every tool reads empty: the app is not running, the VM Service is
not reachable, or `TelescopePlugin.install()` itself was skipped.
Confirm with `./bin/fsa status`.
