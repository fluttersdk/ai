---
name: magic-social-auth
description: "Add social sign-in to a Magic app: Google, Apple, GitHub and Microsoft through native sheets or a PKCE browser flow, with social:install and social:doctor."
version: 1.0.0
when_to_use: "Use when code imports package:magic_social_auth or touches SocialAuth, SocialAuthResult, SocialAuthButtons, the social_auth config or social:install."
---

# magic_social_auth

Social sign-in for a Magic app, against the `magic-starter-laravel` backend. `SocialAuth.driver(name).signIn()` runs a native sheet (Google on iOS and Android, Apple on iOS) or a backend-hosted browser flow with PKCE (everything else) and answers a `SocialAuthResult`. The package never logs the app in: the caller (or the `magic_starter` bridge) does. `social:install` writes the config and the native edits, `social:doctor` checks them and prints the backend `.env` lines.

This skill covers `magic_social_auth` only. The Magic framework itself (container, facades, `Auth`, `Http`, `Config`) is the `magic-framework` skill; the backend routes and env live in `magic-starter-laravel`.

## Install

```bash
flutter pub add magic_social_auth
dart run magic:dowel plugin:install magic_social_auth
dart run magic:dowel social:install \
  --providers=google,apple,github,microsoft \
  --google-ios-client-id=123-abc.apps.googleusercontent.com \
  --google-server-client-id=123-def.apps.googleusercontent.com \
  --ios-scheme=myapp \
  --android-callback=https://auth.example.com/auth/social
dart run magic:dowel social:doctor
```

Requires Dart >=3.13, Flutter >=3.47, `magic` ^1.0.0 and a backend with the `social-login` feature on. `social:install` registers `SocialAuthServiceProvider` in `lib/config/app.dart`, writes `lib/config/social_auth.dart` and its `configFactories` entry, edits `Info.plist`, the entitlements, `AndroidManifest.xml` and `web/auth.html` for the providers you enable, and publishes the starter bridge when `magic_starter` is a dependency. Every flag is optional; `--dry-run` previews and `--force` overwrites a file that changed since the last install. Import only the barrel: `package:magic_social_auth/magic_social_auth.dart`.

## Sign-in rules

1. Register `SocialAuthServiceProvider` before using `SocialAuth`: it is not auto-registered, and the facade resolves the `social_auth` singleton it binds. `social:install` does it.
2. `SocialAuth.driver(name)` caches per name. It throws `ProviderNotConfiguredException` for `enabled: false` and `ArgumentError` for a name that is neither built in nor registered with `extend`. Gate UI on `SocialAuth.supports(name)`, which answers `false` for both and for a platform the driver does not run on.
3. On the web call `signIn()` straight from the tap handler with no `await` before it. The popup must open in the tap's own synchronous run, or the browser blocks it.
4. A driver answers a `SocialAuthResult` and never creates a session. Run `Auth.login({'token': result.token}, SocialAuth.manager.createUser(result.user!))` yourself, after the app's user factory is registered (`createUser` delegates to `Auth.manager`).
5. Check `result.isTwoFactor` first: on a challenged sign-in `token` and `user` are `null`, and you finish at `auth/two-factor-challenge` with `twoFactorToken`. Tell the user when `deletionCancelled` is `true`.
6. Switch on `SocialAuthException.code`, never on `message`, which the backend translates. A browser callback's `error` becomes the `code` too. SDK and browser failures carry `sdk_error`.
7. A `SocialAuthCancelledException` is not always the user's: Android reports a failed App Link verification and a misconfigured Google client (SHA-1, package name, `server_client_id`) as a cancel. Offer a retry, and stay quiet only when `superseded` is `true`, because the newer flow reports the outcome.
8. Apple's name arrives on the first authorisation only, in `AppleSignInResult.givenName` and `familyName`. Pass it to a profile update at once or it is lost.
9. A second browser flow on mobile while one is open throws `SocialAuthCancelledException(superseded: true)`. Disable the other buttons while one runs (`SocialAuthButtons.loadingProvider`).

## Connect and confirm rules

1. `connect(proof)` links a provider to the signed-in account and `confirm()` re-authenticates with a linked one. Both need the caller's bearer token, which magic's `Http` auth interceptor attaches, so the user must be signed in.
2. `proof` is `{'password': ...}`, `{'code': ...}` or `{'confirmation_token': ...}`, and `null` for a guest. Build it per call: every connect mints a new PKCE pair, link ticket and proof, and none is reusable.
3. On the web `connect` opens the popup after an `await` and is blocked. Call `beginConnect(proof)` first (the network half) and run the opener it returns from a second, explicit tap.
4. `confirm()` answers `confirmationToken`, a single-use proof; send it as `{'confirmation_token': ...}` to the gated call. A password-less, non-guest account has no password to type, which is what it is for.
5. There is no disconnect method. Unlinking is the backend's `DELETE user/social-accounts/{provider}`, and a password-less account cannot remove its last way in (`last_login_method`).

## Config and native rules

1. The app config carries only `enabled`, `google.ios_client_id`, `google.server_client_id` and `callback.ios` and `callback.android`, plus the `SocialAuthButtons` overrides per provider: `label`, `icon_svg`, `icon_class` and `order`. Client secrets, scopes, tenants and the Apple key are the backend's. The browser flow starts at `<network.drivers.api.base_url>/auth/social/{provider}/redirect`, so that key must be the backend's API base.
2. `callback.ios` and `callback.android` must equal the backend's `MAGIC_STARTER_SOCIAL_IOS_REDIRECT` and `MAGIC_STARTER_SOCIAL_ANDROID_REDIRECT`: the backend takes the redirect target only from its own config. There is no web key; the web lands on the app's own `auth.html`.
3. `callback.ios` is a custom scheme URL (`myapp://auth/social`), because an https callback needs iOS 17.4. `callback.android` is an https App Link on a dedicated host that no other App Link filter in the app claims, or Android may open the wrong activity; the host serves `/.well-known/assetlinks.json`.
4. An empty callback that a flow needs throws a `SocialAuthException` naming the key. GitHub and Microsoft need both mobile callbacks, Apple needs the Android one, Google and the web need none.
5. Google without `server_client_id` returns no ID token; the driver throws `sdk_error` and logs the key. The key is the ID token's audience, so it is also in the backend's `MAGIC_STARTER_SOCIAL_GOOGLE_AUDIENCES`.
6. A custom driver sends no nonce for Google. For Apple it sends `Nonce.hashed` to Apple and `Nonce.raw` to the backend, one `Nonce` per sheet.
7. Serve `auth.html` without a `Cross-Origin-Opener-Policy` header. A same-origin one can sever `window.opener`; the page then falls back to writing the result to `localStorage`, which the web flow reads.
8. Run `social:doctor` after any native or config change. Its checks are textual: keep provider entries and `callback` in `lib/config/social_auth.dart` flat maps of string and bool literals.

## Buttons and sign-out rules

1. `SocialAuthButtons` is built from Wind widgets and needs a `WindTheme` above it (`MagicApplication` provides one). `onPressed(provider)` runs synchronously from the tap so a web popup can open.
2. Labels come from `trans('auth.sign_in_with')` and `trans('auth.sign_up_with')` with a `:provider` placeholder. Without those translations pass `labelBuilder`.
3. The widget walks `social_auth.providers`, so a custom provider needs its own entry there as well as `SocialAuth.manager.extend(...)`. Register its icon and label with `registerProviderDefaults`.
4. `SocialAuth.signOut()` signs out only the drivers cached in this process. A session restored at boot cached none, so without the `magic_starter` bridge sign Google out by name on every transition to signed-out, or the next sign-in skips the account picker.

## Recipes

Sign in and finish the session:

```dart
import 'package:magic/magic.dart';
import 'package:magic_social_auth/magic_social_auth.dart';

Future<void> signInWith(String provider) async {
  try {
    final SocialAuthResult result = await SocialAuth.driver(provider).signIn();

    if (result.isTwoFactor) {
      // Finish at auth/two-factor-challenge with result.twoFactorToken.
      return;
    }

    await Auth.login(
      {'token': result.token},
      SocialAuth.manager.createUser(result.user!),
    );
  } on SocialAuthCancelledException catch (error) {
    if (!error.superseded) {
      // Offer a retry.
    }
  } on SocialAuthException catch (error) {
    Log.error('Social sign-in refused: ${error.code}');
  }
}
```

Connect a provider on the web, from two taps:

```dart
import 'package:magic_social_auth/magic_social_auth.dart';

Future<Future<SocialAuthResult> Function()> prepare(String password) {
  return SocialAuth.driver('github').beginConnect({'password': password});
}

// In the next tap handler, an explicit "Continue to GitHub" button.
Future<SocialAuthResult> continueTo(Future<SocialAuthResult> Function() open) {
  return open();
}
```

Get a step-up proof for a password-less account:

```dart
import 'package:magic_social_auth/magic_social_auth.dart';

Future<String?> proof() async {
  final SocialAuthResult result = await SocialAuth.driver('google').confirm();

  return result.confirmationToken;
}
```

Add a provider the backend hosts a flow for:

```dart
import 'package:magic_social_auth/magic_social_auth.dart';

void registerGitLab() {
  SocialAuth.manager.extend(
    'gitlab',
    (config) => RedirectDriver('gitlab', config),
  );
  SocialAuth.manager.registerProviderDefaults(
    'gitlab',
    const SocialProviderDefaults(
      label: 'GitLab',
      iconSvg: '<svg viewBox="0 0 24 24"></svg>',
      order: 5,
    ),
  );
}
```

Sign Google out when the app signs out, without the starter bridge:

```dart
import 'dart:async';

import 'package:magic/magic.dart';
import 'package:magic_social_auth/magic_social_auth.dart';

void signGoogleOutOnSignOut() {
  Auth.stateNotifier.addListener(() {
    if (!Auth.check() && SocialAuth.supports('google')) {
      unawaited(SocialAuth.driver('google').signOut());
    }
  });
}
```

## Testing

No mocking library and no method-channel mock. Fake the platform through the `@visibleForTesting` seams by subclassing: `GoogleDriver.initializeSdk`, `nativeSignIn` and `signOutSdk`, `AppleDriver.requestCredential`, `SocialFlow.authenticate`. Stand in for the backend with `Http.fake({'/auth/social/exchange': Http.response({...})})`, and read recorded requests from the returned fake. In `setUp()` call `MagicApp.reset()`, `Config.flush()`, `SocialAuthManager().forgetDrivers()` and `GoogleDriver.resetInitialization()` (the SDK accepts one initialize per process). Force a platform with `SocialAuthManager().platformOverride`, and reset it to `null` in `tearDown()`. Wrap widget tests in `MaterialApp` and `WindTheme(data: WindThemeData(), child: ...)`. Register a mock driver by contract inheritance (`class MockDriver extends SocialDriver`) through `manager.extend`.
