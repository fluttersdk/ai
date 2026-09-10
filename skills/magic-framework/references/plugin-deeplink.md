<!-- magic_deeplink v0.1.0 | Updated: 2026-09-09 -->

# magic_deeplink Plugin

Deep link handling plugin for Magic Framework: wraps `app_links` with a handler chain, IoC binding, and CLI tooling for generating the platform association files. Universal Links on iOS and macOS, App Links on Android. The web DRIVER is a deliberate no-op, which is not the same as no deep links on web: tapped push notifications still route, and address-bar links are GoRouter's half. See [AppLinksDriver](#applinksdriver).

## Contents

- [Installation](#installation)
- [Platform setup](#platform-setup)
- [DeeplinkManager API](#deeplinkmanager-api)
- [Contracts](#contracts)
- [Built-in Implementations](#built-in-implementations)
- [Configuration](#configuration)
- [ServiceProvider](#serviceprovider)
- [CLI Commands](#cli-commands)
- [Usage Patterns](#usage-patterns)
- [Testing](#testing)
- [Gotchas](#gotchas)

## Installation

```bash
flutter pub add magic_deeplink

# Register the plugin's artisan provider with the app dispatcher (once)
dart run magic:artisan plugin:install magic_deeplink

# Scaffold the config, inject the provider, wire the config factory
dart run magic:artisan deeplink:install
```

The order matters: every `deeplink:*` command is contributed by `MagicDeeplinkArtisanProvider`, and the dispatcher only knows about that provider after `plugin:install` has written it into `.artisan/plugins.json` and regenerated `lib/app/_plugins.g.dart`. Run the second command first and the dispatcher reports an unknown command.

**Know it worked**: `dart run magic:artisan list` lists the `deeplink:*` commands, and `dart run magic:artisan deeplink:doctor` reports on the config, the Dart wiring and both platforms' setup. Run it before reaching for a device; every way of getting this install wrong is silent, and the doctor is the only thing that separates "installed" from "installed and inert".

`deeplink:install` scaffolds `lib/config/deeplink.dart`, injects `DeeplinkServiceProvider` into `lib/config/app.dart`, injects `deeplinkConfig` into `lib/main.dart`'s `configFactories`, and sets `FlutterDeepLinkingEnabled` to `false` in `ios/Runner/Info.plist`. Everything under [Platform setup](#platform-setup) that is not that plist key is manual.

## Platform setup

An operating system will not hand the app a link until the app proves it owns the domain, and Flutter's own deep link handler (on by default since Flutter 3.27) races the `app_links` driver this package wires in unless it is switched off. A plugin installed without these steps compiles and never fires.

### iOS

1. Add the Associated Domains capability in Xcode (Runner target, Signing & Capabilities), with an entry `applinks:<your-domain>`. It writes the entitlement:

   ```xml
   <key>com.apple.developer.associated-domains</key>
   <array>
       <string>applinks:example.com</string>
   </array>
   ```

2. `ios/Runner/Info.plist` carries `FlutterDeepLinkingEnabled` `false`. `deeplink:install` applies this key; re-check it on a project that predates the manifest installer.

   ```xml
   <key>FlutterDeepLinkingEnabled</key>
   <false/>
   ```

3. Upload `apple-app-site-association` (from `deeplink:generate`) to `https://<your-domain>/.well-known/apple-app-site-association`, over HTTPS with no redirect.

### Android

1. Add an `autoVerify` intent filter inside the `.MainActivity` `<activity>` in `android/app/src/main/AndroidManifest.xml`, with a `<data>` element for **both** `http` and `https` (Android requires both, even for an HTTPS-only site):

   ```xml
   <activity
       android:name=".MainActivity"
       android:exported="true"
       ...>
       <intent-filter android:autoVerify="true">
           <action android:name="android.intent.action.VIEW" />
           <category android:name="android.intent.category.DEFAULT" />
           <category android:name="android.intent.category.BROWSABLE" />

           <data android:scheme="http" android:host="example.com" />
           <data android:scheme="https" android:host="example.com" />
       </intent-filter>
   </activity>
   ```

2. Add the Flutter switch **inside that same `<activity>`**, not inside `<application>`:

   ```xml
   <meta-data android:name="flutter_deeplinking_enabled" android:value="false" />
   ```

   `deeplink:install` does NOT apply this one. Artisan's `XmlEditor` inserts `<meta-data>` into `<application>`, and Flutter reads this key from `<activity>`, so automating it would write an entry Flutter never looks at.

3. Upload `assetlinks.json` to `https://<your-domain>/.well-known/assetlinks.json`. Android verifies it at install time, not at click time.

**Know it worked**: `xcrun simctl openurl booted "https://example.com/products/42"` on a booted simulator, `adb shell am start -W -a android.intent.action.VIEW -d "https://example.com/products/42" <package>` on a device, and the registered handler runs. `adb shell pm get-app-links <package>` reports the domain verification state on Android.

## DeeplinkManager API

No facade. Reach it as the singleton `DeeplinkManager()` or through IoC as `Magic.make<DeeplinkManager>('deeplinks')`.

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `setDriver(driver)` | `void` | Set the active deep link driver. |
| `forgetDriver()` | `void` | Remove the current driver (resets to null). |
| `registerHandler(handler)` | `void` | Add a handler to the chain. Duplicates are ignored. |
| `hasHandler(handler)` | `bool` | Check if a handler is registered. |
| `forgetHandlers()` | `void` | Clear all registered handlers. |
| `handleUri(uri, {source, payload})` | `Future<bool>` | Emit `uri` on `onLink`, then delegate to the first matching handler. `source` is required. Returns `true` if a handler handled it. **Does not wait for a frame**: see below. |
| `getInitialLink()` | `Future<Uri?>` | The URI that cold-launched the app, cached after the first call. The provider does NOT call this; see [ServiceProvider](#serviceprovider). |
| `onLink` | `Stream<Uri>` | Broadcast stream of all incoming links (fired before handler dispatch). |
| `driver` | `DeeplinkDriver` | Getter. Throws `DeeplinkException(code: 'NO_DRIVER')` if unset. |
| `reset()` | `void` | `@visibleForTesting`. Forgets handlers and driver, drops the cached initial link, and replaces the `onLink` controller. |

Both in-package callers of `handleUri` wait for the first frame before routing, and it is the CALLER that waits, not the sink. Call `handleUri` or `getInitialLink` yourself during boot and you inherit none of that: magic's router cannot accept a navigation before anything is drawn, so the link goes nowhere and the app finishes booting onto its initial route, with no exception and no log. Measured on a device, that is exactly how the push path failed before it took the same wait. If you drive the chain by hand from boot:

```dart
await WidgetsFlutterBinding.ensureInitialized().endOfFrame;
await manager.handleUri(uri, source: DeeplinkSource.manual);
```

`endOfFrame` rather than a post-frame callback, because it SCHEDULES a frame when the scheduler is idle; a post-frame callback on an application nobody is drawing waits for a frame that never comes. Capture it once if you route more than one link, or each await queues behind a different frame and the links can arrive out of order.

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

final manager = DeeplinkManager();

manager.registerHandler(MyCustomHandler());

// Raw stream, before handlers.
manager.onLink.listen((uri) => Log.info('Incoming link', {'uri': '$uri'}));

// Drive the chain by hand (a debug button, a test).
await manager.handleUri(
  Uri.parse('https://example.com/products/42'),
  source: DeeplinkSource.manual,
);
```

## Contracts

### DeeplinkDriver

Abstract contract for platform link providers.

| Member | Type | Description |
|:-------|:-----|:------------|
| `name` | `String` | Driver identifier. |
| `isSupported` | `bool` | Whether this driver works on the current platform. Read by the provider before anything is wired. |
| `initialize(config)` | `Future<void>` | Boot the driver with the `deeplink` config map. |
| `getInitialLink()` | `Future<Uri?>` | The cold-launch URI, if any. Return `null` rather than throwing. |
| `onLink` | `Stream<Uri>` | Stream of incoming links. |
| `dispose()` | `void` | Release resources. |

### DeeplinkHandler

Abstract contract for URI handlers. Handlers are tested in registration order, first match wins, and `handle` never throws.

```dart
abstract class DeeplinkHandler {
  bool canHandle(Uri uri);
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  });
}
```

### DeeplinkSource

```dart
enum DeeplinkSource { osLink, push, manual }
```

| Value | Meaning | `payload` |
|:------|:--------|:----------|
| `osLink` | The OS opened the app on a Universal Link or App Link. Attacker-craftable: anyone who can get the device to open a URI produces one. | Always `null`. |
| `push` | The user tapped a push notification, and the payload is the server's own. | The full push payload. |
| `manual` | The app asked for the link itself, in code or in a test. | Whatever the caller passed, or `null`. |

`source` is required rather than defaulted on purpose. A handler that acts on more than the path (switching the active team off a `team_id` key, say) may only do that when `source == DeeplinkSource.push`, because that is the one case where the payload was authored by the server. A handler that forgot to ask would treat a crafted OS link exactly like a trusted push.

```dart
class TeamInviteHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) => uri.path == '/invite';

  @override
  Future<bool> handle(
    Uri uri, {
    required DeeplinkSource source,
    Map<String, dynamic>? payload,
  }) async {
    // Only a server-authored payload may switch the active team.
    if (source == DeeplinkSource.push && payload?['team_id'] != null) {
      await TeamController.instance.switchTeam(payload!['team_id']);
    }

    MagicRoute.to('/invite', query: uri.queryParameters);
    return true;
  }
}
```

## Built-in Implementations

### AppLinksDriver

A conditional-export barrel over three arms, selected at compile time:

```dart
export 'app_links_driver_stub.dart'
    if (dart.library.js_interop) 'app_links_driver_web.dart'
    if (dart.library.io) 'app_links_driver_io.dart';
```

- **Driver name**: `'app_links'` on every arm.
- **io arm**: wraps the `app_links` package; `isSupported` is `Platform.isAndroid || Platform.isIOS || Platform.isMacOS`. It is the only arm that touches a platform channel.
- **web arm**: inert, not partial. `isSupported` is `false`, `getInitialLink()` is `null`, `onLink` is `const Stream<Uri>.empty()`, `initialize`/`dispose` do nothing. It is NOT wired to `app_links_web`, which reads `location.href` once at boot and never reacts to later navigation, while GoRouter already owns the address bar.

  **An inert driver is not an inert feature, and reading only this line has sent people away from something that works.** The push bridge is wired OUTSIDE the `isSupported` gate, so on web a tapped OneSignal push with the tab open reaches the same handler chain as on mobile, through `OneSignalWebDriver`. Put the link in the notification's `additionalData` under `url`, `deep_link`, `link` or `uri`; a launch URL set on the OneSignal side alone is not read by the bridge. The address-bar half is GoRouter's and needs two things this package does not own and cannot check: `routing.url_strategy: 'path'`, and a host rewrite of unknown paths to `index.html`. Without either, the URL is a 404 or a hash route and the app never sees it. A push clicked with NO tab open runs no Dart at all, so it arrives as an ordinary page load and needs both.
- **stub arm**: the default when neither guard matches; same inert answers.

The provider registers it automatically when `deeplink.driver` is `'app_links'` and `isSupported` is true.

### RouteDeeplinkHandler

Maps URI path patterns to navigation. Constructor: `RouteDeeplinkHandler({required List<String> paths})`.

```dart
DeeplinkManager().registerHandler(
  RouteDeeplinkHandler(paths: ['/products/:id', '/orders/*', '/promo/:code']),
);
```

- `:param` matches one path segment; `*` matches anything (it compiles to `.*`).
- Matching is case-insensitive, and a trailing slash is stripped before comparison.
- On match it calls `MagicRoute.to(uri.path, query: uri.queryParameters)` and returns `true`.
- It ignores `source` and `payload` deliberately: navigating to a path the consumer listed is safe whoever asked for it.

### OneSignalDeeplinkHandler

Not a `DeeplinkHandler`. It is a listener adapter that turns a tapped push into a `handleUri` call, wired automatically by `DeeplinkServiceProvider` when `'notifications'` is bound in the container.

```dart
void setup(DeeplinkManager manager, dynamic notifications)
void dispose()
Uri? extractUri(Map<String, dynamic>? data)
Map<String, dynamic>? extractData(dynamic event)
```

- It subscribes to the notification MANAGER's `onPushClicked` stream (owned from construction), never a push driver's, which is what makes it independent of provider order.
- `notifications` is read structurally as `dynamic`, so this package declares no dependency on `magic_notifications`.
- URI keys checked in order: `url`, `deep_link`, `link`, `uri`. First non-empty string that parses wins.
- The whole payload travels with the URI as `source: DeeplinkSource.push`.
- Failures (a manager with no `onPushClicked`, an event with no readable `data`, a throwing handler) are reported at error level through `Log`, guarded by `Magic.bound('log')`.

`NotificationManager.onPushClicked` arrives in `magic_notifications` 0.1.0. This package declares no dependency on it, so nothing enforces that floor: pair it with an older release and you get the error-level report instead of a routed link.

## Configuration

Scaffolded to `lib/config/deeplink.dart` by `deeplink:install`. The `ios` and `android` sub-keys are read by `deeplink:generate` only; they are not used at runtime.

```dart
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',          // only built-in driver
    'domain': 'example.com',        // your Universal Link / App Link domain
    'scheme': 'https',

    'ios': {
      'team_id': 'YOUR_TEAM_ID',    // Apple Developer Team ID
      'bundle_id': 'com.example.app',
    },

    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'YOUR_SHA256_FINGERPRINT',  // keystore SHA-256, colon-separated
      ],
    },

    'paths': [
      '/*',                         // patterns passed to the generate command
    ],
  },
};
```

`deeplink.enabled` is honoured by the provider: an ABSENT key means enabled, and only an explicit `false` wires nothing.

## ServiceProvider

`DeeplinkServiceProvider` is **NOT auto-registered**; `deeplink:install` injects it into `lib/config/app.dart`.

```dart
DeeplinkServiceProvider(super.app, {DeeplinkDriver Function()? driverFactory})
```

**register()**: binds `DeeplinkManager()` as a singleton under the key `'deeplinks'`.

**boot()**, in order:

1. Returns immediately when `deeplink.enabled` is explicitly `false`.
2. Builds the driver through `driverFactory` (default `AppLinksDriver.new`) when `deeplink.driver` is `'app_links'`.
3. Wires it only when `driver.isSupported`: sets it on the manager and awaits `driver.initialize(config)`. An unsupported platform leaves `manager.driver` unset.
4. Subscribes to `driver.onLink` as the ONE delivery path. `manager.getInitialLink()` is not called: `app_links` serves the cold-start link on the stream too, and reading both ran the whole handler chain twice per tap.
5. Defers each delivery until `WidgetsFlutterBinding.ensureInitialized().endOfFrame`, captured once at boot, because `MagicRoute.to` throws until `MagicApp` has built the router. `endOfFrame` schedules a frame when the scheduler is idle, so a link handed to an app nobody is drawing still lands. A routing failure is reported through `Log.error`, not swallowed and not left to escape as an unhandled async error.
6. Wires `OneSignalDeeplinkHandler` when `app.bound('notifications')`, guarded: a throw here would abort app boot and every provider after it, over an optional plugin.

**dispose()**: idempotent provider-level teardown. Disposes the push-click handler, cancels the link subscription, disposes the driver, and calls `manager.forgetDriver()`. A teardown landing inside `boot`'s `await` is covered by an internal flag.

`driverFactory` exists for tests: the real driver answers `isSupported` from the host platform and takes its stream from `app_links`, so neither the gate nor the delivery path can be exercised through it.

`boot()` does NOT register a `RouteDeeplinkHandler`; it has no way to know which paths the app claims. Register one yourself (see below).

## CLI Commands

### install

```bash
dart run magic:artisan deeplink:install
dart run magic:artisan deeplink:install --force     # overwrite lib/config/deeplink.dart
dart run magic:artisan deeplink:install --dry-run   # preview, write nothing
```

### generate

```bash
dart run magic:artisan deeplink:generate --output ./public
dart run magic:artisan deeplink:generate \
  --team-id ABCDE12345 \
  --bundle-id com.example.app \
  --package-name com.example.app \
  --sha256-fingerprints AA:BB:CC:... \
  --output public
```

Reads `lib/config/deeplink.dart` and merges CLI flags over it (flags win). Options: `--output` (default `public`), `--root` (default `.`), `--team-id`, `--bundle-id`, `--package-name`, plus the multi-value `--sha256-fingerprints` and `--paths` (default `['/*']`). Outputs:

- `apple-app-site-association`, in Apple's modern `appIDs` + `components` shape (TN3155), no `apps` key. Written only when both `--team-id` and `--bundle-id` resolve; otherwise the command WARNS and continues.
- `assetlinks.json`. Written only when both `--package-name` and `--sha256-fingerprints` resolve, same warning otherwise.

### doctor

```bash
dart run magic:artisan deeplink:doctor
dart run magic:artisan deeplink:doctor --verbose
dart run magic:artisan deeplink:doctor --remote   # also fetch both files from the live domain
```

Ships in 0.1.0, the release this file is stamped for. It reads `lib/config/deeplink.dart` (rejecting the scaffold placeholders `example.com`, `YOUR_TEAM_ID`, `com.example.app`, `YOUR_SHA256_FINGERPRINT`), then checks iOS (`applinks:` entitlement host, `FlutterDeepLinkingEnabled`), Android (the manifest's element TREE, so a `flutter_deeplinking_enabled` meta-data sitting on `<application>` instead of `<activity>` is caught where a grep cannot see it, plus the `autoVerify` filter's `http`/`https` schemes and host) and the two generated association files against the config. Everything is local and read-only without `--remote`. The one thing it cannot prove is that a real device matches an incoming link to this app, and the report says so.

## Usage Patterns

### Registering the route handler

```dart
import 'package:magic/magic.dart';
import 'package:magic_deeplink/magic_deeplink.dart';

class AppServiceProvider extends ServiceProvider {
  @override
  void register() {}

  @override
  Future<void> boot() async {
    DeeplinkManager().registerHandler(
      RouteDeeplinkHandler(
        paths: app.make<ConfigRepository>('config').get('deeplink.paths'),
      ),
    );
  }
}
```

### Specific handler before the catch-all

```dart
final manager = DeeplinkManager();

manager.registerHandler(TeamInviteHandler());                        // specific first
manager.registerHandler(RouteDeeplinkHandler(paths: ['/*']));        // catch-all last
```

### Listening without intercepting

```dart
// Raw stream: does not affect the handler chain.
DeeplinkManager().onLink.listen((uri) {
  Log.info('Deep link received', {'uri': uri.toString()});
});
```

## Testing

```dart
setUp(() {
  MagicApp.reset();
  DeeplinkManager().reset();   // handlers, driver, cached initial link, onLink controller
});

tearDown(() => DeeplinkManager().reset());

test('handles product deep link', () async {
  DeeplinkManager().registerHandler(RouteDeeplinkHandler(paths: ['/products/:id']));

  final handled = await DeeplinkManager().handleUri(
    Uri.parse('https://example.com/products/42'),
    source: DeeplinkSource.osLink,
  );

  expect(handled, isTrue);
});
```

Inject a fake driver to exercise the provider: `DeeplinkServiceProvider(app, driverFactory: () => FakeDeeplinkDriver())`.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Plugin installed, nothing ever fires | The [platform setup](#platform-setup) is the usual cause: no associated-domains entitlement, no `autoVerify` intent filter, or Flutter's own deep linking still on. Every one of those fails silently (the link just opens the browser), so run `deeplink:doctor` rather than reading the manifest by eye. |
| `handle(Uri uri)` with no `source` | The contract is `handle(uri, {required DeeplinkSource source, Map<String, dynamic>? payload})`. A pre-0.1.0 handler does not compile. |
| Navigating with the bare `Route` facade | The facade is `MagicRoute`; unqualified `Route` resolves to Flutter's own `Route<T>`. The signature is `MagicRoute.to(String path, {Map<String, String>? query})`; there is no `extra` parameter. |
| Acting on `payload` regardless of `source` | Only `DeeplinkSource.push` carries a server-authored payload. An `osLink` URI is attacker-craftable and carries none. |
| Accessing `DeeplinkManager().driver` before boot, or on web | The provider sets the driver in `boot()`, and only when `isSupported`. Otherwise the getter throws `DeeplinkException(code: 'NO_DRIVER')`. |
| Expecting `getInitialLink()` to be called for you | The provider delivers the cold-start link off `driver.onLink` and never calls it. Call it yourself only if you want to ask directly. |
| Deep links dead after setting `deeplink.enabled: false` | An explicit `false` wires nothing at all: no driver, no subscription, no push bridge. An absent key means enabled. |
| Catch-all handler registered first | First match wins. Register specific handlers before `RouteDeeplinkHandler(paths: ['/*'])`. |
| Worrying about provider order for the push bridge | It does not matter, PROVIDED `magic_notifications` buffers cold-start clicks (its reference says whether yours does). Boot runs after every provider has registered (`magic/lib/src/foundation/application.dart:353`), and the bridge subscribes to the notification manager's own click stream. That stream is a broadcast one, and a broadcast stream drops what it publishes to nobody: the tap that COLD-STARTS the app is drained during `driver.initialize()`, so a build where notifications boots first, and whose manager does not buffer, loses it with no exception and no log. On such a build, list `DeeplinkServiceProvider` before `NotificationServiceProvider`. Note the installer appends each provider to the END of the list, so the order you get is the order you installed in. |
| `reset()` skipped in tests | `DeeplinkManager` is a singleton that outlives the container; a stale cached initial link or handler leaks into the next test. |
| `generate` produced only one file | It warns and continues: AASA needs `--team-id` plus `--bundle-id`, `assetlinks.json` needs `--package-name` plus `--sha256-fingerprints`. |
| `:param` not matching a nested path | `:param` matches a single segment only. Use `*` for multi-segment patterns. |
