# Record reference

The 9 record types that ride inside the `telescope_*` MCP response
envelopes. Every record carries a `time` (or `timestamp`) field in ISO
8601, plus its own typed payload. Optional fields are omitted from JSON
when null, never serialized as `null`; check for key presence, not
truthiness.

For the envelope shape (`{"records": [...]}`, etc.), see `mcp-tools.md`.

## Contents

- [`HttpRequestRecord`](#httprequestrecord)
- [`LogRecordEntry`](#logrecordentry)
- [`ExceptionRecord`](#exceptionrecord)
- [`EventRecord`](#eventrecord)
- [`GateRecord`](#gaterecord)
- [`DumpRecord`](#dumprecord)
- [`QueryRecord`](#queryrecord)
- [`MagicCacheRecord`](#magiccacherecord)
- [`MagicModelRecord` (no MCP tool)](#magicmodelrecord-no-mcp-tool)
- [Time format](#time-format)
- [Field-presence rules](#field-presence-rules)

---

## HttpRequestRecord

Inside `telescope_requests` → `records[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `url` | string | yes | Full URL including scheme + query string. |
| `method` | string | yes | Uppercase: `GET`, `POST`, `PUT`, `PATCH`, `DELETE`. |
| `statusCode` | integer | yes | `0` when the call failed before a response (timeout, DNS). |
| `durationMs` | integer | yes | Wall-clock duration in milliseconds. |
| `isError` | boolean | yes | `true` for 4xx / 5xx or transport failures. |
| `timestamp` | string (ISO 8601) | yes | Note: this field is `timestamp`, not `time`, on HTTP records only. |
| `requestHeaders` | object (string → string) | opt | Often redacted by the adapter. |
| `requestBody` | string | opt | Truncated snippet; not the full payload. |
| `responseBody` | string | opt | Truncated snippet. |
| `attributedHeuristically` | boolean | opt (omitted when false) | `true` when the adapter could not directly associate the call to the request and inferred it from timing. Treat the record as best-effort. |

---

## LogRecordEntry

Inside `telescope_tail` → `messages[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `level` | string | yes | Uppercase name: `FINEST`, `FINER`, `FINE`, `CONFIG`, `INFO`, `WARNING`, `SEVERE`, `SHOUT`. |
| `levelValue` | integer | yes | Numeric value from `package:logging`. Useful for ordering without parsing the string. |
| `message` | string | yes | The log message body. |
| `loggerName` | string | yes | The named logger that emitted the record (`UserController`, `Magic.Http`, etc.). |
| `time` | string (ISO 8601) | yes | |
| `error` | string | opt | `error.toString()` when the Logger call attached an error object. |
| `stackTrace` | string | opt | Full stack trace when attached. |

---

## ExceptionRecord

Inside `telescope_exceptions` → `exceptions[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `exceptionType` | string | yes | `runtimeType.toString()` of the thrown object. |
| `message` | string | yes | `exception.toString()`. |
| `time` | string (ISO 8601) | yes | |
| `stackTrace` | string | opt | Full stack trace when one was attached. |
| `isolate` | string | opt | Source isolate name (`main`, worker name). |

Only uncaught exceptions. A swallowed `try / catch` does not produce a
record here.

---

## EventRecord

Inside `telescope_events` → `events[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `eventType` | string | yes | Class name of the dispatched event (`AuthLoginSucceeded`, `ModelSaved`, etc.). |
| `payload` | object | yes | Empty `{}` in current builds (structured payload extraction is V1.x backlog). |
| `time` | string (ISO 8601) | yes | |
| `listenerCount` | integer | opt | Number of registered listeners at dispatch time. |

---

## GateRecord

Inside `telescope_gates` → `gates[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `ability` | string | yes | Ability name as registered (`users.destroy`, `users.create`). |
| `result` | boolean | yes | `true` for allow, `false` for deny. |
| `arguments` | array | yes | Positional arguments passed to `Gate.allows / .denies`. Each entry is JSON-stringified via its `toString()` (no `toJson` indirection). |
| `time` | string (ISO 8601) | yes | |
| `userId` | string | opt | Authenticated user's id at the check moment; absent for guest. |

---

## DumpRecord

Inside `telescope_dumps` → `dumps[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `message` | string | yes | The full string passed to `debugPrint`. |
| `time` | string (ISO 8601) | yes | |
| `wrapWidth` | integer | opt | The `wrapWidth` argument when supplied. |

Only `debugPrint("...")` produces a record here. Plain Dart `print(...)`
does NOT route through the `debugPrint` callback `DumpWatcher` overrides,
so `print("...")` output is invisible to `telescope_dumps`; switch the
call site to `debugPrint(...)` (or add a wrapper that forwards) when the
agent needs to see it. Raw `dart:io stdout.write` is also invisible.

---

## QueryRecord

Inside `telescope_queries` → `queries[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `sql` | string | yes | The SQL string as the QueryBuilder sent it. Bindings are placeholders (`?`). |
| `bindings` | array | yes | Bound parameters in order. Each entry preserves its Dart type (string, int, double, bool, null). |
| `timeMs` | integer | yes | Execution duration in milliseconds. |
| `connectionName` | string | yes | `default` unless the consumer named a non-default connection. |
| `time` | string (ISO 8601) | yes | |

---

## MagicCacheRecord

Inside `telescope_caches` → `caches[]`.

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `operation` | string | yes | One of `put`, `hit`, `miss`, `forget`, `flush`. |
| `key` | string | yes | The cache key. |
| `time` | string (ISO 8601) | yes | |
| `ttlMs` | integer | opt | TTL in milliseconds (`Duration.inMilliseconds`). Absent for operations that do not carry a TTL (`hit`, `miss`, `forget`, `flush`). |

The cache buffer is currently a placeholder (Magic does not yet emit
the events); records will start appearing once Magic ships them.

---

## MagicModelRecord (no MCP tool)

The `_magicModels` buffer exists and is populated by `MagicModelWatcher`,
but no MCP tool surfaces it. The record shape (visible to Dart callers
via `TelescopeStore.recentModels()`):

| JSON key | Type | Required | Notes |
|---|---|---|---|
| `modelClass` | string | yes | E.g. `User`, `Order`. |
| `event` | string | yes | One of `created`, `saved`, `deleted`. |
| `modelKey` | string | yes | The primary key of the affected row. |
| `time` | string (ISO 8601) | yes | |
| `attributes` | object | opt | The model's serialized attributes at the moment of the event. |

To inspect model lifecycle from the agent, use `telescope_events` and
filter on `eventType` matching `ModelCreated`, `ModelSaved`,
`ModelDeleted`. Those events flow through `Event.dispatch()` and surface
in the events buffer.

---

## Time format

Every `time` and `timestamp` field is an ISO 8601 string with UTC
offset, produced by `DateTime.toIso8601String()`:

```
2026-05-25T09:14:22.318Z
2026-05-25T11:14:22.318+02:00
```

Records are inserted at the moment of capture inside the running app's
isolate; clock drift between the agent host and the app is irrelevant
for ordering (the ring buffer order is insertion order, not timestamp
order).

---

## Field-presence rules

- Optional fields are omitted when null; they are never serialized as
  `"field": null`. Check for key presence with `containsKey`, not
  truthiness.
- `attributedHeuristically` on `HttpRequestRecord` is the one boolean
  that follows the omit-when-false convention; expect it absent on
  every directly-attributed call.
- Numeric fields default to zero where meaningful (`statusCode: 0` for
  pre-response failures, `timeMs: 0` for zero-duration queries) rather
  than being omitted.
- Arrays are always present (`bindings: []`, `arguments: []`) even when
  empty; they are never null.
