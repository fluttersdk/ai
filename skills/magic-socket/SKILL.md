---
name: magic-socket
description: "Receive real-time broadcasts in a Magic app with the Echo facade, Reverb and null drivers, private and presence channels, and Echo.fake in tests."
version: 1.0.0
when_to_use: "Use when code imports package:magic_socket or touches Echo, BroadcastServiceProvider, broadcastingConfig, ListensToBroadcasts, BroadcastListeners, FakeBroadcastManager or X-Socket-ID in a Magic app."
---

# magic_socket

Real-time broadcasting for a Magic app. The `Echo` facade subscribes to public, private and presence channels through a `BroadcastManager`: `ReverbBroadcastDriver` speaks the Pusher protocol to Laravel Reverb and reconnects by itself, `NullBroadcastDriver` (the default) accepts every call and delivers nothing. `BroadcastServiceProvider` binds the manager, starts the connection at boot and adds the `X-Socket-ID` header to `Http` requests. `ListensToBroadcasts` shares one private channel between controllers, and `Echo.fake` tests it.

This skill covers `magic_socket` only. The Magic framework itself (container, providers, `Http`, `MagicController`, config) is the `magic-framework` skill.

## Install

```bash
flutter pub add magic_socket
dart run magic:dowel plugin:install magic_socket
```

Requires Dart >=3.13, Flutter >=3.47 and `magic` ^1.0.0. The installer adds `BroadcastServiceProvider` to `lib/config/app.dart` and `() => broadcastingConfig` to the `configFactories` of `lib/main.dart`; it publishes no config. Import only `package:magic_socket/magic_socket.dart`. Set `.env`:

```dotenv
BROADCAST_CONNECTION=reverb
REVERB_HOST=localhost
REVERB_PORT=8080
REVERB_SCHEME=ws
REVERB_APP_KEY=
```

`BROADCAST_CONNECTION` defaults to `null`. Private and presence auth is `POST /broadcasting/auth` through `Http`, and `X-Socket-ID` needs a network driver, so the app lists `NetworkServiceProvider`.

## Channel rules

1. Use `Echo.channel` for public, `Echo.private` for private and `Echo.join` for presence. Pass the bare name (`user.1`); the driver adds `private-` or `presence-`.
2. `Echo.listen(channel, event, cb)` is a public-channel shorthand. A private event is `Echo.private(name).listen(event, cb)`.
3. A second `listen` for one event on one channel replaces the first. Two controllers wanting one event use `BroadcastListeners`, not two `listen` calls.
4. Handlers must be idempotent: the server can repeat a frame, including a retried queued job.
5. Refetch missed data when `channel.onSubscriptionChanged` turns `true`. `Echo.onReconnect` fires after the subscribe was sent, before the server confirms it.
6. `Echo.connect()` is idempotent and joins an attempt in flight. Boot does not wait for the socket, so read `Echo.socketId` only after awaiting `Echo.connect()`.
7. A 401 or 403 on the auth route is logged and not retried; a missing response or a 5xx is retried with backoff (`BroadcastAuthException.isRetryable`).

## Config rules

1. Register `broadcastingConfig` in `configFactories`, never `configs`: it calls `env()`, which needs `.env` loaded.
2. `auth_endpoint`, `reconnect`, `max_reconnect_delay` (30000 ms), `activity_timeout` (120 s) and `connection_timeout` (15 s) are not env keys; change them by wrapping the factory.
3. An unknown connection or driver name resolves to the null driver. Register a custom driver with `BroadcastManager.extend(name, factory)` before the provider that resolves it.
4. `SocketIdInterceptor` is added only for a connection other than `null` and only when a network driver is bound; never add it by hand.

## Listener rules

1. `ListensToBroadcasts` replaces core's removed `make:controller --broadcasts`; there is no generator. Keys are `'<alias>:<event>'`.
2. Declare each alias once, `BroadcastListeners.channel('team', () => id == null ? null : 'teams.$id')`, and call `await BroadcastListeners.sync()` at startup and on every auth change.
3. `startListening()` runs from `onInit`. A controller used only through `.instance` calls it from its constructor.
4. A `null` alias name leaves that channel; `sync()` disconnects only when no alias is live. A standalone `AuthChannelSubscription` disconnects on its own `null` name unless `disconnectOnTeardown: false`.

## Recipes

Subscribe and react:

```dart
import 'package:magic_socket/magic_socket.dart';

void watchOrders() {
  Echo.channel('orders').listen('OrderShipped', (event) {
    print('Order ${event.data['id']} has shipped');
  });
}
```

Join a presence channel:

```dart
import 'package:magic_socket/magic_socket.dart';

void joinRoom() {
  final room = Echo.join('room.1');

  room.onJoin.listen((member) => print('${member['name']} joined'));
  room.onLeave.listen((member) => print('${member['name']} left'));
}
```

A controller on a shared channel:

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class MonitorController extends MagicController with ListensToBroadcasts {
  @override
  Map<String, void Function(BroadcastEvent)> get listeners => {
    'team:check.recorded': (event) => print(event.data),
  };
}

Future<void> declareTeamChannel(int? teamId) async {
  BroadcastListeners.channel('team', () => teamId == null ? null : 'teams.$teamId');
  await BroadcastListeners.sync();
}
```

## Testing

Import `package:magic_socket/testing.dart`. In `setUp()` call `MagicApp.reset()` and `Magic.flush()`. `Echo.fake()` returns a `FakeBroadcastManager`; assert with `assertSubscribed`, `assertNotSubscribed`, `assertListening`, `assertNotListening`, `assertConnected`, `assertDisconnected` and `assertInterceptorAdded`. Private and presence names carry their prefix in assertions (`private-user.1`). `assertSubscribed` does not prove a handler exists, so use `assertListening`, and `fake.dispatch(channel, event, data)` to run it with a decoded payload. `fake.driver.setSubscribed(name, true)` stands in for the server's confirmation.

`Echo.fake`, the `BroadcastListeners` registry and `BroadcastManager.extend` are statics that `Magic.flush()` does not clear. In `tearDown()` call `Echo.unfake()`, `BroadcastListeners.reset()` and `BroadcastManager.resetDrivers()`.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic_socket/magic_socket.dart';
import 'package:magic_socket/testing.dart';

void main() {
  tearDown(() => Echo.unfake());

  test('a handler receives a frame', () {
    final FakeBroadcastManager fake = Echo.fake();
    final received = <BroadcastEvent>[];

    Echo.private('user.1').listen('ProfileUpdated', received.add);
    fake.dispatch('private-user.1', 'ProfileUpdated', {'name': 'Ada'});

    expect(received, hasLength(1));
  });
}
```
