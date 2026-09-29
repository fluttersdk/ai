<!-- magic_sentry v0.0.2 | Updated: 2026-09-29 -->

# magic_sentry Plugin

Sentry error and performance monitoring for Magic Framework. It boots `sentry_flutter` in one web-safe zone before `Magic.init`, reports the HTTP failures magic's `Http` facade turns into `MagicResponse` values, keeps Sentry's scope user in step with `Auth.stateNotifier`, turns any event implementing magic's `ReportsBreadcrumb` into a breadcrumb, and registers a navigator observer on `MagicRouter`.

The package is generic on purpose: it has no user model, team or tag of its own. App-specific data reaches it through the provider's callbacks or through an event that opts into `ReportsBreadcrumb`.

## Contents

- [Installation](#installation)
- [Boot order](#boot-order)
- [SentryServiceProvider](#sentryserviceprovider)
- [HTTP reporting](#http-reporting)
- [User context](#user-context)
- [Event breadcrumbs](#event-breadcrumbs)
- [Configuration](#configuration)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_sentry: ^0.0.2
```

0.0.2 pins `magic ^0.0.24`, the newest at that release; the real requirement is still `magic` 0.0.22, the first release with `Event.listenAny` and `ReportsBreadcrumb`. It also pins `sentry_flutter` / `sentry_dio` `^9.27.0`.

```bash
dart run <app>:artisan plugin:install magic_sentry
```

There is no package-specific CLI. `plugin:install` reads the package's `install.yaml`, publishes `lib/config/sentry.dart` from `assets/stubs/install/sentry_config.stub`, and injects `SentryServiceProvider` into `lib/config/app.dart`'s `providers` list. It cannot rewrite `main()`; that wiring is yours (below).

## Boot order

Sentry starts BEFORE `Magic.init`, so a failure during magic's own boot is reported too. `main()` is one call:

```dart
import 'config/sentry.dart';

void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
  MagicSentry.installErrorWidgetBreadcrumb();
  await Magic.init(configFactories: [...]);
  runApp(MyApp());
}
```

| Member | Signature | What it does |
|:-------|:----------|:-------------|
| `MagicSentry.run` | `static void run({required FutureOr<void> Function(SentryFlutterOptions) configure, required FutureOr<void> Function() appRunner})` | Opens ONE `runZonedGuarded` zone, calls `WidgetsFlutterBinding.ensureInitialized()`, `Env.load()`, then `SentryFlutter.init(configure, appRunner: appRunner)`. A zone-level error goes to `Sentry.captureException` and is still dumped to the console. |
| `MagicSentry.installErrorWidgetBreadcrumb` | `static void installErrorWidgetBreadcrumb()` | Wraps `ErrorWidget.builder` to add a `fatal` breadcrumb (`category: 'ui.error_widget'`) when a build error replaces the interface, then returns the default widget unchanged. Call once, early in `appRunner`. |

One zone is the point, not a detail: on Flutter web `SentryFlutter.init` opens its own zone only from the root zone (flutter/flutter#100277), so entering one first keeps the app and its binding in the same zone.

`configure` runs before `Config` exists, which is why the published `lib/config/sentry.dart` reads `.env` through `Env` directly and is NOT a magic config factory: `install.yaml` has no `magic.config_factory` key.

## SentryServiceProvider

```dart
// lib/config/app.dart
'providers': [
  // ...
  (app) => SentryServiceProvider<User>(
    app,
    userId: (user) => user.id,
    userEmail: (user) => user.email,
    userExtras: (user) => {'team_id': '${user.currentTeamId}'},
  ),
],
```

| Parameter | Type | Effect |
|:----------|:-----|:-------|
| `userId` | `String Function(T user)?` | Turns user reporting on. Leave it out to skip user reporting; everything else still wires up. |
| `userEmail` | `String? Function(T user)?` | Optional; an empty or null email reports the id alone. |
| `userExtras` | `Map<String, String> Function(T user)?` | Scope tags applied while a user is reported. Each call's keys replace the previous call's, so a team switch leaves no stale tag. |

`T extends Model`, the host app's own `Authenticatable` model. `register()` binds nothing. `boot()` returns at once unless `Sentry.isEnabled`, then wires, in order:

1. The network driver: `sentry_dio`'s `addSentry(captureFailedRequests: false)` on a `DioNetworkDriver` (HTTP breadcrumbs and spans), then `SentryNetworkInterceptor` into magic's interceptor chain. A failure resolving the driver is logged (`Log.warning` when `log` is bound, `debugPrint` otherwise) and does not fail the boot.
2. `SentryUserContext<T>.install()` when `userId` was given.
3. The event breadcrumb listener through `Event.listenAny`, removing the previous one first, so a second boot in one isolate registers it once.
4. `MagicRouter.instance.addObserver(SentryNavigatorObserver())`. This has to run before the router builds its `routerConfig`, which is why it lives in `boot()` and why the provider belongs in the `providers` list rather than being wired later.

## HTTP reporting

`SentryNetworkInterceptor extends MagicNetworkInterceptor` reads each `MagicError` and decides:

| Status | Disposition |
|:-------|:------------|
| `0` (no response: a dead connection) | Event |
| `>= 500` | Event |
| anything else (4xx: an expired session, a validation error) | `warning` breadcrumb, `category: 'http'` |

- The endpoint is normalised before it is reported: the query string is dropped and a numeric or UUID path segment becomes `{id}`, so `/monitors/42` and `/monitors/43` are one issue.
- An event is fingerprinted `['http', method, endpoint, status]` and carries an `http_failure` context (method, endpoint, status, the transport message when there is one).
- One event per distinct `METHOD endpoint status` per session: a repeat becomes an `error` breadcrumb marked `(repeat)`. The set is process-wide (`SentryNetworkInterceptor.reportedFailures`), not time-windowed.
- `sentry_dio`'s own failed-request capture stays OFF. Turning it back on double-reports every failure, with a stack trace inside the SDK instead of at the caller.

## User context

`SentryUserContext<T extends Model>` is what the provider installs; construct it directly only outside the provider.

```dart
SentryUserContext<User>(
  id: (user) => user.id,
  email: (user) => user.email,
  extras: (user) => {'plan': user.plan},
).install();
```

- `install()` applies the current auth state immediately (a session restored at boot is reported from the first event), then subscribes `apply` to `Auth.stateNotifier`. A second `install()` on the same notifier adds no second listener.
- `apply()` sets the scope user, or explicitly `null` on sign-out: a stale user would file the next visitor's errors under the person who left.
- A user whose `id` extractor answers `''` counts as nobody, since several magic apps model "no session" as an empty user rather than null.
- `id` and `email` run on every auth change: read straight off the model, no network call.

## Event breadcrumbs

Any `MagicEvent` that also implements magic's `ReportsBreadcrumb` becomes a Sentry breadcrumb (level `info`) with no extra wiring. This package does not know which events exist; the event opts in.

```dart
class InvoicePaid extends MagicEvent implements ReportsBreadcrumb {
  InvoicePaid(this.invoiceId);

  final String invoiceId;

  @override
  String get breadcrumbCategory => 'billing';

  @override
  String get breadcrumbMessage => 'Invoice paid';

  @override
  Map<String, Object?> get breadcrumbData => {'invoice_id': invoiceId};
}
```

`breadcrumbData` is a whitelist the event author curates: `EventBreadcrumbs.breadcrumbFor(event)` copies it as-is and never adds or drops a key, so keep tokens, emails and query values out of it. `magic_deeplink`'s `DeeplinkOpened` and `DeeplinkNavigating` already implement the contract and carry only the matched route pattern. `breadcrumbFor` answers `null` for an event that does not implement it.

## Configuration

`plugin:install` publishes `lib/config/sentry.dart`, the app's own editable copy. It exposes `configureSentry`, `sentryDsn`, `sentryEnabled` and the env key constants, and reads:

| Key | Default | Purpose |
|:----|:--------|:--------|
| `SENTRY_DSN` | `''` | Empty leaves the SDK inert while `appRunner` still runs. `sentryDsn` is a `String`, never null: `Sentry.init` throws on a null DSN, which would stop the app booting on every machine without one. |
| `SENTRY_ENVIRONMENT` | `'local'` | Tags every event. |
| `SENTRY_RELEASE` | unset | Required on web, which has no manifest to derive a release from; set it at build time. |
| `SENTRY_TRACES_SAMPLE_RATE` | `0.2` | Fraction of transactions traced. |

`sendDefaultPii` is fixed to `false` and session replay is never enabled; an app that wants either sets it in its own `configure`. `enableAutoSessionTracking` is on, and release health only records a session when `SentryNavigatorObserver` sees a NAMED route.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Calling `Magic.init` before `MagicSentry.run` | `MagicSentry.run` is the whole body of `main()`; `Magic.init` goes inside `appRunner` |
| Reading the Sentry config through `Config.get` | `Config` is not loaded when `configure` runs; read `.env` through `Env`, as the published file does |
| Importing `configureSentry` from the package | The barrel exports no config names; import the app's own `config/sentry.dart` |
| Re-enabling `captureFailedRequests` on `addSentry()` | Leave it off; `SentryNetworkInterceptor` is the one layer that reports HTTP failures |
| Wiring `SentryNavigatorObserver` in `main()` or after the first frame | `MagicRouter` refuses an observer once `routerConfig` is built; the provider registers it in `boot()` |
| Unnamed routes, then empty release health | Give routes a `name`; the observer reads `RouteSettings.name` |
| Putting app-specific tags or team logic in a fork of this package | Pass `userExtras`, or dispatch an event implementing `ReportsBreadcrumb` |
| A secret in `breadcrumbData` | It is sent verbatim; whitelist only what is safe to store |
