<!-- magic_device v0.0.1 | Updated: 2026-10-29 -->

# magic_device Plugin

Device signals for Flutter apps: whether the device draws from the mains, whether the viewer is away, and the macOS window's fullscreen state. Two classes, `DevicePower` and `WindowFullscreen`, plus a re-export of `battery_plus`'s `BatteryState`.

Unlike the other plugins on this list it has no service provider, no config file, no facade and no artisan command, and it does not depend on `magic`: construct the classes where you need them (a controller, a provider's `boot()`, a background job). The package is generic on purpose; anything app-specific (whether this device is a television) reaches it through a constructor parameter.

## Contents

- [Installation](#installation)
- [DevicePower](#devicepower)
- [WindowFullscreen](#windowfullscreen)
- [Testing](#testing)
- [Gotchas](#gotchas)

## Installation

```yaml
dependencies:
  magic_device: ^0.0.1
```

Requires Dart `>=3.6.0` and Flutter `>=3.27.0`. It pulls `battery_plus ^7.1.2` (battery state) and `flutter_inactive_timer ^4.0.0` (the desktop idle clock, through `dart:ffi`). There is no `plugin:install` step and nothing to inject into `lib/config/app.dart`.

The macOS half of `WindowFullscreen` is a native plugin (`MagicDevicePlugin`) that registers the `magic_device/window` channel itself, so the host's `MainFlutterWindow.swift` stays Flutter's stock one. No other platform has native code from this package.

```dart
import 'package:magic_device/magic_device.dart';
```

## DevicePower

Two hardware signals a background job gates on: whether the device is on mains power, and whether the viewer has been away long enough that the work would not disturb them.

```dart
final DevicePower power = DevicePower(television: () => isTelevision);
power.start();

if (await power.charging && power.idle) {
  // Safe to run the heavy job.
}

power.stop();
```

| Member | Signature | Meaning |
|:-------|:----------|:--------|
| constructor | `DevicePower({Future<BatteryState> Function()? batteryState, Future<int> Function()? idleDuration, TargetPlatform? platform, bool Function()? television})` | Every platform read is injectable. Omitted readers use `battery_plus`, the OS idle clock and `defaultTargetPlatform`; `television` defaults to `() => false`. |
| `instance` | `static final DevicePower instance` | A shared instance built with every default, so it can never answer for a television. |
| `charging` | `Future<bool>` | On mains power. `full`, `charging` and `connectedNotCharging` count (a batteryless Mac reports the last); `discharging` and `unknown` do not. A platform with no `battery_plus` implementation (`MissingPluginException`) answers `false`. Asks the platform on every read. |
| `idle` | `bool` | Away for at least `idleThreshold`. A cached flag, read without awaiting. |
| `start()` | `void` | Begins collecting. Idempotent. |
| `stop()` | `void` | Stops collecting and resets `idle` to `false`, so a stopped instance claims no signal rather than a stale one. |
| `idleThreshold` | `static const Duration` | 2 minutes. |
| `pollInterval` | `static const Duration` | 30 seconds, the desktop poll. |

How `idle` is measured depends on the platform:

| Platform | Source |
|:---------|:-------|
| macOS, Windows | The system-wide last-input clock, read every `pollInterval` (plus once at `start()`). Neither OS notifies "the user came back", so a poll is the only shape. |
| iOS, Android, Linux, web | The app lifecycle: idle whenever the state is not `AppLifecycleState.resumed`. There is no system-wide input clock to read. |

Nothing is collected until `start()`: an instance that never starts holds no channel, no timer and no lifecycle observer, and `idle` stays `false`.

### Televisions

A batteryless Android TV reports `BatteryState.unknown`, which would read as not charging forever and gate the work off on a box that never runs on anything else. Pass a `television` predicate and `charging` answers `true` without asking the platform. The package cannot detect a television itself, which is why the predicate is the host's.

## WindowFullscreen

Whether the macOS window is fullscreen, and the one call that flips it. A `ChangeNotifier`, reached through one shared instance.

```dart
final WindowFullscreen fullscreen = WindowFullscreen.instance;
fullscreen.addListener(_onFullscreenChanged);

if (fullscreen.available) {
  await fullscreen.toggle();
}
```

| Member | Signature | Meaning |
|:-------|:----------|:--------|
| `instance` | `static WindowFullscreen get instance` | The app's one reader, made on first use. On macOS the first use also reads the window once, so a window that opens already fullscreen is picked up. |
| `available` | `bool` | `true` on macOS only (and never on web). Gate the control on it. |
| `active` | `bool` | Fullscreen, as the window last confirmed (AppKit's did-notification). |
| `target` | `bool` | Fullscreen or on its way there. Moves on the will-notification, ahead of `active`, so a layout can animate with the window. |
| `transitioning` | `bool` | Between the will- and the did-notification; the window's size changes on every frame. |
| `toggle()` | `Future<void>` | Asks the window to enter or leave fullscreen. A no-op when not `available`, or while a press or a transition is under way. |
| `resetInstance()` | `static void`, `@visibleForTesting` | Disposes the shared reader so the next `instance` starts afresh. |

The state follows the window, not the calls. The plugin forwards `willEnterFullScreen`, `didEnterFullScreen`, `willExitFullScreen` and `didExitFullScreen` on `magic_device/window` for every change, so the green button, Esc and the Window menu notify listeners exactly as `toggle()` does. Listeners hear only real changes.

`toggle()` details:

- A second press while the first is pending or the window is animating is ignored, so a double press cannot undo itself.
- It throws `PlatformException(code: 'no_window')` when the Flutter view is not in a window; that refusal releases the press, so later toggles still work.
- AppKit silently ignores the request for an app that is not frontmost. Nothing moves and no notification arrives; `target` stays put because only a will-notification moves it.

## Testing

`DevicePower` takes every platform read through its constructor, so a test needs no plugin and no mocking library:

```dart
final DevicePower power = DevicePower(
  batteryState: () async => BatteryState.discharging,
  idleDuration: () async => const Duration(minutes: 5).inMilliseconds,
  platform: TargetPlatform.macOS,
);

power.start();
await power.refreshIdle(); // @visibleForTesting: drive the poll without waiting

expect(await power.charging, isFalse);
expect(power.idle, isTrue);

power.stop();
```

`BatteryState` comes from `package:magic_device/magic_device.dart`, so the test (and a host supplying its own reader) does not need `battery_plus` as a direct dependency.

`WindowFullscreen` reads `defaultTargetPlatform`: set `debugDefaultTargetPlatformOverride = TargetPlatform.macOS` and mock the `magic_device/window` channel to exercise it, and call `WindowFullscreen.resetInstance()` in `tearDown` so the next test does not inherit the handler and state.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Using `DevicePower.instance` on a television build | `instance` is built with defaults and cannot take `television`. Construct your own `DevicePower(television: ...)` and hold it. |
| Treating `BatteryState.unknown` as mains | It is what a batteryless Android reports; pass `television` instead of widening the rule. |
| Constructing `Battery()` beside `DevicePower` | `DevicePower` holds the one static `Battery()`; a second instance steals its EventChannel subscription. Supply a reader through `batteryState` instead. |
| Reading `idle` without calling `start()` | It stays `false` until `start()`; `stop()` resets it to `false`. |
| Expecting mobile `idle` to mean "no touches for two minutes" | On iOS and Android it means the app is not in front. Only macOS and Windows read a real input clock. |
| Building a second `WindowFullscreen` | There is no public constructor: the channel takes one handler. Use `instance`, add and remove listeners, never dispose it from a view. |
| Showing a fullscreen control everywhere | Gate it on `available`; on every platform but macOS `toggle()` sends nothing. |
| Animating the layout off `active` | `active` changes only once the window lands. Follow `target` to move with the window, and `transitioning` to hold off size-sensitive work. |
| Editing `MainFlutterWindow.swift` to add a channel | Not needed: the package's macOS plugin registers `magic_device/window` and finds the window on each call. |
