<!-- magic_socket v1.0.0 | Updated: 2026-11-14 -->

# magic_socket Plugin

Real-time broadcasting for a Magic app: the `Echo` facade, `BroadcastManager`, the Reverb (Pusher protocol) and null drivers, `BroadcastListeners`, `ListensToBroadcasts`, `AuthChannelSubscription`, `SocketIdInterceptor` and `FakeBroadcastManager`. They lived in core `magic` up to 0.0.41; core 1.0.0 removed them, together with `make:controller --broadcasts` and the installer's `--without-broadcasting`.

## Contents

- [Installation](#installation)
- [Echo Facade API](#echo-facade-api)
- [Channels](#channels)
- [Configuration](#configuration)
- [Shared channels (BroadcastListeners)](#shared-channels-broadcastlisteners)
- [Testing](#testing)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_socket: ^1.0.0
```

Requires Dart >=3.13, Flutter >=3.47 and `magic ^1.0.0`.

```bash
flutter pub add magic_socket
dart run magic:dowel plugin:install magic_socket
```

The installer adds `BroadcastServiceProvider` to `lib/config/app.dart` and `() => broadcastingConfig` to the `configFactories` of `lib/main.dart`; it publishes no config. Import only `package:magic_socket/magic_socket.dart`. The provider binds the manager, connects at boot (not for the `null` connection) and, when a network driver is bound, adds `SocketIdInterceptor` so every `Http` request carries `X-Socket-ID`; list `NetworkServiceProvider` too.

## Echo Facade API

| Member | Return type | Notes |
|:-------|:------------|:------|
| `Echo.channel(name)` | `BroadcastChannel` | Public channel. |
| `Echo.private(name)` | `BroadcastChannel` | Private; the driver adds `private-` and authenticates with `POST /broadcasting/auth` through `Http`. |
| `Echo.join(name)` | `BroadcastPresenceChannel` | Presence; exposes `members`, `onJoin`, `onLeave`. |
| `Echo.listen(channel, event, callback)` | `BroadcastChannel` | Public-channel shorthand. A private event is `Echo.private(name).listen(event, cb)`. |
| `Echo.leave(name)` | `void` | Unsubscribe. |
| `Echo.connect()` / `Echo.disconnect()` | `Future<void>` | `connect` is idempotent and joins an attempt in flight. |
| `Echo.connection` | `BroadcastDriver` | The resolved default driver. |
| `Echo.socketId` | `String?` | Read only after awaiting `Echo.connect()`. |
| `Echo.connectionState` | `Stream<BroadcastConnectionState>` | `connecting`, `connected`, `disconnected`, `reconnecting`. |
| `Echo.onReconnect` | `Stream<void>` | Fires after the subscribe was sent, before the server confirms it. |
| `Echo.addInterceptor(interceptor)` | `void` | A `BroadcastInterceptor` (`onSend`, `onReceive`, `onError`). |
| `Echo.manager` | `BroadcastManager` | `BroadcastManager.extend(name, factory)` registers a custom driver before the provider that resolves it. |
| `Echo.fake()` / `Echo.unfake()` | `FakeBroadcastManager` / `void` | Testing. |

A `BroadcastEvent` carries `event`, `channel`, `data` (decoded map) and `receivedAt`. A channel exposes `listen`, `stopListening`, `events`, `name`, `isSubscribed` and `onSubscriptionChanged`.

## Channels

Pass the bare name (`user.1`); the driver adds the prefix. A second `listen` for one event on one channel replaces the first, so two controllers wanting one event use `BroadcastListeners`. Handlers must be idempotent (the server can repeat a frame). Refetch missed data when `onSubscriptionChanged` turns `true`. A 401 or 403 on the auth route is logged and not retried; a missing response or a 5xx is retried with backoff (`BroadcastAuthException.isRetryable`). `ReverbBroadcastDriver` reconnects by itself (exponential backoff with jitter, Pusher close codes decide retry); `NullBroadcastDriver` accepts every call and delivers nothing.

## Configuration

Register `broadcastingConfig` in `configFactories`, never `configs` (it calls `env()`). `.env` keys: `BROADCAST_CONNECTION` (`null` by default, or `reverb`), `REVERB_HOST`, `REVERB_PORT`, `REVERB_SCHEME`, `REVERB_APP_KEY`. `auth_endpoint`, `reconnect`, `max_reconnect_delay` (30000 ms), `activity_timeout` (120 s) and `connection_timeout` (15 s) are not env keys; change them by wrapping the factory. An unknown connection or driver name resolves to the null driver.

## Shared channels (BroadcastListeners)

`ListensToBroadcasts` replaces the removed `make:controller --broadcasts`; there is no generator. Keys are `'<alias>:<event>'`.

```dart
import 'package:magic/magic.dart';
import 'package:magic_socket/magic_socket.dart';

class MonitorController extends MagicController with ListensToBroadcasts {
  @override
  Map<String, void Function(BroadcastEvent)> get listeners => {
    'team:check.recorded': (event) => print(event.data),
  };
}

BroadcastListeners.channel('team', () => teamId == null ? null : 'teams.$teamId');
await BroadcastListeners.sync();
```

Declare each alias once, and call `sync()` at startup and on every auth change. `startListening()` runs from `onInit`; a controller used only through `.instance` calls it from its constructor. A `null` alias name leaves that channel, and `sync()` disconnects only when no alias is live. A standalone `AuthChannelSubscription(channelName:, listeners:, onReconnect:)` disconnects on its own `null` name unless `disconnectOnTeardown: false`.

## Testing

Import `package:magic_socket/testing.dart`. `Echo.fake()` returns a `FakeBroadcastManager` with `assertSubscribed`, `assertNotSubscribed`, `assertListening`, `assertNotListening`, `assertConnected`, `assertDisconnected` and `assertInterceptorAdded`; private and presence names carry their prefix (`private-user.1`). `fake.dispatch(channel, event, data)` runs a handler with a decoded payload; `fake.driver.setSubscribed(name, true)` stands in for the server's confirmation. `Echo.fake`, the `BroadcastListeners` registry and `BroadcastManager.extend` are statics that `Magic.flush()` does not clear: in `tearDown()` call `Echo.unfake()`, `BroadcastListeners.reset()` and `BroadcastManager.resetDrivers()`.

```dart
tearDown(() => Echo.unfake());

test('a handler receives a frame', () {
  final FakeBroadcastManager fake = Echo.fake();
  final received = <BroadcastEvent>[];

  Echo.private('user.1').listen('ProfileUpdated', received.add);
  fake.dispatch('private-user.1', 'ProfileUpdated', {'name': 'Ada'});

  expect(received, hasLength(1));
});
```

## Gotchas

| Mistake | Fix |
|:--------|:----|
| `Echo` call with no provider | Register `BroadcastServiceProvider`; it is not auto-registered. |
| `broadcastingConfig` under `configs` | Use `configFactories`. |
| Reading `Echo.socketId` right after boot | Boot does not wait for the socket; await `Echo.connect()` first. |
| Two controllers `listen`ing to one event | Use `BroadcastListeners` and `ListensToBroadcasts`. |
| `assertSubscribed` as proof a handler exists | Use `assertListening`. |
| Expecting `X-Socket-ID` with no network driver | Add `NetworkServiceProvider`; the interceptor is skipped otherwise and for the `null` connection. |
