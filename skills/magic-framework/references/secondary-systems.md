# Magic Framework: Secondary Systems

Complete reference for Magic framework utility systems: Cache, Events, Logging, Localization, Storage, Encryption, Vault, Carbon, Launch, and Pick. All systems are accessible through facades after importing `package:magic/magic.dart`.

## Contents

- [Support Helpers (Number, Str, Arr, Cast)](#support-helpers)
- [Environment Variables (Env)](#environment-variables-env)
- [Cache System](#cache-system)
- [Event Dispatcher](#event-dispatcher)
- [Logging Manager](#logging-manager)
- [Localization (Translator)](#localization-translator)
- [Session (Flash Store)](#session-flash-store)
- [Storage Manager](#storage-manager)
- [Encryption (Crypt Facade)](#encryption-crypt-facade)
- [Vault (Security Storage)](#vault-security-storage)
- [Carbon (Date Manipulation)](#carbon-date-manipulation)
- [Launch (URL Launcher)](#launch-url-launcher)
- [Pick (File & Image Selection)](#pick-file--image-selection)
- [Broadcasting](#broadcasting)
- [Sync](#sync)
- [Key Gotchas](#key-gotchas)

## Support Helpers (Number, Str, Arr, Cast)

Four `abstract final class` static namespaces under `lib/src/support/`, no facade, no IoC binding, no shared base class between them. Full doc page with tr/en examples: `doc/digging-deeper/helpers.md`.

### Number

Locale-aware number formatting. Every method resolves `locale` (or `Lang.current` when omitted) through `Intl.verifiedLocale`, falling back to `'en'` for a locale intl has no data for.

| Method | Description |
|:-------|:------------|
| `Number.format(value, {precision, maxPrecision, grouped, locale})` | Locale grouping/decimal marks. `grouped: false` drops the thousands separator. |
| `Number.currency(amount, {code, precision, locale})` | Built on `simpleCurrency`, not `currency`: resolves the locale's symbol (`'₺1.234,50'`), not a bare ISO code. |
| `Number.percentage(value, {precision, maxPrecision, locale})` | Takes a 0-100 input like Laravel, not intl's native 0-1 fraction. |
| `Number.fileSize(bytes, {precision, maxPrecision, locale})` | Steps by 1024 (B/KB/MB/GB/TB/PB). |
| `Number.abbreviate(value, {precision, maxPrecision, locale})` | Compacts with the locale's own unit letters (`Mn`/`B` tr, `M`/`K` en). |

### Str

Locale-aware casing. `String.toUpperCase()`/`toLowerCase()` get Turkish/Azerbaijani wrong (dotted `i` vs dotless `ı`); `Str.upper`/`Str.lower` correct for it, defaulting `locale` to `Lang.current.languageCode` and accepting a full tag (`tr_TR`, `tr-TR`).

| Method | Description |
|:-------|:------------|
| `Str.upper(value, {locale})` / `Str.lower(value, {locale})` | Dotted-i aware casing. `İ` maps to a plain `i` in EVERY locale (not only tr/az) to avoid the web's combining-dot lowercase. |
| `Str.initials(value, {limit, capitalize, locale})` | First letter of each whitespace-separated word; `limit` keeps only the first N words. |
| `Str.unwrap(value, before, [after])` | Strips `before` from the start and `after` (default `before`) from the end, each checked/stripped independently (Laravel's `Str::unwrap`); a prefix-only match (`'"x'`) still loses the leading quote. |
| `Str.ascii(value)` | Folds Latin-1 Supplement, Latin Extended-A, the Romanian comma-below letters, `ẞ`, and U+212B to their plain ASCII base, for a search key. A Latin letter outside that coverage (Vietnamese, ...) and every other script pass through untouched; combining marks (U+0300-U+036F) are always dropped. Diverging from Laravel's `Str::ascii`, which transliterates every script it has a table for. |
| `Str.squish(value)` | Trims and collapses every run of whitespace to one space (Laravel's `Str::squish`), over Dart's `\s` class plus two Hangul filler code points. |

### Arr

Dot-path access into a nested `Map<String, dynamic>`, mirroring Laravel's `Arr::get`/`has`/`set`/`dot`. Carries NO typed accessors; compose with `Cast`.

| Method | Description |
|:-------|:------------|
| `Arr.get(map, path, [fallback])` | An exact key wins over walking the path; a numeric segment indexes into a `List`. |
| `Arr.has(map, path)` | True even for a reachable `null` leaf. |
| `Arr.set(map, path, value)` | Creates intermediate maps for a missing or non-map segment. |
| `Arr.dot(map, {prepend})` | Flattens to dotted-key leaves; an empty nested map is kept as its own leaf. |

### Cast

Total, throw-free readers for a loosely-typed wire value (a nested-map field, not a model attribute, which the ORM already coerces via `get<T>`).

| Method | Numeric string? | Notes |
|:-------|:-----------------|:------|
| `Cast.stringOr(v, fallback)` / `stringOrNull(v)` | n/a | |
| `Cast.intOr(v, fallback)` | **Parses** | The one reader that parses a numeric string (orders/durations: a silent fallback would misorder a list). |
| `Cast.intOrNull(v)` / `numOrNull(v)` / `doubleOrNull(v)` | Does NOT parse | Checks `is num`, never `is double` (JSON `3` decodes as double on web, int on VM). |
| `Cast.boolOr(v, fallback)` / `boolOrNull(v)` | n/a | |
| `Cast.idOrNull(v)` | Stringifies a `num` | A pk can be uuid or bigint; reading an int id as null would corrupt a save-diff. |

## Environment Variables (Env)

`Env`/`env()` mimic Laravel's `env()` helper over `flutter_dotenv`. Full doc page: `doc/getting-started/configuration.md`.

`Env.get<T>(key, [defaultValue])`/`env<T>(key, [defaultValue])` only fall back to `defaultValue` when `key` is entirely ABSENT; a key present but blank resolves to `''` (Laravel parity: `KEY=""`/`KEY=''` also resolve to `''`, not the two-character literal `flutter_dotenv`'s own parser would otherwise leave in place).

| Method | Description |
|:-------|:------------|
| `Env.filled(key, fallback)` | Treats absent, blank, AND quote-only the same way, all resolving to `fallback`. Strips one wrapping quote pair + surrounding whitespace from a present value (an inner apostrophe survives). Use for anything that becomes a URL, a title, or a link. |
| `Env.getOrFail(key)` | Throws `StateError` only when `key` is entirely absent; still returns `''` for a present-but-empty value. |

### AppLifecycle

`AppLifecycle.states()` (`lib/src/support/app_lifecycle.dart`) answers a `Stream<AppLifecycleState>`, for a reader constructed before a `WidgetsBinding` necessarily exists (a service provider's `register()`, for instance, where `WidgetsBinding.instance` throws). Each subscription adds its own observer on `listen` and removes it on `cancel`; nothing before the first `listen` touches the binding. Prefer Flutter's own `AppLifecycleListener` for a widget-lifetime reader.

```dart
final subscription = AppLifecycle.states().listen((state) {
  if (state == AppLifecycleState.paused) Log.info('app paused');
});
```

## Cache System

The Cache system provides a unified key-value caching API with TTL (time-to-live) support. Backed by the `CacheManager` and resolved via the `Cache` facade.

### Cache API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `put(key, value, {ttl})` | `String key`, `dynamic value`, `Duration? ttl` | `Future<void>` | Store an item in the cache with optional expiration. |
| `get(key, {defaultValue})` | `String key`, `dynamic defaultValue` | `dynamic` | Retrieve an item from the cache or return the default value. |
| `has(key)` | `String key` | `bool` | Check if an item exists and is not expired. |
| `forget(key)` | `String key` | `Future<void>` | Remove a specific item from the cache. |
| `flush()` | — | `Future<void>` | Clear all items from the cache. |
| `remember<T>(key, ttl, callback)` | `String key`, `Duration ttl`, `Future<T> Function() callback` | `Future<T>` | Get from cache or execute callback and cache result. |

### Usage

```dart
import 'package:magic/magic.dart';

// Store with TTL
await Cache.put('user:123', user, ttl: Duration(hours: 1));

// Retrieve
final user = await Cache.get('user:123');
final fallback = await Cache.get('missing', defaultValue: {});

// Check existence
if (Cache.has('user:123')) {
  print('Cached!');
}

// Remove
await Cache.forget('user:123');

// Remember pattern (cache-aside)
final cachedUsers = await Cache.remember<List<User>>(
  'users:all',
  Duration(minutes: 30),
  () => fetchUsers(),
);

// Clear all
await Cache.flush();
```

### Drivers
- `MemoryStore`: In-memory, lost on app restart (default for web/testing).
- `FileStore`: Persistent file-based cache (default for mobile).

## Event Dispatcher

A pub/sub system for decoupling business logic from side-effects. Dispatchers publish `MagicEvent` instances; listeners subscribe via factory functions.

### Core Types

- **`MagicEvent`**: Base class for all events. Extend to define custom events.
- **`MagicListener<T>`**: Base class for event handlers. Override `handle(T event)`.
- **`EventDispatcher`**: Singleton that manages registration and dispatch.

### Event API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Event.dispatch(event)` | `MagicEvent event` | `Future<void>` | Dispatch an event to all registered listeners. |
| `Event.listen<T extends MagicEvent>(factory)` | `MagicListener Function() factory` | `void` | Register a listener without adding it to `AppEventServiceProvider.listen`; `T` must be named explicitly. Equivalent to `EventDispatcher.instance.register(T, [factory])`. Call from a provider's `register()`, not `boot()`. |

### EventDispatcher (Direct Access)

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `EventDispatcher.instance.register(eventType, listeners)` | `Type eventType`, `List<MagicListener Function()> listeners` | `void` | Register listener factories for an event type. |
| `EventDispatcher.instance.clear()` | — | `void` | Clear all registered listeners (testing only). |

### Framework Auth Events

`BaseGuard` (and `Auth.fake()`'s fake guard) dispatch `AuthLogin`/`AuthLogout` through `Event`: `AuthLogin` at the end of a successful `startSession` (not on a restore), `AuthLogout` on every `logout()` including a guest's (means "the in-memory session ended", not "the credentials are gone"; gate server-side release on `Auth.hasToken()`). `AuthRestored` fires only on an API-confirmed sync. Full firing conditions: `references/auth-system.md#auth-events`.

### Usage

```dart
import 'package:magic/magic.dart';

// 1. Define an event
class UserRegistered extends MagicEvent {
  final String userId;
  final String email;

  UserRegistered({
    required this.userId,
    required this.email,
  });
}

// 2. Define a listener
class SendWelcomeEmail extends MagicListener<UserRegistered> {
  @override
  Future<void> handle(UserRegistered event) async {
    print('Sending welcome email to ${event.email}');
  }
}

class LogUserSignup extends MagicListener<UserRegistered> {
  @override
  Future<void> handle(UserRegistered event) async {
    Log.info('User registered', {'id': event.userId});
  }
}

// 3. Register in a ServiceProvider
@override
Future<void> boot() async {
  EventDispatcher.instance.register(UserRegistered, [
    () => SendWelcomeEmail(),
    () => LogUserSignup(),
  ]);
}

// 4. Dispatch
await Event.dispatch(UserRegistered(
  userId: '123',
  email: 'user@example.com',
));
```

### Error Handling

If a listener throws an exception, the dispatcher catches it, logs via `Log.error()`, and continues to the next listener. The exception is not re-thrown.

## Logging Manager

Multi-channel logging system following RFC 5424 severity levels. Accessed via the `Log` facade.

### Log API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Log.emergency(message, [context])` | `String message`, `dynamic context` | `void` | Log a system-unusable error. |
| `Log.alert(message, [context])` | `String message`, `dynamic context` | `void` | Log an action-must-be-taken error. |
| `Log.critical(message, [context])` | `String message`, `dynamic context` | `void` | Log a critical error. |
| `Log.error(message, [context])` | `String message`, `dynamic context` | `void` | Log a runtime error. |
| `Log.warning(message, [context])` | `String message`, `dynamic context` | `void` | Log a warning (exceptional but non-error condition). |
| `Log.notice(message, [context])` | `String message`, `dynamic context` | `void` | Log a normal but significant event. |
| `Log.info(message, [context])` | `String message`, `dynamic context` | `void` | Log an informational message. |
| `Log.debug(message, [context])` | `String message`, `dynamic context` | `void` | Log a detailed debug message. |
| `Log.log(level, message, [context])` | `String level`, `String message`, `dynamic context` | `void` | Log at an arbitrary level. |
| `Log.channel(name)` | `String name` | `LoggerDriver` | Get a specific named channel driver. |

### Usage

```dart
import 'package:magic/magic.dart';

Log.info('User logged in', {'user_id': 123, 'ip': '192.168.1.1'});

Log.error(
  'Payment processing failed',
  {'order_id': 'ORD-001', 'error': 'Insufficient funds'},
);

Log.warning('Cache miss for key', {'key': 'user:123'});

Log.debug('Query executed', {'sql': 'SELECT * FROM users'});

// Get a specific channel (e.g., 'slack', 'file')
Log.channel('slack').error('Critical server issue');
```

### Drivers
- **`console`**: Outputs to standard output with configurable log level.
- **`stack`**: Aggregates multiple drivers (e.g., console + file simultaneously).

### Custom Drivers

Register custom log drivers via `LogManager.extend()` — follows the same pattern as `Auth.manager.extend(...)`:

```dart
// In a ServiceProvider boot():
LogManager.extend('sentry', (config) => SentryLoggerDriver(
  minLevel: config['level'] ?? 'warning',
));
```

Custom drivers implement the `LoggerDriver` abstract class. They can be referenced in config by name and included in stack channels.

### Configuration

```dart
// config/logging.dart
'logging': {
  'default': env('LOG_CHANNEL', 'stack'),
  'channels': {
    'stack': {
      'driver': 'stack',
      'channels': ['console', 'sentry'],
    },
    'console': {
      'driver': 'console',
      'level': 'debug',
    },
    'sentry': {
      'driver': 'sentry',
      'level': 'warning',
    },
  },
}
```

## Localization (Translator)

Multi-language translation system with JSON-based message files and runtime locale switching. Accessed via the `Lang` facade or `trans()` helper.

### Lang API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Lang.get(key, [replace])` | `String key`, `Map<String, dynamic>? replace` | `String` | Get a translated string with optional `:placeholder` replacements. Falls back PER KEY to `fallback_locale`, so a key missing from the current catalogue is served from the fallback's rather than rendering as its own dotted path. Answers the key itself only when neither defines it. |
| `Lang.has(key)` | `String key` | `bool` | Check if a translation key exists in the current catalogue OR the fallback's, since both are merged at load. |
| `Lang.setLocale(locale, {reload})` | `Locale locale`, `bool reload` | `Future<void>` | Switch app locale at runtime (reload rebuilds widgets). |
| `Lang.detectLocale()` | — | `Locale` | Detect best-matching locale from device/browser settings. |
| `Lang.detectAndSetLocale()` | — | `Future<Locale>` | Detect and apply the best-matching locale. |
| `Lang.setSupportedLocales(locales)` | `List<Locale> locales` | `void` | Set list of supported locales. |
| `Lang.current` | — | `Locale` | Get the current active locale. |
| `Lang.isLoaded` | — | `bool` | Check if translations are loaded. |
| `Lang.supportedLocales` | — | `List<Locale>` | Get list of supported locales. |
| `Lang.addListener(callback)` | `VoidCallback callback` | `void` | Subscribe to locale changes. |
| `Lang.removeListener(callback)` | `VoidCallback callback` | `void` | Unsubscribe from locale changes. |

### trans() Helper

```dart
String trans(String key, [Map<String, dynamic>? replace]) => Lang.get(key, replace);
String transChoice(String key, int number, [Map<String, dynamic>? replace]) => Lang.choice(key, number, replace);
```

### Pluralization

A sentence carrying a number needs `transChoice`, never `trans`: `trans` is a lookup plus a replacement, so one wording renders at every count.

```json
{ "apples": "There is one apple|There are :count apples" }
```

```dart
transChoice('apples', 1);  // "There is one apple"
transChoice('apples', 4);  // "There are 4 apples"
```

Inline conditions are supported and win over the positional segments: `"{0} Nothing here|[1,19] :count messages|[20,*] Lots"`. Write a line that is all conditions or none, because a stripped condition shifts the positional segments behind it.

**The index is the current locale's, not English's.** Turkish, Japanese, Korean, Chinese and eleven more have one form, so their second segment is unreachable. French counts zero as singular. Russian has three forms and Arabic six. A two-segment line looks correct for as long as only a one-form language is rendered, which is why this defect survives review in an app whose first locale is Turkish.

### Usage

```dart
import 'package:magic/magic.dart';

// JSON file: assets/lang/en/messages.json
// {
//   "welcome": "Hello, :name!",
//   "auth": {
//     "failed": "Invalid credentials"
//   }
// }

// Basic translation
String greeting = Lang.get('welcome', {'name': 'Alice'});
// Output: "Hello, Alice!"

// Nested key access
String error = Lang.get('auth.failed');
// Output: "Invalid credentials"

// Helper shorthand
Text(trans('welcome', {'name': 'Bob'}))

// Runtime locale switching
await Lang.setLocale(Locale('tr'));  // Switch to Turkish
Text(trans('welcome'))  // Uses Turkish translations

// Check translation existence
if (Lang.has('premium_feature')) {
  showPremiumBanner();
}

// Listen for locale changes
Lang.addListener(() {
  print('Locale changed to: ${Lang.current}');
});

// Auto-detect device language
await Lang.detectAndSetLocale();
```

### Hot Restart in Development

In debug mode, `JsonAssetLoader` attempts to bypass `rootBundle` cache so translation JSON changes can be picked up on hot restart. On web, uses `fetch()` with cache-busting; on desktop, reads from disk via `dart:io` (best-effort). On mobile, falls back to `rootBundle`. Release builds use standard `rootBundle` caching.

### JSON Format

Translation files use `:attribute` placeholders:

```json
{
  "greeting": "Welcome, :name!",
  "items": "You have :count items",
  "auth": {
    "login": "Sign in",
    "password_required": "Password is required"
  }
}
```

## Session (Flash Store)

Laravel-style flash data for form repopulation and transient messages. Two internal buckets:

- `_next` — receives `flash()` / `flashErrors()` writes during the current frame.
- `_current` — read by `old()`, `error()`, `hasError()`, `hasFlash`.

`Session.tick()` promotes `_next` → `_current`. The framework does **not** tick automatically — wire a routerDelegate listener gated on real `MagicRouter.instance.currentLocation` changes during bootstrap (GoRouter fires `routerDelegate` notifications for non-navigation rebuilds too, which would prematurely burn the flash). Each value then survives exactly one navigation hop.

```dart
// Call once during app bootstrap (e.g. in a ServiceProvider.boot()):
var lastLocation = MagicRouter.instance.currentLocation;
MagicRouter.instance.router.routerDelegate.addListener(() {
  final current = MagicRouter.instance.currentLocation;
  if (current != lastLocation) {
    Session.tick();
    lastLocation = current;
  }
});
```

### API

| Method | Returns | Purpose |
|--------|---------|---------|
| `Session.flash(Map<String, dynamic> input)` | `void` | Flash inputs for next hop (merged, not replaced) |
| `Session.flashErrors(Map<String, List<String>> errors)` | `void` | Flash per-field validation errors (merged) |
| `Session.old(String field, [String? fallback])` | `String?` | Current-bucket input as string. Fallback returns only if the key was never flashed; explicit null flash returns `null` |
| `Session.oldRaw(String field)` | `dynamic` | Current-bucket raw, non-stringified value |
| `Session.error(String field)` | `String?` | First current-bucket error for field |
| `Session.errors(String field)` | `List<String>` | All current-bucket errors for field |
| `Session.hasError(String field)` | `bool` | True if field has at least one current-bucket error |
| `Session.hasFlash` | `bool` | **Getter.** Any readable flash data this frame |
| `Session.tick()` | `void` | Promote next → current. Not auto-wired — attach at bootstrap (snippet above) |
| `Session.reset()` | `void` | Clear both buckets (testing) |
| `Session.setStore(SessionStore store)` | `void` | Swap backing store (testing) |

Top-level helpers (mirror Laravel's Blade API):

```dart
String? old(String field, [String? fallback]);
String? error(String field);
```

### Auto-flash on validation failure

`MagicFormData.validate()` calls `Session.flash(form.data)` automatically when client-side validation fails. Per-field validation errors are **not** auto-flashed — call `Session.flashErrors(...)` manually (e.g. from a server response) if you need `error('field')` to resolve after navigation. Typical flow:

```dart
// Submit view:
void _submit() {
  if (!form.validate()) return;  // on failure: data + errors are flashed
  form.process(() => controller.save(form.data));
}

// Next view (re-entered via MagicRoute.back or similar) repopulates:
class UserFormView extends MagicStatefulView<UserController> { ... }
class _UserFormViewState extends MagicStatefulViewState<UserController, UserFormView> {
  late final form = MagicFormData({
    'email': old('email') ?? '',
    'name': old('name') ?? '',
  }, controller: controller);

  @override Widget build(BuildContext context) => Column(children: [
    TextField(
      controller: form['email'],
      decoration: InputDecoration(errorText: error('email')),
    ),
  ]);
}
```

### Manual flash from a controller

```dart
Future<void> store(Map<String, dynamic> data) async {
  final response = await Http.post('/users', data: data);
  if (!response.successful) {
    Session.flash(data);
    Session.flashErrors(response.errors);
    MagicRoute.back();
    return;
  }
  // ...
}
```

### Testing

```dart
setUp(() {
  MagicApp.reset();
  Magic.flush();
  Session.reset();              // clear both buckets
});

test('flash survives one tick', () {
  Session.flash({'email': 'foo@bar.com'});
  Session.tick();
  expect(Session.old('email'), 'foo@bar.com');
  Session.tick();                // second tick — current bucket now empty
  expect(Session.old('email'), isNull);
});
```

## Storage Manager

File system abstraction for local disk operations. Supports multiple disks (local, public) and handles platform differences (mobile vs. web). Accessed via the `Storage` facade.

### Storage API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Storage.put(path, contents, {mimeType})` | `String path`, `dynamic contents`, `String? mimeType` | `Future<String>` | Store file contents (bytes, string, or MagicFile). |
| `Storage.get(path)` | `String path` | `Future<Uint8List?>` | Retrieve file as bytes or null if not found. |
| `Storage.getFile(path)` | `String path` | `Future<MagicFile?>` | Retrieve file as MagicFile with metadata. |
| `Storage.exists(path)` | `String path` | `Future<bool>` | Check if file exists. |
| `Storage.delete(path)` | `String path` | `Future<bool>` | Delete a file. |
| `Storage.url(path)` | `String path` | `Future<String>` | Get a displayable URL (file:// on mobile, blob: on web). |
| `Storage.download(path, {name})` | `String path`, `String? name` | `Future<void>` | Trigger download (share sheet on mobile, browser dialog on web). |
| `Storage.disk([name])` | `String? name` | `StorageDisk` | Get a specific disk instance. |

### Usage

```dart
import 'package:magic/magic.dart';

// Store bytes
final imageBytes = await imageFile.readAsBytes();
await Storage.put('avatars/user-123.jpg', imageBytes, mimeType: 'image/jpeg');

// Store a MagicFile (from Pick)
final picked = await Pick.image();
if (picked != null) {
  await Storage.put('gallery/photo.jpg', picked);
}

// Retrieve as bytes
final bytes = await Storage.get('avatars/user-123.jpg');

// Retrieve as MagicFile
final file = await Storage.getFile('avatars/user-123.jpg');
if (file != null) {
  print('Name: ${file.name}');
  print('Is image: ${file.isImage}');
  final data = await file.readAsBytes();
}

// Check existence
if (await Storage.exists('avatars/user-123.jpg')) {
  print('Avatar already uploaded');
}

// Get displayable URL
final url = await Storage.url('avatars/user-123.jpg');
Image.network(url);  // Works on all platforms

// Delete
await Storage.delete('avatars/user-123.jpg');

// Download
await Storage.download('reports/monthly.pdf', name: 'report-march.pdf');

// Use a specific disk
await Storage.disk('public').put('uploads/file.pdf', bytes);
```

### Platform Behavior

| Method | Mobile/Desktop | Web |
|--------|----------------|-----|
| `put()` | Writes to file system | Stores in SharedPreferences (Base64) |
| `url()` | Returns `file://` path | Returns `blob:` URL |
| `download()` | Opens share sheet | Triggers browser download |

## Encryption (Crypt Facade)

AES-256-CBC encryption for sensitive data. Two modes: config-based (using app key) and device-based (using Vault-stored key).

> **Warning**: `EncryptionServiceProvider` is NOT auto-registered. Add it manually to `config/app.dart`.

### Crypt API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Crypt.encrypt(value)` | `String value` | `String` | Encrypt using app key (config-based). |
| `Crypt.decrypt(payload)` | `String payload` | `String` | Decrypt using app key (throws on error). |
| `Crypt.encryptWithDeviceKey(value)` | `String value` | `Future<String>` | Encrypt using device-specific key. |
| `Crypt.decryptWithDeviceKey(payload)` | `String payload` | `Future<String>` | Decrypt using device-specific key. |
| `Crypt.hasDeviceKey()` | — | `Future<bool>` | Check if device key exists. |
| `Crypt.generateDeviceKey()` | — | `Future<void>` | Generate a new device key (invalidates old data). |
| `Crypt.clearDeviceKey()` | — | `Future<void>` | Delete device key (data becomes unrecoverable). |

### Usage

```dart
import 'package:magic/magic.dart';

// Config-based encryption (uses APP_KEY)
final encrypted = Crypt.encrypt('my-secret-value');
final decrypted = Crypt.decrypt(encrypted);

// Device-based encryption (unique per device, stored in Vault)
final deviceEncrypted = await Crypt.encryptWithDeviceKey('sensitive-data');
final deviceDecrypted = await Crypt.decryptWithDeviceKey(deviceEncrypted);

// Device key lifecycle
if (!await Crypt.hasDeviceKey()) {
  await Crypt.generateDeviceKey();
}

// Cleanup
await Crypt.clearDeviceKey();
```

### Requirements

- `APP_KEY` in `.env` must be exactly 32 characters.
- Device key is auto-generated on first use.
- Errors throw `MagicDecryptException`.

## Vault (Security Storage)

Hardware-backed secure storage for sensitive tokens, passwords, and keys. Uses `flutter_secure_storage` under the hood.

### Vault API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Vault.put(key, value)` | `String key`, `String value` | `Future<void>` | Store a string securely. |
| `Vault.get(key)` | `String key` | `Future<String?>` | Retrieve a string or null if not found. |
| `Vault.delete(key)` | `String key` | `Future<void>` | Delete a key. |
| `Vault.flush()` | — | `Future<void>` | Clear all stored data (WARNING: irreversible). |

### Usage

```dart
import 'package:magic/magic.dart';

// Store authentication token securely
final token = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
await Vault.put('auth:token', token);

// Retrieve
final storedToken = await Vault.get('auth:token');

// Check before use
if (storedToken != null) {
  // Use token
}

// Delete on logout
await Vault.delete('auth:token');

// Wipe all sensitive data
await Vault.flush();
```

### Platform Notes

- **iOS**: Uses Keychain.
- **Android**: Uses EncryptedSharedPreferences.
- **Web**: Falls back to SharedPreferences (not hardware-backed).

## Carbon (Date Manipulation)

Laravel-style fluent date wrapper around Jiffy for parsing, formatting, and manipulating dates.

### Carbon API

#### Constructors

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Carbon.now([timezone])` | `String? timezone` | `Carbon` | Current date/time (optionally in specific timezone). |
| `Carbon.parse(dateString)` | `String dateString` | `Carbon` | Parse a date string (flexible formats). |
| `Carbon.fromDateTime(dateTime)` | `DateTime dateTime` | `Carbon` | Wrap a DateTime. |
| `Carbon.create({...})` | Year, month, day, hour, minute, second, millisecond | `Carbon` | Create from parts. |

#### Testing

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Carbon.setTestNow([testNow])` | `Carbon? testNow` | `void` | Freeze the clock to `testNow`; no argument (or `null`) clears the freeze. Covers `now()`, `isToday/isYesterday/isTomorrow`, `isFuture/isPast`, and argument-less `diffForHumans()`. Static: clear it in `tearDown`. |
| `Carbon.hasTestNow()` | none | `bool` | Whether the clock is currently frozen. |

#### Getters

| Property | Type | Description |
|:---------|:-----|:------------|
| `year` | `int` | Year value. |
| `month` | `int` | Month (1-12). |
| `day` | `int` | Day of month. |
| `hour` | `int` | Hour (0-23). |
| `minute` | `int` | Minute (0-59). |
| `second` | `int` | Second (0-59). |
| `dayOfWeek` | `int` | Day of week (1=Monday, 7=Sunday). |
| `dayOfYear` | `int` | Day of year (1-366). |
| `weekOfYear` | `int` | Week number in year. |
| `daysInMonth` | `int` | Days in current month. |
| `quarter` | `int` | Quarter (1-4). |
| `toDateTime` | `DateTime` | Underlying DateTime. |

#### Manipulation (All return new Carbon instance)

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `add(duration)` | `Duration duration` | `Carbon` | Add a duration. |
| `subtract(duration)` | `Duration duration` | `Carbon` | Subtract a duration. |
| `addDays(count)` | `int count` | `Carbon` | Add N days. |
| `addWeeks(count)` | `int count` | `Carbon` | Add N weeks. |
| `addMonths(count)` | `int count` | `Carbon` | Add N months. |
| `addYears(count)` | `int count` | `Carbon` | Add N years. |
| `addHours(count)` | `int count` | `Carbon` | Add N hours. |
| `addMinutes(count)` | `int count` | `Carbon` | Add N minutes. |
| `addSeconds(count)` | `int count` | `Carbon` | Add N seconds. |
| `subDays(count)` | `int count` | `Carbon` | Subtract N days. |
| `subWeeks(count)` | `int count` | `Carbon` | Subtract N weeks. |
| `subMonths(count)` | `int count` | `Carbon` | Subtract N months. |
| `subYears(count)` | `int count` | `Carbon` | Subtract N years. |
| `subHours(count)` | `int count` | `Carbon` | Subtract N hours. |
| `subMinutes(count)` | `int count` | `Carbon` | Subtract N minutes. |
| `subSeconds(count)` | `int count` | `Carbon` | Subtract N seconds. |

#### Boundaries

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `startOfDay()` | `Carbon` | 00:00:00 of this day. |
| `endOfDay()` | `Carbon` | 23:59:59.999 of this day. |
| `startOfWeek()` | `Carbon` | Start of week (Monday). |
| `endOfWeek()` | `Carbon` | End of week (Sunday). |
| `startOfMonth()` | `Carbon` | First day of month at 00:00:00. |
| `endOfMonth()` | `Carbon` | Last day of month at 23:59:59. |
| `startOfYear()` | `Carbon` | January 1 at 00:00:00. |
| `endOfYear()` | `Carbon` | December 31 at 23:59:59. |
| `setTimezone(timezone)` | `Carbon` | Convert to different timezone. |

#### Formatting

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `format(pattern)` | `String pattern` | `String` | Format using intl patterns (e.g., 'yyyy-MM-dd HH:mm:ss'). |
| `toIso8601String()` | — | `String` | ISO 8601 format. |
| `toDateString()` | — | `String` | yyyy-MM-dd. |
| `toTimeString()` | — | `String` | HH:mm:ss. |
| `toDateTimeString()` | — | `String` | yyyy-MM-dd HH:mm:ss. |
| `diffForHumans([other])` | `Carbon? other` | `String` | Human-readable diff (e.g., "2 hours ago"). |
| `shortDiffForHumans([other])` | `Carbon? other` | `String` | Compact ladder for dense tables/list rows: seconds through years (`'14m ago'`, `'1mo ago'` for a truncated 30-day month, `'5m from now'`, `'Just now'` under 1s). Each unit and wrapper resolves through `Lang` (`time.units_short.*`, `time.ago`, `time.from_now`, `time.just_now`) with an English literal fallback. |

#### Comparison & Checking

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `isAfter(other)` | `Carbon other` | `bool` | Check if after another date. |
| `isBefore(other)` | `Carbon other` | `bool` | Check if before another date. |
| `isSame(other, [unit])` | `Carbon other`, `Unit unit` | `bool` | Check if same day/month/year. |
| `isBetween(start, end, [unit])` | `Carbon start`, `Carbon end`, `Unit unit` | `bool` | Check if between two dates. |
| `isToday()` | — | `bool` | Check if this is today. |
| `isYesterday()` | — | `bool` | Check if this is yesterday. |
| `isTomorrow()` | — | `bool` | Check if this is tomorrow. |
| `isFuture()` | — | `bool` | Check if in the future. |
| `isPast()` | — | `bool` | Check if in the past. |
| `isWeekend()` | — | `bool` | Saturday or Sunday. |
| `isWeekday()` | — | `bool` | Monday through Friday. |
| `isLeapYear()` | — | `bool` | Check if leap year. |

#### Diff

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `diffInDays(other)` | `Carbon other` | `int` | Days between dates. |
| `diffInHours(other)` | `Carbon other` | `int` | Hours between dates. |
| `diffInMinutes(other)` | `Carbon other` | `int` | Minutes between dates. |
| `diffInSeconds(other)` | `Carbon other` | `int` | Seconds between dates. |
| `diffInMonths(other)` | `Carbon other` | `int` | Months between dates. |
| `diffInYears(other)` | `Carbon other` | `int` | Years between dates. |

### Usage

```dart
import 'package:magic/magic.dart';

// Create instances
final now = Carbon.now();
final parsed = Carbon.parse('2024-03-15');
final specific = Carbon.create(year: 2024, month: 3, day: 15, hour: 14, minute: 30);

// Manipulation (all return new instances)
final tomorrow = now.addDay();
final nextWeek = now.addWeeks(1);
final lastMonth = now.subMonths(1);

// Boundaries
final endOfMonth = now.endOfMonth();
final startOfYear = now.startOfYear();

// Formatting
print(now.format('MMMM dd, yyyy'));     // "March 24, 2024"
print(now.toDateTimeString());          // "2024-03-24 14:30:00"
print(now.diffForHumans());             // "just now"

// Comparison
if (parsed.isBefore(now)) {
  print('Event is in the past');
}

if (now.isToday()) {
  print('Today is the day!');
}

// Diff
final days = now.diffInDays(parsed);
print('Days between: $days');

// Timezone handling
final ny = now.setTimezone('America/New_York');
final tokyo = now.setTimezone('Asia/Tokyo');
```

## Launch (URL Launcher)

Context-free facade for opening URLs, emails, phone calls, and SMS. Built on `url_launcher`.

> **Warning**: `LaunchServiceProvider` is NOT auto-registered. Add `(app) => LaunchServiceProvider(app)` to `config/app.dart`.

### Launch API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Launch.url(url, {mode})` | `String url`, `LaunchMode? mode` | `Future<bool>` | Open URL in external app or in-app browser. |
| `Launch.email(address, {subject, body})` | `String address`, `String? subject`, `String? body` | `Future<bool>` | Open email client pre-filled. |
| `Launch.phone(number)` | `String number` | `Future<bool>` | Open phone dialer. |
| `Launch.sms(number, {body})` | `String number`, `String? body` | `Future<bool>` | Open SMS app pre-filled. |
| `Launch.canLaunch(url)` | `String url` | `Future<bool>` | Check if device can handle URL scheme. |

### Usage

```dart
import 'package:magic/magic.dart';

// Open a URL
await Launch.url('https://flutter.dev');

// Open in in-app browser
await Launch.url(
  'https://flutter.dev',
  mode: LaunchMode.inAppWebView,
);

// Send email with pre-filled fields
await Launch.email(
  'support@example.com',
  subject: 'Bug Report',
  body: 'I found an issue with...',
);

// Call
await Launch.phone('+1-800-555-0123');

// Send SMS
await Launch.sms('+1-800-555-0123', body: 'On my way!');

// Check before launching
if (await Launch.canLaunch('tel:+1-800-555-0123')) {
  await Launch.phone('+1-800-555-0123');
}
```

### Error Handling

All methods return `false` on failure and log via `Log`. They never throw exceptions. Empty strings return `false` immediately.

### URL Schemes

For `canLaunch()` to work on iOS 9+ and Android 11+, declare schemes in native manifest:

**iOS (Info.plist)**:
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>tel</string>
  <string>sms</string>
  <string>mailto</string>
</array>
```

**Android (AndroidManifest.xml)**:
```xml
<queries>
  <intent>
    <action android:name="android.intent.action.DIAL" />
  </intent>
  <intent>
    <action android:name="android.intent.action.SENDTO" />
  </intent>
</queries>
```

## Pick (File & Image Selection)

File and media picker facade integrating `image_picker` and `file_picker`.

### Pick API

#### Image Picking

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Pick.image({maxWidth, maxHeight, imageQuality})` | Sizing/quality options | `Future<MagicFile?>` | Pick single image from gallery. |
| `Pick.images({maxWidth, maxHeight, imageQuality})` | Sizing/quality options | `Future<List<MagicFile>>` | Pick multiple images from gallery. |
| `Pick.camera({preferredCamera, maxWidth, maxHeight, imageQuality, fallbackToGallery, onError})` | Camera & fallback options | `Future<MagicFile?>` | Capture photo from camera (with optional gallery fallback). |
| `Pick.media({maxWidth, maxHeight, imageQuality})` | Sizing/quality options | `Future<MagicFile?>` | Pick image or video from gallery. |

#### Video Picking

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Pick.video({maxDuration})` | `Duration? maxDuration` | `Future<MagicFile?>` | Pick video from gallery. |
| `Pick.recordVideo({preferredCamera, maxDuration, fallbackToGallery, onError})` | Camera & fallback options | `Future<MagicFile?>` | Record video from camera. |

#### File Picking

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Pick.file({extensions})` | `List<String>? extensions` | `Future<MagicFile?>` | Pick single file with optional extension filter. |
| `Pick.files({extensions})` | `List<String>? extensions` | `Future<List<MagicFile>>` | Pick multiple files; empty list if cancelled. |
| `Pick.directory()` | — | `Future<String?>` | Pick a directory path. |
| `Pick.saveFile({fileName, bytes, mimeType, dialogTitle})` | `fileName` and `bytes` required | `Future<Uri?>` | Open save dialog; returns the written uri (`file`, `content` or `blob` scheme). |

### Usage

```dart
import 'package:magic/magic.dart';

// Pick single image
final image = await Pick.image(imageQuality: 80);
if (image != null) {
  print('Picked: ${image.name}');
  await Storage.put('avatars/user.jpg', image);
}

// Pick multiple images
final gallery = await Pick.images();
for (final img in gallery) {
  await img.store('gallery');
}

// Capture from camera with fallback to gallery
final photo = await Pick.camera(
  fallbackToGallery: true,
  onError: (e) => print('Camera error: $e'),
);

// Pick video
final video = await Pick.video(maxDuration: Duration(seconds: 30));
if (video != null) {
  await video.store('videos');
}

// Record video
final recording = await Pick.recordVideo(
  maxDuration: Duration(minutes: 2),
  fallbackToGallery: true,
);

// Pick PDF file
final pdf = await Pick.file(extensions: ['pdf']);
if (pdf != null) {
  await Storage.put('documents/${pdf.name}', pdf);
}

// Pick multiple documents
final docs = await Pick.files(extensions: ['pdf', 'doc', 'docx']);
for (final doc in docs) {
  await doc.store('uploads');
}

// Pick directory
final dirPath = await Pick.directory();

// Save dialog. Returns a Uri, not a path: Android SAF gives content://,
// the web gives blob:.
final Uri? savedTo = await Pick.saveFile(
  fileName: 'export.csv',
  bytes: csvBytes,
);
```

### MagicFile Methods

Files returned by `Pick` are `MagicFile` instances with:

```dart
// Properties
file.name;           // File name
file.path;           // File path
file.size;           // File size in bytes
file.mimeType;       // MIME type
file.isImage;        // true if image
file.isVideo;        // true if video
file.isPdf;          // true if PDF
file.extension;      // File extension

// Methods
await file.readAsBytes();     // Read file bytes
await file.store(path);       // Store to Storage
await file.storeAs(diskName); // Store with disk selection
```

### Platform Support

| Method | Android | iOS | Web | Desktop |
|:-------|:--------|:----|:----|:--------|
| `image()` | ✅ | ✅ | ✅ | ✅ |
| `images()` | ✅ | ✅ | ✅ | ✅ |
| `camera()` | ✅ | ✅ | ✅ | ⚠️ |
| `video()` | ✅ | ✅ | ✅ | ✅ |
| `file()` | ✅ | ✅ | ✅ | ✅ |
| `files()` | ✅ | ✅ | ✅ | ✅ |
| `directory()` | ✅ | ✅ | ❌ | ✅ |
| `recordVideo()` | ✅ | ✅ | ✅ | ⚠️ |

⚠️ Desktop camera requires custom delegate setup.

## Broadcasting

Laravel Echo-equivalent real-time channel system over WebSockets. Accessed via the `Echo` facade backed by `BroadcastManager`.

> **Important**: `BroadcastServiceProvider` is NOT auto-registered. Add it explicitly to the `providers` list in config.

### Echo Facade API

| Method / Property | Returns | Description |
|:------------------|:--------|:------------|
| `Echo.channel(name)` | `BroadcastChannel` | Subscribe to a public channel |
| `Echo.private(name)` | `BroadcastChannel` | Subscribe to a private channel (auth handshake required) |
| `Echo.join(name)` | `BroadcastPresenceChannel` | Join a presence channel (auth + member tracking) |
| `Echo.listen(channel, event, callback)` | `BroadcastChannel` | Shorthand: subscribe + listen in one call |
| `Echo.leave(name)` | `void` | Unsubscribe from a channel |
| `Echo.connect()` | `Future<void>` | Establish the WebSocket connection; idempotent, never opens a second socket |
| `Echo.disconnect()` | `Future<void>` | Close the connection |
| `Echo.connection` | `BroadcastDriver` | The resolved default driver instance |
| `Echo.socketId` | `String?` | Server-assigned socket ID, or `null` when disconnected |
| `Echo.connectionState` | `Stream<BroadcastConnectionState>` | Stream of connection lifecycle state changes |
| `Echo.onReconnect` | `Stream<void>` | Emits once each time the driver reconnects |
| `Echo.addInterceptor(interceptor)` | `void` | Register a `BroadcastInterceptor` on the connection |
| `Echo.manager` | `BroadcastManager` | The underlying manager (for `extend()` and advanced use) |
| `Echo.fake()` | `FakeBroadcastManager` | Swap to in-memory fake for testing |
| `Echo.unfake()` | `void` | Restore the real manager binding |

### Channel Types

- **Public** (`Echo.channel('name')`): No auth. Any connected client may subscribe.
- **Private** (`Echo.private('name')`): Driver adds `private-` prefix, performs HTTP auth via `auth_endpoint`.
- **Presence** (`Echo.join('name')`): Driver adds `presence-` prefix, auth + member list tracking. Returns `BroadcastPresenceChannel` with `members`, `onJoin`, `onLeave`.

### BroadcastChannel API

| Method | Returns | Description |
|:-------|:--------|:------------|
| `channel.listen(event, callback)` | `BroadcastChannel` | Register a listener for an event name (chainable) |
| `channel.stopListening(event)` | `void` | Remove a listener |
| `channel.events` | `Stream<BroadcastEvent>` | Raw stream of all events on this channel |
| `channel.name` | `String` | Fully-qualified channel name |

### BroadcastEvent Fields

| Property | Type | Description |
|:---------|:-----|:------------|
| `event` | `String` | Event name (e.g. `'App\\Events\\OrderShipped'`) |
| `channel` | `String` | Channel name the event arrived on |
| `data` | `Map<String, dynamic>` | Decoded JSON payload |
| `receivedAt` | `DateTime` | Local timestamp of receipt |

### BroadcastConnectionState

Values: `connecting`, `connected`, `disconnected`, `reconnecting`.

### BroadcastManager

| Method | Description |
|:-------|:------------|
| `BroadcastManager.extend(name, factory)` | Register a custom driver factory `(Map<String,dynamic>) => BroadcastDriver` |
| `BroadcastManager.resetDrivers()` | Clear all custom driver registrations (testing) |
| `manager.connection([name])` | Resolve named or default driver (result cached for default) |

### BroadcastInterceptor Contract

All methods have pass-through default implementations; override only what you need:

```dart
abstract class BroadcastInterceptor {
  Map<String, dynamic> onSend(Map<String, dynamic> message) => message;
  BroadcastEvent onReceive(BroadcastEvent event) => event;
  dynamic onError(dynamic error) => error;
}
```

Register interceptors via `Echo.addInterceptor(interceptor)` or `driver.addInterceptor(interceptor)`.

### ReverbBroadcastDriver (Pusher Protocol)

Handles the full Pusher protocol over WebSocket: connection handshake, ping/pong keepalive, public/private/presence subscriptions, event deduplication via ring buffer, automatic reconnection with exponential backoff + 30% random jitter, client-side activity monitoring, and configurable connection establishment timeout.

Config keys under `broadcasting.connections.reverb`:

| Key | Default | Description |
|:----|:--------|:------------|
| `host` | `'localhost'` | WebSocket server host |
| `port` | `8080` | WebSocket server port |
| `scheme` | `'ws'` | `ws` or `wss` |
| `app_key` | `''` | Reverb/Pusher application key |
| `auth_endpoint` | `'/broadcasting/auth'` | HTTP endpoint for private/presence auth |
| `reconnect` | `true` | Auto-reconnect on disconnect |
| `max_reconnect_delay` | `30000` | Max backoff delay in ms |
| `activity_timeout` | `120` | Seconds of inactivity before ping is sent |
| `connection_timeout` | `15` | Seconds to wait for connection establishment |
| `dedup_buffer_size` | `100` | Ring buffer size for deduplication |

Constructor DI parameters for testing:
- `channelFactory` — overrides WebSocket creation (inject mock channels)
- `authFactory` — overrides the HTTP auth call for private/presence channels (inject mock auth responses)
- `pongTimeout` — override the 30-second pong deadline (use short durations in tests)
- `random` — inject a seeded `Random` for deterministic backoff jitter in tests

**Connection health**: Activity monitor detects silent connection loss using the Pusher protocol `activity_timeout` (provided by server in handshake; falls back to `activity_timeout` config key, default 120s). After `activity_timeout` seconds of inactivity → sends `pusher:ping`. If no `pusher:pong` within `pongTimeout` (30s default) → closes socket, triggers reconnect. Timer resets on ANY inbound message.

**Reconnection backoff**: Exponential backoff with 30% random jitter — `base = 500ms × 2^attempt` (capped at `max_reconnect_delay`), `delay = base + random(0..base×0.3)`. Jitter prevents thundering herd when many clients reconnect simultaneously.

**Connection timeout**: Configurable via `connection_timeout` (default 15s). If the server doesn't complete the Pusher handshake within this window → closes socket, schedules reconnect, throws `TimeoutException`.

Auth failures in `_authenticateAndSubscribe()` are logged via `Log.error()` and routed through the interceptor `onError()` chain. On reconnect, all channels are re-subscribed with `await` — `onReconnect` emits only after completion. Per-channel error handling ensures partial failures don't block other channels.

### NullBroadcastDriver

Silently drops all broadcast operations. Used for local development or when `broadcasting.default` is `'null'`. `BroadcastServiceProvider` skips `connect()` when the default connection is `null`.

### AuthChannelSubscription

Reconciles a single private channel subscription against a caller-supplied, re-read-on-every-call channel name: the seam behind a channel whose name depends on auth state (a team id, a user id).

```dart
late final subscription = AuthChannelSubscription(
  channelName: () {
    final teamId = Auth.user<User>()?.teamId;
    return teamId == null ? null : 'teams.$teamId';
  },
  listeners: {'incident.opened': (event) => refetchIncidents()},
  onReconnect: refetchIncidents,
);

Auth.stateNotifier.addListener(subscription.sync);
subscription.sync(); // reconcile once at startup too
```

`sync()` is serialised (a call arriving mid-flight defers and re-runs once more) and a no-op when `channelName()` still answers the subscribed name, whatever the connection is doing (the Reverb driver recovers a drop on its own). A name change leaves the old channel by its prefixed name, calls `Echo.connect()` when the connection is not live, then subscribes and wires every `listeners` entry. That connect is safe mid-reconnect: `ReverbBroadcastDriver.connect()` is idempotent (returns when connected, joins an attempt in flight, supersedes an armed retry), so it never opens a second socket. `onReconnect` fires on both an `Echo.onReconnect` signal and a `connectionState` transition to `connected`. `dispose()` cancels only the reconnect-listening subscriptions, not the channel or connection. A `null` channel name disconnects the whole default connection, dropping any other channel the app subscribed elsewhere through `Echo`: deliberate, a signed-out app has no business staying on the socket. Full reference: `doc/digging-deeper/broadcasting.md#auth-scoped-subscriptions`.

### FakeBroadcastManager (Testing)

```dart
final fake = Echo.fake();

// Trigger some code that uses Echo...
Echo.channel('orders');
Echo.private('user.1');

// Assert
fake.assertConnected();
fake.assertSubscribed('orders');
fake.assertSubscribed('private-user.1');
fake.assertNotSubscribed('presence-room.1');
fake.assertInterceptorAdded();

// Inspect driver directly
expect(fake.driver.subscribedChannels, hasLength(2));

// Reset between test cases
fake.reset();
```

### Usage Examples

```dart
import 'package:magic/magic.dart';

// Public channel
Echo.channel('orders').listen('OrderShipped', (event) {
  print('Order ${event.data['id']} shipped');
});

// Private channel (auth required)
Echo.private('user.${userId}').listen('ProfileUpdated', (event) {
  print('Profile updated: ${event.data}');
});

// Presence channel
final room = Echo.join('room.1');
room.onJoin.listen((member) => print('${member['name']} joined'));
room.onLeave.listen((member) => print('${member['name']} left'));
room.listen('MessagePosted', (event) => print(event.data['body']));

// React to connection state
Echo.connectionState.listen((state) {
  if (state == BroadcastConnectionState.reconnecting) {
    showReconnectingBanner();
  }
});

// Re-subscribe after reconnect
Echo.onReconnect.listen((_) {
  Echo.channel('orders').listen('OrderShipped', onShipped);
});

// Custom driver
BroadcastManager.extend('pusher', (config) => PusherBroadcastDriver(config));
```

## Sync

`SyncFeed` (`lib/src/sync/sync_feed.dart`) runs a push-then-pull skeleton over one REST resource: push everything written locally since this device's own mark (`POST '$resource/sync'`, batched at `batchSize`, default 500), then pull every page past the server's own cursor (`GET resource`, up to `maxPages`, default 100), never throwing (an exception becomes `SyncReport.failure`, logged via `Log.error`).

A subclass supplies `feed` (the ledger key), `resource`/`envelopeKey` (the wire endpoint), `pending({account, sinceMillis, scope})` (rows to push, oldest first), and `adoptRow({account, row})` (write one pulled row, answering whether it was newer). Use `Cast.intOrNull`/`doubleOrNull`/`boolOrNull` inside `adoptRow` for a numeric/boolean field whose wire type is not guaranteed (web's `int`/`double` share one float).

```dart
class ItemsSyncFeed extends SyncFeed {
  @override String get feed => 'items';
  @override String get resource => 'items';
  @override String get envelopeKey => 'items';

  @override
  Future<List<SyncPushRow>> pending({required String account, required int sinceMillis, required String scope}) async {
    // return locally-written rows newer than sinceMillis, oldest first
  }

  @override
  Future<bool> adoptRow({required String account, required Map<String, dynamic> row}) async {
    // write the row locally, return true when it was newer than what was held
  }
}

final SyncReport report = await ItemsSyncFeed().run(scope: 'team-42', account: userId);
```

**Two clocks, only one advances locally.** The push mark is this device's own `updated_at` epoch millis; the pull cursor is the server's opaque text, read and rewritten unread. A row adopted from a pull carries the originating device's clock, so the push mark never advances to it; the row is simply re-sent once and rejected by the server's own `>=` check.

`SyncLedger` (`lib/src/sync/sync_ledger.dart`) is the bookmark store behind `SyncFeed.run`: `read`/`write` over a `(scope, feed)` pair, upserted by delete-then-insert inside a `SAVEPOINT`/`RELEASE` (not `DB.transaction`, since `BEGIN` does not nest and a feed may already run inside a caller's own transaction; a savepoint does). `CreateSyncCursorsTable` (`lib/src/sync/create_sync_cursors_table.dart`) creates the `sync_cursors` table it reads; magic has no migration discovery, so list it in the app's own `Migrator().run([...])` call. Scope derivation, salt, and run scheduling stay app-side. Full reference: `doc/digging-deeper/sync.md`.

## Key Gotchas

- **Cache**: `remember<T>()` returns cached value directly (not awaited) if it exists; only awaits callback on miss.
- **Events**: Listeners run sequentially. If one throws, others still execute. Errors are logged, not re-thrown.
- **Logging**: `Log.channel(name)` returns a `LoggerDriver` resolved via `LogManager.driver(name)`, enabling per-channel logging.
- **Lang**: `trans()` is a shorthand for `Lang.get()` and `transChoice()` for `Lang.choice()`. Translations must be loaded before first use. A sentence with a number needs `transChoice`; the plural index is the current locale's, and fifteen languages have only one form.
- **Storage**: `put()` returns the path, `get()` returns raw bytes. Use `getFile()` for metadata.
- **Crypt**: App key must be exactly 32 characters. Device keys are auto-generated on first `encryptWithDeviceKey()` call.
- **Vault**: Async operations. May fail if hardware keystore is locked (e.g., on first boot before PIN unlock).
- **Carbon**: All manipulation methods return NEW instances; original is immutable.
- **Launch**: Never throws; always returns bool. Register `LaunchServiceProvider` manually.
- **Pick**: Returns `MagicFile` instances which wrap `image_picker` and `file_picker` results. Camera fallback requires explicit opt-in.
