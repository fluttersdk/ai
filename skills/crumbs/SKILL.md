---
name: crumbs
description: "Read the HTTP, logs, exceptions and events a running Flutter app captured, with crumbs."
version: 0.0.13
when_to_use: "Use when calling crumbs_* tools or crumbs:* commands to see what a running Flutter app did; driving the UI is tapir, app lifecycle is dowel."
---

<!-- crumbs v0.0.13 | Skill updated: 2026-11-14 -->

# crumbs

Crumbs lets an agent read what a running Flutter app recorded. Inside the app, watchers and adapters write records into in-memory ring buffers; the app registers `ext.crumbs.*` VM Service extensions that serve those buffers, and you call them as `crumbs_*` MCP tools or as `./bin/dowel crumbs:*` commands from a shell. The loop is: zero the buffers, make the app do the thing, read what landed.

Scope: this skill reads captured state. Driving the UI (taps, text, navigation, snapshots) is the `tapir` skill; starting, reloading and stopping the app, `dowel_logs` and MCP wiring are the `dowel` skill; a `flutter_test` widget test needs neither.

## Install

If a `crumbs_*` call reports that no app or VM Service is reachable, the app is not running; if it reports an unregistered `ext.crumbs.*` method, crumbs is not installed or the app predates the install. From the Flutter app root:

```bash
flutter pub add crumbs
dart run crumbs crumbs:install        # scaffolds ./bin/dowel, registers the plugin, patches lib/main.dart
dart run crumbs mcp:install           # writes the `dowel` entry into .mcp.json
./bin/dowel start --device=chrome     # or macos, linux, windows, a device id
./bin/dowel crumbs:tail               # "No log records." on a fresh start is not an error
```

`crumbs:install` puts this block before `runApp(` (before `await Magic.init(` on a Magic app, so boot errors are caught), behind `if (kDebugMode)`, so profile and release builds drop crumbs:

```dart
if (kDebugMode) {
  CrumbsPlugin.install();
  CrumbsPlugin.registerWatcher(ExceptionWatcher());
  CrumbsPlugin.registerWatcher(DumpWatcher());
}
```

On a Magic app it also adds `MagicCrumbsIntegration.install()` (from `package:magic_devtools/crumbs.dart`) after `Magic.init()`, which registers the Magic HTTP adapter and the model, cache, event, gate and query watchers, but only when the resolved `magic_devtools` is a release built on crumbs; otherwise it warns and skips that line. Until that release ships, `MagicTelescopeIntegration` feeds `fluttersdk_telescope`, not crumbs, so the HTTP, event, gate, query and cache buffers of crumbs stay empty in a Magic app; upgrade `magic_devtools` then and rerun. Re-running the command is safe. Reconnect the MCP client after `mcp:install` (in Claude Code, `/mcp reconnect dowel`); a stdio server is not reloaded on its own. A Claude Code allow-list entry for the tools is `mcp__dowel__crumbs_*`.

## Rules

### The capture model

1. **Crumbs reads, it never drives.** A buffer holds only what the app did since launch or the last clear. Make the app act first (tapir, a script, a person), then read; reading an idle app proves nothing.
2. **Each buffer has one producer, and most are opt-in.** An empty answer means "no producer" until you know one is registered:

   | Buffer | Read with | Filled by |
   |---|---|---|
   | logs | `crumbs_tail` | `LogWatcher`, installed by `CrumbsPlugin.install()`; only `package:logging` calls |
   | HTTP | `crumbs_requests` | a `CrumbsHttpAdapter`; `DioHttpAdapter` installs no interceptor, the app's own interceptor calls `DioHttpAdapter.recordRequest` |
   | exceptions | `crumbs_exceptions` | `ExceptionWatcher`: uncaught errors from `FlutterError.onError` and `PlatformDispatcher.instance.onError` |
   | dumps | `crumbs_dumps` | `DumpWatcher`: `debugPrint` only (not `print`), debug builds only |
   | events, gates, queries, caches | `crumbs_events`, `crumbs_gates`, `crumbs_queries`, `crumbs_caches` | the Magic watchers from `MagicCrumbsIntegration`; `crumbs_events` holds auth, database and gate-definition events |
   | frames | `crumbs_frames` | `FramePerfWatcher`, registered by the host |
   | models | nothing | Magic's model watcher; model events go to this buffer, which no tool serves |

   The CLI says so on an empty read (`No HTTP records (register a CrumbsHttpAdapter).`). `crumbs_frames` always carries `livenessCounter`, the count of frames drawn: frames empty while it stays still means no watcher or a stalled engine, not an idle app.
3. **Crumbs is debug-only by the host's guard.** `CrumbsPlugin.install()` itself checks no build mode; the guard around it in `lib/main.dart` decides. `DumpWatcher` adds its own debug check. `--dart-define=CRUMBS_DISABLE=1` skips the install.
4. **Buffers are rings.** 500 records each by default, frame perf 3600; the oldest is evicted without notice. A host can change a cap with `CrumbsStore.setCapacity(n, kind: CrumbsKind.x)`. A hot restart empties them; `crumbs_clear` empties all of them at once and answers `{"cleared": true}`.

### Reading

5. **Every answer is one JSON object with one list,** oldest first: `records` (requests), `messages` (tail), `exceptions`, `dumps`, `events`, `gates`, `queries`, `caches`, `frames`. Over MCP it arrives as one text block; parse it before reading fields.
6. **`limit` keeps the newest N; `level` is a minimum.** Omit `limit` over MCP for the whole buffer; the CLI defaults to 50. A `limit` that is not a number reads the whole buffer, zero or below reads nothing. `crumbs_tail { level: "WARNING" }` keeps WARNING, SEVERE and SHOUT; an unknown level name matches nothing, so an empty answer after a typo is the typo.
7. **Page logs and events with the cursor.** `crumbs_tail` and `crumbs_events` (and their commands) take `since`, an `atUs` in microseconds, exclusive, and answer `cursor`, the largest `atUs` returned (or the `since` you gave when nothing is newer). Pass it back as `since` to read only newer records. With `since`, `limit` keeps the oldest N after it, plus any records sharing the last `atUs`, so paging skips nothing. `logger` (exact name, logs) and `type` (event type prefix) narrow further. The tool schemas list only `limit` and `level`, but dowel forwards every argument, so these work over MCP too. A non-integer `since` is refused with `invalidParams`.
8. **`--follow` streams.** `crumbs:tail --follow` and `crumbs:events --follow` re-read every second from the last cursor until interrupted; run them in the background while driving the app, with `--json` for one object per line.
9. **Join across buffers on `atUs`,** the monotonic clock every record but exceptions, dumps and gates carries; `time` and `timestamp` are wall clock, for display. `interactionId` with `linkedBy` (`zone`, `frame`, `window`) appear when the capturing site links records to one interaction.

### Redaction and the timeline on disk

10. **`********` is crumbs' mask, not the app's value.** Every HTTP record is masked before it is buffered: credential request headers (`authorization`, `cookie`, `x-api-key` and the like) and credential keys of a JSON or form body (`password`, `token`, `access_token`, `secret` and the like), case-insensitive, at any depth. A masked header was sent; a missing one is absent from `requestHeaders`. An empty credential stays visible.
11. **The host's `redactor` fails closed.** `CrumbsRedaction.redactor` runs over every text of the log, event, exception and HTTP records before they are buffered and sets `redacted: true`. A redactor that throws drops the record from the buffer and the stream, so a line missing right after a sensitive log call can be a failing redactor. Dumps, gates, queries, caches, models and frames are not run through it.
12. **The JSONL timeline holds redacted records only.** When the host runs `CrumbsFileSink.start(directory: ...)`, log, event and exception records with `redacted: true` are written as `{"kind": "log"|"event"|"exception", ...}` lines to rotating `timeline-<UTC stamp>-<n>.jsonl` files that outlive the buffers and the launch. Without a `redactor` nothing is written. Read it only with `crumbs:files` (no MCP tool); "No timeline file sink is running." means the host started none.

### Crumbs and tapir

13. **Tapir acts, crumbs explains.** Use tapir to cause an effect and see the screen; use crumbs to see why: the request and its status, the log line, the exception and its stack. Tapir reads crumbs only through reader pointers the host assigns (`MagicCrumbsIntegration` does it): `tapir_wait_for_network_idle` reads `CrumbsStore.pendingHttpCount`, which stays 0 unless an adapter counts in-flight requests, so it may report idle at once. Wait on the UI or on `crumbs_requests` instead.

## Recipes

The verify loop, after any change you want to prove:

```text
crumbs_clear                                   zero the buffers
tapir_tap { ref: "q3" }                        a ref from tapir_find, or any action that exercises the change
tapir_wait_for { text: "Saved" }               wait on the UI, not on network idle
crumbs_requests { limit: 10 }                  the call went out, with the expected status
crumbs_exceptions                              empty, or read the newest stackTrace
crumbs_tail { level: "WARNING", limit: 50 }    nothing unexpected was logged
```

Hunt a fault that already happened: do not clear. Read `crumbs_exceptions { limit: 5 }`, then `crumbs_tail { limit: 100 }` and `crumbs_requests { limit: 20 }` and match them by time; a 4xx or 5xx just before the throw is the usual cause.

The same from a shell, following one logger while a second shell drives the app:

```bash
./bin/dowel crumbs:clear
./bin/dowel crumbs:tail --logger=Sync --json --follow     # background; one JSON object per line
./bin/dowel crumbs:requests --limit=20
./bin/dowel crumbs:events --type=Auth --since=<cursor>
./bin/dowel crumbs:files                                  # timeline files, newest first
```

## Testing

Code that feeds crumbs (an adapter, a watcher, a redactor) is tested against `CrumbsStore` directly; reset it after each test so buffers, caps, the redactor and the hidden-name lists do not leak:

```dart
import 'package:crumbs/crumbs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(CrumbsStore.resetForTesting);

  test('the redactor masks a card number before the log is buffered', () {
    CrumbsRedaction.redactor =
        (String text) => text.replaceAll(RegExp(r'\d{16}'), '[card]');

    CrumbsStore.recordLog(
      LogRecordEntry(
        level: 'INFO',
        levelValue: 800,
        message: 'paid with 4242424242424242',
        loggerName: 'checkout',
        time: DateTime.now(),
      ),
    );

    final LogRecordEntry entry = CrumbsStore.recentLogs().single;
    expect(entry.message, 'paid with [card]');
    expect(entry.redacted, isTrue);
  });
}
```

In CI, run the CLI against a started app and read with `--json`; every read command exits 0 even on an empty buffer, so assert on the output, not the exit code.

## References

| Read when | File |
|---|---|
| Calling a `crumbs_*` tool and you need its parameters, envelope or errors | `${CLAUDE_SKILL_DIR}/references/mcp-tools.md` |
| Running a `crumbs:*` command from Bash: flags, output, exit codes | `${CLAUDE_SKILL_DIR}/references/cli-commands.md` |
| Reading the fields of a record | `${CLAUDE_SKILL_DIR}/references/records.md` |
| Composing a longer flow: crash hunt, Magic trace, cursor paging, the timeline, coexisting reporters | `${CLAUDE_SKILL_DIR}/references/workflows.md` |
