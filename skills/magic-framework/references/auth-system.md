# Authentication System

Guard-based authentication layer with secure storage, automatic token refresh, and session restoration.

## Auth Facade API

The `Auth` facade proxies calls to the default guard.

| Method | Signature | Description |
|:-------|:----------|:------------|
| `check` | `bool check()` | Is the user authenticated? |
| `guest` | `bool get guest` | Is the user NOT authenticated? |
| `user` | `T? user<T extends Model>()` | Get the current authenticated user |
| `id` | `dynamic id()` | Get the user's primary key |
| `login` | `Future<void> login(Map data, Authenticatable user)` | Store credentials and set authenticated user |
| `logout`| `Future<void> logout()` | Clear storage and user state |
| `restore`| `Future<void> restore()` | Restore session from storage (on app boot) |
| `hasToken`| `Future<bool> hasToken()` | Check if a token exists in storage |
| `getToken`| `Future<String?> getToken()` | Get the current token from storage |
| `refreshToken`| `Future<bool> refreshToken()` | Manually trigger a token refresh |
| `registerModel`| `registerModel<T>(factory)` | Register the user factory (alias for `manager.setUserFactory`) |
| `stateNotifier`| `ValueNotifier<int> get stateNotifier` | Reactive notifier — bumps on login/logout/restore |

## Setup: User Factory (REQUIRED)

Magic needs a factory to hydrate your `User` model from JSON. Register this in a `ServiceProvider.boot()` method.

```dart
// lib/app/providers/app_service_provider.dart
@override
Future<void> boot() async {
    Auth.manager.setUserFactory((data) => User.fromMap(data));
}
```

## Auth Configuration

Defined in `config/auth.dart`.

```dart
// lib/config/auth.dart
final Map<String, dynamic> authConfig = {
    'defaults': {
        'guard': 'api',
    },
    'guards': {
        'api': {
            'driver': 'bearer',
        },
    },
    'endpoints': {
        'user': '/api/user',     // Fetch fresh user data on restore
        'refresh': '/api/refresh', // Token refresh endpoint
    },
    'token': {
        'key': 'auth_token',     // Vault storage key
        'header': 'Authorization',
        'prefix': 'Bearer',
    },
};
```

## Guards

Guards implement the `Guard` contract and handle the specifics of credential storage.

### BearerTokenGuard
The default for JWT or Laravel Sanctum.
- **Header**: `Authorization: Bearer <token>`
- **Storage**: Persists token in secure `Vault`.
- **Refresh**: Supports `refreshToken()` via `refresh_token` if configured.

### BasicAuthGuard
- **Header**: `Authorization: Basic <base64>`
- **Login**: Expects `{'username': '...', 'password': '...'}`.

### ApiKeyGuard
- **Header**: Custom header (e.g., `X-API-KEY: <key>`)
- **Login**: Expects `{'token': '...'}` or `{'api_key': '...'}`.

## Token Management

Tokens are stored in the hardware-backed `Vault` (Secure Storage).
- `Auth.login(data, user)`: Extracts token from `data` and saves to `Vault`.
- `Auth.restore()`: 
    1. Loads token from `Vault`.
    2. Loads user from local cache (instant UI).
    3. Fetches fresh user from `user` endpoint in background (syncs state).

## Auth Interceptor & Refresh

The `AuthInterceptor` is automatically added to the `Http` facade.
- **Injection**: Injects the active guard's token into every request's headers.
- **401 Retry**: 
    1. If a 401 occurs, it calls `Auth.refreshToken()`.
    2. If successful, it retries the original request **once**.
    3. If refresh fails, it calls `Auth.logout()` and redirects to login.

## Gate & Policies

Authorization is handled via the `Gate` facade and `Policy` classes.

```dart
// Define an ability
Gate.define('update-monitor', (user, monitor) => user.id == monitor.teamId);

// Check ability
if (Gate.allows('update-monitor', monitor)) {
    // User can update
}
```

**Policies** (grouped logic for a model):
```dart
class MonitorPolicy extends Policy<Monitor> {
    bool update(User user, Monitor monitor) => user.id == monitor.userId;
    bool delete(User user, Monitor monitor) => user.isAdmin;
}
```

## Usage Examples

**Manual Login Flow:**
```dart
final response = await Http.post('/login', data: credentials);
if (response.successful) {
    final user = User.fromMap(response['user']);
    // Store token and user
    await Auth.login({'token': response['token']}, user);
    MagicRoute.to('/');
}
```

## Reactive Auth State

`Auth.stateNotifier` is a `ValueNotifier<int>` that increments on every auth state change (login, logout, restore). Use it to reactively rebuild UI:

```dart
ValueListenableBuilder(
    valueListenable: Auth.stateNotifier,
    builder: (context, _, child) {
        if (Auth.guest) return const LoginView();
        return const DashboardView();
    },
)
```
```dart
ValueListenableBuilder(
    valueListenable: Auth.stateNotifier,
    builder: (context, _, child) {
        if (Auth.guest) return const LoginView();
        return const DashboardView();
    },
)
```

## Gotchas

- **User Factory**: If `Auth.user` is null but `Auth.check()` is true, you forgot to call `Auth.manager.setUserFactory()`.
- **Wait for Restore**: Always `await Auth.restore()` in your app's boot process to prevent flickers or unauthorized requests.
- **Reactive UI**: Use `Auth.stateNotifier` to rebuild widgets when auth state changes. It fires on login, logout, and restore completion.
- **401 Loop**: The interceptor only retries once. If the second attempt is also 401, the error propagates.
- **Prefix Defaults**: `token.prefix` defaults to `Bearer`. If using `ApiKeyGuard` with a raw key, set `prefix` to an empty string in config.
