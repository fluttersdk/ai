# Authentication & Authorization System

Guard-based authentication with secure token storage, automatic session restoration, and authorization via Gate and Policies.

## Auth Facade

The `Auth` facade provides static access to the authentication system and proxies calls to the default guard.

### Login & Logout

```dart
import 'package:magic/magic.dart';

// Login (app handles API call, parses response)
final response = await Http.post('/login', data: {'email': ..., 'password': ...});
final user = User.fromMap(response.data['user']);
await Auth.login({'token': response.data['token']}, user);
Route.to('/dashboard');

// Logout
await Auth.logout();
```

### Check Authentication State

```dart
if (Auth.check()) {
  final user = Auth.user<User>();
  print(user?.name);
} else {
  print('Not logged in');
}

// Check if guest (not authenticated)
if (Auth.guest) {
  Route.to('/login');
}

// Get user ID
final userId = Auth.id();
```

### Session Restoration

`Auth.restore()` must be called during app boot to restore the user from stored credentials.

```dart
// In main() or MagicApp initialization
await Magic.init();
await Auth.restore();
if (Auth.check()) {
  Route.to('/dashboard');
} else {
  Route.to('/login');
}
```

**Restoration process:**
1. Load token from Vault (secure storage)
2. Load user from local cache (instant UI)
3. Fetch fresh user from API endpoint in background (syncs data)

If API sync fails, the cached user remains authenticated.

### Token Management

```dart
// Check if token exists
final hasToken = await Auth.hasToken();

// Get stored token
final token = await Auth.getToken();

// Manually refresh token
final success = await Auth.refreshToken();
```

### User Factory Registration

Magic requires a factory to hydrate your `User` model from JSON. Register this in a `ServiceProvider.boot()` method **before `AuthServiceProvider` boots**.

```dart
// lib/app/providers/app_service_provider.dart
import 'package:magic/magic.dart';

class AppServiceProvider extends ServiceProvider {
  @override
  void register() {}

  @override
  Future<void> boot() async {
    // MUST be called before Auth.restore() runs
    Auth.manager.setUserFactory((data) => User.fromMap(data));
  }
}
```

Ensure `AppServiceProvider` is listed **before** `AuthServiceProvider` in your app's `config/app.dart`:

```dart
'providers': [
  AppServiceProvider, // Must be first
  AuthServiceProvider,
  // ...
],
```

### Reactive State

`Auth.stateNotifier` is a `ValueNotifier<int>` that bumps on every auth state change (login, logout, restore). Use it to reactively rebuild UI:

```dart
ValueListenableBuilder(
  valueListenable: Auth.stateNotifier,
  builder: (context, _, child) {
    if (Auth.guest) return const LoginView();
    return const DashboardView();
  },
)
```

### Get a Specific Guard

```dart
// Get default guard
final guard = Auth.guard();

// Get named guard
final apiGuard = Auth.guard('api');

// Login/logout/check on specific guard
await apiGuard.login(data, user);
final isAuthed = apiGuard.check();
```

## Auth Configuration

Defined in `lib/config/auth.dart`.

```dart
final Map<String, dynamic> defaultAuthConfig = {
  'auth': {
    // -----------------------------------------------
    // Defaults
    // -----------------------------------------------
    'defaults': {
      'guard': 'api',  // Default guard name
    },

    // -----------------------------------------------
    // Guards (per-guard configuration)
    // -----------------------------------------------
    'guards': {
      'api': {
        'driver': 'bearer',  // Or 'basic', 'api_key'
      },
    },

    // -----------------------------------------------
    // API Endpoints
    // -----------------------------------------------
    'endpoints': {
      'user': '/api/user',       // Fetch fresh user on restore
      'refresh': '/api/refresh', // Token refresh endpoint
    },

    // -----------------------------------------------
    // Token Storage & Headers
    // -----------------------------------------------
    'token': {
      'key': 'auth_token',        // Vault storage key for access token
      'refresh_key': 'refresh_token', // Vault storage key for refresh token
      'header': 'Authorization',  // HTTP header name
      'prefix': 'Bearer',         // Header prefix (e.g., "Bearer <token>")
    },

    // -----------------------------------------------
    // User Caching
    // -----------------------------------------------
    'cache': {
      'user_key': 'auth_user',  // Vault key for cached user JSON
    },

    // -----------------------------------------------
    // Auto Restoration
    // -----------------------------------------------
    'auto_refresh': true,  // Automatically restore session on boot
  },
};
```

## Guards

Guards implement the `Guard` contract and handle authentication specifics.

### BearerTokenGuard (Default)

Token-based authentication for JWT or Laravel Sanctum.

- **Driver**: `'bearer'` or `'sanctum'`
- **Header**: `Authorization: Bearer <token>`
- **Storage**: Token persisted in Vault
- **Refresh**: Supports `refreshToken()` if `refresh_token` is configured
- **Use case**: JSON Web Tokens, OAuth tokens

```dart
// config/auth.dart
'guards': {
  'api': {
    'driver': 'bearer',  // or 'sanctum'
  },
},

// Login with refresh token (optional)
await Auth.login({
  'token': response['token'],
  'refresh_token': response['refresh_token'],  // Optional
}, user);
```

### BasicAuthGuard

HTTP Basic Authentication (username:password encoded in base64).

- **Driver**: `'basic'`
- **Header**: `Authorization: Basic <base64(username:password)>`
- **Storage**: Base64-encoded credentials in Vault
- **Use case**: API with basic auth, service-to-service auth

```dart
// config/auth.dart
'guards': {
  'api': {
    'driver': 'basic',
  },
},

// Login
await Auth.login({
  'username': 'user@example.com',
  'password': 'secret',
}, user);
```

### ApiKeyGuard

Static API key authentication.

- **Driver**: `'api_key'`
- **Header**: Custom header with API key (default: `X-API-KEY`)
- **Storage**: Key persisted in Vault
- **Use case**: Service-to-service APIs, fixed credentials

```dart
// config/auth.dart
'guards': {
  'api': {
    'driver': 'api_key',
  },
},

// Login
await Auth.login({
  'api_key': 'sk_live_xxx',
}, user);
```

## Token Management

Tokens are stored in the hardware-backed Vault (secure storage).

- **Access Token**: Stored under `token.key` (default: `'auth_token'`)
- **Refresh Token**: Stored under `token.refresh_key` (default: `'refresh_token'`)

### Login Flow

```dart
final response = await Http.post('/login', data: credentials);
final user = User.fromMap(response.data['user']);
await Auth.login({
  'token': response.data['token'],
  'refresh_token': response.data['refresh_token'],  // Optional
}, user);
```

The `login()` method extracts tokens from the data map and persists them securely. On subsequent API calls, the `AuthInterceptor` automatically injects the token into request headers.

### Token Refresh

The `AuthInterceptor` automatically handles token refresh on 401:

1. Guard returns 401 from API
2. Interceptor calls `Auth.refreshToken()`
3. If successful, retries the original request once
4. If refresh fails, calls `Auth.logout()` and user is redirected to login

Manual refresh:

```dart
final success = await Auth.refreshToken();
if (!success) {
  // Refresh failed, user is logged out
  Route.to('/login');
}
```

## Gate & Authorization

The `Gate` facade provides declarative authorization checks.

### Define Abilities

Abilities are registered via `Gate.define()` in a service provider or controller boot.

```dart
// lib/app/providers/gate_service_provider.dart
import 'package:magic/magic.dart';

class GateServiceProvider extends ServiceProvider {
  @override
  void register() {}

  @override
  Future<void> boot() async {
    // Simple ability
    Gate.define('view-dashboard', (user) => true);

    // Ability with model argument
    Gate.define('update-post', (user, post) => user.id == post.userId);

    // Complex logic
    Gate.define('delete-post', (user, post) =>
      user.isAdmin || user.id == post.userId
    );

    // Register policies
    PostPolicy().register();
    CommentPolicy().register();
  }
}
```

### Check Abilities

```dart
// Check if user CAN perform ability
if (Gate.allows('update-post', post)) {
  showEditButton();
}

// Check if user CANNOT perform ability
if (Gate.denies('delete-post', post)) {
  showAccessDenied();
}

// Alias for allows()
if (Gate.check('view-dashboard')) {
  showDashboard();
}

// Check if ability exists
if (Gate.has('update-post')) {
  // ...
}

// Get all defined abilities
final abilities = Gate.abilities;
```

### Super Admin Bypass

Use `Gate.before()` to register a callback that runs before all ability checks. Useful for super-admin bypass:

```dart
Gate.before((user, ability) {
  if (user.isAdmin) {
    return true;  // Grant access
  }
  return null;    // Continue with normal check
});
```

Return values:
- `true` → Allow access, skip normal check
- `false` → Deny access, skip normal check
- `null` → Continue with normal ability check

### Policies

Policies group authorization logic for a model. Create a policy by extending `Policy` and implementing `register()`.

```dart
// lib/app/policies/post_policy.dart
import 'package:magic/magic.dart';

class PostPolicy extends Policy {
  @override
  void register() {
    Gate.define('view-post', view);
    Gate.define('create-post', create);
    Gate.define('update-post', update);
    Gate.define('delete-post', delete);
  }

  bool view(Model user, Post post) {
    return post.isPublished || user.id == post.userId;
  }

  bool create(Model user) {
    return true;  // Anyone can create
  }

  bool update(Model user, Post post) {
    return user.id == post.userId;
  }

  bool delete(Model user, Post post) {
    return user.isAdmin || user.id == post.userId;
  }
}
```

Register policies in a service provider:

```dart
@override
Future<void> boot() async {
  PostPolicy().register();
  CommentPolicy().register();
}
```

## Authorization Widgets

### MagicCan

Conditionally render content if the user has an ability.

```dart
import 'package:magic/magic.dart';

MagicCan(
  ability: 'update-post',
  arguments: post,
  child: WButton(
    text: 'Edit Post',
    onTap: () => controller.edit(post),
  ),
)
```

With placeholder (rendered if denied):

```dart
MagicCan(
  ability: 'view-admin-panel',
  child: AdminPanel(),
  placeholder: Text('Access Denied'),
)
```

Multiple abilities via nesting:

```dart
// Show edit button if user can update, otherwise show view button if user can view
MagicCan(
  ability: 'update-post',
  arguments: post,
  child: EditButton(),
  placeholder: MagicCan(
    ability: 'view-post',
    arguments: post,
    child: ViewButton(),
  ),
)
```

### MagicCannot

Conditionally render content if the user CANNOT perform an ability (inverse of MagicCan).

```dart
MagicCannot(
  ability: 'view-content',
  child: LoginPrompt(),
)
```

## User Model: Authenticatable Mixin

Your user model must implement the `Authenticatable` mixin to work with guards.

```dart
import 'package:magic/magic.dart';

class User extends Model with Authenticatable {
  @override
  String get table => 'users';

  @override
  String get resource => 'users';
}
```

The `Authenticatable` mixin provides:

| Property | Type | Description |
|:---------|:-----|:------------|
| `authIdentifier` | `dynamic` | Unique identifier (typically primary key value) |
| `authIdentifierName` | `String` | Identifier column name (typically `'id'`) |
| `authPassword` | `String?` | Password (reads from `'password'` column) |

Override properties if your schema differs:

```dart
class User extends Model with Authenticatable {
  @override
  String? get authPassword => getAttribute('hashed_password');
}
```

## Auth Events

The auth system dispatches events on state changes:

| Event | Fired | Data |
|:------|:------|:-----|
| `AuthRestored` | After successful session restore | `user` |
| `AuthLoginAttempted` | When login is attempted | (none) |
| `AuthLogoutAttempted` | When logout is requested | (none) |
| `GateAbilityDefined` | When ability is registered | `ability` |
| `GateAccessChecked` | After every Gate check | `ability`, `arguments`, `allowed`, `user` |
| `GateAccessDenied` | When access is denied | `ability`, `arguments`, `user` |

Register listeners in a ServiceProvider:

```dart
@override
Future<void> boot() async {
  EventDispatcher.instance.register(AuthRestored, [
    () => MyAuthRestoredListener(),
  ]);

  EventDispatcher.instance.register(GateAccessDenied, [
    () => MyAccessDeniedListener(),
  ]);
}
```

## Gotchas

| Mistake | Fix |
|:--------|:----|
| User factory not registered | Call `Auth.manager.setUserFactory()` in a provider `boot()` method **before** `AuthServiceProvider` |
| `Auth.user` is null even though `Auth.check()` is true | User factory must be registered before any authentication |
| `Auth.restore()` not awaited on boot | Always `await Auth.restore()` during app initialization to prevent UI flicker |
| `Auth.guest` throws error (used as method) | `Auth.guest` is a GETTER, not a method. Write `Auth.guest` not `Auth.guest()` |
| Token not injected into API requests | Ensure `AuthInterceptor` is registered (automatic via `AuthServiceProvider`) |
| 401 retry loop never ends | Interceptor retries once only. If second attempt is also 401, error propagates |
| `Api_keyGuard` header always uses `X-API-KEY` | Customize via `token.header` in config |
| `Gate.allows()` called before user factory is set | Gate checks `Auth.user()` internally — ensure factory is registered first |
| Policy ability not defined | Call `PolicyClass().register()` in a service provider `boot()` method |
