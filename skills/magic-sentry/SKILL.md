---
name: magic-sentry
description: "Boot Sentry before Magic.init, report HTTP failures, track the user and mask URL tokens in a Magic app with magic_sentry."
version: 1.0.0
when_to_use: "Use when code imports package:magic_sentry or touches MagicSentry.run, SentryServiceProvider, SentryTokenScrubber or Sentry setup in a Magic app."
---

# magic_sentry

Sentry for a Magic app. `MagicSentry.run` starts the SDK before `Magic.init` in one web-safe zone; `SentryServiceProvider` then wires an HTTP failure interceptor, the scope user, event breadcrumbs and the navigator observer; `SentryTokenScrubber` masks URL-borne tokens before anything is sent. Every part is inert without a DSN. The package is generic on purpose: it has no user model, team or tag, and app data reaches it through callbacks.

This skill covers `magic_sentry` only. The Magic framework itself (container, facades, routing, `Auth`) is the `magic-framework` skill, and Sentry's own SDK is Sentry's documentation.

## Install

```bash
flutter pub add magic_sentry
dart run magic:dowel plugin:install magic_sentry
```

Requires Dart >=3.13, Flutter >=3.47 and `magic` ^1.0.0, with `sentry_flutter` and `sentry_dio` ^10.3.0 pulled in (Android `minSdk` 26, iOS 15, macOS 12). The installer publishes `lib/config/sentry.dart` and registers the provider in `lib/config/app.dart`; it cannot rewrite `main()`. Import only the barrel: `package:magic_sentry/magic_sentry.dart`. `package:magic_sentry/cli.dart` (`MagicSentryDowelProvider`, no commands) is for dowel's `plugin:install`, never for app code.

## Boot rules

1. `MagicSentry.run(configure: configureSentry, appRunner: _boot)` is the entire body of `main()`, and `Magic.init` plus `runApp` go inside `appRunner`. Sentry starts first so a boot failure is reported, and one zone keeps Flutter web from raising a "Zone mismatch".
2. Never call `WidgetsFlutterBinding.ensureInitialized()` before `run`. It creates `SentryWidgetsFlutterBinding`, and an existing plain binding is kept, which switches frame tracking off.
3. `configure` runs before `Config` exists, so read `.env` through `Env`, never `Config.get`. The published `lib/config/sentry.dart` already does, and `install.yaml` has no `magic.config_factory` key for that reason.
4. Import `configureSentry` from the app's own `config/sentry.dart`. The barrel exports no config names, and a package copy would make the documented `main()` an ambiguous import.
5. An empty `SENTRY_DSN` is valid and means off: `Sentry.isEnabled` is false, `boot()` returns early, `appRunner` still runs. `sentryDsn` is a `String`, never null, because `Sentry.init` throws on a null DSN.
6. `sendDefaultPii` and session replay stay off in `configureSentry`. An app that wants either sets it in its own `configure`, never from `.env`. `SENTRY_RELEASE` is read from the bundled `.env`, not from `--dart-define`.
7. Call `MagicSentry.installErrorWidgetBreadcrumb()` once, early in `appRunner`; it tags a build error that replaced the interface.

## Provider rules

1. Register `SentryServiceProvider<T>` in the `providers` list of `lib/config/app.dart`. `boot()` adds `SentryNavigatorObserver` to `MagicRouter`, which refuses one after it has built its `routerConfig`, so wiring it later fails.
2. `userId` turns user reporting on; `userEmail` and `userExtras` are optional. `T` is the app's own `Authenticatable` model. Read straight off the model: the callbacks run on every auth change, so no network call. Return a `String` from `userId`: `Model.id` is `dynamic` and often an `int`, which throws when the context installs, so write `user.id?.toString() ?? ''`.
3. `Auth.stateNotifier` drives the user, so sign-out sets it to null. `userExtras` keys replace the previous call's, so a team switch leaks no old tag.
4. Leave `captureFailedRequests` off on `sentry_dio`'s `addSentry()`. `SentryNetworkInterceptor` is the one layer that reports HTTP failures, and its events carry a stack trace at your call site and an endpoint fingerprint.

## HTTP rules

Magic's `Http` never throws, so a failure is a `MagicResponse` value and only the interceptor reports it. Status `0` (no response) and `>= 500` become an event, fingerprinted `['http', method, endpoint, status]`; anything else is a `warning` breadcrumb, because a 4xx is usually the product working. The endpoint has its query dropped and numeric or UUID segments collapsed to `{id}` so one endpoint is one issue. One event per distinct `METHOD endpoint status` per session, then `(repeat)` breadcrumbs. Do not use `normalizeEndpoint` to make a URL safe to send: it collapses ids only, and `SentryTokenScrubber.scrubApiUrl` masks what is left.

## Scrubbing rules

`run` installs `SentryTokenScrubber` after `configure`, so it runs first in `beforeSend`, `beforeSendTransaction`, `beforeSendSpan`, `beforeBreadcrumb` and `beforeSendLog` and hands the masked value to the app's hook. It masks query values whose key contains `token`, `password`, `secret`, `signature`, `credential` or `api_key`; path segments bound to a route param whose name contains `token` (from `MagicRouter.instance.allRoutes`, groups included); and on an `http` breadcrumb or span URL any 32+ character opaque segment, a UUID excepted. It only masks, fails closed to `[Filtered]`, and covers streamed spans because `sentry_flutter` 10 streams by default and never builds a transaction.

- Set app hooks inside `configure`. A hook assigned after `SentryFlutter.init` replaces the scrubber.
- Name a credential route param with `token` in it (`:resetToken`), or the route rule does not see it.
- Keep secrets out of `breadcrumbData` and transaction `extra`; the first is sent as written apart from masking, the second is not scrubbed.

## Recipes

Wire the app:

```dart
import 'package:magic/magic.dart';
import 'package:magic_sentry/magic_sentry.dart';
import 'package:material_ui/material_ui.dart';

import 'config/app.dart';
import 'config/sentry.dart'; // published by plugin:install

void main() {
  MagicSentry.run(configure: configureSentry, appRunner: _boot);
}

Future<void> _boot() async {
  MagicSentry.installErrorWidgetBreadcrumb();

  await Magic.init(
    configFactories: [
      () => appConfig,
      // Keep every other config factory your main() already passes.
    ],
  );

  runApp(MagicApplication(title: 'My App'));
}
```

Report the user and tag a team (`User` is the app's model):

```dart
(app) => SentryServiceProvider<User>(
  app,
  userId: (user) => user.id?.toString() ?? '',
  userEmail: (user) => user.email,
  userExtras: (user) => {'plan': user.plan},
),
```

Make an event leave a breadcrumb:

```dart
import 'package:magic/magic.dart';

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

## Testing

No mocking library is needed, and without a DSN nothing needs setting up. To read the scope user, bind a hub with a placeholder DSN and undo it afterwards:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  setUp(() async {
    MagicApp.reset();
    Magic.flush();
    await Sentry.init(
      (options) => options.dsn = 'https://public@o0.ingest.sentry.io/0',
    );
  });

  tearDown(() async {
    Auth.unfake();
    await Sentry.close();
  });

  test('the scope starts with no user', () async {
    SentryUser? user;

    await Sentry.configureScope((scope) => user = scope.user);

    expect(user, isNull);
  });
}
```

`SentryNetworkInterceptor.dispositionFor`, `normalizeEndpoint`, `SentryUserContext.userFor` and `EventBreadcrumbs.breadcrumbFor` are plain functions. The scrubber's route rule reads `MagicRouter.instance.allRoutes`, so register routes with `MagicRoute.page` first and call `MagicRouter.reset()` in `tearDown`. `SentryNetworkInterceptor.reportedFailures` is a static set that survives between tests: clear it in `setUp`.
