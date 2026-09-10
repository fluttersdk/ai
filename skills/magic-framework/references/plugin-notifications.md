<!-- magic_notifications v0.3.0 | Updated: 2026-09-09 -->

# magic_notifications Plugin

Push and in-app notification system for Magic Framework: the `Notify` facade, database (in-app) notifications with real-time streaming, OneSignal push integration, the notification UI (bell, list, preference matrix), and two ways to learn about a new row: a broadcast socket (preferred, 0.0.3+) or background polling (the fallback).

## Contents

- [Installation](#installation)
- [CLI commands and MCP tools](#cli-commands-and-mcp-tools)
- [Notify Facade API](#notify-facade-api)
- [Contracts](#contracts)
- [Channels](#channels)
- [PushDriver](#pushdriver)
- [Models](#models)
- [UI: views, controllers, registry](#ui-views-controllers-registry)
- [Configuration](#configuration)
- [Service Provider Setup](#service-provider-setup)
- [Usage Patterns](#usage-patterns)
- [Gotchas](#gotchas)

## Installation

```bash
flutter pub add magic_notifications

# Register the plugin's artisan provider with the app dispatcher (once)
dart run magic:artisan plugin:install magic_notifications

# Scaffold lib/config/notifications.dart, inject the provider, wire the config factory
dart run magic:artisan notifications:install

# Confirm the install
dart run magic:artisan notifications:doctor
```

Requires `magic ^0.0.6` (for `Echo.connection`, the accessor the realtime path needs to tell an open connection from a closed one).

### Two iOS pieces no command can install

Push works without both of these, which is why they are easy to miss and why `notifications:doctor` warns about them: a build with no Notification Service Extension delivers notifications normally and quietly reports no confirmed deliveries, no rich media and no badge counts. The absence looks like the product working.

1. An **App Group** on the Runner target, named `group.<bundle.id>.onesignal`.
2. A **Notification Service Extension** target carrying that same App Group.

Both add or change an Xcode target, which a pub package cannot do. The steps are in the package's `doc/getting-started/installation.md`. They fail independently: an extension with no shared group gives rich media and still no confirmed delivery, because the container is how the extension hands what it saw back to the app.

**Testing the cold-start path needs a profile or release build.** iOS refuses to launch a debug Flutter build from a link or the home screen, and OneSignal documents that on iOS in Debug a force-closed app opened from a notification never registers the click listener. A cold tap that appears to do nothing in Debug is usually this rather than the wiring.

## CLI commands and MCP tools

Seven commands, all through the app's artisan dispatcher:

| Command | Purpose |
|:--------|:--------|
| `notifications:install` | Scaffold config, inject `NotificationServiceProvider`, wire platform setup |
| `notifications:configure` | Reconfigure channels and platforms interactively |
| `notifications:channels` | Report the configured channels and their status |
| `notifications:doctor` | Diagnose install, config presence, OneSignal App ID format, `polling_interval` range, platform setup |
| `notifications:test` | Send a test notification |
| `notifications:publish` | Publish views for customization |
| `notifications:uninstall` | Remove the plugin scaffolding |

Two of them are exposed as read-only MCP tools, so an agent can diagnose without mutating anything: `notifications_doctor` (takes `verbose`) and `notifications_channels`. The mutating commands (install, configure, test, uninstall, publish) are deliberately absent from the MCP surface. Run `dart run magic:artisan mcp:install` once to register them with the client.

## Notify Facade API

All methods are accessed via the static `Notify` facade after importing `package:magic_notifications/magic_notifications.dart`.

### Sending

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.send(notifiable, notification)` | `Notifiable notifiable`, `Notification notification` | `Future<void>` | Send notification to entity through channels defined by `notification.via()`. |

### Database (In-App) Notifications

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.notifications()` | none | `Stream<List<DatabaseNotification>>` | Broadcast stream: emits current cache immediately, then re-emits on every fetch/read/delete. |
| `Notify.fetchNotifications()` | none | `Future<void>` | Fetch from `GET /notifications` and push updated list to stream. |
| `Notify.refreshNotifications()` | none | `Future<void>` | Alias for `fetchNotifications()`. |
| `Notify.fetchPaginatedNotifications({page, perPage})` | `int page = 1`, `int perPage = 15` | `Future<PaginatedNotifications>` | Paginated response with meta (current_page, last_page, total). **Throws `NotificationException` on a failed read** (0.1.0+); it does not answer an empty page, which a caller cannot tell from an empty inbox. |
| `Notify.unreadCount()` | none | `Future<int>` | Fetch unread count from `GET /notifications/unread-count`. |
| `Notify.markAsRead(id)` | `String id` | `Future<void>` | Optimistically mark read locally, then `POST /notifications/{id}/read`. Reverts on failure. |
| `Notify.markAllAsRead()` | none | `Future<void>` | Optimistically mark all read locally, then `POST /notifications/read-all`. Reverts on failure. |
| `Notify.deleteNotification(id)` | `String id` | `Future<void>` | Optimistically remove locally, then `DELETE /notifications/{id}`. **Rolls the row back and rethrows on failure** (0.1.0+), so a caller can tell a delete that worked from one that did not. |

### Push Notifications

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.initializePush(userId)` | `String userId` | `Future<void>` | Record the intent to be subscribed as `userId`, then reconcile it against the driver. Call after `Auth.login()`. A build with no push driver is a supported state: it no longer throws (0.1.0+). |
| `Notify.requestPushPermission()` | none | `Future<bool>` | Show system permission dialog. Returns `true` if granted. |
| `Notify.logoutPush()` | none | `Future<void>` | Drop the cached rows, clear the intent, unlink the device. Call before `Auth.logout()`. |
| `Notify.describePushUserUsing(resolver)` | `PushUserAttributesResolver?` | `void` | Register once how the app describes whoever signs in (email + tags). Nothing is sent until `notifications.push.share_user_attributes` is on, and it ships OFF. |
| `Notify.extend(name, factory)` | `String`, `PushDriver Function()` | `void` | Register a push driver under a name; the config's `push.driver` picks one. |
| `Notify.forgetDrivers()` | none | `void` | Drop every channel, registered driver and resolved instance. The test-isolation seam. |

### Polling

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.startPolling()` | none | `void` | Start 30-second polling. Fetches immediately on start. Idempotent. **No-op while realtime is live**, so it is safe to wire next to `startRealtime()` as the fallback. |
| `Notify.stopPolling()` | none | `void` | Stop polling and destroy timer. Call on logout. |
| `Notify.pausePolling()` | none | `void` | Pause (timer keeps running, fetches are skipped). Use on app background. |
| `Notify.resumePolling()` | none | `void` | Resume paused polling. Fetches immediately on resume. |
| `Notify.isPolling` | none | `bool` | Whether the periodic timer is currently armed. |

### Realtime (0.0.3+)

Notification state can arrive over the app's broadcast socket instead of being polled for. This is the preferred path; polling stays as the fallback for a deployment with no broadcast driver.

| Method | Parameters | Return Type | Description |
|:-------|:-----------|:------------|:------------|
| `Notify.startRealtime()` | `{String? channel, String event = 'notification.created'}` | `Future<bool>` | Subscribe to the notifiable's private channel and apply each frame to the cache. Returns `false` (changing nothing) when the app has no broadcast driver, so the caller keeps polling. |
| `Notify.stopRealtime()` | none | `void` | Leave the channel and drop the connection watcher. Does NOT close the connection (it is shared) and does NOT restart polling. |
| `Notify.isRealtime` | none | `bool` | Whether state is currently arriving over a socket. |

`channel` has to come from the caller: this package has no user model and cannot know whose notifications these are. Laravel's default for a `Notifiable` that has not overridden `receivesBroadcastNotificationsOn()` is `App.Models.User.{id}`.

What a successful `startRealtime()` does, in order: connects only if no connection exists (magic's Reverb driver `connect()` is NOT idempotent, a second call leaks the first socket), subscribes and listens for the event exactly once, stops the poller, fetches the existing list ONCE (a socket carries only what happens next), and watches the connection so a drop falls back to polling and a reconnect lifts the fallback. It is idempotent per channel: the same channel is a no-op, a different one moves the subscription.

Requires `magic ^0.0.6` for `Echo.connection`, the public accessor that tells an open connection from a closed one.

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
| `notify(notification)` | `Future<void>` | Convenience method that calls `NotificationManager().send(this, notification)`. |

### NotificationChannel (abstract)

Implement to create a custom channel.

| Member | Type | Description |
|:-------|:-----|:------------|
| `name` | `String` | Channel identifier (e.g., `'database'`, `'push'`). |
| `isAvailable` | `bool` | Whether the channel is configured and available. |
| `send(notifiable, notification)` | `Future<void>` | Deliver the notification through this channel. |

## Channels

### DatabaseChannel (`'database'`)

`isAvailable` is always `true`, and `send()` is a **no-op**: it reads `toDatabase()`, returns early on `null`, and writes nothing. Database rows are created SERVER-side; the channel exists for API parity with Laravel and the client learns about a row by socket or poll. To create one from the client, `Http.post('/notifications', data: notification.toDatabase(user))` yourself.

### PushChannel (`'push'`)

Posts `toPush()` to a self-addressed endpoint that makes the platform emit a real push to the caller's own device. `isAvailable` is `_driver.isSupported && notifications.push.self_test_enabled`, and that key ships OFF (an absent or non-boolean value reads as off), so the channel sends nothing until a deployment switches both halves on (the backend carries the same switch and answers 501 while it is off). It refuses a `Notifiable` that is not the authenticated user: the endpoint derives the recipient from the session.

## PushDriver

### PushDriver (abstract)

| Member | Type | Description |
|:-------|:-----|:------------|
| `name` | `String` | Driver identifier (e.g., `'onesignal'`). |
| `isSupported` | `bool` | Whether push is supported on this platform. |
| `permissionState()` | `Future<PushPermissionState>` | Current permission state. **Async since 0.1.0**: both platforms answer asynchronously. |
| `isOptedIn` | `bool` | Whether user is opted in. |
| `subjectGuard` / `mayDisplay(data)` | `bool Function(Map)?` / `bool` | The guard that keeps a push addressed to the previous account off this device. |
| `initialize(config)` | `Future<void>` | Initialize driver with config map. |
| `login(externalId)` / `logout()` | `Future<void>` | Attach / detach the external id on the subscription. |
| `currentExternalId()` / `currentSubscriptionId()` | `Future<String?>` | ABSTRACT since 0.1.0; the reconciler reads what the device is actually subscribed as. |
| `requestPermission()` | `Future<bool>` | Show permission dialog. Returns grant result. |
| `canRaisePermissionRequest()` | `Future<bool>` | Whether a request would actually show something. Defaulted. |
| `canOpenPlatformSettings` | `bool` | Defaults to `false`; mobile overrides it. |
| `optIn()` / `optOut()` | `Future<void>` | Opt the user in or out. |
| `setTags(tags)` / `removeTag(key)` / `removeTags(keys)` | `Future<void>` | Targeting tags. `removeTags` is defaulted (a loop over `removeTag`). |
| `addEmail(email)` / `removeEmail(email)` | `Future<void>` | Email subscription, both defaulted. |
| `reachability()` | `Future<PushReachability>` | `unavailable` / `blocked` / `off` / `on`, without triggering the OS dialog. Defaulted. |
| `onNotificationReceived` | `Stream<PushNotificationEvent>` | Fires when a notification arrives in the foreground. |
| `onNotificationClicked` | `Stream<PushNotificationEvent>` | Fires when the user taps a notification. |
| `onPermissionChanged` | `Stream<PushPermissionState>` | Fires when the permission state changes. |
| `onIdentityChanged` | `Stream<PushIdentityChange>` | ABSTRACT since 0.1.0; the SDK's own view of external id, subscription id and opt-in. |

`PushPermissionState` enum values: `notDetermined`, `denied`, `authorized`, `provisional`. A custom driver written against 0.0.3 does not compile on 0.1.0+ until it implements the three members marked ABSTRACT.

On the manager rather than the driver: `Notify.manager.onPushClicked` and `onPushReceived` republish every driver's events on streams the manager owns from construction, so a listener attached before any driver exists still receives later events. That is the stream `magic_deeplink` bridges.

Both are BROADCAST streams, which drop what they publish to nobody, so "the stream exists from construction" never meant "the stream remembers". `onPushClicked` alone is now an exception: it holds clicks until the first listener and replays them once, because the tap that COLD-STARTS the app is drained inside `driver.initialize()`, which this package's own provider awaits in `boot()`, and a consumer that lists notifications before `magic_deeplink` subscribes only afterwards. Without the buffer that tap opened the app on its initial route with no exception and no log. The replay is one-shot: a second listener arriving later is not handed the same tap again. `onPushReceived` has no buffer and needs none, since nothing navigates off it.

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

Factory: `DatabaseNotification.fromMap(map)`, which parses Laravel notification response shape.

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
| `toMap()` | none | Convert to `Map<String, dynamic>` (excludes null fields). |

### NotificationPreference

User-level channel preferences. Use `isEnabled(type, channel)` to gate channel delivery.

| Property | Type | Description |
|:---------|:-----|:------------|
| `pushEnabled` | `bool` | Global push toggle. Default `true`. |
| `emailEnabled` | `bool` | Global email toggle. Default `true`. |
| `inAppEnabled` | `bool` | Global in-app toggle. Default `true`. |
| `typePreferences` | `Map<String, ChannelPreference>` | Per-type overrides keyed by notification type string. |

`isEnabled(notificationType, channel)` returns `false` if either the global toggle or the type-specific toggle is disabled. Returns `true` by default if no type-specific preference exists.

## UI: views, controllers, registry

The package owns the notification UI since 0.1.0. `magic_starter` used to ship its own copies and no longer exports any of them.

| Symbol | Shape |
|:-------|:------|
| `NotificationDropdown` | The bell. `{required notificationStream, onMarkAsRead, onMarkAllAsRead, onNotificationTap, onViewAll}` plus five className overrides (`panelClassName`, `triggerClassName`, `triggerIconClassName`, `badgeClassName`, `badgeTextClassName`). |
| `NotificationsListView` | `{onMarkAsRead, onMarkAllAsRead, onDelete, onNavigate, perPage = 15}`. `onDelete` is `Future<bool> Function(String id)?` (0.2.0): `true` means the row is gone and the page reloads, `false` means the host declined and nothing is re-read. The per-row delete control renders only when it is non-null. |
| `NotificationPreferencesView` | `{pushProvisioned, backRoute}`. The per-type channel matrix plus a bulk row per channel. |
| `NotificationsListController` | `.instance`; owns the page and its rows. `loadPage(int page)`, `refresh()`, `currentPage`. |
| `NotificationPreferencesController` | `.instance`; `fetchPreferences()`, `updateTypePreference(String type, String channel, bool isEnabled)`, `updateChannelAcrossTypes(String channel, bool isEnabled)`, plus `matrixNotifier`, `pushProvisionedNotifier`, `bulkSavingNotifier`. |

`Notify.view` is a `NotificationViewRegistry` seeding `notifications.list` and `notifications.preferences` on first read. API: `register`, `registerDefault`, `has`, `hasOverride`, `make`, `registerLayout`, `registerModal`, `slot`, `buildSlot`, `clear`; `Notify.forgetView()` drops the registry itself.

```dart
// Swap a screen.
Notify.view.register('notifications.preferences',
    () => const NotificationPreferencesView(backRoute: '/settings'));

// Say what one of the app's own notification types looks like.
Notify.view.slot(NotificationViewRegistry.typeIconSlotView, 'monitor_down',
    (context) => WIcon(Icons.error_outline, className: 'text-lg text-red-500'));
```

Ask `hasOverride(key)`, not `has(key)`, before installing your own default: reading `Notify.view` is what seeds the package's screens, so `has` is true from the first read. Register `'default'` (`NotificationViewRegistry.typeIconFallbackSlot`) as the slot name to answer for every remaining type.

The package ships no translation catalogue: the host supplies every `notifications.*` key, and `Translator.get` renders a missing key as the key itself.

## Configuration

Scaffolded to `lib/config/notifications.dart` by `notifications:install` and registered via `configFactories`. Every switch below ships OFF, and an absent key reads as off.

```dart
'notifications': {
  'push': {
    'driver': 'onesignal',              // the only built-in driver
    'app_id': '<onesignal-app-id>',
    'service_worker_path': '...',       // web
    'service_worker_scope': '...',      // web
    'notify_button_enabled': false,     // OneSignal bell widget (web)
    'self_test_enabled': false,         // gates PushChannel.send(); backend carries the same switch
    'auto_request_on_login': false,     // raise the OS prompt once after sign-in (think twice on web)
    'reprompt_after_hours': 0,          // the app's OWN reminder cadence; 0 means never
    'fallback_to_settings': true,       // mobile: a request on a denied device opens app settings
    'share_user_attributes': false,     // gates email + tags reaching OneSignal
  },
  'database': {
    'enabled': true,
    'polling_interval': 30,   // seconds; read at runtime since 0.2.0
  },
  'mail': {
    'enabled': false,         // mail channel requires a backend handler
  },
  'soft_prompt': {
    'enabled': true,          // read by pushPromptAdvice(); the dialog widget itself was removed in 0.1.0
    'title': 'Enable Notifications',
    'message': 'Stay updated with important alerts and updates',
  },
},
```

`Notify.manager.pushPromptAdvice({declinedAt})` answers whether the app's own reminder may be shown right now and what its button can accomplish; the package never stores the decline timestamp itself.

## Service Provider Setup

Register `NotificationServiceProvider` in `config/app.dart`. It is NOT auto-registered.

```dart
// config/app.dart
'providers': [
  // ...existing providers...
  (app) => NotificationServiceProvider(app),
],
```

`register()` binds the `NotificationManager` singleton under `'notifications'`. `boot()` resolves it back THROUGH the container (so a missing binding surfaces as magic's own diagnostic), registers `DatabaseChannel`, reads the persisted push intent BEFORE resolving a driver (resolving one attaches the receive listeners, and the SDK replays a cold-start tap while `initialize` runs), then resolves the driver through the manager's name-keyed registry: an explicitly set or `Notify.extend`-registered driver outranks the config, an absent `push.driver` is a quiet `null`, and a configured name nothing can serve is logged at error level and degrades rather than failing boot. With a driver it registers `PushChannel` and initializes it, and it always ends on one unconditional `reconcilePushIdentity()`, because a signed-out cold boot fires no auth event at all.

## Usage Patterns

### Basic Setup & Lifecycle

```dart
import 'package:magic_notifications/magic_notifications.dart';

// After user login. Ask for the socket first, then arm polling as the fallback:
// startPolling() is a no-op while realtime is live, so the caller does not have
// to know whether a socket happens to be up.
await Notify.initializePush(user.id.toString());
await Notify.startRealtime(channel: 'App.Models.User.${user.id}');
Notify.startPolling();

// On app background (e.g., in AppLifecycleListener)
Notify.pausePolling();

// On app foreground
Notify.resumePolling();

// On logout
await Notify.logoutPush();
Notify.stopRealtime();
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
// In a controller or service provider boot(). Listen on the MANAGER, not the
// driver: the manager owns these streams from construction, so this works
// before any driver has been resolved and survives one being swapped.
Notify.manager.onPushClicked.listen((event) {
  final url = event.data['url'] as String?;
  if (url != null) {
    MagicRoute.to(url);
  }
});
```

An app that also installs `magic_deeplink` gets this wiring for free: its provider bridges `onPushClicked` into the deep link handler chain.

### Custom Channel Registration

```dart
// In NotificationServiceProvider.boot() or AppServiceProvider.boot()
Notify.manager.registerChannel(MyCustomChannel());
```

## Gotchas

| Mistake | Fix |
|:--------|:----|
| `NotificationServiceProvider` not registered | It is NOT auto-registered. Add `(app) => NotificationServiceProvider(app)` to `config/app.dart`. |
| Expecting `Notify.initializePush()` to throw without a driver | It does not (0.1.0+). A build with no push driver is a supported state: the intent is recorded and reconciled against nothing. `Notify.manager.pushDriver` is the call that throws `NotificationException(code: 'PUSH_DRIVER_NOT_CONFIGURED')`; `pushDriverOrNull` is the quiet read. |
| Push login called before permission granted | `initializePush()` records the intent and reconciles it. It will not throw, but the device is not linked until a subscription is active. |
| Polling not stopped on logout | Always call `Notify.stopPolling()` on logout: the timer holds a reference to `NotificationManager` and keeps fetching. Pair it with `Notify.stopRealtime()`, which the manager does not do for you (only the caller knows the user is gone). |
| `startRealtime()` returned `false` and the bell stays empty | It returns `false` without changing anything when the app has no broadcast driver (a null `BROADCAST_CONNECTION`). That is why `startPolling()` is armed next to it: reporting success there would stop the poller and leave the bell permanently empty. |
| `startRealtime()` called without a channel | `channel` is required in practice: `null` or empty returns `false` immediately. The package has no user model and cannot derive the name. |
| `notifications()` stream never emits | The stream emits current cache immediately to each new listener. If the cache is empty, subscribe then call `fetchNotifications()` to trigger the first emission. |
| `markAsRead()` reverts | It is optimistic: a failed backend call reverts local state, so the UI flashes back. `deleteNotification()` reverts AND rethrows (0.1.0+), so a caller has to handle the throw. |
| `via()` returns an unknown channel name | `NotificationManager.send()` logs a warning and skips that channel. A channel that THROWS no longer stops the others: the first error is rethrown after every channel has had its turn. |
| `toDatabase()` returns `null` for the `'database'` channel | `DatabaseChannel` skips without error. It writes nothing either way: the row is created server-side. |
| Waiting for `PushNotSupportedException` | Removed in 0.1.0. The platform factory throws `UnsupportedPlatformException` (a `NotificationException`) instead of silently handing back the wrong driver. |
| Reaching for `PushPromptDialog` | Removed in 0.1.0; the package ships no prompt widget. Build your own and ask `Notify.manager.pushPromptAdvice(declinedAt: ...)` whether to show it. |
| `permissionState` read as a getter | It is `Future<PushPermissionState> permissionState()` since 0.1.0. A custom driver also has to implement `currentExternalId()`, `currentSubscriptionId()` and `onIdentityChanged`. |
| A raw `notifications.*` key rendering on screen | The package ships no catalogue; the host supplies every key. 0.1.0+ added `notifications.delete_failed`, and `magic_starter` adds three delete-confirmation keys. |
