# Records reference

The JSON keys of each record as `toJson()` writes it, which is what an MCP answer, a `--json` line and a timeline line carry; a command's text line prints a subset. A key marked optional is left out when its value is null.

## Contents

- [Clocks and links](#clocks-and-links)
- [HttpRequestRecord](#httprequestrecord)
- [LogRecordEntry](#logrecordentry)
- [ExceptionRecord](#exceptionrecord)
- [DumpRecord](#dumprecord)
- [EventRecord](#eventrecord)
- [GateRecord](#gaterecord)
- [QueryRecord](#queryrecord)
- [CacheRecord](#cacherecord)
- [ModelRecord](#modelrecord)
- [FramePerfRecord](#frameperfrecord)

## Clocks and links

- `time` (or `timestamp` on HTTP) is the wall clock as ISO 8601, for display.
- `atUs` is a monotonic microsecond reading of `FlutterTimeline.now`, taken when the record is built. It orders records across buffers whatever the wall clock does; join on it. Exceptions, dumps and gates have none. The `since` cursor assumes a buffer's insertion order is its `atUs` order: a record built with an explicit `atUs` behind one already read is skipped by the next cursor read.
- `interactionId` and `linkedBy` (`zone`, `frame` or `window`) are set when the capturing site ties the record to one interaction (a tap, a navigation). `window` means no interaction was open and `interactionId` is null: join by `atUs`.
- `redacted` (logs, events, exceptions, HTTP) is true only when the host's `CrumbsRedaction.redactor` ran over the record before it was buffered.

## HttpRequestRecord

Answer key `requests`. The credential masking of `CrumbsRedaction` has already run: a hidden value reads `********`.

| Key | Type | Notes |
|---|---|---|
| `url` | String | The value of a credential-named query parameter reads `********`; the rest of the URL is as captured |
| `method` | String | |
| `statusCode` | int | |
| `durationMs` | int | |
| `isError` | bool | Set by the adapter |
| `timestamp` | String | Wall clock |
| `requestHeaders` | Map | Optional |
| `requestBody`, `responseBody` | String | Optional; the adapter decides what is kept |
| `attributedHeuristically` | bool | Present only when true: the adapter matched the response to its request by order, not by id |
| `requestId` | String | Optional; the adapter's exact pairing id |
| `startUs`, `endUs` | int | Optional; send and arrival on the `atUs` clock |
| `atUs`, `interactionId`, `linkedBy`, `redacted` | | See above |

An interceptor that calls `CrumbsStore.recordHttp` builds the record itself: `url`, `method`, `statusCode`, `durationMs`, `isError` and `timestamp` are required, the headers and bodies optional, and `atUs` comes from the clock unless set; `requestId`, `startUs`, `endUs`, `attributedHeuristically`, `interactionId` and `linkedBy` come from an adapter that sets them.

## LogRecordEntry

Answer key `messages`. Written by `LogWatcher` from `package:logging`.

| Key | Type | Notes |
|---|---|---|
| `level` | String | `FINEST` to `SHOUT` |
| `levelValue` | int | 300 (`FINEST`) to 1200 (`SHOUT`) |
| `message`, `loggerName` | String | |
| `time` | String | Wall clock |
| `error`, `stackTrace` | String | Optional |
| `atUs`, `redacted` | | |

## ExceptionRecord

Answer key `exceptions`. Written by `ExceptionWatcher`.

| Key | Type | Notes |
|---|---|---|
| `exceptionType` | String | The runtime type |
| `message` | String | |
| `time` | String | Wall clock; no `atUs` |
| `stackTrace`, `isolate` | String | Optional; `ExceptionWatcher` never sets `isolate` |
| `redacted` | bool | |

## DumpRecord

Answer key `dumps`. Written by `DumpWatcher` from `debugPrint`: `message`, `time`, optional `wrapWidth`. Free text: only a host `redactor` masks the message, and the record has no `redacted` flag.

## EventRecord

Answer key `events`. Written by an event watcher (Magic's, through `MagicCrumbsIntegration` in a `magic_devtools` release built on crumbs).

| Key | Type | Notes |
|---|---|---|
| `eventType` | String | The `type` filter is a prefix of this |
| `payload` | Map | Made JSON-safe at insert: a value `jsonEncode` cannot write (`NaN` and the infinities included), and a non-String key, is stored as its `toString()`; one whose `toString()` throws reads `<unprintable Type>` |
| `time` | String | |
| `listenerCount` | int | Optional |
| `atUs`, `interactionId`, `linkedBy`, `redacted` | | |

## GateRecord

Answer key `gates`: `ability`, `result` (true allowed, false denied), `arguments` (list), `time`, optional `userId`. A value under a credential-named key inside `arguments` reads `********`; a host `redactor` also masks its strings and the `userId`, never the `ability`. Made JSON-safe like an event payload. No `redacted` flag.

## QueryRecord

Answer key `queries`: `sql`, `bindings`, `timeMs`, `connectionName`, `time`, `atUs`, optional `interactionId`, `linkedBy`. A value under a credential-named key of a Map inside `bindings` reads `********` (a positional binding has no key); a host `redactor` also masks the `sql` and the strings in `bindings`, never the `connectionName`; `bindings` are made JSON-safe like an event payload; and nothing masks a credential written as a SQL literal without one. No `redacted` flag.

## CacheRecord

Answer key `caches`: `operation` (`hit`, `miss`, `put`, `forget`, `flush`), `key`, `time`, optional `ttlMs`, `atUs`, optional `interactionId`, `linkedBy`. Not masked.

## ModelRecord

No extension serves it; it is read in process with `CrumbsStore.recentModels()`. Keys: `modelClass`, `event`, `modelKey`, `time`, optional `attributes`, `atUs`, optional `interactionId`, `linkedBy`. Not masked.

## FramePerfRecord

Answer key `frames`, beside `livenessCounter`. Written by `FramePerfWatcher`.

| Key | Type | Notes |
|---|---|---|
| `frameNumber` | int | The engine's frame number |
| `buildMicros`, `rasterMicros`, `vsyncOverheadMicros`, `totalSpanMicros` | int | Microseconds |
| `time` | String | |
| `blocks` | Map | Named timeline spans to `{micros, selfMicros, count}`; `selfMicros` excludes directly nested spans. Empty while timeline collection is off |
| `vsyncStartUs` | int | Optional; the engine's vsync timestamp, whose clock is not proven to match `atUs`, so do not join on it |
| `atUs` | int | |
| `interactionId`, `linkedBy` | String | Optional |
