## Magic.init() Lifecycle

The bootstrap process follows a strict sequence executed via `Magic.init()`:

1. **Load Environment** — `Env.load(fileName)`
2. **Evaluate Config Factories** — Execute `configFactories` closures (after Env is loaded)
3. **Initialize MagicApp** — Merge default framework configs with user-provided configs
4. **Bind Core Services** — Register internal services (e.g., `LogManager`)
5. **Register Configured Providers** — Load providers from `Config.get('app.providers')`
6. **Register Runtime Providers** — Add providers passed to `Magic.init()`
7. **Boot All Providers** — Async call `boot()` on all registered `ServiceProvider`s
8. **Pre-build Router** — Finalize `MagicRouter.instance.routerConfig` before app runs

**CRITICAL**: `Magic.init()` MUST be awaited in `main()` before any facade or container access.

```dart
import 'package:magic/magic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    envFileName: '.env',
    configFactories: [
      () => appConfig,
      () => authConfig,
      () => networkConfig,
    ],
    providers: [
      AuthServiceProvider(Magic.app),
    ],
  );

  runApp(const MagicApplication());
}
```

### Magic.init() Parameters

```dart
static Future<void> init({
  String envFileName = '.env',
  List<Map<String, dynamic>> configs = const [],
  List<Map<String, dynamic> Function()> configFactories = const [],
  List<ServiceProvider> providers = const [],
})
```

- **`envFileName`** — Path to `.env` file (default: `.env`)
- **`configs`** — Static config maps evaluated immediately (before `Env` is loaded, so `Env.get()` won't work here)
- **`configFactories`** — Config closures evaluated after `Env.load()` completes (use this for values that depend on `Env.get()`)
- **`providers`** — Runtime service providers added in addition to those in `Config.get('app.providers')`

### configFactories vs configs

Use **`configFactories`** when your config values depend on environment variables. The distinction is critical:

```dart
// ❌ Wrong — Env not loaded yet, DB_HOST will be null
await Magic.init(
  configs: [
    {
      'database': {
        'host': Env.get('DB_HOST', 'localhost'),
      },
    },
  ],
);

// ✅ Correct — Env is loaded, DB_HOST is available
await Magic.init(
  configFactories: [
    () => {
      'database': {
        'host': Env.get('DB_HOST', 'localhost'),
      },
    },
  ],
);
```

## IoC Container (Magic.make, Magic.put, Magic.singleton)

The `MagicApp` container manages service resolution. Access via `Magic.*` static methods.

### Service Binding

```dart
// Bind a factory — new instance each call
Magic.bind('logger', () => Logger());

// Bind a singleton — same instance every call
Magic.singleton('database', () => DatabaseConnection());

// Store an existing instance
final config = Config.load();
Magic.app.setInstance('config', config);
```

### Service Resolution

```dart
// Resolve a service
final db = Magic.make<DatabaseConnection>('database');

// Check if a service is bound
if (Magic.bound('cache')) {
  final cache = Magic.make<CacheService>('cache');
}
```

### Container Methods

| Method | Signature | Purpose |
|--------|-----------|---------|
| `Magic.bind()` | `void bind(String key, Function closure, {bool shared = false})` | Register a factory. If `shared: true`, acts as singleton. |
| `Magic.singleton()` | `void singleton(String key, Function closure)` | Lazy singleton — instantiated once, cached thereafter. |
| `Magic.make()` | `T make<T>(String key)` | Resolve service from container. Throws if not registered. |
| `Magic.app.setInstance()` | `void setInstance(String key, dynamic value)` | Bind an already-instantiated object to a key. |
| `Magic.bound()` | `bool bound(String key)` | Check if a service is registered. |
| `Magic.flush()` | `void flush()` | Clear all bindings and instances (for testing). |
| `MagicApp.reset()` | `static void reset()` | Destroy the entire `MagicApp` singleton (for test teardown). |

### Resolution Order

1. Check `_instances` map (cached singletons)
2. Check `_bindings` map (factory definitions)
3. Throw exception if not found

## Controller Management

Shortcuts for managing UI controllers as type-keyed singletons. Useful for accessing state from anywhere without BuildContext.

```dart
// Register a controller instance
final userController = UserController();
Magic.put(userController);

// Resolve it by type
final controller = Magic.find<UserController>();

// Resolve or create if missing
final controller = Magic.findOrPut(UserController.new);

// Check if registered
if (Magic.isRegistered<UserController>()) {
  // ...
}

// Remove it
Magic.delete<UserController>();
```

### Singleton Accessor Pattern

```dart
class UserController extends MagicController {
  // Lazy singleton accessor — create on first access
  static UserController get instance => Magic.findOrPut(UserController.new);
}

// Usage from anywhere
UserController.instance.fetchUser();
```

### Controller Methods

| Method | Purpose |
|--------|---------|
| `Magic.put<T>(controller)` | Register a controller instance by type `T`. |
| `Magic.find<T>()` | Resolve a controller by type. Throws if not registered. |
| `Magic.findOrPut<T>(T Function() builder)` | Resolve or create if missing. **Preferred pattern.** |
| `Magic.delete<T>()` | Remove a controller from the registry. |
| `Magic.isRegistered<T>()` | Check if type `T` is registered. |

## ServiceProvider Lifecycle

Abstract class for organizing service bindings and initialization logic into modules.

### Two-Phase Lifecycle

**Phase 1: `register()`** — Synchronous, called immediately when provider is registered. Only bind services here; do not access other services.

**Phase 2: `boot()`** — Asynchronous, called after ALL providers are registered. Safe to resolve other services and perform initialization.

### Example

```dart
import 'package:magic/magic.dart';

class AuthServiceProvider extends ServiceProvider {
  AuthServiceProvider(super.app);

  @override
  void register() {
    // Bind services into container
    app.singleton('auth', () => AuthManager());
    app.bind('guard', () => BearerTokenGuard());
  }

  @override
  Future<void> boot() async {
    // All providers are now registered; safe to resolve
    final auth = app.make<AuthManager>('auth');

    // Perform initialization that depends on other services
    Auth.manager.setUserFactory((data) => User.fromMap(data));

    // Register policies, listeners, or other boot-time logic
    Gate.define('view-profile', (user, profile) {
      return user.id == profile.userId;
    });
  }
}
```

### Registering Providers

**Via config:**
```dart
// config/app.dart
return {
  'app': {
    'providers': [
      (app) => RouteServiceProvider(app),
      (app) => AuthServiceProvider(app),
      (app) => DatabaseServiceProvider(app),
    ],
  },
};
```

**Via runtime:**
```dart
await Magic.init(
  providers: [
    AuthServiceProvider(Magic.app),
    MyCustomProvider(Magic.app),
  ],
);
```

## Environment & Configuration

### Env.get() — Environment Variables

```dart
import 'package:magic/magic.dart';

// Load .env file (called by Magic.init())
await Env.load(fileName: '.env');

// Get with default fallback
final dbHost = Env.get('DB_HOST', 'localhost');
final apiKey = Env.get<String>('API_KEY', '');
final port = Env.get<int>('PORT', 5432);
final debug = Env.get<bool>('DEBUG', false);

// Type casting
// - 'true', '1', 'yes' (case-insensitive) → bool true
// - Numeric strings → int or double
// - Other strings → String as-is

// Check existence
if (Env.has('STRIPE_KEY')) {
  initStripe();
}

// Get all env vars
final all = Env.all();
```

### Config.get() — Configuration Values

```dart
import 'package:magic/magic.dart';

// Get with dot notation
final appName = Config.get('app.name');
final cacheDriver = Config.get('cache.driver', 'memory');
final dbPort = Config.get<int>('database.port', 5432);

// Set at runtime
Config.set('cache.ttl', 3600);
Config.set('app.debug', false);

// Check existence
if (Config.has('services.stripe')) {
  initStripe();
}

// Get all config
final all = Config.all();

// Merge additional config
Config.merge({
  'database': {
    'host': 'production.db.example.com',
  },
});
```

### Pattern: Environment-Aware Configs

Use `configFactories` to build configs that reference environment variables:

```dart
import 'package:magic/magic.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Magic.init(
    configFactories: [
      // Database config depends on Env
      () => {
        'database': {
          'driver': 'sqlite',
          'path': Env.get('DATABASE_PATH', ':memory:'),
        },
      },
      // API config depends on Env
      () => {
        'services': {
          'api': {
            'url': Env.get('API_URL', 'http://localhost:8000'),
            'timeout': Env.get<int>('API_TIMEOUT', 30),
          },
        },
      },
    ],
  );

  runApp(const MagicApplication());
}
```

## Testing: Reset & Flush

Always reset the app between tests to ensure clean state.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

void main() {
  group('MyController', () {
    setUp(() async {
      // Reset the singleton and flush container
      MagicApp.reset();
      Magic.flush();

      // Re-initialize for this test
      await Magic.init(
        configFactories: [() => {'app': {}}],
      );

      // Inject test doubles
      Magic.put(MockAuthService());
    });

    tearDown(() {
      // Clean up after each test
      MagicApp.reset();
      Magic.flush();
    });

    test('loads user on init', () async {
      final controller = MyController();
      // ...
    });
  });
}
```

### Reset Methods

| Method | Purpose |
|--------|---------|
| `MagicApp.reset()` | Destroy the `MagicApp` singleton instance. Clears all state. |
| `Magic.flush()` | Clear all container bindings, instances, and controllers. |
| `Env.reset()` | Clear loaded environment variables (for testing). |

## Key Gotchas

- **Async Init**: Always `await Magic.init()`. Never use `.then()` — providers won't boot reliably.
- **Config Factories**: `configs` parameter won't have access to `Env.get()`. Use `configFactories` when you need environment variables.
- **Router Access**: `MagicRouter.instance.routerConfig` is `null` until `Magic.init()` completes.
- **Unregistered Services**: `Magic.make()` throws if service not bound. Use `Magic.bound()` to check first.
- **Not Auto-Registered**: `EncryptionServiceProvider` is not auto-registered. Add manually to `app.providers` if needed.
- **Test Cleanup**: Always call `MagicApp.reset()` + `Magic.flush()` in `setUp()` and `tearDown()`.
