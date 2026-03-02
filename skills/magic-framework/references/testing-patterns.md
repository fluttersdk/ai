# Magic Framework: Testing Patterns

Reference for testing Magic framework applications including service mocking, controller tests, model persistence, and UI integration.

## Required setUp Pattern

Every Magic test MUST reset the global state in `setUp` to prevent state leakage between tests.

```dart
setUp(() {
    // 1. Reset the IoC container
    MagicApp.reset();
    
    // 2. Clear cached facade instances (Log, Auth, Http, etc.)
    Magic.flush();
});
```

## Mocking Services

Magic favors manual mocks that extend the base contract over code-generated mocks.

### Mocking the Network Driver
```dart
class MockNetworkDriver extends NetworkDriver {
    Map<String, dynamic>? nextResponse;
    int nextStatusCode = 200;

    void mock(Map<String, dynamic> data, {int status = 200}) {
        nextResponse = data;
        nextStatusCode = status;
    }

    @override
    Future<MagicResponse> get(String url, {Map<String, dynamic>? query}) async {
        return MagicResponse(data: nextResponse ?? {}, statusCode: nextStatusCode);
    }
    // Implement other methods...
}

// In test:
final mock = MockNetworkDriver();
Magic.setInstance('network', mock); // Inject mock into container
```

## Testing Controllers

Controllers should be tested for state transitions and side effects.

```dart
test('it fetches monitors and sets success state', () async {
    final controller = MonitorController();
    Magic.put<MonitorController>(controller); // Register in container

    mockNetwork.mock({'data': [{'id': 1, 'name': 'Monitor 1'}]});

    await controller.fetchMonitors();

    expect(controller.isSuccess, isTrue);
    expect(controller.rxState, isNotEmpty);
});
```

## Testing Models & Persistence

Use an in-memory SQLite database for fast model testing.

```dart
setUp(() {
    final db = sqlite3.openInMemory();
    DatabaseManager().setConnection(db);
    
    // Run migrations or create tables
    db.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT)');
});

test('model can save to database', () async {
    final user = User()..name = 'Anilcan';
    await user.save();
    
    final found = await User.find(1);
    expect(found?.name, 'Anilcan');
});
```

Middleware are tested by verifying they call or skip `next()`.

```dart
test('EnsureAuthenticated blocks guest users', () async {
    await Auth.logout(); // Ensure guest state
    
    final middleware = EnsureAuthenticated();
    bool nextCalled = false;
    
    middleware.handle(() {
        nextCalled = true;
    });
    
    expect(nextCalled, isFalse); // Middleware halted the pipeline
});

test('EnsureAuthenticated allows authenticated users', () async {
    // Setup: mock auth state
    final user = User()..fill({'id': 1, 'name': 'Test'});
    await Auth.login({'token': 'test'}, user);
    
    final middleware = EnsureAuthenticated();
    bool nextCalled = false;
    
    middleware.handle(() {
        nextCalled = true;
    });
    
    expect(nextCalled, isTrue);
});
```

## Testing Forms & Validation

Test validation rules in isolation or via `Validator.make()`.

```dart
test('email rule validates correctly', () {
    final rule = Email();
    
    expect(rule.passes('email', 'valid@example.com', {}), isTrue);
    expect(rule.passes('email', 'invalid-email', {}), isFalse);
});

test('validator catches multiple errors', () {
    final validator = Validator.make(
        {'email': 'bad', 'password': '123'},
        {'email': [Email()], 'password': [Min(6)]}
    );
    
    expect(validator.fails(), isTrue);
    expect(validator.errors().length, 2);
});
```

## Integration Test Patterns

Integration tests verify that multiple modules (e.g., Auth + Network + Controller) work together.

```dart
test('full login flow', () async {
    await Magic.init(configFactories: [() => testConfig]);
    
    final controller = AuthController.instance;
    mockNetwork.mock({'token': 'secret_token', 'user': {'id': 1, 'name': 'Anilcan'}});
    
    await controller.login('anilcan@example.com', 'password');
    
    expect(Auth.check(), isTrue);
    expect(Auth.user()?.name, 'Anilcan');
    expect(await Vault.get('auth_token'), 'secret_token');
});
```

## Directory Structure

Test files MUST mirror the `lib/src/` structure.

```text
test/
├── foundation/    # Container, Config, Env
├── auth/          # Guards, Gates
├── cache/         # Drivers
├── database/      # Models, QueryBuilder
├── events/        # Dispatcher, Listeners
├── http/          # Controllers, Middleware
├── integration/   # Multi-module flows
└── validation/    # Rules, Validator
```

## Gotchas

- **Magic.flush()**: Crucial if your tests change container bindings. Facades cache instances internally and won't see new bindings without a flush.
- **SQLite In-Memory**: Use `sqlite3.openInMemory()` to avoid filesystem artifacts.
- **Platform Channels**: Use `TestDefaultBinaryMessengerBinding` to mock platform-specific logic (e.g., `path_provider` for `FileStore`).
- **Kernel.flush()**: Call `Kernel.flush()` in `setUp` alongside `MagicApp.reset()` and `Magic.flush()` when testing middleware registration.
- **Auth User Factory**: Always call `Auth.manager.setUserFactory()` in your integration test setup if testing `Auth.user<T>()`.
