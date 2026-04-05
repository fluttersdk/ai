# Magic CLI: Command Reference

Complete reference for the Magic CLI — an Artisan-inspired code generation and project management tool for Magic Framework projects.

## Invocation

All commands are invoked via `dart run magic:magic <command>` from the Flutter project root (where `pubspec.yaml` lives).

> [!TIP]
> Optionally install globally for shorter syntax: `dart pub global activate magic_cli`, then use bare `magic` command. Ensure `~/.pub-cache/bin` is in your `PATH`.

## Command Overview

| Category | Command | Description |
|:---------|:--------|:------------|
| **Setup** | `dart run magic:magic install` | Initialize Magic in a Flutter project |
| **Setup** | `dart run magic:magic key:generate` | Generate `APP_KEY` for encryption |
| **Generator** | `dart run magic:magic make:model Name` | Eloquent model with optional related files |
| **Generator** | `dart run magic:magic make:controller Name` | Controller (basic or resource) |
| **Generator** | `dart run magic:magic make:view Name` | View class (stateless or stateful) |
| **Generator** | `dart run magic:magic make:migration name` | Database migration |
| **Generator** | `dart run magic:magic make:enum Name` | String-backed enum with `fromValue()` |
| **Generator** | `dart run magic:magic make:event Name` | Event class extending `MagicEvent` |
| **Generator** | `dart run magic:magic make:listener Name` | Listener class extending `MagicListener` |
| **Generator** | `dart run magic:magic make:middleware Name` | Route middleware extending `MagicMiddleware` |
| **Generator** | `dart run magic:magic make:factory Name` | Model factory for seeding/testing |
| **Generator** | `dart run magic:magic make:seeder Name` | Database seeder |
| **Generator** | `dart run magic:magic make:provider Name` | Service provider |
| **Generator** | `dart run magic:magic make:policy Name` | Authorization policy with Gate definitions |
| **Generator** | `dart run magic:magic make:request Name` | Form request (validation rules class) |
| **Generator** | `dart run magic:magic make:lang code` | JSON language file |


## Project Setup

### `dart run magic:magic install`

Initializes Magic in an existing Flutter project. Creates the full directory structure, configuration files, service providers, routes, and `main.dart` bootstrap.

```bash
dart run magic:magic install
dart run magic:magic install --without-database --without-events
```

| Flag | Effect |
|:-----|:-------|
| `--without-database` | Skip SQLite/Eloquent setup and migrations directory |
| `--without-cache` | Skip cache system and `config/cache.dart` |
| `--without-auth` | Skip authentication guards and `config/auth.dart` |
| `--without-events` | Skip event dispatcher and events/listeners directories |
| `--without-localization` | Skip i18n/translator and `assets/lang/` directory |
| `--without-logging` | Skip logging channels and `config/logging.dart` |
| `--without-network` | Skip HTTP/Dio network layer and `config/network.dart` |
| `--without-broadcasting` | Skip broadcasting/WebSocket setup and `config/broadcasting.dart` |

**Generated structure:**

```
lib/
├── config/
│   ├── app.dart              # App name, env, providers list
│   ├── auth.dart             # Guard config, token endpoints
│   ├── broadcasting.dart     # Broadcasting connections (Reverb, null)
│   ├── cache.dart            # Cache driver, TTL
│   ├── database.dart         # SQLite connection
│   ├── logging.dart          # Log channels
│   ├── network.dart          # Base URL, timeouts
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
├── database/
│   ├── migrations/
│   ├── seeders/
│   └── factories/
├── resources/
│   └── views/
│       └── welcome_view.dart
├── routes/
│   └── app.dart              # Route definitions
└── main.dart                 # Bootstrap with Magic.init()
```

### `dart run magic:magic key:generate`

Generates a random 32-byte encryption key (base64-encoded) and writes it to `.env`.

```bash
dart run magic:magic key:generate
dart run magic:magic key:generate --show    # Display without writing to .env
```

Updates your `.env`:
```
APP_KEY=base64:randomGeneratedKey...
```

| Flag | Effect |
|:-----|:-------|
| `--show` | Display the generated key to stdout instead of writing to `.env` |

Required for the `Crypt` facade and encryption operations.


## Code Generators

All generators share these conventions:

- **Auto-suffix**: `dart run magic:magic make:controller User` → `UserController`. The suffix is appended if not already present; existing suffixes are detected and not doubled.
- **Nested paths**: `dart run magic:magic make:controller Admin/Dashboard` → `lib/app/controllers/admin/dashboard_controller.dart`. Directory segments are converted to snake_case.
- **`--force` flag**: All generators accept `--force` to overwrite existing files.
- **Import statement**: Generated files automatically import `package:magic/magic.dart`.

### `dart run magic:magic make:model`

Creates an Eloquent model with optional companion files.

```bash
dart run magic:magic make:model Monitor
dart run magic:magic make:model Monitor -m          # + migration
dart run magic:magic make:model Monitor -mc         # + migration + controller
dart run magic:magic make:model Monitor -mcf        # + migration + controller + factory
dart run magic:magic make:model Monitor -mcfsp      # + migration + controller + factory + seeder + policy
dart run magic:magic make:model Monitor -a          # all companion files
```

| Flag | Short | Generates |
|:-----|:------|:----------|
| `--migration` | `-m` | Migration file in `lib/database/migrations/` |
| `--controller` | `-c` | Controller in `lib/app/controllers/` (with `--resource` when used with `-a`) |
| `--factory` | `-f` | Factory in `lib/database/factories/` |
| `--seeder` | `-s` | Seeder in `lib/database/seeders/` |
| `--policy` | `-p` | Policy in `lib/app/policies/` |
| `--all` | `-a` | All of the above (controller generated as resource) |

**Output**: `lib/app/models/monitor.dart`

**Generated stub:**

```dart
class Monitor extends Model with HasTimestamps, InteractsWithPersistence {
    Monitor() : super();

    @override String get table => 'monitors';
    @override String get resource => 'monitors';
    @override List<String> get fillable => [];
    @override Map<String, String> get casts => {};

    // Typed Accessors — add manually:
    //   String? get name => get<String>('name');
    //   set name(String? value) => set('name', value);

    static Future<Monitor?> find(dynamic id) =>
        InteractsWithPersistence.findById<Monitor>(id, Monitor.new);
    static Future<List<Monitor>> all() =>
        InteractsWithPersistence.allModels<Monitor>(Monitor.new);
}
```

### `dart run magic:magic make:controller`

Creates a controller class.

```bash
dart run magic:magic make:controller Monitor
dart run magic:magic make:controller Monitor --resource    # CRUD resource controller
dart run magic:magic make:controller Admin/Dashboard       # Nested path
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--resource` | `-r` | Generate with CRUD methods: `index`, `create`, `show`, `edit`, `store`, `update`, `destroy` |
| `--model` | `-m` | Specify the model name for the resource controller |

**Output**: `lib/app/controllers/monitor_controller.dart`

**Basic controller stub:**

```dart
import 'package:magic/magic.dart';

class MonitorController extends MagicController {
    // TODO: Implement controller logic
    Widget index() => WDiv(children: []);
}
```

**Resource controller stub** (with `--resource`): Includes full CRUD methods — `index()`, `create()`, `show()`, `edit()`, `store()`, `update()`, `destroy()` — with API integration scaffolding.

### `dart run magic:magic make:view`

Creates a view widget.

```bash
dart run magic:magic make:view Login
dart run magic:magic make:view Login --stateful    # With initState/dispose lifecycle
dart run magic:magic make:view Auth/Register       # Nested path
```

| Flag | Effect |
|:-----|:-------|
| `--stateful` | Generate `StatefulWidget` with `initState()` and `dispose()` lifecycle hooks |

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

**Stateful stub** (with `--stateful`): Generates `StatefulWidget` with `initState()` for resource setup and `dispose()` for cleanup.

### `dart run magic:magic make:migration`

Creates a database migration file with a timestamp prefix.

```bash
dart run magic:magic make:migration create_monitors_table
dart run magic:magic make:migration add_status_to_monitors_table
dart run magic:magic make:migration create_monitors_table --create=monitors
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--create` | `-c` | Specify the table name for a `Schema.create()` migration |
| `--table` | `-t` | Specify the table name for an alter-table migration |

**Output**: `lib/database/migrations/m_20260324213600_create_monitors_table.dart` (timestamp auto-generated)

**Create migration stub:**

```dart
import 'package:magic/magic.dart';

class CreateMonitorsTable extends Migration {
    @override
    String get name => 'm_20260324213600_create_monitors_table';

    @override
    void up() {
        Schema.create('monitors', (Blueprint table) {
            table.id();
            table.timestamps();
        });
    }

    @override
    void down() {
        Schema.dropIfExists('monitors');
    }
}
```

### `dart run magic:magic make:enum`

Creates a string-backed enum with `fromValue()` lookup and `selectOptions` getter.

```bash
dart run magic:magic make:enum MonitorStatus
dart run magic:magic make:enum Status/OrderStatus       # Nested path
```

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

### `dart run magic:magic make:event`

Creates an event class for the pub/sub system.

```bash
dart run magic:magic make:event MonitorCreated
dart run magic:magic make:event Auth/TokenRefreshed     # Nested path
```

**Output**: `lib/app/events/monitor_created.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class MonitorCreated extends MagicEvent {
    MonitorCreated();
}
```

### `dart run magic:magic make:listener`

Creates an event listener.

```bash
dart run magic:magic make:listener SendMonitorNotification
dart run magic:magic make:listener SendNotification --event=MonitorCreated
dart run magic:magic make:listener Auth/RestoreSession   # Nested path
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

### `dart run magic:magic make:middleware`

Creates a route middleware.

```bash
dart run magic:magic make:middleware EnsureAuthenticated
dart run magic:magic make:middleware Admin/RoleCheck     # Nested path
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

### `dart run magic:magic make:factory`

Creates a model factory for testing and seeding.

```bash
dart run magic:magic make:factory Monitor        # Auto-appends 'Factory'
dart run magic:magic make:factory MonitorFactory # No double-suffix
```

**Output**: `lib/database/factories/monitor_factory.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class MonitorFactory extends Factory<Model> {
    @override
    Model newInstance() => throw UnimplementedError(
        'Import your Monitor model and override newInstance()',
    );

    @override
    Map<String, dynamic> definition() {
        return {
            // 'name': faker.person.name(),
        };
    }
}
```

### `dart run magic:magic make:seeder`

Creates a database seeder.

```bash
dart run magic:magic make:seeder User           # Auto-appends 'Seeder'
dart run magic:magic make:seeder UserSeeder     # No double-suffix
```

**Output**: `lib/database/seeders/user_seeder.dart`

**Generated stub:**

```dart
import 'package:magic/magic.dart';

class UserSeeder extends Seeder {
    @override
    Future<void> run() async {
        // Use factories to create data:
        // await UserFactory().count(10).create();
    }
}
```

### `dart run magic:magic make:provider`

Creates a service provider.

```bash
dart run magic:magic make:provider Payment             # Auto-appends 'ServiceProvider'
dart run magic:magic make:provider PaymentServiceProvider # No double-suffix
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

### `dart run magic:magic make:policy`

Creates an authorization policy with Gate definitions.

```bash
dart run magic:magic make:policy Monitor              # Auto-appends 'Policy'
dart run magic:magic make:policy MonitorPolicy        # No double-suffix
dart run magic:magic make:policy Monitor --model=Monitor
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--model` | `-m` | Specify the model the policy authorizes (inferred from class name by default) |

**Output**: `lib/app/policies/monitor_policy.dart`

**Generated stub:** Includes policy methods for authorization checks and Gate definitions.

### `dart run magic:magic make:request`

Creates a form request class for validation.

```bash
dart run magic:magic make:request StoreMonitor          # Auto-appends 'Request'
dart run magic:magic make:request StoreMonitorRequest   # No double-suffix
```

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

### `dart run magic:magic make:lang`

Creates a JSON language/translation file.

```bash
dart run magic:magic make:lang tr
dart run magic:magic make:lang en
```

**Output**: `assets/lang/tr.json`

Language codes must match the asset path convention. Ensure the `assets/lang/` directory is declared in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/lang/
```


## Common Patterns

### Scaffolding a Full Resource

Generate all companion files for a new resource with chained `-mcfsp` flags:

```bash
dart run magic:magic make:model Monitor -mcfsp
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
dart run magic:magic make:model Monitor --all
```

### Nested Paths

Organize files into subdirectories:

```bash
dart run magic:magic make:controller Admin/Dashboard
# → lib/app/controllers/admin/dashboard_controller.dart

dart run magic:magic make:view Settings/Profile
# → lib/resources/views/settings/profile_view.dart
```

Directory segments are automatically converted to snake_case in filenames.

### Creating a Resource Controller with Model

Combine flags for automatic resource controller generation with model binding:

```bash
dart run magic:magic make:model Monitor -c --all
dart run magic:magic make:controller Monitor --resource --model=Monitor
```

## Gotchas

1. **Project root**: All commands resolve paths relative to `pubspec.yaml`. Run from the Flutter project root.
2. **Auto-suffixes**: Commands like `make:controller`, `make:factory`, `make:seeder`, `make:provider`, `make:policy`, `make:request` auto-append suffixes. Providing existing suffixes does not create doubles (e.g., `make:controller MonitorController` creates one file, not `MonitorControllerController`).
3. **No rollback**: `make:model -mcf` generates multiple files independently. If one generator fails, others still create files.
4. **Nested paths**: Use forward slashes to create subdirectories: `Admin/Dashboard` → `admin/dashboard_controller.dart`.
5. **Lang codes**: `make:lang` codes must match `assets/lang/{code}.json` convention. Declare the directory in `pubspec.yaml` assets.
6. **Timestamp migrations**: `make:migration` automatically prepends `m_YYYYMMDDHHMMSS_` prefix. Always run from your project root so timestamps are consistent.
