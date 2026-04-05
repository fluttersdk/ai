# HTTP & Network System

Magic provides a Laravel-inspired HTTP client built on Dio, with RESTful resource helpers, form validation error parsing, and a consistent response interface.

Import via:
```dart
import 'package:magic/magic.dart';
```

## Network Configuration

Defined in `lib/config/network.dart`. The default configuration uses the `api` driver.

```dart
// lib/config/network.dart
Map<String, dynamic> defaultNetworkConfig = {
  'network': {
    'default': 'api',
    'drivers': {
      'api': {
        'driver': 'dio',
        'base_url': 'https://api.example.com/v1',
        'timeout': 10000,
        'interceptors': [
          // Optional: user-defined interceptor class names
          // 'AuthInterceptor',
        ],
        'headers': {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      },
    },
  },
};
```

Configuration options:
- `base_url`: Root URL for all requests
- `timeout`: Request timeout in milliseconds
- `headers`: Default headers sent with every request
- `interceptors`: List of interceptor class names to register on boot

## Http Facade

The `Http` facade provides static access to the network driver for making requests.

### RESTful Resource Methods

These methods follow Laravel conventions, auto-constructing resource URLs.

#### `index(String resource, {Map<String, dynamic>? filters, Map<String, String>? headers})`

Fetch all resources via `GET /resource`.

```dart
final response = await Http.index('users');
// GET https://api.example.com/v1/users

final response = await Http.index('posts', filters: {'status': 'published'});
// GET https://api.example.com/v1/posts?status=published
```

#### `show(String resource, String id, {Map<String, String>? headers})`

Fetch a single resource via `GET /resource/{id}`.

```dart
final response = await Http.show('users', '123');
// GET https://api.example.com/v1/users/123
```

#### `store(String resource, Map<String, dynamic> data, {Map<String, String>? headers})`

Create a new resource via `POST /resource`.

```dart
final response = await Http.store('users', {
  'name': 'John Doe',
  'email': 'john@example.com',
});
// POST https://api.example.com/v1/users
```

#### `update(String resource, String id, Map<String, dynamic> data, {Map<String, String>? headers})`

Update a resource via `PUT /resource/{id}`.

```dart
final response = await Http.update('users', '123', {
  'name': 'Jane Doe',
});
// PUT https://api.example.com/v1/users/123
```

#### `destroy(String resource, String id, {Map<String, String>? headers})`

Delete a resource via `DELETE /resource/{id}`.

```dart
final response = await Http.destroy('users', '123');
// DELETE https://api.example.com/v1/users/123
```

### Raw HTTP Methods

Use these for full control over URL paths and request bodies.

#### `get(String url, {Map<String, dynamic>? query, Map<String, String>? headers})`

Perform a GET request with optional query parameters.

```dart
final response = await Http.get('/users');

final response = await Http.get('/search', query: {'q': 'flutter', 'limit': 10});
// GET /search?q=flutter&limit=10
```

#### `post(String url, {dynamic data, Map<String, String>? headers})`

Perform a POST request with a request body.

```dart
final response = await Http.post('/register', data: {
  'email': 'user@example.com',
  'password': 'secret123',
});
```

#### `put(String url, {dynamic data, Map<String, String>? headers})`

Perform a PUT request to update a resource.

```dart
final response = await Http.put('/profile', data: {
  'bio': 'Updated bio',
});
```

#### `delete(String url, {Map<String, String>? headers})`

Perform a DELETE request.

```dart
final response = await Http.delete('/notifications/123');
```

#### `upload(String url, {required Map<String, dynamic> data, required Map<String, dynamic> files, Map<String, String>? headers})`

Upload files via multipart form data. Automatically sets `Content-Type: multipart/form-data`.

```dart
final response = await Http.upload('/teams/123', data: {
  'name': 'Team Name',
  '_method': 'PUT', // Laravel method spoofing (optional)
}, files: {
  'logo': logoFile, // MagicFile, XFile, String (path), Uint8List, or List<int>
});
```

Files parameter accepts:
- `MagicFile`: Magic's file wrapper (supports bytes, XFile, paths)
- `XFile`: image_picker or file_picker result
- `String`: File path
- `Uint8List` or `List<int>`: Raw bytes (filename derived from field name)
- `MultipartFile`: Dio's multipart type (advanced)

## MagicResponse API

All `Http` methods return a `MagicResponse`, which wraps the HTTP response and provides helper methods for error handling.

### Status Checks

| Property | Type | Description |
|:---------|:-----|:------------|
| `successful` | `bool` | Status code 200–299 |
| `failed` | `bool` | Status code >= 400 |
| `clientError` | `bool` | Status code 400–499 |
| `serverError` | `bool` | Status code >= 500 |
| `unauthorized` | `bool` | Status code 401 |
| `forbidden` | `bool` | Status code 403 |
| `notFound` | `bool` | Status code 404 |
| `isValidationError` | `bool` | Status code 422 |

### Response Data

| Property | Type | Description |
|:---------|:-----|:------------|
| `data` | `dynamic` | Raw response body (Map, List, String, etc.) |
| `statusCode` | `int` | HTTP status code |
| `headers` | `Map<String, dynamic>` | Response headers |
| `message` | `String?` | Optional status message |
| `operator[]` | `dynamic` | Shorthand for `data[key]` when data is a Map |

```dart
final response = await Http.get('/users/123');

if (response.successful) {
  print(response.data); // Raw data
  print(response.statusCode); // 200
  print(response['name']); // Equivalent to response.data['name']
}
```

### Validation Error Parsing

Magic automatically parses Laravel's validation error format: `{"errors": {"field": ["message"]}}`.

| Property | Type | Description |
|:---------|:-----|:------------|
| `errors` | `Map<String, List<String>>` | Validation errors by field |
| `errorsList` | `List<String>` | Flat list of all error messages |
| `firstError` | `String?` | First error message or root `message` key |
| `errorMessage` | `String?` | Top-level `message` field from response |

```dart
final response = await Http.post('/register', data: formData);

if (response.isValidationError) {
  // Access all errors by field
  response.errors.forEach((field, messages) {
    print('$field: ${messages.join(", ")}');
  });

  // Or get first error for UI display
  print(response.firstError); // "The email field is required."

  // Or flatten all errors
  print(response.errorsList); // ["email required", "password required"]
}
```

### Type Casting

```dart
// Cast the entire data response to a specific type
final users = response.dataAs<List>();

// Or access nested data via the [] operator
final userName = response['user']['name'];
```

## Validation Error Example

When a Laravel API returns a 422 response:

```json
{
  "errors": {
    "email": ["The email field is required."],
    "password": ["The password must be at least 8 characters."]
  }
}
```

Access in Dart:

```dart
final res = await Http.post('/register', data: formData);

if (res.isValidationError) {
  print(res.errors);
  // {"email": ["The email field is required."], "password": [...]}

  print(res.firstError);
  // "The email field is required."

  print(res.errorsList);
  // ["The email field is required.", "The password must be at least 8 characters."]
}
```

## Interceptors

Implement `MagicNetworkInterceptor` to hook into the request/response lifecycle for logging, auth injection, or error recovery.

```dart
import 'package:magic/magic.dart';

class LoggingInterceptor extends MagicNetworkInterceptor {
  @override
  Future<dynamic> onRequest(MagicRequest request) async {
    print('HTTP Request: ${request.method} ${request.url}');
    print('Headers: ${request.headers}');
    return request; // Return modified request or original
  }

  @override
  Future<dynamic> onResponse(MagicResponse response) async {
    print('HTTP Response: ${response.statusCode}');
    return response;
  }

  @override
  Future<dynamic> onError(MagicError error) async {
    print('HTTP Error: ${error.statusCode} ${error.message}');
    // Return a MagicResponse to resolve the error (e.g., after retry)
    // Or return error to propagate it
    return error;
  }
}
```

Register in a `ServiceProvider.boot()` or directly:

```dart
// In a service provider
boot() {
  Magic.make<NetworkDriver>('network').addInterceptor(LoggingInterceptor());
}

// Or directly after Magic.init()
await Magic.init();
Magic.make<NetworkDriver>('network').addInterceptor(LoggingInterceptor());
```

## Driver Plugin Hook

For SDK integrations that need direct Dio access (e.g., `sentry_dio`, certificate pinning), use `configureDriver()`:

```dart
// In a service provider boot()
final driver = Magic.make<DioNetworkDriver>('network');
driver.configureDriver((dio) {
  dio.addSentry(); // sentry_dio integration
});
```

This is a `DioNetworkDriver`-specific method (not on the `NetworkDriver` contract). Cast or resolve as `DioNetworkDriver` to access it.

## ValidatesRequests Mixin

Use the `ValidatesRequests` mixin in controllers to simplify validation error mapping from HTTP responses.

```dart
import 'package:magic/magic.dart';

class RegisterController extends MagicController with ValidatesRequests {
  Future<void> submit(Map<String, dynamic> data) async {
    final res = await Http.post('/register', data: data);

    if (res.isValidationError) {
      setErrorsFromResponse(res); // Populates validationErrors map
      return;
    }

    if (res.successful) {
      // Handle success
    }
  }
}
```

The mixin provides:
- `validationErrors`: Map of field errors
- `setErrorsFromResponse(MagicResponse)`: Parse 422 response into validationErrors
- `hasError(String field)`: Check if a field has errors
- `fieldError(String field)`: Get error message for a field

## MagicStateMixin Fetch Helpers

`MagicStateMixin<T>` ships `fetchList()` and `fetchOne()` to eliminate boilerplate loading/success/error state transitions for HTTP fetches.

### `fetchList<E>(url, fromMap, {dataKey, query, headers})`

Fetches a JSON array under `dataKey` (default `'data'`) and calls `setSuccess(items)`, `setEmpty()`, or `setError(message)` automatically.

```dart
class ProjectController extends MagicController
    with MagicStateMixin<List<Project>> {
  Future<void> loadProjects(String teamId) =>
      fetchList('teams/$teamId/projects', Project.fromMap);
}
```

Signature:
```dart
Future<void> fetchList<E>(
  String url,
  E Function(Map<String, dynamic>) fromMap, {
  String dataKey = 'data',
  Map<String, dynamic>? query,
  Map<String, String>? headers,
})
```

Note: `E` is the element type of the list. The resulting `List<E>` is cast to `T` (the mixin's type parameter), so declare the controller as `MagicStateMixin<List<E>>`.

### `fetchOne(url, fromMap, {dataKey, query, headers})`

Fetches a single object under `dataKey` (default `'data'`) and calls `setSuccess(item)` or `setError(message)` automatically.

```dart
class ProjectDetailController extends MagicController
    with MagicStateMixin<Project> {
  Future<void> loadProject(String id) =>
      fetchOne('projects/$id', Project.fromMap);
}
```

Signature:
```dart
Future<void> fetchOne(
  String url,
  T Function(Map<String, dynamic>) fromMap, {
  String dataKey = 'data',
  Map<String, dynamic>? query,
  Map<String, String>? headers,
})
```

State transition table (both helpers):

| Condition | State |
|-----------|-------|
| Response `failed` (>= 400) | `setError(response.errorMessage ?? 'Failed to load')` |
| Response body is not a JSON object (`Map`) | `fetchList`: `setEmpty()` / `fetchOne`: `setError('Invalid response format')` |
| `fetchList`: `dataKey` value is not a `List`, is empty, or contains no valid `Map` elements | `setEmpty()` |
| `fetchOne`: `dataKey` value is `null` | `setError('Resource not found')` |
| `fetchOne`: `dataKey` value is not a `Map<String, dynamic>` | `setError('Invalid response: "<dataKey>" must contain a JSON object')` (interpolates actual key) |
| Data present and valid | `setSuccess(parsed)` |

Testing with `Http.fake()`:
```dart
Http.fake({
  'teams/*/projects': Http.response({
    'data': [
      {'id': 1, 'name': 'Project A'},
    ],
  }, 200),
});

await controller.loadProjects('team-1');

expect(controller.isSuccess, isTrue);
expect(controller.rxState?.length, 1);
```

## Common Patterns

### Error Handling with Network Requests

```dart
final response = await Http.post('/users', data: userData);

if (response.successful) {
  print('User created: ${response['id']}');
} else if (response.isValidationError) {
  print('Validation failed: ${response.firstError}');
} else if (response.unauthorized) {
  // Redirect to login
} else if (response.serverError) {
  print('Server error: ${response.statusCode}');
}
```

### Custom Headers per Request

```dart
final response = await Http.get('/protected', headers: {
  'Authorization': 'Bearer $token',
  'X-Custom-Header': 'value',
});
```

### File Upload with Additional Data

```dart
final response = await Http.upload('/posts', data: {
  'title': 'My Post',
  'description': 'A great post',
}, files: {
  'featured_image': imageFile,
  'attachment': documentFile,
});
```

### Handling Data Wrapping

Many APIs wrap responses in a `data` key. Use the `[]` operator or access `data['data']`:

```dart
final response = await Http.get('/users');
// Response: {"data": [{"id": 1, "name": "John"}], "meta": {...}}

final users = response['data']; // [{"id": 1, "name": "John"}]
// Or: response.data['data']
```

## Testing

Magic provides a built-in `Http.fake()` API that swaps the real `NetworkDriver` with a `FakeNetworkDriver`. No third-party mock libraries are required.

### `Http.fake([dynamic stubs])` → `FakeNetworkDriver`

Registers a fake driver in the IoC container and returns it for assertion.

- No args — all requests return 200 with `null` data.
- `Map<String, MagicResponse>` — URL pattern to response mapping (`*` wildcard supported).
- `FakeRequestHandler` — callback receiving `MagicRequest`, returning `MagicResponse`.

```dart
setUp(() {
  MagicApp.reset();
  Magic.flush();

  // All requests → 200 empty
  final fake = Http.fake();

  // URL pattern stubs
  final fake = Http.fake({
    'users/*': Http.response({'id': 1, 'name': 'Alice'}, 200),
    'auth/login': Http.response({'token': 'abc'}, 200),
  });

  // Callback stub
  final fake = Http.fake((request) {
    return Http.response({'ok': true}, 200);
  });
});
```

### `Http.response([dynamic data, int statusCode = 200])` → `MagicResponse`

Factory helper for building stub responses.

```dart
Http.response()                                  // 200, empty Map ({})
Http.response({'id': 1, 'name': 'Alice'})        // 200, Map
Http.response({'message': 'Not found'}, 404)     // 404, Map
Http.response([{'id': 1}, {'id': 2}], 200)       // 200, List
```

### `Http.unfake()` → `void`

Removes the fake from the IoC container and restores the original singleton binding. Call in `tearDown`.

```dart
tearDown(() {
  Http.unfake();
});
```

### Assertion Methods on `FakeNetworkDriver`

| Method | Description |
|:-------|:------------|
| `assertSent(bool Function(MagicRequest) predicate)` | Pass if at least one recorded request matches. |
| `assertNotSent(bool Function(MagicRequest) predicate)` | Pass if no recorded request matches. |
| `assertNothingSent()` | Pass if no requests were recorded at all. |
| `assertSentCount(int expected)` | Pass if exactly `expected` requests were recorded. |
| `preventStrayRequests()` | Throw `StrayRequestException` for unmatched requests. |
| `stub(String pattern, MagicResponse)` | Add a URL pattern stub after construction. |
| `reset()` | Clear recorded requests and stubs without restoring real driver. |
| `recorded` | `List<(MagicRequest, MagicResponse)>` of all request/response pairs. |

```dart
final fake = Http.fake({
  'users/*': Http.response({'id': 1}, 200),
})..preventStrayRequests();

await Http.get('/users/42');

fake.assertSent((r) => r.url.contains('users'));
fake.assertSentCount(1);
fake.assertNotSent((r) => r.method == 'DELETE');
```

## Gotchas

- **Null data on network errors**: `response.data` is `null` for timeouts or connection failures. Always guard before access.
- **422 is not a failure for rendering**: A 422 response is a successful HTTP transaction (validation error). Use `response.isValidationError` to distinguish from network errors.
- **Method spoofing for multipart**: When uploading files for a PUT/PATCH operation in Laravel, use `POST` with `'_method': 'PUT'` in the data map.
- **Timeout configuration**: Default timeout is 10 seconds (10000 ms). Adjust in `config/network.dart` if needed.
- **Response data wrapper**: Always check whether the API wraps data in a `"data"` key. Use `response['data']` or access the root depending on API design.
- **File upload field names**: Ensure field names in the `files` map match the API's expected form field names (e.g., `'photo'`, `'attachment'`).
