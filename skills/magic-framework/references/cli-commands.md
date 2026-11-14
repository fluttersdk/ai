# Magic CLI: Command Reference

Complete reference for the Magic CLI, a code generation and project management tool for Magic Framework projects, built on dowel and modelled on Laravel's `php artisan`.

## Contents

- [Invocation](#invocation)
- [Command Overview](#command-overview)
- [Project Setup](#project-setup)
- [Code Generators](#code-generators)
- [Common Patterns](#common-patterns)
- [Gotchas](#gotchas)

## Invocation

All commands are invoked via `dart run magic:dowel <command>` from the Flutter project root (where `pubspec.yaml` lives). Magic declares a `dowel` executable in its `pubspec.yaml` (`executables: { dowel: }`, backed by `bin/dowel.dart`), so once `magic` is a dependency the command works with no global activation and no app-specific package name. The commands come from `MagicDowelProvider`; once `magic:install` has scaffolded the app's `bin/dispatcher.dart`, `dart run magic:dowel` hands each call to it, and the commands of every registered plugin resolve there too.

## Command Overview

| Category | Command | Description |
|:---------|:--------|:------------|
| **Setup** | `dart run magic:dowel magic:install` | Initialize Magic in a Flutter project |
| **Generator** | `dart run magic:dowel make:model Name` | Eloquent model with optional related files |
| **Generator** | `dart run magic:dowel make:controller Name` | Controller (basic or resource) |
| **Generator** | `dart run magic:dowel make:view Name` | View class (stateless or stateful) |
| **Generator** | `dart run magic:dowel make:enum Name` | String-backed enum with `fromValue()` |
| **Generator** | `dart run magic:dowel make:event Name` | Event class extending `MagicEvent` |
| **Generator** | `dart run magic:dowel make:listener Name` | Listener class extending `MagicListener` |
| **Generator** | `dart run magic:dowel make:middleware Name` | Route middleware extending `MagicMiddleware` |
| **Generator** | `dart run magic:dowel make:provider Name` | Service provider |
| **Generator** | `dart run magic:dowel make:policy Name` | Authorization policy with Gate definitions |
| **Generator** | `dart run magic:dowel make:request Name` | Form request (validation rules class) |
| **Generator** | `dart run magic:dowel make:lang code` | JSON language file |
| **Generator** | `dart run magic:dowel make:component Name` | Atomic component folder (recipe + component + preview + index) |
| **Generator** | `dart run magic:dowel make:repository Name` | `Repository` cache class for one model's rows |
| **Generator** | `dart run magic:dowel make:action Name` | `MagicAction` write unit, plain or `--kind=create\|update\|delete` |
| **Generator** | `dart run magic:dowel make:form Name` | `MagicFormObject` class, plain or `--resource=<Model>` |
| **Generator** | `dart run magic:dowel make:test Name --kind=<kind>` | Test skeleton mirroring another generator's output |
| **Generator** | `dart run magic:dowel make:resource Name` | Full CRUD vertical: composes model, repository, actions, requests, form, controller, views and tests |
| **Codegen** | `dart run magic:dowel previews:refresh` | Regenerate `_previews.g.dart` from `*.preview.dart` files |
| **Design** | `dart run magic:dowel design:sync` | Generate the wind theme (aliases + brand seed) from `DESIGN.md` |
| **Design** | `dart run magic:dowel design:lint` | Validate `DESIGN.md` against the design rules |

Core ships 17 `make:*` generators. `make:migration`, `make:seeder` and `make:factory` belong to `magic_local_storage`, and `key:generate` to `magic_encryption`; each is registered by that plugin's dowel provider, so it exists only after `plugin:install` for it (see `plugin-local-storage.md` and `plugin-encryption.md`).


## Project Setup

### `dart run magic:dowel magic:install`

Initializes Magic in an existing Flutter project. Creates the full directory structure, configuration files, service providers, routes, and `main.dart` bootstrap.

```bash
dart run magic:dowel magic:install
dart run magic:dowel magic:install --without-auth --without-cache
```

The installer carries no flags for the extracted layers (SQLite, encryption, picker, broadcasting): `--without-database` and `--without-broadcasting` are gone. Add a plugin with `flutter pub add <package>` then `dart run magic:dowel plugin:install <package>`.

| Flag | Effect |
|:-----|:-------|
| `--without-cache` | Skip cache system and `config/cache.dart` |
| `--without-auth` | Skip authentication guards and `config/auth.dart` |
| `--without-localization` | Skip i18n/translator and `assets/lang/` directory |
| `--without-logging` | Skip logging channels and `config/logging.dart` |
| `--without-network` | Skip HTTP/Dio network layer and `config/network.dart` |
| `--with-devtools` | Add the debug trio (`magic_devtools ^1.0.0` + `tapir ^1.0.0` + `crumbs ^1.0.0`) to `dependencies` and wire it (plus `MagicPerfIntegration`) into `lib/main.dart` under `!kReleaseMode`, in one step |

`--with-devtools` is a one-step replacement for the manual debug-tooling bootstrap. After the core install it adds the three packages as regular `dependencies` (the `!kReleaseMode` gate tree-shakes them from release builds while debug and profile builds keep them, so `dev_dependencies` would trip `depend_on_referenced_packages`), imports `package:flutter/foundation.dart` (`show kReleaseMode`), `package:crumbs/crumbs.dart`, `package:magic_devtools/crumbs.dart`, `package:magic_devtools/magic_devtools.dart`, `package:magic_devtools/tapir.dart` and `package:tapir/tapir.dart`, and injects `TapirPlugin.install()`, `CrumbsPlugin.install()`, `CrumbsPlugin.registerWatcher(ExceptionWatcher())`, `CrumbsPlugin.registerWatcher(DumpWatcher())` and `MagicPerfIntegration.install()` before `Magic.init(` plus `MagicCrumbsIntegration.install()` and `MagicTapirIntegration.install()` after it. Call presence decides what is written: an app already calling `MagicDevtools.installPre(` is left untouched, and a block whose call is already in `lib/main.dart` is not written again, so re-running or hand wiring never duplicates the wiring or the deps (the umbrella `MagicDevtools.installPre()` / `installPost()` is the alternative, never mixed with it). Manual steps afterwards: `flutter pub get`, `dart run magic:dowel plugin:install tapir`, `plugin:install crumbs`, `tapir:install`, `crumbs:install` and `mcp:install` (which surfaces the `tapir_*` / `crumbs_*` MCP tools). `tapir:install` and `crumbs:install` write single-tool blocks only, never `MagicDevtools` or `MagicPerfIntegration`, and each skips a block whose `TapirPlugin.install(` / `CrumbsPlugin.install(` call already exists, so running them after `--with-devtools` writes nothing twice.

```bash
dart run magic:dowel magic:install --with-devtools
```

**Generated structure:**

```
lib/
├── config/
│   ├── app.dart              # App name, env, providers list
│   ├── auth.dart             # Guard config, token endpoints
│   ├── cache.dart            # Cache driver, TTL
│   ├── logging.dart          # Log channels
│   ├── network.dart          # Base URL, timeouts
│   ├── routing.dart          # URL strategy (path/hash)
│   └── view.dart             # Snackbar/dialog styling
├── app/
│   ├── controllers/
│   ├── models/
│   ├── policies/
│   ├── providers/
│   │   ├── app_service_provider.dart
│   │   └── route_service_provider.dart
│   └── http/
│       └── kernel.dart       # Middleware registration
├── resources/
│   └── views/
│       └── welcome_view.dart
├── routes/
│   └── app.dart              # Route definitions
└── main.dart                 # Bootstrap with Magic.init()
```

`key:generate` is no longer a core command: it ships with `magic_encryption` (see `plugin-encryption.md`).


## Code Generators

All generators share these conventions:

- **Auto-suffix**: `dart run magic:dowel make:controller User` → `UserController`. The suffix is appended if not already present; existing suffixes are detected and not doubled.
- **Nested paths**: `dart run magic:dowel make:controller Admin/Dashboard` → `lib/app/controllers/admin/dashboard_controller.dart`. Directory segments are converted to snake_case.
- **`--force` flag**: All generators accept `--force` to overwrite existing files.
- **`--test` flag**: `make:controller`, `make:view`, `make:action`, `make:form`, `make:repository` and `make:request` also accept `--test`, which chains `make:test --kind=<kind>` onto a successful write so the matching test skeleton lands alongside the class in the same run. `--force` on the host forwards to the chained `make:test` too.
- **Import statement**: Generated files automatically import `package:magic/magic.dart`.

### `dart run magic:dowel make:model`

Creates an Eloquent model with optional companion files.

```bash
dart run magic:dowel make:model Monitor
dart run magic:dowel make:model Monitor -m          # + migration (needs magic_local_storage)
dart run magic:dowel make:model Monitor -mc         # + migration + controller
dart run magic:dowel make:model Monitor -mcf        # + migration + controller + factory
dart run magic:dowel make:model Monitor -mcfsp      # + migration + controller + factory + seeder + policy
dart run magic:dowel make:model Monitor -a          # all companion files
```

| Flag | Short | Generates |
|:-----|:------|:----------|
| `--migration` | `-m` | Migration file in `lib/database/migrations/` (magic_local_storage's `make:migration`) |
| `--controller` | `-c` | Controller in `lib/app/controllers/` (with `--resource` when used with `-a`) |
| `--factory` | `-f` | Factory in `lib/database/factories/` (magic_local_storage's `make:factory`) |
| `--seeder` | `-s` | Seeder in `lib/database/seeders/` (magic_local_storage's `make:seeder`) |
| `--policy` | `-p` | Policy in `lib/app/policies/` |
| `--all` | `-a` | All of the above (controller generated as resource) |

`-m`, `-f` and `-s` (and `make:resource`'s factory) look the generator up in the dowel registry by name. Without `magic_local_storage` installed each prints a hint naming the plugin and skips that one file; the rest of the run carries on.

An existing model file without `--force` stops the run before any companion (migration, factory, seeder, policy, controller) is generated against it, the same as every other generator.

**Output**: `lib/app/models/monitor.dart`

**Generated stub:**

```dart
class Monitor extends Model with HasTimestamps, InteractsWithPersistence {
    Monitor() : super();

    @override String get table => 'monitors';
    @override String get resource => 'monitors';
    @override List<String> get fillable => [];
    @override Map<String, String> get casts => const {};

    // Typed Accessors — add manually:
    //   String? get name => get<String>('name');
    //   set name(String? value) => set('name', value);

    static Future<Monitor?> find(dynamic id) =>
        InteractsWithPersistence.findById<Monitor>(id, Monitor.new);
    static Future<List<Monitor>> all() =>
        InteractsWithPersistence.allModels<Monitor>(Monitor.new);

    static Monitor fromMap(Map<String, dynamic> map) =>
        Monitor()..setRawAttributes(map, sync: true)..exists = map.containsKey('id');
}
```

`fromMap` hydrates the model directly from raw API data via `setRawAttributes`, bypassing the `fillable` mass-assignment guard (unlike `fill`); `exists` is set from whether the map carries an `id` key.

### `dart run magic:dowel make:controller`

Creates a state-owning `MagicController` implementing `SessionScoped`: a plain controller by default, or (with `--resource`) a read controller wrapping a `RepositoryQuery` over the target model's repository.

```bash
dart run magic:dowel make:controller Monitor
dart run magic:dowel make:controller Monitor --resource              # reads MonitorRepository
dart run magic:dowel make:controller Monitor --resource --model=Ping # reads PingRepository
dart run magic:dowel make:controller Monitor --timers --actions --validates
dart run magic:dowel make:controller Admin/Dashboard --test          # + matching test
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--resource` | `-r` | Generate a read controller owning a `RepositoryQuery` over the model |
| `--model` | `-m` | The model a `--resource` controller reads (default: the controller name) |
| `--actions` | | Mix in `RunsActions` |
| `--timers` | | Mix in `OwnsTimers` |
| `--validates` | | Mix in `ValidatesRequests` and `CollapsesIndexedErrorKeys` |
| `--test` | | Also scaffold `test/app/controllers/<name>_controller_test.dart` |

Mixins are always assembled in the same fixed order regardless of the order the flags were passed: `OwnsTimers`, `RunsActions`, then `ValidatesRequests, CollapsesIndexedErrorKeys` (the latter must follow the former, since it is constrained `on ValidatesRequests`). `--broadcasts` is gone: add `ListensToBroadcasts` from `magic_socket` by hand (`plugin-socket.md`).

**Output**: `lib/app/controllers/monitor_controller.dart`

**Basic controller stub:**

```dart
import 'package:magic/magic.dart';

class MonitorController extends MagicController implements SessionScoped {
    static MonitorController get instance => Magic.findOrPut(MonitorController.new);

    @override
    Future<void> resetForSession() async {
        // TODO: clear cached state, then refetch for the new session.
    }
}
```

**Resource controller stub** (with `--resource`): owns a `RepositoryQuery<Monitor>` over `MonitorRepository.instance`, exposes `items`, `ensureFresh()` and `reload()`, starts the first read from `onInit()`, disposes the query from `onClose()`, and `resetForSession()` resets the repository and reloads the query.

### `dart run magic:dowel make:view`

Creates a view class: a plain `StatelessWidget` with no backing controller, or a `MagicStatefulView<T>` wired to one.

```bash
dart run magic:dowel make:view Login                          # StatelessWidget
dart run magic:dowel make:view Auth/Register                  # Nested path
dart run magic:dowel make:view Monitor --controller=Monitor   # MagicStatefulView<MonitorController>
dart run magic:dowel make:view Login --stateful               # Controller derived: LoginController
dart run magic:dowel make:view Monitors/List --controller=Monitor --list --form=MonitorFormObject
```

| Flag | Effect |
|:-----|:-------|
| `--stateful` | Generate a stateful view with lifecycle hooks |
| `--controller=Name` | Bind the view to this controller (suffix optional); implies `--stateful` |
| `--list` | Add `RefetchesOnMount` so the view reloads on every mount; expects a controller made with `make:controller --resource` (its `ensureFresh()`) |
| `--form=Name` | Add a `State`-owned form object field (suffix optional), disposed in `onClose`; implies `--stateful` |
| `--test` | Also scaffold `test/resources/views/<name>_view_test.dart` |

**Output**: `lib/resources/views/login_view.dart`

**Stateless stub:**

```dart
import 'package:magic/magic.dart';

class LoginView extends StatelessWidget {
    const LoginView({super.key});

    @override
    Widget build(BuildContext context) {
        return WDiv(children: []);
    }
}
```

**Stateful stub** (`--stateful`, or implied by `--controller`/`--form`): a `MagicStatefulView<Controller>` whose `State` registers the controller via `Magic.findOrPut` in `initState()`, disposes the `--form` object in `onClose()`, and (with `--list`) overrides `refetch()` to call `controller.ensureFresh()`.

### `dart run magic:dowel make:enum`

Creates a string-backed enum with `fromValue()` lookup and `selectOptions` getter.

```bash
dart run magic:dowel make:enum MonitorStatus
dart run magic:dowel make:enum Status/OrderStatus       # Nested path
dart run magic:dowel make:enum IncidentSeverity --wire  # Wire-backed enum
```

| Flag | Effect |
|:-----|:-------|
| `--wire` | Generate a wire-backed enum instead: an `unknown` fallback case, a `fromWire()` factory that never throws on an unrecognised value, and a `trans()`-backed `label` getter |

**Output**: `lib/app/enums/monitor_status.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

enum MonitorStatus {
    active('active', 'Active'),
    inactive('inactive', 'Inactive');

    const MonitorStatus(this.value, this.label);

    final String value;
    final String label;

    static MonitorStatus? fromValue(String? value) {
        if (value == null) return null;
        try {
            return MonitorStatus.values.firstWhere((e) => e.value == value);
        } catch (_) {
            return null;
        }
    }

    List<SelectOption> get selectOptions =>
        MonitorStatus.values.map((e) => SelectOption(value: e.value, label: e.label)).toList();
}
```

### `dart run magic:dowel make:event`

Creates an event class for the pub/sub system.

```bash
dart run magic:dowel make:event MonitorCreated
dart run magic:dowel make:event Auth/TokenRefreshed     # Nested path
```

**Output**: `lib/app/events/monitor_created.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class MonitorCreated extends MagicEvent {
    MonitorCreated();
}
```

### `dart run magic:dowel make:listener`

Creates an event listener.

```bash
dart run magic:dowel make:listener SendMonitorNotification
dart run magic:dowel make:listener SendNotification --event=MonitorCreated
dart run magic:dowel make:listener Auth/RestoreSession   # Nested path
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--event` | `-e` | The event class the listener handles (defaults to `MagicEvent`) |

**Output**: `lib/app/listeners/send_monitor_notification.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class SendMonitorNotification extends MagicListener<MagicEvent> {
    @override
    Future<void> handle(MagicEvent event) async {
        // TODO: Implement your event handling logic here.
    }
}
```

### `dart run magic:dowel make:middleware`

Creates a route middleware.

```bash
dart run magic:dowel make:middleware EnsureAuthenticated
dart run magic:dowel make:middleware Admin/RoleCheck     # Nested path
```

**Output**: `lib/app/middleware/ensure_authenticated.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class EnsureAuthenticated extends MagicMiddleware {
    @override
    Future<void> handle(void Function() next) async {
        // TODO: Add your middleware logic here.
        // Call next() to allow the request to proceed.
        await next();
    }
}
```

### `dart run magic:dowel make:provider`

Creates a service provider.

```bash
dart run magic:dowel make:provider Payment             # Auto-appends 'ServiceProvider'
dart run magic:dowel make:provider PaymentServiceProvider # No double-suffix
```

**Output**: `lib/app/providers/payment_service_provider.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class PaymentServiceProvider extends ServiceProvider {
    PaymentServiceProvider(super.app);

    @override
    void register() {
        // Bind services to the container synchronously.
    }

    @override
    Future<void> boot() async {
        // Called after all providers registered — safe to resolve dependencies.
    }
}
```

### `dart run magic:dowel make:policy`

Creates an authorization policy with Gate definitions.

```bash
dart run magic:dowel make:policy Monitor              # Auto-appends 'Policy'
dart run magic:dowel make:policy MonitorPolicy        # No double-suffix
dart run magic:dowel make:policy Monitor --model=Monitor
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--model` | `-m` | Specify the model the policy authorizes (inferred from class name by default) |

**Output**: `lib/app/policies/monitor_policy.dart`

**Generated stub:** Includes policy methods for authorization checks and Gate definitions.

### `dart run magic:dowel make:request`

Creates a form request class for validation.

```bash
dart run magic:dowel make:request StoreMonitor          # Auto-appends 'Request'
dart run magic:dowel make:request StoreMonitorRequest   # No double-suffix
dart run magic:dowel make:request StoreMonitor --test   # + matching test
```

| Flag | Effect |
|:-----|:-------|
| `--test` | Also scaffold `test/app/validation/requests/<name>_request_test.dart` |

**Output**: `lib/app/validation/requests/store_monitor_request.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class StoreMonitorRequest extends FormRequest {
    @override
    Map<String, List<Rule>> rules() {
        return {
            'name': [Required(), Min(2), Max(255)],
            'email': [Required(), Email()],
        };
    }
}
```

### `dart run magic:dowel make:lang`

Creates a JSON language/translation file.

```bash
dart run magic:dowel make:lang tr
dart run magic:dowel make:lang en
dart run magic:dowel make:lang tr --from=en   # copy en.json's key tree into tr.json
```

| Flag | Effect |
|:-----|:-------|
| `--from=locale` | Source locale to copy the key tree from (default `en`) |

When `assets/lang/<from>.json` exists, writes `assets/lang/<code>.json` with the SAME key tree, each leaf copied verbatim from the source (a complete catalogue ready for a human translator). Otherwise writes an empty translation map (`{}`).

**Output**: `assets/lang/tr.json`

Language codes must match the asset path convention. Ensure the `assets/lang/` directory is declared in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/lang/
```


### `dart run magic:dowel make:component`

Scaffolds an atomic component folder under `lib/ui/components/<name>/`, plus its widget test at `test/ui/components/<name>/<name>_test.dart` (the barrel imported with a prefix, so a name like `Badge` stays unambiguous).

```bash
dart run magic:dowel make:component Avatar
dart run magic:dowel make:component Avatar --variants=intent,size
dart run magic:dowel make:component Panel --slots
```

**Output** (for `Avatar`): `lib/ui/components/avatar/avatar.dart` (`class Avatar`, unprefixed PascalCase), `avatar.recipe.dart` (a `WindRecipe`, or a `WindSlotRecipe` under `--slots`, seeded with the requested `--variants` axes), `index.dart` (re-exports the component + recipe, NOT the preview), and conditionally `avatar.preview.dart` (a single public `AvatarPreview` matrix).

The preview file (`avatar.preview.dart`) and the chained `previews:refresh` are only scaffolded when the target project already maintains a preview catalogue: any `*.preview.dart` file or a `_previews.g.dart` index anywhere under `lib/`. `--preview`/`--no-preview` override the auto-detection in either direction.

| Flag | Effect |
|:-----|:-------|
| `--variants=a,b` | Seeds the named variant axes into the recipe (values left empty to fill in). |
| `--slots` | Scaffolds a multi-part `WindSlotRecipe` instead of a single-element `WindRecipe`. |
| `--preview` / `--no-preview` | Force the preview file (and `previews:refresh`) on/off, overriding catalogue auto-detection. |
| `--force` | Overwrite an existing component. |

`make:component` also always scaffolds the matching widget test at `test/ui/components/<name>/<name>_test.dart` (skipped with a note when the project has no `pubspec.yaml` to read a package name from).


### `dart run magic:dowel make:repository`

Creates a `Repository<T>` subclass caching one REST resource's rows by id (Eloquent's identity map).

```bash
dart run magic:dowel make:repository Monitor            # Auto-appends 'Repository'
dart run magic:dowel make:repository MonitorRepository  # No double-suffix
dart run magic:dowel make:repository Monitor --test     # + matching test
```

| Flag | Effect |
|:-----|:-------|
| `--test` | Also scaffold `test/app/repositories/<name>_repository_test.dart` |

**Output**: `lib/app/repositories/monitor_repository.dart`

### `dart run magic:dowel make:action`

Creates a `MagicAction` subclass in `lib/app/actions/`. Plain (no `--kind`) scaffolds the default stateless skeleton (`MagicAction<Object?, void>`); `--kind` with `--model` scaffolds one of the three write variants against that model.

```bash
dart run magic:dowel make:action PauseMonitor
dart run magic:dowel make:action Monitors/PauseMonitor              # Nested path
dart run magic:dowel make:action Monitors/CreateMonitor --kind=create --model=Monitor
dart run magic:dowel make:action Monitors/PauseMonitor --test       # + matching test
```

| Flag | Effect |
|:-----|:-------|
| `--kind=create\|update\|delete` | The write variant to scaffold; requires `--model` |
| `--model=Name` | The model this action writes; required alongside `--kind` |
| `--test` | Also scaffold `test/app/actions/<name>_test.dart` |

The kinds: `create` fills and saves a new model; `update` takes `({String id, Map<String, dynamic> fields})`, saves, and writes the row into `<Model>Repository` via `upsertFromShow`; `delete` deletes and evicts the row. A refused save throws `ActionRequestFailed.refusalOf(...)` with the model's `lastRemoteResponse`, and a refused delete throws `ActionRequestFailed` carrying it, so `isTransportFailure` can tell a request that got no readable answer from a refusal.

**Output**: `lib/app/actions/pause_monitor.dart`

### `dart run magic:dowel make:form`

Creates a `MagicFormObject` subclass in `lib/app/forms/`. The `FormObject` suffix is deliberate: apps already name form widgets `<Resource>Form`, so the object backing one needs a distinct name. `--resource=<Model>` scaffolds the full create/edit contract instead of the plain skeleton: an `editing` field, `initial` seeded from `editing?.toArray()`, `request` choosing between the model's Store/Update requests, and `persist` running the matching Create/Update action. A create then calls `<Model>Controller.instance.reload()`, so the form expects the `--resource` controller `make:resource` writes beside it.

```bash
dart run magic:dowel make:form Monitor                          # → MonitorFormObject
dart run magic:dowel make:form Monitor --request=StoreMonitorRequest
dart run magic:dowel make:form Monitor --resource=Monitor        # Full create/edit contract
dart run magic:dowel make:form Monitor --test                    # + matching test
```

| Flag | Effect |
|:-----|:-------|
| `--request=Class` | The `FormRequest` class this form validates against |
| `--resource=Model` | The model this form creates/edits; scaffolds the full `editing` + Store/Update + `persist` contract |
| `--test` | Also scaffold `test/app/forms/<name>_test.dart` |

**Output**: `lib/app/forms/monitor_form_object.dart`

### `dart run magic:dowel make:test`

Scaffolds a test skeleton mirroring where a `make:*` generator's own output lives (Laravel's `make:test`, ported to magic's `lib/` → `test/` layout).

```bash
dart run magic:dowel make:test Monitor --kind=controller
dart run magic:dowel make:test Monitors/PauseMonitor --kind=action   # Nested path
dart run magic:dowel make:test Monitor --kind=repository --force     # Overwrite
```

| Flag | Effect |
|:-----|:-------|
| `--kind=controller\|action\|form\|repository\|request\|view\|unit` | The generator kind whose output this test mirrors |

The generated test imports the target class as `package:<name>/...`, where `<name>` is read from the target project's own `pubspec.yaml` (relative `../lib/` imports would trip `avoid_relative_lib_imports`). `unit` has no source-file counterpart; its stub only substitutes `{{ packageName }}` inside a TODO comment.

**Output**: e.g. `test/app/controllers/monitor_controller_test.dart` for `--kind=controller`.

### `dart run magic:dowel make:resource`

Magic's analogue of Laravel's `make:model --all`: composes the owning generators into one CRUD vertical for a model (model and, when `magic_local_storage` is installed, its factory; repository, the create/update/delete actions, the Store and Update requests, the resource form object, a `--resource --actions` controller, and the list and form views, plus the tests for the actions, the form and the controller). It writes no file itself; every file comes from its own generator.

```bash
dart run magic:dowel make:resource Monitor
dart run magic:dowel make:resource Monitor --no-views   # Data and logic layers only
dart run magic:dowel make:resource Monitor --no-model   # The model already exists
dart run magic:dowel make:resource Monitor --force      # Overwrite the clashes
```

| Flag | Effect |
|:-----|:-------|
| `--views` / `--no-views` | Generate the list and form views (default on) |
| `--model` / `--no-model` | Generate the model and its factory (default on; the factory needs `magic_local_storage`, otherwise a hint is printed and the vertical is written without one) |
| `--force` | Overwrite any clashing file (a hand-edited model or factory is kept regardless) |

The run is all-or-nothing: every target path is preflighted before anything is written. A present model or factory is kept (never regenerated, even under `--force`); any other present file fails the run (exit 1, nothing written) unless `--force` is passed. The index and create route lines are printed for pasting into `RouteServiceProvider.boot()`, never written into it.

**Output** (for `Monitor`, all defaults): `lib/app/models/monitor.dart`, `lib/database/factories/monitor_factory.dart` (with `magic_local_storage`), `lib/app/repositories/monitor_repository.dart`, `lib/app/actions/monitors/{create,update,delete}_monitor.dart` (+ tests), `lib/app/validation/requests/{store,update}_monitor_request.dart`, `lib/app/forms/monitor_form_object.dart` (+ test), `lib/app/controllers/monitor_controller.dart` (+ test), `lib/resources/views/monitors/{monitors_list_view,monitor_form_view}.dart`.

### `dart run magic:dowel previews:refresh`

Regenerates the dev-only preview catalog index from `*.preview.dart` files.

```bash
dart run magic:dowel previews:refresh
dart run magic:dowel previews:refresh --path=lib/ui/components
```

**Output**: `<scan-dir>/_previews.g.dart` (default scan dir `lib`). Each `*.preview.dart` file must declare exactly ONE public `*Preview` class; the command validates the name, fails fast on a slug collision, sorts deterministically, and writes atomically. The generated file returns a `List<PreviewEntry>` from the `previewEntries()` function (never a top-level const list) so the catalog tree-shakes from release builds. Feed it to the catalog via `MagicPreview.register(previewEntries())`.

| Flag | Effect |
|:-----|:-------|
| `--path=DIR` | Directory to scan for `*.preview.dart` files (default `lib`). |


### `dart run magic:dowel design:sync`

Generates the wind theme (semantic aliases + brand seed) from a `DESIGN.md`.

```bash
dart run magic:dowel design:sync
dart run magic:dowel design:sync --input=DESIGN.md --output=lib/config/wind_theme.g.dart
```

**Output**: a Dart source file exposing `Map<String, String> designAliases` (17 property-prefixed semantic keys with arbitrary-hex light + `dark:` pairs, drop-in for `WindThemeData(aliases: ...)`) and `Map<String, MaterialColor> designColors` (the brand `primary` with a generated 50-900 ramp seeded from the DESIGN.md `primary` light hex). Idempotent (byte-identical on re-run) and written atomically. Do not hand-edit the generated file; re-run `design:sync`.

| Flag | Effect |
|:-----|:-------|
| `--input=PATH` | DESIGN.md source, relative to the project root (default `DESIGN.md`). |
| `--output=PATH` | Generated wind theme file (default `lib/config/wind_theme.g.dart`). |


### `dart run magic:dowel design:lint`

Validates a `DESIGN.md` against six rules: broken-ref (error), missing-primary, unknown-key (the `dark:` overlay is never flagged), section-order, missing-sections, orphaned-tokens, and contrast-ratio (WCAG AA 4.5:1 on component bg/text pairs). Exits nonzero only on an error-severity finding.

```bash
dart run magic:dowel design:lint --input=DESIGN.md
```

| Flag | Effect |
|:-----|:-------|
| `--input=PATH` | DESIGN.md to validate, relative to the project root (default `DESIGN.md`). |


## Common Patterns

### Scaffolding a Full Resource

Generate all companion files for a new resource with chained `-mcfsp` flags (the migration, factory and seeder need `magic_local_storage`; without it those three are skipped with a hint):

```bash
dart run magic:dowel make:model Monitor -mcfsp
```

This creates:
- `lib/app/models/monitor.dart`
- `lib/database/migrations/m_YYYYMMDDHHMMSS_create_monitors_table.dart`
- `lib/app/controllers/monitor_controller.dart` (as resource controller)
- `lib/database/factories/monitor_factory.dart`
- `lib/database/seeders/monitor_seeder.dart`
- `lib/app/policies/monitor_policy.dart`

Or use the shorthand:

```bash
dart run magic:dowel make:model Monitor --all
```

### Nested Paths

Organize files into subdirectories:

```bash
dart run magic:dowel make:controller Admin/Dashboard
# → lib/app/controllers/admin/dashboard_controller.dart

dart run magic:dowel make:view Settings/Profile
# → lib/resources/views/settings/profile_view.dart
```

Directory segments are automatically converted to snake_case in filenames.

### Creating a Resource Controller with Model

Combine flags for automatic resource controller generation with model binding:

```bash
dart run magic:dowel make:model Monitor -c --all
dart run magic:dowel make:controller Monitor --resource --model=Monitor
```

### Scaffolding a Full CRUD Vertical with `make:resource`

`make:resource` composes the same shape by hand: model (+ factory with `magic_local_storage`), repository, the create/update/delete actions, the Store/Update requests, the resource form object, a `--resource --actions` controller, and the list/form views, plus their tests:

```bash
dart run magic:dowel make:resource Monitor
```

Skip the data layer when the model already exists, or the views for an API-only vertical:

```bash
dart run magic:dowel make:resource Monitor --no-model
dart run magic:dowel make:resource Monitor --no-views
```

The run is all-or-nothing: it preflights every target path first, so a clash anywhere leaves the project untouched unless `--force` is passed.

## Gotchas

1. **Project root**: All commands resolve paths relative to `pubspec.yaml`. Run from the Flutter project root.
2. **Auto-suffixes**: Commands like `make:controller`, `make:provider`, `make:policy`, `make:request`, `make:repository`, `make:form` auto-append suffixes. Providing existing suffixes does not create doubles (e.g., `make:controller MonitorController` creates one file, not `MonitorControllerController`).
3. **No rollback**: `make:model -mcf` generates multiple files independently. If one generator fails, others still create files. `make:resource` is the exception: it preflights every target path before writing anything, so a clash fails the whole run with nothing written.
4. **Nested paths**: Use forward slashes to create subdirectories: `Admin/Dashboard` → `admin/dashboard_controller.dart`.
5. **Lang codes**: `make:lang` codes must match `assets/lang/{code}.json` convention. Declare the directory in `pubspec.yaml` assets.
6. **Plugin generators**: `make:migration`, `make:seeder` and `make:factory` exist only with `magic_local_storage` registered (`plugin:install`); `make:migration` prepends an `m_YYYYMMDDHHMMSS_` prefix, so run it from the project root.
7. **`--test` needs a package name**: the chained `make:test` (and `make:component`'s own matching test) resolve the target project's package name from `pubspec.yaml`'s `name:` key; a project without one skips the test with a printed note rather than failing the whole command.
8. **`make:action --kind`**: always requires `--model` (the model the write acts on); the command refuses to write with `--kind` and no `--model`.
