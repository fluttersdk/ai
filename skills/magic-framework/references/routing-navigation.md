# Routing & Navigation

Comprehensive guide to route registration, context-free navigation, middleware, transitions, and persistent layouts in the Magic framework.

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
| `.middleware(List<dynamic>)` | Attach middleware (aliases or factories) | `.middleware(['auth', 'admin'])` |
| `.transition(RouteTransition)` | Set page transition animation | `.transition(RouteTransition.slideUp)` |

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

## Route Transitions

Built-in transition animations via the `RouteTransition` enum:

| Value | Animation |
|-------|-----------|
| `RouteTransition.none` | No animation (instant page switch) |
| `RouteTransition.fade` | Cross-fade effect |
| `RouteTransition.slideRight` | Slide in from right, slide out to left |
| `RouteTransition.slideUp` | Slide in from bottom |
| `RouteTransition.scale` | Scale up with fade |

```dart
MagicRoute.page('/modal', () => ModalPage())
    .transition(RouteTransition.slideUp);

MagicRoute.page('/details', () => DetailsPage())
    .transition(RouteTransition.slideRight);
```

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

// Push onto stack (preserves history)
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
  void handle(void Function() next) {
    if (Auth.check()) {
      next(); // Proceed to next middleware or route
    } else {
      // Halt pipeline (do not call next())
      MagicRouter.instance.setIntendedUrl(MagicRouter.instance.currentLocation ?? '/');
      MagicRoute.replace('/login');
    }
  }
}
```

Middleware must call `next()` to proceed. If it doesn't, the pipeline halts and the route is blocked.

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
  void handle(void Function() next) {
    if (!Auth.check()) {
      MagicRouter.instance.setIntendedUrl(MagicRouter.instance.currentLocation ?? '/');
      MagicRoute.replace('/login');
    } else {
      next();
    }
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

## Gotchas

- **Route Registration Timing:** Routes must be registered during `ServiceProvider.register()` or `boot()`. They cannot be added after `MagicRouter.instance.routerConfig` is accessed.
- **Middleware Next Required:** Middleware must call `next()` to allow the request to proceed. Failing to call it halts the pipeline.
- **Path Parameters:** Parameters are injected by position into the handler function. Ensure the function signature matches the number of parameters in the route.
- **Named Routes:** Only use named navigation if the route was explicitly named with `.name()`.
- **Replace vs. To:** `replace()` leaves history untouched — `back()` still returns to the route before the replaced one. Use for login redirects and splash screens where the replaced route should not appear in back navigation.
- **back() across shells:** `MagicRoute.back()` works across shell (layout) routes. Magic tracks navigation history automatically via `to()` and `toNamed()`. Use `fallback:` for guaranteed behavior when history is empty: `MagicRoute.back(fallback: '/home')`.
- **Intended URL Cleanup:** `pullIntendedUrl()` is a one-time read that clears the stored URL. Call it only once per login flow.
