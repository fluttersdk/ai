# magic_social_auth Plugin

Laravel Socialite-style social authentication for Magic Framework — Google, Microsoft, and GitHub out of the box with a pluggable driver system.

## Registration

`SocialAuthServiceProvider` is NOT included in Magic's default providers. Add it explicitly:

```dart
// config/app.dart
'providers': [
  AppServiceProvider,   // Must register Auth user factory first
  AuthServiceProvider,
  SocialAuthServiceProvider,  // Add this
  // ...
],
```

```dart
import 'package:magic_social_auth/magic_social_auth.dart';
```

## SocialAuth Facade

Static access to the social authentication system.

| Method | Return | Description |
|:-------|:-------|:------------|
| `SocialAuth.driver(name)` | `SocialDriver` | Get a driver by provider name. Cached after first resolve. |
| `SocialAuth.supports(name)` | `bool` | Check if provider supports the current platform. Returns `false` on any error. |
| `SocialAuth.signOut()` | `Future<void>` | Sign out all cached drivers and clear the driver cache. |
| `SocialAuth.manager` | `SocialAuthManager` | Direct access to the manager instance. |

```dart
// Authenticate with a provider
await SocialAuth.driver('google').authenticate();

// Guard against unsupported platforms before showing button
if (SocialAuth.supports('github')) {
  await SocialAuth.driver('github').authenticate();
}

// Sign out (clears Google native session, forgets all drivers)
await SocialAuth.signOut();
```

## SocialAuthManager

Singleton manager — use `SocialAuth.manager` to access it.

| Method | Description |
|:-------|:------------|
| `driver(name)` | Resolve driver by name (cached). Throws `ProviderNotConfiguredException` if disabled. |
| `extend(name, factory)` | Register a custom driver factory `(Map<String, dynamic> config) => SocialDriver`. Clears cached instance. |
| `setHandler(handler)` | Replace the default `HttpSocialAuthHandler` with a custom `SocialAuthHandler`. |
| `handleAuth(token)` | Called internally by drivers. Routes token to the registered handler. |
| `createUser(data)` | Delegates to `Auth.manager.createUser(data)` — uses the app's registered user factory. |
| `registerProviderDefaults(provider, defaults)` | Register `SocialProviderDefaults` for a custom provider so `SocialAuthButtons` can render it. |
| `forgetDrivers()` | Clear all cached driver instances (use in test `tearDown`). |
| `signOut()` | Call `signOut()` on every cached driver, then clear the cache. |

## Built-in Drivers

| Driver | Config key | Platforms | Flow |
|:-------|:-----------|:----------|:-----|
| `GoogleDriver` | `google` | iOS, Android, Web | Native SDK (mobile) / authorization popup (web) |
| `MicrosoftDriver` | `microsoft` | iOS, Android, Web, macOS, Windows | OAuth PKCE via `flutter_web_auth_2` |
| `GithubDriver` | `github` | iOS, Android, Web, macOS, Windows, Linux | OAuth browser flow via `flutter_web_auth_2` |

### Token flows

- **Google (mobile)**: Returns `accessToken` + `idToken` + profile fields. Backend verifies ID token.
- **Google (web)**: Returns `accessToken` only — backend must call Google's userinfo API.
- **Microsoft / GitHub**: Returns empty `accessToken` + `authorizationCode`. Backend must exchange the code for a token. Check `token.isCodeExchange` to detect this flow.

## Contracts

### SocialDriver (abstract)

```dart
abstract class SocialDriver {
  SocialDriver(this.config);

  final Map<String, dynamic> config;

  String get name;
  Set<SocialPlatform> get supportedPlatforms;

  // Check current platform. Pass explicit platform to override detection.
  bool supportsPlatform([SocialPlatform? platform]);

  // Step 1: open native SDK / browser, return token.
  Future<SocialToken> getToken();

  // Step 2: calls getToken() then manager.handleAuth(token). Override rarely.
  Future<void> authenticate();

  // No-op by default. Override in drivers with native sign-out (Google).
  Future<void> signOut();
}
```

### SocialAuthHandler (abstract)

Called after `getToken()` succeeds. The default implementation (`HttpSocialAuthHandler`) POSTs the token to the backend and calls `Auth.login()`.

```dart
abstract class SocialAuthHandler {
  Future<void> handle(SocialToken token);
}
```

**Default: `HttpSocialAuthHandler`**

1. Reads `social_auth.endpoint` from config (default `'/auth/social/{provider}'`).
2. Replaces `{provider}` with `token.provider` and sends `POST` with `token.toMap()`.
3. Expects `{"data": {"token": "...", "user": {...}}}` from the backend.
4. Calls `Auth.login({'token': authToken}, user)`.

## Models

### SocialToken

Returned by `driver.getToken()` and passed to `handleAuth()`.

| Field | Type | Description |
|:------|:-----|:------------|
| `provider` | `String` | Driver name: `'google'`, `'microsoft'`, `'github'` |
| `accessToken` | `String` | OAuth access token. Empty string for code-exchange flows. |
| `authorizationCode` | `String?` | OAuth authorization code (Microsoft, GitHub). |
| `idToken` | `String?` | JWT ID token (Google mobile, Microsoft). |
| `email` | `String?` | User's email — may be null on web flows. |
| `name` | `String?` | User's display name — may be null on web flows. |
| `avatarUrl` | `String?` | User's avatar URL — may be null on web flows. |
| `extra` | `Map<String, dynamic>?` | Provider-specific extra data. |
| `isCodeExchange` | `bool` | Getter: `true` when `authorizationCode != null`. |

```dart
// toMap() is what the handler POSTs to the backend
token.toMap();
// {
//   'provider': 'github',
//   'access_token': '',
//   'authorization_code': 'ghu_xxx',  // only when present
//   'id_token': '...',                 // only when present
//   'email': '...',                    // only when present
//   ...
// }
```

### SocialPlatform

```dart
enum SocialPlatform { ios, android, web, macos, windows, linux }

// Current platform (auto-detected)
SocialPlatformExtension.current  // → SocialPlatform.ios, etc.

platform.isMobile   // ios or android
platform.isDesktop  // macos, windows, or linux
```

## Configuration

Add to your `config/` directory and register the config factory:

```dart
// lib/config/social_auth.dart
const Map<String, dynamic> defaultSocialAuthConfig = {
  'social_auth': {
    // Backend endpoint template. {provider} is replaced at runtime.
    'endpoint': '/auth/social/{provider}',

    'providers': {
      'google': {
        'enabled': true,
        'client_id': null,           // iOS/Android client ID from Google Console
        'server_client_id': null,    // Web/server client ID (mobile only)
        'scopes': ['email', 'profile'],
        'label': 'Google',           // Override button label
        'icon_svg': null,            // Override button icon SVG
        'order': 1,                  // Button render order
      },
      'microsoft': {
        'enabled': true,
        'client_id': null,           // Azure App Registration client ID
        'tenant': 'common',          // 'common', 'organizations', or tenant GUID
        'scopes': ['openid', 'profile', 'email'],
        'callback_scheme': 'myapp',  // Custom URL scheme for mobile callback
        'web_callback_url': null,    // Full callback URL for web
        'label': 'Microsoft',
        'order': 2,
      },
      'github': {
        'enabled': true,
        'client_id': null,           // GitHub OAuth App client ID
        'scopes': ['read:user', 'user:email'],
        'callback_scheme': 'myapp',  // Custom URL scheme for mobile callback
        'web_callback_url': null,    // Full callback URL for web
        'label': 'GitHub',
        'order': 3,
      },
    },
  },
};
```

Register via `configFactories` if any values need `Env.get()`:

```dart
// In Magic.init() call
configFactories: [
  () => {
    'social_auth': {
      'endpoint': '/auth/social/{provider}',
      'providers': {
        'google': {
          'enabled': true,
          'client_id': Env.get('GOOGLE_CLIENT_ID'),
          'server_client_id': Env.get('GOOGLE_SERVER_CLIENT_ID'),
        },
        'github': {
          'enabled': true,
          'client_id': Env.get('GITHUB_CLIENT_ID'),
          'callback_scheme': Env.get('APP_SCHEME', fallback: 'myapp'),
        },
      },
    },
  },
],
```

## SocialAuthButtons Widget

Config-driven buttons — reads `social_auth.providers`, filters by `enabled` flag and platform support, renders in `order`.

```dart
SocialAuthButtons(
  onAuthenticate: (provider) async {
    setState(() => _loadingProvider = provider);
    try {
      await SocialAuth.driver(provider).authenticate();
      Route.to('/dashboard');
    } on SocialAuthCancelledException {
      // User cancelled — do nothing
    } on SocialAuthException catch (e) {
      MagicFeedback.error(e.message);
    } finally {
      setState(() => _loadingProvider = null);
    }
  },
  loadingProvider: _loadingProvider,  // Shows spinner on tapped button, disables others
  mode: SocialAuthMode.signIn,        // Or SocialAuthMode.signUp
)
```

| Prop | Type | Default | Description |
|:-----|:-----|:--------|:------------|
| `onAuthenticate` | `Future<void> Function(String provider)` | required | Callback with the provider name. |
| `loadingProvider` | `String?` | `null` | Provider currently loading. Pass empty string to disable all buttons. |
| `mode` | `SocialAuthMode` | `signIn` | Changes button label text. Uses `trans('auth.sign_in_with'/'auth.sign_up_with')`. |
| `className` | `String?` | `null` | Override outer container className. |
| `buttonClassName` | `String?` | `null` | Override individual button className. |
| `labelBuilder` | `String Function(String provider, SocialAuthMode mode)?` | `null` | Custom label builder. Overrides `trans()` lookup. |

Label translation keys required:
- `auth.sign_in_with` with `:provider` placeholder
- `auth.sign_up_with` with `:provider` placeholder

## Custom Driver

```dart
// 1. Implement SocialDriver
class AppleDriver extends SocialDriver {
  AppleDriver(super.config);

  @override
  String get name => 'apple';

  @override
  Set<SocialPlatform> get supportedPlatforms => {
    SocialPlatform.ios,
    SocialPlatform.macos,
  };

  @override
  Future<SocialToken> getToken() async {
    // Implement Apple Sign In
    // ...
    return SocialToken(
      provider: name,
      accessToken: credential.identityToken ?? '',
      idToken: credential.identityToken,
      email: credential.email,
      name: credential.fullName?.givenName,
    );
  }
}

// 2. Register in a ServiceProvider.boot()
SocialAuth.manager.extend('apple', (config) => AppleDriver(config));

// 3. Register UI metadata so SocialAuthButtons renders it
SocialAuth.manager.registerProviderDefaults('apple', const SocialProviderDefaults(
  label: 'Apple',
  iconSvg: '<svg>...</svg>',
  order: 0,   // Render first
));
```

## Custom Handler (e.g., Firebase)

```dart
class FirebaseAuthHandler implements SocialAuthHandler {
  @override
  Future<void> handle(SocialToken token) async {
    final credential = GoogleAuthProvider.credential(
      idToken: token.idToken,
      accessToken: token.accessToken.isNotEmpty ? token.accessToken : null,
    );
    await FirebaseAuth.instance.signInWithCredential(credential);
    // Optionally call Auth.login() to sync with Magic's auth state
  }
}

// Register before first authenticate() call
SocialAuth.manager.setHandler(FirebaseAuthHandler());
```

## Exceptions

| Exception | When thrown |
|:----------|:------------|
| `SocialAuthException(message, {code})` | Base exception for all auth failures. |
| `SocialAuthCancelledException` | User cancelled the auth flow (dismisses sheet/browser). |
| `UnsupportedPlatformException(message)` | Driver called on an unsupported platform. |
| `ProviderNotConfiguredException(provider)` | Provider's `enabled: false` in config, or driver name not recognized. |

## Gotchas

| Mistake | Fix |
|:--------|:----|
| `SocialAuthServiceProvider` not registered | Add it manually to `config/app.dart` providers — it is NOT auto-registered. |
| `Auth.manager.setUserFactory()` not called | `SocialAuthManager.createUser()` delegates to `Auth.manager` — the factory must be registered before `authenticate()` completes. |
| `SocialAuthButtons` renders nothing | Check that at least one provider has `enabled: true` AND supports the current platform. |
| `trans('auth.sign_in_with')` key missing | Add `"sign_in_with": "Sign in with :provider"` and `"sign_up_with": "Sign up with :provider"` to your `auth` translation namespace. |
| Microsoft/GitHub `accessToken` is empty | Both drivers use code exchange. Check `token.isCodeExchange` — backend must exchange `authorizationCode` for a token. |
| Google web sends no email/name | Web authorization popup returns only `accessToken`. Backend must call Google's userinfo API to get profile data. |
| Custom driver not shown in `SocialAuthButtons` | Call `registerProviderDefaults()` in addition to `extend()` — the widget won't render providers without UI metadata. |
| `SocialAuth.manager.forgetDrivers()` in tests | Call this in `tearDown()` alongside `MagicApp.reset()` + `Magic.flush()` to clear cached driver instances. |
| `callback_scheme` mismatch | The scheme in config must exactly match the custom URL scheme registered in your app's native manifest. |
