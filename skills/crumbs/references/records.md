# Records reference

The JSON keys of each record as `toJson()` writes it, which is what every tool, command and timeline line carries. A key marked optional is left out when its value is null.

## Contents

- [Clocks and links](#clocks-and-links)
- [HttpRequestRecord](#httprequestrecord)
- [LogRecordEntry](#logrecordentry)
- [ExceptionRecord](#exceptionrecord)
- [DumpRecord](#dumprecord)
- [EventRecord](#eventrecord)
- [GateRecord](#gaterecord)
- [QueryRecord](#queryrecord)
- [MagicCacheRecord](#magiccacherecord)
- [MagicModelRecord](#magicmodelrecord)
- [FramePerfRecord](#frameperfrecord)

## Clocks and links

- `time` (or `timestamp` on HTTP) is the wall clock as ISO 8601, for display.
- `atUs` is a monotonic microsecond reading of `FlutterTimeline.now`, taken when the record is built. It orders records across buffers whatever the wall clock does; join on it. Exceptions, dumps and gates have none.
- `interactionId` and `linkedBy` (`zone`, `frame` or `window`) are set when the capturing site ties the record to one interaction (a tap, a navigation). `window` means no interaction was open and `interactionId` is null: join by `atUs`.
- `redacted` (logs, events, exceptions, HTTP) is true only when the host's `CrumbsRedaction.redactor` ran over the record before it was buffered.

## HttpRequestRecord

Answer key `records`. The credential masking of `CrumbsRedaction` has already run: a hidden value reads `********`.

| Key | Type | Notes |
|---|---|---|
| `url`, `method` | String | |
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
| `stackTrace`, `isolate` | String | Optional |
| `redacted` | bool | |

## DumpRecord

Answer key `dumps`. Written by `DumpWatcher` from `debugPrint`: `message`, `time`, optional `wrapWidth`. Not run through the `redactor`.

## EventRecord

Answer key `events`. Written by an event watcher (Magic's, through `MagicCrumbsIntegration`).

| Key | Type | Notes |
|---|---|---|
| `eventType` | String | The `type` filter is a prefix of this |
| `payload` | Map | Made JSON-safe at insert: a value `jsonEncode` cannot write, and a non-String key, is stored as its `toString()` |
| `time` | String | |
| `listenerCount` | int | Optional |
| `atUs`, `interactionId`, `linkedBy`, `redacted` | | |

## GateRecord

Answer key `gates`: `ability`, `result` (true allowed, false denied), `arguments` (list), `time`, optional `userId`.

## QueryRecord

Answer key `queries`: `sql`, `bindings`, `timeMs`, `connectionName`, `time`, `atUs`, optional `interactionId`, `linkedBy`.

## MagicCacheRecord

Answer key `caches`: `operation` (`hit`, `miss`, `put`, `forget`, `flush`), `key`, `time`, optional `ttlMs`, `atUs`, optional `interactionId`, `linkedBy`.

## MagicModelRecord

No extension serves it; it is read in process with `CrumbsStore.recentModels()`. Keys: `modelClass`, `event`, `modelKey`, `time`, optional `attributes`, `atUs`, optional `interactionId`, `linkedBy`.

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
