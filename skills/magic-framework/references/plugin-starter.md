<!-- magic_starter v0.0.1-alpha.23 | Updated: 2026-08-29 -->

# magic_starter Plugin

Full-stack Flutter starter kit for Magic Framework: pre-built auth flows, team management, profile settings, notification UI, and responsive app/guest layouts with an opt-in feature flag system.

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
- [Settings page width](#settings-page-width)
- [Controllers](#controllers)
- [Layouts & Notification Integration](#layouts--notification-integration)
- [Gate Abilities](#gate-abilities)
- [Gotchas](#gotchas)

## Installation & Setup

```bash
# Register the plugin's artisan provider with the app dispatcher (once)
dart run magic:artisan plugin:install magic_starter

# Scaffold config, register provider, inject config into main.dart
dart run magic:artisan starter:install

# Reconfigure features interactively
dart run magic:artisan starter:configure

# Diagnose configuration issues
dart run magic:artisan starter:doctor

# Publish views/layouts for customization (Jetstream-style)
dart run magic:artisan starter:publish

# Remove plugin scaffolding
dart run magic:artisan starter:uninstall
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

### Bootstrap: the identity contract (reach for this first)

`MagicStarter.bootstrap()` is the single entry point for everything the starter needs from the host app. Prefer it over the loose `use*` setters: the three required arguments are exactly the ones whose absence used to fail silently.

```dart
MagicStarter.bootstrap(
  userFactory: (data) => User.fromMap(data),
  onLogout: () => MagicStarterAuthController.instance.logout(),
  locales: const {'en': 'English', 'tr': 'Türkçe'},
  // Teams (all three or none):
  currentTeam: () => Auth.user<User>()?.currentTeam?.toMagicStarterTeam(),
  allTeams: () => Auth.user<User>()?.allTeams.map((t) => t.toMagicStarterTeam()).toList() ?? [],
  onSwitch: (teamId) => MagicStarterTeamController.instance.switchTeam(teamId),
);
```

| Argument | Required | Notes |
|:---------|:---------|:------|
| `userFactory` | yes | `UserModelFactory`. Skipping it used to leave `MagicStarterAuthUser.fromMap` in place, so every starter screen quietly read the starter's own user type instead of the app's. |
| `onLogout` | yes | `Future<void> Function()`. |
| `locales` | yes | `Map<String, String>` of code to label. |
| `currentTeam` / `allTeams` / `onSwitch` | all three or none | Optional because `magic_starter.features.teams` defaults to `false`. |

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
| `useCardTheme(theme)` | `void` | Override `MSCard` variant backgrounds, border radius, padding. |
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
  },
  'legal': {
    'terms_url': null,    // Shows ToS link on register page when set
    'privacy_url': null,  // Shows Privacy link on register page when set
  },
},
```

All 14 features default to `false` in code. The template above has some enabled as a reasonable starting point.

`billing.web_origin` carries no default on purpose, and its absence fails SILENTLY. The billing view
concatenates it into Stripe's `successUrl`, `cancelUrl` and the portal `returnUrl`, Stripe rejects a
relative url, and the resulting `BillingException` is logged rather than shown, so the customer sees a
checkout button that does nothing. `starter:doctor` reports the missing key (alpha.23+).

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
| `settings.hub` | always | `MagicStarterSettingsHubView` |
| `profile.profile` | always | `MagicStarterProfileSubPageView` |
| `settings.appearance` | always | `MagicStarterAppearanceView` |
| `settings.security.password` | always | `MagicStarterPasswordView` |
| `settings.language` | `features.extended_profile` | `MagicStarterLanguageView` |
| `settings.timezone` | `features.timezones` | `MagicStarterTimezoneView` |
| `settings.newsletter` | `features.newsletter` | `MagicStarterNewsletterView` |
| `settings.security.two_factor` | `features.two_factor` | `MagicStarterTwoFactorView` |
| `settings.security.sessions` | `features.sessions` | `MagicStarterSessionsView` |
| `teams.create` | `features.teams` | `MagicStarterTeamCreateView` |
| `teams.settings` | `features.teams` | `MagicStarterTeamSettingsView` |
| `teams.invitation_accept` | `features.teams` | `MagicStarterTeamInvitationAcceptView` |
| `teams.billing` | `features.billing` | `MagicStarterBillingView` |
| `notifications.list` | `features.notifications` | `MagicStarterNotificationsListView` |
| `notifications.preferences` | `features.notifications` | `MagicStarterNotificationPreferencesView` |

The settings surface is an iOS-style hub plus drill-down sub-pages, which is why the keys read the way they do. `settings.hub` is the index; the profile page is `profile.profile` (NOT `profile.settings`, which registers nothing); security pages nest under `settings.security.*`.

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
dart run magic:artisan starter:publish

# Publish a single view by tag
dart run magic:artisan starter:publish --tag=views:auth.login

# Publish all auth views
dart run magic:artisan starter:publish --tag=views:auth

# Publish all layouts
dart run magic:artisan starter:publish --tag=layouts
```

Published files go to `lib/resources/views/starter/` (views) or `lib/resources/layouts/starter/` (layouts). Auto-wire adds `MagicStarter.view.register()` calls to `AppServiceProvider`.

## Design-system components

39 atomic components, all `MS`-prefixed, exported from `package:magic_starter/magic_starter.dart`. Each lives in a 4-file folder under `lib/src/ui/components/` (`<name>.dart`, `<name>.recipe.dart`, `<name>.preview.dart`, `index.dart`) and styles through a `WindRecipe` that reads `MagicStarterTokens.defaultAliases`, so a consumer's theme drives them.

> [!IMPORTANT]
> The `MS` prefix is not optional and there is no compat shim. The pre-`MS` component names (`Button`, `Dialog`, `Switch`, ...) were removed in alpha.19, and so were the six `MagicStarter*` alias widgets (`MagicStarterCard`, `MagicStarterPageHeader`, `MagicStarterSocialDivider`, `MagicStarterNotificationDropdown`, `MagicStarterTeamSelector`, `MagicStarterUserProfileDropdown`). Write `MSCard`, `MSPageHeader`, `MSSocialDivider`, `MSNotificationDropdown`, `MSTeamSelector`, `MSUserProfileDropdown`. The prefix is what ends the `package:flutter/material.dart` collision, so no `hide` clause is needed either way.

| Family | Components |
|:-------|:-----------|
| Form controls | `MSButton`, `MSInput`, `MSTextarea`, `MSCheckbox`, `MSSwitch`, `MSRadio`, `MSSelect`, `MSCombobox` |
| Display | `MSBadge`, `MSTypography`, `MSSkeleton`, `MSToast`, `MSTooltip`, `MSEmptyState`, `MSErrorState`, `MSDataTable` |
| Selection / navigation | `MSSegmentedControl`, `MSTabs`, `MSAccordion`, `MSNavbar`, `MSDropdownMenu` |
| Overlay | `MSDialog`, `MSBottomSheet`, `MSConfirmDialog` |
| Composition | `MSFormField`, `MSCard`, `MSPageHeader`, `MSSocialDivider` |
| Page geometry | `MSPageContainer`, `MSPageScaffold` |
| Settings surface | `MSSettingsSection`, `MSSettingsRow`, `MSSettingsNavRow` |
| Billing surface | `MSUsageMeter`, `MSUpgradeDialog`, `MSUpgradeNudge` |
| App chrome | `MSNotificationDropdown`, `MSUserProfileDropdown`, `MSTeamSelector` |

`MSButton`, `MSInput` and `MSTextarea` take `bool fullWidth = false`, which wraps the rendered widget in a `SizedBox(width: double.infinity)` rather than adding a className token (Material widgets ignore cross-axis stretch).

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
| `MagicStarterTimezoneSelect` | Searchable timezone dropdown backed by `GET /timezones` (async search, never local data) |
| `MagicStarterAuthFormCard` | Centered card wrapper for auth-adjacent screens |
| `MagicStarterHideBottomNav` | `InheritedWidget` that signals `MagicStarterAppLayout` to hide the mobile bottom nav for fullscreen routes |
| `MagicStarterConfirmDialog` | Thin alias of `MSConfirmDialog`, kept for existing callers. New code writes `MSConfirmDialog`. |
| `MagicStarterDialogShell` | Thin alias of `MSDialog` (sticky header/footer, scrollable body). New code writes `MSDialog`. |

### MagicStarterHideBottomNav

Wrap a route's widget to hide the mobile bottom navigation bar in `MagicStarterAppLayout`:

```dart
MagicStarterHideBottomNav(child: FullscreenEditorView())
```

## Session scope (cross-tenant leak guard)

magic caches controllers as Type-keyed singletons and runs `onInit` once per instance lifetime. A logout followed by a login as a DIFFERENT user, or a team switch, therefore never re-runs the initial fetch, and the previous session's rows stay on screen. On a team-scoped product that is not staleness, it shows one tenant's data to another.

Any controller that caches session-scoped or team-scoped data implements `SessionScopedController`, and the host attaches the sync once:

```dart
class MonitorController extends MagicController implements SessionScopedController {
  @override
  Future<void> resetForSession() async {
    monitors.clear();          // CLEAR first, always
    await fetchMonitors();     // then refetch for the new identity
  }
}

// AppServiceProvider.boot()
SessionScopeSync.attach();     // drives every registered controller off Auth.stateNotifier
```

| API | Signature | Notes |
|:----|:----------|:------|
| `SessionScopedController.resetForSession()` | `Future<void>` | Interface method. Must clear before it refetches. |
| `SessionScopeSync.attach()` | `static void` | Subscribes to `Auth.stateNotifier`, keyed on `<userId>:<teamId>`, so a team switch counts as an identity change. |
| `SessionScopeSync.detach()` | `static void` | Unsubscribes from the exact notifier instance `attach` used. Needed in tests, which re-bind the guard. |

Three rules are load-bearing:

1. **Clear before refetch.** An ordinary `reload()` is deliberately non-destructive so a transport blip does not blank a dashboard. Across an identity change that is exactly wrong: a failed refetch must leave the screen empty rather than populated with the previous tenant's rows.
2. **Only a change to a NON-NULL identity resets.** Resetting on logout could only fire requests that 401 from the login screen.
3. **Each controller's reset is isolated.** One failure logs and does not abort the others.

## Route middleware

Two guards ship ready to register as the `auth` and `guest` aliases in the app's `Kernel`:

| Middleware | Redirects | Destination |
|:-----------|:----------|:------------|
| `EnsureAuthenticated` | a visitor away from a protected page | `MagicStarterConfig.loginRoute()` |
| `RedirectIfAuthenticated` | a signed-in user away from a guest page | `MagicStarterConfig.homeRoute()` |

Both override `redirectTarget` (a pre-build synchronous redirect) rather than `handle` (a post-build remount), so a guarded page never mounts for someone who is about to be sent away. Each one guards its own destination so the redirect cannot loop, which matters because go_router raises after more than five successive redirects.

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

## Settings page width

`MagicStarter.manager.settingsMaxWidthClassName` (default `MagicStarterManager.defaultSettingsMaxWidth`, `max-w-7xl`) is the width cap the settings scaffold centres its content column at. Set it from the same constant the host's own page container uses, or the two columns centre inside the same content region at different widths:

```dart
MagicStarter.manager.settingsMaxWidthClassName = PageContainer.maxWidthClassName;
```

> [!NOTE]
> The next release renames this to `pageContainerClassName` and widens it to carry the whole geometry (cap plus edge margins plus vertical rhythm). Passing a bare cap stays valid, so the one-value call above survives the rename.

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
| Published view not loading | `dart run magic:artisan starter:publish` copies views to `lib/resources/views/starter/`. Auto-wire adds `MagicStarter.view.register()` to AppServiceProvider. |
| `Icons.*` in `build()` | Extract as `static const _iconName = Icons.xxx`. Required for Flutter web tree-shaking. |
| `brandBuilder` + `brandClassName` both set | `brandBuilder` wins. `brandClassName` is ignored when a builder is registered. |
| Hardcoding dialog classNames | All modal classNames must come from `MagicStarter.manager.modalTheme`. Never hardcode in widget build methods. |
| Navigation theme not affecting UI | `MagicStarter.useNavigationTheme()` must be called before the app layout is first painted. |
| Bottom nav visible on fullscreen routes | Wrap route widget with `MagicStarterHideBottomNav(child: widget)` to hide mobile bottom nav. |
| Published view not auto-wired | `dart run magic:artisan starter:doctor` detects published but unregistered views. Re-run publish or manually add `MagicStarter.view.register()`. |
