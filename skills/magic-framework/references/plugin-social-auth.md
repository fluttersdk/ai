<!-- magic_social_auth v0.0.9 | Updated: 2026-10-09 -->

# magic_social_auth Plugin

Social authentication for Magic Framework against the `magic-starter-laravel` backend: native Google and Apple sheets on mobile, a backend-hosted browser flow with PKCE for GitHub, Microsoft and everything else, on iOS, Android and web. The package never logs the app in: a driver answers a `SocialAuthResult` and the caller decides what a session, a 2FA challenge or a cancelled deletion means.

0.0.8 is a breaking rewrite: there is no token model and no handler, only drivers that answer a `SocialAuthResult`. It needs `magic ^0.0.24`, `fluttersdk_artisan ^0.0.18`, Dart `^3.12.0` and Flutter `>=3.44.0`, and a backend with the `social-login` feature on. 0.0.9 changes no API: its floors move to `magic ^0.0.27` and `fluttersdk_artisan ^0.0.19`.

## Contents

- [Installation](#installation)
- [Registration](#registration)
- [SocialAuth Facade](#socialauth-facade)
- [SocialAuthManager](#socialauthmanager)
- [Built-in Drivers](#built-in-drivers)
- [Flows](#flows)
- [Contracts](#contracts)
- [Models](#models)
- [Configuration](#configuration)
- [SocialAuthButtons Widget](#socialauthbuttons-widget)
- [Custom Driver](#custom-driver)
- [Completing a Sign-In](#completing-a-sign-in)
- [Exceptions](#exceptions)
- [Gotchas](#gotchas)

## Installation

```bash
# Register the plugin's artisan provider with the app dispatcher (once)
dart run magic:artisan plugin:install magic_social_auth

# One non-interactive run leaves the app ready to sign in
dart run <app>:artisan social:install \
  --providers=google,apple,github,microsoft \
  --google-ios-client-id=123-abc.apps.googleusercontent.com \
  --google-server-client-id=123-def.apps.googleusercontent.com \
  --ios-scheme=myapp \
  --android-callback=https://auth.example.com/auth/social

# Check the result and print the backend env to set
dart run <app>:artisan social:doctor
```

`plugin:install` injects `SocialAuthServiceProvider` into `lib/config/app.dart` and registers the artisan provider; it publishes no stub files. Every `social:install` flag is optional (an omitted value is written as an empty string and `social:doctor` names it), and `--dry-run` prints every staged operation and writes nothing.

| Flag | Default | What it does |
|:-----|:--------|:-------------|
| `--providers=` | `google,apple,github,microsoft` | Providers to enable; the rest get `enabled: false`. An unknown name stops the run. Google and Apple add their native iOS edits only when listed. |
| `--google-ios-client-id=` | empty | Google iOS OAuth client id. Written to the config (`google.ios_client_id`) and to `Info.plist` as `GIDClientID`, with its reversed form registered as a URL scheme. |
| `--google-server-client-id=` | empty | Google web OAuth client id, the audience the backend verifies. Written to the config (`google.server_client_id`) and `Info.plist` as `GIDServerClientID`. |
| `--ios-scheme=` | empty | Custom URL scheme the browser flow returns to on iOS. Written as `callback.ios` = `myapp://auth/social`. |
| `--android-callback=` | empty | https App Link the browser flow returns to on Android. Written as `callback.android` and declared as the `CallbackActivity` intent filter. Must have a host and a path; use a host no other App Link filter claims. |
| `--force` | off | Overwrite files changed since the last install. Without it such a file is a conflict and the run exits 1. |

What `social:install` writes: the provider in `lib/config/app.dart`; `lib/config/social_auth.dart` plus its `configFactories` entry in `lib/main.dart`; the iOS Google keys and, with Apple on, the `com.apple.developer.applesignin` entitlement in every entitlements file the app target signs with; the Android `CallbackActivity` when `--android-callback` is given; `web/auth.html` when the project has `web/`; and, when `magic_starter` is in `pubspec.yaml`, `lib/app/providers/social_auth_starter_service_provider.dart`, the bridge that plugs the package into the starter's screens (see [Completing a Sign-In](#completing-a-sign-in)).

`social:doctor` reads the config, `Info.plist`, the entitlements files, `AndroidManifest.xml`, `web/` and the pubspec, prints a section per platform the project has, and exits 1 when anything fails: missing Google ids or callbacks, an absent Apple entitlement, Apple disabled while another provider is on (App Store guideline 4.8), an Android callback activity that is not `exported`, lacks `taskAffinity=""` or an `autoVerify` https filter, or overlaps another App Link filter, a missing `web/auth.html`, and an unregistered starter bridge. It cannot prove an Android App Link verifies or that a provider console lists the callback. It also prints the `magic-starter-laravel` `.env` lines that mirror the config (`MAGIC_STARTER_SOCIAL_PROVIDERS`, `..._IOS_REDIRECT`, `..._ANDROID_REDIRECT`, `..._WEB_REDIRECT`, the Google and Apple audiences) and the callback each provider console must list (`https://<api host>/magic-starter/social/{provider}/callback`). The two callbacks must equal the backend's redirect values exactly.

## Registration

`SocialAuthServiceProvider` is NOT included in Magic's default providers; `plugin:install` adds it. By hand:

```dart
// config/app.dart
'providers': [
  AppServiceProvider,   // Must register Auth user factory first
  AuthServiceProvider,
  (app) => SocialAuthServiceProvider(app),
  // ...
],
```

```dart
// lib/main.dart
await Magic.init(
  configFactories: [
    () => appConfig,
    () => socialAuthConfig,
  ],
);
```

```dart
import 'package:magic_social_auth/magic_social_auth.dart';
```

## SocialAuth Facade

Static access to the social authentication system.

| Method | Return | Description |
|:-------|:-------|:------------|
| `SocialAuth.driver(name)` | `SocialDriver` | Get a driver by provider name. Cached after first resolve. |
| `SocialAuth.supports(name)` | `bool` | Whether the provider supports the current platform. Returns `false` on any error. |
| `SocialAuth.signOut()` | `Future<void>` | Sign out every cached driver and clear the driver cache. |
| `SocialAuth.manager` | `SocialAuthManager` | Direct access to the manager instance. |

```dart
// Sign in. On the web call it straight from the tap handler: nothing may be awaited first.
final SocialAuthResult result = await SocialAuth.driver('google').signIn();

// Guard against unsupported platforms before showing a button
if (SocialAuth.supports('apple')) { /* offer Sign in with Apple */ }

// Sign the Google SDK out
await SocialAuth.signOut();
```

## SocialAuthManager

Singleton manager, reached through `SocialAuth.manager`.

| Member | Description |
|:-------|:------------|
| `driver(name)` | Resolve a driver by name (cached). Throws `ProviderNotConfiguredException` when `enabled: false`, and `ArgumentError` for a name that is neither built in nor extended. |
| `extend(name, factory)` | Register a custom driver factory `(Map<String, dynamic> config) => SocialDriver`. Clears the cached instance. |
| `createUser(data)` | Delegates to `Auth.manager.createUser(data)`, the app's registered user factory. |
| `registerProviderDefaults(provider, defaults)` | Register `SocialProviderDefaults` for a custom provider so `SocialAuthButtons` can render it. |
| `platform` | The platform built-in drivers resolve for. |
| `forgetDrivers()` | Clear cached drivers (use in test `tearDown`). |
| `signOut()` | Call `signOut()` on every cached driver, then clear the cache. |

## Built-in Drivers

The manager resolves the driver that runs on the current platform; `SocialAuth.driver('google')` is a `GoogleDriver` on iOS and Android and a `RedirectDriver` on the web.

| Provider | iOS | Android | Web |
|:---------|:----|:--------|:----|
| Google | native SDK (`GoogleDriver`) | native SDK (`GoogleDriver`) | browser flow (`RedirectDriver`) |
| Apple | native sheet (`AppleDriver`) | browser flow | browser flow |
| GitHub | browser flow | browser flow | browser flow |
| Microsoft | browser flow | browser flow | browser flow |

macOS, Windows and Linux are not supported: `SocialAuth.supports(name)` answers `false` and `SocialAuthButtons` omits the provider.

- **`GoogleDriver`** (`google_sign_in ^7.2.0`): posts the SDK's ID token to `auth/social/google/token`. No nonce goes with it. Reads `ios_client_id` (iOS only) and `server_client_id` (the ID token's audience; without it Google returns no ID token and the driver throws a `SocialAuthException` naming the key). `signOut()` signs the SDK out so the next sign-in offers the account picker.
- **`AppleDriver`** (`sign_in_with_apple ^8.2.0`, iOS only): every sheet gets a fresh `Nonce`; Apple receives its lowercase sha256 hex and the backend receives the raw value and checks the two match. The authorization code goes along for the refresh token that account deletion revokes. The result is an `AppleSignInResult`, which adds `givenName` and `familyName`: Apple shares the name on the first authorization only, so pass it on to a profile update or it is lost.
- **`RedirectDriver`**: any provider through the backend's browser flow. See [Flows](#flows).

## Flows

Every provider ends at the same place: a Sanctum token, or a two-factor challenge when the account confirmed 2FA.

**Native token flow** (Google on iOS and Android, Apple on iOS): the ID token is posted to `POST auth/social/{provider}/token` with an `intent` of `signin`, `connect` or `confirm`. A provider access token is never sent, only an ID token checked against the backend's configured audiences, and it is single use.

**Browser flow** (everything else), hosted by the backend:

1. The app mints a PKCE pair (verifier of 64 characters, challenge `base64url(sha256(verifier))`) and opens `GET <base_url>/auth/social/{provider}/redirect?platform=<ios|android|web>&challenge=...` (a connect adds `ticket=`, a confirm adds `intent=confirm`). iOS uses `ASWebAuthenticationSession`, Android an Auth Tab, the web a popup.
2. The provider sends the browser to the backend's fixed callback, which sends it on to the app: `myapp://auth/social?code=...` on iOS, the https App Link on Android, the app's `auth.html` on the web. A refusal arrives as `?error=<code>`. No token ever sits in a URL.
3. The app posts `{code, code_verifier}` to `POST auth/social/exchange`. The code is single use and worthless without the verifier.

Nothing is persisted: every flow mints a new pair. One browser flow at a time on mobile (a second start throws `SocialAuthCancelledException(superseded: true)`); on the web a new click supersedes a pending popup. Do not serve the app shell or `auth.html` with `Cross-Origin-Opener-Policy: same-origin`; it severs the popup's link back to the app.

## Contracts

### SocialDriver (abstract)

```dart
abstract class SocialDriver {
  SocialDriver(this.config, {SocialPlatform? platform});

  final Map<String, dynamic> config;   // social_auth.providers.<name>
  final SocialPlatform platform;

  String get name;                      // the name the backend routes on
  Set<SocialPlatform> get supportedPlatforms;
  bool supportsPlatform([SocialPlatform? platform]);

  // Sign in, or register, with the provider.
  Future<SocialAuthResult> signIn();

  // The network half of a connect; returns the call that opens the provider.
  Future<Future<SocialAuthResult> Function()> beginConnect(Map<String, String>? proof);

  // beginConnect followed by the opener, in one go (mobile).
  Future<SocialAuthResult> connect(Map<String, String>? proof);

  // Re-authenticate with an already linked provider for a step-up proof.
  Future<SocialAuthResult> confirm();

  // Ends the provider SDK's own session; a no-op by default.
  Future<void> signOut();
}
```

| Method | Backend intent | Answer carries |
|:-------|:---------------|:---------------|
| `signIn()` | `signin` | `token` and `user`, or `isTwoFactor` and `twoFactorToken`; `deletionCancelled` when the sign-in cancelled a scheduled deletion. |
| `beginConnect(proof)` / `connect(proof)` | `connect` | `connectedProvider`. Needs the caller's bearer token. |
| `confirm()` | `confirm` | `confirmationToken`, a single-use step-up proof. Needs the caller's bearer token. |

`proof` is the step-up field the account can give (`{'password': ...}`, `{'code': ...}` or `{'confirmation_token': ...}`), `null` for a guest, minted for this one call and never cached. A connect needs a link ticket first, which is a network request; a web popup opened after an `await` is blocked. So `beginConnect` does everything that needs the network and returns the opener, which opens the provider before its own first `await`: run it from a fresh tap. `connect` is for mobile. On the web a `signIn()` also has to run in the tap's own synchronous run.

```dart
await SocialAuth.driver('github').connect({'password': password});   // mobile

final open = await SocialAuth.driver('github').beginConnect(proof);  // web: prepare...
final SocialAuthResult linked = await open();                         // ...open from the next tap
```

`confirm()` is for a password-less, non-guest account that has no password to type for a sensitive action: it re-authenticates with a provider already linked and yields `result.confirmationToken`, sent as `{'confirmation_token': ...}` to the gated call. The token lives about 600 seconds (the backend's `confirmation_ttl`). A connect's link ticket expires after the backend's `link_ticket_ttl` (300 seconds by default).

## Models

### SocialAuthResult

| Field | Type | Set by |
|:------|:-----|:-------|
| `token` | `String?` | A completed sign-in: the Sanctum token. |
| `user` | `Map<String, dynamic>?` | A completed sign-in: the user resource. |
| `isTwoFactor` | `bool` | A sign-in on an account with confirmed 2FA. |
| `twoFactorToken` | `String?` | Same: finish at `auth/two-factor-challenge` with it and the user's code. |
| `deletionCancelled` | `bool` | A sign-in that cancelled a scheduled account deletion. |
| `connectedProvider` | `String?` | A connect. |
| `confirmationToken` | `String?` | A confirm. |

`SocialAuthResult.fromJson` reads the backend's body: the 2FA challenge at the top level, everything else under `data`.

### SocialPlatform

```dart
enum SocialPlatform { ios, android, web, macos, windows, linux }

SocialPlatformExtension.current  // auto-detected
platform.isMobile   // ios or android
platform.isDesktop  // macos, windows, or linux
```

## Configuration

`social:install` writes `lib/config/social_auth.dart`; every value is read at runtime through `Config.get`.

```dart
Map<String, dynamic> get socialAuthConfig => {
  'social_auth': {
    'providers': {
      'google': {
        'enabled': true,
        'ios_client_id': '123-abc.apps.googleusercontent.com',     // iOS only; also GIDClientID in Info.plist
        'server_client_id': '123-def.apps.googleusercontent.com',  // the ID token's audience
      },
      'apple': {'enabled': true},
      'github': {'enabled': true},
      'microsoft': {'enabled': true},
    },

    // Must equal the backend's MAGIC_STARTER_SOCIAL_IOS_REDIRECT and MAGIC_STARTER_SOCIAL_ANDROID_REDIRECT.
    'callback': {
      'ios': 'myapp://auth/social',
      'android': 'https://auth.example.com/auth/social',
    },
  },
};
```

| Key | Description |
|:----|:------------|
| `providers.<name>.enabled` | `false` makes `SocialAuthButtons` skip the provider and `SocialAuth.driver(name)` throw `ProviderNotConfiguredException`. |
| `callback.ios` | A custom scheme URL; the scheme is what the app listens on. An https callback would need iOS 17.4. |
| `callback.android` | An https App Link on a dedicated host; its host and path become the Auth Tab's `httpsHost` and `httpsPath` and the `CallbackActivity` intent filter. |

There is no web callback key: the web flow lands on the app's own `/auth.html` (the backend's `MAGIC_STARTER_SOCIAL_WEB_REDIRECT`). A flow whose callback is empty throws a `SocialAuthException` naming the key. A callback is needed by GitHub and Microsoft on iOS and Android, and by Apple on Android.

UI overrides read by `SocialAuthButtons` from each provider entry: `label`, `icon_svg`, `icon_class` (default `w-5 h-5`) and `order` (built in: Google 1, Microsoft 2, GitHub 3, Apple 4; on iOS Apple is always first, as Apple's review guidelines expect).

Owned elsewhere: `network.drivers.api.base_url` (magic; the browser flow starts at `<base_url>/auth/social/{provider}/redirect` and the native and exchange calls go through the `Http` facade, so the auth interceptor attaches the bearer a connect or confirm needs) and the `auth.sign_in_with` / `auth.sign_up_with` translations.

Nothing else is read: the backend owns scopes, tenants and client ids, so any other key under `social_auth` is dead config and can be deleted.

## SocialAuthButtons Widget

Config-driven buttons: reads `social_auth.providers`, filters by `enabled` and platform support, renders in `order`.

```dart
SocialAuthButtons(
  // No await before signIn(): a web popup must open in the tap's own run.
  onPressed: (provider) => SocialAuth.driver(provider)
      .signIn()
      .then(onSignedIn, onError: onFailed),
  loadingProvider: _loadingProvider,  // spinner on the tapped button, others disabled
  mode: SocialAuthMode.signIn,        // or SocialAuthMode.signUp
)
```

| Prop | Type | Default | Description |
|:-----|:-----|:--------|:------------|
| `onPressed` | `void Function(String provider)` | required | Called synchronously from the tap with the provider name. |
| `loadingProvider` | `String?` | `null` | Provider currently loading. Pass an empty string to disable all buttons. |
| `mode` | `SocialAuthMode` | `signIn` | Label text through `trans('auth.sign_in_with'/'auth.sign_up_with')`. |
| `className` | `String?` | `null` | Override outer container className. |
| `buttonClassName` | `String?` | `null` | Override individual button className. |
| `labelBuilder` | `String Function(String provider, SocialAuthMode mode)?` | `null` | Custom label builder; overrides the `trans()` lookup. |

With `magic_starter` you do not use this widget: the starter renders its own `MagicStarterSocialButtons`.

## Custom Driver

The backend serves Google, Apple, GitHub and Microsoft. A custom driver is for a provider your own backend adds. For one the backend hosts a browser flow for, reuse `RedirectDriver`; otherwise extend `SocialDriver`.

```dart
// Register in a ServiceProvider.boot(), before the first SocialAuth.driver('gitlab')
SocialAuth.manager.extend('gitlab', (config) => RedirectDriver('gitlab', config));

// UI metadata so SocialAuthButtons can render it
SocialAuth.manager.registerProviderDefaults('gitlab', const SocialProviderDefaults(
  label: 'GitLab',
  iconSvg: '<svg>...</svg>',
  order: 5,
));
```

A custom driver is resolved after the `enabled` check, so `social_auth.providers.gitlab.enabled: false` still disables it.

## Completing a Sign-In

**With `magic_starter`** you write none of this: the bridge `social:install` publishes (`SocialAuthStarterServiceProvider`, `AppSocialAuth`) implements the starter's `MagicStarterSocialAuth` over `SocialAuth` and calls `MagicStarter.useSocialAuth`. It handles 2FA, `Auth.login` and `deletion_cancelled` through the starter's completion, applies the name Apple shares to the profile once, maps every failure to `MagicStarterSocialException`, and signs Google out on every transition to signed-out. List it after the auth and starter providers. See `plugin-starter.md`.

**Without it**, the app finishes the sign-in:

```dart
Future<void> signInWith(String provider) async {
  try {
    final SocialAuthResult result = await SocialAuth.driver(provider).signIn();

    if (result.isTwoFactor) {
      // Finish at auth/two-factor-challenge with result.twoFactorToken and the user's code.
      return;
    }

    await Auth.login(
      {'token': result.token},
      SocialAuth.manager.createUser(result.user!),
    );

    if (result.deletionCancelled) {
      // Signing in cancelled a scheduled account deletion: tell the user.
    }
  } on SocialAuthCancelledException catch (error) {
    if (!error.superseded) { /* offer a retry */ }
  } on SocialAuthException catch (error) {
    // Switch on error.code, never on error.message.
  }
}
```

The app also owns one more thing: **sign Google out on its own sign-out**, or the next sign-in skips the account picker. Call the driver by name, because the manager only signs out drivers it has cached and a session restored at boot has created none:

```dart
Auth.stateNotifier.addListener(() {
  if (!Auth.check()) {
    unawaited(SocialAuth.driver('google').signOut());
  }
});
```

Guard it to Google being enabled and the platform being iOS or Android.

Disconnecting (`DELETE user/social-accounts/{provider}`) and setting a first password (`POST user/password/set`) are backend calls the starter's screens make; they are not driver methods. Account deletion is a backend concern too: `DELETE user` schedules it (a grace period a sign-in cancels, surfaced as `deletionCancelled`), or runs it immediately when the caller asks.

## Exceptions

| Exception | When thrown |
|:----------|:------------|
| `SocialAuthException(message, {code, statusCode})` | A backend refusal. `code` is the backend's machine code (or the `error` a browser callback carried), `statusCode` the HTTP status. Switch on `code`, never on `message`, which the backend translates. |
| `SocialAuthCancelledException` | The user closed the sheet, or another flow took the browser (`superseded` is `true`; stay quiet, the newer flow reports). An Android Auth Tab whose App Link verification failed also reports this, so the message invites a retry. |
| `UnsupportedPlatformException(message)` | The provider or the browser flow does not run on this platform. |
| `ProviderNotConfiguredException(provider)` | The provider has `enabled: false`. |

Backend refusal codes: `social_email_taken` (the owner signs in and connects the provider from their profile), `social_account_taken`, `last_login_method`, `provider_not_supported`, `platform_not_configured`, `flow_expired`, `invalid_identity`, `provider_email_missing`, `password_already_set`, `password_not_set`, `step_up_required`, `provider_unavailable` (503, retry later), and the deletion refusals `owns_shared_teams`, `team_has_active_subscription`, `subscription_active`.

## Gotchas

| Mistake | Fix |
|:--------|:----|
| Looking for a token model or a handler to plug in | There is none. Call `signIn()` and read the `SocialAuthResult`; the caller logs the app in. |
| A client id, scope or tenant key in the config does nothing | The backend owns them. The app config carries only `enabled`, the two Google client ids and `callback.ios` / `callback.android`. |
| `SocialAuthServiceProvider` not registered | `plugin:install` adds it; by hand it goes in `config/app.dart` providers. |
| `Auth.manager.setUserFactory()` not called | `SocialAuthManager.createUser()` delegates to `Auth.manager`; register the factory first. |
| `SocialAuthButtons` renders nothing | At least one provider must have `enabled: true` AND support the current platform. |
| `trans('auth.sign_in_with')` key missing | Add `"sign_in_with": "Sign in with :provider"` and `"sign_up_with": "Sign up with :provider"` to the `auth` namespace. |
| Web popup blocked | The popup must open in the tap's own synchronous run: call `signIn()` with no `await` before it; a connect uses `beginConnect` and a second tap. |
| Sign-in sheet closes at once on Android | The SDK reports a misconfigured Google client (SHA-1, package name, `server_client_id`) as a cancel, and an Auth Tab whose App Link failed verification does too. Run `social:doctor`; serve `/.well-known/assetlinks.json` on the callback host. |
| Browser flow lands nowhere | `callback.ios` and `callback.android` must equal the backend's redirect env exactly; the backend takes the redirect target only from its own config. |
| Apple name lost | It arrives on the first authorization only, in `AppleSignInResult.givenName` and `familyName`; pass it to a profile update. |
| Google skips the account picker | Sign the SDK out by name on every transition to signed-out; a restored session has cached no driver. |
| `SocialAuth.manager.forgetDrivers()` in tests | Call it in `tearDown()` alongside `MagicApp.reset()` + `Magic.flush()`. |
