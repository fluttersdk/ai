<!-- magic_starter v0.0.40 | Updated: 2026-10-09 -->

# magic_starter Plugin

Full-stack Flutter starter kit for Magic Framework: pre-built auth flows, team management, profile settings, billing, and responsive app/guest layouts with an opt-in feature flag system. The notification UI moved to `magic_notifications` in alpha.25; this package mounts it. From 0.0.40 every sibling floor names the newest release at that point: `magic ^0.0.27`, `magic_notifications ^0.3.8`, `magic_payments ^0.0.8`, `fluttersdk_wind ^1.8.1` and `fluttersdk_artisan ^0.0.19`. The `magic_payments` floor is a real requirement: the billing screen purchases by catalogue product key and reads `StoreBillingService.products()`, `store` and `lastChangeTiming`, all new in 0.0.8, so 0.0.40 does not compile against 0.0.7 (see [Billing](#billing)). The real `magic` requirement is 0.0.24: the starter reads `AuthRestored.changed` to skip the app reload when a restore left the user unchanged. Underneath it sit older ones: `SessionScope`, `SessionScoped`, the keyed `LatestRead` and `BaseGuard.cacheUser` arrive in magic 0.0.22, `Notify.pushState` in magic_notifications 0.3.5, and `StoreIdentitySync` in magic_payments 0.0.5. Two more carry a requirement older than the batch that set them. Wind is declared DIRECTLY, rather than taken through `magic`, so a floor exists to raise when this package calls a new Wind API: 0.0.28 passes `WSelect.onOpen`, which 1.6.0 adds. And `magic` has needed 0.0.12 since 0.0.29, for two reasons rather than one: `RouteDefinition.stacked()` exists in no release below it, and 0.0.12 is also where a routed page stopped being transparent, which is the defect stacking a route would otherwise expose.

0.0.39 is BREAKING in three places, all from the redesigned social login and account deletion, and it needs a `magic-starter-laravel` with its `social-login` feature on. `MagicStarter.useSocialAuth(bridge)` replaces the old social login builder hook, with no alias. Every gated `MagicStarterProfileController` method takes a `proof` map where it took a `password`. `doDeleteAccount` schedules the deletion (a grace period a sign-in cancels), or runs it immediately when asked, rather than removing the account in the request. See [Social login and connected accounts](#social-login-and-connected-accounts) and [Identity confirmation and account deletion](#identity-confirmation-and-account-deletion).

Versions left the alpha rail at 0.0.27: `0.0.1-alpha.26` is followed by `0.0.27`, carrying the counter rather than resetting it. An existing `^0.0.1-alpha.N` pin already covers it, since a caret on a zero major ends at `0.1.0`, and `flutter pub add magic_starter` now takes the current release without a prerelease pin.

## Contents

- [Installation & Setup](#installation--setup)
- [MagicStarter Facade API](#magicstarter-facade-api)
- [Configuration](#configuration)
- [View Registry](#view-registry)
- [Design-system components](#design-system-components)
- [Reusable Widgets](#reusable-widgets)
- [Session scope (cross-tenant leak guard)](#session-scope-cross-tenant-leak-guard)
- [Route middleware](#route-middleware)
- [Plan upgrade wall](#plan-upgrade-wall)
- [Billing](#billing)
- [Page geometry](#page-geometry)
- [Controllers](#controllers)
- [Social login and connected accounts](#social-login-and-connected-accounts)
- [Identity confirmation and account deletion](#identity-confirmation-and-account-deletion)
- [Guest Claim](#guest-claim)
- [Layouts & Notification Integration](#layouts--notification-integration)
- [Gate Abilities](#gate-abilities)
- [Gotchas](#gotchas)

## Installation & Setup

```bash
flutter pub add magic_starter

# Register the plugin's artisan provider with the app dispatcher (once).
# The manifest declares `bootstrap_command: starter:install`, so this chains
# the install below by itself; run it again by hand if that subprocess failed.
dart run magic:artisan plugin:install magic_starter

# Scaffold config, register provider, inject config into main.dart.
# --features implies non-interactive AND turns every key it does not list OFF.
dart run magic:artisan starter:install
dart run magic:artisan starter:install --features=teams,two_factor

# Confirm the install (published-but-unregistered views, missing billing origin, ...)
dart run magic:artisan starter:doctor

# Reconfigure features interactively
dart run magic:artisan starter:configure

# Publish views/layouts for customization (Jetstream-style)
dart run magic:artisan starter:publish

# Remove plugin scaffolding
dart run magic:artisan starter:uninstall
```

Register the service provider in `lib/config/app.dart`:

```dart
'providers': [
  AppServiceProvider,        // MagicStarter.bootstrap() lives here
  AuthServiceProvider,
  (app) => MagicStarterServiceProvider(app),
],
```

View defaults are register-if-absent (the manager constructor calls `registerDefaultViews()`), so a host registration made in any provider wins. Two things do care about order: the teams warning `MagicStarterServiceProvider.boot()` logs when no team resolver is configured yet, and a `Gate.define()` on one of the nine starter abilities, which is silently replaced when the starter boots after you. Override an ability AFTER this provider.

## MagicStarter Facade API

Accessed via `package:magic_starter/magic_starter.dart`. All configuration calls should be made in a `ServiceProvider.boot()` method.

### Bootstrap: the identity contract (reach for this first)

`MagicStarter.bootstrap()` is the single entry point for everything the starter needs from the host app. Prefer it over the loose `use*` setters: the three required arguments are exactly the ones whose absence used to fail silently.

```dart
MagicStarter.bootstrap(
  userFactory: (data) => User.fromMap(data),
  onLogout: () => MagicStarterAuthController.instance.logout(),
  locales: const {'en': 'English', 'tr': 'Türkçe'},
  onLogin: () async => Log.info('signed in as ${Auth.id()}'),  // optional, 0.0.37+
  // Teams (all three or none):
  currentTeam: () => Auth.user<User>()?.currentTeam?.toMagicStarterTeam(),
  allTeams: () => Auth.user<User>()?.allTeams.map((t) => t.toMagicStarterTeam()).toList() ?? [],
  onSwitch: (teamId) => MagicStarter.switchTeam('$teamId'),
);
```

| Argument | Required | Notes |
|:---------|:---------|:------|
| `userFactory` | yes | `UserModelFactory`. Skipping it used to leave `MagicStarterAuthUser.fromMap` in place, so every starter screen quietly read the starter's own user type instead of the app's. |
| `onLogout` | yes | `Future<void> Function()`. |
| `locales` | yes | `Map<String, String>` of code to label. |
| `onLogin` | no | `Future<void> Function()`, 0.0.37+. Runs after a FRESH sign-in (password, two-factor, social, guest, phone OTP), off magic's `AuthLogin`, unawaited and logged on failure. Not on a cold-boot restore, not on a team switch. Also `MagicStarter.useLogin(callback)`. |
| `onGuestClaimed` | no | `Future<void> Function(GuestClaimOutcome)`, 0.0.37+. See [Guest Claim](#guest-claim). |
| `currentTeam` / `allTeams` / `onSwitch` | all three or none | Optional because `magic_starter.features.teams` defaults to `false`. Route `onSwitch` through `MagicStarter.switchTeam('$teamId')`, which is what `starter:install` generates: it also re-identifies the store rail. |

Two throws to know: a PARTIAL team-callback set raises `ArgumentError` before any setter runs (so a rejected call leaves the manager untouched rather than half-configured), and enabling the teams feature without the callbacks raises `StateError`. The 16 optional theming setters are deliberately NOT part of `bootstrap()`; call them separately. Every individual setter below stays public for partial or advanced setup, and `starter:doctor` accepts either shape.

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
| `switchTeam(String teamId)` | `Future<bool>` | 0.0.37+. Switches through `MagicStarterTeamController.switchTeam()`, applies the fresh user the answer carries (only when its `data` is the signed-in user, same id; otherwise `Auth.restore()`), then, on success only, `StoreIdentitySync.syncNow()`. A store-rail error is logged and the switch still answers `true`, since the backend already accepted it. |
| `currentTeamId()` | `String?` | 0.0.37+. The active team id as a string. |

```dart
MagicStarter.useTeamResolver(
  currentTeam: () => Auth.user<User>()?.currentTeam?.toMagicStarterTeam(),
  allTeams: () => Auth.user<User>()?.allTeams.map((t) => t.toMagicStarterTeam()).toList() ?? [],
  onSwitch: (id) => MagicStarter.switchTeam('$id'),
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
| `useNavigationTheme(theme)` | `void` | Override active nav items, brand, bottom nav, avatar colors (the dropdown trigger's initial and glyph via `dropdownAvatarTextClassName`, 0.0.36+). |
| `useModalTheme(theme)` | `void` | Override modal container, buttons, inputs, typography tokens. |
| `useFormTheme(theme)` | `void` | Override form input, label, button, link tokens across all forms. |
| `useAuthTheme(theme)` | `void` | Override auth card, title, error banner, social divider tokens. |
| `useCardTheme(theme)` | `void` | Override `MSCard` variant backgrounds, border radius, padding. |
| `usePageHeaderTheme(theme)` | `void` | Override page header container, title, subtitle tokens. |
| `useLayoutTheme(theme)` | `void` | Override sidebar, header, content/drawer background, brand bar tokens. |
| `useWindTheme(theme)` | `void` | Derive all 7 sub-themes from a `WindThemeData`'s semantic aliases (`MagicStarterTheme.fromWind`) and delegate to `useTheme()`. One call instead of 7 structs; individual setters still override afterwards. |

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
      navigationBreakpoint: 'sm', // sidebar from 640px instead of the default 'lg'
      sidebarExpandedBreakpoint: 'lg', // icons only between the two
      sidebarCompactWidth: 80, // the compact rail's width
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
| `beforeLogout(hook)` | `void` | 0.0.37+. `Future<void> Function()`. Both user sign-out paths (the profile dropdown and `MagicStarterAuthController.logout()`) await every hook in registration order BEFORE a custom `useLogout()` callback and before `Auth.logout()`, while the token is still valid. Each is isolated (a throw is logged) and bounded to five seconds. When `magic_notifications` is bound and push-state reporting is configured, the provider registers `Notify.pushState.release` as a default hook. Account deletion runs none (the server already revoked the tokens), and neither does the `AuthInterceptor` sign-out after a failed refresh. |
| `useLogin(callback)` | `void` | 0.0.37+. The `onLogin` hook; see the bootstrap table. |
| `useGuestClaimed(callback)` | `void` | 0.0.37+. See [Guest Claim](#guest-claim). |
| `useHeader(builder)` | `void` | Replace the default app layout header. Builder receives `(context, isDesktop)`. |
| `useSidebarFooter(builder)` | `void` | Add widget between navigation and user menu in sidebar/drawer. Builder receives `(context)`. |
| `useSocialAuth(bridge)` | `void` | 0.0.39+. Register the app's `MagicStarterSocialAuth` bridge (requires `features.social_login`). The starter renders the buttons itself; see [Social login and connected accounts](#social-login-and-connected-accounts). |
| `socialAuth` | `MagicStarterSocialAuth?` | The registered bridge, or `null`. |
| `useGuestAuthEntry(builder)` | `void` | Register custom widget for guest/anonymous login flows (requires `features.guest_auth`). |
| `guestAuthEntryBuilder` | `Widget Function()?` | Get registered builder, or `null`. |
| `useNewsletterLabel(label)` | `void` | Override the default newsletter checkbox label. |
| `newsletterLabel` | `String?` | Get registered label, or `null`. |
| `useLocaleOptions(locales)` | `void` | Register custom locale options for the language selector. Takes `Map<String, String>` of code to native name. |
| `localeOptions` | `List<SelectOption<String>>` | Get locale options (auto-derived from `Lang.supportedLocales` if not overridden). |

### Notifications

The notification UI belongs to `magic_notifications` (alpha.25 removed this package's copies with no shim): `MagicStarterNotificationController`, `MagicStarterNotificationsListView`, `MagicStarterNotificationPreferencesView`, `MSNotificationDropdown`, `MagicStarter.useNotificationTypeMapper` and the `MagicStarterNotificationTypeMapper` typedef are all gone. Use `NotificationPreferencesController`, `NotificationsListView`, `NotificationPreferencesView` and `NotificationDropdown` from `package:magic_notifications/magic_notifications.dart`, and say what a type looks like through the notification package's own slot:

```dart
Notify.view.slot(NotificationViewRegistry.typeIconSlotView, 'monitor_down',
    (context) => WIcon(Icons.error_outline, className: 'text-lg text-red-500'));
```

What stays here: `registerMagicStarterNotificationRoutes()` mounts `/notifications` and `/settings/notifications` in the `layout.app` shell and re-registers both screens wrapped in `MSPageContainer`, so they inherit the host's page geometry. Both are handed `contentClassName: ''` (0.0.28+, needs `magic_notifications ^0.3.2`), because that package pads its own content column for a standalone mount and the two paddings otherwise apply to the same edge: measured on a phone, these two pages sat 32 logical pixels from the display against 16 everywhere else. The delete row asks first, through this package's `MSConfirmDialog`. See `plugin-notifications.md` for the `Notify` facade API.

**One more key an upgrading app adds by hand, and it is a SESSIONS key rather than a notifications one: `profile.unknown_device` (0.0.28+).** It sits here because this is where the list of keys no package supplies lives, not because it belongs to the notification screens. A session row is titled from the agent the backend sends, `<platform> - <browser>` for a browser and `<platform> - <app>` for a native client (the `agent.app` `magic-starter-laravel` sends, read defensively so an older backend behaves as before). When every part is empty the row falls back to that key, where it used to echo the section heading and render a phone as "Browser Sessions" beside a mobile icon. Both screens that draw sessions use it, the settings one and the profile one. `starter:install` scaffolds it; an app with a hand-written catalogue sees the raw key until it adds one.

Those screens read five `notifications.*` keys no package supplies: `bulk_title` and `bulk_description` (the bulk channel card, `magic_notifications` 0.3.0), `delete` (the row's delete glyph, which a screen reader otherwise announces as "button"), `delete_failed`, and `channel_sms`. `starter:install` scaffolds all five into `en.stub`; an app upgrading with a hand-written catalogue adds them itself, or `Translator.get` renders each key as its own text.

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
    'social_login': true,      // buttons, Connected accounts page and provider confirmation; needs a bridge (0.0.39+)
    'notifications': true,
    'timezones': false,
    'billing': false,          // gates `teams.billing` (alpha.23+ ships it in the generated stub)
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
    'billing': '/teams/billing',
  },
  'billing': {
    'web_origin': null,   // REQUIRED once billing is on, and no default exists
    'billable': 'user',   // 0.0.37+: 'user' or 'team'; must match magic-starter-laravel's own key
  },
  'localization': {
    'apply_user_locale': true,  // 0.0.37+: apply the signed-in user's saved locale on sign-in and restore
  },
  'notifications': {
    'external_id_prefix': 'user_',  // must equal the backend's own prefix (0.0.27+)
  },
  'legal': {
    'terms_url': null,    // ToS link on the register page and in the store billing disclosure
    'privacy_url': null,  // Privacy link on the register page and in the store billing disclosure
  },
  'account': {
    'deletion_url': null, // 0.0.40+: where a card-billed subscription is cancelled and the account deleted
  },
},
```

All 14 features default to `false` in code. The template above has some enabled as a reasonable starting point.

`billing.billable` (0.0.37+) picks who the store rail bills: the provider sets `StoreIdentitySync.billableId` from it in `register()`, and any value but `'user'` or `'team'` throws a `StateError`. `localization.apply_user_locale` cooperates with a profile save's own language switch, so one save still issues exactly one `Lang.setLocale()`.

`billing.web_origin` carries no default on purpose, and its absence fails SILENTLY. The billing view
concatenates it into Stripe's `successUrl`, `cancelUrl` and the portal `returnUrl`, Stripe rejects a
relative url, and the resulting `BillingException` is logged rather than shown, so the customer sees a
checkout button that does nothing. `starter:doctor` reports the missing key (alpha.23+).

`notifications.external_id_prefix` is new in 0.0.27 and needs no host code: `MagicStarterServiceProvider`
listens to `Auth.stateNotifier` and declares `<prefix><user id>` as the push external id when a session
begins, releases it when one ends, and reads the current state once at boot so a session restored before
this provider boots is declared too. The default `user_` is what `magic-starter-laravel`'s `HasNotifications`
composes, and the two must agree EXACTLY: OneSignal accepts a mismatch and delivers to nobody, so the only
trace is a zero-recipient report on the server. A blank value resolves to `user_` rather than to no prefix.
`starter:doctor` prints the prefix it resolves to (0.0.27+) and never fails on it, since any value is valid
as long as the backend uses the same one; three of the four sites that compose the id live in the backend,
where no check inside this package can reach them. The release also stops `Notify` polling on the two
sign-outs the auth controller never sees (account deletion, and magic's `AuthInterceptor` failing a token
refresh); `MagicStarterAppLayout.initState` re-arms it when the shell remounts.

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

### Routes push, except where they deliberately do not (0.0.29+)

Eleven routes are registered `.stacked()`, so they push and can be popped: the eight settings spokes, `teams/create`, `teams/settings`, and both notification screens. The Connected accounts page (0.0.39) is stacked too. `MagicRoute.to()` otherwise calls `go()`, which replaces the Navigator's whole page list, and a settings app was then never more than one page deep: no iOS edge swipe, and on Android the embedder unregisters its own back callback at a stack depth of one, so the system back button LEFT THE APP from a sub-page.

Three groups keep replacing, each for a reason: the settings hub (a host commonly points a nav destination at it, and a pushing destination grows the stack per tab tap), `/invitations/:token/accept` (an arrival from an emailed link, with nothing behind it), and the six auth routes.

A stacked route names NO transition, which is the half a host controls. These routes used to pin `RouteTransition.none`, and magic reads an explicit value as opting out of `MagicRouter.defaultTransition`, so an app that asked for the platform animation app-wide got none of it here. The default is itself `none`, so an app that sets nothing sees what it saw before; set `MagicRouter.instance.defaultTransition = RouteTransition.platform` to get the operating system's own animation and the gestures that come with it.

### Built-in View Keys

| Key | Condition | Default Widget |
|:----|:----------|:---------------|
| `auth.login` | always | `MagicStarterLoginView` |
| `auth.register` | always | `MagicStarterRegisterView` |
| `auth.forgot_password` | always | `MagicStarterForgotPasswordView` |
| `auth.reset_password` | always | `MagicStarterResetPasswordView` |
| `auth.two_factor_challenge` | `features.two_factor` | `MagicStarterTwoFactorChallengeView` |
| `auth.otp_verify` | `features.phone_otp` | `MagicStarterOtpVerifyView` |
| `settings.hub` | always | `MagicStarterSettingsHubView` |
| `profile.profile` | always | `MagicStarterProfileSubPageView` |
| `settings.appearance` | always | `MagicStarterAppearanceView` |
| `settings.security.password` | always | `MagicStarterPasswordView`. For an account with `has_password` false it renders the Set password form instead of the change form (0.0.39+). |
| `settings.language` | `features.extended_profile` | `MagicStarterLanguageView` |
| `settings.timezone` | `features.timezones` | `MagicStarterTimezoneView` |
| `settings.newsletter` | `features.newsletter` | `MagicStarterNewsletterView` |
| `settings.security.two_factor` | `features.two_factor` | `MagicStarterTwoFactorView` |
| `settings.security.connected_accounts` | `features.social_login` | `MagicStarterConnectedAccountsView` (0.0.39+). The route is registered on the feature alone; the settings hub row also needs a bridge from `useSocialAuth`. |
| `settings.security.sessions` | `features.sessions` | `MagicStarterSessionsView`. Reads `profile.unknown_device`, one of the keys no package supplies; see [Notifications](#notifications), where the rest of that list lives. |
| `teams.create` | `features.teams` | `MagicStarterTeamCreateView` |
| `teams.settings` | `features.teams` | `MagicStarterTeamSettingsView` |
| `teams.invitation_accept` | `features.teams` | `MagicStarterTeamInvitationAcceptView` |
| `teams.billing` | `features.billing` | `MagicStarterBillingView` |

`notifications.list` and `notifications.preferences` are NOT on this registry (alpha.25). They live on `Notify.view`, whose API is the same; move the override there.

The settings surface is an iOS-style hub plus drill-down sub-pages, which is why the keys read the way they do. `settings.hub` is the index; the profile page is `profile.profile` (NOT `profile.settings`, which registers nothing; `MagicStarterProfileSettingsView` is exported and publishable, but nothing mounts it for you); security pages nest under `settings.security.*`.

`teams.billing` is gated on its OWN `features.billing` toggle, not on `features.teams`. The key sits in the `teams.` area because that is where the route lives (`MagicStarterConfig.billingRoute()`, default `/teams/billing`), but a subscription is bought by whoever holds the account, so an app with no team features can still sell one.

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

MagicStarter.view.slot('teams.settings', 'afterSection:members', (context) {
  return MyCustomBillingSection();
});
```

Slot API: `slot(viewKey, slotName, builder)`, `hasSlot(viewKey, slotName)`, `buildSlot(viewKey, slotName, context)`. `buildSlot()` returns `null` when no slot is registered. Slots are cleared by `registry.clear()`.

Slots that a shipped view actually reads: `header` and `footer` on every auth view, `settings.hub`, `profile.profile` and the three `teams.*` views; `formFooter` on `auth.login` and `auth.register`; `afterSection:members` on `teams.settings`. A slot name a view does not read is silently inert.

**Timing rule**: Slot registration must happen before the view is built (ideally in `AppServiceProvider.boot()`).

### Publish Command (Jetstream-style)

Copy any view or layout to the host app for full ownership:

```bash
# Publish all views and layouts
dart run magic:artisan starter:publish

# Publish a single view by tag
dart run magic:artisan starter:publish --tag=views:auth.login

# Publish all auth views
dart run magic:artisan starter:publish --tag=views:auth

# Publish all layouts
dart run magic:artisan starter:publish --tag=layouts
```

`--tag` takes `config`, `views`, `layouts`, `middleware`, `lang` or `all` (the default), each with an optional scope (`views:auth`, `views:auth.login`, `layouts:app`). There is no `views:notifications` any more: this package no longer ships those two screens, so customise them through `Notify.view`.

Published files go to `lib/resources/views/starter/` (views) or `lib/resources/layouts/starter/` (layouts). Auto-wire adds `MagicStarter.view.register()` calls to `AppServiceProvider`.

## Design-system components

44 atomic components (39 until 0.0.37), all `MS`-prefixed, exported from `package:magic_starter/magic_starter.dart`. Each lives in a 4-file folder under `lib/src/ui/components/` (`<name>.dart`, `<name>.recipe.dart`, `<name>.preview.dart`, `index.dart`) and styles through a `WindRecipe` that reads `MagicStarterTokens.defaultAliases`, so a consumer's theme drives them.

> [!IMPORTANT]
> The `MS` prefix is not optional and there is no compat shim. The pre-`MS` component names (`Button`, `Dialog`, `Switch`, ...) were removed in alpha.19, and so were the six `MagicStarter*` alias widgets (`MagicStarterCard`, `MagicStarterPageHeader`, `MagicStarterSocialDivider`, `MagicStarterNotificationDropdown`, `MagicStarterTeamSelector`, `MagicStarterUserProfileDropdown`). Write `MSCard`, `MSPageHeader`, `MSSocialDivider`, `MSTeamSelector`, `MSUserProfileDropdown`. The bell is no longer here at all: it is `NotificationDropdown` from `magic_notifications`. The prefix is what ends the `package:flutter/material.dart` collision, so no `hide` clause is needed either way.

| Family | Components |
|:-------|:-----------|
| Form controls | `MSButton`, `MSInput`, `MSTextarea`, `MSCheckbox`, `MSSwitch`, `MSSwitchRow`, `MSRadio`, `MSSelect`, `MSCombobox`, `MSKeyValueEditor`, `MSStringValueList` |
| Display | `MSBadge`, `MSTypography`, `MSSkeleton`, `MSToast`, `MSTooltip`, `MSEmptyState`, `MSErrorState`, `MSDataTable` |
| Selection / navigation | `MSSegmentedControl`, `MSTabs`, `MSAccordion`, `MSNavbar`, `MSDropdownMenu` |
| Overlay | `MSDialog`, `MSBottomSheet`, `MSConfirmDialog` |
| Composition | `MSFormField`, `MSFormActions`, `MSCard`, `MSPageHeader`, `MSHeaderAction`, `MSSocialDivider` |
| Page geometry | `MSPageContainer`, `MSPageScaffold` |
| Settings surface | `MSSettingsSection`, `MSSettingsRow`, `MSSettingsNavRow` |
| Billing surface | `MSUsageMeter`, `MSUpgradeDialog`, `MSUpgradeNudge` |
| App chrome | `MSUserProfileDropdown`, `MSTeamSelector`, `MSAvatar` |

The five added in 0.0.37 are `MSFormActions` (a cancel/submit footer row), `MSSwitchRow` (a labelled `MSSwitch`), `MSHeaderAction` (a page-header action that collapses to an icon below `lg`), `MSKeyValueEditor` (a controlled editor for a list of key/value pairs) and `MSStringValueList` (a controlled chip editor for distinct strings). Each takes every visible string as a required constructor parameter and reads no translation key of its own.

`MSButton`, `MSInput` and `MSTextarea` take `bool fullWidth = false`, which wraps the rendered widget in a `SizedBox(width: double.infinity)` rather than adding a className token (Material widgets ignore cross-axis stretch).

`MSAvatar` (0.0.28+) is the one answer to "show this person's photo, and something sensible when there is not one". It owns exactly two things, clipping the photo to the box and choosing between the photo and the fallback, and it owns no size, no shape and no colour: those differ per surface and arrive as `className`. The fallback is a WIDGET rather than a string, because the initials rule is not shared (this package takes one letter, a host app commonly takes two). A photo that fails to load falls back too, so an expired signed link shows the initial rather than a grey box.

```dart
MSAvatar(
  photoUrl: user.profilePhotoUrl,
  className: 'w-8 h-8 rounded-full bg-primary',
  fallback: WText(initials, className: 'text-sm font-bold text-on-primary'),
)
```

Do not put a `flex` on that className. Inside a wind flex a child asking for `w-full` gets the SCREEN width and `h-full` collapses, so the photo lays out as a wide band and the clip shows one slice of it; the component centres its fallback inside the fallback branch for exactly this reason.

`photoUrl` may be `null` and usually is: from `magic-starter-laravel` 0.0.11 `profile_photo_url` is `null` for a user or team with no upload, where earlier backends sent a generated ui-avatars.com image. So `null` is what "no photo" looks like on the wire, and a host reading `profile_photo_url` itself handles it rather than treating the field as always a string. Against a backend on 0.0.10 or earlier, every avatar that passes the field through (the expanded sidebar does from 0.0.36) draws that generated image instead of the themed initial.

Since 0.0.36 both forms of the sidebar avatar draw a person glyph (`Icons.person_outline`, on the text classes the initial would have used) when there is no name to take a letter from, which covers the frames before a session is known as well as an account with no name; there is no "U" from `common.user` any more. `MSUserProfileDropdown`'s trigger listens to `Auth.stateNotifier` itself, because the shell mounts it const and a const child is not rebuilt with its parent, so a guest session opened after the first frame shows on the next one. A custom `triggerBuilder` is re-run on the same notification, which follows the session only when the builder reads `Auth.user()` as it runs: one that closes over a name its enclosing `build` computed replays that stale value until the enclosing widget rebuilds. The expanded sidebar draws the account's photo through `MSAvatar` too, and its initial and glyph take `MagicStarterNavigationTheme.avatarTextClassName` on `avatarClassName`. The trigger's initial and glyph take `MagicStarterNavigationTheme.dropdownAvatarTextClassName` (default `text-sm font-bold text-white`, the string that was hard-coded before), and `MagicStarterTheme.fromWind` (so `useWindTheme`) derives it from the theme's `text-on-primary` role, since the trigger's background starts at the primary colour.

`MSDataTable` (alpha.22+) has two constructors, and the choice is about the collection rather than the styling. The default renders every row, which is right for a short and complete list. `MSDataTable.paginated` hands the body to magic's `MagicPaginatedListView` inside a box bounded by `bodyHeight`, so a long collection costs the viewport instead of the whole result and reaching the tail asks the paginator for its next page. The header stays outside the scrolling body either way. Column labels and `loadingLabel` are ALREADY TRANSLATED strings, not keys: several callers render a label that is not a key at all (a currency code, a region name).

### Page geometry is not per-page

Every authenticated page goes through `MSPageScaffold` (page surface, own scroll, container, header, `gap-6` sections column) or `MSPageContainer` for a bare page. A page that opens with its own `WDiv(className: 'p-4 lg:p-6 ...')` has invented a width and a padding, and will not line up with its neighbours. Never put a `max-w-*` or `px-*` on a page root: the geometry comes from `MagicStarter.manager.pageContainerClassName`, which the HOST sets once.

```dart
MSPageScaffold(
  title: trans('projects.title'),
  subtitle: trans('projects.manage_subtitle'),
  actions: [
    MSButton(onPressed: _onCreate, child: WText(trans('projects.new'))),
  ],
  children: [
    MSCard(title: trans('projects.recent'), child: _list()),
  ],
)
```

### MSPageHeader props

```dart
MSPageHeader(
  title: trans('projects.title'),
  subtitle: trans('projects.manage_subtitle'),
  leading: BackButton(),
  titleSuffix: StatusBadge(status: 'active'), // inline widget after title
  inlineActions: true, // force single-row layout at every width
  actions: [
    MSButton(onPressed: _onCreate, child: WText(trans('projects.new'))),
  ],
)
```

`inlineActions` is `bool?` and falls back to `MagicStarterPageHeaderTheme.inlineActions`. It does two things and both are required together: it swaps `containerClassName` for `containerInlineClassName`, AND it gives the title row `flex-1 min-w-0` instead of `sm:flex-1`. Theming the container into a row at every width without setting the flag leaves the title column a loose fit below `sm`, so a long title takes its intrinsic width and overflows. `MSPageScaffold` does not expose the argument, which is why the theme field exists.

## Reusable Widgets

The starter-specific widgets, exported from the same barrel. These are not design-system components: they carry starter behaviour (an API call, a wizard, a layout signal) rather than a style recipe.

| Widget | Purpose |
|:-------|:--------|
| `MagicStarterTwoFactorModal` | Multi-step 2FA wizard (QR setup, OTP confirm, recovery codes) |
| `MagicStarterPasswordConfirmDialog` | Password-confirm dialog with inline error display, `ConfirmDialogVariant` support |
| `MagicStarterSocialButtons` | 0.0.39+. One "Continue with" button per provider the bridge offers, rendered on login and register. Takes `socialAuth`, `onSelected`, `isLoading` and `busyProvider`; calls `onSelected` synchronously from the tap so a web popup can open. |
| `MagicStarterStepUpDialog` | 0.0.39+. Identity confirmation for a password-less account: a TOTP `code` field and one "Confirm with <provider>" button per linked provider. Opened through `confirmIdentity`, which a host rarely bypasses. |
| `MagicStarterTimezoneSelect` | Searchable timezone dropdown backed by `GET /timezones` (async search, never local data). Pages through the endpoint since 0.0.28: it asks for the next page on scroll, resets its cursor through `WSelect.onOpen` when the menu reopens, and drops any response whose list epoch has moved. |
| `MagicStarterAuthFormCard` | Centered card wrapper for auth-adjacent screens |
| `MagicStarterHideBottomNav` | `InheritedWidget` that signals `MagicStarterAppLayout` to hide the mobile bottom nav for fullscreen routes |
| `MagicStarterHideChrome` | Since 0.0.32. The same shape for the WHOLE shell: no sidebar, no drawer, no header, no bottom bar, no safe-area inset and no scroll container. The layout stays mounted, so its notification polling, its auth listeners and its route key survive. For a media player or a map, which sizes itself and cannot use the scroll container's unbounded height. |
| `MagicStarterConfirmDialog` | Thin alias of `MSConfirmDialog`, kept for existing callers. New code writes `MSConfirmDialog`. |
| `MagicStarterDialogShell` | Thin alias of `MSDialog` (sticky header/footer, scrollable body). New code writes `MSDialog`. |

### MagicStarterHideBottomNav

Wrap a route's widget to hide the mobile bottom navigation bar in `MagicStarterAppLayout`:

```dart
MagicStarterHideBottomNav(child: FullscreenEditorView())
```

### MagicStarterHideChrome

Since 0.0.32. Wrap a route group's layout to give the window to the child and keep the shell mounted:

```dart
MagicRoute.group(
  layout: (child) => MagicStarterHideChrome(
    child: MagicStarter.view.makeLayout('layout.app', child: child),
  ),
  layoutId: 'app.immersive',
  routes: () { /* the player route */ },
);
```

### The rail, since 0.0.32

`MagicStarterAppLayout` no longer hardcodes `lg` as the point where the sidebar replaces the drawer plus
bottom bar, and it can render the sidebar as an icon rail:

| Field | Default | What it decides |
|---|---|---|
| `MagicStarterLayoutTheme.navigationBreakpoint` | `'lg'` | From which Wind breakpoint the persistent sidebar replaces the drawer and the bottom bar. Lower it for a television or a small window. |
| `MagicStarterLayoutTheme.sidebarExpandedBreakpoint` | `'lg'` | From which breakpoint the sidebar carries labels. Between the two it is compact: icons only, every text label dropped, brand and user name included, because a label at the compact width is clipped rather than shortened. Equal to `navigationBreakpoint`, which is the shipped pair, means never compact. |
| `MagicStarterLayoutTheme.sidebarCompactWidth` | `80` | The compact width. 80 rather than 72 because `MSTeamSelector`'s compact trigger measures exactly 72 and the sidebar's `border-r` takes one more pixel. |
| `MagicStarterLayoutTheme.contentClassName` | `'flex-1 min-h-0'` | Since 0.0.33; the default stopped scrolling in 0.0.37 (BREAKING, it was `'flex-1 overflow-y-auto'`). The box the route child is handed. In a go_router shell the route child is the nested Navigator, so a scrolling box laid its Overlay out under an unbounded height: a page left under a `.stacked()` route was never laid out again and failed `_debugRelayoutBoundaryAlreadyMarkedNeedsLayout` in debug. Every routed page now scrolls itself: through `MSPageScaffold`, or `SingleChildScrollView(primary: false)`. A page of your own that relied on the shell renders cut off at the window, and so does a `DashboardView` from a pre-0.0.37 install stub. |
| `MagicStarterLayoutTheme.contentScrollPrimary` | `false` | Since 0.0.33 (was `true` until 0.0.37). Follows `contentClassName`. Setting the old pair back (`'flex-1 overflow-y-auto'`, `true`) through `useLayoutTheme` restores the old behaviour with the stacked-route hazard. Lost either way: tapping the iOS status bar no longer scrolls a shell page to the top. |
| `MagicStarterNavigationTheme.focusItemClassName` | `''` | Applied to every sidebar, drawer and bottom-bar item, so a host driven by arrow keys or a remote can light the destination that holds focus. Tokens carry the `focus:` prefix. |
| `MagicStarterLayoutTheme.sidebarCollapsible` | `false` | Since 0.0.34. A toggle above the user menu collapses the labelled sidebar to the compact form and back. Shown only at or above `sidebarExpandedBreakpoint`, where an expansion is possible. The choice is remembered through `Cache` under `magic_starter.sidebar_collapsed` (ten year TTL, since the cache has no `forever` and its default is an hour) when the host binds a cache, and in memory otherwise. |
| `MagicStarterLayoutTheme.sidebarCollapsedByDefault` | `false` | Since 0.0.34. The state before the viewer has chosen; a remembered choice wins. Ignored unless `sidebarCollapsible` is set. |
| `MagicStarterNavigationTheme.compactBrandBuilder` | `null` | Since 0.0.34. What the compact rail's brand bar shows, for a wordmark that does not fit 80 pixels. Unset, the rail shows `brandBuilder`. The rail's bar appends `justify-around` to `brandBarClassName`, which centres a lone brand on the icon line and keeps Wind's own child wrapping, so a brand wider than the rail stays bounded. A custom widget whose root is a `flex-1` `WDiv` is still wrapped and throws "Incorrect use of ParentDataWidget": give the brand no flex share at its root. |

The toggle reads `nav.collapse_sidebar` and `nav.expand_sidebar`. Both ship in the install stub; a host
installed before 0.0.34 adds them to its own language files, or the labelled toggle shows the raw key.

Both breakpoint fields are Wind `screens` keys rather than pixel counts, and a name the theme does not
carry throws a `StateError` naming the field and listing the valid keys. It used to answer false
silently, which made `sidebarExpandedBreakpoint: 'large'` drop every label at every width.

## Session scope (cross-tenant leak guard)

magic caches controllers as Type-keyed singletons and runs `onInit` once per instance lifetime. A logout followed by a login as a DIFFERENT user, or a team switch, therefore never re-runs the initial fetch, and the previous session's rows stay on screen. On a team-scoped product that is not staleness, it shows one tenant's data to another.

**0.0.37 is BREAKING here: `SessionScopedController` and `SessionScopeSync` are removed, with no alias. magic core (0.0.22+) owns session scoping**; see `SKILL.md`'s "Actions, Repositories, SessionScope, BroadcastListeners" section for magic's side. Implement magic's `SessionScoped` (the same single `resetForSession()` member) and attach magic's `SessionScope` once:

```dart
class MonitorController extends MagicController implements SessionScoped {
  @override
  Future<void> resetForSession() async {
    monitors.clear();          // CLEAR first, always
    await fetchMonitors();     // then refetch for the new identity
  }
}

// AppServiceProvider.boot(), AFTER MagicStarterServiceProvider, as the last Auth.stateNotifier listener:
SessionScope.attach();
```

What the starter does, and does not:

- `MagicStarterServiceProvider` sets `SessionScope.identity` to `<userId>:<teamId>` in `register()`, so a team switch by the same user counts as an identity change. It never attaches; that stays the app's call.
- `MagicStarterTeamController` and `MagicStarterBillingController` implement `SessionScoped`. The team controller clears members and invitations and reloads only while team settings is mounted; the settings view re-seeds its name field from the new team.
- A team switch no longer remounts the app (`Magic.reload()`), which used to discard a toast shown right after it. In an app that never calls `SessionScope.attach()`, the switch itself resets every `SessionScoped` controller registered with `Magic` (team, billing and the host's own), each isolated.
- A non-controller holder (a repository) registers with `SessionScope.register(holder)`; controllers are found in `Magic.controllers` without registration.

Three rules are load-bearing:

1. **Clear before refetch.** An ordinary `reload()` is deliberately non-destructive so a transport blip does not blank a dashboard. Across an identity change that is exactly wrong: a failed refetch must leave the screen empty rather than populated with the previous tenant's rows.
2. **Only a change to a NON-NULL identity resets.** Resetting on logout could only fire requests that 401 from the login screen.
3. **Each controller's reset is isolated.** One failure logs and does not abort the others.

A host implementing its own switch path applies the switch answer's user directly rather than always calling `Auth.restore()`, which would re-apply the CACHED user, still on the previous team. Full contract: `doc/basics/session-scope.md` (magic_starter's own doc).

## Route middleware

Two guards ship ready to register as the `auth` and `guest` aliases in the app's `Kernel`:

| Middleware | Redirects | Destination |
|:-----------|:----------|:------------|
| `EnsureAuthenticated` | a visitor away from a protected page | `MagicStarterConfig.loginRoute()` |
| `RedirectIfAuthenticated` | a signed-in account away from a guest page | `MagicStarterConfig.homeRoute()` |

Since 0.0.34 `RedirectIfAuthenticated` lets a user whose `is_guest` is true through: a guest session is signed in, and the login and registration pages are where it becomes an account. From the same release a guest gets Sign in and Create account at the top of `MSUserProfileDropdown` (the menu reads `is_guest`) and a Sign in row under the settings hub's upgrade row. The hub shows both of its guest rows when `Gate.denies('starter.delete-account')`, which is how the hub tells a guest: that ability is granted only when `is_guest != true` (see Gate Abilities), so it is denied for a guest and the rows appear. All of this only ever meets a guest when `features.guest_auth` is on, since nothing else creates one; on a default install (the flag is `false`) no user carries `is_guest` and none of it shows. Create account opens the profile route's in-place upgrade, so the guest keeps its own rows. `MagicStarterGuestAuthController.doGuestLogin` goes home without a request when the user is already a guest, because a second `POST /auth/guest` revokes every token of a returning guest, including one a host keeps to claim the guest's data at sign-in.

Both override `redirectTarget` (a pre-build synchronous redirect) rather than `handle` (a post-build remount), so a guarded page never mounts for someone who is about to be sent away. Each one guards its own destination so the redirect cannot loop, which matters because go_router raises after more than five successive redirects.

`EnsureAuthenticated` also records the requested location with `MagicRouter.setIntendedUrl` before bouncing (0.0.27), and the `NavigatesRoutes.navigateHome()` every post-auth path calls reads it back with `pullIntendedUrl`, falling back to `MagicStarterConfig.homeRoute()`. So a deep link that lands on a signed-out device survives the login bounce. Nothing is recorded for the guest-only auth routes themselves, and `redirectTarget` only sees `state.matchedLocation`, so a recorded intent loses the original query string.

## Plan upgrade wall

A plan-gated refusal arrives as a `403` carrying an `upgrade.required_plan` marker. `PlanUpgradeRequirement.fromResponse` reads it and returns `null` for anything else, so a caller branches on "upgrade wall or real failure" without matching English prose.

```dart
final response = await Http.post('/monitors/$id/analyze');

if (!response.successful) {
  final requirement = PlanUpgradeRequirement.fromResponse(response);
  if (requirement != null) {
    UpgradePrompt.show(requirement);   // dialog + routes to billing with the plan intent
    return;
  }
  // real failure, handle normally
}
```

| API | Signature | Notes |
|:----|:----------|:------|
| `PlanUpgradeRequirement.fromResponse(response)` | `static PlanUpgradeRequirement?` | `null` unless the `403` carries the `upgrade.required_plan` marker. Fields: `message` (server copy, rendered verbatim), `requiredPlan` (catalog id), `feature` (human label). |
| `UpgradePrompt.show(requirement)` | `static void` | Shows `MSUpgradeDialog`; "Upgrade" closes it and routes to `MagicStarterConfig.billingRoute()` (`magic_starter.routes.billing`, default `/teams/billing`) with a fresh single-use `intent` token. |
| `MSUpgradeDialog` | `{message, requiredPlan, onUpgrade, onDismiss, className}` | The modal itself, when you want to drive it yourself. |
| `MSUpgradeNudge` | inline widget | The quiet in-page variant. |

The marker is REQUIRED on purpose: a `403` without it is an authorization denial no purchase fixes (a team-scope denial, a revoked token), and offering to upgrade there would be a lie. A fresh intent per navigation matters because the billing screen mounts more than once per arrival (the router rebuilds it on the auth-state refresh) and both mounts read the same query, which otherwise opened two checkout sessions.

Copy comes from the `common.upgrade`, `common.upgrade_available_on`, and `common.upgrade_dialog_not_now` lang keys, added to the published `en` stub. An app that installed an earlier stub adds those three keys itself.

## Billing

`teams.billing` (`MagicStarterBillingView`, gated on `features.billing`) is the ready-made screen over `magic_payments`; the contract itself is in `references/plugin-payments.md`. 0.0.40 is BREAKING here. It needs `magic_payments` 0.0.8, whose rails purchase by catalogue product key, and a `magic-starter-laravel` whose `GET /billing/plans` rows carry `products` with `sellable` and `store_ids`. Both rails now buy a PRODUCT: web checkout sends `checkout(productKey:)` and a store build calls `purchase(productKey, context:)` for the product the selected tier sells on the selected cycle. Nothing sends a plan id and a cycle separately any more, so a host fake that implements `WebBillingService` or `StoreBillingService` adopts the new signatures.

### Plans and products

`MagicStarterPlan.fromMap(row)` decodes one catalogue row into `id`, `name`, `tagline`, `features`, `recommended`, `cycles`, `products` and `raw`. A tier carries NO price of its own: `MagicStarterPlan.monthly`, `annual` and `currency` are removed, because the producer's rows no longer send a tier price. A plan slot that read them reads `plan.products` or `plan.raw`.

| Member | Answers |
|:-------|:--------|
| `cycles` | `List<BillingCycle>`: the cycles the WEB rail sells this tier on. Empty for a free, custom or store-only tier. |
| `products` | Every subscription product of the tier, grandfathered ones (`sellable: false`) included so a held product can be ranked. |
| `sellableProducts` | The sellable subscription products with a cycle: the only ones a purchase, checkout or price read may name. |
| `productFor(cycle)` | The sellable product on `cycle`, else the tier's first sellable product, else `null`. |
| `webProductFor(cycle)` | The same, among the products on one of `cycles`. `null` for a tier the web does not sell. |
| `storeProducts(store)` | The sellable products that have an id in `store` (`ManageVia.appStore` or `ManageVia.playStore`). |
| `storeProductFor(cycle, store)` | The same pick as `productFor`, among `storeProducts(store)`. |

`MagicStarterProduct` (exported through `magic_starter_plan.dart`) is one entry of a row's `products`: `key` (the value a purchase, checkout and swap send), `type` (`ProductType?`), `tier`, `cycle` (`BillingCycle?`; an unknown word is `null`, never monthly), `sellable` (absent reads `true`), `storeIds` (`MagicStarterStoreIds`, a record `(appStore, play)`, Play as `subscriptionId:basePlanId`) and `webPrices` (`Map<String, MagicStarterWebPrice>` keyed by ISO 4217 code, each `(amountMinor, display)`).

How a card is priced: the first row, when it sells no product, is the free floor (`plan_price_free`), and a tier above it with no sellable product is custom (`plan_price_custom`). A web card shows the selected product's first web price `display` (`29.00 USD`), `plan_price_checkout` when it has none, and `plan_price_app` for a tier the web does not sell. A store card shows the store's own `StoreProductOffer.priceString`, with `plan_price_store` ("Price shown in the store") until or unless the store prices it, and a tier its store carries nothing of says `plan_store_unsold` instead of a price (except on the held tier's own card). A store build offers and prices only products with an id in ITS store, and the cycle toggle, now rendered on store builds too, hides when that store sells only one cycle. `renewal_text` and `renewal_ends` lost their `/mo`, since the figure is the product's price for its whole period. A store card also renders the subscription disclosure (price per period, auto-renewal, where to cancel) with Terms and Privacy links from `legal.terms_url` and `legal.privacy_url`; an unset url is left out.

### The controller's purchase surface

| Member | Type | Behaviour |
|:-------|:-----|:----------|
| `purchaseContext` | `PurchaseContext` | Built from `plans` on every read: `tierOrder` in catalogue order, `tierOfProduct` for every product key, and `tierOfStoreProduct` for every App Store and Play id the rows list, grandfathered products included. |
| `storeOffers` | `Map<String, StoreProductOffer>` | The store's prices, filled by `loadStoreProducts()`, which asks only for keys the store has an id for. A key missing from it renders with no figure, never a guessed one. |
| `purchaseInStore(product)` | `Future<bool>` | Calls `purchase(product.key, context: purchaseContext)`. Throws `BillingException` with `BillingErrorCode.pending` when a purchase is already waiting, and `UnsupportedPlatformException` with no store rail. |
| `purchaseInStoreAndWait(product)` | `Future<MagicStarterStorePurchaseOutcome>` | Buys, then waits for the backend: `dismissed`, `confirmed` (the entitlement moved), `deferred` (`lastChangeTiming` is `atRenewal`, nothing polled), `processing` (not reflected within the 60 s wait; the webhook may still land) or `abandoned` (the wait was cancelled). |
| `awaitingProductKey` | `String?` | Holds the store gate shut so a second tap cannot charge twice. Clears on an entitlement read that differs from the pre-sheet snapshot, 60 s after the store reported, or on a session reset. |
| `entitlementSnapshot` | `MagicStarterEntitlementSnapshot` | `(plan, product, provider, currentPeriodEnd)`, compared as a whole to see a purchase land. |
| `cancelWait()` | `void` | Stops a running wait (screen closed, team switched); the gate stays shut on the terms above. |

`canPurchaseViaStore` refuses a subscription the OTHER store sold, read from `storeRail.store` against the entitlement's `manageVia` and never from the platform, and refuses while `awaitingProductKey` is set. A store failure toasts `magic_starter.billing.errors.<snake_case code>` (`not_configured`, `unmapped_active_product`, ...), one sentence per `BillingErrorCode` (`unknown` keeps `toast_failed_text`); `pending` is shown as information, not as a failure. The free tier's Downgrade never renders once the subscription has stopped renewing; otherwise it opens the billing portal on a web build where `portalAvailable`, or the store's own subscription page for a store-billed team with a `manageUrl` and an owner (or an unresolved membership), and renders no button anywhere else.

An app that installed an earlier `en` stub adds, under `magic_starter.billing`, `errors.*`, `plan_price_free`, `plan_price_app`, `plan_price_checkout`, `plan_store_unsold`, the `store_disclosure_*` keys, `wait_processing` and `wait_takes_effect_on`, drops `plan_price_monthly`, removes the `/mo` from its `renewal_text` and `renewal_ends` values (or an annual card reads `290.00 USD/mo`), and adds the `social.deletion_blocking_teams*` and `social.subscription_*` keys below. A fresh `starter:install` already ships them.

## Page geometry

`MagicStarter.manager.pageContainerClassName` carries the WHOLE geometry `MSPageContainer` applies: width cap, horizontal edge margins, vertical rhythm. It defaults to `MagicStarterManager.defaultPageContainerClassName` (`'max-w-7xl px-4 lg:px-8 pt-6 sm:pt-8 pb-16'`). Set it once, from the same string the host's own pages use, or starter pages and host pages centre at different widths inside the same shell:

```dart
MagicStarter.manager.pageContainerClassName = PageContainer.className;
```

It carries all of it in one string on purpose: a cap that agrees while the padding does not still reads as two different pages. The pre-alpha.25 name `settingsMaxWidthClassName` is gone, with no alias.

## Controllers

All controllers use the `Magic.findOrPut(ControllerClass.new)` singleton pattern. Access via `.instance`.

| Controller | Singleton | Responsibilities |
|:-----------|:----------|:----------------|
| `MagicStarterAuthController` | `.instance` | Login, social sign-in, register, forgot/reset password, 2FA challenge, logout |
| `MagicStarterGuestAuthController` | `.instance` | Guest/anonymous login flows |
| `MagicStarterOtpController` | `.instance` | Phone OTP verification |
| `MagicStarterProfileController` | `.instance` | Profile info, password change and first password, sessions, two-factor, connected accounts, account deletion |
| `MagicStarterTeamController` | `.instance` | Team create, settings, member management, team switching |
| `MagicStarterNewsletterController` | `.instance` | Newsletter subscription management |
| `MagicStarterBillingController` | constructed, not `.instance` | Plans, usage meters, the web and store rails, and product-keyed store purchases (`purchaseInStore`, `purchaseInStoreAndWait`; see [Billing](#billing)). It takes `usageCopy` and `formatNumber` as required arguments (and optional `storeFundedTeamReader` / `isOwnerReader`), so the host registers its own instance with `Magic.put`. |

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

// Social sign-in (needs a bridge); call it straight from the tap, no await before it
MagicStarterAuthController.instance.doSocialSignIn('google');

// 2FA
await MagicStarterAuthController.instance.doTwoFactorChallenge(
  twoFactorToken: tokenFromLoginResponse,
  code: '123456',
);

// Logout
await MagicStarterAuthController.instance.logout();
```

The preference matrix is `NotificationPreferencesController` in `magic_notifications` now; see `plugin-notifications.md`.

## Social login and connected accounts

Since 0.0.39. Needs `magic-starter-laravel` with its `social-login` feature on. The starter owns the screens and what a sign-in concludes (a session, a two-factor challenge, a cancelled deletion); a BRIDGE the app registers owns the provider SDKs and the backend calls, so this package depends on no social login package. `magic_social_auth` 0.0.8 publishes the bridge (see `plugin-social-auth.md`); `starter:install` with `social_login` on leaves a comment in the generated provider telling you to register one.

```dart
// From a provider listed after the auth and starter providers. The published bridge registers in register(),
// because it sits after RouteServiceProvider, whose routes must already see it; boot() starts its auth listener.
MagicStarter.useSocialAuth(AppSocialAuth());
```

```dart
abstract class MagicStarterSocialAuth {
  List<String> providers();                       // display order: google, apple, ...
  String label(String provider);                  // 'Google'
  Widget icon(String provider);

  Future<Map<String, dynamic>> signIn(String provider);

  Future<Future<Map<String, dynamic>> Function()> beginConnect(
    String provider,
    Map<String, String> proof,
  );

  Future<String> confirm(String provider);        // the confirmation token
  Future<void> signOut();
}
```

| Method | Contract |
|:-------|:---------|
| `signIn(provider)` | Answers the backend's body untouched: a session (`{data: {user, token}}`, plus `data.deletion_cancelled` when the sign-in cancelled a scheduled deletion) or a challenge (`{two_factor: true, two_factor_token}`). Called synchronously from the tap with no `await` before it, so a web popup can open. A newer call supersedes a pending one. |
| `beginConnect(provider, proof)` | The network half of a connect (the backend link ticket). Answers the call that opens the provider and then answers `{data: {provider, email}}`. `proof` is minted fresh per call and empty for a guest. |
| `confirm(provider)` | Re-authenticates with a linked provider and answers the confirmation token. |
| `signOut()` | Ends provider SDK sessions. The starter never calls it: the bridge must sign Google out itself whenever `Auth.stateNotifier` goes to signed-out; the published bridge does. |

Every failure is a `MagicStarterSocialException(code:, message:, cancelled:)`. `cancelled` is the user backing out and shows nothing; otherwise the starter shows the `social.<code>` sentence (`socialFailureMessage`) and falls back to `message`.

While a bridge is set and `features.social_login` is on:

- Login and register render `MagicStarterSocialButtons`, one per `providers()` entry. `MagicStarterAuthController.doSocialSignIn(provider)` signs in and concludes through `CompletesSignIn`, the one completion every sign-in uses (password, social, two-factor challenge, OTP, guest): a challenge opens the two-factor route, a session logs in and goes home, and `data.deletion_cancelled` shows the "Account deletion cancelled" toast. The tapped provider shows a spinner (`pendingSocialProvider`) but stays tappable.
- The Connected accounts page lives at `MagicStarterConfig.settingsConnectedAccountsRoute()` (`<profile_prefix>/security/connected-accounts`), view key `settings.security.connected_accounts`. The route needs only the feature flag; the settings hub row also needs the bridge, and a page opened without one lists no provider.
- Connect confirms identity first (see below), then `MagicStarterProfileController.beginSocialConnect(provider, proof:)` asks the bridge to begin and answers the opener (or `null` when refused or cancelled). `doConnectSocialAccount(opener)` runs it and restores the user. On the web the page shows a "Continue with <provider>" button for a second tap, because a popup opened after the awaits behind the proof and the ticket is blocked. Every retry mints a new proof, link ticket and PKCE pair.
- `doDisconnectSocialAccount(provider)` sends `DELETE /user/social-accounts/{provider}` and restores the user, asking no proof. The page disables it for a password-less account with one active link; the backend's 422 `last_login_method` is the real guard.
- A password-less account sees Set password on the Security password page: `MagicStarterProfileController.doSetPassword(password:, passwordConfirmation:, proof:)` sends `POST /user/password/set` and restores the user, which flips `has_password` and the page to the change form. `password_already_set` and `password_not_set` restore the user and show the form that applies.

`MagicStarterAuthUser` gains `hasPassword` (true when a backend that predates social login omits the field), `isGuest`, `socialAccounts` (`provider`, `email_at_link`, `created_at`, `revoked_at`; a revoked link is not a way in) and `deletionScheduledAt`.

Language keys no package supplies: a `social.*` group (`continue_with`, `connect`, `disconnect`, `connected_accounts`, `confirm_identity`, `confirm_with`, `step_up_required`, `deletion_cancelled`, `deletion_scheduled` and one sentence per backend refusal code), `profile.set_password`, `profile.set_password_description`, `profile.password_set`, `profile.password_set_failed` and `magic_starter.titles.connected_accounts`. A fresh `starter:install` writes them; an upgrading app with a hand-written catalogue merges them from `assets/stubs/install/en.stub`, or each renders as its own key.

## Identity confirmation and account deletion

Since 0.0.39. A few actions make the backend ask the caller to prove who they are again: two-factor enable and disable, viewing and regenerating recovery codes, revoking a session, deleting the account, linking a provider and setting a first password. The proof reaches the controller as a `Map<String, String>` spread into the request body, minted per call and never kept (a confirmation token is single use).

| Account | Proof |
|:--------|:------|
| Has a password | `{'password': ...}` from `MagicStarterPasswordConfirmDialog` |
| No password, not a guest | `MagicStarterStepUpDialog`: `{'code': <TOTP>}` when two-factor is on, or `{'confirmation_token': ...}` from a linked provider through the bridge's `confirm` |
| Guest (`is_guest`, no password) | `{}`, no dialog |

These `MagicStarterProfileController` methods take `proof:` where they took `password:` (BREAKING; `{'password': password}` keeps the old behaviour for a password account): `doEnableTwoFactor`, `doDisableTwoFactor`, `getRecoveryCodes`, `doRegenerateRecoveryCodes`, `doRevokeSession(tokenId:, ...)`, `doRevokeOtherSessions`, `doDeleteAccount` and `doSetPassword`.

`confirmIdentity` and `confirmAndRun` (in `lib/src/support/confirms_identity.dart`) and `MagicStarterStepUpDialog` are exported, so a host that overrides a registry view confirms a password-less account the same way:

```dart
final success = await confirmAndRun(
  context,
  controller,
  title: trans('magic_starter.profile.delete_account.title'),
  action: (proof) => controller.doDeleteAccount(proof: proof),
);
```

`confirmIdentity(context, {variant, title, description, accepts, attempt})` answers the proof, or `null` on cancel; with `attempt` a returned error string is shown inline and the dialog stays open for a fresh proof. `confirmAndRun` runs the gated `action(proof)` inside the dialog; the dialog stays open only while the server refuses the proof itself (`step_up_required`, or a field error on `password`, `code` or `confirmation_token`), and the call answers `true` only when the action succeeded. A 422 `step_up_required` narrows the dialog to the proofs in `accepts` (`MagicStarterProfileController.stepUpAccepts`).

Refusals are read by `code`, never by message: `step_up_required`, `password_already_set`, `password_not_set`, `last_login_method`, and for deletion `owns_shared_teams`, `team_has_active_subscription`, `subscription_active`. Each has its own `social.*` sentence.

A deletion refusal that names teams (`team_ids`) appends them through `social.deletion_blocking_teams`, or `social.deletion_blocking_teams_count` when the host's team resolver cannot name every one. From 0.0.40 `team_has_active_subscription` reads `team_providers` and keeps the one action that clears it in `MagicStarterProfileController.refusalAction` (a `MagicStarterRefusalAction`, `(label, run)`, or `null`):

- `app_store` or `play_store`: `social.subscription_store`, with "Manage subscription" (the store's own subscription page) only when `Payments.store?.store` is the store that sold it. On the web or on the other store's device the sentence stands alone.
- `stripe`: `social.subscription_stripe` with an action that opens `magic_starter.account.deletion_url` (`MagicStarterConfig.accountDeletionUrl()`, blank reads as unset), or `social.subscription_stripe_no_link` with no action when the host set none.
- anything else: the generic `social.team_has_active_subscription`.

**Account deletion** is `doDeleteAccount({required Map<String, String> proof, bool immediately = false})`, `POST /user` with `_method: DELETE`, the proof spread in, and `immediately: true` added when asked.

- Scheduled (the default): the backend answers `202` with `data.deletion_scheduled_at` and a sentence that says how to cancel, revokes every token at once and purges the account after a grace period (30 days by default). Signing in again by any method within it cancels the deletion, and that sign-in's answer carries `data.deletion_cancelled`.
- Immediate (`immediately: true`): no grace period; the same refusals and the same proof apply.
- Either way the controller shows the backend's sentence as a toast, calls `Auth.logout()` and goes to the login route. No before-logout hooks run, since the server has already revoked the tokens. A refusal keeps the user signed in and shows its own sentence.

## Guest Claim

Since 0.0.37.

With `features.guest_auth` on, `MagicStarterGuestClaim` moves what a guest accumulated onto the account they sign in to next, wired by `MagicStarterServiceProvider` to magic's auth events. `GuestClaimOutcome` is `none` (nothing settled: signed out, still the guest, no record, a keychain refusal, or an unreachable API; every one of these keeps the record for the next attempt), `claimed` (the server accepted the claim), `refused` (the server's 422, or a 404 from a backend without the claim route; final, no retry, so a backend lacking the route never receives the guest's live token again), or `promoted` (the signed-in account IS the recorded guest, promoted in place by registration; nothing to move).

1. **Guest sign-in** (`AuthLogin` for a user whose `is_guest` is `true`): the guest's bearer token and user id are written to `Vault` under `MagicStarterGuestClaim.tokenKey` (`guest_claim_token`) and `MagicStarterGuestClaim.userKey` (`guest_claim_user`), awaited.
2. **Sign-in or restore of a real account** (`AuthLogin` for a non-guest, or `AuthRestored`): `MagicStarterGuestClaim.instance.claimIfPending()` runs unawaited, posting `POST /auth/guest/claim` with `{'guest_token': ...}` authenticated as the target account. A claim already in flight hands every caller the same future.
3. **Sign-out** (`AuthLogout`): `MagicStarterGuestClaim.forget()` deletes the record before `Auth.logout()` returns, so the next person on the device cannot claim the previous viewer's rows.

Every outcome but `none` reaches the host through `onGuestClaimed`, set via `MagicStarter.bootstrap(onGuestClaimed:)` or `MagicStarter.useGuestClaimed(callback)`:

```dart
MagicStarter.useGuestClaimed((outcome) async {
  if (outcome == GuestClaimOutcome.claimed) await Library.refresh();
});
```

The claim does not ride the `Http` facade or its interceptors: it posts on a bare `DioNetworkDriver` built straight from `network.drivers.api`, since its body is the guest's still-live bearer token and the facade driver is what `magic_devtools` records request bodies from in debug/profile builds. Full contract: `doc/basics/authentication.md#guest-claim` (magic_starter's own doc).

## Layouts & Notification Integration

The app layout (`layout.app`) auto-manages notification polling:

- `initState` calls `Notify.startPolling()` when `features.notifications` is enabled
- `dispose` calls `Notify.stopPolling()` as a safety net
- The header bell is `NotificationDropdown` from `magic_notifications`, wired to `Notify.notifications()`, `markAsRead`, `markAllAsRead`, the row's `actionUrl`, and the notifications route
- `MagicStarterServiceProvider` registers an `AuthRestored` listener that calls `Magic.reload()` after a confirmed `Auth.restore()` sync that CHANGED the user (`AuthRestored.changed`); a sync that only confirms the cached user, the usual cold boot, reloads nothing. A team switch no longer goes through it (0.0.37); team-scoped screens reset through `SessionScope` instead

Realtime is NOT wired here: the layout arms the poller only. Call `Notify.startRealtime(channel: ...)` from your own auth wiring if the backend broadcasts; `startPolling()` is a no-op while it is live. See `plugin-notifications.md`.

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
| View key not registered | `MagicStarter.view.make(key)` throws `StateError`. Conditional views (`two_factor`, `phone_otp`, `billing`, teams) are only registered when their feature flag is `true`. |
| Overriding a notification screen on the wrong registry | `notifications.list` and `notifications.preferences` live on `Notify.view`, not `MagicStarter.view`. Registering on the starter's registry mounts nothing. |
| `features.social_login` enabled but no `useSocialAuth()` bridge | The flag gates the feature; without a bridge the login and register buttons and the settings hub row are absent. The Connected accounts route still exists, and a page opened without a bridge lists no provider. |
| Looking for a builder to render social buttons | There is none. Register a `MagicStarterSocialAuth` with `MagicStarter.useSocialAuth(...)`; the starter renders the buttons. |
| `password:` rejected by `doDeleteAccount`, `doRevokeSession`, `doEnableTwoFactor` and the other gated calls | They take `proof:` since 0.0.39. Pass `{'password': password}`, or get a proof from `confirmIdentity`. |
| A web provider popup blocked | The popup must open in the tap's own run. Call `doSocialSignIn` straight from the tap with no `await` before it; a connect needs the second "Continue with" tap the Connected accounts page shows. |
| A bridge that leaves Google signed in | The starter never calls `signOut()`. The bridge signs Google out on every transition to signed-out, or the next sign-in skips the account picker. |
| Account deletion treated as instant | By default it schedules: the user is signed out at once, but the account is purged after a grace period and a sign-in within it cancels the deletion. Pass `immediately: true` to skip the grace period. |
| Custom logout without stopping Notify polling | If you override `useLogout()`, call `Notify.logoutPush()` and `Notify.stopPolling()` manually. See `plugin-notifications.md`. Before-logout hooks (the push-state release included) still run ahead of it from 0.0.37. |
| `MagicStarterPlan.monthly`, `annual` or `currency` not found | Removed in 0.0.40: a tier has no price. Read `plan.products` (`webPrices`, `productFor(cycle)`) or `plan.raw`. |
| A billing fake calling `purchase(plan: ...)` or `checkout(plan:, cycle:)` | 0.0.40 needs `magic_payments` 0.0.8: `purchase(productKey, {context})`, `checkout(productKey:, ...)`, `swap(productKey:)`, plus `products()`, `store` and `lastChangeTiming` on a store fake. |
| Offering a `sellable: false` product | Read `sellableProducts`, `webProductFor` or `storeProductFor`; the raw `products` list includes grandfathered products, kept only for ranking. |
| `SessionScopedController` / `SessionScopeSync` not found | Removed in 0.0.37. Implement magic's `SessionScoped` and call magic's `SessionScope.attach()`. |
| A page of your own cut off at the window after upgrading | 0.0.37's shell content box no longer scrolls. Wrap the page in `MSPageScaffold` or `SingleChildScrollView(primary: false)`. |
| `onSwitch` calling `MagicStarterTeamController.instance.switchTeam` directly | Works, but skips the store-rail re-identify. Use `MagicStarter.switchTeam('$teamId')`. |
| A `Gate.define()` override silently lost | The starter defines its nine abilities in `boot()`, and a same-key define is replaced by whichever provider boots last. Override AFTER `MagicStarterServiceProvider`. View defaults are register-if-absent, so they are not order-sensitive. |
| `two_factor` view key missing at runtime | The view is only registered when `MagicStarterConfig.hasTwoFactorFeatures()` is `true` at boot time. Feature flags must be set before `Magic.init()`. |
| Theme sub-theme ordering | `useTheme()` sets all 7 sub-themes at once; individual `useFormTheme()` etc. can override after. Call unified first if using both. |
| Slot not rendering | `MagicStarter.view.slot(viewKey, slotName, builder)` must be called before the view is built. Views call `buildSlot()` at build time. |
| Published view not loading | `dart run magic:artisan starter:publish` copies views to `lib/resources/views/starter/`. Auto-wire adds `MagicStarter.view.register()` to AppServiceProvider. |
| `Icons.*` in `build()` | Extract as `static const _iconName = Icons.xxx`. Required for Flutter web tree-shaking. |
| `brandBuilder` + `brandClassName` both set | `brandBuilder` wins. `brandClassName` is ignored when a builder is registered. |
| Hardcoding dialog classNames | All modal classNames must come from `MagicStarter.manager.modalTheme`. Never hardcode in widget build methods. |
| Navigation theme not affecting UI | `MagicStarter.useNavigationTheme()` must be called before the app layout is first painted. |
| Bottom nav visible on fullscreen routes | Wrap route widget with `MagicStarterHideBottomNav(child: widget)` to hide mobile bottom nav. |
| Published view not auto-wired | `dart run magic:artisan starter:doctor` detects published but unregistered views. Re-run publish or manually add `MagicStarter.view.register()`. |
| A raw key rendering in a tab title or a dialog | The catalogue is the CONSUMER's; `trans()` answers a missing key with the key. An app upgrading past alpha.24 merges the 20 `magic_starter.titles.*` keys from `assets/stubs/install/en.stub`, and past alpha.26 adds `common.delete`, `notifications.delete_confirm_title` and `notifications.delete_confirm_message`. A fresh `starter:install` already ships them. |
