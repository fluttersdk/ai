# Workflows

Longer flows built from the rules in `SKILL.md`. Each assumes the app runs under dowel with crumbs installed.

## Contents

- [Verify a change](#verify-a-change)
- [Hunt a crash](#hunt-a-crash)
- [Trace a Magic action](#trace-a-magic-action)
- [Narrow the log](#narrow-the-log)
- [Follow a buffer with the cursor](#follow-a-buffer-with-the-cursor)
- [Read the timeline on disk](#read-the-timeline-on-disk)
- [Capture HTTP in an app without Magic](#capture-http-in-an-app-without-magic)
- [Turn on redaction and the timeline](#turn-on-redaction-and-the-timeline)
- [Coexist with Sentry or Bugsnag](#coexist-with-sentry-or-bugsnag)

## Verify a change

```text
1. crumbs_clear                                 zero point, so startup noise is gone
2. drive the change with tapir                  tapir_tap, tapir_fill, tapir_navigate
3. tapir_wait_for { text: "<result text>" }     wait on the screen
4. crumbs_requests { limit: 10 }                expected method, url and statusCode
5. crumbs_exceptions                            expect an empty list
6. crumbs_tail { level: "WARNING" }             expect nothing new
```

Report what each read returned. "No exceptions" counts only if `ExceptionWatcher` is registered; "no requests" only if an adapter records.

## Hunt a crash

The fault already happened, so do not clear.

```text
1. crumbs_exceptions { limit: 5 }       the newest is last: read exceptionType, message, stackTrace
2. crumbs_tail { limit: 100 }           the log lines before it, by time
3. crumbs_requests { limit: 20 }        a 4xx or 5xx just before the throw is the usual cause
4. crumbs_gates { limit: 10 }           with the Magic integration, a denied ability before an authorisation error
```

Exception records carry no `atUs`; line them up by `time`. To reproduce it cleanly afterwards, run the verify loop above.

## Trace a Magic action

With `MagicCrumbsIntegration` installed (a `magic_devtools` release built on crumbs ships it), one action fans out across buffers:

```text
1. crumbs_clear
2. the action: a model save, a sign-in, a form submit
3. crumbs_events { limit: 20 }      auth, database and gate-definition events (model events go to the model buffer, which no tool serves)
4. crumbs_queries { limit: 20 }     what reached the local database
5. crumbs_requests { limit: 20 }    what reached the API
6. crumbs_gates { limit: 10 }       what was allowed or denied
7. crumbs_caches { limit: 20 }      hits, misses, puts, forgets
```

Join events, queries, requests and caches on `atUs`; gates have only `time`.

## Narrow the log

- `crumbs_tail { level: "WARNING" }` keeps WARNING and above; move to `SEVERE` if still noisy. The buffer keeps every level, so a looser read later needs no new capture.
- `crumbs_tail { logger: "Auth" }` keeps one logger by exact name.
- `crumbs_dumps` holds `debugPrint` output; it is a separate buffer from the log.

## Follow a buffer with the cursor

```bash
./bin/dowel crumbs:tail --logger=Sync --json --follow           # background; one JSON line per record
./bin/dowel crumbs:events --type=Auth --json --limit=20          # first page, note the last atUs
./bin/dowel crumbs:events --type=Auth --json --since=<that atUs> # only what came after
```

Over MCP, pass the `cursor` of one answer as `since` on the next: `crumbs_events { type: "Auth", since: <cursor> }`. With `since`, `limit` keeps the oldest records after it, so paging is exact for the records that exist when the page is read; a record added later with the same microsecond `atUs` as the page's last record can be missed.

## Read the timeline on disk

When the host runs a `CrumbsFileSink`, redacted log, event and exception records outlive the buffers and the launch:

```bash
./bin/dowel crumbs:files                                         # newest first, earlier launches too
./bin/dowel crumbs:files --name=<file> -v                        # lines, then "next offset: <n>"
./bin/dowel crumbs:files --name=<file> --offset=<next offset>    # continue
```

Each line is `{"kind": "log"|"event"|"exception", ...}` followed by the record's keys; join kinds on `atUs` (exceptions have only `time`). "No timeline file sink is running." means the host started none, or the sink stopped after a failed write. A sink that runs but writes nothing has no `redactor` set (it writes only `redacted: true` records).

## Capture HTTP in an app without Magic

crumbs hooks no HTTP client: record from the app's own interceptor through `CrumbsStore.recordHttp`, which masks the credentials before it buffers the record:

```dart
import 'package:crumbs/crumbs.dart';
import 'package:dio/dio.dart';

final class CrumbsDioInterceptor extends Interceptor {
  final Map<RequestOptions, Stopwatch> _clocks = <RequestOptions, Stopwatch>{};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    _clocks[options] = Stopwatch()..start();
    handler.next(options);
  }

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _record(response.requestOptions, response.statusCode ?? 0);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(err.requestOptions, err.response?.statusCode ?? 0, failed: true);
    handler.next(err);
  }

  void _record(RequestOptions options, int statusCode, {bool failed = false}) {
    CrumbsStore.recordHttp(
      HttpRequestRecord(
        url: options.uri.toString(),
        method: options.method,
        statusCode: statusCode,
        durationMs: _clocks.remove(options)?.elapsedMilliseconds ?? 0,
        isError: failed || statusCode >= 400,
        timestamp: DateTime.now(),
        requestHeaders: <String, String>{
          for (final MapEntry<String, dynamic> header in options.headers.entries)
            header.key: '${header.value}',
        },
      ),
    );
  }
}
```

Inside the debug guard: `dio.interceptors.add(CrumbsDioInterceptor());`. Headers, bodies and the URL query are masked at insert, but the store masks only JSON and form strings: run a body held as a `Map` through `CrumbsRedaction.redactParameters` first, and a string body through `CrumbsRedaction.redactBody` before truncating it, because a cut JSON body no longer parses. No adapter is involved, so `CrumbsStore.pendingHttpCount` stays 0; a `CrumbsHttpAdapter` that tracks in-flight requests (registered with `CrumbsPlugin.registerHttpAdapter`, `pendingCount` implemented) is what feeds it.

## Turn on redaction and the timeline

The host sets both, inside the debug guard, after `CrumbsPlugin.install()`:

```dart
CrumbsRedaction.hideRequestParameters(<String>['otp']);
CrumbsRedaction.redactor =
    (String text) => text.replaceAll(RegExp(r'\b\d{16}\b'), '[card]');
await CrumbsFileSink.start(directory: timelineDirectory); // an absolute directory the app owns
```

The redactor must be pure and total: a throw drops the record rather than let it through unmasked. It also covers the free text key masking cannot reach (a log message, a dump, a query's SQL). Set it before the records you want on disk are made; a record buffered while it was null stays `redacted: false` and the sink skips it. `start` throws a `FileSystemException` when the directory cannot be created or written. The sink writes through `dart:io`, so it needs a native target; `maxFileBytes` (default 1 MiB) and `maxFiles` (default 8) bound its disk use.

## Coexist with Sentry or Bugsnag

`ExceptionWatcher` and `DumpWatcher` save the handler in place when they install and call it after recording, so install the other reporter first: it keeps receiving every error and every `debugPrint`. A reporter installed later must chain to the handler it replaces, or crumbs stops seeing those errors. `ExceptionWatcher` returns the previous `PlatformDispatcher.onError` handler's verdict, so a reporter that marks an error fatal still does, and it calls the previous handler even when recording an error throws (an error whose `toString()` throws). `FramePerfWatcher` adds a timings callback rather than replacing one, so it has nothing to chain.
