# Magic Framework: Secondary Systems

Reference for the Magic framework's utility systems including Cache, Events, Logging, Localization, Storage, Encryption, Security, Support, and Policies.

## Cache System

The Cache system provides a unified API for various cache backends. Resolved via the `Cache` facade or `CacheManager`.

### Cache API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `get(key, {defaultValue})` | `dynamic` | Retrieve an item from the cache. |
| `put(key, value, {ttl})` | `Future<void>` | Store an item in the cache with an optional TTL `Duration`. |
| `has(key)` | `bool` | Determine if an item exists in the cache and is not expired. |
| `forget(key)` | `Future<void>` | Remove an item from the cache. |
| `flush()` | `Future<void>` | Remove all items from the cache. |

### Drivers
- `MemoryStore`: Simple in-memory cache (default for web/testing).
- `FileStore`: Persistent file-based cache (default for mobile).

### Configuration
```dart
// config/cache.dart
'cache': {
    'driver': env('CACHE_DRIVER', 'file'), // 'file' or 'memory'
    'ttl': 3600, // Default TTL in seconds
}
```

## Event Dispatcher

A simple pub/sub system for decoupling application logic. The `Event` facade only exposes `dispatch()`. Listener registration is done via `EventDispatcher.instance.register()`.

### API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `dispatch(MagicEvent event)` | `Future<void>` | Fire an event and notify all registered listeners. |
| `EventDispatcher.instance.register(Type, List<MagicListener Function()>)` | `void` | Register listener factories for an event type. |

### Usage
```dart
// 1. Define an Event
class UserRegistered extends MagicEvent {
    final User user;
    UserRegistered(this.user);
}

// 2. Define a Listener
class SendWelcomeEmail extends MagicListener<UserRegistered> {
    @override
    Future<void> handle(UserRegistered event) async {
        // Logic to send email
    }
}

// 3. Register in a ServiceProvider
@override
void register() {
    EventDispatcher.instance.register(UserRegistered, [
        () => SendWelcomeEmail(),
    ]);
}

// 4. Dispatch
await Event.dispatch(UserRegistered(user));
```

## Logging Manager

Channel-based logging system. Accessed via the `Log` facade.

### Log API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `debug(message, [exception])` | `void` | Log a debug message. |
| `info(message, [exception])` | `void` | Log an informational message. |
| `warning(message, [exception])` | `void` | Log a warning message. |
| `error(message, [exception])` | `void` | Log an error message. |
| `channel(name)` | `LoggerDriver` | Get a specific logging channel instance. |

### Drivers
- `console`: Logs to the standard output.
- `stack`: Logs to multiple channels simultaneously.

### Configuration
```dart
// config/logging.dart
'logging': {
    'default': env('LOG_CHANNEL', 'stack'),
    'channels': {
        'stack': {
            'driver': 'stack',
            'channels': ['console'],
        },
        'console': {
            'driver': 'console',
            'level': 'debug',
        },
    },
}
```

## Localization (Translator)

Manages multi-language support and date localization. Accessed via the `Lang` facade or `trans()` helper.

### Lang API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `get(key, [replacements])` | `String` | Get a translation for a key with optional `:placeholder` replacements. |
| `setLocale(Locale locale)` | `Future<void>` | Switch the application locale at runtime. |
| `detectLocale()` | `Locale` | Detect the best matching locale from device settings. |
| `has(key)` | `bool` | Check if a translation key exists. |

### Usage
```dart
// JSON: "welcome": "Hello, :name!"
String msg = Lang.get('welcome', {'name': 'Anilcan'}); // "Hello, Anilcan!"

// Using helper
String title = __('app.title');
```

## Storage Manager

Filesystem abstraction for local disk operations. Accessed via the `Storage` facade.

### Storage API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `put(path, content, {mimeType})` | `Future<String>` | Store a file (String or Uint8List) at the given path. |
| `get(path)` | `Future<Uint8List?>` | Retrieve file contents as bytes. |
| `exists(path)` | `Future<bool>` | Check if a file exists. |
| `delete(path)` | `Future<bool>` | Remove a file. |
| `url(path)` | `Future<String>` | Get a URL for the given file path. |
| `disk(name)` | `StorageDisk` | Get a specific storage disk instance. |

### Configuration
```dart
// config/filesystems.dart
'filesystems': {
    'default': 'local',
    'disks': {
        'local': {
            'driver': 'local',
            'root': 'storage/app',
        },
        'public': {
            'driver': 'local',
            'root': 'storage/app/public',
        },
    },
}
```

## Encryption (MagicEncrypter)

AES-256-CBC encryption for sensitive data. Accessed via the `Crypt` facade.

> [!WARNING]
> `EncryptionServiceProvider` is NOT auto-registered. You must add it manually to your `app.providers` list.

### Crypt API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `encrypt(value)` | `String` | Encrypt a string value (returns `iv:ciphertext` format). |
| `decrypt(payload)` | `String` | Decrypt a payload. Throws `MagicDecryptException` on failure. |

### Requirement
The `APP_KEY` in your `.env` MUST be exactly 32 characters long.

## Security (MagicVaultService)

Hardware-backed secure storage using `flutter_secure_storage`. Accessed via the `Vault` facade.

### Vault API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `put(key, value)` | `Future<void>` | Store a sensitive string in secure storage. |
| `get(key)` | `Future<String?>` | Retrieve a string from secure storage. |
| `remove(key)` | `Future<void>` | Delete a key from secure storage. |
| `flush()` | `Future<void>` | Clear all data from secure storage. |

## Support (Carbon)

A Laravel-style date manipulation wrapper around `Jiffy`.

### Carbon API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `now([timezone])` | `Carbon` | Create an instance for the current time. |
| `parse(dateString)` | `Carbon` | Parse a date string. |
| `addDays(count)` | `Carbon` | Add days and return a new instance. |
| `startOfMonth()` | `Carbon` | Get the start of the month. |
| `format(pattern)` | `String` | Format using `intl` patterns. |
| `diffForHumans()` | `String` | Get "2 hours ago" style relative time. |

### Usage
```dart
final tomorrow = Carbon.now().addDay().endOfDay();
print(tomorrow.toDateTimeString()); // "2024-01-16 23:59:59"
```


## Launch (URL Launcher)

Context-free facade for opening URLs, emails, phone calls, and SMS messages. Built on `url_launcher`. Accessed via the `Launch` facade.

> [!WARNING]
> `LaunchServiceProvider` is NOT auto-registered. Add `(app) => LaunchServiceProvider(app)` to your `app.providers` config.

### Launch API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `url(String url, {LaunchMode mode})` | `Future<bool>` | Open URL in external app (default) or in-app WebView. |
| `email(String address, {String? subject, String? body})` | `Future<bool>` | Open email client pre-filled. Subject/body are auto URI-encoded. |
| `phone(String number)` | `Future<bool>` | Open device phone dialer. |
| `sms(String number, {String? body})` | `Future<bool>` | Open SMS app pre-filled. Body is auto URI-encoded. |
| `canLaunch(String url)` | `Future<bool>` | Check if device can handle the URL scheme. |

### Usage
```dart
// Open a URL
await Launch.url('https://flutter.dev');

// Open in-app browser
await Launch.url('https://flutter.dev', mode: LaunchMode.inAppWebView);

// Send email
await Launch.email('support@example.com', subject: 'Bug Report', body: 'Details...');

// Phone call
await Launch.phone('+1234567890');

// SMS
await Launch.sms('+1234567890', body: 'On my way!');

// Check before launching
if (await Launch.canLaunch('tel:+1234567890')) {
    await Launch.phone('+1234567890');
}
```

### Error Handling

All methods return `false` on failure — they **never throw**. Errors are logged via `Log`. Empty string inputs return `false` immediately without attempting a launch.

### Testing

The `LaunchService` accepts a `LaunchAdapter` for dependency injection. In tests, provide a mock adapter:

```dart
final mockAdapter = MockLaunchAdapter();
app.singleton('launch', () => LaunchService(adapter: mockAdapter));
```

## Policies & Gate

Authorization system for checking user permissions. Accessed via the `Gate` facade.

### Gate API

| Method | Return Type | Description |
|:-------|:------------|:------------|
| `define(ability, callback)` | `void` | Define a named authorization ability. |
| `allows(ability, [args])` | `bool` | Check if the authenticated user has the ability. |
| `denies(ability, [args])` | `bool` | Inverse of `allows()`. |
| `before(callback)` | `void` | Register a callback that runs before all checks (e.g., for Super Admin). |

### Usage
```dart
// 1. Define in ServiceProvider.boot()
Gate.define('edit-post', (user, post) => user.id == post.userId);

// 2. Check in UI or Controller
if (Gate.allows('edit-post', post)) {
    // Show edit button
}
```

## Gotchas

- **Encryption Registration**: `EncryptionServiceProvider` must be manually added to `config/app.dart`.
- **App Key Length**: `Crypt` will fail if your `APP_KEY` is not exactly 32 characters.
- **Translator Initialization**: `Lang.get()` returns the key itself if translations are not yet loaded. Ensure `Magic.init()` is awaited.
- **Storage Paths**: Local storage paths are relative to the application's document directory.
- **Event Listeners**: Always register listeners using factory closures `() => MyListener()` to avoid lifecycle issues.
- **Vault Availability**: `Vault` operations are async and might fail if the hardware keystore is locked (e.g., on first boot before unlock).
- **Carbon Immutability**: All `Carbon` manipulation methods return a NEW instance; they do not mutate the original object.
- **Launch Registration**: `LaunchServiceProvider` must be manually added to `app.providers`. On iOS 9+ and Android 11+, declare URL schemes in the native manifest for `canLaunch()` to work.
