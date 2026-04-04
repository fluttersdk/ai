# Magic Framework: Testing Patterns

Reference for testing Magic framework applications including service mocking, controller tests, model persistence, and UI integration.

## Essential setUp Pattern

Every Magic test MUST reset the global state in `setUp()` to prevent state leakage between tests. This is non-negotiable.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

void main() {
  group('MyFeature', () {
    setUp(() {
      // 1. Reset the IoC container and destroy the singleton instance
      MagicApp.reset();

      // 2. Clear all cached facade instances (Log, Auth, Cache, Http, etc.)
      Magic.flush();
    });

    test('example test', () {
      // Test code here
    });
  });
}
```

**Why this matters:**
- `MagicApp.reset()` destroys the singleton instance and clears all bindings, instances, and configuration state
- `Magic.flush()` clears the internal controller registry and facade caches so they don't retain stale references between tests
- Without this setup, tests pollute each other's state (bindings, singletons, facade instances)

## Controller Testing

Controllers are tested by verifying state transitions and side effects. Use `Magic.put<T>()` to inject controller instances that can be resolved within your test.

### Basic Controller Test

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';

class UserController extends MagicController with MagicStateMixin<List<User>> {
  Future<void> fetchUsers() async {
    setLoading();
    try {
      final users = await Http.get('/users');
      setSuccess(users);
    } catch (e) {
      setError('Failed to fetch users');
    }
  }
}

void main() {
  group('UserController', () {
    late UserController controller;

    setUp(() {
      MagicApp.reset();
      Magic.flush();

      controller = UserController();
      Magic.put<UserController>(controller);
    });

    test('initial state is empty', () {
      expect(controller.isEmpty, isTrue);
      expect(controller.isLoading, isFalse);
      expect(controller.isSuccess, isFalse);
      expect(controller.isError, isFalse);
    });

    test('setLoading changes state to loading', () {
      controller.setLoading();
      expect(controller.isLoading, isTrue);
    });

    test('setSuccess stores data and marks state as success', () {
      final data = [User(id: 1, name: 'Alice')];
      controller.setSuccess(data);

      expect(controller.isSuccess, isTrue);
      expect(controller.rxState, equals(data));
    });

    test('setError stores message and marks state as error', () {
      controller.setError('Network failed');

      expect(controller.isError, isTrue);
      expect(controller.rxStatus.message, equals('Network failed'));
    });

    test('fetchUsers updates state on success', () async {
      // Mock the HTTP driver
      final mockHttp = MockNetworkDriver();
      mockHttp.mock({'data': [{'id': 1, 'name': 'Bob'}]});

      Magic.bind('http.driver', () => mockHttp, shared: true);

      await controller.fetchUsers();

      expect(controller.isSuccess, isTrue);
      expect(controller.rxState, isNotEmpty);
    });

    test('fetchUsers sets error state on failure', () async {
      final mockHttp = MockNetworkDriver();
      mockHttp.mockError(Exception('Connection timeout'));

      Magic.bind('http.driver', () => mockHttp, shared: true);

      await controller.fetchUsers();

      expect(controller.isError, isTrue);
    });
  });
}
```

### Injecting Test Controllers

When testing UI widgets that depend on controllers, register a test controller using `Magic.put<T>()`:

```dart
test('MyWidget displays data from controller', () async {
  final testController = MyController();
  testController.setSuccess(['item1', 'item2']);

  Magic.put<MyController>(testController);

  await tester.pumpWidget(MyApp());

  expect(find.text('item1'), findsOneWidget);
  expect(find.text('item2'), findsOneWidget);
});
```

## Model Testing

Models are tested with an in-memory SQLite database for speed. Mobile apps use file-based SQLite; web uses in-memory.

### Setup Database for Model Tests

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:sqlite3/sqlite3.dart';

class User extends Model with HasTimestamps, InteractsWithPersistence {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';

  @override
  List<String> get fillable => ['name', 'email', 'born_at'];

  @override
  Map<String, String> get casts => {
    'born_at': 'datetime',
  };

  String? get name => get<String>('name');
  set name(String? value) => set('name', value);

  String? get email => get<String>('email');
  set email(String? value) => set('email', value);

  Carbon? get bornAt => get<Carbon>('born_at');
  set bornAt(dynamic value) => set('born_at', value);

  static Future<User?> find(dynamic id) =>
    InteractsWithPersistence.findById<User>(id, User.new);

  static Future<List<User>> all() =>
    InteractsWithPersistence.allModels<User>(User.new);
}

void main() {
  group('User Model', () {
    late Database db;

    setUp(() {
      MagicApp.reset();
      Magic.flush();

      // Create in-memory database
      db = sqlite3.openInMemory();
      DatabaseManager().setConnection(db);

      // Create test table
      db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          email TEXT,
          born_at TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');
    });

    tearDown(() {
      DatabaseManager().dispose();
    });

    test('can fill and retrieve attributes', () {
      final user = User()
        ..fill({
          'name': 'Alice',
          'email': 'alice@example.com',
        });

      expect(user.name, 'Alice');
      expect(user.email, 'alice@example.com');
    });

    test('can save new model to database', () async {
      final user = User()
        ..fill({
          'name': 'Bob',
          'email': 'bob@example.com',
        });

      final result = await user.save();

      expect(result, isTrue);
      expect(user.exists, isTrue);
      expect(user.id, isNotNull);
    });

    test('can find model by id', () async {
      db.execute(
        "INSERT INTO users (name, email) VALUES ('Carol', 'carol@example.com')"
      );

      final user = await User.find(1);

      expect(user, isNotNull);
      expect(user!.name, 'Carol');
      expect(user.exists, isTrue);
    });

    test('find returns null for non-existent id', () async {
      final user = await User.find(999);
      expect(user, isNull);
    });

    test('can update existing model', () async {
      db.execute(
        "INSERT INTO users (name, email) VALUES ('Dave', 'dave@example.com')"
      );

      final user = await User.find(1);
      user!.name = 'David';
      await user.save();

      final updated = await User.find(1);
      expect(updated!.name, 'David');
    });

    test('can delete model', () async {
      db.execute(
        "INSERT INTO users (name, email) VALUES ('Eve', 'eve@example.com')"
      );

      final user = await User.find(1);
      final result = await user!.delete();

      expect(result, isTrue);
      expect(user.exists, isFalse);

      final deleted = await User.find(1);
      expect(deleted, isNull);
    });

    test('timestamps are updated automatically', () {
      final user = User()..fill({'name': 'Frank'});
      user.updateTimestamps();

      expect(user.createdAt, isNotNull);
      expect(user.updatedAt, isNotNull);
    });

    test('all returns all models', () async {
      db.execute("INSERT INTO users (name, email) VALUES ('Alice', 'a@example.com')");
      db.execute("INSERT INTO users (name, email) VALUES ('Bob', 'b@example.com')");

      final users = await User.all();

      expect(users.length, 2);
      expect(users[0].name, 'Alice');
      expect(users[1].name, 'Bob');
    });

    test('isDirty detects model changes', () {
      final user = User()
        ..fill({'name': 'Original'})
        ..syncOriginal();

      expect(user.isDirty(), isFalse);

      user.name = 'Changed';
      expect(user.isDirty(), isTrue);
      expect(user.isDirty('name'), isTrue);
    });

    test('refresh reloads model from database', () async {
      db.execute("INSERT INTO users (name, email) VALUES ('Grace', 'grace@example.com')");

      final user = await User.find(1);
      expect(user!.name, 'Grace');

      // Update directly in database
      db.execute("UPDATE users SET name = 'Gracey' WHERE id = 1");

      // Refresh the model
      await user.refresh();

      expect(user.name, 'Gracey');
    });
  });
}
```

### Casting and Type Conversions

```dart
test('casts datetime to Carbon', () {
  final user = User();
  user.bornAt = Carbon.parse('2000-01-15T10:30:00');

  final bornAt = user.bornAt;
  expect(bornAt, isA<Carbon>());
  expect(bornAt!.year, 2000);
  expect(bornAt.month, 1);
  expect(bornAt.day, 15);
});

test('casts json to Map', () {
  final user = User();
  user.settings = {'theme': 'dark', 'notifications': true};

  final settings = user.settings;
  expect(settings, isA<Map<String, dynamic>>());
  expect(settings!['theme'], 'dark');
});
```

## Mocking Services

Magic favors manual mocks that extend the service contract (interface) over code-generated mocks. This is simpler and aligns with Laravel's testing philosophy.

### Mocking HTTP Requests

```dart
class MockNetworkDriver extends NetworkDriver {
  Map<String, dynamic>? nextResponse;
  int nextStatusCode = 200;
  Exception? nextException;

  void mock(Map<String, dynamic> data, {int status = 200}) {
    nextResponse = data;
    nextStatusCode = status;
    nextException = null;
  }

  void mockError(Exception error) {
    nextException = error;
  }

  @override
  Future<MagicResponse> get(String url, {Map<String, dynamic>? query}) async {
    if (nextException != null) throw nextException!;
    return MagicResponse(
      data: nextResponse ?? {},
      statusCode: nextStatusCode,
    );
  }

  @override
  Future<MagicResponse> post(String url, {dynamic body}) async {
    if (nextException != null) throw nextException!;
    return MagicResponse(
      data: nextResponse ?? {},
      statusCode: nextStatusCode,
    );
  }

  // Implement other methods as needed
}

// In test:
setUp(() {
  MagicApp.reset();
  Magic.flush();

  final mockHttp = MockNetworkDriver();
  Magic.bind('http.driver', () => mockHttp, shared: true);
});

test('controller handles HTTP response', () async {
  final mockHttp = Magic.make<MockNetworkDriver>('http.driver');
  mockHttp.mock({'user': {'id': 1, 'name': 'Alice'}});

  // Test code that uses Http...
});
```

### Mocking Cache

```dart
class MockCacheStore extends CacheStore {
  final Map<String, dynamic> _cache = {};

  @override
  Future<dynamic> get(String key, {dynamic defaultValue}) async {
    return _cache[key] ?? defaultValue;
  }

  @override
  Future<void> put(String key, dynamic value, {Duration? ttl}) async {
    _cache[key] = value;
  }

  @override
  Future<void> forget(String key) async {
    _cache.remove(key);
  }

  @override
  Future<void> flush() async {
    _cache.clear();
  }
}

setUp(() {
  MagicApp.reset();
  Magic.flush();

  final mockCache = MockCacheStore();
  Magic.bind('cache.store', () => mockCache, shared: true);
});
```

## Test Bootstrap

Magic ships a `MagicTest` helper in `package:magic/testing.dart` that replaces boilerplate `setUp`/`tearDown` wiring.

### Unit / Widget Tests — `MagicTest.init()`

Call once at the top of `main()`. Registers all hooks automatically:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/testing.dart';

void main() {
  MagicTest.init(); // setUpAll + setUp + tearDown wired in one call

  test('container is clean', () {
    // MagicApp.reset() + Magic.flush() already ran
  });
}
```

Hooks registered by `MagicTest.init()`:
- `setUpAll` → `TestWidgetsFlutterBinding.ensureInitialized()`
- `setUp` → `MagicApp.reset()` + `Magic.flush()`
- `tearDown` → `Magic.flush()`

### Integration Tests — `MagicTest.boot()`

Use when providers must boot (full `Magic.init()` lifecycle):

```dart
import 'package:magic/testing.dart';

void main() {
  setUpAll(() async {
    await MagicTest.boot(
      configs: [
        {'database': {'default': 'sqlite', 'connections': {'sqlite': {'driver': 'sqlite', 'database': ':memory:'}}}},
      ],
      envFileName: '.env.testing',
    );
  });

  test('full lifecycle', () async {
    // All service providers have run register() + boot()
  });
}
```

**When to use which:**
- `MagicTest.init()` — unit tests, controller tests, validation tests, facade faking
- `MagicTest.boot()` — integration tests that exercise the full provider lifecycle

## Http Faking

Magic provides a built-in `Http.fake()` API — no third-party mock libraries needed. It swaps the IoC-bound `NetworkDriver` with a `FakeNetworkDriver` that records requests and returns stubbed responses.

### setUp / tearDown Pattern

```dart
late FakeNetworkDriver fake;

setUp(() {
  MagicApp.reset();
  Magic.flush();

  fake = Http.fake(); // All requests return 200 with empty data ({}) by default
});

tearDown(() {
  Http.unfake(); // Restore real driver
});
```

### URL Pattern Stubs

Patterns support `*` as a wildcard. Leading `/` is stripped before matching.

```dart
final fake = Http.fake({
  'users/*': Http.response({'id': 1, 'name': 'Alice'}, 200),
  'auth/login': Http.response({'token': 'test-token'}, 200),
  'posts': Http.response({'message': 'Forbidden'}, 403),
});

final response = await Http.get('/users/42');
expect(response['name'], 'Alice');
```

### Callback Stubs

Pass a `FakeRequestHandler` for dynamic per-request logic.

```dart
final fake = Http.fake((request) {
  if (request.method == 'DELETE') {
    return Http.response({}, 403);
  }

  return Http.response({'ok': true}, 200);
});
```

### Adding Stubs After Construction

Use `fake.stub()` to register patterns incrementally. Later stubs take priority.

```dart
final fake = Http.fake();

fake.stub('users/*', Http.response({'id': 1}, 200));
fake.stub('users/99', Http.response({'error': 'Not found'}, 404)); // Takes priority
```

### Assertion Methods

```dart
// At least one request matched predicate
fake.assertSent((r) => r.url.contains('users'));

// No request matched predicate
fake.assertNotSent((r) => r.url.contains('payments'));

// Exactly zero requests
fake.assertNothingSent();

// Exact request count
fake.assertSentCount(3);
```

### Prevent Stray Requests

```dart
final fake = Http.fake({
  'users': Http.response([], 200),
})..preventStrayRequests();

// Throws StrayRequestException for any URL not matched above
```

### Reset Between Tests

```dart
setUp(() {
  MagicApp.reset();
  Magic.flush();
  fake = Http.fake();
});

// Or reset without restoring real driver:
fake.reset(); // Clears recorded + stubs
```

## Facade Faking

Magic provides built-in fakes for Auth, Cache, Vault, and Log — no third-party mock libraries needed. Each facade exposes `fake()` / `unfake()` methods that swap the IoC-bound service with an in-memory implementation.

### setUp / tearDown Pattern

```dart
late FakeAuthManager authFake;
late FakeCacheManager cacheFake;
late FakeVaultService vaultFake;
late FakeLogManager logFake;

setUp(() {
  MagicApp.reset();
  Magic.flush();

  authFake = Auth.fake();         // In-memory auth, no storage
  cacheFake = Cache.fake();       // In-memory cache, records operations
  vaultFake = Vault.fake();       // In-memory secure storage, no platform channels
  logFake = Log.fake();           // Captures log entries, no console output
});

tearDown(() {
  Auth.unfake();
  Cache.unfake();
  Vault.unfake();
  Log.unfake();
});
```

### Auth.fake()

```dart
// Pre-authenticate with a user
final fake = Auth.fake(user: myUser);
expect(Auth.check(), isTrue);

// Or start as guest
final fake = Auth.fake();
expect(Auth.guest, isTrue);

// Assertions
fake.assertLoggedIn();             // User is authenticated
fake.assertLoggedOut();            // No user authenticated
fake.assertLoginAttempted();       // At least one login() call
fake.assertLoginCount(2);          // Exactly 2 login() calls
```

### Cache.fake()

```dart
final fake = Cache.fake();

await Cache.put('users', ['Alice', 'Bob']);
final value = Cache.get('users');

// Assertions
fake.assertHas('users');           // Key exists in store
fake.assertMissing('missing_key'); // Key not in store
fake.assertPut('users');           // put() was called with this key

// Recorded operations: List<CacheRecord> ({operation, key, value})
expect(fake.recorded.first.operation, 'put');
```

### Vault.fake()

```dart
// Pre-seed with initial values
final fake = Vault.fake({'auth_token': 'seed-token'});

await Vault.put('key', 'value');
await Vault.delete('key');

// Assertions
fake.assertWritten('key');         // put() was called with this key
fake.assertDeleted('key');         // delete() was called with this key
fake.assertContains('key');        // Key currently exists in store
fake.assertMissing('key');         // Key not in store

// Recorded operations: List<VaultOperation> ({operation, key})
expect(fake.recorded.first.operation, 'put');
```

### Log.fake()

```dart
final fake = Log.fake();

Log.error('Payment failed', {'order': 42});
Log.info('User logged in');

// Assertions
fake.assertLogged('error', 'Payment failed');  // Level + message match
fake.assertLoggedError('Payment failed');       // Shorthand for error level
fake.assertNothingLogged();                     // No entries at all
fake.assertNothingLogged('warning');            // No entries at 'warning' level
fake.assertLoggedCount(2);                      // Exactly 2 entries total

// Entries: List<FakeLogEntry> ({level, message, context})
expect(fake.entries[0].level, 'error');
```

### Reset Without Unfaking

Use `fake.reset()` when reusing a fake across multiple tests in a group:

```dart
final logFake = Log.fake();

test('first test', () {
  Log.error('a');
  logFake.assertLoggedCount(1);
  logFake.reset(); // Clear entries — fake remains installed
});

test('second test', () {
  Log.error('b');
  logFake.assertLoggedCount(1); // Starts from zero
});
```

## Middleware Testing

Middleware is tested by verifying whether it calls `next()` or halts the pipeline.

```dart
class EnsureAuthenticated extends MagicMiddleware {
  @override
  void handle(void Function() next) {
    if (!Auth.check()) {
      // Halt pipeline by not calling next()
      return;
    }

    // Allow request to continue
    next();
  }
}

void main() {
  group('EnsureAuthenticated Middleware', () {
    setUp(() {
      MagicApp.reset();
      Magic.flush();
    });

    test('blocks unauthenticated users', () {
      final middleware = EnsureAuthenticated();
      bool nextCalled = false;

      middleware.handle(() {
        nextCalled = true;
      });

      expect(nextCalled, isFalse);
    });

    test('allows authenticated users', () {
      // Setup: mock authenticated state
      final user = User()..fill({'id': 1, 'name': 'Alice'});
      Auth.manager.setUser(user);

      final middleware = EnsureAuthenticated();
      bool nextCalled = false;

      middleware.handle(() {
        nextCalled = true;
      });

      expect(nextCalled, isTrue);
    });
  });
}
```

## Validation Testing

Validation rules can be tested in isolation or via `Validator.make()`.

### Testing Individual Rules

```dart
test('Email rule validates correctly', () {
  final rule = Email();

  expect(rule.passes('email', 'valid@example.com', {}), isTrue);
  expect(rule.passes('email', 'invalid-email', {}), isFalse);
  expect(rule.passes('email', '', {}), isFalse);
});

test('Min rule enforces minimum length', () {
  final rule = Min(6);

  expect(rule.passes('password', 'secret', {}), isFalse); // 6 chars exactly - fails (min is 6 exclusive)
  expect(rule.passes('password', 'password123', {}), isTrue);
});

test('Required rule validates required fields', () {
  final rule = Required();

  expect(rule.passes('name', 'Alice', {}), isTrue);
  expect(rule.passes('name', '', {}), isFalse);
  expect(rule.passes('name', null, {}), isFalse);
});
```

### Testing Validator

```dart
test('validator collects multiple errors', () {
  final validator = Validator.make(
    {
      'email': 'bad-email',
      'password': '123',
      'name': '',
    },
    {
      'email': [Email()],
      'password': [Min(6)],
      'name': [Required()],
    },
  );

  expect(validator.fails(), isTrue);
  expect(validator.errors().length, 3);
  expect(validator.errors()['email'], isNotEmpty);
  expect(validator.errors()['password'], isNotEmpty);
  expect(validator.errors()['name'], isNotEmpty);
});

test('validator passes when all rules pass', () {
  final validator = Validator.make(
    {
      'email': 'alice@example.com',
      'password': 'secret123',
    },
    {
      'email': [Required(), Email()],
      'password': [Required(), Min(8)],
    },
  );

  expect(validator.passes(), isTrue);
  expect(validator.errors(), isEmpty);
});
```

## Integration Testing

Integration tests verify that multiple modules (Auth + Network + Controller, or Database + Service) work together correctly. Place these in `test/integration/`.

### Full Feature Flow

```dart
// test/integration/login_flow_test.dart

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async => '.',
        );
  });

  group('Login Flow Integration', () {
    late Database db;

    setUp(() async {
      MagicApp.reset();
      Magic.flush();

      // Setup database
      db = sqlite3.openInMemory();
      DatabaseManager().setConnection(db);
      db.execute('''
        CREATE TABLE users (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          email TEXT UNIQUE,
          password TEXT,
          created_at TEXT,
          updated_at TEXT
        )
      ''');

      // Setup mock HTTP
      final mockHttp = MockNetworkDriver();
      Magic.bind('http.driver', () => mockHttp, shared: true);

      // Initialize auth with user factory
      await Magic.init(configs: [
        {
          'app': {
            'name': 'Test App',
            'providers': [
              (app) => CacheServiceProvider(app),
              (app) => AuthServiceProvider(app),
            ],
          },
          'auth': {
            'guards': {
              'bearer': {
                'driver': 'bearer',
              },
            },
            'defaults': {
              'guard': 'bearer',
            },
          },
        },
      ]);

      // Set user factory for Auth
      Auth.manager.setUserFactory(User.new);

      // Seed database with test user
      db.execute(
        "INSERT INTO users (email, password) VALUES ('alice@example.com', 'hashed_password')"
      );
    });

    tearDown(() {
      DatabaseManager().dispose();
    });

    test('user can login and access protected resources', () async {
      // Mock HTTP login endpoint
      final mockHttp = Magic.make<MockNetworkDriver>('http.driver');
      mockHttp.mock({
        'token': 'auth_token_123',
        'user': {
          'id': 1,
          'email': 'alice@example.com',
        },
      });

      // Create and test controller
      final authController = AuthController.instance;
      await authController.login('alice@example.com', 'password');

      // Verify auth state
      expect(Auth.check(), isTrue);
      expect(Auth.user<User>()?.email, 'alice@example.com');

      // Verify token was cached
      final token = await Vault.get('auth_token');
      expect(token, 'auth_token_123');
    });

    test('failed login keeps user unauthenticated', () async {
      final mockHttp = Magic.make<MockNetworkDriver>('http.driver');
      mockHttp.mockError(Exception('Invalid credentials'));

      final authController = AuthController.instance;

      try {
        await authController.login('bob@example.com', 'wrong_password');
      } catch (_) {
        // Expected to fail
      }

      expect(Auth.check(), isFalse);
      expect(Auth.user(), isNull);
    });

    test('user can logout and lose access', () async {
      // First login
      final mockHttp = Magic.make<MockNetworkDriver>('http.driver');
      mockHttp.mock({
        'token': 'auth_token_123',
        'user': {'id': 1, 'email': 'alice@example.com'},
      });

      final authController = AuthController.instance;
      await authController.login('alice@example.com', 'password');
      expect(Auth.check(), isTrue);

      // Then logout
      await Auth.logout();
      expect(Auth.check(), isFalse);
      expect(await Vault.get('auth_token'), isNull);
    });
  });
}
```

## Test Directory Structure

Tests must mirror the `lib/src/` structure. This makes tests easy to locate and organize.

```
test/
├── foundation/          # Container, Config, Env tests
│   ├── container_test.dart
│   └── config_test.dart
├── auth/                # Auth guards and managers
│   └── auth_test.dart
├── cache/               # Cache drivers and managers
│   ├── cache_test.dart
│   └── drivers/
│       └── file_store_test.dart
├── database/            # Models, QueryBuilder, Migrations
│   ├── eloquent/
│   │   └── model_test.dart
│   ├── query_builder_test.dart
│   ├── migrator_test.dart
│   └── schema_test.dart
├── events/              # Event dispatcher and listeners
│   └── events_test.dart
├── http/                # Controllers, Middleware, Kernel
│   ├── magic_controller_test.dart
│   └── middleware_test.dart
├── localization/        # Translator and loaders
│   └── localization_test.dart
├── logging/             # Log manager and drivers
│   └── logging_test.dart
├── routing/             # Router tests
│   └── router_test.dart
├── storage/             # File storage and disk operations
│   └── storage_test.dart
├── ui/                  # Views, Forms, responsive widgets
│   ├── magic_view_test.dart
│   ├── magic_form_data_test.dart
│   └── magic_builder_test.dart
├── validation/          # Rules and validator
│   └── validation_test.dart
└── integration/         # Multi-module workflows
    ├── magic_init_test.dart
    └── login_flow_test.dart
```

## Common Testing Patterns

### Testing Config Access

```dart
test('config values can be retrieved', () async {
  await Magic.init(configs: [
    {
      'app': {
        'name': 'My App',
        'debug': true,
      },
    },
  ]);

  expect(Config.get('app.name'), 'My App');
  expect(Config.get('app.debug'), isTrue);
  expect(Config.get('app.missing', 'default'), 'default');
});
```

### Testing Service Providers

```dart
class TestServiceProvider extends ServiceProvider {
  bool registerCalled = false;
  bool bootCalled = false;

  @override
  void register() {
    registerCalled = true;
    app.singleton('test.service', () => TestService());
  }

  @override
  Future<void> boot() async {
    bootCalled = true;
  }
}

test('service provider is registered and booted', () async {
  final provider = TestServiceProvider(MagicApp.instance);
  MagicApp.instance.register(provider);
  await MagicApp.instance.boot();

  expect(provider.registerCalled, isTrue);
  expect(provider.bootCalled, isTrue);
  expect(MagicApp.instance.bound('test.service'), isTrue);
});
```

### Testing Facade Access

```dart
test('Log facade resolves underlying service', () {
  Magic.bind('log', () => TestLogger(), shared: true);

  Log.info('Test message');

  expect(Magic.make<TestLogger>('log').lastMessage, 'Test message');
});

test('Cache facade stores and retrieves values', () async {
  Magic.bind('cache.store', () => TestCacheStore(), shared: true);

  await Cache.put('key', 'value');
  final retrieved = await Cache.get('key');

  expect(retrieved, 'value');
});
```

## Common Gotchas

### Missing setUp Reset

**Problem:** Tests fail intermittently due to state pollution.

**Solution:** Always call `MagicApp.reset()` and `Magic.flush()` in `setUp()`.

```dart
setUp(() {
  MagicApp.reset();
  Magic.flush();
});
```

### Facade Caching Issues

**Problem:** After binding a new service, the facade still returns the old instance.

**Solution:** Call `Magic.flush()` to clear facade caches.

```dart
setUp(() {
  MagicApp.reset();
  Magic.flush(); // Required to clear cached facade instances
});
```

### Database Connection Not Set

**Problem:** Model tests fail because `DatabaseManager` has no active connection.

**Solution:** Create and set the database connection in `setUp()`.

```dart
setUp(() {
  final db = sqlite3.openInMemory();
  DatabaseManager().setConnection(db);
});
```

### Auth User Factory Not Set

**Problem:** `Auth.user<T>()` returns null or throws an error in integration tests.

**Solution:** Call `Auth.manager.setUserFactory()` after `Magic.init()`.

```dart
await Magic.init(configs: [...]);
Auth.manager.setUserFactory(User.new);
```

### Platform Channels in Tests

**Problem:** File storage or path provider tests fail with "No implementation found for method".

**Solution:** Mock the platform channel in `setUpAll()`.

```dart
setUpAll(() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall methodCall) async => '.',
      );
});
```

### Testing Async Operations

**Problem:** Test completes before async operation finishes.

**Solution:** Use `await` or `expectLater()` for async operations.

```dart
test('async operation completes', () async {
  final controller = MyController();

  await controller.fetchData(); // Wait for completion

  expect(controller.isSuccess, isTrue);
});

test('listenable updates state', () {
  final controller = MyController();

  expectLater(
    controller.rxState,
    emits(['item1', 'item2']),
  );

  controller.fetchData();
});
```

### Comparing Model Instances

**Problem:** Two models with the same data are not equal.

**Solution:** Compare using `.toMap()` or individual fields.

```dart
test('models with same data are equivalent', () {
  final user1 = User()..fill({'id': 1, 'name': 'Alice'});
  final user2 = User()..fill({'id': 1, 'name': 'Alice'});

  // Don't use expect(user1, user2)
  expect(user1.toMap(), user2.toMap());
});
```

## Running Tests

```bash
# Run all tests
flutter test

# Run tests in specific module
flutter test test/database/eloquent/model_test.dart

# Run tests matching pattern
flutter test --name "User Model"

# Run with verbose output
flutter test -v

# Run with coverage
flutter test --coverage
```

## Imports

All test files should start with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:magic/magic.dart';
```

For database tests, also add:

```dart
import 'package:sqlite3/sqlite3.dart';
```

For integration tests with platform channels:

```dart
import 'package:flutter/services.dart';
```
