# magic_starter Plugin

Full-stack Flutter starter kit for Magic Framework — pre-built auth flows, team management, profile settings, notification UI, and responsive app/guest layouts with an opt-in feature flag system.

**Version:** 0.0.1-alpha.1 · **Requires:** `magic ^1.0.0-alpha.3`, `magic_notifications ^0.0.1-alpha.1`

## Installation & Setup

```bash
# Scaffold config, register provider, inject config into main.dart
dart run magic_starter:install

# Reconfigure features interactively
dart run magic_starter:configure

# Diagnose configuration issues
dart run magic_starter:doctor

# Publish config/assets for customization
dart run magic_starter:publish

# Remove plugin scaffolding
dart run magic_starter:uninstall
```

Register the service provider in `lib/config/app.dart`:

```dart
'providers': [
  AppServiceProvider,        // Must boot before MagicStarterServiceProvider
  AuthServiceProvider,
  (app) => MagicStarterServiceProvider(app),
],
```

## MagicStarter Facade API

Accessed via `package:magic_starter/magic_starter.dart`. All configuration calls should be made in a `ServiceProvider.boot()` method.

### User Model

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `useUserModel(factory)` | `void` | Register factory to hydrate your `User` model from API data. |
| `createUser(data)` | `Authenticatable` | Instantiate a user model using the registered factory. |

```dart
MagicStarter.useUserModel((data) => User.fromMap(data));
```

### Teams

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `useTeamResolver({currentTeam, allTeams, onSwitch})` | `void` | Register team accessor callbacks for the app layout. Required when `features.teams` is enabled. |
| `teamResolver` | `MagicStarterTeamResolverConfig?` | Get registered config, or `null`. |
| `hasTeamResolver` | `bool` | Whether a team resolver has been registered. |

```dart
MagicStarter.useTeamResolver(
  currentTeam: () => Auth.user<User>()?.currentTeam?.toMagicStarterTeam(),
  allTeams: () => Auth.user<User>()?.allTeams.map((t) => t.toMagicStarterTeam()).toList() ?? [],
  onSwitch: (id) => MagicStarterTeamController.instance.switchTeam(id),
);
```

### Navigation

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `useNavigation({mainItems, systemItems, bottomItems, profileMenuItems})` | `void` | Register navigation items for the app layout. |
| `navigationConfig` | `MagicStarterNavigationConfig?` | Get registered config, or `null`. |
| `hasNavigation` | `bool` | Whether navigation has been registered. |

```dart
MagicStarter.useNavigation(
  mainItems: [
    MagicStarterNavItem(icon: Icons.dashboard, labelKey: 'nav.dashboard', path: '/'),
    MagicStarterNavItem(icon: Icons.monitor_heart, labelKey: 'nav.monitors', path: '/monitors'),
  ],
  bottomItems: [
    MagicStarterNavItem(icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, labelKey: 'nav.dashboard', path: '/'),
  ],
  profileMenuItems: [
    MagicStarterNavItem(icon: Icons.notifications_outlined, labelKey: 'nav.notifications', path: '/notifications'),
  ],
);
```

`MagicStarterNavItem` fields: `icon` (required), `labelKey` (required, passed through `trans()`), `path` (required), `activeIcon` (optional).

### Custom Behaviors

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `useLogout(callback)` | `void` | Override the default logout handler in the app layout. |
| `useHeader(builder)` | `void` | Replace the default app layout header. Builder receives `(context, isDesktop)`. |
| `useSocialLogin(builder)` | `void` | Register custom social login buttons (requires `features.social_login`). Builder receives `(context, isLoading)`. |
| `hasSocialLogin` | `bool` | Whether social login builder is registered. |
| `socialLoginBuilder` | `SocialLoginBuilder?` | Get registered builder, or `null`. |
| `useGuestAuthEntry(builder)` | `void` | Register custom widget for guest/anonymous login flows (requires `features.guest_auth`). |
| `guestAuthEntryBuilder` | `Widget Function()?` | Get registered builder, or `null`. |
| `useNewsletterLabel(label)` | `void` | Override the default newsletter checkbox label. |
| `newsletterLabel` | `String?` | Get registered label, or `null`. |
| `useLocaleOptions(locales)` | `void` | Register custom locale options for the language selector. Takes `Map<String, String>` of code → native name. |
| `localeOptions` | `List<SelectOption<String>>` | Get locale options (auto-derived from `Lang.supportedLocales` if not overridden). |

### Notifications

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `useNotificationTypeMapper(mapper)` | `void` | Register a mapper to resolve notification types to icons and color classes. |
| `notificationTypeMapper` | `MagicStarterNotificationTypeMapper?` | Get registered mapper, or `null` (views use built-in defaults). |

```dart
MagicStarter.useNotificationTypeMapper((type) => switch (type) {
  'monitor_down' => (icon: Icons.error_outline, colorClass: 'text-red-500'),
  'monitor_up' => (icon: Icons.check_circle_outline, colorClass: 'text-green-500'),
  _ => (icon: Icons.info_outline, colorClass: 'text-blue-500'),
});
```

Notification polling is handled automatically by the app layout. See `plugin-notifications.md` for the `Notify` facade API.

### Access

| Property | Type | Description |
|:---------|:-----|:------------|
| `manager` | `MagicStarterManager` | Direct manager access via IoC. |
| `view` | `MagicStarterViewRegistry` | View registry for overriding built-in screens. |
| `isReady` | `bool` | `false` when teams are enabled but no team resolver is configured. |

## Configuration

Copy from `lib/config/magic_starter.dart` into your app config:

```dart
'magic_starter': {
  'features': {
    'teams': false,
    'profile_photos': false,
    'registration': true,
    'two_factor': false,
    'sessions': false,
    'guest_auth': false,
    'phone_otp': false,
    'newsletter': false,
    'email_verification': false,
    'extended_profile': true,
    'social_login': true,
    'notifications': true,
    'timezones': false,
  },
  'auth': {
    'email': true,    // Email-based login/register
    'phone': false,   // Phone-based login/register (can enable both)
  },
  'defaults': {
    'locale': 'en',
    'timezone': 'UTC',
  },
  'supported_locales': ['en', 'tr'],
  'routes': {
    'home': '/',
    'login': '/auth/login',
    'auth_prefix': '/auth',
    'teams_prefix': '/teams',
    'profile_prefix': '/settings',
    'notifications_prefix': '/notifications',
  },
  'legal': {
    'terms_url': null,    // Shows ToS link on register page when set
    'privacy_url': null,  // Shows Privacy link on register page when set
  },
},
```

All 13 features default to `false` in code. The template above has some enabled as a reasonable starting point — adjust per your backend configuration.

## View Registry

Override any pre-built screen by registering a custom builder under its string key. Call `MagicStarter.view.register()` in a service provider `boot()`.

```dart
// Override a single screen
MagicStarter.view.register('auth.login', () => CustomLoginView());

// Override a layout shell
MagicStarter.view.registerLayout('layout.app', (child) => CustomAppLayout(child: child));
```

### Built-in View Keys

| Key | Condition | Default Widget |
|:----|:----------|:---------------|
| `auth.login` | always | `MagicStarterLoginView` |
| `auth.register` | always | `MagicStarterRegisterView` |
| `auth.forgot_password` | always | `MagicStarterForgotPasswordView` |
| `auth.reset_password` | always | `MagicStarterResetPasswordView` |
| `auth.two_factor_challenge` | `features.two_factor` | `MagicStarterTwoFactorChallengeView` |
| `auth.otp_verify` | `features.phone_otp` | `MagicStarterOtpVerifyView` |
| `profile.settings` | always | `MagicStarterProfileSettingsView` |
| `teams.create` | `features.teams` | `MagicStarterTeamCreateView` |
| `teams.settings` | `features.teams` | `MagicStarterTeamSettingsView` |
| `teams.invitation_accept` | `features.teams` | `MagicStarterTeamInvitationAcceptView` |
| `notifications.list` | `features.notifications` | `MagicStarterNotificationsListView` |
| `notifications.preferences` | `features.notifications` | `MagicStarterNotificationPreferencesView` |
| `layout.guest` | always | `MagicStarterGuestLayout` |
| `layout.app` | always | `MagicStarterAppLayout` |

Registry methods: `register(key, builder)`, `registerLayout(key, layoutBuilder)`, `has(key)`, `hasLayout(key)`, `make(key)`, `makeLayout(key, child: child)`. `make()` throws `StateError` for unregistered keys.

## Controllers

All controllers use the `Magic.findOrPut(ControllerClass.new)` singleton pattern. Access via `.instance`.

| Controller | Singleton | Responsibilities |
|:-----------|:----------|:----------------|
| `MagicStarterAuthController` | `.instance` | Login, register, forgot/reset password, 2FA challenge, logout |
| `MagicStarterGuestAuthController` | `.instance` | Guest/anonymous login flows |
| `MagicStarterOtpController` | `.instance` | Phone OTP verification |
| `MagicStarterProfileController` | `.instance` | Profile info, password change, sessions, account deletion |
| `MagicStarterTeamController` | `.instance` | Team create, settings, member management, team switching |
| `MagicStarterNotificationController` | `.instance` | Notification preferences matrix, per-channel toggles |
| `MagicStarterNewsletterController` | `.instance` | Newsletter subscription management |

### Auth Controller Key Methods

```dart
// Login — phone takes precedence in dual-identity mode
await MagicStarterAuthController.instance.doLogin(
  email: 'user@example.com',
  password: 'secret',
  rememberMe: true,
);

// Register — auto-logins if backend returns token+user
await MagicStarterAuthController.instance.doRegister(
  name: 'Alice',
  email: 'alice@example.com',
  password: 'secret',
  passwordConfirmation: 'secret',
  subscribeNewsletter: true,
);

// 2FA — provide code OR recoveryCode, never both
await MagicStarterAuthController.instance.doTwoFactorChallenge(
  twoFactorToken: tokenFromLoginResponse,
  code: '123456',
);

// Logout — stops Notify polling, calls Auth.logout(), redirects
await MagicStarterAuthController.instance.logout();
```

### Notification Controller Key Methods

```dart
// Fetch preference matrix from GET /notification-preferences
await MagicStarterNotificationController.instance.fetchPreferences();

// Toggle a channel preference (optimistic update, rolls back on failure)
await MagicStarterNotificationController.instance.updateTypePreference(
  'monitor_down',  // notification type key
  'email',         // channel name
  true,            // enabled
);

// Reactive matrix access
ValueListenableBuilder(
  valueListenable: MagicStarterNotificationController.instance.matrixNotifier,
  builder: (context, matrix, _) { /* ... */ },
);
```

Matrix structure from backend: `{ "type_key": { "label": "...", "channels": { "channel": { "enabled": bool, "locked": bool } } } }`

## Layouts & Notification Integration

The app layout (`layout.app`) auto-manages notification polling:

- `initState` → calls `Notify.startPolling()` when `features.notifications` is enabled
- `dispose` → calls `Notify.stopPolling()` as a safety net
- `AuthRestored` event → triggers `Magic.reload()` to refresh team-scoped data

For the `Notify` facade API (polling interval, badge counts, push token registration, `logoutPush`), see `plugin-notifications.md`.

## Gate Abilities

`MagicStarterServiceProvider` registers 9 abilities during `boot()`. All grant access when `user.is_guest != true`. Override any by calling `Gate.define()` with the same key after the provider boots.

| Ability | Controls |
|:--------|:---------|
| `starter.update-profile-photo` | Profile photo upload/remove section |
| `starter.update-email` | Email field in profile information |
| `starter.update-phone` | Phone field in extended profile |
| `starter.update-password` | Password change section |
| `starter.verify-email` | Email verification banner |
| `starter.manage-two-factor` | Two-factor authentication section |
| `starter.manage-newsletter` | Newsletter preferences section |
| `starter.logout-sessions` | Session revoke buttons |
| `starter.delete-account` | Account deletion section |

## Gotchas

| Mistake | Fix |
|:--------|:----|
| `features.teams` enabled but no `useTeamResolver()` call | `MagicStarter.isReady` returns `false`; a warning is logged at boot. Call `useTeamResolver()` in `AppServiceProvider.boot()`. |
| `useUserModel()` not called | Starter falls back to `MagicStarterAuthUser` — your typed `User` model won't be hydrated. Always register before `MagicStarterServiceProvider` boots. |
| View key not registered | `MagicStarter.view.make(key)` throws `StateError`. Conditional views (`two_factor`, `phone_otp`, notifications) are only registered when their feature flag is `true`. |
| Calling `useTeamResolver()` / `useNavigation()` after `Magic.init()` | These calls are safe at any time, but the app layout reads the config at mount — call before the first navigation. |
| `features.social_login` enabled but no `useSocialLogin()` builder | The feature flag gates the UI section; without a builder, the social login area renders nothing. |
| Custom logout without stopping Notify polling | If you override `useLogout()`, call `Notify.logoutPush()` and `Notify.stopPolling()` manually. See `plugin-notifications.md`. |
| `MagicStarterServiceProvider` registered before `AppServiceProvider` | `useUserModel()` in `AppServiceProvider.boot()` runs after the starter's `register()` but before its `boot()`. Order: `AppServiceProvider` first, then `MagicStarterServiceProvider`. |
| `two_factor` view key missing at runtime | The view is only registered in `registerDefaultViews()` when `MagicStarterConfig.hasTwoFactorFeatures()` is `true` at boot time. Feature flags must be set before `Magic.init()`. |
