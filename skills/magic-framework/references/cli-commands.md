# Magic CLI: Command Reference

Complete reference for the Magic CLI — an Artisan-inspired code generation and project management tool for Magic Framework projects.

## Installation

```bash
dart pub global activate fluttersdk_magic_cli
```

Ensure `~/.pub-cache/bin` is in your PATH. All commands must be run from the Flutter project root (where `pubspec.yaml` lives).

## Command Overview

| Category | Command | Description |
|:---------|:--------|:------------|
| **Setup** | `magic install` | Initialize Magic in a Flutter project |
| **Setup** | `magic key:generate` | Generate `APP_KEY` for encryption |
| **Generator** | `magic make:model Name` | Eloquent model with optional related files |
| **Generator** | `magic make:controller Name` | Controller (basic or resource) |
| **Generator** | `magic make:view Name` | View class (stateless or stateful) |
| **Generator** | `magic make:migration name` | Database migration |
| **Generator** | `magic make:enum Name` | String-backed enum with `fromValue()` |
| **Generator** | `magic make:event Name` | Event class extending `MagicEvent` |
| **Generator** | `magic make:listener Name` | Listener class extending `MagicListener` |
| **Generator** | `magic make:middleware Name` | Route middleware extending `MagicMiddleware` |
| **Generator** | `magic make:factory Name` | Model factory for seeding/testing |
| **Generator** | `magic make:seeder Name` | Database seeder |
| **Generator** | `magic make:provider Name` | Service provider |
| **Generator** | `magic make:policy Name` | Authorization policy with Gate definitions |
| **Generator** | `magic make:request Name` | Form request (validation rules class) |
| **Generator** | `magic make:lang code` | JSON language file |
| **Inspection** | `magic route:list` | List all registered routes |
| **Inspection** | `magic config:list` | List all configuration keys |
| **Inspection** | `magic config:get key` | Get a specific config value (dot notation) |
| **Boost** | `magic boost:install` | Set up MCP integration for AI assistants |
| **Boost** | `magic boost:mcp` | Run the MCP server (stdio transport) |
| **Boost** | `magic boost:update` | Regenerate AI context files (`AGENTS.md`) |


## Project Setup

### `magic install`

Initializes Magic in an existing Flutter project. Creates the full directory structure, configuration files, service providers, routes, and `main.dart` bootstrap.

```bash
magic install
magic install --without-database --without-events
```

| Flag | Effect |
|:-----|:-------|
| `--without-database` | Skip SQLite/Eloquent setup (still writes `config/database.dart` as stub) |
| `--without-cache` | Skip cache system |
| `--without-auth` | Skip authentication guards and interceptors |
| `--without-events` | Skip event dispatcher |
| `--without-localization` | Skip i18n/translator |
| `--without-logging` | Skip logging channels |
| `--without-network` | Skip HTTP/Dio network layer |

**Generated structure:**

```
lib/
├── config/
│   ├── app.dart              # App name, env, providers list
│   ├── auth.dart             # Guard config, token endpoints
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

### `magic key:generate`

Generates a random 32-character encryption key and writes it to `.env`.

```bash
magic key:generate
```

Updates your `.env`:
```
APP_KEY=base64:randomGeneratedKey...
```

> [!NOTE]
> Required for the `Crypt` facade. The key must be exactly 32 characters.


## Code Generators

All generators share these conventions:

- **Auto-suffix**: `magic make:controller User` → `UserController`. The suffix is appended if not already present.
- **Nested paths**: `magic make:controller Admin/Dashboard` → `lib/app/controllers/admin/dashboard_controller.dart`.
- **`--force` flag**: All generators accept `--force` to overwrite existing files without prompting.
- **Stub templating**: Uses `{{ placeholder }}` syntax. `StubLoader` handles PascalCase, snake_case, and kebab-case transforms automatically.

### `make:model`

Creates an Eloquent model with optional companion files.

```bash
magic make:model Monitor
magic make:model Monitor -m          # + migration
magic make:model Monitor -mc         # + migration + controller
magic make:model Monitor -mcf        # + migration + controller + factory
magic make:model Monitor -mcfsp      # + migration + controller + factory + seeder + policy
magic make:model Monitor -a          # all companion files
```

| Flag | Short | Generates |
|:-----|:------|:----------|
| `--migration` | `-m` | Migration file in `lib/database/migrations/` |
| `--controller` | `-c` | Controller in `lib/app/controllers/` |
| `--factory` | `-f` | Factory in `lib/database/factories/` |
| `--seeder` | `-s` | Seeder in `lib/database/seeders/` |
| `--policy` | `-p` | Policy in `lib/app/policies/` |
| `--all` | `-a` | All of the above |

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

### `make:controller`

Creates a controller class.

```bash
magic make:controller Monitor
magic make:controller Monitor --resource    # CRUD resource controller
magic make:controller Admin/Dashboard       # Nested path
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--resource` | `-r` | Generate with CRUD methods: `index`, `create`, `show`, `edit`, `store`, `update`, `destroy` |
| `--model` | `-m` | Specify the model name for the resource controller |

**Output**: `lib/app/controllers/monitor_controller.dart`

**Basic controller stub:**

```dart
class MonitorController extends MagicController {
    static MonitorController get instance =>
        Magic.findOrPut(MonitorController.new);

    Widget index() { ... }
    Widget show(String id) { ... }
}
```

**Resource controller stub** (with `--resource`): Includes `MagicStateMixin`, `ValidatesRequests`, and full CRUD methods — `index()`, `create()`, `show()`, `edit()`, `load()`, `store()`, `update()`, `destroy()` — with proper API calls, error handling, and navigation.

### `make:view`

Creates a view widget.

```bash
magic make:view Login
magic make:view Login --stateful    # With initState/dispose lifecycle
magic make:view Auth/Register       # Nested path
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--stateful` | `-s` | Generate `StatefulWidget` with `initState()` and `dispose()` |

**Output**: `lib/resources/views/login_view.dart`

**Stateless stub:**

```dart
class LoginView extends StatelessWidget {
    const LoginView({super.key});

    @override
    Widget build(BuildContext context) {
        return WDiv(
            className: 'flex flex-col p-6',
            children: [
                WText('Login', className: 'text-2xl font-bold text-gray-900 dark:text-white'),
            ],
        );
    }
}
```

**Stateful stub** (with `--stateful`): Adds `StatefulWidget` with `initState()` for resource setup and `dispose()` for cleanup.

### `make:migration`

Creates a database migration file.

```bash
magic make:migration create_monitors_table
magic make:migration add_status_to_monitors_table
magic make:migration create_monitors_table --create=monitors
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--create` | `-c` | Specify the table name for a `Schema.create()` migration |
| `--table` | `-t` | Specify the table name for an alter-table migration |

**Output**: `lib/database/migrations/m_2026_03_03_031600_create_monitors_table.dart`

**Create migration stub:**

```dart
class CreateMonitorsTable extends Migration {
    @override
    String get name => 'm_2026_03_03_031600_create_monitors_table';

    @override
    void up() {
        Schema.create('monitors', (Blueprint table) {
            table.id();
            // Add your columns here.
            table.timestamps();
        });
    }

    @override
    void down() {
        Schema.dropIfExists('monitors');
    }
}
```

### `make:enum`

Creates a string-backed enum with `fromValue()` lookup.

```bash
magic make:enum MonitorStatus
```

**Output**: `lib/app/enums/monitor_status.dart`

**Generated stub:**

```dart
enum MonitorStatus {
    sample('sample', 'Sample');

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
}
```

### `make:event`

Creates an event class for the pub/sub system.

```bash
magic make:event MonitorCreated
```

**Output**: `lib/app/events/monitor_created.dart`

**Generated stub:**

```dart
class MonitorCreated extends MagicEvent {
    MonitorCreated();
}
```

### `make:listener`

Creates an event listener.

```bash
magic make:listener SendMonitorNotification
```

**Output**: `lib/app/listeners/send_monitor_notification.dart`

**Generated stub:**

```dart
class SendMonitorNotification extends MagicListener<EventClass> {
    @override
    Future<void> handle(EventClass event) async {
        // TODO: Implement your event handling logic here.
    }
}
```

Register in your `EventServiceProvider`:

```dart
EventDispatcher.instance.register(MonitorCreated, [
    () => SendMonitorNotification(),
]);
```

### `make:middleware`

Creates a route middleware.

```bash
magic make:middleware EnsureTeamSelected
```

**Output**: `lib/app/http/middleware/ensure_team_selected.dart`

**Generated stub:**

```dart
class EnsureTeamSelected extends MagicMiddleware {
    @override
    Future<void> handle(void Function() next) async {
        // TODO: Add your middleware logic here.
        // Call next() to allow the request to proceed.
        next();
    }
}
```

Register in your `Kernel`:

```dart
Kernel.register('ensure-team', () => EnsureTeamSelected());
```

### `make:factory`

Creates a model factory for testing and seeding.

```bash
magic make:factory MonitorFactory
magic make:factory Monitor    # Auto-appends 'Factory'
```

**Output**: `lib/database/factories/monitor_factory.dart`

**Generated stub:**

```dart
class MonitorFactory extends Factory<Model> {
    @override
    Model newInstance() => throw UnimplementedError(
        'Import your model and override newInstance()',
    );

    @override
    Map<String, dynamic> definition() {
        return {
            'name': faker.person.name(),
            // Add more attributes here.
        };
    }
}
```

### `make:seeder`

Creates a database seeder.

```bash
magic make:seeder MonitorSeeder
```

**Output**: `lib/database/seeders/monitor_seeder.dart`

**Generated stub:**

```dart
class MonitorSeeder extends Seeder {
    @override
    Future<void> run() async {
        // Use factories to create data:
        // await MonitorFactory().count(10).create();
    }
}
```

### `make:provider`

Creates a service provider and optionally registers it in `config/app.dart`.

```bash
magic make:provider PaymentServiceProvider
magic make:provider Payment    # Auto-appends 'ServiceProvider'
```

**Output**: `lib/app/providers/payment_service_provider.dart`

**Generated stub:**

```dart
class PaymentServiceProvider extends ServiceProvider {
    PaymentServiceProvider(super.app);

    @override
    void register() {
        // Sync — bind to container only. No async calls.
    }

    @override
    Future<void> boot() async {
        // Called after all providers registered — safe to resolve dependencies.
    }
}
```

### `make:policy`

Creates an authorization policy with Gate definitions.

```bash
magic make:policy MonitorPolicy
magic make:policy Monitor    # Auto-appends 'Policy'
magic make:policy Monitor --model=Monitor
```

| Flag | Short | Effect |
|:-----|:------|:-------|
| `--model` | `-m` | Specify the model the policy authorizes |

**Output**: `lib/app/policies/monitor_policy.dart`

**Generated stub:** Includes `register()` with four Gate definitions — `view-monitor`, `create-monitor`, `update-monitor`, `delete-monitor` — and private handler methods.

### `make:request`

Creates a form request class for validation.

```bash
magic make:request StoreMonitorRequest
```

**Output**: `lib/app/requests/store_monitor_request.dart`

**Generated stub:**

```dart
class StoreMonitorRequest {
    StoreMonitorRequest(this.data);

    final Map<String, dynamic> data;

    Map<String, List<Rule>> rules() {
        return {
            // 'name': [Required(), Min(2), Max(255)],
            // 'email': [Required(), Email()],
        };
    }

    Validator validate() {
        return Validator.make(data, rules());
    }
}
```

### `make:lang`

Creates a JSON language file.

```bash
magic make:lang tr
magic make:lang es
```

**Output**: `assets/lang/tr.json`

> [!NOTE]
> Language codes must match the asset path convention (`assets/lang/{code}.json`). Ensure the `assets/lang/` directory is declared in your `pubspec.yaml` assets.


## Inspection Commands

### `route:list`

Lists all registered routes in the application.

```bash
magic route:list
```

### `config:list`

Lists all configuration files and their top-level keys.

```bash
magic config:list
magic config:list --verbose    # Show key previews
```

### `config:get`

Gets a specific configuration value using dot notation.

```bash
magic config:get app.name
magic config:get network.default
magic config:get app.url -s    # Show source
```

**Priority**: Project config → `.env` → Framework defaults.


## Boost Commands (AI Integration)

Three commands for setting up AI coding assistant integration via Model Context Protocol (MCP).

### `boost:install`

Sets up MCP integration for AI assistants (Cursor, VS Code).

```bash
magic boost:install
```

Creates `.magic/guidelines/` with framework documentation and configures MCP server in your IDE.

### `boost:mcp`

Runs the MCP server using stdio transport. Used by AI clients — not invoked manually.

```bash
magic boost:mcp
```

**MCP tools exposed**: `app_info`, `list_routes`, `get_config`, `validate_wind`, `search_docs`.

### `boost:update`

Regenerates AI context files from the current project state.

```bash
magic boost:update
```

> [!WARNING]
> This overwrites existing `AGENTS.md` files. Commit your changes before running.


## Common Patterns

### Scaffolding a Full Resource

Generate all files for a new resource in one command:

```bash
magic make:model Monitor -a
```

This creates:
- `lib/app/models/monitor.dart`
- `lib/database/migrations/m_YYYY_MM_DD_HHMMSS_create_monitors_table.dart`
- `lib/app/controllers/monitor_controller.dart`
- `lib/database/factories/monitor_factory.dart`
- `lib/database/seeders/monitor_seeder.dart`
- `lib/app/policies/monitor_policy.dart`

### Nested Paths

Organize files into subdirectories:

```bash
magic make:controller Admin/DashboardController
# → lib/app/controllers/admin/dashboard_controller.dart

magic make:view Settings/ProfileView
# → lib/resources/views/settings/profile_view.dart
```


## Gotchas

1. **Project root**: All commands resolve paths relative to `pubspec.yaml`. Run from the Flutter project root.
2. **No rollback**: `make:model -mcf` generates multiple files independently. If one stub fails, others still write.
3. **Boost overwrites**: `boost:update` replaces existing `AGENTS.md` files — always commit first.
4. **Database stub**: `magic install --without-database` skips SQLite config but still writes `config/database.dart` as a stub.
5. **Lang codes**: `make:lang` codes must match `assets/lang/{code}.json` convention.
6. **Provider auto-registration**: `make:provider` injects the import and provider factory into `config/app.dart` automatically. It checks for duplicates before writing.
