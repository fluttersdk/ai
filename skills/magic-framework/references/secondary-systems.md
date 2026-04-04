# Magic Framework: Secondary Systems

Complete reference for Magic framework utility systems: Cache, Events, Logging, Localization, Storage, Encryption, Vault, Carbon, Launch, and Pick. All systems are accessible through facades after importing `package:magic/magic.dart`.

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

### EventDispatcher (Direct Access)

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `EventDispatcher.instance.register(eventType, listeners)` | `Type eventType`, `List<MagicListener Function()> listeners` | `void` | Register listener factories for an event type. |
| `EventDispatcher.instance.clear()` | — | `void` | Clear all registered listeners (testing only). |

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

Multi-language translation system with JSON-based message files and runtime locale switching. Accessed via the `Lang` facade or `trans()` helper.

### Lang API

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Lang.get(key, [replace])` | `String key`, `Map<String, dynamic>? replace` | `String` | Get a translated string with optional `:placeholder` replacements. |
| `Lang.has(key)` | `String key` | `bool` | Check if a translation key exists. |
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
```

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
| `Pick.file({extensions, withData})` | `List<String>? extensions`, `bool withData` | `Future<MagicFile?>` | Pick single file with optional extension filter. |
| `Pick.files({extensions, withData})` | `List<String>? extensions`, `bool withData` | `Future<List<MagicFile>>` | Pick multiple files. |
| `Pick.directory()` | — | `Future<String?>` | Pick a directory path. |
| `Pick.saveFile({dialogTitle, fileName, bytes})` | Dialog & file options | `Future<String?>` | Open save dialog. |

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

// Save dialog
final savePath = await Pick.saveFile(
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

## Key Gotchas

- **Cache**: `remember<T>()` returns cached value directly (not awaited) if it exists; only awaits callback on miss.
- **Events**: Listeners run sequentially. If one throws, others still execute. Errors are logged, not re-thrown.
- **Logging**: `Log.channel(name)` returns a `LoggerDriver` resolved via `LogManager.driver(name)`, enabling per-channel logging.
- **Lang**: `trans()` helper is a shorthand for `Lang.get()`. Translations must be loaded before first use.
- **Storage**: `put()` returns the path, `get()` returns raw bytes. Use `getFile()` for metadata.
- **Crypt**: App key must be exactly 32 characters. Device keys are auto-generated on first `encryptWithDeviceKey()` call.
- **Vault**: Async operations. May fail if hardware keystore is locked (e.g., on first boot before PIN unlock).
- **Carbon**: All manipulation methods return NEW instances; original is immutable.
- **Launch**: Never throws; always returns bool. Register `LaunchServiceProvider` manually.
- **Pick**: Returns `MagicFile` instances which wrap `image_picker` and `file_picker` results. Camera fallback requires explicit opt-in.
