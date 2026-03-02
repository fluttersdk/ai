# Magic Framework: Bootstrap & Lifecycle

Reference for the Magic framework initialization process, IoC container mechanics, and core service patterns.


## Magic.init() Lifecycle

The bootstrap process follows a strict 7-step sequence executed via `Magic.init()`.

| Step | Operation | Description |
|------|-----------|-------------|
| 1 | `Env.load(fileName)` | Parse `.env` file into memory. |
| 2 | Execute `configFactories` | Run user config closures. `Env.get()` is now available. |
| 3 | `MagicApp.init()` | Merge default framework configs with user-provided configs. |
| 4 | Core Bindings | Register internal services (e.g., `LogManager` as 'log'). |
| 5 | Provider Registration | Load providers from `Config.get('app.providers')` + runtime providers. |
| 6 | `await MagicApp.boot()` | Asynchronously call `boot()` on all registered `ServiceProvider`s. |
| 7 | Router Pre-build | Finalize `MagicRouter.instance.routerConfig` to prevent web navigation glitches. |

**CRITICAL**: `Magic.init()` MUST be awaited in `main()` before any facade or container resolution.

```dart
void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    await Magic.init(
        configFactories: [
            () => appConfig,
            () => authConfig,
            () => networkConfig,
        ],
    );
    
    runApp(MagicApplication(title: 'My App'));
}
```

**Full `Magic.init()` signature:**
```dart
static Future<void> init({
    String envFileName = '.env',
    List<Map<String, dynamic>> configs = const [],
    List<Map<String, dynamic> Function()> configFactories = const [],
    List<ServiceProvider> providers = const [],
})
```

- `envFileName`: Custom `.env` file name (default `.env`).
- `configs`: Static config maps (evaluated immediately — `Env` not yet available).
- `configFactories`: Config closures (evaluated after `Env.load()` — use this when values depend on `Env.get()`).
- `providers`: Runtime providers added in addition to those in `Config.get('app.providers')`.

## IoC Container API (MagicApp)

The `MagicApp` container manages service resolution. Access via `Magic.make()` or internal `app` references.

| Method | Signature | Purpose |
|--------|-----------|---------|
| `bind` | `void bind(String key, Function closure, {bool shared = false})` | Register factory. If `shared: true`, it acts as a singleton. |
| `singleton` | `void singleton(String key, Function closure)` | Lazy singleton. Resolved once, shared thereafter. |
| `make` | `T make<T>(String key)` | Resolve service from container. |
| `setInstance` | `void setInstance(String key, dynamic value)` | Bind an existing object directly to a key. |
| `bound` | `bool bound(String key)` | Check if a key is registered in the container. |
| `flush` | `void flush()` | Clear all instances and bindings. |
| `reset` | `static void reset()` | Destroy the `MagicApp` singleton instance (useful for testing). |

**Resolution Flow**: Check `_instances` (cached singletons) → check `_bindings` (factories) → throw `ResolutionException` if not found.

## Controller Management

Shortcuts for managing UI controllers as singletons.

| Method | Purpose |
|--------|---------|
| `Magic.put<T>(controller)` | Manually register a controller instance. |
| `Magic.find<T>()` | Resolve a controller by its type `T`. |
| `Magic.findOrPut<T>(T Function() builder)` | Resolve or register if missing. **Preferred pattern.** |
| `Magic.delete<T>()` | Remove a controller from the container. |
| `Magic.isRegistered<T>()` | Check if type `T` is currently registered. |

**Singleton Accessor Pattern**:
```dart
class MonitorController extends MagicController {
    static MonitorController get instance => Magic.findOrPut(MonitorController.new);
}
```

## ServiceProvider

Abstract class for modular service registration and booting.

- `register()`: **Sync**. Only for binding to the container. Do not resolve other services here.
- `boot()`: **Async**. Safe to resolve other services and perform setup logic.

```dart
class AppServiceProvider extends ServiceProvider {
    AppServiceProvider(super.app);
    
    @override
    void register() {
        // Bind service to container
        app.singleton('api', () => ApiService());
    }
    
    @override
    Future<void> boot() async {
        // Safe to use facades or other services
        Auth.manager.setUserFactory((data) => User.fromMap(data));
        MonitorPolicy().register();
    }
}
```

**Registration in Config**:
```dart
// config/app.dart
'app': {
    'providers': [
        (app) => RouteServiceProvider(app),
        (app) => AppServiceProvider(app),
    ],
}
```

## Environment & Config

| Tool | API | Description |
|------|-----|-------------|
| **Env** | `Env.get<T>(key, [default])` | Reads from `.env`. Use global `env()` helper for brevity. |
- **Config Methods**: `Config.get<T>(key, [default])`, `Config.set(key, value)`, `Config.has(key)`, `Config.merge(Map)` — all use dot notation.
| **Config** | `Config.set(key, value)` | Runtime override of configuration values. |

**Pattern**: Use `configFactories` when values depend on `Env.get()`, ensuring the environment is loaded before the config is evaluated.

## Kernel (Middleware Registration)

Register named middleware for use in route definitions.

```dart
void registerKernel() {
    // Global middleware (runs on every route)
    Kernel.global([
        () => LoggingMiddleware(),
    ]);

    // Named route middleware
    Kernel.registerAll({
        'auth': () => EnsureAuthenticated(),
        'guest': () => RedirectIfAuthenticated(),
    });
}
```

**Kernel API:**

| Method | Signature | Purpose |
|--------|-----------|---------|
| `Kernel.global(factories)` | `void global(List<MagicMiddleware Function()>)` | Register middleware that runs on every route |
| `Kernel.register(name, factory)` | `void register(String, MagicMiddleware Function())` | Register a named route middleware alias |
| `Kernel.registerAll(map)` | `void registerAll(Map<String, MagicMiddleware Function()>)` | Bulk register named middleware |
| `Kernel.resolve(dynamic)` | `MagicMiddleware?` | Resolve by string alias, factory, or instance |
| `Kernel.execute(list)` | `Future<bool>` | Run middleware chain — returns false if halted |
| `Kernel.flush()` | `void` | Clear all middleware (for testing) |

## Gotchas

- **Async Init**: Never use `Magic.init().then(...)`. Always `await` it to ensure providers are booted.
- **Config Factories**: Using `configs` instead of `configFactories` for `Env`-dependent logic will result in `null` values as `Env` is not yet loaded.
- **Router Access**: `MagicRouter.instance.routerConfig` is `null` until `Magic.init()` finishes Step 7.
- **Crypt Service**: `EncryptionServiceProvider` is NOT auto-registered. Add it manually to `app.providers` if needed.
