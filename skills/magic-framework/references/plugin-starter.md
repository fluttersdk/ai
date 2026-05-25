<!-- magic_starter v0.0.1-alpha.14 | Updated: 2026-04-16 -->

# magic_starter Plugin

Full-stack Flutter starter kit for Magic Framework — pre-built auth flows, team management, profile settings, notification UI, and responsive app/guest layouts with an opt-in feature flag system.

## Installation & Setup

```bash
# Scaffold config, register provider, inject config into main.dart
dart run magic_starter:install

# Reconfigure features interactively
dart run magic_starter:configure

# Diagnose configuration issues
dart run magic_starter:doctor

# Publish views/layouts for customization (Jetstream-style)
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

### Theme System

The manager holds 7 sub-theme objects. Set all at once via `useTheme()` or individually. Bidirectional sync: the `theme` getter constructs a `MagicStarterTheme` from all fields, the setter distributes to each.

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `useTheme(theme)` | `void` | Set all 7 sub-themes at once via `MagicStarterTheme`. |
| `theme` | `MagicStarterTheme` | Get unified theme (constructs from individual fields). |
| `useNavigationTheme(theme)` | `void` | Override active nav items, brand, bottom nav, avatar colors. |
| `useModalTheme(theme)` | `void` | Override modal container, buttons, inputs, typography tokens. |
| `useFormTheme(theme)` | `void` | Override form input, label, button, link tokens across all forms. |
| `useAuthTheme(theme)` | `void` | Override auth card, title, error banner, social divider tokens. |
| `useCardTheme(theme)` | `void` | Override `MagicStarterCard` variant backgrounds, border radius, padding. |
| `usePageHeaderTheme(theme)` | `void` | Override page header container, title, subtitle tokens. |
| `useLayoutTheme(theme)` | `void` | Override sidebar, header, content/drawer background, brand bar tokens. |

```dart
// Set everything at once
MagicStarter.useTheme(
  MagicStarterTheme(
    navigation: MagicStarterNavigationTheme(
      activeItemClassName: 'active:text-amber-500 active:bg-amber-500/10',
      brandBuilder: (context) => Image.asset('assets/logo.png', height: 28),
    ),
    form: MagicStarterFormTheme(
      inputClassName: 'rounded-xl border-2 border-zinc-700 bg-zinc-900 text-white',
      primaryButtonClassName: 'bg-indigo-600 hover:bg-indigo-700 text-white rounded-xl',
    ),
    auth: MagicStarterAuthTheme(
      cardClassName: 'rounded-3xl bg-zinc-900 border border-zinc-700 p-8',
    ),
    layout: MagicStarterLayoutTheme(
      sidebarWidth: 280,
      sidebarClassName: 'h-full flex flex-col bg-zinc-900 border-r border-zinc-700',
      drawerBackgroundLightShade: 0.3, // drawer background opacity
    ),
  ),
);

// Override just one sub-theme afterward
MagicStarter.useCardTheme(
  MagicStarterCardTheme(
    surfaceClassName: 'bg-zinc-50 dark:bg-zinc-900 border border-zinc-200 dark:border-zinc-700',
    borderRadius: 'rounded-xl',
  ),
);
```

All sub-theme classes live in `lib/src/configuration/magic_starter_theme.dart`. `MagicStarterTheme` supports `copyWith()` for partial overrides.

**Ordering rule**: `useTheme()` sets all 7 sub-themes at once. Individual `useFormTheme()` etc. can override after. Call unified first if using both.

### Custom Behaviors

| Method / Property | Signature | Description |
|:------------------|:----------|:------------|
| `useLogout(callback)` | `void` | Override the default logout handler in the app layout. |
| `useHeader(builder)` | `void` | Replace the default app layout header. Builder receives `(context, isDesktop)`. |
| `useSidebarFooter(builder)` | `void` | Add widget between navigation and user menu in sidebar/drawer. Builder receives `(context)`. |
| `useSocialLogin(builder)` | `void` | Register custom social login buttons (requires `features.social_login`). Builder receives `(context, isLoading)`. |
| `hasSocialLogin` | `bool` | Whether social login builder is registered. |
| `socialLoginBuilder` | `SocialLoginBuilder?` | Get registered builder, or `null`. |
| `useGuestAuthEntry(builder)` | `void` | Register custom widget for guest/anonymous login flows (requires `features.guest_auth`). |
| `guestAuthEntryBuilder` | `Widget Function()?` | Get registered builder, or `null`. |
| `useNewsletterLabel(label)` | `void` | Override the default newsletter checkbox label. |
| `newsletterLabel` | `String?` | Get registered label, or `null`. |
| `useLocaleOptions(locales)` | `void` | Register custom locale options for the language selector. Takes `Map<String, String>` of code to native name. |
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

All 13 features default to `false` in code. The template above has some enabled as a reasonable starting point.

## View Registry

Override any pre-built screen by registering a custom builder under its string key. Call `MagicStarter.view.register()` in a service provider `boot()`.

```dart
// Override a single screen
MagicStarter.view.register('auth.login', () => CustomLoginView());

// Override a layout shell
MagicStarter.view.registerLayout('layout.app', (child) => CustomAppLayout(child: child));

// Override a modal
MagicStarter.view.registerModal('modal.confirm', () => CustomConfirmDialog());
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

### Built-in Layout Keys

| Key | Default Widget |
|:----|:---------------|
| `layout.guest` | `MagicStarterGuestLayout` |
| `layout.app` | `MagicStarterAppLayout` |

### Built-in Modal Keys

| Key | Default Widget |
|:----|:---------------|
| `modal.confirm` | `MagicStarterConfirmDialog` (with `ConfirmDialogVariant`: primary/danger/warning) |
| `modal.password_confirm` | `MagicStarterPasswordConfirmDialog` |
| `modal.two_factor` | `MagicStarterTwoFactorModal` (multi-step wizard) |

Registry methods: `register()`, `registerLayout()`, `registerModal()`, `has()`, `hasLayout()`, `hasModal()`, `make()`, `makeLayout()`, `makeModal()`. All `make*()` methods throw `StateError` for unregistered keys.

### Builder Slots

Inject custom widgets into specific sections of plugin views without overriding the entire view. Each view defines named insertion points (header, footer, section-specific slots).

```dart
// Register a slot builder
MagicStarter.view.slot('auth.login', 'header', (context) {
  return WText('Welcome back!', className: 'text-2xl font-bold text-center');
});

MagicStarter.view.slot('profile.settings', 'afterSection:info', (context) {
  return MyCustomBillingSection();
});
```

Slot API: `slot(viewKey, slotName, builder)`, `hasSlot(viewKey, slotName)`, `buildSlot(viewKey, slotName, context)`. `buildSlot()` returns `null` when no slot is registered. Slots are cleared by `registry.clear()`.

**Timing rule**: Slot registration must happen before the view is built (ideally in `AppServiceProvider.boot()`).

### Publish Command (Jetstream-style)

Copy any view or layout to the host app for full ownership:

```bash
# Publish all views and layouts
dart run magic_starter:publish

# Publish a single view by tag
dart run magic_starter:publish --tag=views:auth.login

# Publish all auth views
dart run magic_starter:publish --tag=views:auth

# Publish all layouts
dart run magic_starter:publish --tag=layouts
```

Published files go to `lib/resources/views/starter/` (views) or `lib/resources/layouts/starter/` (layouts). Auto-wire adds `MagicStarter.view.register()` calls to `AppServiceProvider`.

## Reusable Widgets

Exported from `package:magic_starter/magic_starter.dart` for use in consumer apps:

| Widget | Purpose |
|:-------|:--------|
| `MagicStarterPageHeader` | Full-width page header with `title`, `subtitle`, `leading`, `actions`, `titleSuffix` (Widget?), `inlineActions` (bool) |
| `MagicStarterCard` | Card with `title` slot, `noPadding` mode, `CardVariant` (surface/inset/elevated) |
| `MagicStarterConfirmDialog` | Confirmation dialog with `ConfirmDialogVariant` (primary/danger/warning), async `onConfirm` |
| `MagicStarterPasswordConfirmDialog` | Password-confirm dialog with inline error display, `ConfirmDialogVariant` support |
| `MagicStarterTwoFactorModal` | Multi-step 2FA wizard (QR setup, OTP confirm, recovery codes) |
| `MagicStarterDialogShell` | Shared dialog shell with sticky header/footer, scrollable body |
| `MagicStarterAuthFormCard` | Centered card wrapper for auth-adjacent screens |
| `MagicStarterTimezoneSelect` | Searchable timezone dropdown backed by `GET /timezones` |
| `MagicStarterTeamSelector` | Current-team switcher dropdown with create/settings links |
| `MagicStarterUserProfileDropdown` | User avatar menu with profile links, theme toggle, logout |
| `MagicStarterNotificationDropdown` | Bell-icon dropdown with live unread badge and mark-as-read |
| `MagicStarterSocialDivider` | "Or continue with" divider for auth forms |
| `MagicStarterHideBottomNav` | `InheritedWidget` that signals `MagicStarterAppLayout` to hide mobile bottom nav for fullscreen routes |

### MagicStarterPageHeader Props

```dart
MagicStarterPageHeader(
  title: trans('projects.title'),
  subtitle: trans('projects.manage_subtitle'),
  leading: BackButton(),
  titleSuffix: StatusBadge(status: 'active'), // inline widget after title
  inlineActions: true, // force single-row layout on all screen sizes
  actions: [
    PrimaryButton(label: trans('projects.new'), onTap: _onCreate),
  ],
)
```

### MagicStarterHideBottomNav

Wrap a route's widget to hide the mobile bottom navigation bar in `MagicStarterAppLayout`:

```dart
MagicStarterHideBottomNav(child: FullscreenEditorView())
```

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
// Login
await MagicStarterAuthController.instance.doLogin(
  email: 'user@example.com',
  password: 'secret',
  rememberMe: true,
);

// Register
await MagicStarterAuthController.instance.doRegister(
  name: 'Alice',
  email: 'alice@example.com',
  password: 'secret',
  passwordConfirmation: 'secret',
  subscribeNewsletter: true,
);

// 2FA
await MagicStarterAuthController.instance.doTwoFactorChallenge(
  twoFactorToken: tokenFromLoginResponse,
  code: '123456',
);

// Logout
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

- `initState` calls `Notify.startPolling()` when `features.notifications` is enabled
- `dispose` calls `Notify.stopPolling()` as a safety net
- `AuthRestored` event triggers `Magic.reload()` to refresh team-scoped data

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
| `useUserModel()` not called | Starter falls back to `MagicStarterAuthUser`. Always register before `MagicStarterServiceProvider` boots. |
| View key not registered | `MagicStarter.view.make(key)` throws `StateError`. Conditional views (`two_factor`, `phone_otp`, notifications) are only registered when their feature flag is `true`. |
| `features.social_login` enabled but no `useSocialLogin()` builder | The feature flag gates the UI section; without a builder, the social login area renders nothing. |
| Custom logout without stopping Notify polling | If you override `useLogout()`, call `Notify.logoutPush()` and `Notify.stopPolling()` manually. See `plugin-notifications.md`. |
| `MagicStarterServiceProvider` registered before `AppServiceProvider` | Order: `AppServiceProvider` first, then `MagicStarterServiceProvider`. |
| `two_factor` view key missing at runtime | The view is only registered when `MagicStarterConfig.hasTwoFactorFeatures()` is `true` at boot time. Feature flags must be set before `Magic.init()`. |
| Theme sub-theme ordering | `useTheme()` sets all 7 sub-themes at once; individual `useFormTheme()` etc. can override after. Call unified first if using both. |
| Slot not rendering | `MagicStarter.view.slot(viewKey, slotName, builder)` must be called before the view is built. Views call `buildSlot()` at build time. |
| Published view not loading | `dart run magic_starter:publish` copies views to `lib/resources/views/starter/`. Auto-wire adds `MagicStarter.view.register()` to AppServiceProvider. |
| `Icons.*` in `build()` | Extract as `static const _iconName = Icons.xxx`. Required for Flutter web tree-shaking. |
| `brandBuilder` + `brandClassName` both set | `brandBuilder` wins. `brandClassName` is ignored when a builder is registered. |
| Hardcoding dialog classNames | All modal classNames must come from `MagicStarter.manager.modalTheme`. Never hardcode in widget build methods. |
| Navigation theme not affecting UI | `MagicStarter.useNavigationTheme()` must be called before the app layout is first painted. |
| Bottom nav visible on fullscreen routes | Wrap route widget with `MagicStarterHideBottomNav(child: widget)` to hide mobile bottom nav. |
| Published view not auto-wired | `dart run magic_starter:doctor` detects published but unregistered views. Re-run publish or manually add `MagicStarter.view.register()`. |
