# magic_deeplink Plugin

Deep link handling plugin for Magic Framework — wraps `app_links` with a handler chain, IoC binding, and CLI tooling for generating server-side verification files.

## Installation

```bash
dart run magic_deeplink install
```

Scaffolds `lib/config/deeplink.dart`, injects `DeeplinkServiceProvider` into `lib/config/app.dart`, and injects `deeplinkConfig` into `lib/main.dart`.

## DeeplinkManager API

No facade — accessed via singleton `DeeplinkManager()` or IoC `Magic.make<DeeplinkManager>('deeplinks')`.

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `setDriver(driver)` | `void` | Set the active deep link driver. |
| `forgetDriver()` | `void` | Remove the current driver (resets to null). |
| `registerHandler(handler)` | `void` | Add a handler to the chain. Duplicates are ignored. |
| `hasHandler(handler)` | `bool` | Check if a handler is registered. |
| `forgetHandlers()` | `void` | Clear all registered handlers. |
| `handleUri(uri)` | `Future<bool>` | Emit `uri` on `onLink` and delegate to first matching handler. Returns `true` if handled. |
| `getInitialLink()` | `Future<Uri?>` | Get the URI that cold-launched the app (cached after first call). |
| `onLink` | `Stream<Uri>` | Broadcast stream of all incoming links (fired before handler dispatch). |
| `driver` | `DeeplinkDriver` | Getter — throws `DeeplinkException(code: 'NO_DRIVER')` if unset. |

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

final manager = DeeplinkManager();

// Register a custom handler
manager.registerHandler(MyCustomHandler());

// Listen to all links (raw stream, before handlers)
manager.onLink.listen((uri) {
  print('Incoming link: $uri');
});

// Get initial link (cold launch)
final initial = await manager.getInitialLink();
if (initial != null) {
  await manager.handleUri(initial);
}
```

## Contracts

### DeeplinkDriver

Abstract contract for platform link providers.

| Member | Type | Description |
|:-------|:-----|:------------|
| `name` | `String` | Driver identifier. |
| `isSupported` | `bool` | Whether this driver works on the current platform. |
| `initialize(config)` | `Future<void>` | Boot the driver with config map. |
| `getInitialLink()` | `Future<Uri?>` | Return the cold-launch URI, if any. |
| `onLink` | `Stream<Uri>` | Stream of subsequent incoming links. |
| `dispose()` | `void` | Release resources. |

### DeeplinkHandler

Abstract contract for URI handlers. Handlers are tested in registration order — first match wins.

| Member | Type | Description |
|:-------|:-----|:------------|
| `canHandle(uri)` | `bool` | Return `true` if this handler claims the URI. |
| `handle(uri)` | `Future<bool>` | Process the URI. Return `true` on success. |

```dart
// Custom handler example
class PaymentHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) => uri.path.startsWith('/payment');

  @override
  Future<bool> handle(Uri uri) async {
    final orderId = uri.queryParameters['order_id'];
    Route.to('/payment/confirm', extra: {'orderId': orderId});
    return true;
  }
}
```

## Built-in Implementations

### AppLinksDriver

Wraps the `app_links` package. Supports Android, iOS, and macOS. Not supported on web.

- **Driver name**: `'app_links'`
- **`isSupported`**: `true` on Android, iOS, macOS; `false` on web and other platforms.
- Registered automatically by `DeeplinkServiceProvider` when `deeplink.driver` is `'app_links'`.

### RouteDeeplinkHandler

Maps URI path patterns to `MagicRoute.to()` navigation. Patterns support wildcards (`*`) and named segments (`:param`).

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

// Match specific paths
final handler = RouteDeeplinkHandler(
  paths: ['/products/:id', '/orders/*', '/promo/:code'],
);
DeeplinkManager().registerHandler(handler);
```

- Pattern `/products/:id` matches `/products/42` (`:param` matches one path segment).
- Pattern `/orders/*` matches `/orders/any/nested/path` (`*` matches everything).
- Matching is case-insensitive.
- On match, navigates to `uri.path` and passes `uri.queryParameters`.

### OneSignalDeeplinkHandler

Auto-registered by `DeeplinkServiceProvider` when `magic_notifications` is bound in the IoC container. Extracts URIs from notification click payloads and feeds them into `DeeplinkManager.handleUri()`.

Checks for URI under these payload keys in order: `'url'`, `'deep_link'`, `'link'`, `'uri'`.

No manual registration needed when using `magic_notifications`.

## Configuration

Scaffolded to `lib/config/deeplink.dart` by `dart run magic_deeplink install`. The `ios` and `android` sub-keys are only read by `dart run magic_deeplink:generate` — they are not used at runtime.

```dart
Map<String, dynamic> get deeplinkConfig => {
  'deeplink': {
    'enabled': true,
    'driver': 'app_links',          // Only built-in driver
    'domain': 'example.com',        // Your web domain for universal/app links
    'scheme': 'https',              // 'https' or custom scheme

    'ios': {
      'team_id': 'YOUR_TEAM_ID',    // Apple Developer Team ID
      'bundle_id': 'com.example.app',
    },

    'android': {
      'package_name': 'com.example.app',
      'sha256_fingerprints': [
        'YOUR_SHA256_FINGERPRINT',  // Colon-separated hex string
      ],
    },

    'paths': [
      '/*',                         // Patterns passed to generate command
    ],
  },
};
```

## ServiceProvider

`DeeplinkServiceProvider` is **NOT auto-registered** — add it explicitly or use `dart run magic_deeplink install` which does this automatically.

**register()**: Binds `DeeplinkManager()` as a singleton under key `'deeplinks'`.

**boot()**: Resolves driver from `deeplink.driver` config → initializes it → subscribes driver's `onLink` stream to `manager.handleUri()` → schedules `getInitialLink()` via `Future.delayed(Duration.zero)` (defers until after first frame so router is ready). Also auto-registers `OneSignalDeeplinkHandler` if `'notifications'` is bound.

```dart
// lib/config/app.dart
import 'package:magic_deeplink/magic_deeplink.dart';

final appConfig = {
  'app': {
    'providers': [
      (app) => DeeplinkServiceProvider(app),
    ],
  },
};
```

## CLI Commands

### install

```bash
dart run magic_deeplink install
dart run magic_deeplink install --force   # Overwrite existing config
```

Writes `lib/config/deeplink.dart`, injects `DeeplinkServiceProvider` into `lib/config/app.dart`, and injects `deeplinkConfig` factory into `lib/main.dart`.

### generate

```bash
dart run magic_deeplink generate --output ./public
dart run magic_deeplink generate \
  --team-id ABCDE12345 \
  --bundle-id com.example.app \
  --package-name com.example.app \
  --sha256-fingerprints AA:BB:CC:... \
  --output public
```

Reads values from `lib/config/deeplink.dart` and merges with any CLI flags (flags take priority). Outputs:
- `apple-app-site-association` — iOS Universal Links verification file.
- `assetlinks.json` — Android App Links verification file.

Upload both files to your web server's `/.well-known/` directory (or domain root for AASA).

## Usage Patterns

### Basic setup with route handler

```dart
import 'package:magic_deeplink/magic_deeplink.dart';

class AppServiceProvider extends ServiceProvider {
  @override
  void register() {}

  @override
  Future<void> boot() async {
    final manager = DeeplinkManager();

    // Handle all paths defined in config
    manager.registerHandler(
      RouteDeeplinkHandler(paths: ['/products/:id', '/orders/:id', '/*']),
    );
  }
}
```

### Custom handler with specific logic

```dart
class InviteHandler extends DeeplinkHandler {
  @override
  bool canHandle(Uri uri) => uri.path == '/invite' && uri.queryParameters.containsKey('code');

  @override
  Future<bool> handle(Uri uri) async {
    final code = uri.queryParameters['code']!;
    await Magic.make<InviteService>('invites').redeem(code);
    Route.to('/welcome');
    return true;
  }
}

// Register specific handlers before catch-all
manager.registerHandler(InviteHandler());
manager.registerHandler(RouteDeeplinkHandler(paths: ['/*']));  // Catch-all last
```

### Listening to all links without intercepting

```dart
// Subscribe to raw link stream — does not affect handler chain
DeeplinkManager().onLink.listen((uri) {
  Log.info('Deep link received', {'uri': uri.toString()});
});
```

## Testing

```dart
setUp(() {
  MagicApp.reset();
  Magic.flush();
  DeeplinkManager().forgetHandlers();
  DeeplinkManager().forgetDriver();
});

test('handles product deep link', () async {
  final handler = RouteDeeplinkHandler(paths: ['/products/:id']);
  DeeplinkManager().registerHandler(handler);

  final handled = await DeeplinkManager().handleUri(
    Uri.parse('https://example.com/products/42'),
  );
  expect(handled, isTrue);
});
```

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Accessing `DeeplinkManager().driver` before provider boots | `DeeplinkServiceProvider` sets the driver in `boot()` — accessing `driver` before that throws `DeeplinkException(code: 'NO_DRIVER')` |
| Initial link never handled | `getInitialLink()` is deferred via `Future.delayed(Duration.zero)` — router must be initialized before it fires |
| Catch-all handler registered first | Handler chain is first-match-wins — register specific handlers before `RouteDeeplinkHandler(paths: ['/*'])` |
| `OneSignalDeeplinkHandler` not activating | Requires `'notifications'` to be bound in IoC before `DeeplinkServiceProvider.boot()` runs — ensure provider order in `app.dart` |
| `forgetHandlers()` skipped in tests | Always call `DeeplinkManager().forgetHandlers()` + `forgetDriver()` in `setUp()` — manager is a singleton |
| `generate` command missing iOS output | Requires both `--team-id` and `--bundle-id` — skips AASA silently if either is missing |
| `RouteDeeplinkHandler` `:param` not matching | `:param` matches a single path segment only — use `*` for multi-segment patterns |
