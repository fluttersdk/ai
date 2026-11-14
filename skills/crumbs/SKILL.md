---
name: crumbs
description: "Read the HTTP, logs, exceptions and events a running Flutter app captured, with crumbs."
version: 1.0.0
when_to_use: "Use when calling crumbs_* tools or crumbs:* commands to see what a running Flutter app did; driving the UI is tapir, app lifecycle is dowel."
---

<!-- crumbs v1.0.0 | Skill updated: 2026-11-14 -->

# crumbs

Crumbs lets an agent read what a running Flutter app recorded. Inside the app, watchers and adapters write records into in-memory ring buffers; the app registers `ext.crumbs.*` VM Service extensions that serve those buffers, and you call them as `crumbs_*` MCP tools or as `./bin/dowel crumbs:*` commands from a shell. The loop is: zero the buffers, make the app do the thing, read what landed.

Scope: this skill reads captured state. Driving the UI (taps, text, navigation, snapshots) is the `tapir` skill; starting, reloading and stopping the app, `dowel_logs` and MCP wiring are the `dowel` skill; a `flutter_test` widget test needs neither.

## Install

If a `crumbs_*` call reports that no running Flutter app was detected, start one (below). If it reports that an `ext.crumbs.*` method "is not registered in the running app yet" (a CLI exit 75), the app is still booting, is a release build, or has no crumbs: retry after a few seconds, then check the guard in `lib/main.dart`. From the Flutter app root:

```bash
flutter pub add crumbs
dart run crumbs crumbs:install        # scaffolds ./bin/dowel, registers the plugin, patches lib/main.dart
dart run crumbs mcp:install           # writes the `dowel` entry into .mcp.json
./bin/dowel start --device=chrome     # or macos, linux, windows, a device id
./bin/dowel crumbs:tail               # "No log records." on a fresh start is not an error
```

`crumbs:install` puts this block before `runApp(` (before `await Magic.init(` on a Magic app, so boot errors are caught), behind `if (!kReleaseMode)`, so debug and profile builds carry crumbs and a release build drops it:

```dart
if (!kReleaseMode) {
  CrumbsPlugin.install();
  CrumbsPlugin.registerWatcher(ExceptionWatcher());
  CrumbsPlugin.registerWatcher(DumpWatcher());
}
```

On a Magic app it also adds `MagicCrumbsIntegration.install()` (from `package:magic_devtools/crumbs.dart`) after `Magic.init()`, which registers the Magic HTTP adapter and the model, cache, event, gate and query watchers, and a `magic_devtools` release built on crumbs ships that integration; when the resolved `magic_devtools` lacks the library it warns and skips that line, so Magic's buffers stay empty until you upgrade `magic_devtools` and rerun. Re-running is safe: a `main.dart` that already calls `CrumbsPlugin.install(` gets no second crumbs block, and a rerun still adds `MagicCrumbsIntegration.install()` once the resolved `magic_devtools` ships it, behind the guard of the existing crumbs block. Reconnect the MCP client after `mcp:install` (in Claude Code, `/mcp reconnect dowel`); a stdio server is not reloaded on its own. A Claude Code allow-list entry for the tools is `mcp__dowel__crumbs_*`.

## Rules

### The capture model

1. **Crumbs reads, it never drives.** A buffer holds only what the app did since launch or the last clear. Make the app act first (tapir, a script, a person), then read; reading an idle app proves nothing.
2. **Each buffer has one producer, and most are opt-in.** An empty answer means "no producer" until you know one is registered:

   | Buffer | Read with | Filled by |
   |---|---|---|
   | logs | `crumbs_tail` | `LogWatcher`, installed by `CrumbsPlugin.install()`; only `package:logging` calls |
   | HTTP | `crumbs_requests` | a `CrumbsHttpAdapter`, or the app's own interceptor calling `CrumbsStore.recordHttp`; crumbs hooks no HTTP client itself |
   | exceptions | `crumbs_exceptions` | `ExceptionWatcher`: uncaught errors from `FlutterError.onError` and `PlatformDispatcher.instance.onError` |
   | dumps | `crumbs_dumps` | `DumpWatcher`: `debugPrint` only (not `print`), debug builds only |
   | events, gates, queries, caches | `crumbs_events`, `crumbs_gates`, `crumbs_queries`, `crumbs_caches` | the Magic watchers `MagicCrumbsIntegration` registers, in a `magic_devtools` release built on crumbs; `crumbs_events` holds auth, database and gate-definition events |
   | frames | `crumbs_frames` | `FramePerfWatcher`, registered by the host |
   | models | nothing | Magic's model watcher (same release); model events go to this buffer, which no tool serves |

   The CLI names the producer on an empty read for every buffer but logs and timeline files (`No HTTP records (register a CrumbsHttpAdapter).`). `crumbs_frames` always carries `livenessCounter`, the count of frames drawn: after you drive the UI, frames empty while it stays still means no watcher is registered or the engine stalled.
3. **Crumbs runs only where the host's guard lets it.** `CrumbsPlugin.install()` itself checks no build mode; the guard around it in `lib/main.dart` decides, and the one `crumbs:install` writes is `!kReleaseMode`, so debug and profile builds carry crumbs and a release build does not. `DumpWatcher` adds its own debug check (`DumpWatcher()..allowInRelease = true`, set before `registerWatcher`, lifts it once the host guard allows the build). `--dart-define=CRUMBS_DISABLE=1` (or `true`, `yes`) makes `install()`, `registerWatcher` and `registerHttpAdapter` return without installing anything, so a disabled build has no extensions and no watcher.
4. **Buffers are rings.** 500 records each by default, frame perf 3600; the oldest is evicted without notice. A host can change a cap with `CrumbsStore.setCapacity(n, kind: CrumbsKind.x)`. A hot restart empties them; `crumbs_clear` empties all of them at once and answers `{"cleared": true}`.

### Reading

5. **Every answer is one JSON object with one list,** oldest first: `requests`, `messages` (tail), `exceptions`, `dumps`, `events`, `gates`, `queries`, `caches`, `frames`. Beside it: `cursor` on tail and events, `livenessCounter` on frames. Over MCP it arrives as one text block; parse it before reading fields.
6. **`limit` keeps the newest N; `level` is a minimum.** Omit `limit` over MCP for the whole buffer; the CLI defaults to 50. A `limit` that is not a number reads the whole buffer, zero or below reads nothing. `crumbs_tail { level: "WARNING" }` keeps WARNING, SEVERE and SHOUT; an unknown level name matches nothing, so an empty answer after a typo is the typo.
7. **Page logs and events with the cursor.** `crumbs_tail` and `crumbs_events` (and their commands) take `since`, an `atUs` in microseconds, exclusive, and answer `cursor`, the largest `atUs` returned (or the `since` you gave when nothing is newer). Pass it back as `since` to read only newer records. With `since`, `limit` keeps the oldest N after it, plus any records sharing the last `atUs`, so paging is exact for the records that exist when the page is read; a record added later with the same microsecond `atUs` as the page's last record can be missed. `logger` (exact name, logs) and `type` (event type prefix) narrow further; the tool schemas declare all of them (`crumbs_tail`: `limit`, `level`, `logger`, `since`; `crumbs_events`: `limit`, `type`, `since`). A non-integer `since` is refused with `invalidParams` (the CLI exits 3).
8. **`--follow` streams.** `crumbs:tail --follow` and `crumbs:events --follow` re-read every second from the last cursor until interrupted; run them in the background while driving the app, with `--json` for one object per line.
9. **Join across buffers on `atUs`,** the monotonic clock every record but exceptions, dumps and gates carries; `time` and `timestamp` are wall clock, for display. `interactionId` with `linkedBy` (`zone`, `frame`, `window`) appear when the capturing site links records to one interaction.

### Redaction and the timeline on disk

10. **`********` is crumbs' mask, not the app's value.** Credential keys are masked before a record is buffered, with no host setup: HTTP request headers (`authorization`, `cookie`, `x-api-key` and the like), keys of a JSON or form body, request or response alike (`password`, `token`, `access_token`, `secret`, `api_key` and the like), credential-named parameters in the URL query (`access_token`, `api_key`, the `X-Amz-*` signature of a presigned URL), and the same keys inside the Map elements of a query's `bindings` and a gate check's `arguments` (a positional binding has no key, so only a `redactor` masks it). Case-insensitive, at any depth. A masked header was sent; a missing one is absent from `requestHeaders`. An empty credential stays visible.
11. **The host's `redactor` fails closed, and free text has no other mask.** `CrumbsRedaction.redactor` runs over every text of the log, event, exception and HTTP records, a dump's message, a query's SQL and bindings, and a gate's arguments and user id before they are buffered; the log, event, exception and HTTP records then carry `redacted: true`. Without a `redactor`, a credential written into a log line, a `debugPrint` or a SQL literal is buffered as written. A redactor that throws drops the record from the buffer and the stream, so a line missing right after a sensitive log call can be a failing redactor. Cache, model and frame records are not masked.
12. **The JSONL timeline holds redacted records only.** When the host runs `CrumbsFileSink.start(directory: ...)`, log, event and exception records with `redacted: true` are written as `{"kind": "log"|"event"|"exception", ...}` lines to rotating `timeline-<UTC stamp>-<n>.jsonl` files that outlive the buffers and the launch. Without a `redactor` nothing is written. One sink per directory: a second process writing there has its files pruned. Read it only with `crumbs:files` (no MCP tool); "No timeline file sink is running." means the host started none.

### Crumbs and tapir

13. **Tapir acts, crumbs explains.** Use tapir to cause an effect and see the screen; use crumbs to see why: the request and its status, the log line, the exception and its stack. Tapir reads crumbs only through reader pointers the host assigns, and reads 0 where none is set: `tapir_wait_for_network_idle` reads `CrumbsStore.pendingHttpCount`, which stays 0 unless an adapter counts in-flight requests, so it may report idle at once. Wait on the UI or on `crumbs_requests` instead.

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
./bin/dowel crumbs:events --type=Auth --json --since=<last atUs>
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

In CI, run the CLI against a started app and read with `--json`; a read command exits 0 even on an empty buffer, so assert on the output, not the exit code. Exit 75 means the extension is not registered yet: retry a few times, then check the build mode and the install.

## References

| Read when | File |
|---|---|
| Calling a `crumbs_*` tool and you need its parameters, envelope or errors | `${CLAUDE_SKILL_DIR}/references/mcp-tools.md` |
| Running a `crumbs:*` command from Bash: flags, output, exit codes | `${CLAUDE_SKILL_DIR}/references/cli-commands.md` |
| Reading the fields of a record | `${CLAUDE_SKILL_DIR}/references/records.md` |
| Composing a longer flow: crash hunt, Magic trace, cursor paging, the timeline, coexisting reporters | `${CLAUDE_SKILL_DIR}/references/workflows.md` |
