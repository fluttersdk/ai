# Routing & Navigation

Comprehensive guide to route registration, context-free navigation, middleware, and route transitions in the Magic framework.


## Route Registration

Routes are registered using the `MagicRoute` class. A route maps a path to a widget, usually returned by a controller.

```dart
// Simple page registration
MagicRoute.page('/monitors', () => MonitorController.instance.index());
MagicRoute.page('/monitors/:id', () => MonitorController.instance.show());

// Fluent builder for advanced configuration
MagicRoute.page('/admin', () => AdminController.instance.index())
    .name('admin.index')
    .middleware(['auth'])
    .transition(RouteTransition.fade);
```

### RouteDefinition Fluent API

| Method | Purpose |
|--------|---------|
| `.name(String)` | Assigns a unique name for named navigation. |
| `.middleware(List<dynamic>)` | Applies middleware aliases (Strings) or factory functions. |
| `.transition(RouteTransition)` | Sets the page transition animation for this route. |

## Route Groups

Groups allow you to apply shared layouts (ShellRoutes) and middleware to a set of routes.

```dart
MagicRoute.group(
  layout: (child) => AppLayout(child: child),
  middleware: ['auth'],
  routes: () {
    MagicRoute.page('/', () => DashboardController.instance.index());
    MagicRoute.page('/monitors', () => MonitorController.instance.index());
    MagicRoute.page('/monitors/:id', () => MonitorController.instance.show());
  },
);
```

## Route Transitions

Magic supports several built-in transition animations via the `RouteTransition` enum.

| Value | Animation |
|-------|-----------|
| `RouteTransition.none` | Uses the platform-default transition. |
| `RouteTransition.fade` | Cross-fade effect. |
| `RouteTransition.slideRight` | Slides in from the right. |
| `RouteTransition.slideUp` | Slides in from the bottom. |
| `RouteTransition.scale` | Scales up while fading in. |

## Navigation API

Navigation is context-free, meaning you don't need a `BuildContext` to move between pages.

| Method | Purpose |
|--------|---------|
| `MagicRoute.to('/path')` | Standard push navigation to a path. |
| `MagicRoute.back()` | Pops the current route. |
| `MagicRoute.replace('/path')` | Replaces the current route (removes from history). |
| `MagicRoute.toNamed('name')` | Navigates using the route's assigned name. |

## Path & Query Parameters

Parameters are extracted from the current GoRouter state managed by `MagicRouter`.

```dart
// For route: '/monitors/:id'
final id = MagicRouter.instance.pathParameter('id');

// For route: '/search?q=flutter'
final query = MagicRouter.instance.queryParameter('q');
```

## Intended URL

Used to redirect users back to their original destination after a successful login.

```dart
// Inside a guest/auth middleware:
MagicRouter.instance.setIntendedUrl('/dashboard/settings');
MagicRoute.replace('/auth/login');

// Inside login logic after success:
final url = MagicRouter.instance.pullIntendedUrl(); // Returns and clears the stored URL
MagicRoute.to(url ?? '/');
```

## Middleware Pipeline

Middleware allows you to intercept navigation. They must be registered in the `Kernel`.

### Registration

Middleware must be registered in the `Kernel` before use. Use `Kernel.registerAll()` for bulk or `Kernel.register()` individually.

```dart
// Global middleware (runs on every route)
Kernel.global([
  () => LoggingMiddleware(),
]);

// Named route middleware
Kernel.registerAll({
  'auth': () => EnsureAuthenticated(),
  'guest': () => RedirectIfAuthenticated(),
});
```

**Kernel API:**

| Method | Purpose |
|--------|---------|
| `Kernel.global(List<MagicMiddleware Function()>)` | Middleware that runs on every route |
| `Kernel.register(String name, MagicMiddleware Function())` | Register a named middleware alias |
| `Kernel.registerAll(Map<String, MagicMiddleware Function()>)` | Bulk register named middleware |
| `Kernel.resolve(dynamic)` | Resolve by string alias, factory, or instance |
| `Kernel.execute(List<MagicMiddleware>)` | Run chain sequentially — returns `false` if halted |
| `Kernel.flush()` | Clear all middleware (for testing) |

### Implementation

```dart
class EnsureAuthenticated extends MagicMiddleware {
  @override
  void handle(void Function() next) {
    if (Auth.check()) {
      next(); // Proceed to next middleware or route
    } else {
      MagicRouter.instance.setIntendedUrl(currentPath);
      MagicRoute.replace('/auth/login');
      // Halting pipeline by NOT calling next()
    }
  }
}
```

## RouteServiceProvider Pattern

The recommended way to organize routing is within a `ServiceProvider`. Routes **must** be registered in the `register()` method.

```dart
class RouteServiceProvider extends ServiceProvider {
  RouteServiceProvider(super.app);

  @override
  void register() {
    registerKernel();    // Register middleware
    registerAppRoutes(); // Register actual routes
  }
}
```

## MagicApplication Widget

The root widget of your Flutter app that initializes the routing system and themes.

```dart
void main() async {
  await Magic.init(configFactories: [() => appConfig]);

  runApp(MagicApplication(
    title: 'My Magic App',
    windTheme: windTheme,
    onInit: () => Log.info('App starting...'),
  ));
}
```

## Gotchas

- **Registration Phase:** Routes must be registered during the `ServiceProvider.register()` phase. Registering in `boot()` is too late because the GoRouter configuration is generated during the bootstrap process.
- **Next is Required:** Middleware **must** call `next()` to allow the request to proceed. If `next()` is never called, the navigation will stall and the screen will remain unchanged.
- **Named Navigation:** Named navigation only works if you explicitly call `.name()` on the `RouteDefinition`.
- **Param Extraction:** `pathParameter()` and `queryParameter()` read directly from the current router state, not from a manual parsing of the URL string.
- **History Management:** `replace()` should be used carefully (e.g., after login or on splash screens) as it prevents the user from going "back" to that specific entry.
- **Root Widget:** `MagicApplication` is mandatory as it provides the `MaterialApp.router` configuration required by the framework.
