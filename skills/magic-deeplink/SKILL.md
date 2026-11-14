---
name: magic-deeplink
description: "Route Universal Links, App Links and tapped pushes to Magic routes with magic_deeplink: handler chain, RouteDeeplinkHandler and the deeplink: commands."
version: 1.0.0
when_to_use: "Use when code imports package:magic_deeplink or touches DeeplinkManager, RouteDeeplinkHandler, the deeplink config or a deeplink: command in a Magic app."
---

# magic_deeplink

Deep links for a Magic app. `DeeplinkServiceProvider` wires `app_links` into `DeeplinkManager`, which offers each incoming `Uri` to its handlers in registration order; the first whose `canHandle` is true handles it. `RouteDeeplinkHandler` maps a path onto a route with `MagicRoute.to`. A tapped push from `magic_notifications` enters the same chain. The `deeplink:install`, `deeplink:generate` and `deeplink:doctor` commands scaffold the config, write the `apple-app-site-association` and `assetlinks.json` files and check the install.

This skill covers `magic_deeplink` only. The Magic framework itself (container, providers, `MagicRoute`, `Config`, `Log`, events) is the `magic-framework` skill, and the push side is `magic_notifications`.

## Install

```bash
flutter pub add magic_deeplink
dart run magic:dowel plugin:install magic_deeplink
dart run magic:dowel deeplink:doctor
```

Requires Dart >=3.13, Flutter >=3.47 and `magic` ^1.0.0. The installer publishes `lib/config/deeplink.dart`, adds `DeeplinkServiceProvider` to `lib/config/app.dart`, adds the `deeplinkConfig` factory to `lib/main.dart` and sets `FlutterDeepLinkingEnabled` to `false` in `ios/Runner/Info.plist`. It registers no handler and does not touch the Android manifest. Import only the barrel: `package:magic_deeplink/magic_deeplink.dart`.

## Setup rules

1. Finish the native setup before debugging code. iOS needs the Associated Domains capability with `applinks:<domain>`; Android needs an `autoVerify` intent filter with a `<data>` element for both `http` and `https`; both need their association file served from `https://<domain>/.well-known/`. Every miss ends the same way, a link that opens the browser with no exception and no log, so run `dart run magic:dowel deeplink:doctor` first.
2. Put `<meta-data android:name="flutter_deeplinking_enabled" android:value="false" />` inside `<activity>` by hand. The installer cannot place it there, and in `<application>` Flutter never reads it. Flutter's own deep link handler otherwise takes the link before the chain sees it.
3. `deeplink.enabled` absent means on; only an explicit `false` wires nothing, the push bridge included. `deeplink.driver` must be `'app_links'`, the only value that creates a driver; another value wires no driver, though the push bridge still runs.
4. `deeplink.paths` is written into the `components` of the AASA file and filters nothing at runtime. Which paths the app routes is decided by the handler you register.
5. A `'scheme'` key in `lib/config/deeplink.dart` is read by nothing. Delete it.
6. `generate` and `doctor` read `lib/config/deeplink.dart` as text. Keep `domain`, `team_id`, `bundle_id`, `package_name`, `sha256_fingerprints` and `paths` as single-quoted literals, not double-quoted strings or values built from a variable.
7. Do not look for a `Deeplink` facade. The entry point is `DeeplinkManager()`, also bound as `'deeplinks'` in the container.

## Handler rules

1. Register your own handler in a provider's `boot()`: `DeeplinkServiceProvider` registers none, and a link with no handler makes `handleUri` answer `false` with no error. Several handlers are normal; `forgetHandlers()` clears all of them and there is no way to remove one.
2. Register specific handlers before wildcard ones. The first `canHandle` that returns true wins, and a wildcard registered first claims what a later specific handler would have taken.
3. Set `hosts` on `RouteDeeplinkHandler`. `null` claims a matching path on any host. When set, a relative URI (a push payload path) always passes, and an absolute one is claimed only over `http` or `https`, with no explicit port and no userinfo, on a host equal to an entry, ignoring case. A blank entry is ignored, so `['']` refuses every absolute URI.
4. `:name` matches one path segment and `*` matches anything, slashes included; a trailing slash is dropped before matching. Matching ignores case unless `caseSensitive: true`, which is what a go_router app wants, since `/INCIDENTS/5` would otherwise be claimed and then land on the not-found page.
5. A custom `DeeplinkHandler` returns `Future<bool>` from `handle` and never throws. The manager does not catch: the provider logs the error and the link is lost, and no later handler is tried. `RouteDeeplinkHandler` follows the rule itself: a navigation that fails, such as the `StateError` of a router not built yet, is logged when a `log` binding exists and answered `false`.
6. `handle` takes a required `DeeplinkSource source`. Read `payload`, or act on anything beyond the path, only when `source == DeeplinkSource.push`: an `osLink` is whatever the device was asked to open and anyone can craft one, and it carries no payload. `manual` is your own `handleUri` call.
7. Move the session's tenant with `TenantSwitchGate` on `RouteDeeplinkHandler(tenantGate:)`, never by hand-reading a query value. Only a push switches, the tenant comes from the payload under `payloadKey` (default `'team_id'`) and never from the URI query, ids compare as trimmed strings, and an absent tenant or an unresolved session navigates without switching. A switch that answers `false` or throws calls `onSwitchFailed` and does not navigate, because the backend would still resolve the page against the old tenant. An `onSwitched` that throws is logged and the link still opens.
8. `DeeplinkOpened` and `DeeplinkNavigating` are dispatched by `RouteDeeplinkHandler` for crash reporters. They carry the matched pattern (`/invitations/:token/accept`), never the path, the query or a payload value, because a link can carry a token in any of them. Do not add the concrete path to a breadcrumb.

## Manager and driver rules

1. `handleUri(uri, {required source, payload})` emits the URI on `onLink` first, claimed or not, then runs the chain. It does not wait for a frame: `MagicRoute.to` throws `StateError` until the router is built, so a link you hand it during boot goes nowhere. Await `WidgetsFlutterBinding.ensureInitialized().endOfFrame` once, before the first link, then call it.
2. Do not route `getInitialLink()` as well as the provider's stream. `app_links` delivers the cold-start link as the first emission of `onLink`, so reading both runs the chain twice for one tap. The provider never calls `getInitialLink()`.
3. `manager.driver` throws `DeeplinkException` with code `NO_DRIVER` when none is set. `AppLinksDriver.isSupported` is true on Android, iOS and macOS only; on web, Windows and Linux the provider sets no driver and subscribes to nothing, so read `driver` behind a catch or not at all.
4. The provider wires only `AppLinksDriver`. A custom `DeeplinkDriver` needs `manager.setDriver`, your own `initialize`, a subscription to its `onLink` and a call to `handleUri` for each URI. `setDriver` replaces the old driver without disposing it.
5. On web the driver is inert, because GoRouter owns the address bar. Address-bar links reach a route only with `routing.url_strategy` set to `'path'` and a host rewrite of unknown paths to `index.html`. A tapped push with the tab open still routes, through the push bridge.
6. macOS is wired by the provider and covered by nothing else: the install, `doctor` and `generate` cover iOS and Android only.

## Push bridge rules

1. Nothing to write: when `app.bound('notifications')` is true the provider attaches `OneSignalDeeplinkHandler`, which subscribes to the notification manager's `onPushClicked` and calls `handleUri` with `DeeplinkSource.push` and the whole payload. It is not a `DeeplinkHandler` and is not in the chain.
2. The link is the first non-empty string under `url`, `deep_link`, `link` or `uri` in the payload. A push with none is not a failure, and a launch URL set only on the OneSignal side is not read.
3. The notification manager is read structurally, so this package does not depend on `magic_notifications` and the provider order does not matter. A manager without `onPushClicked`, or an event without a readable `data` map, is reported at error level through `Log` when a `log` binding exists and routes nothing.

## CLI rules

1. The commands exist only after `plugin:install` registered `MagicDeeplinkDowelProvider`. The package has no `bin/` of its own; run `dart run magic:dowel deeplink:<command>`.
2. `deeplink:generate` takes each value from a flag first and `lib/config/deeplink.dart` second. It writes `apple-app-site-association` when `team_id` and `bundle_id` resolve and `assetlinks.json` when `package_name` and `sha256_fingerprints` resolve; a platform with missing values is skipped with a warning and exit code `0`. The one exception is `--paths`: an explicit `--paths '/*'` is indistinguishable from the default, so it does not override a config `paths` such as `['/invite/*']`.
3. `deeplink:doctor` reads the project and exits `1` when a check fails and `0` when only warnings were raised. `--remote` also fetches both association files from the live domain and requires `deeplink.domain`. It cannot prove that a device matches a link to your app.
4. Generate into the folder the doctor looks in: `--output public/.well-known` or `web/.well-known`.

## Recipes

Route a link to a screen:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class AppServiceProvider extends ServiceProvider {
  AppServiceProvider(super.app);

  @override
  void register() {}

  @override
  Future<void> boot() async {
    DeeplinkManager().registerHandler(
      RouteDeeplinkHandler(
        paths: ['/monitors/:id', '/invitations/:token/accept'],
        hosts: [Config.getOrFail<String>('deeplink.domain')],
      ),
    );
  }
}
```

A handler of your own, checking where the link came from:

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class InviteHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) => uri.path.startsWith('/invite/');

  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    final String code = uri.pathSegments.last;

    if (code.isEmpty) return false;

    try {
      MagicRoute.to('/invite/$code');
    } on StateError {
      return false; // The router is not built yet.
    }

    return true;
  }
}
```

Switch tenant before a push opens its page:

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  String? activeTeam = '1'; // The host's own session state.

  final RouteDeeplinkHandler handler = RouteDeeplinkHandler(
    paths: ['/incidents/:id'],
    tenantGate: TenantSwitchGate(
      currentTenantId: () => activeTeam,
      switchTenant: (String teamId) async {
        activeTeam = teamId;

        return true;
      },
    ),
  );

  DeeplinkManager().registerHandler(handler);
}
```

See every link the manager is handed:

```dart
import 'package:flutter/foundation.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

void main() {
  DeeplinkManager().onLink.listen((Uri uri) => debugPrint('link: $uri'));
}
```

## Testing

No mocking library is needed. `DeeplinkManager` is a singleton that outlives the container, so call `DeeplinkManager().reset()` in `setUp` and `tearDown`: it clears the handlers and the driver, drops the cached initial link and replaces the `onLink` controller. Call `MagicApp.reset()` before a provider test, then `register()` and `await boot()` on `DeeplinkServiceProvider(app, driverFactory: () => fakeDriver)`: the real driver answers `isSupported` from the host platform, so pass a subclass of `DeeplinkDriver` instead. Drive the chain with `DeeplinkManager().handleUri(uri, source: DeeplinkSource.osLink)`. With no router built, `RouteDeeplinkHandler.handle` answers `false` rather than throwing, so assert matching with `canHandle` and navigation in a widget test with real routes.
