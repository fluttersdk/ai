---
name: magic-framework
description: "Magic Framework — Laravel-inspired Flutter framework with IoC Container, Facades, Eloquent ORM, and GoRouter wrapper. ALWAYS activate for: Magic.init, MagicApp, MagicController, MagicView, MagicStatefulView, MagicFormData, MagicRoute, MagicResponse, Eloquent Model, InteractsWithPersistence, HasTimestamps, ServiceProvider, MagicMiddleware, ValidatesRequests, MagicStateMixin, Auth facade, Http facade, Config facade, Cache facade, DB facade, Gate facade, Log facade, Event facade, Lang facade, Schema facade, Vault facade, Storage facade, Pick facade, Crypt facade, Launch facade, LaunchServiceProvider, MagicCan, MagicCannot, MagicBuilder, MagicForm, WFormInput, QueryBuilder, Blueprint, Migration, Seeder, Factory, Magic.findOrPut, Magic.make, Magic.snackbar, Magic.confirm, Magic.loading, Carbon, trans(), env(), rules(), handleApiError, setErrorsFromResponse, MagicApplication, RouteServiceProvider, Kernel, magic install, make:model, make:controller, make:view, make:migration, make:enum, make:event, make:listener, make:middleware, make:factory, make:seeder, make:provider, make:policy, make:request, make:lang, key:generate, magic CLI. Use for ANY Flutter project built on the Magic framework."
---

# Magic Framework

Laravel-inspired Flutter framework. IoC Container + Facades + Eloquent ORM + GoRouter. All styling is handled by Wind UI (separate skill) — this skill covers architecture, data, and navigation only.

## Core Laws

1. **await Magic.init()**: Must be awaited in `main()` before ANY facade call. Never `.then()`.
2. **Facade-first**: Use `Auth`, `Http`, `Config`, `Cache`, `DB`, `Log`, `Event`, `Lang`, `Route`, `Gate`, `Schema`, `Vault`, `Storage`, `Pick`, `Crypt`, `Launch` — never resolve manually unless extending.
3. **Singleton controllers**: `static X get instance => Magic.findOrPut(X.new);` — the canonical pattern.
4. **Typed getters**: Models use `get<T>('key')` — never `getAttribute()`.
5. **fillable whitelist**: Models declare `fillable` — never use `guarded = []`.
6. **Service Provider discipline**: `register()` = sync bindings only. `boot()` = async, may resolve other services.
7. **MagicFormData auto-inference**: String values → `TextEditingController`. Other types → `ValueNotifier<T>`.
8. **Trailing commas + multi-line**: Always. No exceptions.

## Bootstrap Lifecycle

```dart
void main() async {
    WidgetsFlutterBinding.ensureInitialized();
    await Magic.init(
        configFactories: [
            () => appConfig,
            () => authConfig,
        ],
    );
    runApp(MagicApplication(title: 'My App'));
}
```

**7-step sequence**: Env.load → configFactories → MagicApp.init → Core bindings → Provider registration → await boot() → Router pre-build.

Use `configFactories` (not `configs`) when values depend on `Env.get()`.

## IoC Container Quick Reference

| Method | Purpose |
|--------|---------|
| `app.singleton('key', () => Svc())` | Lazy singleton (shared) |
| `app.bind('key', () => Svc())` | New instance each resolve |
| `app.setInstance('key', obj)` | Bind existing object |
| `Magic.make<T>('key')` | Resolve from container |
| `Magic.findOrPut<T>(T.new)` | Controller singleton (preferred) |
| `Magic.put<T>(ctrl)` | Register controller |
| `Magic.find<T>()` | Resolve controller by type |
| `Magic.delete<T>()` | Remove controller |

## Model Template

```dart
class Monitor extends Model with HasTimestamps, InteractsWithPersistence {
    @override String get table => 'monitors';
    @override String get resource => 'monitors';
    @override List<String> get fillable => ['name', 'url', 'status'];
    @override Map<String, String> get casts => {
        'settings': 'json',
        'created_at': 'datetime',
    };

    int? get id => get<int>('id');
    String? get name => get<String>('name');
    set name(String? v) => set('name', v);

    static Future<Monitor?> find(dynamic id) =>
        InteractsWithPersistence.findById<Monitor>(id, Monitor.new);
    static Future<List<Monitor>> all() =>
        InteractsWithPersistence.allModels<Monitor>(Monitor.new);
}
```

**Hybrid persistence**: `save()` → API first → local SQLite. `find()` → local first → API fallback → sync to local.

## Controller Pattern

```dart
class MonitorController extends MagicController
    with MagicStateMixin<bool>, ValidatesRequests {
    static MonitorController get instance => Magic.findOrPut(MonitorController.new);

    final monitorsNotifier = ValueNotifier<List<Monitor>>([]);

    Future<void> loadMonitors() async {
        setLoading();
        try {
            final monitors = await Monitor.all();
            monitorsNotifier.value = monitors;
            setSuccess(true);
        } catch (e) {
            Log.error('Failed: $e', e);
            setError(trans('errors.network_error'));
        }
    }

    Future<void> store(Map<String, dynamic> data) async {
        setLoading();
        clearErrors();
        final response = await Http.post('/monitors', data: data);
        if (response.successful) {
            Magic.toast(trans('monitors.created'));
            MagicRoute.to('/monitors');
            return;
        }
        handleApiError(response, fallback: trans('monitors.create_failed'));
    }
}
```

**State methods**: `setLoading()`, `setSuccess(data)`, `setError(msg)`, `setEmpty()`.
**Render**: `controller.renderState((data) => Widget(), onLoading: ..., onError: (msg) => ...)`.

## Views

| Type | Use When |
|------|----------|
| `MagicView<T>` | Stateless display, auto-resolves controller via `Magic.find<T>()` |
| `MagicStatefulView<T>` | Local state needed (forms, animations), has `onInit()`/`onClose()` lifecycle |
| `MagicBuilder<T>` | Reactive section wrapping a `ValueNotifier` |

## Forms & Validation

```dart
late final form = MagicFormData({
    'email': '',           // String → TextEditingController
    'password': '',        // String → TextEditingController
    'accept_terms': false, // bool → ValueNotifier<bool>
}, controller: controller);

// In build():
MagicForm(
    formData: form,
    child: Column(children: [
        WFormInput(
            controller: form['email'],
            validator: rules([Required(), Email()], field: 'email'),
        ),
    ]),
)
```

**Built-in rules**: `Required`, `Email`, `Min(n)`, `Max(n)`, `Confirmed`, `Same(field)`, `Accepted`.
**Server errors**: `handleApiError(response)` auto-maps Laravel 422 errors to form fields.
**Dispose**: Always `form.dispose()` in `onClose()`.

## Routing & Navigation

```dart
// Registration (in ServiceProvider.register()):
MagicRoute.page('/monitors', () => MonitorController.instance.index());
MagicRoute.page('/monitors/:id', () => MonitorController.instance.show())
    .name('monitors.show')
    .middleware(['auth']);

// Groups with layout:
MagicRoute.group(
    layout: (child) => AppLayout(child: child),
    middleware: ['auth'],
    routes: () { /* register routes */ },
);

// Navigation (context-free):
MagicRoute.to('/monitors');
MagicRoute.back();
MagicRoute.replace('/login');

// Parameters:
MagicRouter.instance.pathParameter('id');
MagicRouter.instance.queryParameter('q');
```

## HTTP & Responses

```dart
final res = await Http.get('/monitors', query: {'page': 1});
final res = await Http.post('/monitors', data: {'name': 'Test'});

res.successful   // 200-299
res.failed       // >= 400
res.data         // Map<String, dynamic>
res['key']       // operator[] shorthand
res.errors       // Laravel validation errors (422)
res.firstError   // First error message
```

## Auth Flow

```dart
// In ServiceProvider.boot() — REQUIRED:
Auth.manager.setUserFactory((data) => User.fromMap(data));

// Usage:
Auth.check()           // bool — is authenticated?
Auth.user<T>()          // T? — authenticated user model
await Auth.login(data, user)   // Future<void> — store token + set user
await Auth.logout()
await Auth.restore()   // Restore from Vault
```

## Context-Free UI Feedback

| Method | Purpose |
|--------|---------|
| `Magic.snackbar(title, msg)` | Standard snackbar |
| `Magic.success(title, msg)` | Green snackbar |
| `Magic.error(title, msg)` | Red snackbar |
| `Magic.toast(msg)` | Brief toast |
| `Magic.dialog<T>(widget)` | Custom dialog |
| `Magic.confirm(title: ..., message: ...)` | YES/NO confirmation |
| `Magic.loading(message: ...)` | Persistent loading overlay |
| `Magic.closeLoading()` | Dismiss loading |

## Anti-Patterns Wall

| ❌ Wrong | ✅ Correct | Why |
|---------|-----------|-----|
| `Magic.init().then(...)` | `await Magic.init()` | Providers not booted |
| `getAttribute('name')` | `get<String>('name')` | Type-safe access |
| `guarded = []` | Explicit `fillable` list | Security |
| Routes in `boot()` | Routes in `register()` | Too late — router built during bootstrap |
| `configs: [appConfig]` | `configFactories: [() => appConfig]` | Env not loaded yet |
| Skipping `MagicApp.reset()` in tests | `setUp(() { MagicApp.reset(); Magic.flush(); })` | Leaked state |
| `setSuccess()` inside `build()` | Call in async methods only | Notification loop |
| Forgetting `form.dispose()` | Always in `onClose()` | Memory leak |
| Missing `setUserFactory` | Call in `boot()` | Auth facade broken |
| `Event.dispatch(event)` | `EventDispatcher.instance.register(type, [...])` | Facade only has dispatch — register listeners via EventDispatcher |
| Using `Launch` without `LaunchServiceProvider` | Add `(app) => LaunchServiceProvider(app)` to `app.providers` | Facade unresolvable |

## Test Setup (Mandatory)

```dart
setUp(() {
    MagicApp.reset();   // Clear IoC container
    Magic.flush();      // Clear cached facade instances
});
```

Mock by extending contracts. Inject via `Magic.put<T>(mockController)`. Never use code generation for mocks.


## CLI Quick Reference

Magic CLI provides Artisan-inspired code generation. Install with `dart pub global activate fluttersdk_magic_cli`.

```bash
magic install                          # Initialize project
magic make:model Monitor -mcfsp        # Model + migration + controller + factory + seeder + policy
magic make:controller Monitor -r       # Resource controller with CRUD
magic make:view Login --stateful        # Stateful view with lifecycle
magic make:migration create_monitors   # Database migration
magic make:enum MonitorStatus           # String-backed enum
magic make:provider Payment             # Service provider
magic key:generate                      # Generate APP_KEY
```

All generators support `--force` (overwrite) and nested paths (`Admin/Dashboard`). Auto-suffixes are appended when missing.

## Reference Index

| File | Content | Load When |
|------|---------|-----------|
| `references/bootstrap-lifecycle.md` | Magic.init steps, IoC API, ServiceProvider, Env/Config, Kernel | Setting up app bootstrap or providers |
| `references/facades-api.md` | All 16 facades (incl. Launch) with method signatures and return types | Looking up any facade API |
| `references/eloquent-orm.md` | Model definition, attributes, casts, relations, QueryBuilder, migrations | Working with models or database |
| `references/controllers-views.md` | MagicController, MagicStateMixin, MagicView, MagicBuilder, auth widgets | Building controllers or views |
| `references/forms-validation.md` | MagicFormData, MagicForm, rules(), Validator, built-in rules, i18n | Building forms or validation |
| `references/routing-navigation.md` | Route registration, groups, transitions, middleware, navigation API | Setting up routes or navigation |
| `references/http-network.md` | NetworkManager, MagicResponse, interceptors, config | Making HTTP requests or configuring network |
| `references/auth-system.md` | AuthManager, guards, token refresh, policies, Gate | Implementing authentication or authorization |
| `references/secondary-systems.md` | Cache, Events, Logging, Localization, Storage, Encryption, Vault, Carbon, Launch, Policies | Using any secondary framework system |
| `references/testing-patterns.md` | Test setup, mocking, controller/model/middleware testing | Writing tests for Magic framework code |
| `references/cli-commands.md` | Magic CLI: install, make:* generators, inspection, boost/MCP commands | Scaffolding code or setting up a project with the CLI |
