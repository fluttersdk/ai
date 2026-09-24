# Routing & Navigation

Comprehensive guide to route registration, context-free navigation, middleware, transitions, and persistent layouts in the Magic framework.

## Contents

- [Route Registration](#route-registration)
- [Fluent Route Definition API](#fluent-route-definition-api)
- [Route Groups](#route-groups)
- [Resource Routes (ResourceController)](#resource-routes-resourcecontroller)
- [Persistent Layouts (Shell Routes)](#persistent-layouts-shell-routes)
- [Route Transitions](#route-transitions)
- [Stacking and the Back Button](#stacking-and-the-back-button)
- [Context-Free Navigation](#context-free-navigation)
- [Path & Query Parameters](#path--query-parameters)
- [Named Routes](#named-routes)
- [Intended URL (Redirect-After-Login Pattern)](#intended-url-redirect-after-login-pattern)
- [Middleware Pipeline](#middleware-pipeline)
- [RouteServiceProvider Pattern](#routeserviceprovider-pattern)
- [Router Configuration](#router-configuration)
- [Key Patterns](#key-patterns)
- [URL Strategy (Web)](#url-strategy-web)
- [Navigator Observers](#navigator-observers)
- [Page Titles](#page-titles)
- [Gotchas](#gotchas)

## Route Registration

Routes are registered using the `MagicRoute.page()` method. Each route maps a path to a widget builder function.

```dart
import 'package:magic/magic.dart';

// Simple route
MagicRoute.page('/', () => HomePage());

// Route with path parameters (accessed via handler signature)
MagicRoute.page('/users/:id', (id) => UserPage(id: id));

// Fluent API for advanced configuration
MagicRoute.page('/dashboard', () => DashboardPage())
    .name('dashboard')
    .middleware(['auth'])
    .transition(RouteTransition.fade);
```

Path parameters are injected directly into the handler function signature. The framework matches parameter count and passes them in order.

```dart
// Single parameter
MagicRoute.page('/posts/:id', (id) => PostPage(id: id));

// Multiple parameters
MagicRoute.page('/users/:userId/posts/:postId', (userId, postId) {
  return PostDetailPage(userId: userId, postId: postId);
});
```

## Fluent Route Definition API

After calling `MagicRoute.page()`, chain these methods:

| Method | Purpose | Example |
|--------|---------|---------|
| `.name(String)` | Assign a name for named navigation | `.name('users.show')` |
| `.title(String)` | Set page title (document.title on web, app switcher on mobile) | `.title('Dashboard')` |
| `.middleware(List<dynamic>)` | Attach middleware (aliases or factories) | `.middleware(['auth', 'admin'])` |
| `.transition(RouteTransition)` | Set page transition animation | `.transition(RouteTransition.slideUp)` |
| `.stacked([bool])` | Push instead of replacing the stack, so the route can be popped | `.stacked()` |
| `.swipeBack(bool)` | Allow or refuse the platform back gesture on this route | `.swipeBack(false)` |

## Route Groups

Group related routes to share a prefix, middleware, or layout.

```dart
MagicRoute.group(
  prefix: '/admin',
  middleware: ['auth', 'admin'],
  routes: () {
    MagicRoute.page('/', () => AdminDashboard());
    MagicRoute.page('/users', () => AdminUsersPage());
    MagicRoute.page('/settings', () => AdminSettingsPage());
  },
);
```

Nested groups combine their prefixes and middleware:

```dart
MagicRoute.group(
  prefix: '/api',
  routes: () {
    MagicRoute.group(
      prefix: '/v1',
      middleware: ['api-auth'],
      routes: () {
        MagicRoute.page('/status', () => ApiStatusPage()); // /api/v1/status
      },
    );
  },
);
```

### Route Group Options

| Option | Type | Purpose |
|--------|------|---------|
| `prefix` | `String?` | URL prefix for all routes in the group |
| `middleware` | `List<dynamic>` | Middleware applied to all routes |
| `as` | `String?` | Named prefix (e.g., 'admin.') for route names |
| `layout` | `Widget Function(Widget)` | Persistent shell layout for grouped routes |
| `layoutId` | `String?` | Layout identifier for merging groups with same layout |
| `routes` | `void Function()` | Callback to register child routes |

## Resource Routes (ResourceController)

`MagicRoute.resource(name, controller, {only, except})` auto-wires up to four canonical GET routes to a controller that mixes in `ResourceController`. Each generated `RouteDefinition` gets an auto-assigned `{slug}.{method}` name and title (slug is the normalized `name`, so a nested path like `/admin/users` produces `admin/users.index`).

```dart
static List<RouteDefinition> MagicRoute.resource(
  String name,
  ResourceController controller, {
  List<String>? only,      // whitelist of methods
  List<String>? except,    // blacklist of methods
});
```

### Generated routes

| Path | HTTP-style method | ResourceController hook |
|------|-------------------|-------------------------|
| `GET /{name}` | `index` | `Widget index()` |
| `GET /{name}/create` | `create` | `Widget create()` |
| `GET /{name}/:id` | `show` | `Widget show(String id)` |
| `GET /{name}/:id/edit` | `edit` | `Widget edit(String id)` |

### ResourceController mixin

```dart
mixin ResourceController {
  /// Override to expose only a subset. Default: {'index', 'create', 'show', 'edit'}.
  Set<String> get resourceMethods => const {'index', 'create', 'show', 'edit'};

  Widget index() => throw UnimplementedError();
  Widget create() => throw UnimplementedError();
  Widget show(String id) => throw UnimplementedError();
  Widget edit(String id) => throw UnimplementedError();
}
```

### Usage

```dart
class UserRoutes with ResourceController {
  @override Set<String> get resourceMethods => {'index', 'create', 'show', 'edit'};
  @override Widget index() => const UserListView();
  @override Widget create() => const UserCreateView();
  @override Widget show(String id) => UserShowView(id: id);
  @override Widget edit(String id) => UserEditView(id: id);
}

// In RouteServiceProvider.register():
MagicRoute.resource('users', UserRoutes());                         // all four methods
MagicRoute.resource('posts', PostRoutes(), only: ['index', 'show']); // read-only
MagicRoute.resource('teams', TeamRoutes(), except: ['edit']);       // all except edit
```

Resolution rules:
- `name` is normalized — collapses repeated slashes, strips leading/trailing slashes.
- `only` / `except` narrow the set further, but only **within** `resourceMethods` (so a controller that lists `['index', 'show']` cannot expose `edit` even via `only`).
- Unknown method names in `only` or `except` throw `ArgumentError` at registration time, not at navigation.

## Persistent Layouts (Shell Routes)

Use layouts to maintain persistent UI (tabs, navigation rails, sidebars) while child routes change.

### Via Route Group

```dart
MagicRoute.group(
  layout: (child) => AppLayout(
    sidebar: NavigationSidebar(),
    child: child,
  ),
  routes: () {
    MagicRoute.page('/dashboard', () => DashboardPage());
    MagicRoute.page('/settings', () => SettingsPage());
  },
);
```

The layout builder receives the child widget and returns the wrapped layout.

### Via Direct Layout Registration

```dart
MagicRoute.layout(
  id: 'main-layout',
  builder: (child) => AppLayout(child: child),
  routes: [
    MagicRoute.page('/dashboard', () => DashboardPage()),
    MagicRoute.page('/profile', () => ProfilePage()),
  ],
);
```

Multiple layout groups with the same ID merge their routes under a single layout shell.

### Above Every Route: `MagicApplication.builder`

A layout belongs to its routes, so a `to()` to an unstacked route outside the group disposes it. For a widget that must survive every navigation (a floating video player whose platform view must never be remounted, a global banner), wrap the router instead:

```dart
MagicApplication(
  builder: (context, child) => Stack(
    children: [
      child!,
      const FloatingPlayer(),
    ],
  ),
)
```

Passed straight to `MaterialApp.builder`: the builder runs inside `Theme`, localizations, `Directionality` and `MediaQuery`, `child` is the `Router` (which builds the root Navigator), and the layer's State survives every `to()`, push and `back()`. From the layer's own context `Navigator.of` and `Overlay.of` find nothing: navigate with `MagicRoute`, open dialogs with `Magic.dialog()`, and put an `Overlay` inside the layer around any `Tooltip`, `WPopover` or `WSelect`, which throw without one. `Magic.reload()` (and `Lang.setLocale()` without `reload: false`) remounts the layer with a new State. The loading and failure screens before init are not wrapped; null wraps nothing.

## Route Transitions

Built-in transition animations via the `RouteTransition` enum:

| Value | Animation | Back gesture |
|-------|-----------|--------------|
| `RouteTransition.none` (default) | No animation (instant page switch) | no |
| `RouteTransition.platform` | The running platform's own | yes |
| `RouteTransition.fade` | Cross-fade effect | no |
| `RouteTransition.slideRight` | Slide in from right, slide out to left | no |
| `RouteTransition.slideUp` | Slide in from bottom | no |
| `RouteTransition.scale` | Scale up with fade | no |

```dart
MagicRoute.page('/modal', () => ModalPage())
    .transition(RouteTransition.slideUp);

MagicRoute.page('/details', () => DetailsPage())
    .transition(RouteTransition.slideRight);
```

Only `platform` carries a gesture. Flutter installs the iOS back-swipe detector inside `CupertinoPageTransition`, so a custom transition on a bare page route never reaches it; `platform` routes through `PageTransitionsTheme` instead and picks up the Cupertino slide plus its swipe on iOS and macOS, predictive back on Android, and the zoom on Windows and Linux.

Override what `platform` looks like on `MagicApplication`, not per route:

```dart
MagicApplication(
  pageTransitionsTheme: const PageTransitionsTheme(
    builders: {
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
    },
  ),
)
```

Applied with `copyWith`, so the Wind theme is otherwise untouched, and null changes nothing. A per-route value cannot express the case this exists for: the transition is chosen once at registration, and what an app usually wants is the native animation on mobile and none on desktop or web.

A partial map is a partial override. A platform left out of `builders` keeps its own default, so omitting `TargetPlatform.iOS` leaves the Cupertino slide and its swipe in place; what removes the gesture is naming iOS and giving it a different builder.

## Stacking and the Back Button

`MagicRoute.to()` calls `go()`, which REPLACES the Navigator's page list. With one page there is nothing to pop, so there is no swipe, and on Android there is no back button either: Flutter reports `canHandlePop: false` and the embedder unregisters its back callback, so the system back leaves the app.

Mark the routes a reader drills INTO and leave the ones they switch BETWEEN alone, or a re-tapped nav destination grows the stack:

```dart
MagicRoute.page('/monitors', () => MonitorsPage());

MagicRoute.page('/monitors/:id', (id) => MonitorPage(id))
    .stacked()
    .transition(RouteTransition.platform);
```

App-wide defaults, set before the router is built:

```dart
MagicRouter.instance.defaultStacked = true;
MagicRouter.instance.defaultTransition = RouteTransition.platform;
```

Leave `defaultStacked` off on web: `go()` already gives a working browser Back. A route you do stack still owns the address bar there, because the router turns on go_router's `optionURLReflectsImperativeAPIs`, so a pushed detail page shows its own url and can be deep-linked. That flag covers every push (`MagicRoute.push()`, a go_router `context.push`), and a reload brings back only the path: no go_router `extra`, and no page beneath for `back()` without a `fallback`.

`back()` is unchanged and still prefers the native pop, so the history fallback keeps covering unstacked routes.

`toNamed()` resolves the name to a location and hands it to `to()`, so a stacked route pushes whichever verb reaches it. The page type is `MagicPlatformPage`, exported for a type check and never constructed by hand.

Navigating to the path you are already on turns on the query: naming none is a re-tapped destination and does nothing, and naming one swaps the top page while the stack under it survives.

The swap REBUILDS the screen rather than remounting it, which is what a query change does everywhere in Magic: go_router keys a page on the matched path and the query is not part of it. So read the query in `build()`, never in `initState()`, and do not register the page as a `const` widget, or nothing rebuilds at all.

`swipeBack(false)` refuses the gesture ALONE; the route is still popped by Android back, by your own chrome and by `back()`. Use `PopScope` when the route should not be left at all, which Flutter's gesture already honours.

A drawer and the swipe do not fight over the left edge: the gesture is refused on a route with nothing under it, so the detector never enters the arena on the drawer's own screen.

## Context-Free Navigation

Navigate from anywhere without `BuildContext`: controllers, services, callbacks.

```dart
import 'package:magic/magic.dart';

// Navigate to a path
MagicRoute.to('/dashboard');
MagicRoute.to('/users/42');

// Navigate with query parameters
MagicRoute.to('/search', query: {'q': 'flutter'});

// Navigate to a named route
MagicRoute.toNamed('users.show', params: {'id': '42'});

// Push onto stack (preserves history). Before the router has mounted, this
// replaces instead: a cold-start deeplink has no stack to push onto, and
// pushing there leaves an empty location every later read answers from.
// `to()` on a `.stacked()` route behaves the same way.
MagicRoute.push('/details');

// Go back (works across shell routes — history-based fallback automatic)
MagicRoute.back();

// Go back with explicit fallback when history stack is empty
MagicRoute.back(fallback: '/home');

// Replace current route (swaps last history entry, no stack growth)
MagicRoute.replace('/home');
```

## Path & Query Parameters

Access parameters from the current route:

```dart
// Extract from route definition
MagicRoute.page('/posts/:id', (id) {
  // `id` is injected directly
  return PostPage(id: id);
});

// Access globally from anywhere
final id = MagicRouter.instance.pathParameter('id');
final query = MagicRouter.instance.queryParameter('q');

// Get all parameters at once
final allPathParams = MagicRouter.instance.pathParameters;
final allQueryParams = MagicRouter.instance.queryParameters;

// Current location (path + query)
final location = MagicRouter.instance.currentLocation;

// Current path only (without query string)
final path = MagicRouter.instance.currentPath;
```

## Named Routes

Assign names to routes for navigation without hardcoding paths.

```dart
MagicRoute.page('/users/:id', (id) => UserPage(id: id))
    .name('users.show');

MagicRoute.page('/posts/:id/edit', (id) => EditPostPage(id: id))
    .name('posts.edit');

// Navigate by name
MagicRoute.toNamed('users.show', params: {'id': '42'});
MagicRoute.toNamed('posts.edit', params: {'id': 'abc'}, query: {'tab': 'content'});
```

## Intended URL (Redirect-After-Login Pattern)

Save a user's intended destination before redirecting to login, then restore it after authentication.

```dart
// Inside auth middleware
if (!Auth.check()) {
  MagicRouter.instance.setIntendedUrl(currentPath);
  MagicRoute.replace('/login');
}

// Inside login success handler
final intended = MagicRouter.instance.pullIntendedUrl();
MagicRoute.to(intended ?? '/');
```

`pullIntendedUrl()` returns and clears the URL (one-time read).

## Middleware Pipeline

Middleware intercepts navigation to enforce authentication, authorization, logging, etc.

### Registration

Middleware must be registered in the `Kernel` (usually in `lib/app/kernel.dart`):

```dart
import 'package:magic/magic.dart';

class Kernel extends HttpKernel {
  @override
  void registerMiddleware() {
    // Named middleware (referenced by string alias)
    registerAll({
      'auth': () => EnsureAuthenticated(),
      'guest': () => RedirectIfAuthenticated(),
      'admin': () => EnsureAdmin(),
    });

    // Global middleware (runs on every route)
    global([
      () => LoggingMiddleware(),
    ]);
  }
}
```

### Attachment

Attach middleware to routes or groups:

```dart
// Route-level
MagicRoute.page('/admin', () => AdminPage())
    .middleware(['auth', 'admin']);

// Group-level
MagicRoute.group(
  middleware: ['auth'],
  routes: () {
    MagicRoute.page('/dashboard', () => DashboardPage());
  },
);
```

### Implementation

```dart
import 'package:magic/magic.dart';

class EnsureAuthenticated extends MagicMiddleware {
  @override
  String? redirectTarget(String location) {
    // Evaluated pre-build in the router redirect; the destination view
    // mounts exactly once. Return null to allow navigation.
    if (!Auth.check() && location != '/login') {
      MagicRouter.instance.setIntendedUrl(location);
      return '/login';
    }
    return null;
  }
}
```

The `handle()` hook must call `next()` to proceed; if it doesn't, the pipeline halts and the route is blocked. Redirect-style guards (the example above) instead override `redirectTarget`, which resolves before the route builds and never interacts with `next()`.

## RouteServiceProvider Pattern

Organize routing in a `ServiceProvider`:

```dart
import 'package:magic/magic.dart';

import '../kernel.dart';
import '../../routes/app.dart';

class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  void register() {
    registerKernel();      // Register middleware
    registerAppRoutes();   // Register routes
  }

  @override
  Future<void> boot() async {
    // Async initialization if needed
  }
}
```

Then define routes in a dedicated file:

```dart
// lib/routes/app.dart
import 'package:magic/magic.dart';
import '../resources/views/home_page.dart';

void registerAppRoutes() {
  MagicRoute.page('/', () => HomePage());

  MagicRoute.group(
    prefix: '/admin',
    middleware: ['auth', 'admin'],
    routes: () {
      MagicRoute.page('/dashboard', () => AdminDashboardPage());
    },
  );
}
```

## Router Configuration

Access the `GoRouter` instance for `MaterialApp.router`:

```dart
import 'package:flutter/material.dart';
import 'package:magic/magic.dart';

void main() async {
  await Magic.init(configFactories: [() => appConfig]);

  runApp(MaterialApp.router(
    title: 'My App',
    routerConfig: MagicRoute.config,
    theme: ThemeData.light(),
  ));
}
```

## Key Patterns

**Redirect After Login**

```dart
// Middleware
class EnsureAuthenticated extends MagicMiddleware {
  @override
  String? redirectTarget(String location) {
    if (!Auth.check() && location != '/login') {
      MagicRouter.instance.setIntendedUrl(location);
      return '/login';
    }
    return null;
  }
}

// Login success
final intended = MagicRouter.instance.pullIntendedUrl();
MagicRoute.to(intended ?? '/');
```

**Nested Route Groups**

```dart
MagicRoute.group(
  prefix: '/api',
  middleware: ['api-rate-limit'],
  routes: () {
    MagicRoute.group(
      prefix: '/v1',
      middleware: ['api-auth'],
      routes: () {
        MagicRoute.page('/status', () => ApiStatusPage()); // /api/v1/status
      },
    );
  },
);
```

**Persistent Navigation Layout**

```dart
MagicRoute.layout(
  builder: (child) => DashboardShell(
    navigation: BottomNavigationBar(items: [...]),
    child: child,
  ),
  routes: [
    MagicRoute.page('/dashboard', () => DashboardHome()),
    MagicRoute.page('/settings', () => SettingsPage()),
  ],
);
```

## URL Strategy (Web)

Flutter web defaults to hash-based URLs (`/#/path`). Set `url_strategy` in routing config to `'path'` for clean path-based URLs (`/path`), or `'hash'` to explicitly keep hash-based URLs:

```dart
'routing': {
  'url_strategy': 'path', // 'path' | 'hash' | null (default: null — hash strategy)
},
```

No effect on iOS, Android, or desktop. Requires server-side fallback to `index.html` for all routes (e.g., nginx `try_files $uri $uri/ /index.html`).

## Navigator Observers

Register `NavigatorObserver` instances for analytics, monitoring, or performance tracking. Observers must be registered before the router is built.

```dart
// In RouteServiceProvider.boot()
MagicRouter.instance.addObserver(SentryNavigatorObserver(
  enableAutoTransactions: true,
  setRouteNameAsTransaction: true,
));

MagicRouter.instance.addObserver(FirebaseAnalyticsObserver(
  analytics: FirebaseAnalytics.instance,
));
```

Read-only access to registered observers:

```dart
final observers = MagicRouter.instance.observers; // List<NavigatorObserver> (unmodifiable)
```

Observers are passed to GoRouter's `observers` parameter automatically. Adding observers after `routerConfig` is accessed throws `StateError`.

## Page Titles

Automatic page title management via `TitleManager` singleton. Uses `SystemChrome.setApplicationSwitcherDescription` which updates the browser tab title on web and the app switcher on mobile.

### Title Suffix

```dart
MagicApplication(
  title: 'My App',
  titleSuffix: 'Kodizm.AI',
)
// Page titles render as "Dashboard - Kodizm.AI"
```

### Static Route Titles

```dart
MagicRoute.page('/dashboard', () => DashboardPage())
    .title('Dashboard');
```

### MagicTitle Widget (Dynamic Titles)

```dart
MagicTitle(
  title: project.name, // data-dependent
  child: ProjectContent(),
)
```

Sets override on mount, updates on rebuild, clears on dispose.

### Imperative API

```dart
MagicRoute.setTitle('Custom Title');
final title = MagicRoute.currentTitle; // without suffix
```

### Resolution Priority

1. `MagicTitle` / `MagicRoute.setTitle()` — override
2. `RouteDefinition.title()` — route-level
3. `MagicApplication.title` — fallback

### TitleManager (Internal)

- `TitleManager.instance` — singleton, lazy-initialized
- `TitleManager.configure(onTitleChanged: callback)` — injectable callback for testing
- `TitleManager.reset()` — clears state, called by `MagicRouter.reset()`
- Route listener: `GoRouter.routerDelegate.addListener` — fires on all navigation types

## Gotchas

- **Observer Registration Timing:** Observers must be added before `routerConfig` is accessed, same as routes. Register in `RouteServiceProvider.boot()`.
- **Route Registration Timing:** Routes must be registered during `ServiceProvider.register()` or `boot()`. They cannot be added after `MagicRouter.instance.routerConfig` is accessed.
- **Middleware Next Required:** Middleware must call `next()` to allow the request to proceed. Failing to call it halts the pipeline.
- **Path Parameters:** Parameters are injected by position into the handler function. Ensure the function signature matches the number of parameters in the route.
- **Named Routes:** Only use named navigation if the route was explicitly named with `.name()`.
- **Replace vs. To:** `replace()` leaves history untouched — `back()` still returns to the route before the replaced one. Use for login redirects and splash screens where the replaced route should not appear in back navigation.
- **back() across shells:** `MagicRoute.back()` works across shell (layout) routes. Magic tracks navigation history automatically via `to()` and `toNamed()` on an unstacked route; a stacked one records nothing, because the pushed page IS the record and `back()` prefers the native pop. Use `fallback:` for guaranteed behavior when history is empty: `MagicRoute.back(fallback: '/home')`.
- **Intended URL Cleanup:** `pullIntendedUrl()` is a one-time read that clears the stored URL. Call it only once per login flow.
