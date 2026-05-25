# Watchers reference

Authoritative sources: `lib/src/watchers/watcher.dart` (contract), `lib/src/watchers/log_watcher.dart`,
`lib/src/watchers/exception_watcher.dart`, `lib/src/watchers/dump_watcher.dart`,
`references/magic/lib/src/cli/telescope_integration.dart` (Magic-side impls).

## TelescopeWatcher contract

```dart
abstract class TelescopeWatcher {
  String get name;
  void install();
  void uninstall();
}
```

Three frozen methods. Magic-side watchers (`MagicModelWatcher`, `MagicCacheWatcher`, `MagicEventWatcher`,
`MagicGateWatcher`, `MagicQueryWatcher`) depend on this contract. No new abstract methods without a coordinated
bump across both repos.

## Registration

```dart
// Immediately calls watcher.install() and holds a reference.
TelescopePlugin.registerWatcher(MyWatcher());
```

Call after `TelescopePlugin.install()`. The plugin keeps every registered watcher in a private list; `install()`
is idempotent on re-registration attempts.

## kDebugMode gate

The primary gate belongs to the consumer's `main.dart`:

```dart
if (kDebugMode) {
  TelescopePlugin.install();
  TelescopePlugin.registerWatcher(ExceptionWatcher());
  TelescopePlugin.registerWatcher(DumpWatcher());
}
```

`DumpWatcher.install()` adds its own internal `kDebugMode` guard (see below). `ExceptionWatcher` does NOT gate
internally: the consumer `if (kDebugMode)` block is the gate for exception capture.

## Chain-preserve discipline

Any watcher that replaces a global hook must:

1. Save the previous handler before replacing it.
2. Call the saved handler inside the new handler body.
3. Restore the saved handler in `uninstall()`.

This lets Sentry, Bugsnag, and other observability tools coexist with telescope without silently masking each other.
Numbered step comments are required in `install()` bodies that chain-preserve (see CLAUDE.md conventions).

## Idempotency rule

Every concrete watcher uses a private `_installed` bool (or equivalent sentinel) to guard against double-install:

```dart
@override
void install() {
  if (_installed) return;
  _installed = true;
  // ... actual hook registration
}

@override
void uninstall() {
  if (!_installed) return;
  // ... restore saved state
  _installed = false;
}
```

Use an instance-level field (not a static), so multiple watcher instances in test isolation are independent.

## Record feeding rule

Watchers call only the matching `TelescopeStore.record*` static method. They do not import `telescope_plugin.dart`,
do not reach into `Queue` / `StreamController` internals, and do not cross-call sibling watchers.

---

## Built-in watchers (shipped with fluttersdk_telescope)

### LogWatcher (auto-installed)

**Source:** `lib/src/watchers/log_watcher.dart`
**Name:** `'log'`
**Auto-installed:** yes, by `TelescopePlugin.install()`. No explicit registration needed.

Subscribes to `Logger.root.onRecord` from `package:logging`. Enables `hierarchicalLoggingEnabled = true` and sets
`Logger.root.level = Level.ALL` on install so every named logger in the app funnels through root. Idempotency via
`_sub != null` sentinel (subscription reference, not a bool flag).

Feeds: `TelescopeStore.recordLog(LogRecordEntry.fromLogRecord(record))`

**LogRecordEntry fields:** `level` (string, e.g. `'INFO'`), `loggerName`, `message`, `time`, `error` (optional),
`stackTrace` (optional).

```dart
// No action needed. TelescopePlugin.install() handles it.
TelescopePlugin.install();
```

If the app does not use `package:logging`, the watcher is dormant (no records flow through `Logger.root`).

### ExceptionWatcher (opt-in)

**Source:** `lib/src/watchers/exception_watcher.dart`
**Name:** `'exception'`
**Auto-installed:** no.

Hooks both `FlutterError.onError` (synchronous framework + widget errors) and
`PlatformDispatcher.instance.onError` (async, isolate, and plugin-originated errors). Both hooks are chain-preserved.

The `PlatformDispatcher.onError` handler returns the previous handler's return value
(`_previousPlatformOnError?.call(error, stack) ?? true`). When no previous handler exists, defaults to `true`
(handled). When the previous handler returns `false`, this watcher also returns `false`, propagating the error to
the native platform crash handler (Sentry-friendly contract).

`install()` numbered phases:

```dart
// 1. Chain-preserve and replace FlutterError.onError (sync framework errors).
_previousFlutterOnError = FlutterError.onError;
FlutterError.onError = (details) { TelescopeStore.recordException(...); _previousFlutterOnError?.call(details); };

// 2. Chain-preserve and replace PlatformDispatcher.onError (async + isolate + plugin errors).
_previousPlatformOnError = PlatformDispatcher.instance.onError;
PlatformDispatcher.instance.onError = (error, stack) { ... return _previousPlatformOnError?.call(error, stack) ?? true; };

// 3. (in uninstall) Restore both handlers symmetrically.
FlutterError.onError = _previousFlutterOnError;
PlatformDispatcher.instance.onError = _previousPlatformOnError;
```

Feeds: `TelescopeStore.recordException(ExceptionRecord(...))`

**ExceptionRecord fields:** `exceptionType`, `message`, `time`, `stackTrace` (optional), `library` (optional).

```dart
if (kDebugMode) {
  TelescopePlugin.registerWatcher(ExceptionWatcher());
}
```

### DumpWatcher (opt-in)

**Source:** `lib/src/watchers/dump_watcher.dart`
**Name:** `'dump'`
**Auto-installed:** no.

Overrides the global `debugPrint` callback. Captures every `debugPrint()` / `print()` call (Flutter routes `print`
through `debugPrint` in debug mode) as a `DumpRecord` and then calls the previous `debugPrint` (chain-preserve).

**kDebugMode gate (internal):** `install()` starts with `if (!kDebugMode && !allowInRelease) return;`. In release
builds this is a no-op so the entire subsystem is tree-shaken. Set `watcher.allowInRelease = true` before calling
`install()` only when release-build capture is explicitly needed.

Feeds: `TelescopeStore.recordDump(DumpRecord(message: ..., time: ..., wrapWidth: ...))`

```dart
if (kDebugMode) {
  TelescopePlugin.registerWatcher(DumpWatcher());
}
```

---

## Magic-side watchers (shipped with magic package)

All registered by `MagicTelescopeIntegration.install()` (`references/magic/lib/src/cli/telescope_integration.dart`).
Call this after both `TelescopePlugin.install()` and `Magic.init()` are complete.

```dart
// In main.dart, after Magic.init():
if (kDebugMode) {
  MagicTelescopeIntegration.install();
}
```

This single call registers: `MagicHttpFacadeAdapter` (HTTP adapter) + `MagicModelWatcher` + `MagicCacheWatcher` +
`MagicEventWatcher` + `MagicGateWatcher` + `MagicQueryWatcher` (all watchers).

### MagicHttpFacadeAdapter (HTTP adapter, not a watcher)

**Contract:** `TelescopeHttpAdapter`, not `TelescopeWatcher`.
**Name:** `'magic_http'`

Wraps Magic's `Http` facade via `MagicNetworkInterceptor`. Captures every HTTP call routed through the `Http`
facade. Overrides `pendingCount` to expose the live in-flight request count (consumed by dusk
`wait_for_network_idle`).

Feeds: `TelescopeStore.recordHttp(HttpRequestRecord(...))`

### MagicModelWatcher

**Name:** `'magic_model'`

Subscribes to Magic's `ModelCreated<T>`, `ModelSaved<T>`, and `ModelDeleted<T>` events via `Event.listen`. Records
each lifecycle transition as a `MagicModelRecord`.

Feeds: `TelescopeStore.recordMagicModel(MagicModelRecord(...))`

**MagicModelRecord fields:** `modelType`, `action` (created / saved / deleted), `time`, `attributes` (JSON snapshot).

### MagicCacheWatcher

**Name:** `'magic_cache'`

Subscribes to Magic's `CacheHit`, `CacheMiss`, `CachePut`, `CacheForget`, and `CacheFlush` events. Records each
cache operation as a `MagicCacheRecord`.

Feeds: `TelescopeStore.recordMagicCache(MagicCacheRecord(...))`

**MagicCacheRecord fields:** `key`, `tag` (hit / miss / put / forget / flush), `time`, `ttl` (optional).

### MagicEventWatcher

**Name:** `'magic_event'`

Subscribes to every event dispatched through Magic's `Event.dispatch()` facade by hooking the global event
dispatcher. Records each dispatch as an `EventRecord` with a JSON snapshot of the event payload.

Feeds: `TelescopeStore.recordEvent(EventRecord(...))`

**EventRecord fields:** `eventClass`, `payload` (JSON map), `time`.

### MagicGateWatcher

**Name:** `'magic_gate'`

Hooks Magic's `Gate.allows` / `Gate.denies` call sites. Records each authorization check as a `GateRecord`.

Feeds: `TelescopeStore.recordGate(GateRecord(...))`

**GateRecord fields:** `ability`, `result` (allowed / denied), `userId`, `argumentClass` (optional), `time`.

### MagicQueryWatcher

**Name:** `'magic_query'`

Subscribes to Magic's `QueryExecuted` event. Records each SQL dispatch as a `QueryRecord`.

Feeds: `TelescopeStore.recordQuery(QueryRecord(...))`

**QueryRecord fields:** `sql`, `bindings`, `timeMs`, `connection`, `time`.

---

## Writing a custom watcher

```dart
final class MyWatcher implements TelescopeWatcher {
  @override
  String get name => 'my_watcher';

  bool _installed = false;

  @override
  void install() {
    if (_installed) return;
    _installed = true;
    // Wire your hook. Chain-preserve any global handler you replace.
    // Call TelescopeStore.record*(...) to push records.
  }

  @override
  void uninstall() {
    if (!_installed) return;
    // Restore saved handler. Set _installed = false.
    _installed = false;
  }
}
```

Register after `TelescopePlugin.install()`:

```dart
if (kDebugMode) {
  TelescopePlugin.registerWatcher(MyWatcher());
}
```

## Test pattern

```dart
setUp(() {
  MagicApp.reset(); // if using Magic
  TelescopeStore.resetForTesting();
});

tearDown(() {
  TelescopeStore.resetForTesting();
  watcher.uninstall(); // restore globals for test isolation
});

test('install + uninstall restores previous handler', () {
  // 1. Sentinel: install a known handler first.
  final calls = <FlutterErrorDetails>[];
  FlutterError.onError = (d) => calls.add(d);

  // 2. Install watcher; it should chain-preserve the sentinel.
  final watcher = ExceptionWatcher()..install();

  // 3. Trigger an error; both the watcher record AND the sentinel fire.
  FlutterError.reportError(FlutterErrorDetails(exception: Exception('test')));
  expect(TelescopeStore.recentExceptions().length, 1);
  expect(calls, hasLength(1));

  // 4. Uninstall; sentinel is back as the only handler.
  watcher.uninstall();
  FlutterError.reportError(FlutterErrorDetails(exception: Exception('after')));
  expect(calls, hasLength(2));
  expect(TelescopeStore.recentExceptions().length, 1); // no new record
});
```
