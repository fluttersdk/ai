# magic_notifications Plugin

Push and in-app notification system for Magic Framework — provides the `Notify` facade, database (in-app) notifications with real-time streaming, OneSignal push integration, and background polling.

**Package**: `magic_notifications` v0.0.1-alpha.1 · **Install**: `dart run magic_notifications install`

## Notify Facade API

All methods are accessed via the static `Notify` facade after importing `package:magic_notifications/magic_notifications.dart`.

### Sending

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.send(notifiable, notification)` | `Notifiable notifiable`, `Notification notification` | `Future<void>` | Send notification to entity through channels defined by `notification.via()`. |

### Database (In-App) Notifications

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.notifications()` | — | `Stream<List<DatabaseNotification>>` | Broadcast stream — emits current cache immediately, then re-emits on every fetch/read/delete. |
| `Notify.fetchNotifications()` | — | `Future<void>` | Fetch from `GET /notifications` and push updated list to stream. |
| `Notify.refreshNotifications()` | — | `Future<void>` | Alias for `fetchNotifications()`. |
| `Notify.fetchPaginatedNotifications({page, perPage})` | `int page = 1`, `int perPage = 15` | `Future<PaginatedNotifications>` | Returns paginated response with meta (current_page, last_page, total). |
| `Notify.unreadCount()` | — | `Future<int>` | Fetch unread count from `GET /notifications/unread-count`. |
| `Notify.markAsRead(id)` | `String id` | `Future<void>` | Optimistically mark read locally, then `POST /notifications/{id}/read`. Reverts on failure. |
| `Notify.markAllAsRead()` | — | `Future<void>` | Optimistically mark all read locally, then `POST /notifications/read-all`. Reverts on failure. |
| `Notify.deleteNotification(id)` | `String id` | `Future<void>` | Optimistically remove locally, then `DELETE /notifications/{id}`. Reverts on failure. |

### Push Notifications

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.initializePush(userId)` | `String userId` | `Future<void>` | Associate logged-in user with push device. Call after `Auth.login()`. |
| `Notify.requestPushPermission()` | — | `Future<bool>` | Show system permission dialog. Returns `true` if granted. |
| `Notify.logoutPush()` | — | `Future<void>` | Unlink device from user account. Call before `Auth.logout()`. |

### Polling

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.startPolling()` | — | `void` | Start 30-second polling. Fetches immediately on start. Idempotent. |
| `Notify.stopPolling()` | — | `void` | Stop polling and destroy timer. Call on logout. |
| `Notify.pausePolling()` | — | `void` | Pause (timer keeps running, fetches are skipped). Use on app background. |
| `Notify.resumePolling()` | — | `void` | Resume paused polling. Fetches immediately on resume. |

### Manager Access

```dart
final manager = Notify.manager; // NotificationManager singleton
```

## Contracts

### Notification (abstract)

Extend to define a notification type.

```dart
import 'package:magic_notifications/magic_notifications.dart';

class MonitorDownNotification extends Notification {
  final Monitor monitor;
  MonitorDownNotification(this.monitor);

  @override
  List<String> via(Notifiable notifiable) => ['database', 'push'];

  @override
  Map<String, dynamic>? toDatabase(Notifiable notifiable) => {
    'title': 'Monitor Down',
    'body': '${monitor.name} is not responding',
    'action_url': '/monitors/${monitor.id}',
  };

  @override
  dynamic toPush(Notifiable notifiable) => PushMessage()
    .heading('Monitor Down')
    .content('${monitor.name} is not responding')
    .url('/monitors/${monitor.id}');
}
```

| Member | Type | Description |
|:-------|:-----|:------------|
| `type` | `String` (getter) | Defaults to `runtimeType.toString()`. Override to customize. |
| `via(notifiable)` | `List<String>` | Required. Return channel names: `'database'`, `'push'`, `'mail'`. |
| `toDatabase(notifiable)` | `Map<String, dynamic>?` | Return payload with `title`, `body`, optional `action_url`. |
| `toPush(notifiable)` | `dynamic` | Return `PushMessage` instance or raw map. |
| `toMail(notifiable)` | `dynamic` | Return mail payload (mail channel not auto-registered). |

### Notifiable (mixin)

Apply to any model that can receive notifications.

```dart
class User extends Model with Notifiable {
  @override
  String get notifiableId => getAttribute('id').toString();

  @override
  String? get notifiableEmail => getAttribute('email') as String?;
}
```

| Member | Type | Description |
|:-------|:-----|:------------|
| `notifiableId` | `String` | Required. Unique identifier used to target the entity. |
| `notifiableEmail` | `String?` | Optional. Used by mail channel. Defaults to `null`. |
| `pushExternalId` | `String` | Push targeting ID. Defaults to `notifiableId`. |
| `notificationPreference` | `dynamic` | Optional `NotificationPreference` instance. Defaults to `null`. |
| `notify(notification)` | `Future<void>` | Convenience method — calls `NotificationManager().send(this, notification)`. |

### NotificationChannel (abstract)

Implement to create a custom channel.

| Member | Type | Description |
|:-------|:-----|:------------|
| `name` | `String` | Channel identifier (e.g., `'database'`, `'push'`). |
| `isAvailable` | `bool` | Whether the channel is configured and available. |
| `send(notifiable, notification)` | `Future<void>` | Deliver the notification through this channel. |

## Channels

### DatabaseChannel (`'database'`)

Stores notifications via `POST /notifications`. Reads `toDatabase()` from the notification. Returns early if `toDatabase()` returns `null`.

### PushChannel (`'push'`)

Sends push via the configured `PushDriver`. Uses `toPush()` from the notification. Skipped if `isAvailable` is `false` (no driver configured or not opted in).

## PushDriver

### PushDriver (abstract)

| Member | Type | Description |
|:-------|:-----|:------------|
| `name` | `String` | Driver identifier (e.g., `'onesignal'`). |
| `isSupported` | `bool` | Whether push is supported on this platform. |
| `permissionState` | `PushPermissionState` | Current permission state. |
| `isOptedIn` | `bool` | Whether user is opted in. |
| `initialize(config)` | `Future<void>` | Initialize driver with config map. |
| `login(externalId)` | `Future<void>` | Associate push subscription with user ID. |
| `logout()` | `Future<void>` | Remove user association from push subscription. |
| `requestPermission()` | `Future<bool>` | Show permission dialog. Returns grant result. |
| `optIn()` | `Future<void>` | Opt user in to push. |
| `optOut()` | `Future<void>` | Opt user out of push. |
| `setTags(tags)` | `Future<void>` | Set targeting tags for segmentation. |
| `removeTag(key)` | `Future<void>` | Remove a specific targeting tag. |
| `onNotificationReceived` | `Stream<PushNotificationEvent>` | Fires when notification arrives in foreground. |
| `onNotificationClicked` | `Stream<PushNotificationEvent>` | Fires when user taps notification. |
| `onPermissionChanged` | `Stream<PushPermissionState>` | Fires when permission state changes. |

`PushPermissionState` enum values: `notDetermined`, `denied`, `authorized`, `provisional`.

### OneSignalDriver

The built-in implementation. Auto-created by `NotificationServiceProvider` when `notifications.push.driver` is `'onesignal'`.

## Models

### DatabaseNotification

Represents an in-app notification from the backend.

| Property | Type | Description |
|:---------|:-----|:------------|
| `id` | `String` | Unique notification ID. |
| `type` | `String` | Notification type string (e.g., `'MonitorDownNotification'`). |
| `title` | `String` | Display title. |
| `body` | `String` | Display message. |
| `data` | `Map<String, dynamic>` | Full data payload from backend. |
| `actionUrl` | `String?` | Optional deep link URL. |
| `createdAt` | `DateTime` | When notification was created. |
| `readAt` | `DateTime?` | When notification was read (`null` if unread). |
| `isRead` | `bool` (getter) | `true` if `readAt != null`. |

Factory: `DatabaseNotification.fromMap(map)` — parses Laravel notification response shape.

### PaginatedNotifications

Wraps the Laravel paginated response (`data` + `meta` keys).

| Property | Type | Description |
|:---------|:-----|:------------|
| `data` | `List<DatabaseNotification>` | Notifications for current page. |
| `currentPage` | `int` | Current page number. |
| `lastPage` | `int` | Last available page number. |
| `perPage` | `int` | Items per page. |
| `total` | `int` | Total notification count. |
| `hasMorePages` | `bool` | Whether more pages are available. |
| `isEmpty` | `bool` | Whether the result has no items. |

### PushMessage

Fluent builder for push notification content.

```dart
PushMessage()
  .heading('Alert Title')
  .content('Alert body text')
  .data({'key': 'value'})
  .url('/deep/link');
```

| Method | Parameters | Description |
|:-------|:-----------|:------------|
| `heading(value)` | `String` | Set notification title. Returns `this`. |
| `content(value)` | `String` | Set notification body. Returns `this`. |
| `data(value)` | `Map<String, dynamic>` | Set full data payload. Returns `this`. |
| `addData(key, value)` | `String key`, `dynamic value` | Add single key to data payload. Returns `this`. |
| `url(value)` | `String` | Set deep link URL. Returns `this`. |
| `toMap()` | — | Convert to `Map<String, dynamic>` (excludes null fields). |

### NotificationPreference

User-level channel preferences. Use `isEnabled(type, channel)` to gate channel delivery.

| Property | Type | Description |
|:---------|:-----|:------------|
| `pushEnabled` | `bool` | Global push toggle. Default `true`. |
| `emailEnabled` | `bool` | Global email toggle. Default `true`. |
| `inAppEnabled` | `bool` | Global in-app toggle. Default `true`. |
| `typePreferences` | `Map<String, ChannelPreference>` | Per-type overrides keyed by notification type string. |

`isEnabled(notificationType, channel)` returns `false` if either the global toggle or the type-specific toggle is disabled. Returns `true` by default if no type-specific preference exists.

## Configuration

Add to `lib/config/notifications.dart` and register via `configFactories`:

```dart
'notifications': {
  'push': {
    'driver': env('PUSH_DRIVER', 'onesignal'),      // 'onesignal' is the only built-in driver
    'app_id': env('ONESIGNAL_APP_ID', ''),           // OneSignal app ID
    'safari_web_id': env('ONESIGNAL_SAFARI_ID', ''), // Safari web push ID (web only)
    'notify_button_enabled': false,                  // Show OneSignal bell widget (web)
  },
  'database': {
    'enabled': true,
    'polling_interval': 30,   // Seconds between background fetches
  },
  'mail': {
    'enabled': false,         // Mail channel requires backend handler
  },
  'soft_prompt': {
    // Soft prompt dialog configuration (see PushPromptDialog)
  },
},
```

## Service Provider Setup

Register `NotificationServiceProvider` in `config/app.dart`. It is NOT auto-registered.

```dart
// config/app.dart
'providers': [
  // ...existing providers...
  (app) => NotificationServiceProvider(app),
],
```

`NotificationServiceProvider.register()` binds `NotificationManager` singleton. `boot()` reads config, creates the `OneSignalDriver`, and initializes it.

## Usage Patterns

### Basic Setup & Lifecycle

```dart
import 'package:magic_notifications/magic_notifications.dart';

// After user login
await Notify.initializePush(user.id.toString());
Notify.startPolling();

// On app background (e.g., in AppLifecycleListener)
Notify.pausePolling();

// On app foreground
Notify.resumePolling();

// On logout
await Notify.logoutPush();
Notify.stopPolling();
await Auth.logout();
```

### Display Notifications in UI

```dart
StreamBuilder<List<DatabaseNotification>>(
  stream: Notify.notifications(),
  builder: (context, snapshot) {
    final notifications = snapshot.data ?? [];
    final unread = notifications.where((n) => !n.isRead).length;

    return Badge(
      count: unread,
      child: Icon(Icons.notifications),
    );
  },
)
```

### Paginated Notification List

```dart
final result = await Notify.fetchPaginatedNotifications(page: 1, perPage: 20);

for (final notification in result.data) {
  print('${notification.title}: ${notification.body}');
}

if (result.hasMorePages) {
  final nextPage = await Notify.fetchPaginatedNotifications(
    page: result.currentPage + 1,
    perPage: 20,
  );
}
```

### Listening to Push Events

```dart
// In a controller or service provider boot()
Notify.manager.pushDriver.onNotificationClicked.listen((event) {
  final url = event.data['url'] as String?;
  if (url != null) {
    Route.to(url);
  }
});
```

### Custom Channel Registration

```dart
// In NotificationServiceProvider.boot() or AppServiceProvider.boot()
Notify.manager.registerChannel(MyCustomChannel());
```

## Gotchas

| Mistake | Fix |
|:--------|:----|
| `NotificationServiceProvider` not registered | It is NOT auto-registered. Add `(app) => NotificationServiceProvider(app)` to `config/app.dart`. |
| `Notify.initializePush()` throws `PUSH_DRIVER_NOT_CONFIGURED` | `NotificationServiceProvider` must be registered and `notifications.push.app_id` must be non-empty in config. |
| `Notify.manager.pushDriver` accessed before push init | Throws `NotificationException`. Guard with `try/catch` or ensure provider is registered. |
| Push login called before permission granted | `initializePush()` silently defers the external ID association. It will not throw, but the device won't be linked until a subscription is active. |
| Polling not stopped on logout | Always call `Notify.stopPolling()` on logout — the timer holds a reference to `NotificationManager` and will keep fetching. |
| `notifications()` stream never emits | The stream emits current cache immediately to each new listener. If the cache is empty, subscribe then call `fetchNotifications()` to trigger the first emission. |
| `markAsRead()` / `deleteNotification()` reverts | These are optimistic — if the backend call fails, local state is reverted. UI will flash back to previous state. |
| `via()` returns unknown channel name | `NotificationManager.send()` logs a warning but does not throw. The notification is silently skipped for that channel. |
| `toDatabase()` returns `null` for `'database'` channel | `DatabaseChannel` skips delivery without error. Ensure `toDatabase()` returns a map with `title` and `body` keys. |
| `PushNotSupportedException` on unsupported platform | Check `Notify.manager.pushDriver.isSupported` before calling push methods. |
