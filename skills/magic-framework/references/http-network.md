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

## Gotchas

- **Null data on network errors**: `response.data` is `null` for timeouts or connection failures. Always guard before access.
- **422 is not a failure for rendering**: A 422 response is a successful HTTP transaction (validation error). Use `response.isValidationError` to distinguish from network errors.
- **Method spoofing for multipart**: When uploading files for a PUT/PATCH operation in Laravel, use `POST` with `'_method': 'PUT'` in the data map.
- **Timeout configuration**: Default timeout is 10 seconds (10000 ms). Adjust in `config/network.dart` if needed.
- **Response data wrapper**: Always check whether the API wraps data in a `"data"` key. Use `response['data']` or access the root depending on API design.
- **File upload field names**: Ensure field names in the `files` map match the API's expected form field names (e.g., `'photo'`, `'attachment'`).
