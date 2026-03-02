# HTTP & Network System

Laravel-inspired HTTP client with Dio driver, interceptors, and reactive controller states.

## Network Configuration

Defined in `config/network.dart`. The `NetworkServiceProvider` resolves the `api` driver by default.

```dart
// lib/config/network.dart
Map<String, dynamic> networkConfig = {
    'network': {
        'default': 'api',
        'drivers': {
            'api': {
                'driver': 'dio',
                'base_url': Env.get('API_BASE_URL', 'https://api.example.com/v1'),
                'timeout': 10000, // milliseconds
                'headers': {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                },
            },
        },
    },
};
```

## Http Facade

The `Http` facade provides static access to the underlying `NetworkDriver` (defaulting to `DioNetworkDriver`).

### RESTful Methods

These methods follow Laravel's resource naming conventions and auto-construct URLs.

| Method | Signature | URL Pattern |
|:-------|:----------|:------------|
| `index` | `index(String resource, {Map filters, Map headers})` | `GET /resource` |
| `show` | `show(String resource, String id, {Map headers})` | `GET /resource/id` |
| `store` | `store(String resource, Map data, {Map headers})` | `POST /resource` |
| `update` | `update(String resource, String id, Map data, {Map headers})` | `PUT /resource/id` |
| `destroy` | `destroy(String resource, String id, {Map headers})` | `DELETE /resource/id` |

### Raw HTTP Methods

| Method | Signature | Description |
|:-------|:----------|:------------|
| `get` | `get(String url, {Map query, Map headers})` | Standard GET request |
| `post` | `post(String url, {dynamic data, Map headers})` | Standard POST request |
| `put` | `put(String url, {dynamic data, Map headers})` | Standard PUT request |
| `delete` | `delete(String url, {Map headers})` | Standard DELETE request |
| `upload` | `upload(String url, {required Map data, required Map files, Map headers})` | Multipart file upload |

```dart
// Example: Multipart upload with data
final response = await Http.upload(
    '/teams/${team.id}',
    data: {
        'name': name,
        '_method': 'PUT', // Laravel spoofing for Multipart
    },
    files: {'photo': photo}, // MagicFile instance
);
```

## MagicResponse API

Every `Http` call returns a `MagicResponse`. It mimics Laravel's `Illuminate\Http\Client\Response`.

| Property | Type | Description |
|:---------|:-----|:------------|
| `successful` | `bool` | Status code 200-299 |
| `failed` | `bool` | Status code >= 400 |
| `clientError` | `bool` | Status code 400-499 |
| `serverError` | `bool` | Status code 5xx |
| `unauthorized`| `bool` | Status code 401 |
| `forbidden` | `bool` | Status code 403 |
| `notFound` | `bool` | Status code 404 |
| `isValidationError` | `bool` | Status code 422 |
| `data` | `dynamic` | Raw response body (usually Map or List) |
| `statusCode` | `int` | HTTP status code |
| `operator[]` | `dynamic` | Shorthand for `data[key]` |

### Validation Errors

Magic handles Laravel's standard `{"errors": {"field": ["msg"]}}` format automatically.

| Property | Type | Description |
|:---------|:-----|:------------|
| `errors` | `Map<String, List<String>>` | Map of all validation errors |
| `errorsList` | `List<String>` | Flat list of all error messages |
| `firstError` | `String?` | First available validation message or `message` root key |

```dart
final res = await Http.post('/register', data: data);
if (res.failed) {
    print(res.firstError); // "The email field is required."
}
```

## Interceptors

Implement `MagicNetworkInterceptor` to hook into the request lifecycle.

```dart
class LoggingInterceptor extends MagicNetworkInterceptor {
    @override
    dynamic onRequest(MagicRequest request) {
        print('HTTP Request: ${request.method} ${request.url}');
        return request;
    }

    @override
    dynamic onResponse(MagicResponse response) {
        print('HTTP Response: ${response.statusCode}');
        return response;
    }

    @override
    dynamic onError(MagicError error) {
        print('HTTP Error: ${error.statusCode} ${error.message}');
        return error;
    }
}
```

Register in a `ServiceProvider.boot()`:
```dart
Magic.make<NetworkDriver>('network').addInterceptor(LoggingInterceptor());
```

## ValidatesRequests Mixin

Handles form validation mapping from `MagicResponse` (422) to local UI state.

```dart
class RegisterController extends MagicController with ValidatesRequests {
    Future<void> submit(Map<String, dynamic> data) async {
        final res = await Http.post('/register', data: data);
        if (res.isValidationError) {
            setErrorsFromResponse(res); // Fills validationErrors map
        }
    }
}
```

## Gotchas

- **Laravel Data Wrapper**: API responses often wrap results in a `data` key. Access via `res.data['data']` or `res['data']`.
- **Method Spoofing**: For multipart uploads (photo/file) that should be `PUT` or `PATCH`, Laravel requires `POST` with a `_method` field set to the desired verb.
- **Multipart Content-Type**: `DioNetworkDriver.upload` automatically sets `Content-Type: multipart/form-data`.
- **422 is not "Failed" in renderState**: `renderState` handles `RxStatus.error()`. You must manually call `setError()` if an HTTP request fails if you want the error view to show.
- **MagicFile**: Use `MagicFile` for uploads; it supports `XFile`, paths, and bytes. Always ensure `filename` is provided if the API is strict.
- **`data` is null on errors**: `res.data` can be `null` on network errors (timeout, no connection) — guard before access.
