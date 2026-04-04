# Magic Framework: Facades API Reference

All facades are available after `await Magic.init()` completes. Import: `package:magic/magic.dart`.

---

## Auth

Proxies calls to the default guard via the `AuthManager` singleton.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Auth.login(Map<String, dynamic> data, Authenticatable user)` | `Future<void>` | Store credentials and set the authenticated user. |
| `Auth.logout()` | `Future<void>` | Clear stored credentials and user from memory. |
| `Auth.check()` | `bool` | True if user is authenticated. |
| `Auth.guest` | `bool` | **Getter.** True if user is NOT authenticated. |
| `Auth.user<T extends Model>()` | `T?` | Get the current user; null if unauthenticated. |
| `Auth.id()` | `dynamic` | Primary key of the authenticated user. |
| `Auth.restore()` | `Future<void>` | Restore session from secure storage on app boot. |
| `Auth.hasToken()` | `Future<bool>` | Check if a stored token exists. |
| `Auth.getToken()` | `Future<String?>` | Read the stored token. |
| `Auth.refreshToken()` | `Future<bool>` | Manually refresh the token; returns success flag. |
| `Auth.registerModel<T>(Authenticatable Function(Map<String, dynamic>) factory)` | `void` | Alias for `manager.setUserFactory()`. |
| `Auth.guard([String? name])` | `Guard` | Access a named guard; defaults to default guard. |
| `Auth.manager` | `AuthManager` | Underlying manager for advanced configuration. |
| `Auth.manager.setUserFactory(Authenticatable Function(Map<String, dynamic>) f)` | `void` | **Required** in `ServiceProvider.boot()` — auth won't work without it. |
| `Auth.manager.extend(String name, Guard Function(Map) f)` | `void` | Register a custom authentication guard. |
| `Auth.stateNotifier` | `ValueNotifier<int>` | **Getter.** Bumps on every login/logout/restore — use in layout widgets to rebuild reactively. |
| `Auth.fake({Authenticatable? user})` | `FakeAuthManager` | **Testing.** Swap real `AuthManager` with `FakeAuthManager`. Pass `user` to pre-authenticate. Returns fake for assertions (`assertLoggedIn`, `assertLoggedOut`, `assertLoginAttempted`, `assertLoginCount`). |
| `Auth.unfake()` | `void` | **Testing.** Remove fake and restore real `AuthManager`. Call in `tearDown`. |

```dart
import 'package:magic/magic.dart';

// In your ServiceProvider.boot():
Auth.manager.setUserFactory(User.fromMap);

// On login:
final response = await Http.post('/login', data: credentials);
final user = User.fromMap(response['data']['user']);
await Auth.login({'token': response['data']['token']}, user);

// Guard check:
if (Auth.check()) {
  final user = Auth.user<User>();
}

// Reactive rebuild:
Auth.stateNotifier.addListener(() => setState(() {}));

// On boot:
await Auth.restore();
if (Auth.guest) Route.to('/login');
```

---

## Cache

Resolves `Magic.make<CacheManager>('cache')`.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Cache.put(String key, dynamic value, {Duration? ttl})` | `Future<void>` | Store item with optional expiration. |
| `Cache.get(String key, {dynamic defaultValue})` | `dynamic` | Retrieve item; returns `defaultValue` if missing or expired. |
| `Cache.has(String key)` | `bool` | Synchronous existence check. |
| `Cache.forget(String key)` | `Future<void>` | Remove a single cache item. |
| `Cache.flush()` | `Future<void>` | Clear all items from the current cache driver. |
| `Cache.remember<T>(String key, Duration ttl, Future<T> Function() callback)` | `Future<T>` | Return cached value or execute callback, store, and return. |
| `Cache.fake()` | `FakeCacheManager` | **Testing.** Swap real `CacheManager` with in-memory `FakeCacheManager` that records operations. Returns fake for assertions (`assertHas`, `assertMissing`, `assertPut`). |
| `Cache.unfake()` | `void` | **Testing.** Remove fake and restore real `CacheManager`. Call in `tearDown`. |

```dart
import 'package:magic/magic.dart';

await Cache.put('users', userList, ttl: Duration(minutes: 5));

final users = await Cache.remember('users', Duration(minutes: 5), () async {
  return await Http.get('/users');
});

if (Cache.has('users')) {
  final cached = Cache.get('users');
}

await Cache.forget('users');
await Cache.flush();
```

---

## Config

Resolves `MagicApp.config` → `ConfigRepository`. Dot-notation throughout.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Config.get<T>(String key, [T? defaultValue])` | `T?` | Dot-notation read; returns `defaultValue` if missing. |
| `Config.getOrFail<T>(String key)` | `T` | Throws if key is not found. |
| `Config.set(String key, dynamic value)` | `void` | Runtime configuration override. |
| `Config.has(String key)` | `bool` | Check if a key exists. |
| `Config.all()` | `Map<String, dynamic>` | Return entire config as a map. |
| `Config.merge(Map<String, dynamic> config)` | `void` | Deep-merge new values into existing config. |
| `Config.prepend(String key, dynamic value)` | `void` | Prepend value to an array config entry. |
| `Config.push(String key, dynamic value)` | `void` | Append value to an array config entry. |
| `Config.forget(String key)` | `void` | Remove a config key. |
| `Config.flush()` | `void` | Clear all configuration. |
| `Config.repository` | `ConfigRepository` | Access the underlying repository directly. |

```dart
import 'package:magic/magic.dart';

final guard  = Config.get<String>('auth.defaults.guard');
final debug  = Config.get('app.debug', false);
final secret = Config.getOrFail<String>('app.key');

Config.set('cache.ttl', 3600);
Config.merge({'services': {'stripe': {'key': 'sk_live_...'}}});
```

---

## Crypt

Resolves `Magic.make<MagicEncrypter>('encrypter')`. Requires `EncryptionServiceProvider` — NOT auto-registered.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Crypt.encrypt(String value)` | `String` | AES-256-CBC encryption using `app.key`. |
| `Crypt.decrypt(String value)` | `String` | Decrypt with `app.key`; throws `MagicDecryptException` on failure. |
| `Crypt.encryptWithDeviceKey(String value)` | `Future<String>` | Encrypt with a device-specific key stored in Vault. |
| `Crypt.decryptWithDeviceKey(String value)` | `Future<String>` | Decrypt with the device-specific key. |
| `Crypt.hasDeviceKey()` | `Future<bool>` | Check if a device encryption key exists. |
| `Crypt.generateDeviceKey()` | `Future<void>` | Generate (or replace) the device key — invalidates previously encrypted data. |
| `Crypt.clearDeviceKey()` | `Future<void>` | Remove device key from Vault; previously encrypted data unrecoverable. |

```dart
import 'package:magic/magic.dart';

// Config-based (requires EncryptionServiceProvider + APP_KEY = 32 chars)
final payload = Crypt.encrypt('sensitive');
final plain   = Crypt.decrypt(payload);

// Device-based (auto-generates key on first use)
final secret = await Crypt.encryptWithDeviceKey('pin:1234');
final pin    = await Crypt.decryptWithDeviceKey(secret);
```

---

## DB

Resolves `Magic.make<DatabaseManager>('db')`.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `DB.table(String table)` | `QueryBuilder` | Fluent query builder entry point. |
| `DB.select(String sql, [List<Object?> params = const []])` | `List<Map<String, dynamic>>` | Raw SELECT; returns list of row maps. |
| `DB.insert(String sql, [List<Object?> params = const []])` | `int` | Raw INSERT; returns last insert rowid. |
| `DB.update(String sql, [List<Object?> params = const []])` | `int` | Raw UPDATE; returns affected row count. |
| `DB.delete(String sql, [List<Object?> params = const []])` | `int` | Raw DELETE; returns affected row count. |
| `DB.statement(String sql, [List<Object?> params = const []])` | `void` | Execute any arbitrary SQL (DDL, etc.). |
| `DB.beginTransaction()` | `void` | Begin a manual transaction. |
| `DB.commit()` | `void` | Commit the current transaction. |
| `DB.rollback()` | `void` | Roll back the current transaction. |
| `DB.transaction<T>(Future<T> Function() callback)` | `Future<T>` | Auto-commit on success, auto-rollback on error. |

```dart
import 'package:magic/magic.dart';

// QueryBuilder
final users = await DB.table('users')
    .where('is_active', true)
    .orderBy('created_at', 'desc')
    .limit(10)
    .get();

// Raw
final rows = DB.select('SELECT * FROM users WHERE age > ?', [18]);
final id   = DB.insert('INSERT INTO users (name) VALUES (?)', ['Alice']);

// Transaction
await DB.transaction(() async {
  await DB.table('orders').insert({'user_id': 1, 'total': 99});
  await DB.table('inventory').where('id', 5).update({'stock': 0});
});
```

---

## Event

Dispatches via `EventDispatcher.instance`. The `Event` facade only exposes `dispatch()` — listener registration is done directly on the dispatcher.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Event.dispatch(MagicEvent event)` | `Future<void>` | Trigger an event to all registered listeners. |
| `EventDispatcher.instance.register(Type eventType, List<MagicListener Function()> factories)` | `void` | Register listener factories for an event type. Call in `ServiceProvider.boot()`. |

```dart
import 'package:magic/magic.dart';

// Define event
class UserRegistered extends MagicEvent {
  final User user;
  UserRegistered(this.user);
}

// Register listeners in ServiceProvider.boot():
EventDispatcher.instance.register(UserRegistered, [
  () => SendWelcomeEmailListener(),
  () => CreateUserProfileListener(),
]);

// Dispatch from anywhere:
await Event.dispatch(UserRegistered(user));
```

---

## Gate

Uses a `GateManager` singleton. `AbilityCallback = Function`, `BeforeCallback = bool? Function(Model user, String ability)`.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Gate.define(String ability, AbilityCallback callback)` | `void` | Register a permission check. Callback receives `(Authenticatable? user, [dynamic args])`. |
| `Gate.before(BeforeCallback callback)` | `void` | Global interceptor; return `true` to allow, `false` to deny, `null` to continue. |
| `Gate.allows(String ability, [dynamic arguments])` | `bool` | True if current user has the ability. |
| `Gate.denies(String ability, [dynamic arguments])` | `bool` | Inverse of `allows()`. |
| `Gate.check(String ability, [dynamic arguments])` | `bool` | Alias for `allows()`. |
| `Gate.has(String ability)` | `bool` | Check if an ability has been defined. |
| `Gate.abilities` | `List<String>` | **Getter.** All defined ability names. |
| `Gate.flush()` | `void` | Remove all abilities (primarily for testing). |
| `Gate.manager` | `GateManager` | Access the underlying manager. |

```dart
import 'package:magic/magic.dart';

// In ServiceProvider.boot():
Gate.before((user, ability) {
  if ((user as User).isAdmin) return true;
  return null;
});

Gate.define('edit-post', (user, post) =>
    (user as User).id == (post as Post).userId);

// In UI / controllers:
if (Gate.allows('edit-post', post)) showEditButton();
if (Gate.denies('delete-post', post)) showAccessDenied();
```

---

## Http

Resolves `Magic.make<NetworkDriver>('network')`.

**RESTful resource helpers** map directly onto REST conventions:

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Http.index(String resource, {Map<String, dynamic>? filters, Map<String, String>? headers})` | `Future<MagicResponse>` | GET /resource |
| `Http.show(String resource, String id, {Map<String, String>? headers})` | `Future<MagicResponse>` | GET /resource/{id} |
| `Http.store(String resource, Map<String, dynamic> data, {Map<String, String>? headers})` | `Future<MagicResponse>` | POST /resource |
| `Http.update(String resource, String id, Map<String, dynamic> data, {Map<String, String>? headers})` | `Future<MagicResponse>` | PUT /resource/{id} |
| `Http.destroy(String resource, String id, {Map<String, String>? headers})` | `Future<MagicResponse>` | DELETE /resource/{id} |

**Raw HTTP methods:**

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Http.get(String url, {Map<String, dynamic>? query, Map<String, String>? headers})` | `Future<MagicResponse>` | GET with optional query params. |
| `Http.post(String url, {dynamic data, Map<String, String>? headers})` | `Future<MagicResponse>` | POST with body. |
| `Http.put(String url, {dynamic data, Map<String, String>? headers})` | `Future<MagicResponse>` | PUT with body. |
| `Http.delete(String url, {Map<String, String>? headers})` | `Future<MagicResponse>` | DELETE. |
| `Http.upload(String url, {required Map<String, dynamic> data, required Map<String, dynamic> files, Map<String, String>? headers})` | `Future<MagicResponse>` | Multipart file upload. |

**Testing utilities:**

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Http.fake([dynamic stubs])` | `FakeNetworkDriver` | Swap real driver for testing. No args = all 200. Map = URL pattern stubs (`*` wildcard). `FakeRequestHandler` = callback stub. |
| `Http.response([dynamic data, int statusCode = 200])` | `MagicResponse` | Build a stub response. Use as values in the `fake()` stubs map. |
| `Http.unfake()` | `void` | Restore real driver. Call in `tearDown`. |

```dart
import 'package:magic/magic.dart';

// RESTful
final list   = await Http.index('/users', filters: {'role': 'admin'});
final single = await Http.show('/users', '42');
final created = await Http.store('/users', {'name': 'Alice', 'email': 'alice@example.com'});
await Http.update('/users', '42', {'name': 'Alicia'});
await Http.destroy('/users', '42');

// Raw
final response = await Http.get('/search', query: {'q': 'flutter'});
if (response.successful) print(response.data);

// Upload
final file = await Pick.image();
await Http.upload('/avatars', data: {'user_id': '1'}, files: {'avatar': file});
```

---

## Lang

Resolves `Translator.instance`.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Lang.get(String key, [Map<String, dynamic>? replace])` | `String` | Translate key with optional `:placeholder` replacements. |
| `Lang.has(String key)` | `bool` | Check if translation key exists. |
| `Lang.setLocale(Locale locale, {bool reload = true})` | `Future<void>` | Change active locale; triggers `Magic.reload()` by default. |
| `Lang.detectLocale()` | `Locale` | Best-match from device locale without changing active locale. |
| `Lang.detectAndSetLocale()` | `Future<Locale>` | Detect and apply best-match locale. |
| `Lang.setSupportedLocales(List<Locale> locales)` | `void` | Register supported locales. |
| `Lang.addListener(VoidCallback listener)` | `void` | Subscribe to locale change events. |
| `Lang.removeListener(VoidCallback listener)` | `void` | Unsubscribe from locale change events. |
| `Lang.current` | `Locale` | **Getter.** Active locale. |
| `Lang.isLoaded` | `bool` | **Getter.** True if translations are loaded. |
| `Lang.supportedLocales` | `List<Locale>` | **Getter.** Registered supported locales. |
| `Lang.delegate` | `LocalizationsDelegate<Translator>` | Flutter localization delegate for `MaterialApp`. |
| `trans(String key, [Map<String, dynamic>? replace])` | `String` | Global helper — alias for `Lang.get()`. |

```dart
import 'package:magic/magic.dart';

// In translation JSON: {"greeting": "Hello, :name!"}
final msg = Lang.get('greeting', {'name': 'Alice'}); // "Hello, Alice!"
final msg = trans('auth.failed');

await Lang.setLocale(Locale('tr'));
await Lang.detectAndSetLocale();
```

---

## Launch

Resolves `Magic.make<LaunchService>('launch')`. Requires `LaunchServiceProvider` — NOT auto-registered. All methods return `false` on failure; they never throw.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Launch.url(String url, {LaunchMode mode = LaunchMode.externalApplication})` | `Future<bool>` | Open URL in external app or in-app WebView. |
| `Launch.email(String address, {String? subject, String? body})` | `Future<bool>` | Open email client pre-filled with address/subject/body. |
| `Launch.phone(String number)` | `Future<bool>` | Open device phone dialer. |
| `Launch.sms(String number, {String? body})` | `Future<bool>` | Open SMS app pre-filled with number/body. |
| `Launch.canLaunch(String url)` | `Future<bool>` | Check if the device can handle the URL scheme. |

```dart
import 'package:magic/magic.dart';

await Launch.url('https://flutter.dev');
await Launch.url('https://example.com', mode: LaunchMode.inAppWebView);
await Launch.email('support@example.com', subject: 'Bug', body: 'Details...');
await Launch.phone('+1234567890');
await Launch.sms('+1234567890', body: 'On my way!');

if (await Launch.canLaunch('tel:+1234567890')) {
  await Launch.phone('+1234567890');
}
```

---

## Log

Resolves `Magic.make<LogManager>('log')`. Supports all RFC 5424 levels.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Log.emergency(String message, [dynamic context])` | `void` | System is unusable. |
| `Log.alert(String message, [dynamic context])` | `void` | Action must be taken immediately. |
| `Log.critical(String message, [dynamic context])` | `void` | Critical conditions. |
| `Log.error(String message, [dynamic context])` | `void` | Runtime error; pass exception as context. |
| `Log.warning(String message, [dynamic context])` | `void` | Exceptional but non-error occurrences. |
| `Log.notice(String message, [dynamic context])` | `void` | Normal but significant events. |
| `Log.info(String message, [dynamic context])` | `void` | Interesting events. |
| `Log.debug(String message, [dynamic context])` | `void` | Detailed debug information. |
| `Log.log(String level, String message, [dynamic context])` | `void` | Log at an arbitrary level string. |
| `Log.channel(String name)` | `LoggerDriver` | Get a named log channel driver. |
| `Log.fake()` | `FakeLogManager` | **Testing.** Swap real `LogManager` with `FakeLogManager` that captures entries in memory (no console output). Returns fake for assertions (`assertLogged`, `assertLoggedError`, `assertNothingLogged`, `assertLoggedCount`). |
| `Log.unfake()` | `void` | **Testing.** Remove fake and restore real `LogManager`. Call in `tearDown`. |

```dart
import 'package:magic/magic.dart';

Log.info('User logged in', {'id': userId});
Log.error('Payment failed', {'error': e.toString(), 'trace': s.toString()});
Log.debug('Query executed', {'sql': sql, 'bindings': params});
```

---

## Pick

Standalone facade; no container registration needed.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Pick.image({double? maxWidth, double? maxHeight, int? imageQuality})` | `Future<MagicFile?>` | Single image from gallery; null if cancelled. |
| `Pick.images({double? maxWidth, double? maxHeight, int? imageQuality})` | `Future<List<MagicFile>>` | Multiple images from gallery; empty list if cancelled. |
| `Pick.camera({CameraDevice preferredCamera, double? maxWidth, double? maxHeight, int? imageQuality, bool fallbackToGallery, void Function(Object)? onError})` | `Future<MagicFile?>` | Capture photo; optionally fall back to gallery. |
| `Pick.media({double? maxWidth, double? maxHeight, int? imageQuality})` | `Future<MagicFile?>` | Pick image or video from gallery. |
| `Pick.video({Duration? maxDuration})` | `Future<MagicFile?>` | Single video from gallery. |
| `Pick.recordVideo({CameraDevice preferredCamera, Duration? maxDuration, bool fallbackToGallery, void Function(Object)? onError})` | `Future<MagicFile?>` | Record video with camera. |
| `Pick.file({List<String>? extensions, bool withData = true})` | `Future<MagicFile?>` | Single file with optional extension filter. |
| `Pick.files({List<String>? extensions, bool withData = true})` | `Future<List<MagicFile>>` | Multiple files with optional extension filter. |
| `Pick.directory()` | `Future<String?>` | Pick a directory path (not supported on Web). |
| `Pick.saveFile({String? dialogTitle, String? fileName, Uint8List? bytes})` | `Future<String?>` | Open save-file dialog; returns chosen path. |

```dart
import 'package:magic/magic.dart';

final image = await Pick.image(maxWidth: 800, imageQuality: 80);
if (image != null) await Storage.put('avatars/me.jpg', image);

final photo = await Pick.camera(
  fallbackToGallery: true,
  onError: (e) => Log.warning('Camera failed: $e'),
);

final pdf = await Pick.file(extensions: ['pdf']);
final docs = await Pick.files(extensions: ['pdf', 'doc', 'docx']);
```

---

## Route

The facade class is `MagicRoute`. Resolves `MagicRouter.instance`.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `MagicRoute.page(String path, Function handler)` | `RouteDefinition` | Register a page route; returns definition for fluent chaining. |
| `MagicRoute.group({String? prefix, List middleware, String? as, Widget Function(Widget)? layout, String? layoutId, required void Function() routes})` | `void` | Group routes with shared prefix/middleware. |
| `MagicRoute.layout({String? id, required Widget Function(Widget child) builder, required List<RouteDefinition> routes})` | `void` | Persistent shell layout for nested routes. |
| `MagicRoute.to(String path, {Map<String, String>? query})` | `void` | Navigate to path — no BuildContext needed. |
| `MagicRoute.toNamed(String name, {Map<String, String> params, Map<String, String> query})` | `void` | Navigate by named route. |
| `MagicRoute.push(String path)` | `void` | Push path onto the navigation stack. |
| `MagicRoute.back({String? fallback})` | `void` | Pop the current route. Works across shell routes via history tracking. Uses `fallback` path when history is empty. |
| `MagicRoute.replace(String path)` | `void` | Replace current route in history. |
| `MagicRoute.config` | `GoRouter` | **Getter.** Pass to `MaterialApp.router(routerConfig:)`. |

```dart
import 'package:magic/magic.dart';

// Route definition (in your ServiceProvider or routes file):
MagicRoute.page('/', () => HomePage()).name('home');
MagicRoute.page('/users/:id', (id) => UserPage(id: id));

MagicRoute.group(
  prefix: '/admin',
  middleware: [AuthMiddleware()],
  routes: () {
    MagicRoute.page('/dashboard', AdminDashboard.new);
    MagicRoute.page('/users', AdminUsersPage.new);
  },
);

// Navigation (from anywhere):
MagicRoute.to('/users/42');
MagicRoute.toNamed('users.show', params: {'id': '42'});
MagicRoute.back();
MagicRoute.replace('/home');

// App setup:
MaterialApp.router(routerConfig: MagicRoute.config);
```

---

## Schema

Resolves `DatabaseManager()` internally. All schema operations are synchronous except existence checks.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Schema.create(String table, void Function(Blueprint) callback)` | `void` | Define and create a new table. |
| `Schema.table(String tableName, void Function(Blueprint) callback)` | `void` | Modify an existing table — add, rename, or drop columns. |
| `Schema.dropIfExists(String table)` | `void` | Drop table if it exists; no-op otherwise. |
| `Schema.drop(String table)` | `void` | Drop table; throws if it doesn't exist. |
| `Schema.rename(String from, String to)` | `void` | Rename a table. |
| `Schema.hasTable(String table)` | `Future<bool>` | Check if a table exists. |
| `Schema.hasColumn(String table, String column)` | `Future<bool>` | Check if a column exists in a table. |
| `Schema.getColumns(String table)` | `Future<List<String>>` | List all column names for a table. |

```dart
import 'package:magic/magic.dart';

Schema.create('users', (table) {
  table.id();
  table.string('name');
  table.string('email').unique();
  table.boolean('is_active').defaultValue(true);
  table.timestamps();
});

Schema.table('users', (table) {
  table.string('avatar_url').nullable();
  table.dropColumn('legacy_field');
});

Schema.dropIfExists('temp_data');

if (await Schema.hasTable('users')) {
  final cols = await Schema.getColumns('users');
}
```

---

## Storage

Resolves `StorageManager()` internally. Defaults to the local disk.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Storage.disk([String? name])` | `StorageDisk` | Get a named disk; defaults to the default disk. |
| `Storage.put(String path, dynamic contents, {String? mimeType})` | `Future<String>` | Write contents (`Uint8List`, `String`, or `MagicFile`); returns stored path/URL. |
| `Storage.get(String path)` | `Future<Uint8List?>` | Retrieve file as raw bytes; null if not found. |
| `Storage.getFile(String path)` | `Future<MagicFile?>` | Retrieve file as `MagicFile` with metadata; null if not found. |
| `Storage.exists(String path)` | `Future<bool>` | Check if a file exists. |
| `Storage.delete(String path)` | `Future<bool>` | Delete file; returns true if deleted. |
| `Storage.url(String path)` | `Future<String>` | `file://` path on mobile/desktop, `blob:` URL on Web. |
| `Storage.download(String path, {String? name})` | `Future<void>` | Share sheet on mobile; browser download on Web. |
| `Storage.flush()` | `void` | Reset the storage manager (primarily for testing). |

```dart
import 'package:magic/magic.dart';

// Store picked image
final image = await Pick.image();
final path  = await Storage.put('avatars/user.jpg', image, mimeType: 'image/jpeg');

// Display
final url = await Storage.url('avatars/user.jpg');
Image.network(url);

// Retrieve
final file = await Storage.getFile('avatars/user.jpg');
if (file != null) print(file.name);

// Cleanup
await Storage.delete('avatars/user.jpg');

// Named disk
await Storage.disk('public').put('uploads/file.pdf', bytes);
```

---

## Vault

Resolves `Magic.make<MagicVaultService>('vault')`. Backed by `flutter_secure_storage`.

| Signature | Return Type | Notes |
|-----------|-------------|-------|
| `Vault.put(String key, String value)` | `Future<void>` | Write sensitive data to secure storage. |
| `Vault.get(String key)` | `Future<String?>` | Read value; null if key does not exist. |
| `Vault.delete(String key)` | `Future<void>` | Remove a specific key. |
| `Vault.flush()` | `Future<void>` | Wipe ALL secure storage data for this app. |
| `Vault.fake([Map<String, String> initialValues = const {}])` | `FakeVaultService` | **Testing.** Swap real `MagicVaultService` with in-memory `FakeVaultService`. Pass `initialValues` to pre-seed. Returns fake for assertions (`assertWritten`, `assertDeleted`, `assertContains`, `assertMissing`). |
| `Vault.unfake()` | `void` | **Testing.** Remove fake and restore real `MagicVaultService`. Call in `tearDown`. |

```dart
import 'package:magic/magic.dart';

await Vault.put('refresh_token', token);
final stored = await Vault.get('refresh_token');
await Vault.delete('refresh_token');
await Vault.flush(); // Danger: clears all secure data
```

---

## Gotchas

- **Init required**: Facades that resolve from the container (`Cache`, `Http`, `Log`, `Launch`, `Vault`) will throw if called before `Magic.init()` completes.
- **Auth.guest is a getter**: `Auth.guest` — no parentheses. `Auth.check()` requires parentheses.
- **Event listeners use factories**: `EventDispatcher.instance.register(Type, [() => MyListener()])` — pass factory closures, not instances.
- **EncryptionServiceProvider**: Not auto-registered. Add `(app) => EncryptionServiceProvider(app)` to providers config. `APP_KEY` must be exactly 32 characters.
- **LaunchServiceProvider**: Not auto-registered. Add `(app) => LaunchServiceProvider(app)` to providers config. Declare URL schemes in the native manifest for `canLaunch()` to work on iOS 9+ and Android 11+.
- **Route facade name**: The class is `MagicRoute`, not `Route`. Alias it if you prefer: `import 'package:magic/magic.dart' show MagicRoute as Route;`.
- **Schema sync**: `Schema.create/table/drop/rename` are synchronous; `Schema.hasTable/hasColumn/getColumns` are async.
- **Storage on Web**: `put()` stores Base64 in SharedPreferences; `url()` returns a `blob:` URL, not a file path.
- **Config dot notation**: `Config.get('auth.defaults.guard')` — nested keys separated by `.`.
