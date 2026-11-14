---
name: magic-notifications
description: "Notifications for a Magic app with magic_notifications: the Notify facade, a backend-driven inbox, OneSignal push and realtime delivery."
version: 1.0.0
when_to_use: "Use when code imports package:magic_notifications or touches Notify, NotificationChannel, PushDriver, OneSignal push, push_state or a notifications:* dowel command in a Magic app."
---

# magic_notifications

Notifications for a Magic app. The backend creates inbox rows and the `Notify` facade reads them (`notifications()`, `fetchNotifications()`, `markAsRead`); `NotificationsListView`, `NotificationPreferencesView` and `NotificationDropdown` render them. Push goes through OneSignal (`OneSignalDriver` on iOS and Android, `OneSignalWebDriver` on web), and new rows arrive over a `magic_socket` channel with `NotificationPoller` as the fallback. The package has two channels, `database` and `push`, and no mail channel.

This skill covers `magic_notifications` only. The Magic framework itself (container, `Config`, `Http`, `Vault`, service providers) is the `magic-framework` skill; the socket layer is `magic_socket`, and routing a tapped push is `magic_deeplink`.

## Install

```bash
flutter pub add magic_notifications
dart run magic:dowel plugin:install magic_notifications
dart run magic:dowel notifications:install
dart run magic:dowel notifications:doctor
```

Requires Dart >=3.13, Flutter >=3.47 and `magic` ^1.0.0. `plugin:install` registers `NotificationServiceProvider` in `lib/config/app.dart` and the commands with dowel; the package has no executable, so a command exists only after it. `notifications:install` writes `lib/config/notifications.dart` and the platform files, and wires `lib/main.dart`. Import only the barrel: `package:magic_notifications/magic_notifications.dart`.

## Provider and config rules

1. Register `NotificationServiceProvider`: `boot()` registers `DatabaseChannel`, loads the persisted push intent, resolves the driver named by `notifications.push.driver`, registers `PushChannel` and initialises the driver when `notifications.push.app_id` is set. A build with no `driver` key is supported: everything except push keeps working.
2. `boot()` starts no polling. Start `Notify.startPolling()` and `startRealtime` from the authenticated layout, so nothing runs while nobody is signed in.
3. A blank `app_id` leaves the driver uninitialised and `reachability()` at `unavailable`. A failed initialisation does not stop boot; read `NotificationServiceProvider.pushInitializationError`.
4. A `driver` value nothing was registered under is logged at error level and push stays off. A driver of your own is `Notify.extend('name', () => MyDriver())` before the provider boots.
5. `polling_interval` is clamped to 5 to 600 seconds and read when the poller is built; a value that is not an `int` reads as 30. `notifications.database.enabled` and the `mail` and `soft_prompt.title` keys the stub writes are read by no runtime code.

## Channel rules

1. `Notification.via()` names channels; `Notify.send` skips an unregistered name with a logged warning and an unavailable channel silently, tries every channel, and rethrows the first error after the last. Never name `'mail'`: there is no mail channel.
2. `DatabaseChannel.send` does nothing, because the backend writes the row. Do not use it to create inbox rows from the client.
3. `PushChannel` is self-addressed and ships off. It posts to `POST /notifications/push-test`, so it can only page the signed-in user, and it is available only when the driver is supported and `notifications.push.self_test_enabled` is `true`. Send push to other people from your backend.
4. A `Notifiable` that is not the signed-in user makes `PushChannel` throw `NotificationException` (`PUSH_RECIPIENT_NOT_AUTHENTICATED_USER`); a failed answer throws `HTTP_<status>`.
5. `Notification` clashes with Flutter's widgets library: `import 'package:flutter/widgets.dart' hide Notification;`.

## Inbox rules

1. `fetchNotifications()` logs a failure and keeps the held list; `fetchPaginatedNotifications` throws `NotificationException` (`NOTIFICATIONS_FETCH_FAILED`, `NOTIFICATIONS_DECODE_FAILED`), so an empty page always means an empty inbox. `unreadCount()` returns `0` on any failure.
2. A row decodes only when `data` carries string `title` and `body`; one bad row fails the whole list.
3. The client sends `page` and `perPage` and reads `meta.current_page`, `last_page`, `per_page` and `total`. `unread-count` must answer `{"count": n}` at the top level: a `{"data": {"count": n}}` wrapper reads as `0`.
4. `markAsRead` and `markAllAsRead` change the held list first and refetch when the request throws. Magic's `Http` returns an error status as a `MagicResponse` instead of throwing, so an HTTP failure is not rolled back. `deleteNotification` restores the row and rethrows; a caller wanting silence adds a `catch`.
5. Signing out clears the held list. Call `Notify.logoutPush()` on sign-out and `Notify.initializePush` after sign-in, or the next person sees the previous person's rows.

## Push rules

1. The package declares no push identity. After sign-in call `Notify.initializePush('<prefix><id>')`; on sign-out `Notify.logoutPush()`. The id is forwarded unchanged and the backend addresses the device by the same string, so one prefix (`user_`) must hold on both sides; `notifications.push_state.external_id_prefix` has to match it. `magic_starter` already does this for its apps.
2. `requestPushPermission()` shows nothing once the OS has answered. Ask `reachability()` (`unavailable`, `blocked`, `off`, `on`) or `Notify.manager.pushPromptAdvice(declinedAt:)` first; `blocked` needs the OS or browser setting, and the app owns the decline timestamp.
3. A tapped push opens nothing. `onPushClicked` hands over `event.data`; routing is a `magic_deeplink` handler your app registers, or your own listener. Put the destination in OneSignal `setData` under `url`, `deep_link`, `link` or `uri`: `setUrl` is the Launch URL and never reaches the payload.
4. `Notify.pushState.watch()` reports device reachability to your backend. Nothing calls it for you, the provider included, so arm it once from a provider's `boot()`; it stays off until both `report_path` and `release_path` are set, and one alone logs an error. Call `release()` before `Auth.logout()`, because the release needs the token.
5. `describePushUserUsing` sends nothing until `share_user_attributes` is `true`. A tag written from a client is user-tamperable: never trust it for a plan, role or entitlement.
6. Web push on iOS Safari reaches nobody until the site is added to the Home Screen. The page loads the OneSignal script and must not call `OneSignal.init()`; the driver initialises from config.
7. iOS needs `aps-environment` `development` for Debug and Profile and `production` for Release; the installer writes both entitlements files and `notifications:doctor` reads them. The APNs key upload, the App Group and the Notification Service Extension stay manual.

## Realtime rules

1. `startRealtime(channel:)` returns `false` and changes nothing when `broadcasting.default` is unset, empty or `'null'`, or when `channel` is empty, so the caller keeps polling. It needs `magic_socket` registered.
2. Call `startPolling()` after it every time: polling is a no-op while the socket is live, and the manager arms its own stand-in poller while the channel is unsubscribed and stops it once the server confirms, refetching once.
3. The channel name is the caller's: `App.Models.User.{id}` for a Laravel notifiable. The event is `NotificationManager.realtimeEvent`, `notification.created`, and the backend must name it in `broadcastAs()`. A redelivered id replaces the held row.

## Screens rules

1. `Notify.view` seeds `notifications.list` and `notifications.preferences` on first read. `register` wraps or replaces one; ask `hasOverride(key)` rather than `has(key)`, which is true from the first read.
2. The package ships no translation catalogue. Add every `notifications.*` key the screens and `PushPrompt` use to each locale, or a key renders as itself.
3. `NotificationsListView.onDelete` returns `Future<bool>`: `true` reloads the page, `false` leaves it alone, a throw reloads.
4. `PushPromptHost` takes a `declinedVaultKey` of its own; it reads the value back as an ISO-8601 timestamp and treats anything else as never declined.

## Recipes

Declare the push identity and arm delivery on sign-in, and undo both on sign-out:

```dart
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

// Once, from a provider's boot() after auth is registered; nothing else calls it.
void armPushState() {
  Notify.pushState.watch();
}

Future<void> onSignIn(String userId) async {
  await Notify.initializePush('user_$userId');
  await Notify.startRealtime(channel: 'App.Models.User.$userId');
  Notify.startPolling();
}

Future<void> onSignOut() async {
  Notify.stopRealtime();
  Notify.stopPolling();
  if (Notify.pushState.isConfigured) await Notify.pushState.release();
  await Notify.logoutPush();
  await Auth.logout();
}
```

Define a notification the database and push channels both know about:

```dart
import 'package:magic_notifications/magic_notifications.dart';

class MonitorDownNotification extends Notification {
  @override
  List<String> via(Notifiable notifiable) => ['database', 'push'];

  @override
  Map<String, dynamic>? toDatabase(Notifiable notifiable) => {
    'title': 'Monitor down',
    'body': 'api.example.com is not responding',
  };

  @override
  PushMessage? toPush(Notifiable notifiable) {
    return PushMessage()
        .heading('Monitor down')
        .content('api.example.com is not responding')
        .url('/monitors/1');
  }
}
```

Ask before interrupting, then act on what the button can do:

```dart
import 'package:magic_notifications/magic_notifications.dart';

Future<void> remind(DateTime? declinedAt) async {
  final PushPromptAdvice advice = await Notify.manager.pushPromptAdvice(
    declinedAt: declinedAt,
  );

  if (!advice.show) return;

  switch (advice.action) {
    case PushPromptAction.request:
      await Notify.requestPushPermission();
    case PushPromptAction.openSettings:
      await Notify.openPushSettings();
    case PushPromptAction.instructions:
    case PushPromptAction.none:
      break;
  }
}
```

## Testing

No mocking library is needed. Boot Magic once with `Magic.init(configFactories: [])`, call `Notify.forgetDrivers()` in `setUp` because the manager is a process-wide singleton (`Notify.forgetView()` after registering a screen), and mock a channel or driver by extending `NotificationChannel` or `PushDriver`. `Http.fake` stubs the backend:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:magic_notifications/magic_notifications.dart';

void main() {
  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Magic.init(configFactories: []);
  });

  setUp(Notify.forgetDrivers);

  test('fetchNotifications fills the stream', () async {
    Http.fake(<String, MagicResponse>{
      'notifications': Http.response(<String, dynamic>{
        'data': [
          {
            'id': '1',
            'type': 'monitor_down',
            'data': {'title': 'Monitor down', 'body': 'api.example.com'},
            'read_at': null,
            'created_at': '2026-11-14T10:30:00Z',
          },
        ],
      }),
    });

    await Notify.fetchNotifications();

    expect(await Notify.notifications().first, hasLength(1));
  });
}
```

`PushChannel` tests set `Config.set('notifications.push.self_test_enabled', true)` first, since the channel ships off.
