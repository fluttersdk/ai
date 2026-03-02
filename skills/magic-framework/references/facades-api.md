# Magic Framework: Facades API Reference

Complete reference for Magic framework facades, their resolution keys, and method signatures.


## Auth & Security

### Auth
Resolves via `AuthManager` singleton.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Auth.check()` | `bool` | Check if a user is currently authenticated. |
| `Auth.user<T extends Model>()` | `T?` | Get the current authenticated user instance. |
| `Auth.id()` | `dynamic` | Get the primary key of the current user. |
| `Auth.login(Map<String, dynamic> data, Authenticatable user)` | `Future<void>` | Store credentials and set the authenticated user. |
| `Auth.logout()` | `Future<void>` | Terminate session and clear stored tokens. |
| `Auth.restore()` | `Future<void>` | Restore session from secure storage (Vault). |
| `Auth.manager` | `AuthManager` | Access the underlying manager for advanced config. |
| `Auth.manager.setUserFactory(Authenticatable Function(Map) f)` | `void` | **REQUIRED** in `ServiceProvider.boot()`. |
| `Auth.manager.extend(String name, Guard Function(Map) f)` | `void` | Register a custom authentication guard. |
| `Auth.guest` | `bool` | Check if user is NOT authenticated. |
| `Auth.hasToken()` | `Future<bool>` | Check if a token exists in storage. |
| `Auth.getToken()` | `Future<String?>` | Get the stored token. |
| `Auth.refreshToken()` | `Future<bool>` | Manually trigger a token refresh. |
| `Auth.registerModel<T>(factory)` | `void` | Alias for `manager.setUserFactory()`. |
| `Auth.stateNotifier` | `ValueNotifier<int>` | Reactive notifier — bumps on login/logout/restore. |

### Vault
Resolves `Magic.make('vault')` → `MagicVaultService` (secure storage).

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Vault.put(String key, String value)` | `Future<void>` | Write sensitive data to secure storage. |
| `Vault.get(String key)` | `Future<String?>` | Read sensitive data. |
| `Vault.remove(String key)` | `Future<void>` | Remove a specific key. |
| `Vault.flush()` | `Future<void>` | Wipe all data from secure storage. |

### Crypt
Resolves via `EncryptionServiceProvider` (Manual registration required).

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Crypt.encrypt(String value)` | `String` | AES-256-CBC encryption. |
| `Crypt.decrypt(String payload)` | `String` | Decrypt a previously encrypted payload. |

*Note: Requires `APP_KEY` (32 characters) defined in `.env`.*

### Gate
Resolves via `GateManager` singleton.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Gate.define(String ability, bool Function(Authenticatable?, [dynamic]) cb)` | `void` | Register a permission check. |
| `Gate.allows(String ability, [dynamic args])` | `bool` | Sync check if user has permission. |
| `Gate.denies(String ability, [dynamic args])` | `bool` | Inverse of `allows()`. |
| `Gate.before(bool? Function(Authenticatable?) cb)` | `void` | Global interceptor (e.g., for Super Admin). |

## Data & Persistence

### DB
Resolves `Magic.make('db')` → `DatabaseManager`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `DB.table(String name)` | `QueryBuilder` | Start a fluent query on a specific table. |
| `DB.select(String query)` | `Future<List<Map>>` | Execute a raw SQL SELECT query. |
| `DB.insert(String query)` | `Future<int>` | Execute a raw INSERT and return the ID. |
| `DB.transaction(Future Function() callback)` | `Future<T>` | Run logic inside a database transaction. |

### Schema
Resolves via `DatabaseManager`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Schema.create(String table, void Function(Blueprint) cb)` | `Future<void>` | Define and create a new table. |
| `Schema.dropIfExists(String table)` | `Future<void>` | Drop a table if it exists. |
| `Schema.hasTable(String table)` | `Future<bool>` | Check for table existence. |

### Cache
Resolves `Magic.make('cache')` → `CacheManager`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Cache.get(String key, {dynamic defaultValue})` | `Future<dynamic>` | Retrieve item from cache. |
| `Cache.put(String key, dynamic val, {Duration? ttl})` | `Future<void>` | Store item with optional expiration. |
| `Cache.has(String key)` | `bool` | Check if item exists in cache (synchronous). |
| `Cache.forget(String key)` | `Future<void>` | Remove a specific cache item. |
| `Cache.flush()` | `Future<void>` | Clear all items from the current cache driver. |

## HTTP & Network

### Http
Resolves `Magic.make('network')` → `NetworkDriver`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Http.get(String url, {Map? query})` | `Future<MagicResponse>` | Perform a GET request. |
| `Http.post(String url, {dynamic data})` | `Future<MagicResponse>` | Perform a POST request. |
| `Http.put(String url, {dynamic data})` | `Future<MagicResponse>` | Perform a PUT request. |
| `Http.patch(String url, {dynamic data})` | `Future<MagicResponse>` | Perform a PATCH request. |
| `Http.delete(String url)` | `Future<MagicResponse>` | Perform a DELETE request. |
| `Http.upload(String url, {required Map data, required Map files, Map? headers})` | `Future<MagicResponse>` | Multipart file upload. |

## UI & Navigation

### Route
Resolves `MagicRouter.instance`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `MagicRoute.to(String path)` | `void` | Push a new route to the stack. |
| `MagicRoute.back()` | `void` | Pop the current route. |
| `MagicRoute.replace(String path)` | `void` | Replace current route in history. |
| `MagicRoute.toNamed(String name)` | `void` | Navigate using a defined route name. |

### Config
Resolves `MagicApp.config` → `ConfigRepository`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Config.get(String key, [dynamic defaultValue])` | `dynamic` | Dot-notation access to configuration. |
| `Config.set(String key, dynamic value)` | `void` | Runtime configuration override. |

## Utility & Infrastructure

### Log
Resolves `Magic.make('log')` → `LogManager`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Log.info(String msg)` | `void` | Log information message. |
| `Log.error(String msg, [dynamic e])` | `void` | Log error with optional exception object. |
| `Log.warning(String msg)` | `void` | Log warning message. |
| `Log.debug(String msg)` | `void` | Log debugging information. |

### Event
Resolves `EventDispatcher`. The facade only exposes `dispatch()` — listener registration is done via `EventDispatcher.instance.register()`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Event.dispatch(MagicEvent event)` | `Future<void>` | Trigger an event across the app. |
| `EventDispatcher.instance.register(Type, List<MagicListener Function()>)` | `void` | Register listener factories for an event type. |

### Lang
Resolves `Translator.instance`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Lang.get(String key, [Map? replacements])` | `String` | Translate a key with optional placeholders. |
| `Lang.has(String key)` | `bool` | Check if a translation key exists. |
| `Lang.setLocale(Locale locale)` | `void` | Change the application's active locale. |
| `trans(String key, [Map? params])` | `String` | **Global helper alias** for `Lang.get()`. |

### Storage
Resolves `StorageManager`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Storage.put(String path, dynamic content, {String? mimeType})` | `Future<String>` | Write file/content to local disk. Returns stored path. |
| `Storage.get(String path)` | `Future<Uint8List?>` | Retrieve file contents as bytes. |
| `Storage.delete(String path)` | `Future<bool>` | Delete a file. |
| `Storage.exists(String path)` | `Future<bool>` | Check if a file exists. |
| `Storage.url(String path)` | `Future<String>` | Get a URL for the given file path. |

### Pick
File and image picker facade.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Pick.image({maxWidth, maxHeight, imageQuality})` | `Future<MagicFile?>` | Pick a single image from gallery. |
| `Pick.images({maxWidth, maxHeight, imageQuality})` | `Future<List<MagicFile>>` | Pick multiple images from gallery. |
| `Pick.camera({preferredCamera, maxWidth, imageQuality, fallbackToGallery})` | `Future<MagicFile?>` | Capture photo with camera. |
| `Pick.video({maxDuration})` | `Future<MagicFile?>` | Pick a video from gallery. |
| `Pick.recordVideo({preferredCamera, maxDuration, fallbackToGallery})` | `Future<MagicFile?>` | Record video with camera. |
| `Pick.media({maxWidth, maxHeight, imageQuality})` | `Future<MagicFile?>` | Pick image or video from gallery. |
| `Pick.file({List<String>? extensions})` | `Future<MagicFile?>` | Pick a single file. |
| `Pick.files({List<String>? extensions})` | `Future<List<MagicFile>>` | Pick multiple files. |
| `Pick.directory()` | `Future<String?>` | Pick a directory (not supported on Web). |
| `Pick.saveFile({fileName, bytes})` | `Future<String?>` | Open save file dialog. |

## Context-Free UI (Magic Class)

The `Magic` class provides static methods for common UI feedback tasks without needing `BuildContext`.

| Method | Return Type | Description |
|--------|-------------|-------------|
| `Magic.snackbar(title, msg, {type})` | `void` | Show a standard snackbar. |
| `Magic.success(title, msg)` | `void` | Show a success (green) snackbar. |
| `Magic.error(title, msg)` | `void` | Show an error (red) snackbar. |
| `Magic.toast(String message)` | `void` | Show a brief toast message. |
| `Magic.dialog<T>(Widget dialog)` | `Future<T?>` | Display a custom dialog. |
| `Magic.confirm({title, message})` | `Future<bool>` | Show a YES/NO confirmation dialog. |
| `Magic.loading({String? message})` | `void` | Show a persistent loading overlay. |
| `Magic.closeLoading()` | `void` | Dismiss the loading overlay. |
| `Magic.reload()` | `void` | Trigger a full application restart. |

## Gotchas

- **Facade Access**: Facades are only available after `Magic.init()` resolves.
- **Event Listeners**: `Event` facade only has `dispatch()`. Register listeners via `EventDispatcher.instance.register(type, [() => MyListener()])` — factories, not instances.
- **Dot Notation**: `Config.get` and `Lang.get` use dot notation (e.g., `auth.defaults.guard`).
- **Crypt Setup**: AES encryption will fail if `APP_KEY` is not exactly 32 characters in your `.env`.
- **Storage Paths**: `Storage` facade defaults to the application's document directory.
